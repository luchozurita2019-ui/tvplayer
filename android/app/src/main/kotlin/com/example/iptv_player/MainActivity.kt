package com.example.iptv_player

import android.net.Uri
import android.provider.Settings
import android.view.Surface
import android.view.WindowManager
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.NextRenderersFactory

@UnstableApi
class MainActivity : FlutterActivity(), Player.Listener, AnalyticsListener {
    companion object {
        private const val METHOD_CHANNEL = "tvfull/media3_texture"
        private const val EVENT_CHANNEL = "tvfull/media3_texture_events"
        private const val DEVICE_CHANNEL = "tvfull/device_identity"
        private const val DEFAULT_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36"
    }

    private var player: ExoPlayer? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var eventSink: EventChannel.EventSink? = null
    private var currentUrl: String? = null
    private var isLive = false
    private var endedRecoveries = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getAndroidId") {
                    result.success(
                        Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID,
                        )
                    )
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                handlePlayerCall(flutterEngine, call, result)
            }
    }

    private fun handlePlayerCall(
        flutterEngine: FlutterEngine,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                "initialize" -> result.success(
                    initializePlayer(
                        flutterEngine,
                        call.argument<Int>("minBuffer") ?: 5000,
                        call.argument<Int>("maxBuffer") ?: 15000,
                        call.argument<Int>("bufferForPlayback") ?: 2500,
                        call.argument<Int>("bufferForPlaybackAfterRebuffer") ?: 1000,
                    )
                )
                "prepare" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("INVALID_URL", "URL vacía", null)
                        return
                    }
                    @Suppress("UNCHECKED_CAST")
                    val headers = (call.argument<Map<String, String>>("headers") ?: emptyMap()).toMutableMap()
                    val userAgent = call.argument<String>("userAgent") ?: DEFAULT_UA
                    val position = call.argument<Number>("position")?.toLong() ?: 0L
                    isLive = call.argument<Boolean>("isLive") ?: true
                    prepare(url, headers, userAgent, position)
                    result.success(null)
                }
                "play" -> { player?.play(); applyKeepScreenOn(); result.success(null) }
                "pause" -> { player?.pause(); result.success(null) }
                "seekTo" -> {
                    val raw = call.argument<Number>("position")?.toLong() ?: 0L
                    val duration = player?.duration ?: 0L
                    val target = if (duration > 0 && duration != C.TIME_UNSET) raw.coerceIn(0L, duration) else raw.coerceAtLeast(0L)
                    player?.seekTo(target)
                    result.success(null)
                }
                "getCurrentPosition" -> result.success((player?.currentPosition ?: 0L).coerceAtLeast(0L))
                "getBufferedPosition" -> result.success((player?.bufferedPosition ?: 0L).coerceAtLeast(0L))
                "getDuration" -> {
                    val value = player?.duration ?: 0L
                    result.success(if (value < 0L || value == C.TIME_UNSET) 0L else value)
                }
                "setAudioTrack" -> result.success(
                    selectTrack(
                        C.TRACK_TYPE_AUDIO,
                        call.argument<Number>("groupIndex")?.toInt(),
                        call.argument<Number>("trackIndex")?.toInt(),
                        call.argument<Boolean>("auto") ?: false,
                        false,
                    )
                )
                "setSubtitleTrack" -> result.success(
                    selectTrack(
                        C.TRACK_TYPE_TEXT,
                        call.argument<Number>("groupIndex")?.toInt(),
                        call.argument<Number>("trackIndex")?.toInt(),
                        call.argument<Boolean>("auto") ?: false,
                        call.argument<Boolean>("off") ?: false,
                    )
                )
                "dispose" -> { disposePlayer(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            eventSink?.success(
                mapOf(
                    "eventType" to "videoError",
                    "errorCode" to "PLAYER_EXCEPTION",
                    "error" to (t.message ?: t.javaClass.simpleName),
                )
            )
            result.error("PLAYER_EXCEPTION", t.message ?: t.javaClass.simpleName, null)
        }
    }

    private fun applyKeepScreenOn() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.decorView.keepScreenOn = true
    }

    private fun clearKeepScreenOn() {
        window.decorView.keepScreenOn = false
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onResume() {
        super.onResume()
        if (player != null) applyKeepScreenOn()
    }

    private fun initializePlayer(
        flutterEngine: FlutterEngine,
        minBuffer: Int,
        maxBuffer: Int,
        playBuffer: Int,
        rebuffer: Int,
    ): Long {
        disposePlayer()
        applyKeepScreenOn()
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(minBuffer, maxBuffer, playBuffer, rebuffer)
            .build()
        val renderersFactory = NextRenderersFactory(this)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
        player = ExoPlayer.Builder(this)
            .setLoadControl(loadControl)
            .setRenderersFactory(renderersFactory)
            .build()
            .also { exo ->
                exo.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                        .build(),
                    true,
                )
                exo.addListener(this)
                exo.addAnalyticsListener(this)
            }
        textureEntry = flutterEngine.renderer.createSurfaceTexture()
        surface = Surface(textureEntry!!.surfaceTexture())
        player!!.setVideoSurface(surface)
        return textureEntry!!.id()
    }

    private fun prepare(
        url: String,
        headers: MutableMap<String, String>,
        userAgent: String,
        positionMs: Long,
    ) {
        val exo = player ?: throw IllegalStateException("Player no inicializado")
        applyKeepScreenOn()
        currentUrl = url
        endedRecoveries = 0
        exo.stop()
        exo.clearMediaItems()
        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
        if (headers.isNotEmpty()) httpFactory.setDefaultRequestProperties(headers)
        val source = DefaultMediaSourceFactory(httpFactory).createMediaSource(
            MediaItem.Builder().setUri(Uri.parse(url)).build()
        )
        exo.setMediaSource(source)
        if (positionMs > 0L) exo.seekTo(positionMs)
        exo.prepare()
        exo.playWhenReady = true
    }

    private fun selectTrack(
        trackType: Int,
        groupIndex: Int?,
        trackIndex: Int?,
        auto: Boolean,
        off: Boolean,
    ): Boolean {
        val exo = player ?: return false
        val builder = exo.trackSelectionParameters.buildUpon().clearOverridesOfType(trackType)
        if (off) {
            builder.setTrackTypeDisabled(trackType, true)
            exo.trackSelectionParameters = builder.build()
            return true
        }
        builder.setTrackTypeDisabled(trackType, false)
        if (!auto) {
            if (groupIndex == null || trackIndex == null) return false
            val groups = exo.currentTracks.groups
            if (groupIndex !in groups.indices) return false
            val group = groups[groupIndex]
            if (group.type != trackType || trackIndex !in 0 until group.length) return false
            builder.addOverride(TrackSelectionOverride(group.mediaTrackGroup, listOf(trackIndex)))
        }
        exo.trackSelectionParameters = builder.build()
        return true
    }

    private fun serializeTracks(trackType: Int): List<Map<String, Any?>> {
        val exo = player ?: return emptyList()
        val output = mutableListOf<Map<String, Any?>>()
        exo.currentTracks.groups.forEachIndexed { groupIndex, group ->
            if (group.type != trackType) return@forEachIndexed
            for (trackIndex in 0 until group.length) {
                val format = group.getTrackFormat(trackIndex)
                output.add(
                    mapOf(
                        "groupIndex" to groupIndex,
                        "trackIndex" to trackIndex,
                        "label" to (format.label ?: ""),
                        "language" to (format.language ?: ""),
                        "mimeType" to (format.sampleMimeType ?: ""),
                        "selected" to group.isTrackSelected(trackIndex),
                        "supported" to group.isTrackSupported(trackIndex),
                    )
                )
            }
        }
        return output
    }

    private fun sendTracks() {
        eventSink?.success(
            mapOf(
                "eventType" to "tracksChanged",
                "audioTracks" to serializeTracks(C.TRACK_TYPE_AUDIO),
                "textTracks" to serializeTracks(C.TRACK_TYPE_TEXT),
            )
        )
    }

    override fun onTracksChanged(tracks: Tracks) = sendTracks()

    override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_BUFFERING -> {
                applyKeepScreenOn()
                eventSink?.success(mapOf("eventType" to "bufferingStart"))
            }
            Player.STATE_READY -> {
                applyKeepScreenOn()
                endedRecoveries = 0
                eventSink?.success(mapOf("eventType" to "prepared"))
                eventSink?.success(mapOf("eventType" to "bufferingEnd"))
                sendTracks()
            }
            Player.STATE_ENDED -> {
                val exo = player
                if (isLive && currentUrl != null && exo != null && endedRecoveries < 5) {
                    endedRecoveries++
                    exo.seekToDefaultPosition()
                    exo.prepare()
                    exo.play()
                } else {
                    eventSink?.success(mapOf("eventType" to "completed"))
                }
            }
        }
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (videoSize.width <= 0 || videoSize.height <= 0) return
        if (isLive) {
            textureEntry?.surfaceTexture()?.setDefaultBufferSize(videoSize.width, videoSize.height)
        }
        eventSink?.success(
            mapOf(
                "eventType" to "videoSize",
                "width" to videoSize.width,
                "height" to videoSize.height,
                "pixelWidthHeightRatio" to videoSize.pixelWidthHeightRatio,
            )
        )
    }

    override fun onPlayerError(error: PlaybackException) {
        eventSink?.success(
            mapOf(
                "eventType" to "videoError",
                "errorCode" to error.errorCode,
                "errorCodeName" to error.errorCodeName,
                "error" to (error.message ?: "error de reproducción"),
            )
        )
    }

    override fun onVideoCodecError(
        eventTime: AnalyticsListener.EventTime,
        videoCodecError: Exception,
    ) {
        eventSink?.success(
            mapOf(
                "eventType" to "codecError",
                "kind" to "video",
                "error" to (videoCodecError.message ?: videoCodecError.javaClass.simpleName),
            )
        )
    }

    override fun onAudioCodecError(
        eventTime: AnalyticsListener.EventTime,
        audioCodecError: Exception,
    ) {
        eventSink?.success(
            mapOf(
                "eventType" to "codecError",
                "kind" to "audio",
                "error" to (audioCodecError.message ?: audioCodecError.javaClass.simpleName),
            )
        )
    }

    private fun disposePlayer() {
        player?.removeListener(this)
        player?.removeAnalyticsListener(this)
        player?.stop()
        player?.clearMediaItems()
        player?.release()
        player = null
        surface?.release()
        surface = null
        textureEntry?.release()
        textureEntry = null
        currentUrl = null
        endedRecoveries = 0
        clearKeepScreenOn()
    }

    override fun onDestroy() {
        disposePlayer()
        super.onDestroy()
    }
}
