from pathlib import Path

ROOT = Path('.')


def replace(path, old, new, count=1):
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:140]!r}')
    text = text.replace(old, new, count)
    p.write_text(text, encoding='utf-8')


# TV FULL PRO 1.2.8+20
# Goal: keep fast zapping while adding reserve and bounded recovery for
# unstable LIVE servers. VOD/Series playback architecture is not changed.

# 1) Flutter LIVE buffer profile: fast first frame, larger reserve afterwards.
path = 'lib/screens/android_media3_texture_player_screen.dart'
replace(
    path,
    "import '../models/channel.dart';\n",
    "import '../models/channel.dart';\nimport '../services/device_performance_service.dart';\n",
)
replace(
    path,
    """  Future<void> _initialize() async {
    try {
      final id = await _player.invokeMethod<int>('initialize', {
        'minBuffer': 2500,
        'maxBuffer': 8000,
        'bufferForPlayback': 1000,
        'bufferForPlaybackAfterRebuffer': 1200,
      });
""",
    """  Future<void> _initialize() async {
    try {
      final lowRam = DevicePerformanceService.instance.lowRam;
      final id = await _player.invokeMethod<int>('initialize', {
        // Arranque rápido, pero con reserva suficiente para servidores que
        // entregan segmentos de forma irregular. LOW_RAM usa una ventana
        // ligeramente menor para no castigar TVs modestos.
        'minBuffer': lowRam ? 4000 : 5000,
        'maxBuffer': lowRam ? 12000 : 15000,
        'bufferForPlayback': 1000,
        'bufferForPlaybackAfterRebuffer': lowRam ? 2200 : 2500,
      });
""",
)
replace(
    path,
    """      case 'codecError':
        debugPrint('TV FULL PRO LIVE codec: ${event['error']}');
        break;
""",
    """      case 'liveRecovery':
        debugPrint(
          'TV FULL PRO LIVE recovery: ${event['reason']} '
          'attempt=${event['attempt']}',
        );
        break;
      case 'codecError':
        debugPrint('TV FULL PRO LIVE codec: ${event['error']}');
        break;
""",
)

# 2) Native Media3: larger read tolerance + bounded health watchdog.
path = 'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt'
replace(
    path,
    """        private const val LIVE_STARTUP_DEADLINE_MS = 4500L
        private const val LIVE_RECOVERY_DEADLINE_MS = 3000L
        private const val MAX_LIVE_ENDED_RECOVERIES = 1
""",
    """        private const val LIVE_STARTUP_DEADLINE_MS = 4500L
        private const val LIVE_RECOVERY_DEADLINE_MS = 4500L
        private const val LIVE_BUFFER_HEALTH_INTERVAL_MS = 2500L
        private const val LIVE_BUFFER_STALL_MS = 6500L
        private const val LIVE_STABLE_RESET_MS = 30000L
        private const val MAX_LIVE_ENDED_RECOVERIES = 2
        private const val MAX_LIVE_STALL_RECOVERIES = 2
""",
)
replace(
    path,
    """    private var playbackGeneration = 0L
    private var startupDeadline: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())
""",
    """    private var playbackGeneration = 0L
    private var startupDeadline: Runnable? = null
    private var liveBufferHealthCheck: Runnable? = null
    private var liveStabilityReset: Runnable? = null
    private var liveEverReady = false
    private var liveBufferLastProgressAtMs = 0L
    private var liveBufferLastPositionMs = 0L
    private var liveStallRecoveries = 0
    private val mainHandler = Handler(Looper.getMainLooper())
""",
)
replace(
    path,
    """        playbackGeneration++
        val generation = playbackGeneration
        cancelStartupDeadline()
        currentUrl = url
        currentHeaders = headers.toMap()
        currentUserAgent = userAgent
        endedRecoveries = 0
        dnsFallbackActive = false
""",
    """        playbackGeneration++
        val generation = playbackGeneration
        cancelStartupDeadline()
        cancelLiveBufferHealthCheck()
        cancelLiveStabilityReset()
        currentUrl = url
        currentHeaders = headers.toMap()
        currentUserAgent = userAgent
        endedRecoveries = 0
        liveStallRecoveries = 0
        liveEverReady = false
        liveBufferLastProgressAtMs = 0L
        liveBufferLastPositionMs = 0L
        dnsFallbackActive = false
""",
)
replace(
    path,
    """        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(if (isLive) 3500 else 12000)
            .setReadTimeoutMs(if (isLive) 6000 else 30000)
""",
    """        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            // LIVE conserva conexión rápida para detectar hosts muertos, pero
            // permite más tiempo de lectura una vez conectado. Esto protege
            // contra servidores que entregan segmentos con jitter.
            .setConnectTimeoutMs(if (isLive) 4000 else 12000)
            .setReadTimeoutMs(if (isLive) 10000 else 30000)
""",
)
replace(
    path,
    """    private fun cancelStartupDeadline() {
        startupDeadline?.let(mainHandler::removeCallbacks)
        startupDeadline = null
    }

    private fun selectTrack(
""",
    """    private fun cancelStartupDeadline() {
        startupDeadline?.let(mainHandler::removeCallbacks)
        startupDeadline = null
    }

    private fun cancelLiveBufferHealthCheck() {
        liveBufferHealthCheck?.let(mainHandler::removeCallbacks)
        liveBufferHealthCheck = null
    }

    private fun cancelLiveStabilityReset() {
        liveStabilityReset?.let(mainHandler::removeCallbacks)
        liveStabilityReset = null
    }

    private fun scheduleLiveStabilityReset(generation: Long) {
        cancelLiveStabilityReset()
        if (!isLive || !liveEverReady) return
        val task = Runnable {
            if (!isLive || generation != playbackGeneration) return@Runnable
            val exo = player ?: return@Runnable
            if (exo.playbackState != Player.STATE_READY) return@Runnable
            // Tras 30 s continuos de reproducción sana permitimos nuevamente
            // recuperaciones futuras. Evita loops rápidos, pero no penaliza una
            // señal que tiene un microcorte aislado mucho más tarde.
            endedRecoveries = 0
            liveStallRecoveries = 0
        }
        liveStabilityReset = task
        mainHandler.postDelayed(task, LIVE_STABLE_RESET_MS)
    }

    private fun scheduleLiveBufferHealthCheck(generation: Long) {
        cancelLiveBufferHealthCheck()
        if (!isLive || !liveEverReady || generation != playbackGeneration) return
        val exo = player ?: return
        if (exo.playbackState != Player.STATE_BUFFERING) return

        val now = System.currentTimeMillis()
        val buffered = exo.bufferedPosition.coerceAtLeast(0L)
        if (liveBufferLastProgressAtMs == 0L) {
            liveBufferLastProgressAtMs = now
            liveBufferLastPositionMs = buffered
        }

        val task = Runnable {
            if (!isLive || generation != playbackGeneration) return@Runnable
            val current = player ?: return@Runnable
            if (current.playbackState != Player.STATE_BUFFERING) return@Runnable

            val checkNow = System.currentTimeMillis()
            val currentBuffered = current.bufferedPosition.coerceAtLeast(0L)
            if (currentBuffered > liveBufferLastPositionMs + 250L) {
                // Siguen llegando datos: dejamos que Media3 reconstruya reserva
                // sin interrumpir un servidor lento que todavía está vivo.
                liveBufferLastPositionMs = currentBuffered
                liveBufferLastProgressAtMs = checkNow
                scheduleLiveBufferHealthCheck(generation)
                return@Runnable
            }

            val silentFor = checkNow - liveBufferLastProgressAtMs
            if (silentFor >= LIVE_BUFFER_STALL_MS &&
                liveStallRecoveries < MAX_LIVE_STALL_RECOVERIES
            ) {
                val url = currentUrl ?: return@Runnable
                liveStallRecoveries++
                cancelLiveBufferHealthCheck()
                cancelLiveStabilityReset()
                try {
                    // Soft reconnect: reemplaza solo la fuente en el MISMO
                    // ExoPlayer/Surface. No reconstruye el reproductor ni la UI.
                    prepareSource(
                        url,
                        currentHeaders,
                        currentUserAgent,
                        0L,
                        useFallbackDns = dnsFallbackActive,
                    )
                    scheduleStartupDeadline(generation, LIVE_RECOVERY_DEADLINE_MS)
                    eventSink?.success(
                        mapOf(
                            "eventType" to "liveRecovery",
                            "reason" to "buffering_stall",
                            "attempt" to liveStallRecoveries,
                        )
                    )
                } catch (error: Throwable) {
                    releasePlaybackGuards()
                    eventSink?.success(
                        mapOf(
                            "eventType" to "videoError",
                            "errorCodeName" to "TVFULL_STALL_RECOVERY_FAILED",
                            "error" to (error.message ?: "Falló la recuperación LIVE"),
                        )
                    )
                }
                return@Runnable
            }

            scheduleLiveBufferHealthCheck(generation)
        }
        liveBufferHealthCheck = task
        mainHandler.postDelayed(task, LIVE_BUFFER_HEALTH_INTERVAL_MS)
    }

    private fun selectTrack(
""",
)
old_state = """    override fun onPlaybackStateChanged(playbackState: Int) {
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
"""
new_state = """    override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_BUFFERING -> {
                if (player?.playWhenReady == true) applyPlaybackGuards()
                cancelLiveStabilityReset()
                if (isLive && liveEverReady) {
                    if (liveBufferLastProgressAtMs == 0L) {
                        liveBufferLastProgressAtMs = System.currentTimeMillis()
                        liveBufferLastPositionMs =
                            (player?.bufferedPosition ?: 0L).coerceAtLeast(0L)
                    }
                    scheduleLiveBufferHealthCheck(playbackGeneration)
                }
                eventSink?.success(mapOf("eventType" to "bufferingStart"))
            }

            Player.STATE_READY -> {
                cancelStartupDeadline()
                cancelLiveBufferHealthCheck()
                liveEverReady = liveEverReady || isLive
                liveBufferLastProgressAtMs = 0L
                liveBufferLastPositionMs = 0L
                if (isLive) scheduleLiveStabilityReset(playbackGeneration)
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
                cancelLiveBufferHealthCheck()
                cancelLiveStabilityReset()
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
                    eventSink?.success(
                        mapOf(
                            "eventType" to "liveRecovery",
                            "reason" to "unexpected_end",
                            "attempt" to endedRecoveries,
                        )
                    )
                } else {
                    releasePlaybackGuards()
                    eventSink?.success(mapOf("eventType" to "completed"))
                }
            }
        }
    }
"""
replace(path, old_state, new_state)
replace(
    path,
    """    override fun onPlayerError(error: PlaybackException) {
        if (!dnsFallbackActive && hasUnknownHost(error)) {
""",
    """    override fun onPlayerError(error: PlaybackException) {
        cancelLiveBufferHealthCheck()
        cancelLiveStabilityReset()
        if (!dnsFallbackActive && hasUnknownHost(error)) {
""",
)
replace(
    path,
    """        playbackGeneration++
        cancelStartupDeadline()
        releasePlaybackGuards()
""",
    """        playbackGeneration++
        cancelStartupDeadline()
        cancelLiveBufferHealthCheck()
        cancelLiveStabilityReset()
        releasePlaybackGuards()
""",
)
replace(
    path,
    """        endedRecoveries = 0
        dnsFallbackActive = false
        normalMediaSourceFactory = null
""",
    """        endedRecoveries = 0
        liveStallRecoveries = 0
        liveEverReady = false
        liveBufferLastProgressAtMs = 0L
        liveBufferLastPositionMs = 0L
        dnsFallbackActive = false
        normalMediaSourceFactory = null
""",
)

# 3) Version bump.
path = 'pubspec.yaml'
replace(path, 'version: 1.2.7+19', 'version: 1.2.8+20')
p = ROOT / path
text = p.read_text(encoding='utf-8')
if 'TV FULL PRO 1.2.8+20 live-stability-v20' not in text:
    text += '\n# TV FULL PRO 1.2.8+20 live-stability-v20\n'
p.write_text(text, encoding='utf-8')
