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
 * Single playback engine for Native TV V6.
 *
 * One engine owns a playback session from start to finish. We never jump between
 * Media3/VLC/HLS/TS after a transient error. The URL supplied by the catalog is
 * always the source of truth and recovery reopens that exact URL.
 */
class StableVlcPlayer(
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
    private val libVlc = LibVLC(
        appContext,
        arrayListOf(
            "--http-reconnect",
            "--network-caching=8000",
            "--live-caching=8000",
            "--file-caching=15000",
        ),
    )
    private val mediaPlayer = MediaPlayer(libVlc)

    val videoLayout: VLCVideoLayout = VLCVideoLayout(context).apply {
        visibility = View.GONE
        isFocusable = false
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
    }

    private var attached = false
    private var released = false
    private var currentUrl = ""
    private var currentLive = false

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
                MediaPlayer.Event.Vout -> videoLayout.post {
                    runCatching { mediaPlayer.updateVideoSurfaces() }
                }
            }
        }
    }

    fun play(url: String, live: Boolean, resumePositionMs: Long = 0L) {
        if (released || url.isBlank()) return
        ensureAttached()
        currentUrl = url
        currentLive = live
        videoLayout.visibility = View.VISIBLE

        if (mediaPlayer.hasMedia()) runCatching { mediaPlayer.stop() }
        val media = Media(libVlc, Uri.parse(url)).apply {
            setHWDecoderEnabled(true, false)
            if (live) {
                addOption(":network-caching=8000")
                addOption(":live-caching=8000")
            } else {
                addOption(":network-caching=15000")
                addOption(":file-caching=15000")
            }
            addOption(":http-reconnect")
        }
        mediaPlayer.setMedia(media)
        media.release()
        mediaPlayer.play()

        if (!live && resumePositionMs > 0L) {
            val target = resumePositionMs.coerceAtLeast(0L)
            videoLayout.postDelayed({
                if (!released && currentUrl == url && mediaPlayer.isSeekable) {
                    mediaPlayer.time = target
                }
            }, 1200L)
        }
    }

    fun stop(hideSurface: Boolean = true) {
        if (released) return
        if (mediaPlayer.hasMedia()) runCatching { mediaPlayer.stop() }
        currentUrl = ""
        if (hideSurface) videoLayout.visibility = View.GONE
    }

    fun togglePause() {
        if (released || !mediaPlayer.hasMedia()) return
        if (mediaPlayer.isPlaying) runCatching { mediaPlayer.pause() }
        else runCatching { mediaPlayer.play() }
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
        return if (track.width > 0 && track.height > 0) track.width to track.height else null
    }

    fun currentTimeMs(): Long = if (released) 0L else mediaPlayer.time.coerceAtLeast(0L)
    fun durationMs(): Long = if (released) 0L else mediaPlayer.length.coerceAtLeast(0L)
    fun isPlaying(): Boolean = !released && mediaPlayer.isPlaying
    fun isSeekable(): Boolean = !released && mediaPlayer.isSeekable
    fun hasMedia(): Boolean = !released && currentUrl.isNotBlank()
    fun url(): String = currentUrl
    fun isLive(): Boolean = currentLive

    fun release() {
        if (released) return
        released = true
        if (mediaPlayer.hasMedia()) runCatching { mediaPlayer.stop() }
        if (attached) runCatching { mediaPlayer.detachViews() }
        attached = false
        runCatching { mediaPlayer.release() }
        runCatching { libVlc.release() }
    }

    private fun ensureAttached() {
        if (!attached) {
            mediaPlayer.attachViews(videoLayout, null, true, false)
            attached = true
        }
    }
}
