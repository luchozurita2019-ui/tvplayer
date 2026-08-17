package com.tvfull.pro.tvcore

import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import com.tvfull.pro.ContentSection
import tv.danmaku.ijk.media.player.IjkMediaPlayer
import tv.danmaku.ijk.media.player.IMediaPlayer

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
    private var listener: Listener? = null
    private var currentUrl: String = ""
    private var currentSection: ContentSection = ContentSection.LIVE
    private var currentPolicy: PlaybackPolicy = PlaybackPolicy()
    private var requestedMode: DecoderMode = DecoderMode.AUTO
    private var activeMode: DecoderMode = DecoderMode.HARDWARE
    private var autoSoftwareRetried = false
    private var resumePositionMs = 0L
    private var released = false
    private var videoRenderingStarted = false
    private var audioRenderingStarted = false
    private var playbackGeneration = 0L

    fun open(
        url: String,
        surfaceHolder: SurfaceHolder,
        section: ContentSection,
        startPositionMs: Long = 0L,
        policy: PlaybackPolicy = PlaybackPolicy(),
        listener: Listener? = null
    ) {
        require(url.startsWith("http://", true) || url.startsWith("https://", true)) { "URL de reproducción inválida" }
        ensureLibraries()
        released = false
        @Suppress("DEPRECATION")
        runCatching { surfaceHolder.setType(SurfaceHolder.SURFACE_TYPE_NORMAL) }
        this.holder = surfaceHolder
        this.listener = listener
        this.currentUrl = url
        this.currentSection = section
        this.currentPolicy = policy
        this.requestedMode = policy.decoderMode
        this.autoSoftwareRetried = false
        this.resumePositionMs = if (section == ContentSection.LIVE || section == ContentSection.RADIO) 0L else startPositionMs.coerceAtLeast(0L)
        val firstMode = if (policy.decoderMode == DecoderMode.SOFTWARE) DecoderMode.SOFTWARE else DecoderMode.HARDWARE
        startInternal(firstMode)
    }

    fun isPlaying(): Boolean = runCatching { player?.isPlaying == true }.getOrDefault(false)
    fun currentPosition(): Long = runCatching { player?.currentPosition ?: 0L }.getOrDefault(0L)
    fun duration(): Long = runCatching { player?.duration ?: 0L }.getOrDefault(0L)
    fun videoWidth(): Int = runCatching { player?.videoWidth ?: 0 }.getOrDefault(0)
    fun videoHeight(): Int = runCatching { player?.videoHeight ?: 0 }.getOrDefault(0)
    fun decoderMode(): DecoderMode = activeMode

    fun pause() {
        runCatching { player?.pause() }
    }

    fun resume() {
        runCatching { player?.start() }
    }

    fun seekTo(positionMs: Long) {
        if (currentSection == ContentSection.LIVE || currentSection == ContentSection.RADIO) return
        runCatching { player?.seekTo(positionMs.coerceAtLeast(0L)) }
    }

    fun stop() {
        resumePositionMs = if (currentSection == ContentSection.LIVE || currentSection == ContentSection.RADIO) 0L else currentPosition()
        playbackGeneration++
        mainHandler.removeCallbacksAndMessages(null)
        releasePlayer()
    }

    fun release() {
        released = true
        playbackGeneration++
        mainHandler.removeCallbacksAndMessages(null)
        releasePlayer()
        holder = null
        listener = null
        currentUrl = ""
    }

    private fun startInternal(mode: DecoderMode) {
        if (released) return
        val surface = holder ?: error("SurfaceHolder no disponible")
        activeMode = mode
        playbackGeneration++
        val generation = playbackGeneration
        videoRenderingStarted = false
        audioRenderingStarted = false
        releasePlayer()

        val p = IjkMediaPlayer()
        player = p
        configure(p, mode)
        p.setDisplay(surface)
        p.setAudioStreamType(AudioManager.STREAM_MUSIC)
        p.setScreenOnWhilePlaying(true)
        installListeners(p, generation)
        listener?.onOpening(currentUrl, mode)

        try {
            p.setDataSource(currentUrl)
            p.prepareAsync()
        } catch (e: Exception) {
            handleError(IMediaPlayer.MEDIA_ERROR_UNKNOWN, 0, e.message ?: "No se pudo abrir el stream")
        }
    }

    private fun configure(p: IjkMediaPlayer, mode: DecoderMode) {
        val hardware = mode == DecoderMode.HARDWARE
        val liveLike = currentSection == ContentSection.LIVE || currentSection == ContentSection.RADIO
        val reconnect = currentPolicy.reconnectEnabled
        val bufferBytes = (
            if (liveLike) currentPolicy.liveBufferBytes else currentPolicy.vodBufferBytes
        ).coerceIn(4L * 1024L * 1024L, 128L * 1024L * 1024L)

        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", if (hardware) 1L else 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-hevc", if (hardware) 1L else 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-auto-rotate", if (hardware) 1L else 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-handle-resolution-change", if (hardware) 1L else 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "opensles", 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "overlay-format", IjkMediaPlayer.SDL_FCC_RV32)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "packet-buffering", 1L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "max-buffer-size", bufferBytes)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", currentPolicy.frameDrop.toLong())
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_CODEC, "skip_loop_filter", 48L)

        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect", if (reconnect) 1L else 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect_streamed", if (reconnect && liveLike) 1L else 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect_at_eof", if (reconnect && liveLike) 1L else 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect_delay_max", 5L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "http-detect-range-support", 0L)
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "user_agent", "TV FULL PRO")
        p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "timeout", 15_000_000L)

        if (!liveLike) {
            p.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "enable-accurate-seek", 1L)
        }
    }

    private fun installListeners(p: IjkMediaPlayer, generation: Long) {
        p.setOnPreparedListener(IMediaPlayer.OnPreparedListener { media ->
            if (generation != playbackGeneration) return@OnPreparedListener
            val seek = resumePositionMs
            if (seek > 0L && currentSection != ContentSection.LIVE && currentSection != ContentSection.RADIO) {
                runCatching { media.seekTo(seek) }
            }
            listener?.onPrepared(media.duration.coerceAtLeast(0L))
            runCatching { media.start() }
        })

        p.setOnInfoListener(IMediaPlayer.OnInfoListener { _, what, _ ->
            if (generation != playbackGeneration) return@OnInfoListener false
            when (what) {
                IMediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START -> {
                    videoRenderingStarted = true
                    listener?.onPlaying()
                }
                IJK_MEDIA_INFO_AUDIO_RENDERING_START -> {
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
            }
            false
        })

        p.setOnBufferingUpdateListener(IMediaPlayer.OnBufferingUpdateListener { _, percent ->
            if (generation == playbackGeneration) listener?.onBuffering(percent < 100, percent.coerceIn(0, 100))
        })

        p.setOnVideoSizeChangedListener(IMediaPlayer.OnVideoSizeChangedListener { _, width, height, _, _ ->
            if (generation != playbackGeneration) return@OnVideoSizeChangedListener
            if (width > 0 && height > 0) {
                runCatching { holder?.setFixedSize(width, height) }
                listener?.onVideoSize(width, height)
                if (audioRenderingStarted && !videoRenderingStarted) scheduleBlackVideoWatchdog(generation)
            }
        })

        p.setOnCompletionListener(IMediaPlayer.OnCompletionListener {
            if (generation == playbackGeneration) listener?.onCompleted()
        })

        p.setOnErrorListener(IMediaPlayer.OnErrorListener { _, what, extra ->
            if (generation == playbackGeneration) handleError(what, extra, "IJK error $what/$extra")
            true
        })
    }

    private fun scheduleBlackVideoWatchdog(generation: Long) {
        if (currentSection == ContentSection.RADIO) return
        mainHandler.postDelayed({
            if (
                generation == playbackGeneration &&
                !released &&
                audioRenderingStarted &&
                !videoRenderingStarted
            ) {
                if (requestedMode == DecoderMode.AUTO && activeMode == DecoderMode.HARDWARE && !autoSoftwareRetried) {
                    fallbackToSoftware("Audio activo pero MediaCodec no renderizó video")
                } else {
                    listener?.onError(IMediaPlayer.MEDIA_ERROR_UNKNOWN, 0, "Audio activo sin frames de video")
                }
            }
        }, 5_000L)
    }

    private fun handleError(code: Int, extra: Int, message: String) {
        val mayBeDecoderOrFormat = when (code) {
            IMediaPlayer.MEDIA_ERROR_UNKNOWN,
            IJK_MEDIA_ERROR_MALFORMED,
            IJK_MEDIA_ERROR_UNSUPPORTED -> true
            IJK_MEDIA_ERROR_IO,
            IJK_MEDIA_ERROR_TIMED_OUT,
            IJK_MEDIA_ERROR_SERVER_DIED -> false
            else -> false
        }

        if (
            !released &&
            mayBeDecoderOrFormat &&
            requestedMode == DecoderMode.AUTO &&
            activeMode == DecoderMode.HARDWARE &&
            !autoSoftwareRetried
        ) {
            fallbackToSoftware(message)
            return
        }
        listener?.onError(code, extra, message)
    }

    private fun fallbackToSoftware(reason: String) {
        if (released || autoSoftwareRetried) return
        autoSoftwareRetried = true
        resumePositionMs = if (currentSection == ContentSection.LIVE || currentSection == ContentSection.RADIO) 0L else currentPosition()
        listener?.onDecoderFallback(DecoderMode.HARDWARE, DecoderMode.SOFTWARE, reason)
        startInternal(DecoderMode.SOFTWARE)
    }

    private fun releasePlayer() {
        val p = player ?: return
        player = null
        runCatching { p.setDisplay(null) }
        runCatching { p.stop() }
        runCatching { p.reset() }
        runCatching { p.release() }
    }

    companion object {
        // Values copied from the official IJKPlayer k0.8.8 IMediaPlayer API.
        // Local constants avoid Kotlin/Javac symbol-resolution differences while
        // keeping the exact upstream native event/error values.
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
