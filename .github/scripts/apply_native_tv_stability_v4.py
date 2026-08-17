from pathlib import Path
import re

ROOT = Path('native-tv-complete')
SRC = ROOT / 'app/src/main/java/com/tvfull/pro'
TV = SRC / 'TvHomeActivity.kt'
PROVISIONING = SRC / 'ProvisioningActivity.kt'
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


# ===========================================================================
# TvHomeActivity: V4 is deliberately targeted. It runs AFTER Professional V2,
# Stability V3 and Premium UI V3. Payment, panel, tracks, image modes and UI
# navigation are not replaced here.
# ===========================================================================
tv = load(TV)

# Network diagnostics + safe HLS probe.
tv = replace_once(
    tv,
    'import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy\n',
    'import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy\n'
    'import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter\n',
    'bandwidth meter import',
)
tv = replace_once(
    tv,
    'import java.text.SimpleDateFormat\n',
    'import java.net.HttpURLConnection\nimport java.net.URL\nimport java.text.SimpleDateFormat\n',
    'HLS probe network imports',
)

# V3 learned HLS after 12 seconds and reused it host-wide. V4 requires a long,
# interruption-free validation and keeps the preference channel-specific.
tv = replace_once(
    tv,
    'private const val HLS_LEARN_STABLE_MS = 12_000L\n        private const val VOD_RECOVERY_RESET_MS = 30_000L\n',
    'private const val HLS_LEARN_STABLE_MS = 90_000L\n'
    '        private const val LIVE_STABLE_RESET_MS = 90_000L\n'
    '        private const val VOD_START_TIMEOUT = 30_000L\n'
    '        private const val VOD_RECOVERY_RESET_MS = 30_000L\n',
    'V4 timing constants',
)

# Runtime live failures survive quick successful reopens. This prevents one EOF
# from being interpreted as proof that TS is bad.
tv = replace_once(
    tv,
    '    private var currentPlaybackUsesHls = false\n',
    '    private var currentPlaybackUsesHls = false\n'
    '    private var liveRuntimeFailures = 0\n'
    '    private var lastLiveInstabilityMs = 0L\n'
    '    private var hlsProbeInFlight = false\n'
    '    private var hlsValidatedForSession = false\n',
    'V4 live stability state',
)

# Do NOT create ExoPlayer just because the Activity became visible.
tv = replace_once(
    tv,
    '''    override fun onStart() {
        super.onStart()
        if (::playerView.isInitialized && player == null) initPlayer()
    }
''',
    '''    override fun onStart() {
        super.onStart()
        // V4: player/decoder/network are created lazily only after the user
        // actually selects a channel, movie, episode or radio stream.
    }
''',
    'lazy player onStart',
)

# The idle player pane must not display an indeterminate spinner.
tv = replace_once(
    tv,
    '''            loading = LinearLayout(this@TvHomeActivity).apply {
                orientation = LinearLayout.VERTICAL
''',
    '''            loading = LinearLayout(this@TvHomeActivity).apply {
                orientation = LinearLayout.VERTICAL
                visibility = View.GONE
''',
    'idle loading hidden',
)

# Keep the last decoded frame while a real recovery is happening. This reduces
# black flashes without pretending the stream is still healthy.
tv = replace_once(
    tv,
    '''                setBackgroundColor(Color.BLACK)
                isFocusable = false
            }
            videoFrame.addView(playerView''',
    '''                setBackgroundColor(Color.BLACK)
                isFocusable = false
                setKeepContentOnPlayerReset(true)
            }
            videoFrame.addView(playerView''',
    'keep last video frame on reset',
)

# VOD gets a longer socket read timeout. Live remains bounded so dead channels
# still fail promptly.
tv = replace_once(
    tv,
    '.setReadTimeoutMs(30_000)\n',
    '.setReadTimeoutMs(if (liveLike) 30_000 else 60_000)\n',
    'separate live/VOD read timeout',
)

# Feed Media3's bandwidth estimator so diagnostics can show real delivery speed.
tv = replace_once(
    tv,
    '''        val retryPolicy = DefaultLoadErrorHandlingPolicy(if (liveLike) 5 else 4)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSource)
            .setLoadErrorHandlingPolicy(retryPolicy)

        val p = ExoPlayer.Builder(this, renderers)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
''',
    '''        val retryPolicy = DefaultLoadErrorHandlingPolicy(if (liveLike) 5 else 4)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSource)
            .setLoadErrorHandlingPolicy(retryPolicy)
        val bandwidthMeter = DefaultBandwidthMeter.getSingletonInstance(this)

        val p = ExoPlayer.Builder(this, renderers)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setBandwidthMeter(bandwidthMeter)
            .build()
''',
    'bandwidth meter player wiring',
)

# Buffering after playback has already started must not throw a full-screen
# loading card over the movie. Media3 keeps its session and buffer intact.
tv = replace_once(
    tv,
    '''                    Player.STATE_BUFFERING -> {
                        beginBuffering()
                        if (waitingFirstFrame) showLoading("Inicializando…")
                        else if (isLiveLike()) scheduleStallWatch()
                        else showLoading("Recuperando reproducción…")
                    }
''',
    '''                    Player.STATE_BUFFERING -> {
                        beginBuffering()
                        if (waitingFirstFrame) {
                            showLoading("Inicializando…")
                        } else if (isLiveLike()) {
                            lastLiveInstabilityMs = System.currentTimeMillis()
                            scheduleStallWatch()
                        } else {
                            // VOD rebuffer != terminal error. Preserve the same
                            // Media3 session and the last video frame.
                            hideLoading()
                            showHud()
                        }
                    }
''',
    'non-destructive VOD buffering UI',
)

# STATE_ENDED in live is treated as a transport EOF and reopened in the same
# mode first. scheduleReconnect V4 decides only after repeated failures whether
# a validated HLS alternative is worth trying.
tv = replace_once(
    tv,
    'if (isLiveLike()) scheduleReconnect("La señal terminó")',
    'if (isLiveLike()) scheduleReconnect("EOF de señal")',
    'live EOF semantics',
)

# Reset the V4 session state only when the user selected new content. A reconnect
# must preserve runtime evidence gathered for that channel.
tv = replace_once(
    tv,
    '''            hlsFallbackTried = false
            forceHlsNextAttempt = false
            diagnostics = PlaybackDiagnostics()
''',
    '''            hlsFallbackTried = false
            forceHlsNextAttempt = false
            liveRuntimeFailures = 0
            lastLiveInstabilityMs = System.currentTimeMillis()
            hlsProbeInFlight = false
            hlsValidatedForSession = false
            diagnostics = PlaybackDiagnostics()
''',
    'reset V4 session state',
)

# Recovery overlays are intentionally subtle. Only the first user-requested open
# owns the large spinner.
tv = replace_regex(
    tv,
    r'''        showLoading\(
            when \{
                reconnect && !isLiveLike\(item\) -> "Recuperando desde \$\{formatTime\(resumePositionMs\)\}…"
                reconnect -> "Reconectando señal…"
                else -> "Inicializando…"
            \}
        \)
''',
    '''        if (reconnect) {
            hideLoading()
            showHud()
            hudBadge.text = "SEÑAL"
            hudBadge.background = rounded(WARNING, 7f)
            hudSubtitle.text = if (isLiveLike(item)) {
                "Recuperando señal…"
            } else {
                "Recuperando desde ${formatTime(resumePositionMs)}…"
            }
        } else {
            showLoading("Inicializando…")
        }
''',
    'subtle reconnect UI',
)

# Live still has the short startup deadline; movies/series receive a full 30s
# before V4 considers that the first frame really failed.
tv = replace_once(
    tv,
    '''        handler.postDelayed({
            if (token == startupToken && waitingFirstFrame && lastPlayed?.id == item.id) {
                if (isLiveLike()) {
                    scheduleReconnect("Inicio sin señal")
                } else {
                    scheduleVodRecovery("No llegó el primer frame")
                }
            }
        }, LIVE_START_TIMEOUT)
''',
    '''        val firstFrameTimeout = if (isLiveLike(item)) LIVE_START_TIMEOUT else VOD_START_TIMEOUT
        handler.postDelayed({
            if (token == startupToken && waitingFirstFrame && lastPlayed?.id == item.id) {
                if (isLiveLike()) {
                    scheduleReconnect("Inicio sin señal")
                } else {
                    scheduleVodRecovery("No llegó el primer frame en ${VOD_START_TIMEOUT / 1000}s")
                }
            }
        }, firstFrameTimeout)
''',
    'separate first frame timeout',
)

# Replace V3's 12-second HLS learning with a 90-second no-instability check.
tv = replace_regex(
    tv,
    r'''    private fun playbackStarted\(\) \{.*?\n    \}\n\n(?=    private fun handlePlaybackError)''',
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

        val item = lastPlayed ?: return
        if (!isLiveLike(item)) return
        val token = startupToken
        handler.postDelayed({
            if (token != startupToken ||
                lastPlayed?.id != item.id ||
                player?.isPlaying != true ||
                waitingFirstFrame
            ) return@postDelayed

            val stableFor = System.currentTimeMillis() - lastLiveInstabilityMs
            if (stableFor < LIVE_STABLE_RESET_MS) return@postDelayed

            if (currentPlaybackUsesHls) {
                setHlsPreferred(item.url, true)
                logPlaybackEvent("HLS validado 90s sin cortes para este canal")
            }
            if (liveRuntimeFailures > 0) {
                logPlaybackEvent("LIVE estable 90s · contador de fallos reiniciado")
            }
            liveRuntimeFailures = 0
        }, LIVE_STABLE_RESET_MS)
    }

''',
    'stable playback learning',
)

# Live errors: a bad experimental HLS must NEVER turn a working TS channel into
# "no disponible". HLS errors immediately return to the original TS. Direct TS
# 401/403/404/410 remain definitive because those came from the real stream URL.
tv = replace_regex(
    tv,
    r'''        if \(isLiveLike\(\)\) \{
            if \(currentPlaybackUsesHls.*?
            return
        \}
''',
    r'''        if (isLiveLike()) {
            val item = lastPlayed ?: return
            lastLiveInstabilityMs = System.currentTimeMillis()

            if (currentPlaybackUsesHls) {
                setHlsPreferred(item.url, false)
                forceHlsNextAttempt = false
                currentPlaybackUsesHls = false
                hlsValidatedForSession = false
                logPlaybackEvent(
                    "HLS falló${status?.let { " · HTTP $it" } ?: ""}; regreso inmediato a TS directo"
                )
                reconnectToken++
                val token = reconnectToken
                handler.postDelayed({
                    if (token == reconnectToken && lastPlayed?.id == item.id) {
                        startPlayback(item, true)
                    }
                }, 180L)
                return
            }

            if (status == 401 || status == 403 || status == 404 || status == 410) {
                markUnavailable("HTTP $status")
            } else {
                scheduleReconnect("Error de señal · $codeName")
            }
            return
        }
''',
    'HLS error return to TS',
)

# Resume a little before the exact failure point. A 1.5s safety margin is much
# friendlier to keyframes/segment boundaries than seeking to a damaged byte edge.
tv = replace_once(
    tv,
    '        val resume = lastKnownPositionMs\n',
    '        val resume = (lastKnownPositionMs - 1_500L).coerceAtLeast(0L)\n',
    'VOD resume safety margin',
)

# Replace host-wide HLS preferences with per-channel hashed preferences. This
# also naturally ignores any bad V3 host-wide preference already stored on TV.
tv = replace_regex(
    tv,
    r'''    private fun hlsPreferenceKey\(url: String\): String \{.*?\n    \}\n''',
    r'''    private fun hlsPreferenceKey(url: String): String {
        val uri = runCatching { Uri.parse(url) }.getOrNull()
        val host = safeHost(url).lowercase(Locale.ROOT)
        val path = uri?.path.orEmpty()
        return "hls_v4_${host.hashCode()}_${path.hashCode()}"
    }
''',
    'channel-specific HLS preference',
)

# V4 direct-first recovery. First and second runtime failures reopen TS. On the
# third failure we probe HLS in the background while TS is reopened. HLS is only
# used on a later failure if the probe returned a real #EXTM3U playlist.
new_schedule_reconnect = r'''    private fun scheduleReconnect(reason: String) {
        val item = lastPlayed ?: return
        if (!isLiveLike()) return

        val runtimeFailure = !waitingFirstFrame
        if (runtimeFailure) {
            liveRuntimeFailures++
            lastLiveInstabilityMs = System.currentTimeMillis()

            if (currentPlaybackUsesHls) {
                setHlsPreferred(item.url, false)
                currentPlaybackUsesHls = false
                forceHlsNextAttempt = false
                hlsValidatedForSession = false
                logPlaybackEvent("HLS terminó/inestable; regreso a TS directo")
            } else if (liveRuntimeFailures >= 3) {
                val useValidatedHls = prepareOrUseHlsFallback(item, reason)
                if (useValidatedHls) {
                    forceHlsNextAttempt = true
                }
            }
        }

        if (reconnectAttempts >= MAX_RECONNECTS) {
            markUnavailable("Máximo de reintentos")
            return
        }
        reconnectAttempts++
        diagnostics.reconnects++
        reconnectToken++
        val token = reconnectToken
        val fastEof = runtimeFailure && reason.contains("EOF", ignoreCase = true)
        val delay = if (fastEof) {
            220L
        } else {
            when (reconnectAttempts) {
                1 -> 600L
                2 -> 1_200L
                3 -> 2_500L
                else -> 4_000L
            }
        }
        hideLoading()
        logPlaybackEvent(
            "LIVE recuperación $reconnectAttempts/$MAX_RECONNECTS · $reason · " +
                "fallos_runtime=$liveRuntimeFailures" +
                if (forceHlsNextAttempt) " · próximo=HLS validado" else " · próximo=TS"
        )
        infoTitle.text = item.name
        infoBody.text = "$reason · recuperación $reconnectAttempts de $MAX_RECONNECTS"
        handler.postDelayed({
            if (token == reconnectToken && lastPlayed?.id == item.id) startPlayback(item, true)
        }, delay)
    }

'''
tv = replace_regex(
    tv,
    r'    private fun scheduleReconnect\(reason: String\) \{.*?\n    \}\n\n(?=    private fun markUnavailable)',
    new_schedule_reconnect,
    'direct-first live recovery',
)

# Replace V3's blind .ts -> .m3u8 switch with a real playlist probe.
new_hls_fallback = r'''    private fun prepareOrUseHlsFallback(item: ContentItem, reason: String): Boolean {
        if (item.section != ContentSection.LIVE || !looksLikeXtreamLiveTs(item.url)) return false
        if (currentPlaybackUsesHls) return false
        if (hlsValidatedForSession) {
            logPlaybackEvent("LIVE usando HLS previamente validado · $reason")
            return true
        }
        if (hlsProbeInFlight || hlsFallbackTried) return false

        val alternative = xtreamHlsAlternative(item.url) ?: return false
        hlsFallbackTried = true
        hlsProbeInFlight = true
        val itemId = item.id
        logPlaybackEvent("LIVE comprobando alternativa HLS sin abandonar TS")

        io.execute {
            val valid = probeHlsPlaylist(alternative)
            runOnUiThread {
                hlsProbeInFlight = false
                if (lastPlayed?.id != itemId) return@runOnUiThread
                hlsValidatedForSession = valid
                if (valid) {
                    logPlaybackEvent("HLS probe OK · se usará sólo si TS vuelve a fallar")
                } else {
                    logPlaybackEvent("HLS probe descartado · no es playlist válida/HTTP 2xx")
                }
            }
        }
        return false
    }

    private fun probeHlsPlaylist(url: String): Boolean {
        val conn = runCatching { URL(url).openConnection() as HttpURLConnection }.getOrNull() ?: return false
        return try {
            conn.connectTimeout = 3_500
            conn.readTimeout = 4_000
            conn.instanceFollowRedirects = true
            conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 Chrome/120 Safari/537.36")
            conn.setRequestProperty("Accept", "application/vnd.apple.mpegurl,application/x-mpegURL,text/plain,*/*")
            conn.setRequestProperty("Connection", "keep-alive")
            val status = conn.responseCode
            if (status !in 200..299) return false
            val input = conn.inputStream
            val bytes = ByteArray(4096)
            val n = input.read(bytes)
            input.close()
            if (n <= 0) return false
            String(bytes, 0, n, Charsets.UTF_8).contains("#EXTM3U", ignoreCase = true)
        } catch (_: Throwable) {
            false
        } finally {
            conn.disconnect()
        }
    }

'''
tv = replace_regex(
    tv,
    r'    private fun maybeTryXtreamHlsFallback\(reason: String\): Boolean \{.*?\n    \}\n\n(?=    private fun looksLikeXtreamLiveTs)',
    new_hls_fallback,
    'validated HLS fallback',
)

# More useful diagnostics: current position, buffer ahead, buffer percentage and
# Media3's estimated delivered bandwidth. No Xtream username/password is logged.
helper_anchor = '    private fun logPlaybackEvent(message: String) {\n'
if helper_anchor not in tv:
    raise SystemExit('logPlaybackEvent anchor missing')

buffer_helper = r'''    private fun playbackBufferSnapshot(): String {
        val p = player ?: return "buffer=n/d"
        val position = p.currentPosition.coerceAtLeast(0L)
        val aheadMs = (p.bufferedPosition - position).coerceAtLeast(0L)
        val estimate = DefaultBandwidthMeter.getSingletonInstance(this).bitrateEstimate
        val bandwidth = if (estimate > 0L) {
            String.format(Locale.US, "%.2f Mbps", estimate / 1_000_000.0)
        } else {
            "n/d"
        }
        return String.format(
            Locale.US,
            "pos=%s · buffer=%.1fs · %d%% · red≈%s",
            formatTime(position),
            aheadMs / 1000.0,
            p.bufferedPercentage,
            bandwidth
        )
    }

'''
tv = replace_once(tv, helper_anchor, buffer_helper + helper_anchor, 'buffer diagnostic helper')

tv = replace_once(
    tv,
    'logPlaybackEvent("BUFFERING inicio · #${diagnostics.bufferingCount}")',
    'logPlaybackEvent("BUFFERING inicio · #${diagnostics.bufferingCount} · ${playbackBufferSnapshot()}")',
    'buffer start snapshot',
)
tv = replace_once(
    tv,
    'if (elapsed >= 500L) logPlaybackEvent("BUFFERING recuperado · ${elapsed}ms")',
    'if (elapsed >= 500L) logPlaybackEvent("BUFFERING recuperado · ${elapsed}ms · ${playbackBufferSnapshot()}")',
    'buffer recovered snapshot',
)

# When playback is explicitly cleared (changing section, leaving VOD, lists),
# release decoder/network resources instead of keeping an idle ExoPlayer around.
tv = replace_once(
    tv,
    '''        player?.stop()
        player?.clearMediaItems()
        if (clear) lastPlayed = null
        currentEpg = null
''',
    '''        player?.stop()
        player?.clearMediaItems()
        if (clear) {
            if (::playerView.isInitialized) playerView.player = null
            player?.release()
            player = null
            playerProfileLiveLike = null
            lastPlayed = null
        }
        currentEpg = null
''',
    'release idle player on clear',
)

save(TV, tv)

# ===========================================================================
# ProvisioningActivity: fully responsive linking screen.
# ===========================================================================
prov = load(PROVISIONING)

new_build_ui = r'''    private fun buildUi(): View {
        val screenWidthDp = resources.configuration.screenWidthDp.coerceAtLeast(320)
        val screenHeightDp = resources.configuration.screenHeightDp.coerceAtLeast(240)
        val compact = screenWidthDp < 820 || screenHeightDp < 520
        val horizontalPaddingDp = (screenWidthDp * 0.055f).toInt().coerceIn(20, 72)
        val verticalPaddingDp = (screenHeightDp * 0.045f).toInt().coerceIn(16, 38)
        val contentWidthDp = (screenWidthDp - horizontalPaddingDp * 2).coerceIn(280, 920)
        val titleSize = if (compact) 28f else 38f
        val subtitleSize = if (compact) 15f else 19f
        val bodySize = if (compact) 14f else 17f
        val codeSize = if (compact) 28f else 36f

        val scroll = android.widget.ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(Color.rgb(7, 11, 18))
            isVerticalScrollBarEnabled = false
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(
                dp(horizontalPaddingDp),
                dp(verticalPaddingDp),
                dp(horizontalPaddingDp),
                dp(verticalPaddingDp)
            )
            minimumHeight = resources.displayMetrics.heightPixels
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(
                dp(if (compact) 20 else 34),
                dp(if (compact) 18 else 28),
                dp(if (compact) 20 else 34),
                dp(if (compact) 18 else 28)
            )
            background = android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.rgb(13, 20, 30), Color.rgb(8, 20, 34))
            ).apply {
                cornerRadius = dp(20).toFloat()
                setStroke(dp(1), Color.rgb(35, 48, 67))
            }
        }

        card.addView(TextView(this).apply {
            text = "TV FULL PRO"
            textSize = titleSize
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            maxLines = 1
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        card.addView(TextView(this).apply {
            text = "ACTIVACIÓN REMOTA"
            textSize = subtitleSize
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(22, 168, 255))
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            letterSpacing = 0.08f
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(if (compact) 5 else 8)
        })

        card.addView(TextView(this).apply {
            text = "Vinculá este televisor desde el panel de TV FULL.\nLas listas y servicios se cargarán automáticamente."
            textSize = bodySize
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 193, 204))
            maxLines = 3
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(if (compact) 10 else 16)
        })

        codeText = TextView(this).apply {
            text = "GENERANDO CÓDIGO…"
            textSize = codeSize
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            maxLines = 1
            setPadding(dp(12), dp(if (compact) 16 else 20), dp(12), dp(if (compact) 16 else 20))
            background = android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.rgb(14, 31, 48), Color.rgb(8, 59, 94))
            ).apply {
                cornerRadius = dp(18).toFloat()
                setStroke(dp(2), Color.rgb(22, 168, 255))
            }
        }
        card.addView(codeText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(if (compact) 14 else 22)
        })

        statusText = TextView(this).apply {
            text = "Registrando dispositivo…"
            textSize = bodySize
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 193, 204))
            maxLines = 3
            setPadding(dp(8), dp(8), dp(8), dp(8))
        }
        card.addView(statusText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(if (compact) 8 else 12)
        })

        val actions = LinearLayout(this).apply {
            orientation = if (contentWidthDp < 620) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        retry = tvButton("REINTENTAR") {
            handler.removeCallbacks(poll)
            val credentials = RemotePrefs.loadCredentials(this)
            if (credentials == null) registerDevice() else syncNow()
        }

        if (contentWidthDp < 620) {
            actions.addView(retry, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(54)))
            actions.addView(tvButton("CONFIGURACIÓN MANUAL") {
                RemotePrefs.disableRemote(this)
                startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
                finish()
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(54)).apply { topMargin = dp(8) })
        } else {
            actions.addView(retry, LinearLayout.LayoutParams(0, dp(56), 1f).apply { marginEnd = dp(8) })
            actions.addView(tvButton("CONFIGURACIÓN MANUAL") {
                RemotePrefs.disableRemote(this)
                startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
                finish()
            }, LinearLayout.LayoutParams(0, dp(56), 1.35f))
        }
        card.addView(actions, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(if (compact) 10 else 16)
        })

        card.addView(TextView(this).apply {
            text = "El televisor consulta el panel automáticamente. No necesitás volver a instalar la aplicación para recibir la asignación."
            textSize = if (compact) 11f else 13f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(130, 142, 160))
            maxLines = 3
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(if (compact) 10 else 14)
        })

        root.addView(card, LinearLayout.LayoutParams(dp(contentWidthDp), ViewGroup.LayoutParams.WRAP_CONTENT))
        scroll.addView(root, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        retry.requestFocus()
        return scroll
    }

'''
prov = replace_regex(
    prov,
    r'    private fun buildUi\(\): View \{.*?\n    \}\n\n(?=    private fun tvButton)',
    new_build_ui,
    'responsive provisioning UI',
)
save(PROVISIONING, prov)

# Distinct install/build identity for this test version.
gradle = load(GRADLE)
gradle = replace_once(gradle, 'versionCode 9', 'versionCode 10', 'V4 version code')
gradle = replace_once(
    gradle,
    "versionName '3.0-native-tv-stability-premium'",
    "versionName '4.0-native-tv-stability'",
    'V4 version name',
)
save(GRADLE, gradle)

print('Native TV Stability V4 targeted fixes applied successfully.')
