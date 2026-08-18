package com.tvfull.pro.tvcore

import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import com.tvfull.pro.ContentSection
import tv.danmaku.ijk.media.player.IjkMediaPlayer
import tv.danmaku.ijk.media.player.IMediaPlayer

/**
 * IJK playback engine kept as an isolated compatibility/test path.
 *
 * The important rule is that the Surface lifecycle is independent from the
 * media lifecycle. Losing a Surface temporarily must detach the video sink,
 * not destroy a healthy stream. When Android recreates the Surface we bind it
 * again immediately. This matches the behavior expected by IJK's setDisplay().
 */
class IjkPlaybackEngine {
    interface Listener {
        fun onOpening(url: String, decoderMode: DecoderMode) {}
        fun onPrepared(durationMs: Long) {}
        fun onAudioStarted() {}
        fun onPlaying() {}
        fun onBuffering(started: Boolean, percent: Int) {}
        fun onVideoSize(width: Int, height: Int) {}
        fun onDecoderFallback(from: DecoderMode, to: DecoderMode, reason: String) {}
        fun onCompleted() {}
        fun onError(code: Int, extra: Int, message: String) {}
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var player: IjkMediaPlayer? = null
    private var holder: SurfaceHolder? = null
    private var registeredHolder: SurfaceHolder? = null
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
    private var playbackGeneration = 0L
    private var blackVideoWatchdog: Runnable? = null
    private var startupWatchdog: Runnable? = null

    private val surfaceCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(surfaceHolder: SurfaceHolder) {
            holder = surfaceHolder
            player?.let { bindDisplay(it, surfaceHolder) }
            maybeStart()
        }

        override fun surfaceChanged(surfaceHolder: SurfaceHolder, format: Int, width: Int, height: Int) {
            holder = surfaceHolder
            player?.let { bindDisplay(it, surfaceHolder) }
            maybeStart()
        }

        override fun surfaceDestroyed(surfaceHolder: SurfaceHolder) {
            if (holder === surfaceHolder) {
                player?.let { bindDisplay(it, null) }
                holder = null
            }
        }
    }

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
        currentUrl = url
        currentSection = section
        currentPolicy = policy
        requestedMode = policy.decoderMode
        autoSoftwareRetried = false
        resumePositionMs = if (isLiveLike()) 0L else startPositionMs.coerceAtLeast(0L)
        targetPlaying = true
        attachSurface(surfaceHolder)

        val firstMode = if (policy.decoderMode == DecoderMode.SOFTWARE) {
            DecoderMode.SOFTWARE
        } else {
            DecoderMode.HARDWARE
        }
        startInternal(firstMode)
    }

    fun attachSurface(surfaceHolder: SurfaceHolder) {
        if (registeredHolder !== surfaceHolder) {
            registeredHolder?.removeCallback(surfaceCallback)
            registeredHolder = surfaceHolder
            surfaceHolder.addCallback(surfaceCallback)
        }
        holder = surfaceHolder
        player?.let { bindDisplay(it, surfaceHolder) }
        maybeStart()
    }

    fun surfaceChanged(surfaceHolder: SurfaceHolder, width: Int, height: Int) {
        attachSurface(surfaceHolder)
    }

    fun detachSurface(surfaceHolder: SurfaceHolder? = null) {
        if (surfaceHolder != null && holder != null && holder !== surfaceHolder) return
        player?.let { bindDisplay(it, null) }
        holder = null
    }

    fun isPlaying(): Boolean = runCatching { player?.isPlaying == true }.getOrDefault(false)
    fun currentPosition(): Long = runCatching { player?.currentPosition ?: 0L }.getOrDefault(0L)
    fun duration(): Long = runCatching { player?.duration ?: 0L }.getOrDefault(0L)
    fun videoWidth(): Int = runCatching { player?.videoWidth ?: 0 }.getOrDefault(0)
    fun videoHeight(): Int = runCatching { player?.videoHeight ?: 0 }.getOrDefault(0)
    fun decoderMode(): DecoderMode = activeMode

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
        // SurfaceView teardown is not a media failure. If Android invalidated the
        // current Surface, keep the stream and wait for surfaceCreated().
        val currentHolder = holder
        if (currentHolder != null && !currentHolder.surface.isValid) {
            detachSurface(currentHolder)
            return
        }

        resumePositionMs = if (isLiveLike()) 0L else currentPosition()
        targetPlaying = false
        playbackGeneration++
        cancelWatchdogs()
        releasePlayer()
    }

    fun release() {
        released = true
        targetPlaying = false
        playbackGeneration++
        cancelWatchdogs()
        releasePlayer()
        registeredHolder?.removeCallback(surfaceCallback)
        registeredHolder = null
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
        cancelWatchdogs()
        releasePlayer()
        prepared = false
        videoRenderingStarted = false
        audioRenderingStarted = false
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
            scheduleStartupWatchdog(generation)
        } catch (e: Exception) {
            handleError(IMediaPlayer.MEDIA_ERROR_UNKNOWN, 0, e.message ?: "No se pudo abrir el stream")
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

        // Do NOT force SDL_FCC_RV32. MediaCodec and FFmpeg must negotiate their
        // native output format; forcing RGB32 was one cause of audio-only playback.
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "packet-buffering", 1L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "max-buffer-size", bufferBytes)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", currentPolicy.frameDrop.toLong())
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
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect_delay_max", 1L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "http-detect-range-support", 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "user_agent", "TV FULL PRO")
        p.setOption(
            IjkMediaPlayer.OPT_CATEGORY_FORMAT,
            "timeout",
            if (liveLike) 6_000_000L else 15_000_000L
        )

        if (!liveLike) {
            p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "enable-accurate-seek", 1L)
        }
    }

    private fun installListeners(p: IjkMediaPlayer, generation: Long) {
        val media: IMediaPlayer = p

        media.setOnPreparedListener(IMediaPlayer.OnPreparedListener { preparedPlayer ->
            if (generation != playbackGeneration) return@OnPreparedListener
            prepared = true
            val seek = resumePositionMs
            if (seek > 0L && !isLiveLike()) {
                runCatching { preparedPlayer.seekTo(seek) }
            }
            listener?.onPrepared(preparedPlayer.duration.coerceAtLeast(0L))
            maybeStart()
        })

        media.setOnInfoListener(IMediaPlayer.OnInfoListener { _, what, _ ->
            if (generation != playbackGeneration) return@OnInfoListener false
            when (what) {
                IMediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START -> {
                    videoRenderingStarted = true
                    cancelStartupWatchdog()
                    cancelBlackVideoWatchdog()
                    listener?.onPlaying()
                }
                IJK_MEDIA_INFO_AUDIO_RENDERING_START -> {
                    audioRenderingStarted = true
                    cancelStartupWatchdog()
                    listener?.onAudioStarted()
                    if (currentSection == ContentSection.RADIO) {
                        listener?.onPlaying()
                    } else {
                        scheduleBlackVideoWatchdog(generation)
                    }
                }
                IMediaPlayer.MEDIA_INFO_BUFFERING_START -> listener?.onBuffering(true, 0)
                IMediaPlayer.MEDIA_INFO_BUFFERING_END -> listener?.onBuffering(false, 100)
            }
            false
        })

        media.setOnBufferingUpdateListener(IMediaPlayer.OnBufferingUpdateListener { _, percent ->
            if (generation == playbackGeneration) {
                listener?.onBuffering(percent < 100, percent.coerceIn(0, 100))
            }
        })

        media.setOnVideoSizeChangedListener(IMediaPlayer.OnVideoSizeChangedListener { _, width, height, _, _ ->
            if (generation != playbackGeneration) return@OnVideoSizeChangedListener
            if (width > 0 && height > 0) {
                // Let SurfaceView keep its Android-managed buffer size. The host UI
                // adjusts layout/aspect ratio without forcing a native RGB surface.
                listener?.onVideoSize(width, height)
                if (audioRenderingStarted && !videoRenderingStarted) {
                    scheduleBlackVideoWatchdog(generation)
                }
            }
        })

        media.setOnCompletionListener(IMediaPlayer.OnCompletionListener {
            if (generation == playbackGeneration) {
                targetPlaying = false
                cancelWatchdogs()
                listener?.onCompleted()
            }
        })

        media.setOnErrorListener(IMediaPlayer.OnErrorListener { _, what, extra ->
            if (generation == playbackGeneration) {
                handleError(what, extra, "IJK error $what/$extra")
            }
            true
        })
    }

    private fun maybeStart() {
        if (released || !prepared || !targetPlaying) return
        val p = player ?: return
        val currentHolder = holder ?: return
        if (!currentHolder.surface.isValid) return
        bindDisplay(p, currentHolder)
        runCatching { if (!p.isPlaying) p.start() }
    }

    private fun scheduleStartupWatchdog(generation: Long) {
        cancelStartupWatchdog()
        if (!isLiveLike()) return
        val watchdog = Runnable {
            if (
                generation == playbackGeneration &&
                !released &&
                !videoRenderingStarted &&
                !audioRenderingStarted
            ) {
                targetPlaying = false
                listener?.onError(IJK_MEDIA_ERROR_TIMED_OUT, IJK_MEDIA_ERROR_TIMED_OUT, "Inicio sin señal")
                playbackGeneration++
                releasePlayer()
            }
        }
        startupWatchdog = watchdog
        mainHandler.postDelayed(watchdog, 6_500L)
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
                    fallbackToSoftware("Audio activo pero MediaCodec no entregó video")
                } else {
                    targetPlaying = false
                    listener?.onError(IMediaPlayer.MEDIA_ERROR_UNKNOWN, 0, "Audio activo sin frames de video")
                }
            }
        }
        blackVideoWatchdog = watchdog
        mainHandler.postDelayed(watchdog, 4_000L)
    }

    private fun handleError(code: Int, extra: Int, message: String) {
        cancelWatchdogs()

        val effective = when (extra) {
            IJK_MEDIA_ERROR_IO,
            IJK_MEDIA_ERROR_MALFORMED,
            IJK_MEDIA_ERROR_UNSUPPORTED,
            IJK_MEDIA_ERROR_TIMED_OUT,
            IJK_MEDIA_ERROR_SERVER_DIED -> extra
            else -> code
        }

        val decoderOrFormatFailure = when (effective) {
            IJK_MEDIA_ERROR_MALFORMED,
            IJK_MEDIA_ERROR_UNSUPPORTED -> true
            IJK_MEDIA_ERROR_IO,
            IJK_MEDIA_ERROR_TIMED_OUT,
            IJK_MEDIA_ERROR_SERVER_DIED -> false
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
        runCatching { mediaPlayer.setDisplay(surfaceHolder) }
    }

    private fun cancelStartupWatchdog() {
        startupWatchdog?.let { mainHandler.removeCallbacks(it) }
        startupWatchdog = null
    }

    private fun cancelBlackVideoWatchdog() {
        blackVideoWatchdog?.let { mainHandler.removeCallbacks(it) }
        blackVideoWatchdog = null
    }

    private fun cancelWatchdogs() {
        cancelStartupWatchdog()
        cancelBlackVideoWatchdog()
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

    private fun isLiveLike(): Boolean =
        currentSection == ContentSection.LIVE || currentSection == ContentSection.RADIO

    companion object {
        private const val IJK_MEDIA_INFO_AUDIO_RENDERING_START = 10002
        private const val IJK_MEDIA_ERROR_SERVER_DIED = 100
        private const val IJK_MEDIA_ERROR_IO = -1004
        private const val IJK_MEDIA_ERROR_MALFORMED = -1007
        private const val IJK_MEDIA_ERROR_UNSUPPORTED = -1010
        private const val IJK_MEDIA_ERROR_TIMED_OUT = -110

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
