package com.tvfull.pro

import android.content.Context
import android.net.Uri
import android.view.View
import android.view.ViewGroup
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

/**
 * Small LibVLC wrapper used by Native TV V5.
 *
 * It is intentionally isolated from catalog/panel/UI code. The Activity decides
 * when VLC is used; this class only owns the decoder/network engine and surface.
 */
class LibVlcPlaybackEngine(
    context: Context,
    private val listener: Listener,
) {
    interface Listener {
        fun onOpening()
        fun onBuffering(percent: Float)
        fun onPlaying()
        fun onPaused()
        fun onStopped()
        fun onEndReached()
        fun onError()
        fun onTimeChanged(timeMs: Long)
    }

    private val appContext = context.applicationContext
    private val options = arrayListOf(
        "--http-reconnect",
        "--network-caching=3500",
        "--live-caching=3500",
        "--file-caching=3500",
        "--drop-late-frames",
        "--skip-frames",
    )

    private val libVlc = LibVLC(appContext, options)
    private val mediaPlayer = MediaPlayer(libVlc)

    val videoLayout: VLCVideoLayout = VLCVideoLayout(context).apply {
        visibility = View.GONE
        isFocusable = false
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
    }

    private var viewsAttached = false
    private var released = false
    private var currentUrl: String = ""

    init {
        mediaPlayer.setEventListener { event ->
            when (event.type) {
                MediaPlayer.Event.Opening -> listener.onOpening()
                MediaPlayer.Event.Buffering -> listener.onBuffering(event.buffering)
                MediaPlayer.Event.Playing -> listener.onPlaying()
                MediaPlayer.Event.Paused -> listener.onPaused()
                MediaPlayer.Event.Stopped -> listener.onStopped()
                MediaPlayer.Event.EndReached -> listener.onEndReached()
                MediaPlayer.Event.EncounteredError -> listener.onError()
                MediaPlayer.Event.TimeChanged -> listener.onTimeChanged(event.timeChanged)
                MediaPlayer.Event.Vout -> {
                    // LibVLC occasionally opens the vout before Android has laid
                    // out the surface. Updating here is the same safeguard used by
                    // VLC Android itself for that race.
                    videoLayout.post { runCatching { mediaPlayer.updateVideoSurfaces() } }
                }
            }
        }
    }

    fun play(url: String, resumePositionMs: Long = 0L) {
        if (released) return
        ensureViewsAttached()
        currentUrl = url
        videoLayout.visibility = View.VISIBLE

        mediaPlayer.stop()
        val media = Media(libVlc, Uri.parse(url)).apply {
            setHWDecoderEnabled(true, false)
            addOption(":network-caching=3500")
            addOption(":live-caching=3500")
            addOption(":file-caching=3500")
            addOption(":http-reconnect")
        }
        mediaPlayer.media = media
        media.release()
        mediaPlayer.play()

        if (resumePositionMs > 0L) {
            // Seek after playback starts. Calling setTime before the input becomes
            // seekable is ignored on some servers.
            videoLayout.postDelayed({
                if (!released && currentUrl == url && mediaPlayer.isSeekable) {
                    mediaPlayer.time = resumePositionMs
                }
            }, 900L)
        }
    }

    fun restartSameStream(resumePositionMs: Long = 0L) {
        val url = currentUrl
        if (url.isNotBlank()) play(url, resumePositionMs)
    }

    fun stop(hideSurface: Boolean = true) {
        if (released) return
        runCatching { mediaPlayer.stop() }
        currentUrl = ""
        if (hideSurface) videoLayout.visibility = View.GONE
    }

    fun pause() {
        if (!released) runCatching { mediaPlayer.pause() }
    }

    fun resume() {
        if (!released) runCatching { mediaPlayer.play() }
    }

    fun togglePause() {
        if (released) return
        if (mediaPlayer.isPlaying) pause() else resume()
    }

    fun seekTo(positionMs: Long) {
        if (!released && mediaPlayer.isSeekable) {
            mediaPlayer.time = positionMs.coerceAtLeast(0L)
        }
    }

    fun setScaleMode(mode: Int) {
        if (released) return
        val scale = when (mode) {
            1 -> MediaPlayer.ScaleType.SURFACE_FILL
            2 -> MediaPlayer.ScaleType.SURFACE_FIT_SCREEN
            else -> MediaPlayer.ScaleType.SURFACE_BEST_FIT
        }
        runCatching { mediaPlayer.setVideoScale(scale) }
    }

    fun currentTimeMs(): Long = if (released) 0L else mediaPlayer.time.coerceAtLeast(0L)
    fun durationMs(): Long = if (released) 0L else mediaPlayer.length.coerceAtLeast(0L)
    fun isPlaying(): Boolean = !released && mediaPlayer.isPlaying
    fun isSeekable(): Boolean = !released && mediaPlayer.isSeekable
    fun hasMedia(): Boolean = !released && currentUrl.isNotBlank()

    fun release() {
        if (released) return
        released = true
        runCatching { mediaPlayer.stop() }
        if (viewsAttached) runCatching { mediaPlayer.detachViews() }
        viewsAttached = false
        runCatching { mediaPlayer.release() }
        runCatching { libVlc.release() }
    }

    private fun ensureViewsAttached() {
        if (!viewsAttached) {
            // SurfaceView mode is deliberate: it is the most stable option on
            // old Android TV/TV Box devices and avoids TextureView races.
            mediaPlayer.attachViews(videoLayout, null, true, false)
            viewsAttached = true
        }
    }
}
