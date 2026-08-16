from pathlib import Path
import re

ROOT = Path('native-tv-complete')
SRC = ROOT / 'app/src/main/java/com/tvfull/pro'
TV = SRC / 'TvHomeActivity.kt'
GRADLE = ROOT / 'app/build.gradle'


def load(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def save(path: Path, text: str) -> None:
    path.write_text(text, encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)


def replace_regex(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return updated


tv = load(TV)

# ---------------------------------------------------------------------------
# Imports / constants / state
# ---------------------------------------------------------------------------
tv = replace_once(
    tv,
    'import android.widget.SeekBar\nimport android.widget.TextView\n',
    'import android.widget.SeekBar\nimport android.widget.ScrollView\nimport android.widget.TextView\n',
    'scroll view import',
)
tv = replace_once(
    tv,
    'import androidx.media3.exoplayer.source.DefaultMediaSourceFactory\n',
    'import androidx.media3.exoplayer.source.DefaultMediaSourceFactory\nimport androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy\n',
    'load error policy import',
)

tv = replace_once(
    tv,
    'private const val MAX_RECONNECTS = 4\n',
    'private const val MAX_RECONNECTS = 4\n        private const val MAX_VOD_RECOVERIES = 4\n        private const val HLS_LEARN_STABLE_MS = 12_000L\n        private const val VOD_RECOVERY_RESET_MS = 30_000L\n',
    'stability constants',
)

field_anchor = 'private var imageMode = AspectRatioFrameLayout.RESIZE_MODE_FIT\n'
if field_anchor not in tv:
    # Professional V2 runs before this patch. Fail loudly if build order changes.
    raise SystemExit('professional V2 imageMode marker missing')

tv = replace_once(
    tv,
    field_anchor,
    field_anchor + '''    private var playerProfileLiveLike: Boolean? = null
    private var lastKnownPositionMs = 0L
    private var vodRecoveryAttempts = 0
    private var vodRecoveryToken = 0L
    private var currentPlaybackStartedAtMs = 0L
    private var hlsFallbackTried = false
    private var forceHlsNextAttempt = false
    private var currentPlaybackUsesHls = false
''',
    'stability state fields',
)

# Capture VOD position continuously. This is the recovery point if the server dies.
tv = replace_once(
    tv,
    '''    private val progressTick = object : Runnable {
        override fun run() {
            updateVodProgress()
            handler.postDelayed(this, 500L)
        }
    }
''',
    '''    private val progressTick = object : Runnable {
        override fun run() {
            capturePlaybackPosition()
            updateVodProgress()
            handler.postDelayed(this, 500L)
        }
    }
''',
    'progress position capture',
)

# ---------------------------------------------------------------------------
# Player: separate live/VOD buffering + Media3 load retry policy
# ---------------------------------------------------------------------------
new_init_player = r'''    private fun initPlayer(liveLike: Boolean = true) {
        // Live and VOD have different goals. Live keeps latency bounded but needs
        // enough reserve to absorb Wi-Fi/provider jitter. VOD can safely buffer
        // much farther ahead because there is no live edge to chase.
        val loadControl = DefaultLoadControl.Builder().apply {
            if (liveLike) {
                setBufferDurationsMs(
                    8_000,   // min reserve
                    24_000,  // bounded live reserve
                    2_500,   // initial playback
                    4_000    // after rebuffer: do not resume with only 1 second
                )
            } else {
                setBufferDurationsMs(
                    20_000,  // VOD reserve
                    60_000,  // preload up to one minute when network permits
                    3_000,
                    6_000    // stronger recovery reserve for movies/series
                )
            }
            setPrioritizeTimeOverSizeThresholds(true)
        }.build()

        val renderers = DefaultRenderersFactory(this)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)

        val dataSource = DefaultHttpDataSource.Factory()
            .setUserAgent("Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 Chrome/120 Safari/537.36")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(8_000)
            .setReadTimeoutMs(30_000)

        // Media3 retries individual loads before escalating a terminal player
        // error. We give live slightly more tolerance for segment/network noise.
        val retryPolicy = DefaultLoadErrorHandlingPolicy(if (liveLike) 5 else 4)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSource)
            .setLoadErrorHandlingPolicy(retryPolicy)

        val p = ExoPlayer.Builder(this, renderers)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()

        playerProfileLiveLike = liveLike
        logPlaybackEvent("PLAYER perfil=${if (liveLike) "LIVE 8-24s / rebuffer 4s" else "VOD 20-60s / rebuffer 6s"}")

        p.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_BUFFERING -> {
                        beginBuffering()
                        if (waitingFirstFrame) showLoading("Inicializando…")
                        else if (isLiveLike()) scheduleStallWatch()
                        else showLoading("Recuperando reproducción…")
                    }
                    Player.STATE_READY -> {
                        endBuffering()
                        cancelStallWatch()
                        if (lastPlayed?.section == ContentSection.RADIO && waitingFirstFrame) playbackStarted()
                        if (!waitingFirstFrame) hideLoading()
                    }
                    Player.STATE_ENDED -> {
                        endBuffering()
                        cancelStallWatch()
                        if (isLiveLike()) scheduleReconnect("La señal terminó")
                        else {
                            logPlaybackEvent("VOD finalizado correctamente en ${formatTime(p.currentPosition.coerceAtLeast(0))}")
                            showLoading("Finalizado")
                        }
                    }
                    else -> Unit
                }
            }

            override fun onRenderedFirstFrame() {
                playbackStarted()
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                diagnostics.width = videoSize.width
                diagnostics.height = videoSize.height
                if (::hud.isInitialized && hud.visibility == View.VISIBLE) showHud()
            }

            override fun onPlayerError(error: PlaybackException) {
                handlePlaybackError(error)
            }
        })
        player = p
        playerView.player = p
    }

    private fun ensurePlayerFor(item: ContentItem): ExoPlayer {
        val wantLive = item.section == ContentSection.LIVE || item.section == ContentSection.RADIO
        if (player == null || playerProfileLiveLike != wantLive) {
            if (::playerView.isInitialized) playerView.player = null
            player?.release()
            player = null
            playerProfileLiveLike = null
            initPlayer(wantLive)
        }
        return player ?: error("Player no disponible")
    }

'''
tv = replace_regex(
    tv,
    r'    private fun initPlayer\(\) \{.*?\n    \}\n\n(?=    private fun startPlayback)',
    new_init_player,
    'replace player initialization',
)

# ---------------------------------------------------------------------------
# Playback opening / resume / Xtream TS->HLS fallback
# ---------------------------------------------------------------------------
new_start_playback = r'''    private fun startPlayback(item: ContentItem, reconnect: Boolean, resumePositionMs: Long = 0L) {
        val p = ensurePlayerFor(item)
        if (!reconnect) {
            reconnectAttempts = 0
            vodRecoveryAttempts = 0
            vodRecoveryToken++
            lastKnownPositionMs = 0L
            hlsFallbackTried = false
            forceHlsNextAttempt = false
            diagnostics = PlaybackDiagnostics()
        }
        lastPlayed = item
        currentEpg = null
        waitingFirstFrame = true
        startupToken++
        reconnectToken++
        cancelStallWatch()
        val token = startupToken
        val playbackUrl = playbackUrlFor(item)
        currentPlaybackStartedAtMs = 0L

        val mode = if (currentPlaybackUsesHls) "HLS fallback" else "directo"
        logPlaybackEvent(
            "OPEN $mode · ${if (isLiveLike(item)) "LIVE" else "VOD"}" +
                if (resumePositionMs > 0L) " · resume ${formatTime(resumePositionMs)}" else ""
        )

        showLoading(
            when {
                reconnect && !isLiveLike(item) -> "Recuperando desde ${formatTime(resumePositionMs)}…"
                reconnect -> "Reconectando señal…"
                else -> "Inicializando…"
            }
        )
        p.stop()
        p.clearMediaItems()
        p.setMediaItem(MediaItem.fromUri(playbackUrl))
        if (!isLiveLike(item) && resumePositionMs > 0L) {
            p.seekTo(resumePositionMs)
        }
        p.prepare()
        p.playWhenReady = true
        if (item.section == ContentSection.LIVE) loadEpg(item)

        handler.postDelayed({
            if (token == startupToken && waitingFirstFrame && lastPlayed?.id == item.id) {
                if (isLiveLike()) {
                    scheduleReconnect("Inicio sin señal")
                } else {
                    scheduleVodRecovery("No llegó el primer frame")
                }
            }
        }, LIVE_START_TIMEOUT)
    }

'''
tv = replace_regex(
    tv,
    r'    private fun startPlayback\(item: ContentItem, reconnect: Boolean\) \{.*?\n    \}\n\n(?=    private fun playbackStarted)',
    new_start_playback,
    'replace startPlayback',
)

# Playback-start behavior: learn successful HLS only after it stays stable.
tv = replace_regex(
    tv,
    r'    private fun playbackStarted\(\) \{.*?\n    \}\n\n(?=    private fun scheduleStallWatch)',
    r'''    private fun playbackStarted() {
        waitingFirstFrame = false
        reconnectAttempts = 0
        cancelStallWatch()
        hideLoading()
        currentPlaybackStartedAtMs = System.currentTimeMillis()
        logPlaybackEvent(
            "PLAY confirmado · ${videoResolutionLabel()}" +
                if (currentPlaybackUsesHls) " · HLS" else ""
        )
        showHud()

        val item = lastPlayed
        if (item != null && item.section == ContentSection.LIVE && currentPlaybackUsesHls) {
            val token = startupToken
            handler.postDelayed({
                if (token == startupToken &&
                    lastPlayed?.id == item.id &&
                    currentPlaybackUsesHls &&
                    player?.isPlaying == true
                ) {
                    setHlsPreferred(item.url, true)
                    logPlaybackEvent("HLS estable aprendido para ${safeHost(item.url)}")
                }
            }, HLS_LEARN_STABLE_MS)
        }
    }

''',
    'replace playbackStarted',
)

# Reconnect tries HLS once for real Xtream /live/*.ts streams before repeating TS.
tv = replace_once(
    tv,
    '''    private fun scheduleReconnect(reason: String) {
        val item = lastPlayed ?: return
        if (!isLiveLike()) return
''',
    '''    private fun scheduleReconnect(reason: String) {
        val item = lastPlayed ?: return
        if (!isLiveLike()) return
        if (maybeTryXtreamHlsFallback(reason)) return
''',
    'live HLS fallback hook',
)
tv = replace_once(
    tv,
    'showLoading("Reconectando…")\n        infoTitle.text = item.name',
    'showLoading("Reconectando señal…")\n        logPlaybackEvent("LIVE reconexión $reconnectAttempts/$MAX_RECONNECTS · $reason")\n        infoTitle.text = item.name',
    'live reconnect logging',
)
tv = replace_once(
    tv,
    '''        showLoading("Canal no disponible")
        diagnostics.error = reason
''',
    '''        showLoading("Canal no disponible")
        logPlaybackEvent("LIVE terminal · $reason")
        diagnostics.error = reason
''',
    'terminal live logging',
)

# ---------------------------------------------------------------------------
# VOD recovery + error classification + safe diagnostics
# ---------------------------------------------------------------------------
error_helpers_anchor = '    private fun scheduleStallWatch() {\n'
if error_helpers_anchor not in tv:
    raise SystemExit('scheduleStallWatch anchor missing')

error_helpers = r'''    private fun handlePlaybackError(error: PlaybackException) {
        endBuffering()
        cancelStallWatch()
        val codeName = PlaybackException.getErrorCodeName(error.errorCode)
        val status = httpStatus(error)
        val position = player?.currentPosition?.coerceAtLeast(0) ?: lastKnownPositionMs
        if (!isLiveLike() && position > 0L) lastKnownPositionMs = position
        diagnostics.error = "$codeName ${error.message.orEmpty()}".trim()
        logPlaybackEvent(
            "ERROR $codeName" +
                (status?.let { " · HTTP $it" } ?: "") +
                " · pos ${formatTime(position)}"
        )

        if (isLiveLike()) {
            if (currentPlaybackUsesHls && lastPlayed != null && isHlsPreferred(lastPlayed!!.url)) {
                setHlsPreferred(lastPlayed!!.url, false)
                logPlaybackEvent("HLS aprendido falló; volvemos a TS directo")
            }
            if (status == 401 || status == 403 || status == 404 || status == 410) {
                markUnavailable("HTTP $status")
            } else {
                scheduleReconnect("Error de señal · $codeName")
            }
            return
        }

        waitingFirstFrame = false
        val definitiveHttp = status == 401 || status == 403 || status == 404 || status == 410
        val decoderError = codeName.contains("DECOD", ignoreCase = true)
        if (definitiveHttp || (decoderError && vodRecoveryAttempts >= 1)) {
            showVodTerminalError(
                if (definitiveHttp) "El servidor rechazó el contenido (HTTP $status)"
                else "El dispositivo no pudo decodificar este contenido"
            )
        } else {
            scheduleVodRecovery("$codeName${status?.let { " · HTTP $it" } ?: ""}")
        }
    }

    private fun scheduleVodRecovery(reason: String) {
        val item = lastPlayed ?: return
        if (isLiveLike(item)) return
        val p = player
        val current = p?.currentPosition?.coerceAtLeast(0) ?: 0L
        if (current > lastKnownPositionMs) lastKnownPositionMs = current

        if (vodRecoveryAttempts >= MAX_VOD_RECOVERIES) {
            showVodTerminalError("No se pudo recuperar después de $MAX_VOD_RECOVERIES intentos")
            return
        }

        vodRecoveryAttempts++
        vodRecoveryToken++
        val token = vodRecoveryToken
        val resume = lastKnownPositionMs
        val delay = when (vodRecoveryAttempts) {
            1 -> 750L
            2 -> 1_500L
            3 -> 3_000L
            else -> 5_000L
        }
        p?.stop()
        showLoading("Recuperando reproducción · $vodRecoveryAttempts/$MAX_VOD_RECOVERIES…")
        logPlaybackEvent(
            "VOD recuperación $vodRecoveryAttempts/$MAX_VOD_RECOVERIES · $reason · resume ${formatTime(resume)}"
        )
        handler.postDelayed({
            if (token == vodRecoveryToken && lastPlayed?.id == item.id) {
                startPlayback(item, true, resume)
            }
        }, delay)
    }

    private fun showVodTerminalError(reason: String) {
        waitingFirstFrame = false
        player?.stop()
        diagnostics.error = reason
        logPlaybackEvent("VOD terminal · $reason · pos ${formatTime(lastKnownPositionMs)}")
        showLoading("No se pudo continuar · Abrí ajustes para ver el diagnóstico")
    }

    private fun capturePlaybackPosition() {
        val item = lastPlayed ?: return
        if (isLiveLike(item)) return
        val p = player ?: return
        val position = p.currentPosition
        if (position > 0L) lastKnownPositionMs = position

        if (vodRecoveryAttempts > 0 &&
            currentPlaybackStartedAtMs > 0L &&
            p.isPlaying &&
            System.currentTimeMillis() - currentPlaybackStartedAtMs >= VOD_RECOVERY_RESET_MS
        ) {
            logPlaybackEvent("VOD estable 30s después de recuperación; contador reiniciado")
            vodRecoveryAttempts = 0
            currentPlaybackStartedAtMs = System.currentTimeMillis()
        }
    }

    private fun playbackUrlFor(item: ContentItem): String {
        currentPlaybackUsesHls = false
        if (item.section != ContentSection.LIVE || !looksLikeXtreamLiveTs(item.url)) return item.url
        val useHls = forceHlsNextAttempt || isHlsPreferred(item.url)
        forceHlsNextAttempt = false
        if (!useHls) return item.url
        val alternative = xtreamHlsAlternative(item.url) ?: return item.url
        currentPlaybackUsesHls = true
        return alternative
    }

    private fun maybeTryXtreamHlsFallback(reason: String): Boolean {
        val item = lastPlayed ?: return false
        if (item.section != ContentSection.LIVE || !looksLikeXtreamLiveTs(item.url)) return false
        if (currentPlaybackUsesHls) return false
        if (hlsFallbackTried) return false

        val alternative = xtreamHlsAlternative(item.url) ?: return false
        hlsFallbackTried = true
        forceHlsNextAttempt = true
        reconnectToken++
        val token = reconnectToken
        logPlaybackEvent("LIVE TS inestable · probando HLS en ${safeHost(alternative)} · $reason")
        showLoading("Optimizando señal…")
        handler.postDelayed({
            if (token == reconnectToken && lastPlayed?.id == item.id) startPlayback(item, true)
        }, 450L)
        return true
    }

    private fun looksLikeXtreamLiveTs(url: String): Boolean {
        val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
        val path = uri.path?.lowercase(Locale.ROOT).orEmpty()
        return (uri.scheme == "http" || uri.scheme == "https") &&
            path.contains("/live/") && path.endsWith(".ts")
    }

    private fun xtreamHlsAlternative(url: String): String? {
        if (!looksLikeXtreamLiveTs(url)) return null
        val uri = Uri.parse(url)
        val path = uri.path ?: return null
        return uri.buildUpon().path(path.dropLast(3) + ".m3u8").build().toString()
    }

    private fun hlsPreferenceKey(url: String): String {
        val host = safeHost(url).lowercase(Locale.ROOT)
        return "hls_${host.hashCode()}"
    }

    private fun isHlsPreferred(url: String): Boolean =
        getSharedPreferences("tvfull_playback_profiles", MODE_PRIVATE)
            .getBoolean(hlsPreferenceKey(url), false)

    private fun setHlsPreferred(url: String, preferred: Boolean) {
        val edit = getSharedPreferences("tvfull_playback_profiles", MODE_PRIVATE).edit()
        if (preferred) edit.putBoolean(hlsPreferenceKey(url), true)
        else edit.remove(hlsPreferenceKey(url))
        edit.apply()
    }

    private fun safeHost(url: String): String =
        runCatching { Uri.parse(url).host.orEmpty() }.getOrDefault("").ifBlank { "servidor" }

    private fun logPlaybackEvent(message: String) {
        val item = lastPlayed
        val content = when (item?.section) {
            ContentSection.LIVE -> "LIVE"
            ContentSection.RADIO -> "RADIO"
            ContentSection.MOVIES -> "MOVIE"
            ContentSection.SERIES -> "SERIES"
            null -> "PLAYER"
        }
        val title = item?.name?.take(42).orEmpty()
        val host = item?.url?.let(::safeHost).orEmpty()
        val line = "${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())} | $content | $title | $host | $message"
        val prefs = getSharedPreferences("tvfull_playback_diagnostics", MODE_PRIVATE)
        val previous = prefs.getString("events", "").orEmpty().lineSequence().filter { it.isNotBlank() }.toMutableList()
        previous += line
        val trimmed = previous.takeLast(40).joinToString("\n")
        prefs.edit().putString("events", trimmed).apply()
    }

    private fun showPlaybackDiagnostics() {
        val prefs = getSharedPreferences("tvfull_playback_diagnostics", MODE_PRIVATE)
        val raw = prefs.getString("events", "").orEmpty()
        val text = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 12f
            typeface = Typeface.MONOSPACE
            setPadding(dp(14), dp(12), dp(14), dp(12))
            this.text = raw.ifBlank { "Todavía no hay eventos registrados." }
        }
        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.rgb(8, 13, 22))
            addView(text)
        }
        AlertDialog.Builder(this)
            .setTitle("DIAGNÓSTICO DE REPRODUCCIÓN")
            .setView(scroll)
            .setPositiveButton("BORRAR") { _, _ ->
                prefs.edit().remove("events").apply()
            }
            .setNegativeButton("CERRAR", null)
            .show()
    }

'''
tv = replace_once(tv, error_helpers_anchor, error_helpers + error_helpers_anchor, 'insert recovery helpers')

# Diagnostics entry in settings.
tv = replace_once(
    tv,
    '''        wrap.addView(settingsButton("SINCRONIZAR PANEL") {
            startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
            finish()
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)).apply { topMargin = dp(8) })

''',
    '''        wrap.addView(settingsButton("SINCRONIZAR PANEL") {
            startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
            finish()
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)).apply { topMargin = dp(8) })

        wrap.addView(settingsButton("DIAGNÓSTICO DE REPRODUCCIÓN") {
            showPlaybackDiagnostics()
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)).apply { topMargin = dp(8) })

''',
    'diagnostic settings button',
)

# Stop/release resets pending recovery state without deleting learned server profile.
tv = replace_once(
    tv,
    '''        reconnectAttempts = 0
        player?.stop()
''',
    '''        reconnectAttempts = 0
        vodRecoveryToken++
        vodRecoveryAttempts = 0
        lastKnownPositionMs = 0L
        forceHlsNextAttempt = false
        hlsFallbackTried = false
        player?.stop()
''',
    'stop recovery reset',
)
tv = replace_once(
    tv,
    '''        player?.release()
        player = null
    }

    private fun beginBuffering()''',
    '''        player?.release()
        player = null
        playerProfileLiveLike = null
    }

    private fun beginBuffering()''',
    'release profile reset',
)

# Buffer diagnostics: one event per buffering interval, not every callback.
tv = replace_once(
    tv,
    '''            diagnostics.bufferingStarted = System.currentTimeMillis()
            diagnostics.bufferingCount++
''',
    '''            diagnostics.bufferingStarted = System.currentTimeMillis()
            diagnostics.bufferingCount++
            logPlaybackEvent("BUFFERING inicio · #${diagnostics.bufferingCount}")
''',
    'buffer start logging',
)
tv = replace_once(
    tv,
    '''            diagnostics.bufferingMs += System.currentTimeMillis() - diagnostics.bufferingStarted
            diagnostics.bufferingStarted = 0
''',
    '''            val elapsed = System.currentTimeMillis() - diagnostics.bufferingStarted
            diagnostics.bufferingMs += elapsed
            diagnostics.bufferingStarted = 0
            if (elapsed >= 500L) logPlaybackEvent("BUFFERING recuperado · ${elapsed}ms")
''',
    'buffer recovered logging',
)

# Overload for content-specific checks while keeping all existing callers.
tv = replace_once(
    tv,
    '    private fun isLiveLike() = lastPlayed?.section == ContentSection.LIVE || lastPlayed?.section == ContentSection.RADIO\n',
    '''    private fun isLiveLike() = lastPlayed?.section == ContentSection.LIVE || lastPlayed?.section == ContentSection.RADIO
    private fun isLiveLike(item: ContentItem) = item.section == ContentSection.LIVE || item.section == ContentSection.RADIO
''',
    'isLiveLike overload',
)

save(TV, tv)

# Version is intentionally distinct from Professional V2.
gradle = load(GRADLE)
gradle = replace_once(gradle, "versionCode 8", "versionCode 9", 'version code')
gradle = replace_once(
    gradle,
    "versionName '2.0-native-tv-professional'",
    "versionName '3.0-native-tv-stability-premium'",
    'version name',
)
save(GRADLE, gradle)

print('Native TV Stability V3 engine patch applied successfully.')
