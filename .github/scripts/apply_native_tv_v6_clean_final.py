from pathlib import Path
import re

ROOT = Path('native-tv-complete')
SRC = ROOT / 'app/src/main/java/com/tvfull/pro'
TV = SRC / 'TvHomeActivity.kt'
CATALOG = SRC / 'CatalogRepository.kt'
PROV = SRC / 'ProvisioningActivity.kt'
GRADLE = ROOT / 'app/build.gradle'
PROGUARD = ROOT / 'app/proguard-rules.pro'


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


# ---------------------------------------------------------------------------
# Build: one VLC engine, per-ABI APKs.
# ---------------------------------------------------------------------------
gradle = load(GRADLE)
if "org.videolan.android:libvlc-all:3.6.0" not in gradle:
    gradle = replace_once(
        gradle,
        "    implementation 'androidx.media3:media3-ui:1.8.0'\n",
        "    implementation 'androidx.media3:media3-ui:1.8.0'\n    implementation 'org.videolan.android:libvlc-all:3.6.0'\n",
        'libvlc dependency',
    )
if "def tvAbi = project.findProperty('tvAbi')" not in gradle:
    gradle = replace_once(
        gradle,
        "plugins {\n    id 'com.android.application'\n    id 'org.jetbrains.kotlin.android'\n}\n",
        "plugins {\n    id 'com.android.application'\n    id 'org.jetbrains.kotlin.android'\n}\n\ndef tvAbi = project.findProperty('tvAbi')\n",
        'abi property',
    )
    gradle = replace_once(
        gradle,
        '        targetSdk 34\n',
        "        targetSdk 34\n        if (tvAbi) {\n            ndk { abiFilters tvAbi }\n        }\n",
        'abi filter',
    )
gradle = replace_once(gradle, 'versionCode 9', 'versionCode 14', 'version code')
gradle = replace_once(
    gradle,
    "versionName '3.0-native-tv-stability-premium'",
    "versionName '6.0-native-tv-clean-single-engine'",
    'version name',
)
save(GRADLE, gradle)

proguard = load(PROGUARD)
if '-keep class org.videolan.libvlc.**' not in proguard:
    proguard += '''\n# LibVLC single playback engine - Native TV V6.\n-keep class org.videolan.libvlc.** { *; }\n-keep interface org.videolan.libvlc.** { *; }\n-keepclasseswithmembernames class * { native <methods>; }\n-dontwarn org.videolan.libvlc.**\n'''
save(PROGUARD, proguard)


# ---------------------------------------------------------------------------
# Catalog: use the provider's own M3U URL as playback compatibility source.
# ---------------------------------------------------------------------------
cat = load(CATALOG)
cat = replace_once(
    cat,
    '    private var m3uCache: List<ContentItem>? = null\n',
    '    private var m3uCache: List<ContentItem>? = null\n    private val fallbackResolver = FallbackPlaylistResolver(config)\n',
    'fallback resolver field',
)

cat = replace_once(
    cat,
    '                ContentSection.SERIES -> loadXtreamCategories("get_series_categories")\n',
    '''                ContentSection.SERIES -> {
                    val native = loadXtreamCategories("get_series_categories")
                    if (native.size > 1) native else fallbackResolver.seriesCategories().ifEmpty { native }
                }
''',
    'series categories fallback',
)
cat = replace_once(
    cat,
    '                ContentSection.SERIES -> loadSeriesItems(categoryId)\n',
    '''                ContentSection.SERIES -> {
                    val native = runCatching { loadSeriesItems(categoryId) }.getOrDefault(emptyList())
                    if (native.isNotEmpty()) native else fallbackResolver.seriesByCategory(categoryId)
                }
''',
    'series items fallback',
)

# Provider playlist URL wins over a locally reconstructed Xtream stream URL.
cat = replace_once(
    cat,
    '                url = resolveDirectSource(direct) ?: liveUrl(id, ext),\n',
    '                url = resolveDirectSource(direct) ?: fallbackResolver.streamUrl(ContentSection.LIVE, id) ?: liveUrl(id, ext),\n',
    'live provider URL',
)
cat = replace_once(
    cat,
    '                url = resolveDirectSource(direct) ?: movieUrl(id, ext),\n',
    '                url = resolveDirectSource(direct) ?: fallbackResolver.streamUrl(ContentSection.MOVIES, id) ?: movieUrl(id, ext),\n',
    'movie provider URL',
)
cat = replace_once(
    cat,
    '            val playable = resolveDirectSource(direct) ?: movieUrl(movie.id, ext)\n',
    '            val playable = resolveDirectSource(direct) ?: fallbackResolver.streamUrl(ContentSection.MOVIES, movie.id) ?: movieUrl(movie.id, ext)\n',
    'movie details provider URL',
)

new_series_episodes = r'''    fun loadSeriesEpisodes(series: ContentItem): List<ContentItem> {
        if (config.mode != SourceMode.XTREAM || series.seriesId.isBlank()) {
            return fallbackResolver.seriesEpisodes(series.name)
        }

        val native = runCatching {
            val json = JSONObject(fetchText(apiUrl("get_series_info", mapOf("series_id" to series.seriesId)), 8_000, 25_000))
            val raw = json.opt("episodes")
            val out = ArrayList<ContentItem>()

            fun appendEpisode(ep: JSONObject, seasonName: String, index: Int) {
                val info = ep.optJSONObject("info") ?: JSONObject()
                val id = cleanText(ep.opt("id")) ?: cleanText(ep.opt("stream_id")) ?: return
                val ext = cleanExtension(
                    cleanText(ep.opt("container_extension")) ?: cleanText(info.opt("container_extension")),
                    "mp4"
                )
                val epNum = cleanText(ep.opt("episode_num")) ?: cleanText(info.opt("episode_num")) ?: (index + 1).toString()
                val title = cleanText(ep.opt("title")) ?: cleanText(info.opt("title")) ?: "Temporada $seasonName · Episodio $epNum"
                val direct = cleanText(ep.opt("direct_source"))
                    ?: cleanText(info.opt("direct_source"))
                    ?: ""
                out += ContentItem(
                    id = id,
                    name = "T$seasonName · E$epNum · $title",
                    url = resolveDirectSource(direct)
                        ?: fallbackResolver.streamUrl(ContentSection.SERIES, id)
                        ?: seriesUrl(id, ext),
                    section = ContentSection.SERIES,
                    extension = ext,
                    directSource = direct,
                    extra = "Temporada $seasonName"
                )
            }

            when (raw) {
                is JSONObject -> {
                    val seasons = raw.keys().asSequence().toList().sortedBy { it.toIntOrNull() ?: 999 }
                    for (season in seasons) {
                        val arr = raw.optJSONArray(season) ?: continue
                        for (i in 0 until arr.length()) arr.optJSONObject(i)?.let { appendEpisode(it, season, i) }
                    }
                }
                is JSONArray -> {
                    for (i in 0 until raw.length()) {
                        val ep = raw.optJSONObject(i) ?: continue
                        val season = cleanText(ep.opt("season")) ?: cleanText(ep.optJSONObject("info")?.opt("season")) ?: "1"
                        appendEpisode(ep, season, i)
                    }
                }
            }
            out
        }.getOrDefault(emptyList())

        return if (native.isNotEmpty()) native else fallbackResolver.seriesEpisodes(series.name)
    }

'''
cat = replace_regex(
    cat,
    r'    fun loadSeriesEpisodes\(seriesId: String\): List<ContentItem> \{.*?\n    \}\n\n(?=    fun loadShortEpg)',
    new_series_episodes,
    'robust series episodes',
)
save(CATALOG, cat)


# ---------------------------------------------------------------------------
# Player: one VLC engine for every content type. Media3 stays linked only so
# existing UI/API code compiles; it never owns a stream in V6.
# ---------------------------------------------------------------------------
tv = load(TV)
state_anchor = '    private var currentPlaybackUsesHls = false\n'
if state_anchor not in tv:
    raise SystemExit('V3 state anchor missing')
tv = replace_once(
    tv,
    state_anchor,
    state_anchor + '''    private lateinit var stablePlayer: StableVlcPlayer
    private var stableRecoveryAttempts = 0
    private var stableRecoveryToken = 0L
    private var stablePlayedOnce = false
    private var stableStartedAtMs = 0L
''',
    'single engine state',
)

# VLC surface is below loading/HUD, alongside the unused Media3 PlayerView.
tv = replace_once(
    tv,
    '            videoFrame.addView(playerView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))\n',
    '''            videoFrame.addView(playerView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            ensureStablePlayer()
            videoFrame.addView(stablePlayer.videoLayout, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
''',
    'stable player surface',
)

# Spinner must not be visible before content is selected.
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

helpers_anchor = '    private fun initPlayer('
helpers = r'''    private fun ensureStablePlayer() {
        if (::stablePlayer.isInitialized) return
        stablePlayer = StableVlcPlayer(this, object : StableVlcPlayer.Listener {
            override fun onOpening() = runOnUiThread {
                if (lastPlayed != null) logPlaybackEvent("VLC SINGLE · opening · URL original")
            }

            override fun onBuffering(percent: Float) = runOnUiThread {
                if (lastPlayed == null) return@runOnUiThread
                if (percent < 99.5f) {
                    beginBuffering()
                    if (waitingFirstFrame) {
                        showLoading("Inicializando…")
                    } else {
                        hideLoading()
                        showHud()
                        hudBadge.text = "SEÑAL"
                        hudBadge.background = rounded(WARNING, 7f)
                        hudSubtitle.text = "Estabilizando señal · ${percent.toInt().coerceIn(0, 100)}%"
                    }
                } else {
                    endBuffering()
                }
            }

            override fun onPlaying() = runOnUiThread {
                if (lastPlayed == null) return@runOnUiThread
                endBuffering()
                waitingFirstFrame = false
                stablePlayedOnce = true
                stableStartedAtMs = System.currentTimeMillis()
                hideLoading()
                stablePlayer.videoResolution()?.let { (w, h) ->
                    diagnostics.width = w
                    diagnostics.height = h
                }
                logPlaybackEvent("VLC SINGLE · PLAY · ${videoResolutionLabel()}")
                showHud()

                val token = stableRecoveryToken
                val itemId = lastPlayed?.id
                handler.postDelayed({
                    if (token == stableRecoveryToken && itemId == lastPlayed?.id && stablePlayer.isPlaying()) {
                        stableRecoveryAttempts = 0
                    }
                }, 30_000L)
            }

            override fun onPaused() = runOnUiThread { if (isFullscreen) showHud() }
            override fun onStopped() = Unit

            override fun onEndReached() = runOnUiThread {
                val item = lastPlayed ?: return@runOnUiThread
                if (!isLiveLike(item)) {
                    val duration = stablePlayer.durationMs()
                    val pos = stablePlayer.currentTimeMs().takeIf { it > 0L } ?: lastKnownPositionMs
                    if (duration > 0L && (duration - pos) <= 12_000L) {
                        waitingFirstFrame = false
                        logPlaybackEvent("VLC SINGLE · VOD finalizado")
                        showLoading("Finalizado")
                        return@runOnUiThread
                    }
                }
                scheduleStableRecovery("Fin inesperado del stream")
            }

            override fun onError() = runOnUiThread {
                scheduleStableRecovery("Error del motor de reproducción")
            }

            override fun onTimeChanged(timeMs: Long) = runOnUiThread {
                val item = lastPlayed ?: return@runOnUiThread
                if (!isLiveLike(item) && timeMs > 0L) lastKnownPositionMs = timeMs
            }
        })
        applyStableImageMode()
    }

    private fun isPlaybackPlaying(): Boolean = ::stablePlayer.isInitialized && stablePlayer.isPlaying()

    private fun applyStableImageMode() {
        if (!::stablePlayer.isInitialized) return
        val mode = when (imageMode) {
            AspectRatioFrameLayout.RESIZE_MODE_FILL -> 1
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM -> 2
            else -> 0
        }
        stablePlayer.setScaleMode(mode)
    }

    private fun scheduleStableRecovery(reason: String) {
        val item = lastPlayed ?: return
        val live = isLiveLike(item)
        val maxAttempts = if (live) 8 else 5
        val position = if (live) 0L else stablePlayer.currentTimeMs().takeIf { it > 0L } ?: lastKnownPositionMs
        if (!live && position > 0L) lastKnownPositionMs = position

        if (stableRecoveryAttempts >= maxAttempts) {
            waitingFirstFrame = false
            diagnostics.error = reason
            logPlaybackEvent("VLC SINGLE terminal · $reason · intentos=$maxAttempts")
            stablePlayer.stop(false)
            showLoading(if (live) "Canal no disponible" else "No se pudo continuar")
            return
        }

        stableRecoveryAttempts++
        diagnostics.reconnects++
        stableRecoveryToken++
        val token = stableRecoveryToken
        val delay = if (live) {
            when (stableRecoveryAttempts) {
                1 -> 350L
                2 -> 800L
                3 -> 1_500L
                4 -> 2_500L
                5 -> 4_000L
                else -> 6_000L
            }
        } else {
            when (stableRecoveryAttempts) {
                1 -> 800L
                2 -> 1_600L
                3 -> 3_000L
                4 -> 5_000L
                else -> 7_000L
            }
        }

        val resume = if (live) 0L else (position - 1_500L).coerceAtLeast(0L)
        stablePlayer.stop(false)
        waitingFirstFrame = true
        logPlaybackEvent(
            "VLC SINGLE recuperación $stableRecoveryAttempts/$maxAttempts · $reason" +
                if (resume > 0L) " · resume ${formatTime(resume)}" else ""
        )
        if (stablePlayedOnce) {
            hideLoading()
            showHud()
            hudBadge.text = "SEÑAL"
            hudBadge.background = rounded(WARNING, 7f)
            hudSubtitle.text = if (live) "Recuperando señal…" else "Recuperando reproducción…"
        } else {
            showLoading(if (live) "Conectando señal…" else "Cargando contenido…")
        }

        handler.postDelayed({
            if (token == stableRecoveryToken && lastPlayed?.id == item.id) {
                startPlayback(item, true, resume)
            }
        }, delay)
    }

    private fun showStablePlaybackOptions() {
        if (!isFullscreen || !::stablePlayer.isInitialized || !stablePlayer.hasMedia()) return
        handler.removeCallbacks(hideHud)
        showHud()
        val options = arrayOf("Audio e idioma", "Subtítulos", "Formato de imagen")
        AlertDialog.Builder(this)
            .setTitle("REPRODUCCIÓN · TV FULL PRO")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> showStableAudioTracks()
                    1 -> showStableSubtitleTracks()
                    2 -> showImageModes()
                }
            }
            .setNegativeButton("CERRAR", null)
            .setOnDismissListener { if (isFullscreen) showHud() }
            .show()
    }

    private fun showStableAudioTracks() {
        val tracks = stablePlayer.audioTracks()
        val selected = stablePlayer.selectedAudioTrack()
        val labels = if (tracks.isEmpty()) arrayOf("No hay pistas de audio alternativas") else
            tracks.map { it.name.ifBlank { "Audio ${it.id}" } + if (it.id == selected) "  ✓" else "" }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("AUDIO / IDIOMA")
            .setItems(labels) { _, which -> tracks.getOrNull(which)?.let { stablePlayer.selectAudioTrack(it.id) } }
            .setNegativeButton("VOLVER") { _, _ -> showStablePlaybackOptions() }
            .show()
    }

    private fun showStableSubtitleTracks() {
        val tracks = stablePlayer.subtitleTracks()
        val selected = stablePlayer.selectedSubtitleTrack()
        val labels = mutableListOf("Desactivados")
        labels += tracks.map { it.name.ifBlank { "Subtítulo ${it.id}" } + if (it.id == selected) "  ✓" else "" }
        AlertDialog.Builder(this)
            .setTitle("SUBTÍTULOS")
            .setItems(labels.toTypedArray()) { _, which ->
                if (which == 0) stablePlayer.selectSubtitleTrack(-1)
                else tracks.getOrNull(which - 1)?.let { stablePlayer.selectSubtitleTrack(it.id) }
            }
            .setNegativeButton("VOLVER") { _, _ -> showStablePlaybackOptions() }
            .show()
    }

'''
tv = replace_once(tv, helpers_anchor, helpers + helpers_anchor, 'insert single engine helpers')

# Every content type now enters the same engine; no fallback engine exists.
new_start = r'''    private fun startPlayback(item: ContentItem, reconnect: Boolean, resumePositionMs: Long = 0L) {
        ensureStablePlayer()
        if (!reconnect) {
            reconnectAttempts = 0
            vodRecoveryAttempts = 0
            stableRecoveryAttempts = 0
            stablePlayedOnce = false
            lastKnownPositionMs = 0L
            diagnostics = PlaybackDiagnostics()
        }
        lastPlayed = item
        currentEpg = null
        waitingFirstFrame = true
        startupToken++
        reconnectToken++
        stableRecoveryToken++
        cancelStallWatch()
        val token = stableRecoveryToken

        player?.stop()
        player?.clearMediaItems()
        playerView.visibility = View.GONE
        stablePlayer.videoLayout.visibility = View.VISIBLE
        applyStableImageMode()

        if (!reconnect || !stablePlayedOnce) showLoading(if (reconnect) "Reconectando…" else "Inicializando…")
        else hideLoading()

        val live = isLiveLike(item)
        val resume = if (live) 0L else resumePositionMs.coerceAtLeast(0L)
        logPlaybackEvent(
            "VLC SINGLE OPEN · ${if (live) "LIVE" else "VOD"} · URL proveedor" +
                if (resume > 0L) " · resume ${formatTime(resume)}" else ""
        )
        stablePlayer.play(item.url, live, resume)
        if (item.section == ContentSection.LIVE) loadEpg(item)

        handler.postDelayed({
            if (token == stableRecoveryToken && waitingFirstFrame && lastPlayed?.id == item.id) {
                scheduleStableRecovery("No llegó el primer frame")
            }
        }, if (live) 22_000L else 40_000L)
    }

'''
tv = replace_regex(
    tv,
    r'    private fun startPlayback\(item: ContentItem, reconnect: Boolean, resumePositionMs: Long = 0L\) \{.*?\n    \}\n\n(?=    private fun playbackStarted)',
    new_start,
    'replace playback opening',
)

# Live fullscreen must query the engine that really owns playback.
tv = replace_once(
    tv,
    'if (lastPlayed?.id == item.id && player?.isPlaying == true) enterFullscreen()',
    'if (lastPlayed?.id == item.id && isPlaybackPlaying()) enterFullscreen()',
    'live fullscreen condition',
)

# Series loader receives the whole item, enabling M3U-name fallback.
tv = replace_once(
    tv,
    'val result = runCatching { repository.loadSeriesEpisodes(series.seriesId) }',
    'val result = runCatching { repository.loadSeriesEpisodes(series) }',
    'series episode call',
)

# HUD/progress/seek/pause all read the single engine.
tv = tv.replace(
    'hudSubtitle.text = "${if (player?.isPlaying == true) "Reproduciendo" else "Pausa"}  ·  ${videoResolutionLabel()}"',
    'hudSubtitle.text = "${if (isPlaybackPlaying()) "Reproduciendo" else "Pausa"}  ·  ${videoResolutionLabel()}"',
    1,
)

new_progress = r'''    private fun updateVodProgress() {
        val item = lastPlayed ?: return
        if (item.section == ContentSection.LIVE || item.section == ContentSection.RADIO) return
        if (!::stablePlayer.isInitialized) return
        val duration = stablePlayer.durationMs()
        val position = stablePlayer.currentTimeMs()
        vodCurrent.text = formatTime(position)
        if (duration <= 0L) {
            vodDuration.text = "--:--"
            vodProgress.progress = 0
        } else {
            vodDuration.text = formatTime(duration)
            vodProgress.progress = ((position.toDouble() / duration.toDouble()) * 1000).toInt().coerceIn(0, 1000)
        }
    }

'''
tv = replace_regex(tv, r'    private fun updateVodProgress\(\) \{.*?\n    \}\n\n(?=    private fun formatTime)', new_progress, 'single engine VOD progress')

new_seek = r'''    private fun seekVod(delta: Long) {
        if (isLiveLike() || !::stablePlayer.isInitialized) return
        val duration = stablePlayer.durationMs()
        val max = if (duration <= 0L) Long.MAX_VALUE else duration
        stablePlayer.seekTo((stablePlayer.currentTimeMs() + delta).coerceAtLeast(0L).coerceAtMost(max))
        showHud()
    }

'''
tv = replace_regex(tv, r'    private fun seekVod\(delta: Long\) \{.*?\n    \}\n\n(?=    private fun togglePause)', new_seek, 'single engine seek')

tv = replace_regex(
    tv,
    r'    private fun togglePause\(\) \{.*?\n    \}\n\n(?=    private fun enterFullscreen)',
    '''    private fun togglePause() {
        if (::stablePlayer.isInitialized) stablePlayer.togglePause()
        showHud()
    }

''',
    'single engine pause',
)

# Professional playback menu stays, but delegates to VLC tracks.
tv = replace_once(
    tv,
    '''    private fun showPlaybackOptions() {
        if (!isFullscreen || player == null) return
''',
    '''    private fun showPlaybackOptions() {
        if (!isFullscreen) return
        showStablePlaybackOptions()
        return
''',
    'single engine playback options',
)

tv = replace_once(
    tv,
    '''        imageMode = mode
        playerView.resizeMode = mode
        getSharedPreferences("tvfull_player_ui", MODE_PRIVATE).edit().putInt("image_mode", mode).apply()
''',
    '''        imageMode = mode
        playerView.resizeMode = mode
        applyStableImageMode()
        getSharedPreferences("tvfull_player_ui", MODE_PRIVATE).edit().putInt("image_mode", mode).apply()
''',
    'single engine image mode',
)

# Stop both UI surfaces cleanly, but never swap engines.
tv = replace_once(
    tv,
    '''        reconnectAttempts = 0
        player?.stop()
        player?.clearMediaItems()
''',
    '''        reconnectAttempts = 0
        stableRecoveryToken++
        stableRecoveryAttempts = 0
        if (::stablePlayer.isInitialized) stablePlayer.stop()
        stablePlayedOnce = false
        player?.stop()
        player?.clearMediaItems()
        playerView.visibility = View.VISIBLE
''',
    'single engine stop',
)

# Leaving the Activity stops playback; engine is released exactly once on destroy.
tv = replace_once(
    tv,
    '''    override fun onStop() {
        super.onStop()
        releasePlayer()
    }
''',
    '''    override fun onStop() {
        super.onStop()
        if (::stablePlayer.isInitialized) stablePlayer.stop()
        releasePlayer()
    }
''',
    'stop stable engine on Activity stop',
)

tv = replace_once(
    tv,
    '''        if (::imageLoader.isInitialized) imageLoader.shutdown()
    }
''',
    '''        if (::imageLoader.isInitialized) imageLoader.shutdown()
        if (::stablePlayer.isInitialized) stablePlayer.release()
    }
''',
    'release stable engine',
)

save(TV, tv)


# ---------------------------------------------------------------------------
# Provisioning: responsive without changing polling/panel/payment logic.
# ---------------------------------------------------------------------------
prov = load(PROV)
responsive_build = r'''    private fun buildUi(): View {
        val dm = resources.displayMetrics
        val widthDp = (dm.widthPixels / dm.density).toInt()
        val heightDp = (dm.heightPixels / dm.density).toInt()
        val side = when {
            widthDp >= 1200 -> dp(72)
            widthDp >= 800 -> dp(48)
            else -> dp(24)
        }
        val vertical = when {
            heightDp >= 700 -> dp(34)
            heightDp >= 520 -> dp(22)
            else -> dp(12)
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(side, vertical, side, vertical)
            setBackgroundColor(Color.rgb(12, 20, 36))
        }

        root.addView(TextView(this).apply {
            text = "TV FULL PRO"
            textSize = if (heightDp < 520) 28f else 36f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            maxLines = 1
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(4) })

        root.addView(TextView(this).apply {
            text = "ACTIVACIÓN REMOTA"
            textSize = if (heightDp < 520) 15f else 18f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(22, 168, 255))
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(8) })

        root.addView(TextView(this).apply {
            text = "Vinculá este dispositivo desde el panel de TV FULL.\nLas listas y servicios se cargarán automáticamente."
            textSize = if (heightDp < 520) 13f else 15f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 193, 204))
            maxLines = 3
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(12) })

        codeText = TextView(this).apply {
            text = "GENERANDO CÓDIGO…"
            textSize = if (widthDp < 700) 25f else 31f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.rgb(30, 43, 65))
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(dp(14), dp(12), dp(14), dp(12))
            maxLines = 1
        }
        root.addView(codeText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(10) })

        statusText = TextView(this).apply {
            text = "Registrando dispositivo…"
            textSize = if (heightDp < 520) 13f else 15f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 193, 204))
            maxLines = 3
        }
        root.addView(statusText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(10) })

        val actions = LinearLayout(this).apply {
            orientation = if (widthDp >= 680) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        retry = tvButton("REINTENTAR") {
            handler.removeCallbacks(poll)
            val credentials = RemotePrefs.loadCredentials(this)
            if (credentials == null) registerDevice() else syncNow()
        }
        val manual = tvButton("CONFIGURACIÓN MANUAL") {
            RemotePrefs.disableRemote(this)
            startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
            finish()
        }
        if (widthDp >= 680) {
            actions.addView(retry, LinearLayout.LayoutParams(0, dp(54), 1f).apply { marginEnd = dp(8) })
            actions.addView(manual, LinearLayout.LayoutParams(0, dp(54), 1f))
        } else {
            actions.addView(retry, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(50)).apply { bottomMargin = dp(6) })
            actions.addView(manual, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(50)))
        }
        root.addView(actions, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        root.addView(TextView(this).apply {
            text = "El dispositivo consulta el panel automáticamente."
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(130, 142, 160))
            maxLines = 2
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(8) })

        retry.requestFocus()
        return root
    }

'''
prov = replace_regex(
    prov,
    r'    private fun buildUi\(\): View \{.*?\n    \}\n\n(?=    private fun tvButton)',
    responsive_build,
    'responsive provisioning UI',
)
save(PROV, prov)

print('Native TV V6 CLEAN FINAL patch applied successfully.')
