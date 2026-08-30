package com.example.iptv_player

import android.app.ActivityManager
import android.content.Context
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
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
import androidx.media3.datasource.okhttp.OkHttpDataSource
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
import java.net.InetAddress
import java.net.UnknownHostException
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import okhttp3.Dns
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.dnsoverhttps.DnsOverHttps

@UnstableApi
class MainActivity : FlutterActivity(), Player.Listener, AnalyticsListener {
    companion object {
        private const val METHOD_CHANNEL = "tvfull/media3_texture"
        private const val EVENT_CHANNEL = "tvfull/media3_texture_events"
        private const val DEVICE_CHANNEL = "tvfull/device_identity"
        private const val DEFAULT_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36"
        private const val LIVE_STARTUP_DEADLINE_MS = 4500L
        private const val LIVE_RECOVERY_DEADLINE_MS = 3000L
        private const val MAX_LIVE_ENDED_RECOVERIES = 1
    }

    private var player: ExoPlayer? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var eventSink: EventChannel.EventSink? = null
    private var currentUrl: String? = null
    private var currentHeaders: Map<String, String> = emptyMap()
    private var currentUserAgent: String = DEFAULT_UA
    private var isLive = false
    private var endedRecoveries = 0
    private var dnsFallbackActive = false
    private var wifiLock: WifiManager.WifiLock? = null
    private var playbackGeneration = 0L
    private var startupDeadline: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var normalMediaSourceFactory: DefaultMediaSourceFactory? = null
    private var normalMediaSourceKey: String? = null
    private var fallbackMediaSourceFactory: DefaultMediaSourceFactory? = null
    private var fallbackMediaSourceKey: String? = null

    private val fallbackDns by lazy { TvFullFallbackDns() }
    private val fallbackHttpClient by lazy {
        OkHttpClient.Builder()
            .dns(fallbackDns)
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(35, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidId" -> result.success(
                        Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID,
                        )
                    )
                    "getAppVersion" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode
                        } else {
                            info.versionCode.toLong()
                        }
                        result.success(
                            mapOf(
                                "versionName" to (info.versionName ?: ""),
                                "versionCode" to code,
                            )
                        )
                    }
                    "getDeviceProfile" -> {
                        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        result.success(
                            mapOf(
                                "lowRam" to manager.isLowRamDevice,
                                "memoryClassMb" to manager.memoryClass,
                                "largeMemoryClassMb" to manager.largeMemoryClass,
                            )
                        )
                    }
                    else -> result.notImplemented()
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
                        call.argument<Int>("backBuffer") ?: 0,
                        call.argument<Boolean>("retainBackBufferFromKeyframe") ?: false,
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

                "play" -> {
                    player?.play()
                    applyPlaybackGuards()
                    result.success(null)
                }

                "pause" -> {
                    player?.pause()
                    releasePlaybackGuards()
                    result.success(null)
                }

                "seekTo" -> {
                    val raw = call.argument<Number>("position")?.toLong() ?: 0L
                    val duration = player?.duration ?: 0L
                    val target = if (duration > 0 && duration != C.TIME_UNSET) {
                        raw.coerceIn(0L, duration)
                    } else {
                        raw.coerceAtLeast(0L)
                    }
                    player?.seekTo(target)
                    result.success(null)
                }

                "getCurrentPosition" -> result.success(
                    (player?.currentPosition ?: 0L).coerceAtLeast(0L)
                )

                "getBufferedPosition" -> result.success(
                    (player?.bufferedPosition ?: 0L).coerceAtLeast(0L)
                )

                "getDuration" -> {
                    val value = player?.duration ?: 0L
                    result.success(if (value < 0L || value == C.TIME_UNSET) 0L else value)
                }

                "getPlaybackSnapshot" -> {
                    val exo = player
                    val duration = exo?.duration ?: 0L
                    result.success(
                        mapOf(
                            "position" to (exo?.currentPosition ?: 0L).coerceAtLeast(0L),
                            "bufferedPosition" to (exo?.bufferedPosition ?: 0L).coerceAtLeast(0L),
                            "duration" to if (duration < 0L || duration == C.TIME_UNSET) 0L else duration,
                            "seekable" to (exo?.isCurrentMediaItemSeekable == true),
                            "live" to (exo?.isCurrentMediaItemLive == true),
                            "dnsFallback" to dnsFallbackActive,
                        )
                    )
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

                "dispose" -> {
                    disposePlayer()
                    result.success(null)
                }

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

    @Suppress("DEPRECATION")
    private fun acquireWifiLock() {
        if (!isLive) return
        try {
            val lock = wifiLock ?: run {
                val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                manager.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    "$packageName:tvfull-live",
                ).also {
                    it.setReferenceCounted(false)
                    wifiLock = it
                }
            }
            if (!lock.isHeld) lock.acquire()
        } catch (_: Throwable) {
            // La reproducción no debe fallar si un fabricante limita WifiLock.
        }
    }

    private fun releaseWifiLock() {
        try {
            val lock = wifiLock
            if (lock != null && lock.isHeld) lock.release()
        } catch (_: Throwable) {
            // Ignorar ROMs que invaliden el lock al cambiar de estado de red.
        }
    }

    private fun applyPlaybackGuards() {
        applyKeepScreenOn()
        acquireWifiLock()
    }

    private fun releasePlaybackGuards() {
        releaseWifiLock()
        clearKeepScreenOn()
    }

    override fun onResume() {
        super.onResume()
        val exo = player
        if (exo?.playWhenReady == true &&
            (exo.playbackState == Player.STATE_BUFFERING || exo.playbackState == Player.STATE_READY)
        ) {
            applyPlaybackGuards()
        }
    }

    override fun onPause() {
        releasePlaybackGuards()
        super.onPause()
    }

    private fun initializePlayer(
        flutterEngine: FlutterEngine,
        minBuffer: Int,
        maxBuffer: Int,
        playBuffer: Int,
        rebuffer: Int,
        backBuffer: Int,
        retainBackBufferFromKeyframe: Boolean,
    ): Long {
        disposePlayer()
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(minBuffer, maxBuffer, playBuffer, rebuffer)
            .setBackBuffer(backBuffer.coerceAtLeast(0), retainBackBufferFromKeyframe)
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
        playbackGeneration++
        val generation = playbackGeneration
        cancelStartupDeadline()
        currentUrl = url
        currentHeaders = headers.toMap()
        currentUserAgent = userAgent
        endedRecoveries = 0
        dnsFallbackActive = false
        prepareSource(url, headers, userAgent, positionMs, useFallbackDns = false)
        if (isLive) scheduleStartupDeadline(generation, LIVE_STARTUP_DEADLINE_MS)
    }

    private fun prepareSource(
        url: String,
        headers: Map<String, String>,
        userAgent: String,
        positionMs: Long,
        useFallbackDns: Boolean,
    ) {
        val exo = player ?: throw IllegalStateException("Player no inicializado")
        applyPlaybackGuards()

        val factory = mediaSourceFactory(headers, userAgent, useFallbackDns)
        val source = factory.createMediaSource(
            MediaItem.Builder().setUri(Uri.parse(url)).build()
        )

        // setMediaSource reemplaza la señal anterior en la misma instancia de
        // ExoPlayer. Evitamos stop + clearMediaItems para que el zapping no
        // reconstruya innecesariamente el pipeline/surface de video.
        exo.setMediaSource(source)
        if (positionMs > 0L) exo.seekTo(positionMs)
        exo.prepare()
        exo.playWhenReady = true
    }

    private fun mediaSourceFactory(
        headers: Map<String, String>,
        userAgent: String,
        useFallbackDns: Boolean,
    ): DefaultMediaSourceFactory {
        val key = sourceFactoryKey(headers, userAgent)
        if (useFallbackDns) {
            val cached = fallbackMediaSourceFactory
            if (cached != null && fallbackMediaSourceKey == key) return cached
            val okHttpFactory = OkHttpDataSource.Factory(fallbackHttpClient)
                .setUserAgent(userAgent)
            if (headers.isNotEmpty()) okHttpFactory.setDefaultRequestProperties(headers)
            return DefaultMediaSourceFactory(okHttpFactory).also {
                fallbackMediaSourceFactory = it
                fallbackMediaSourceKey = key
            }
        }

        val cached = normalMediaSourceFactory
        if (cached != null && normalMediaSourceKey == key) return cached
        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(if (isLive) 3500 else 12000)
            .setReadTimeoutMs(if (isLive) 6000 else 30000)
        if (headers.isNotEmpty()) httpFactory.setDefaultRequestProperties(headers)
        return DefaultMediaSourceFactory(httpFactory).also {
            normalMediaSourceFactory = it
            normalMediaSourceKey = key
        }
    }

    private fun sourceFactoryKey(headers: Map<String, String>, userAgent: String): String =
        buildString {
            append(if (isLive) "live" else "vod")
            append('|')
            append(userAgent)
            headers.entries
                .sortedBy { it.key.lowercase(Locale.US) }
                .forEach {
                    append('|')
                    append(it.key.lowercase(Locale.US))
                    append('=')
                    append(it.value)
                }
        }

    private fun scheduleStartupDeadline(generation: Long, delayMs: Long) {
        cancelStartupDeadline()
        val task = Runnable {
            if (!isLive || generation != playbackGeneration) return@Runnable
            val exo = player ?: return@Runnable
            if (exo.playbackState == Player.STATE_READY) return@Runnable
            exo.stop()
            releasePlaybackGuards()
            eventSink?.success(
                mapOf(
                    "eventType" to "videoError",
                    "errorCode" to "TVFULL_STARTUP_DEADLINE",
                    "errorCodeName" to "TVFULL_STARTUP_DEADLINE",
                    "error" to "La señal no respondió",
                )
            )
        }
        startupDeadline = task
        mainHandler.postDelayed(task, delayMs)
    }

    private fun cancelStartupDeadline() {
        startupDeadline?.let(mainHandler::removeCallbacks)
        startupDeadline = null
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
                if (player?.playWhenReady == true) applyPlaybackGuards()
                eventSink?.success(mapOf("eventType" to "bufferingStart"))
            }

            Player.STATE_READY -> {
                cancelStartupDeadline()
                if (player?.playWhenReady == true) {
                    applyPlaybackGuards()
                } else {
                    releasePlaybackGuards()
                }
                eventSink?.success(mapOf("eventType" to "prepared"))
                eventSink?.success(mapOf("eventType" to "bufferingEnd"))
                sendTracks()
            }

            Player.STATE_ENDED -> {
                cancelStartupDeadline()
                val exo = player
                if (isLive && currentUrl != null && exo != null &&
                    endedRecoveries < MAX_LIVE_ENDED_RECOVERIES
                ) {
                    endedRecoveries++
                    applyPlaybackGuards()
                    exo.seekToDefaultPosition()
                    exo.prepare()
                    exo.play()
                    scheduleStartupDeadline(playbackGeneration, LIVE_RECOVERY_DEADLINE_MS)
                } else {
                    releasePlaybackGuards()
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
        if (!dnsFallbackActive && hasUnknownHost(error)) {
            val url = currentUrl
            if (url != null) {
                val resumePosition = (player?.currentPosition ?: 0L).coerceAtLeast(0L)
                try {
                    dnsFallbackActive = true
                    prepareSource(
                        url,
                        currentHeaders,
                        currentUserAgent,
                        resumePosition,
                        useFallbackDns = true,
                    )
                    eventSink?.success(
                        mapOf(
                            "eventType" to "dnsFallback",
                            "host" to (Uri.parse(url).host ?: ""),
                        )
                    )
                    return
                } catch (_: Throwable) {
                    // El deadline total de LIVE sigue vigente; no encadenamos
                    // resoluciones/reintentos adicionales.
                }
            }
        }

        cancelStartupDeadline()
        releasePlaybackGuards()
        val fastIo = isFastIoError(error)
        eventSink?.success(
            mapOf(
                "eventType" to "videoError",
                "errorCode" to error.errorCode,
                "errorCodeName" to if (fastIo) "TVFULL_FAST_IO" else error.errorCodeName,
                "error" to if (fastIo) "La señal no respondió" else
                    (error.message ?: "error de reproducción"),
            )
        )
    }

    private fun isFastIoError(error: PlaybackException): Boolean {
        val name = error.errorCodeName.lowercase(Locale.US)
        return name.contains("_io_") ||
            name.contains("network") ||
            name.contains("timeout") ||
            name.contains("bad_http_status")
    }

    private fun hasUnknownHost(error: Throwable): Boolean {
        var cause: Throwable? = error
        repeat(12) {
            if (cause == null) return false
            if (cause is UnknownHostException) return true
            cause = cause?.cause
        }
        return false
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
        playbackGeneration++
        cancelStartupDeadline()
        releasePlaybackGuards()
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
        currentHeaders = emptyMap()
        currentUserAgent = DEFAULT_UA
        endedRecoveries = 0
        dnsFallbackActive = false
        normalMediaSourceFactory = null
        normalMediaSourceKey = null
        fallbackMediaSourceFactory = null
        fallbackMediaSourceKey = null
    }

    override fun onDestroy() {
        disposePlayer()
        super.onDestroy()
    }
}

private data class DnsCacheEntry(
    val addresses: List<InetAddress>,
    val expiresAtMs: Long,
)

/**
 * Lightweight DNS fallback inspired by the resolver set present in Hot Player.
 *
 * The normal Media3 path continues using Android/system DNS. This resolver is
 * instantiated only after that normal path fails with UnknownHostException.
 * Results are cached so a provider host is not resolved again for every stream.
 */
private class TvFullFallbackDns : Dns {
    companion object {
        private const val CACHE_TTL_MS = 10 * 60 * 1000L
    }

    private val cache = ConcurrentHashMap<String, DnsCacheEntry>()
    private val bootstrapClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .build()

    private val resolvers: List<Dns> by lazy {
        listOf(
            createResolver(
                "https://cloudflare-dns.com/dns-query",
                listOf("1.1.1.1", "1.0.0.1"),
            ),
            createResolver(
                "https://dns.google/dns-query",
                listOf("8.8.8.8", "8.8.4.4"),
            ),
            createResolver(
                "https://dns.adguard-dns.com/dns-query",
                listOf("94.140.14.14", "94.140.15.15"),
            ),
        )
    }

    override fun lookup(hostname: String): List<InetAddress> {
        if (hostname.isBlank()) throw UnknownHostException("hostname vacío")
        val key = hostname.lowercase(Locale.US)
        val now = System.currentTimeMillis()
        val cached = cache[key]
        if (cached != null && cached.expiresAtMs > now && cached.addresses.isNotEmpty()) {
            return cached.addresses
        }
        if (cached != null) cache.remove(key)

        var lastError: UnknownHostException? = null
        for (resolver in resolvers) {
            try {
                val result = resolver.lookup(hostname)
                if (result.isNotEmpty()) {
                    cache[key] = DnsCacheEntry(result, now + CACHE_TTL_MS)
                    return result
                }
            } catch (error: UnknownHostException) {
                lastError = error
            }
        }
        throw lastError ?: UnknownHostException(hostname)
    }

    private fun createResolver(url: String, bootstrapIps: List<String>): Dns {
        val bootstrap = bootstrapIps.map { InetAddress.getByName(it) }
        return DnsOverHttps.Builder()
            .client(bootstrapClient)
            .url(url.toHttpUrl())
            .bootstrapDnsHosts(bootstrap)
            .build()
    }
}
