package com.tvfull.pro.tvcore

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import com.tvfull.pro.ContentSection

/**
 * Production playback engine for the new TV interface.
 *
 * Goals:
 * - keep the new UI untouched;
 * - start quickly without running with a tiny steady-state buffer;
 * - let Media3 handle decoder fallback;
 * - fail dead live streams quickly;
 * - recover a stream that was already playing without long retry loops.
 */
@UnstableApi
class StablePlaybackEngine(context: Context) {
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

    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private var player: ExoPlayer? = null
    private var holder: SurfaceHolder? = null
    private var listener: Listener? = null
    private var section = ContentSection.LIVE
    private var currentUrl = ""
    private var generation = 0L
    private var firstFrameRendered = false
    private var ready = false
    private var reconnectAttempts = 0
    private var startupWatchdog: Runnable? = null
    private var released = false

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
        released = false
        this.listener = listener
        this.section = section
        this.currentUrl = url
        this.holder = surfaceHolder
        reconnectAttempts = 0
        startInternal(startPositionMs.coerceAtLeast(0L), freshOpen = true)
    }

    fun attachSurface(surfaceHolder: SurfaceHolder) {
        holder = surfaceHolder
        if (surfaceHolder.surface.isValid) {
            runCatching { player?.setVideoSurface(surfaceHolder.surface) }
        }
    }

    fun detachSurface(surfaceHolder: SurfaceHolder? = null) {
        if (surfaceHolder != null && holder !== surfaceHolder) return
        runCatching { player?.clearVideoSurface() }
        holder = null
    }

    fun isPlaying(): Boolean = player?.isPlaying == true
    fun currentPosition(): Long = player?.currentPosition ?: 0L
    fun duration(): Long = player?.duration?.takeIf { it > 0L } ?: 0L
    fun decoderMode(): DecoderMode = DecoderMode.AUTO

    fun pause() {
        player?.pause()
    }

    fun resume() {
        player?.play()
    }

    fun seekTo(positionMs: Long) {
        if (section == ContentSection.LIVE || section == ContentSection.RADIO) return
        player?.seekTo(positionMs.coerceAtLeast(0L))
    }

    fun stop() {
        generation++
        cancelStartupWatchdog()
        firstFrameRendered = false
        ready = false
        reconnectAttempts = 0
        player?.stop()
        player?.clearMediaItems()
    }

    fun release() {
        released = true
        generation++
        cancelStartupWatchdog()
        runCatching { player?.clearVideoSurface() }
        player?.release()
        player = null
        holder = null
        listener = null
        currentUrl = ""
    }

    private fun startInternal(startPositionMs: Long, freshOpen: Boolean) {
        if (released) return
        generation++
        val token = generation
        cancelStartupWatchdog()
        firstFrameRendered = false
        ready = false

        val p = ensurePlayer()
        val currentHolder = holder
        if (currentHolder != null && currentHolder.surface.isValid) {
            p.setVideoSurface(currentHolder.surface)
        }

        listener?.onOpening(currentUrl, DecoderMode.AUTO)
        p.stop()
        p.clearMediaItems()
        p.setMediaItem(MediaItem.fromUri(currentUrl))
        p.prepare()
        if (startPositionMs > 0L && section != ContentSection.LIVE && section != ContentSection.RADIO) {
            p.seekTo(startPositionMs)
        }
        p.playWhenReady = true

        if (section == ContentSection.LIVE || section == ContentSection.RADIO) {
            scheduleStartupWatchdog(token)
        }
    }

    private fun ensurePlayer(): ExoPlayer {
        player?.let { return it }

        // Start fast, but keep a much larger continuity buffer than the previous
        // 3-15 second configuration. This is the key difference: startup and
        // steady-state resilience are independent knobs.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                12_000, // maintain at least ~12s when the network allows it
                45_000, // grow up to ~45s to absorb Wi-Fi/ISP jitter
                1_200,  // fast first start / seek
                3_500   // after a real depletion, refill more before resuming
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val renderers = DefaultRenderersFactory(appContext)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)

        val http = DefaultHttpDataSource.Factory()
            .setUserAgent("Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 Chrome/120 Safari/537.36")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(5_000)
            .setReadTimeoutMs(20_000)

        val p = ExoPlayer.Builder(appContext, renderers)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(DefaultMediaSourceFactory(http))
            .build()

        p.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                val token = generation
                when (state) {
                    Player.STATE_BUFFERING -> {
                        listener?.onBuffering(true, p.bufferedPercentage.coerceIn(0, 100))
                    }
                    Player.STATE_READY -> {
                        ready = true
                        listener?.onPrepared(duration())
                        listener?.onBuffering(false, p.bufferedPercentage.coerceIn(0, 100))
                        if (section == ContentSection.RADIO) {
                            cancelStartupWatchdog()
                            listener?.onAudioStarted()
                            listener?.onPlaying()
                        }
                    }
                    Player.STATE_ENDED -> {
                        cancelStartupWatchdog()
                        listener?.onCompleted()
                    }
                    else -> Unit
                }
            }

            override fun onRenderedFirstFrame() {
                firstFrameRendered = true
                reconnectAttempts = 0
                cancelStartupWatchdog()
                listener?.onPlaying()
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    listener?.onVideoSize(videoSize.width, videoSize.height)
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                cancelStartupWatchdog()
                if (released) return

                // Initial failure: report it immediately. Recovery is reserved for a
                // stream that had already produced video and then failed.
                if (!firstFrameRendered || section == ContentSection.MOVIES || section == ContentSection.SERIES) {
                    listener?.onError(error.errorCode, 0, error.message ?: "No se pudo reproducir")
                    return
                }

                if (reconnectAttempts >= 2) {
                    listener?.onError(error.errorCode, 0, error.message ?: "Se perdió la señal")
                    return
                }

                reconnectAttempts++
                val position = if (section == ContentSection.LIVE || section == ContentSection.RADIO) 0L else currentPosition()
                val delay = if (reconnectAttempts == 1) 700L else 1_500L
                handler.postDelayed({
                    if (!released && tokenIsCurrent(generation)) {
                        startInternal(position, freshOpen = false)
                    }
                }, delay)
            }
        })

        player = p
        return p
    }

    private fun scheduleStartupWatchdog(token: Long) {
        cancelStartupWatchdog()
        val task = Runnable {
            if (token != generation || released) return@Runnable
            if (section == ContentSection.RADIO && ready) return@Runnable
            if (!firstFrameRendered) {
                player?.stop()
                listener?.onError(PlaybackException.ERROR_CODE_TIMEOUT, 0, "Inicio sin señal")
            }
        }
        startupWatchdog = task
        handler.postDelayed(task, 6_000L)
    }

    private fun cancelStartupWatchdog() {
        startupWatchdog?.let { handler.removeCallbacks(it) }
        startupWatchdog = null
    }

    private fun tokenIsCurrent(token: Long): Boolean = token == generation
}
