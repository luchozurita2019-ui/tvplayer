package com.tvfull.pro.tvcore

import android.content.Context
import android.util.AttributeSet
import android.view.SurfaceHolder
import android.view.SurfaceView
import tv.danmaku.ijk.media.player.IMediaPlayer

/**
 * SurfaceView renderer modelled after the proven IJK render lifecycle used by
 * mature IPTV clients. The view owns SurfaceHolder lifecycle; the media player
 * is only bound while the holder is valid.
 */
class IjkSurfaceRenderView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : SurfaceView(context, attrs), SurfaceHolder.Callback {

    interface Callback {
        fun onRenderSurfaceCreated(holder: SurfaceHolder) {}
        fun onRenderSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}
        fun onRenderSurfaceDestroyed(holder: SurfaceHolder) {}
    }

    private var callback: Callback? = null
    private var validHolder: SurfaceHolder? = null
    private var boundPlayer: IMediaPlayer? = null
    private var videoWidth = 0
    private var videoHeight = 0

    init {
        holder.addCallback(this)
        @Suppress("DEPRECATION")
        holder.setType(SurfaceHolder.SURFACE_TYPE_NORMAL)
    }

    fun setRenderCallback(callback: Callback?) {
        this.callback = callback
        validHolder?.let { callback?.onRenderSurfaceCreated(it) }
    }

    fun isSurfaceReady(): Boolean = validHolder?.surface?.isValid == true

    fun currentHolder(): SurfaceHolder? = validHolder?.takeIf { it.surface?.isValid == true }

    fun bind(player: IMediaPlayer?) {
        if (boundPlayer === player && player != null) {
            currentHolder()?.let { runCatching { player.setDisplay(it) } }
            return
        }
        boundPlayer?.let { runCatching { it.setDisplay(null) } }
        boundPlayer = player
        val surface = currentHolder()
        if (player != null && surface != null) {
            runCatching { player.setDisplay(surface) }
        }
    }

    fun unbind(player: IMediaPlayer? = boundPlayer) {
        if (player != null && player === boundPlayer) {
            runCatching { player.setDisplay(null) }
            boundPlayer = null
        }
    }

    fun setVideoSize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        videoWidth = width
        videoHeight = height
        currentHolder()?.let { h ->
            runCatching { h.setFixedSize(width, height) }
        }
        requestLayout()
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        validHolder = holder
        boundPlayer?.let { runCatching { it.setDisplay(holder) } }
        callback?.onRenderSurfaceCreated(holder)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        validHolder = holder
        if (videoWidth > 0 && videoHeight > 0) {
            runCatching { holder.setFixedSize(videoWidth, videoHeight) }
        }
        boundPlayer?.let { runCatching { it.setDisplay(holder) } }
        callback?.onRenderSurfaceChanged(holder, format, width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        callback?.onRenderSurfaceDestroyed(holder)
        boundPlayer?.let { runCatching { it.setDisplay(null) } }
        if (validHolder === holder) validHolder = null
    }
}