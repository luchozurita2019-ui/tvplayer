from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise RuntimeError(f"No se encontró el bloque esperado: {label}")


def replace_region(text: str, start: str, end: str, replacement: str, label: str) -> str:
    if replacement in text:
        return text
    start_at = text.find(start)
    if start_at < 0:
        raise RuntimeError(f"No se encontró inicio de región: {label}")
    end_at = text.find(end, start_at)
    if end_at < 0:
        raise RuntimeError(f"No se encontró fin de región: {label}")
    return text[:start_at] + replacement + text[end_at:]


# ---------------------------------------------------------------------------
# 1) Version: TV FULL PRO 1.2.3+15
# ---------------------------------------------------------------------------
pubspec_path = ROOT / "pubspec.yaml"
pubspec = pubspec_path.read_text(encoding="utf-8")
pubspec = replace_once(pubspec, "version: 1.2.2+14", "version: 1.2.3+15", "version")
pubspec = pubspec.replace(
    "# TV FULL PRO 1.2.2+14 validation marker.",
    "# TV FULL PRO 1.2.3+15 live-speed validation marker.",
)
pubspec_path.write_text(pubspec, encoding="utf-8")


# ---------------------------------------------------------------------------
# 2) LIVE profile: smaller start buffer, VOD untouched.
# ---------------------------------------------------------------------------
live_path = ROOT / "lib/screens/android_media3_texture_player_screen.dart"
live = live_path.read_text(encoding="utf-8")
for old, new, label in (
    ("'minBuffer': 3500", "'minBuffer': 2500", "LIVE minBuffer"),
    ("'maxBuffer': 12000", "'maxBuffer': 8000", "LIVE maxBuffer"),
    ("'bufferForPlayback': 1500", "'bufferForPlayback': 1000", "LIVE bufferForPlayback"),
    (
        "'bufferForPlaybackAfterRebuffer': 800",
        "'bufferForPlaybackAfterRebuffer': 1200",
        "LIVE rebuffer",
    ),
):
    live = replace_once(live, old, new, label)
live_path.write_text(live, encoding="utf-8")


# ---------------------------------------------------------------------------
# 3) Native Media3 LIVE engine: fast zapping + hard startup deadline +
#    controlled WifiLock + one bounded end recovery.
# ---------------------------------------------------------------------------
kotlin_path = ROOT / "android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt"
kotlin = kotlin_path.read_text(encoding="utf-8")

kotlin = replace_once(
    kotlin,
    "import android.net.Uri\nimport android.provider.Settings",
    "import android.net.Uri\nimport android.net.wifi.WifiManager\nimport android.os.Handler\nimport android.os.Looper\nimport android.provider.Settings",
    "imports de reproducción",
)

kotlin = replace_once(
    kotlin,
    '        private const val DEFAULT_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36"\n',
    '        private const val DEFAULT_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36"\n'
    "        private const val LIVE_STARTUP_DEADLINE_MS = 4500L\n"
    "        private const val LIVE_RECOVERY_DEADLINE_MS = 3000L\n"
    "        private const val MAX_LIVE_ENDED_RECOVERIES = 1\n",
    "constantes LIVE rápidas",
)

kotlin = replace_once(
    kotlin,
    "    private var dnsFallbackActive = false\n",
    "    private var dnsFallbackActive = false\n"
    "    private var wifiLock: WifiManager.WifiLock? = null\n"
    "    private var playbackGeneration = 0L\n"
    "    private var startupDeadline: Runnable? = null\n"
    "    private val mainHandler = Handler(Looper.getMainLooper())\n"
    "    private var normalMediaSourceFactory: DefaultMediaSourceFactory? = null\n"
    "    private var normalMediaSourceKey: String? = null\n"
    "    private var fallbackMediaSourceFactory: DefaultMediaSourceFactory? = null\n"
    "    private var fallbackMediaSourceKey: String? = null\n",
    "estado LIVE rápido",
)

kotlin = replace_once(
    kotlin,
    '''                "play" -> {
                    player?.play()
                    applyKeepScreenOn()
                    result.success(null)
                }

                "pause" -> {
                    player?.pause()
                    result.success(null)
                }
''',
    '''                "play" -> {
                    player?.play()
                    applyPlaybackGuards()
                    result.success(null)
                }

                "pause" -> {
                    player?.pause()
                    releasePlaybackGuards()
                    result.success(null)
                }
''',
    "play/pause guards",
)

new_guard_region = '''    private fun applyKeepScreenOn() {
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

'''
kotlin = replace_region(
    kotlin,
    "    private fun applyKeepScreenOn() {",
    "    private fun initializePlayer(",
    new_guard_region,
    "guards de pantalla/Wi-Fi",
)

kotlin = replace_once(
    kotlin,
    "        disposePlayer()\n        applyKeepScreenOn()\n        val loadControl",
    "        disposePlayer()\n        val loadControl",
    "initialize sin guard prematuro",
)

new_prepare_region = '''    private fun prepare(
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

'''
kotlin = replace_region(
    kotlin,
    "    private fun prepare(\n",
    "    private fun selectTrack(\n",
    new_prepare_region,
    "prepare/MediaSource LIVE",
)

new_state_region = '''    override fun onPlaybackStateChanged(playbackState: Int) {
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

'''
kotlin = replace_region(
    kotlin,
    "    override fun onPlaybackStateChanged(playbackState: Int) {",
    "    override fun onVideoSizeChanged(videoSize: VideoSize) {",
    new_state_region,
    "estados LIVE",
)

new_error_region = '''    override fun onPlayerError(error: PlaybackException) {
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

'''
kotlin = replace_region(
    kotlin,
    "    override fun onPlayerError(error: PlaybackException) {",
    "    private fun hasUnknownHost(error: Throwable): Boolean {",
    new_error_region,
    "errores LIVE rápidos",
)

new_dispose_region = '''    private fun disposePlayer() {
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

'''
kotlin = replace_region(
    kotlin,
    "    private fun disposePlayer() {",
    "    override fun onDestroy() {",
    new_dispose_region,
    "dispose LIVE",
)

# Safety assertions: these capabilities already exist in 1.2.2+14 and must be
# retained while applying the live-speed changes.
for marker in (
    '"setAudioTrack"',
    '"setSubtitleTrack"',
    "NextRenderersFactory",
    "TvFullFallbackDns",
):
    if marker not in kotlin:
        raise RuntimeError(f"Se perdió una capacidad requerida: {marker}")

kotlin_path.write_text(kotlin, encoding="utf-8")

vod = (ROOT / "lib/screens/android_media3_vod_player_screen.dart").read_text(encoding="utf-8")
if "_audioTracks" not in vod or "_subtitleTracks" not in vod:
    raise RuntimeError("El reproductor VOD perdió audio/subtítulos múltiples")

print("TV FULL PRO 1.2.3+15: live-speed patch aplicado correctamente")
