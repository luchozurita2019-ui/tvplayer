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
 * Isolated LibVLC playback engine for Native TV V5.
 * Catalog, provisioning, payment and navigation stay outside this class.
 */
class LibVlcPlaybackEngine(
    context: Context,
    private val listener: Listener,
) {
    data class Track(val id: Int, val name: String)

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
        "--network-caching=4500",
        "--live-caching=4500",
        "--file-caching=8000",
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
                    // Surface-size race workaround used by VLC Android itself.
                    videoLayout.post { runCatching { mediaPlayer.updateVideoSurfaces() } }
                }
            }
        }
    }

    fun play(url: String, resumePositionMs: Long = 0L, live: Boolean = false) {
        if (released) return
        ensureViewsAttached()
        currentUrl = url
        videoLayout.visibility = View.VISIBLE

        if (mediaPlayer.hasMedia()) runCatching { mediaPlayer.stop() }
        val media = Media(libVlc, Uri.parse(url)).apply {
            setHWDecoderEnabled(true, false)
            addOption(if (live) ":network-caching=4500" else ":network-caching=8000")
            addOption(if (live) ":live-caching=4500" else ":file-caching=8000")
            addOption(":http-reconnect")
        }
        mediaPlayer.setMedia(media)
        media.release()
        mediaPlayer.play()

        if (resumePositionMs > 0L) {
            videoLayout.postDelayed({
                if (!released && currentUrl == url && mediaPlayer.isSeekable) {
                    mediaPlayer.time = resumePositionMs
                }
            }, 1_000L)
        }
    }

    fun stop(hideSurface: Boolean = true) {
        if (released) return
        if (mediaPlayer.hasMedia()) runCatching { mediaPlayer.stop() }
        currentUrl = ""
        if (hideSurface) videoLayout.visibility = View.GONE
    }

    fun pause() {
        if (!released && mediaPlayer.hasMedia()) runCatching { mediaPlayer.pause() }
    }

    fun resume() {
        if (!released && mediaPlayer.hasMedia()) runCatching { mediaPlayer.play() }
    }

    fun togglePause() {
        if (released || !mediaPlayer.hasMedia()) return
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

    fun audioTracks(): List<Track> = if (released) emptyList() else
        mediaPlayer.audioTracks?.map { Track(it.id, it.name.orEmpty()) }.orEmpty()

    fun subtitleTracks(): List<Track> = if (released) emptyList() else
        mediaPlayer.spuTracks?.map { Track(it.id, it.name.orEmpty()) }.orEmpty()

    fun selectedAudioTrack(): Int = if (released) -1 else mediaPlayer.audioTrack
    fun selectedSubtitleTrack(): Int = if (released) -1 else mediaPlayer.spuTrack
    fun selectAudioTrack(id: Int): Boolean = !released && mediaPlayer.setAudioTrack(id)
    fun selectSubtitleTrack(id: Int): Boolean = !released && mediaPlayer.setSpuTrack(id)

    fun videoResolution(): Pair<Int, Int>? {
        if (released) return null
        val track = runCatching { mediaPlayer.currentVideoTrack }.getOrNull() ?: return null
        val width = track.width
        val height = track.height
        return if (width > 0 && height > 0) width to height else null
    }

    fun currentTimeMs(): Long = if (released) 0L else mediaPlayer.time.coerceAtLeast(0L)
    fun durationMs(): Long = if (released) 0L else mediaPlayer.length.coerceAtLeast(0L)
    fun isPlaying(): Boolean = !released && mediaPlayer.isPlaying
    fun isSeekable(): Boolean = !released && mediaPlayer.isSeekable
    fun hasMedia(): Boolean = !released && currentUrl.isNotBlank()

    fun release() {
        if (released) return
        released = true
        if (mediaPlayer.hasMedia()) runCatching { mediaPlayer.stop() }
        if (viewsAttached) runCatching { mediaPlayer.detachViews() }
        viewsAttached = false
        runCatching { mediaPlayer.release() }
        runCatching { libVlc.release() }
    }

    private fun ensureViewsAttached() {
        if (!viewsAttached) {
            // SurfaceView mode is deliberate for Android TV / TV Box stability.
            mediaPlayer.attachViews(videoLayout, null, true, false)
            viewsAttached = true
        }
    }
}
