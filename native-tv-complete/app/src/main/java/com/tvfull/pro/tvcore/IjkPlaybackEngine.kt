package com.tvfull.pro.tvcore

import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import com.tvfull.pro.ContentSection
import tv.danmaku.ijk.media.player.IjkMediaPlayer
import tv.danmaku.ijk.media.player.IMediaPlayer
import tv.danmaku.ijk.media.player.ISurfaceTextureHolder

/**
 * IJK/FFmpeg playback core for Android TV.
 *
 * The Surface lifecycle intentionally follows the upstream IJK VideoView model:
 * - bind the player to an existing Surface before prepare;
 * - apply the decoded video size to SurfaceHolder.setFixedSize();
 * - for SurfaceView, wait for surfaceChanged() to confirm the fixed buffer size
 *   before starting playback;
 * - detach the display on surface destruction without destroying the player.
 *
 * This avoids the classic IJK symptom where audio starts while the video sink is
 * not ready and the TV remains black.
 */
class IjkPlaybackEngine {
    interface Listener {
        fun onOpening(url: String, decoderMode: DecoderMode) {}
        fun onPrepared(durationMs: Long) {}
        fun onAudioStarted() {}
        fun onPlaying() {}
        fun onBuffering(started: Boolean, percent: Int) {}
        fun onVideoSize(width: Int, height: Int, sarNum: Int, sarDen: Int) {}
        fun onDecoderFallback(from: DecoderMode, to: DecoderMode, reason: String) {}
        fun onCompleted() {}
        fun onError(code: Int, extra: Int, message: String) {}
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var player: IjkMediaPlayer? = null
    private var holder: SurfaceHolder? = null
    private var listener: Listener? = null

    private var currentUrl = ""
    private var currentSection = ContentSection.LIVE
    private var currentPolicy = PlaybackPolicy()
    private var requestedMode = DecoderMode.AUTO
    private var activeMode = DecoderMode.HARDWARE
    private var autoSoftwareRetried = false
    private var resumePositionMs = 0L

    private var released = false
    private var prepared = false
    private var targetPlaying = false
    private var videoRenderingStarted = false
    private var audioRenderingStarted = false
    private var videoWidth = 0
    private var videoHeight = 0
    private var videoSarNum = 1
    private var videoSarDen = 1
    private var surfaceWidth = 0
    private var surfaceHeight = 0
    private var fixedWidth = 0
    private var fixedHeight = 0
    private var playbackGeneration = 0L
    private var blackVideoWatchdog: Runnable? = null

    fun open(
        url: String,
        surfaceHolder: SurfaceHolder,
        section: ContentSection,
        startPositionMs: Long = 0L,
        policy: PlaybackPolicy = PlaybackPolicy(),
        listener: Listener? = null
    ) {
        require(url.startsWith("http://", true) || url.startsWith("https://", true)) {
            "URL de reproducción inválida"
        }
        ensureLibraries()
        released = false
        this.listener = listener
        this.currentUrl = url
        this.currentSection = section
        this.currentPolicy = policy
        this.requestedMode = policy.decoderMode
        this.autoSoftwareRetried = false
        this.resumePositionMs = if (isLiveLike()) 0L else startPositionMs.coerceAtLeast(0L)
        this.targetPlaying = true
        attachSurface(surfaceHolder)

        val firstMode = if (policy.decoderMode == DecoderMode.SOFTWARE) {
            DecoderMode.SOFTWARE
        } else {
            DecoderMode.HARDWARE
        }
        startInternal(firstMode)
    }

    /** Rebind an existing player after a SurfaceView recreation. */
    fun attachSurface(surfaceHolder: SurfaceHolder) {
        holder = surfaceHolder
        val frame = surfaceHolder.surfaceFrame
        surfaceWidth = frame.width().coerceAtLeast(0)
        surfaceHeight = frame.height().coerceAtLeast(0)
        player?.let { bindDisplay(it, surfaceHolder) }
        maybeStart()
    }

    /** Called from SurfaceHolder.Callback.surfaceChanged(). */
    fun surfaceChanged(surfaceHolder: SurfaceHolder, width: Int, height: Int) {
        holder = surfaceHolder
        surfaceWidth = width.coerceAtLeast(0)
        surfaceHeight = height.coerceAtLeast(0)
        player?.let { bindDisplay(it, surfaceHolder) }
        maybeStart()
    }

    /**
     * A destroyed Surface is not a media error. Detach only the video sink so a
     * transient resize/fullscreen/lifecycle change cannot kill a healthy stream.
     */
    fun detachSurface(surfaceHolder: SurfaceHolder? = null) {
        if (surfaceHolder != null && holder != null && surfaceHolder !== holder) return
        player?.let { bindDisplay(it, null) }
        holder = null
        surfaceWidth = 0
        surfaceHeight = 0
    }

    fun isPlaying(): Boolean = runCatching { player?.isPlaying == true }.getOrDefault(false)
    fun currentPosition(): Long = runCatching { player?.currentPosition ?: 0L }.getOrDefault(0L)
    fun duration(): Long = runCatching { player?.duration ?: 0L }.getOrDefault(0L)
    fun videoWidth(): Int = videoWidth
    fun videoHeight(): Int = videoHeight
    fun decoderMode(): DecoderMode = activeMode
    fun hasVideoStarted(): Boolean = videoRenderingStarted
    fun hasAudioStarted(): Boolean = audioRenderingStarted

    fun pause() {
        targetPlaying = false
        runCatching { player?.pause() }
    }

    fun resume() {
        targetPlaying = true
        maybeStart()
    }

    fun seekTo(positionMs: Long) {
        if (isLiveLike()) return
        runCatching { player?.seekTo(positionMs.coerceAtLeast(0L)) }
    }

    fun stop() {
        resumePositionMs = if (isLiveLike()) 0L else currentPosition()
        targetPlaying = false
        playbackGeneration++
        cancelBlackVideoWatchdog()
        releasePlayer()
    }

    fun release() {
        released = true
        targetPlaying = false
        playbackGeneration++
        cancelBlackVideoWatchdog()
        releasePlayer()
        holder = null
        listener = null
        currentUrl = ""
    }

    private fun startInternal(mode: DecoderMode) {
        if (released) return
        val currentHolder = holder ?: error("SurfaceHolder no disponible")

        activeMode = mode
        playbackGeneration++
        val generation = playbackGeneration
        cancelBlackVideoWatchdog()
        releasePlayer()
        resetPlaybackState(keepSurface = true)
        targetPlaying = true

        val p = IjkMediaPlayer()
        player = p
        configure(p, mode)
        installListeners(p, generation)
        bindDisplay(p, currentHolder)
        p.setAudioStreamType(AudioManager.STREAM_MUSIC)
        p.setScreenOnWhilePlaying(true)
        listener?.onOpening(currentUrl, mode)

        try {
            p.setDataSource(currentUrl)
            p.prepareAsync()
        } catch (e: Exception) {
            handleError(
                IMediaPlayer.MEDIA_ERROR_UNKNOWN,
                0,
                e.message ?: "No se pudo abrir el stream"
            )
        }
    }

    private fun configure(p: IjkMediaPlayer, mode: DecoderMode) {
        val hardware = mode == DecoderMode.HARDWARE
        val liveLike = isLiveLike()
        val reconnect = currentPolicy.reconnectEnabled
        val bufferBytes = (
            if (liveLike) currentPolicy.liveBufferBytes else currentPolicy.vodBufferBytes
        ).coerceIn(4L * 1024L * 1024L, 128L * 1024L * 1024L)

        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", if (hardware) 1L else 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-hevc", if (hardware) 1L else 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-auto-rotate", if (hardware) 1L else 0L)
        p.setOption(
            IjkMediaPlayer.OPT_CATEGORY_PLAYER,
            "mediacodec-handle-resolution-change",
            if (hardware) 1L else 0L
        )
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "opensles", 0L)

        // Keep IJK's pixel-format selection on Auto. Forcing RGB32 globally is
        // unnecessary for MediaCodec and makes software decoding more expensive.
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "packet-buffering", 1L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "max-buffer-size", bufferBytes)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", currentPolicy.frameDrop.toLong())

        // Playback start is controlled by the Surface lifecycle below. This is
        // intentionally disabled to avoid starting audio before the Surface buffer
        // has been resized for the decoded video.
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 0L)

        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect", if (reconnect) 1L else 0L)
        p.setOption(
            IjkMediaPlayer.OPT_CATEGORY_FORMAT,
            "reconnect_streamed",
            if (reconnect && liveLike) 1L else 0L
        )
        p.setOption(
            IjkMediaPlayer.OPT_CATEGORY_FORMAT,
            "reconnect_at_eof",
            if (reconnect && liveLike) 1L else 0L
        )
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect_delay_max", 5L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "http-detect-range-support", 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "user_agent", "TVFULLPlayer/1.0")
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "timeout", 15_000_000L)

        if (!liveLike) {
            p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "enable-accurate-seek", 1L)
        }
    }

    private fun installListeners(p: IjkMediaPlayer, generation: Long) {
        p.setOnPreparedListener(IMediaPlayer.OnPreparedListener { media ->
            if (generation != playbackGeneration) return@OnPreparedListener
            prepared = true

            updateVideoGeometry(
                media.videoWidth,
                media.videoHeight,
                media.videoSarNum,
                media.videoSarDen
            )

            val seek = resumePositionMs
            if (seek > 0L && !isLiveLike()) {
                runCatching { media.seekTo(seek) }
            }

            listener?.onPrepared(media.duration.coerceAtLeast(0L))
            maybeStart()
        })

        p.setOnInfoListener(IMediaPlayer.OnInfoListener { _, what, extra ->
            if (generation != playbackGeneration) return@OnInfoListener false
            when (what) {
                IMediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START -> {
                    videoRenderingStarted = true
                    cancelBlackVideoWatchdog()
                    listener?.onPlaying()
                }

                IMediaPlayer.MEDIA_INFO_AUDIO_RENDERING_START -> {
                    audioRenderingStarted = true
                    listener?.onAudioStarted()
                    if (currentSection == ContentSection.RADIO) {
                        listener?.onPlaying()
                    } else {
                        scheduleBlackVideoWatchdog(generation)
                    }
                }

                IMediaPlayer.MEDIA_INFO_BUFFERING_START -> listener?.onBuffering(true, 0)
                IMediaPlayer.MEDIA_INFO_BUFFERING_END -> listener?.onBuffering(false, 100)
                IMediaPlayer.MEDIA_INFO_VIDEO_ROTATION_CHANGED -> {
                    // SurfaceView itself cannot rotate. MediaCodec auto-rotate is
                    // enabled above, matching the reference player's hardware path.
                    @Suppress("UNUSED_VARIABLE") val rotation = extra
                }
            }
            false
        })

        p.setOnBufferingUpdateListener(IMediaPlayer.OnBufferingUpdateListener { _, percent ->
            if (generation == playbackGeneration) {
                listener?.onBuffering(percent < 100, percent.coerceIn(0, 100))
            }
        })

        p.setOnVideoSizeChangedListener(
            IMediaPlayer.OnVideoSizeChangedListener { media, width, height, sarNum, sarDen ->
                if (generation != playbackGeneration) return@OnVideoSizeChangedListener
                val actualWidth = media.videoWidth.takeIf { it > 0 } ?: width
                val actualHeight = media.videoHeight.takeIf { it > 0 } ?: height
                val actualSarNum = media.videoSarNum.takeIf { it > 0 } ?: sarNum
                val actualSarDen = media.videoSarDen.takeIf { it > 0 } ?: sarDen
                updateVideoGeometry(actualWidth, actualHeight, actualSarNum, actualSarDen)
                maybeStart()
            }
        )

        p.setOnCompletionListener(IMediaPlayer.OnCompletionListener {
            if (generation != playbackGeneration) return@OnCompletionListener
            targetPlaying = false
            cancelBlackVideoWatchdog()
            listener?.onCompleted()
        })

        p.setOnErrorListener(IMediaPlayer.OnErrorListener { _, what, extra ->
            if (generation == playbackGeneration) {
                handleError(what, extra, "IJK error $what/$extra")
            }
            true
        })
    }

    private fun updateVideoGeometry(width: Int, height: Int, sarNum: Int, sarDen: Int) {
        if (width <= 0 || height <= 0) return
        videoWidth = width
        videoHeight = height
        videoSarNum = sarNum.takeIf { it > 0 } ?: 1
        videoSarDen = sarDen.takeIf { it > 0 } ?: 1

        val currentHolder = holder
        if (currentHolder != null && (fixedWidth != width || fixedHeight != height)) {
            fixedWidth = width
            fixedHeight = height
            runCatching { currentHolder.setFixedSize(width, height) }
        }
        listener?.onVideoSize(width, height, videoSarNum, videoSarDen)
    }

    /**
     * SurfaceView uses a dedicated buffer size. IJK's reference VideoView waits
     * for surfaceChanged() to confirm that buffer size before start().
     */
    private fun maybeStart() {
        if (released || !prepared || !targetPlaying) return
        val p = player ?: return
        if (holder == null) return

        val hasVideoSize = videoWidth > 0 && videoHeight > 0
        val surfaceMatchesVideo = !hasVideoSize ||
            (surfaceWidth == videoWidth && surfaceHeight == videoHeight)
        if (!surfaceMatchesVideo) return

        runCatching {
            if (!p.isPlaying) p.start()
        }
    }

    private fun scheduleBlackVideoWatchdog(generation: Long) {
        if (currentSection == ContentSection.RADIO || videoRenderingStarted) return
        cancelBlackVideoWatchdog()
        val watchdog = Runnable {
            if (
                generation == playbackGeneration &&
                !released &&
                audioRenderingStarted &&
                !videoRenderingStarted
            ) {
                if (
                    requestedMode == DecoderMode.AUTO &&
                    activeMode == DecoderMode.HARDWARE &&
                    !autoSoftwareRetried
                ) {
                    fallbackToSoftware("MediaCodec entregó audio pero ningún frame de video")
                } else {
                    targetPlaying = false
                    listener?.onError(
                        IMediaPlayer.MEDIA_ERROR_UNKNOWN,
                        0,
                        "Audio activo sin frames de video"
                    )
                }
            }
        }
        blackVideoWatchdog = watchdog
        mainHandler.postDelayed(watchdog, BLACK_VIDEO_TIMEOUT_MS)
    }

    private fun cancelBlackVideoWatchdog() {
        blackVideoWatchdog?.let { mainHandler.removeCallbacks(it) }
        blackVideoWatchdog = null
    }

    private fun handleError(code: Int, extra: Int, message: String) {
        cancelBlackVideoWatchdog()

        // IJK commonly reports MEDIA_ERROR_UNKNOWN (1) in `what` and the useful
        // network/format reason in `extra`. Classify the effective error instead of
        // treating every what=1 as a decoder failure.
        val effective = when (extra) {
            IMediaPlayer.MEDIA_ERROR_IO,
            IMediaPlayer.MEDIA_ERROR_MALFORMED,
            IMediaPlayer.MEDIA_ERROR_UNSUPPORTED,
            IMediaPlayer.MEDIA_ERROR_TIMED_OUT,
            IMediaPlayer.MEDIA_ERROR_SERVER_DIED -> extra
            else -> code
        }

        val decoderOrFormatFailure = when (effective) {
            IMediaPlayer.MEDIA_ERROR_MALFORMED,
            IMediaPlayer.MEDIA_ERROR_UNSUPPORTED -> true
            IMediaPlayer.MEDIA_ERROR_IO,
            IMediaPlayer.MEDIA_ERROR_TIMED_OUT,
            IMediaPlayer.MEDIA_ERROR_SERVER_DIED -> false
            IMediaPlayer.MEDIA_ERROR_UNKNOWN -> extra == 0
            else -> false
        }

        if (
            !released &&
            decoderOrFormatFailure &&
            requestedMode == DecoderMode.AUTO &&
            activeMode == DecoderMode.HARDWARE &&
            !autoSoftwareRetried
        ) {
            fallbackToSoftware(message)
            return
        }

        targetPlaying = false
        listener?.onError(code, extra, message)
    }

    private fun fallbackToSoftware(reason: String) {
        if (released || autoSoftwareRetried) return
        autoSoftwareRetried = true
        resumePositionMs = if (isLiveLike()) 0L else currentPosition()
        listener?.onDecoderFallback(DecoderMode.HARDWARE, DecoderMode.SOFTWARE, reason)
        startInternal(DecoderMode.SOFTWARE)
    }

    private fun bindDisplay(mediaPlayer: IMediaPlayer, surfaceHolder: SurfaceHolder?) {
        if (surfaceHolder == null) {
            mediaPlayer.setDisplay(null)
            return
        }
        if (mediaPlayer is ISurfaceTextureHolder) {
            mediaPlayer.setSurfaceTexture(null)
        }
        mediaPlayer.setDisplay(surfaceHolder)
    }

    private fun releasePlayer() {
        val p = player ?: return
        player = null
        runCatching { p.setDisplay(null) }
        runCatching { p.stop() }
        runCatching { p.reset() }
        runCatching { p.release() }
        prepared = false
        videoRenderingStarted = false
        audioRenderingStarted = false
    }

    private fun resetPlaybackState(keepSurface: Boolean) {
        prepared = false
        videoRenderingStarted = false
        audioRenderingStarted = false
        videoWidth = 0
        videoHeight = 0
        videoSarNum = 1
        videoSarDen = 1
        fixedWidth = 0
        fixedHeight = 0
        if (!keepSurface) {
            surfaceWidth = 0
            surfaceHeight = 0
        } else {
            holder?.surfaceFrame?.let { frame ->
                surfaceWidth = frame.width().coerceAtLeast(0)
                surfaceHeight = frame.height().coerceAtLeast(0)
            }
        }
    }

    private fun isLiveLike(): Boolean =
        currentSection == ContentSection.LIVE || currentSection == ContentSection.RADIO

    companion object {
        private const val BLACK_VIDEO_TIMEOUT_MS = 6_000L

        @Volatile private var librariesLoaded = false

        @Synchronized
        private fun ensureLibraries() {
            if (librariesLoaded) return
            IjkMediaPlayer.loadLibrariesOnce(null)
            IjkMediaPlayer.native_profileBegin("libijkplayer.so")
            librariesLoaded = true
        }
    }
}
