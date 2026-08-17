from pathlib import Path
import re

ROOT = Path('native-tv-complete')
SRC = ROOT / 'app/src/main/java/com/tvfull/pro'
TV = SRC / 'TvHomeActivity.kt'
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


# ===========================================================================
# Build: LibVLC + per-ABI support. V5 runs after Professional V2, Stability V3,
# Premium V3 and V4.2 CLEAN, so all panel/payment/UI features already exist.
# ===========================================================================
gradle = load(GRADLE)
if "org.videolan.android:libvlc-all:3.6.0" not in gradle:
    gradle = replace_once(
        gradle,
        "    implementation 'androidx.media3:media3-ui:1.8.0'\n",
        "    implementation 'androidx.media3:media3-ui:1.8.0'\n"
        "    implementation 'org.videolan.android:libvlc-all:3.6.0'\n",
        'LibVLC dependency',
    )

if 'def tvAbi = project.findProperty' not in gradle:
    gradle = replace_once(
        gradle,
        "plugins {\n    id 'com.android.application'\n    id 'org.jetbrains.kotlin.android'\n}\n",
        "plugins {\n    id 'com.android.application'\n    id 'org.jetbrains.kotlin.android'\n}\n\n"
        "def tvAbi = project.findProperty('tvAbi')\n",
        'ABI project property',
    )
    gradle = replace_once(
        gradle,
        "        targetSdk 34\n",
        "        targetSdk 34\n"
        "        if (tvAbi) {\n"
        "            ndk { abiFilters tvAbi }\n"
        "        }\n",
        'ABI filter',
    )

gradle = replace_once(gradle, 'versionCode 12', 'versionCode 13', 'V5 version code')
gradle = replace_once(
    gradle,
    "versionName '4.2-native-tv-stability-clean'",
    "versionName '5.0-native-tv-hybrid-player'",
    'V5 version name',
)
save(GRADLE, gradle)

proguard = load(PROGUARD)
vlc_rules = '''\n# LibVLC JNI/native bridge used by Native TV V5.\n-keep class org.videolan.libvlc.** { *; }\n-keep interface org.videolan.libvlc.** { *; }\n-keepclasseswithmembernames class * { native <methods>; }\n-dontwarn org.videolan.libvlc.**\n'''
if '-keep class org.videolan.libvlc.**' not in proguard:
    proguard += vlc_rules
save(PROGUARD, proguard)


# ===========================================================================
# TvHomeActivity hybrid engine integration.
# ===========================================================================
tv = load(TV)

# State is added next to the V3 playback state. No provisioning/catalog fields move.
state_anchor = '    private var currentPlaybackUsesHls = false\n'
if state_anchor not in tv:
    raise SystemExit('V3 playback state anchor missing')
tv = replace_once(
    tv,
    state_anchor,
    state_anchor + '''    private lateinit var vlcEngine: LibVlcPlaybackEngine
    private var playingWithVlc = false
    private var vlcCurrentItem: ContentItem? = null
    private var vlcReconnectAttempts = 0
    private var vlcRecoveryToken = 0L
    private var vlcBuffering = false
    private var vlcLastBufferProgressMs = 0L
    private var vlcLastBufferPercent = -1f
    private var vodVlcFallbackTried = false
''',
    'hybrid playback fields',
)

# Add VLC's SurfaceView layer beside Media3, below loading/HUD/overlays.
tv = replace_once(
    tv,
    '            videoFrame.addView(playerView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))\n',
    '''            videoFrame.addView(playerView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            ensureVlcEngine()
            videoFrame.addView(vlcEngine.videoLayout, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
''',
    'VLC video surface',
)

# VLC engine/controller. Surface and playback callbacks are kept on the UI thread.
hybrid_helpers_anchor = '    private fun initPlayer('
if hybrid_helpers_anchor not in tv:
    raise SystemExit('initPlayer anchor missing')

hybrid_helpers = r'''    private fun ensureVlcEngine() {
        if (::vlcEngine.isInitialized) return
        vlcEngine = LibVlcPlaybackEngine(this, object : LibVlcPlaybackEngine.Listener {
            override fun onOpening() = runOnUiThread {
                if (!playingWithVlc) return@runOnUiThread
                logPlaybackEvent("VLC OPENING · motor híbrido")
            }

            override fun onBuffering(percent: Float) = runOnUiThread {
                if (!playingWithVlc) return@runOnUiThread
                vlcBuffering = percent < 99.5f
                val now = System.currentTimeMillis()
                if (percent > vlcLastBufferPercent + 0.5f) {
                    vlcLastBufferPercent = percent
                    vlcLastBufferProgressMs = now
                }
                if (vlcBuffering) {
                    hudBadge.text = "SEÑAL"
                    hudBadge.background = rounded(WARNING, 7f)
                    hudSubtitle.text = "Estabilizando señal · ${percent.toInt().coerceIn(0, 100)}%"
                    showHud()
                    val token = vlcRecoveryToken
                    handler.postDelayed({
                        if (token == vlcRecoveryToken && playingWithVlc && vlcBuffering &&
                            System.currentTimeMillis() - vlcLastBufferProgressMs >= 18_000L
                        ) {
                            scheduleVlcRecovery("Buffer sin progreso")
                        }
                    }, 18_500L)
                }
            }

            override fun onPlaying() = runOnUiThread {
                if (!playingWithVlc) return@runOnUiThread
                waitingFirstFrame = false
                vlcBuffering = false
                vlcReconnectAttempts = 0
                vlcLastBufferPercent = 100f
                vlcLastBufferProgressMs = System.currentTimeMillis()
                hideLoading()
                vlcEngine.videoResolution()?.let { (w, h) ->
                    diagnostics.width = w
                    diagnostics.height = h
                }
                logPlaybackEvent("VLC PLAY confirmado · ${videoResolutionLabel()}")
                showHud()
            }

            override fun onPaused() = runOnUiThread {
                if (playingWithVlc && isFullscreen) showHud()
            }

            override fun onStopped() = Unit

            override fun onEndReached() = runOnUiThread {
                if (!playingWithVlc) return@runOnUiThread
                if (isLiveLike()) scheduleVlcRecovery("EOF de stream")
                else scheduleVlcVodRecovery("Fin inesperado")
            }

            override fun onError() = runOnUiThread {
                if (!playingWithVlc) return@runOnUiThread
                if (isLiveLike()) scheduleVlcRecovery("Error VLC")
                else scheduleVlcVodRecovery("Error VLC")
            }

            override fun onTimeChanged(timeMs: Long) = runOnUiThread {
                if (!playingWithVlc) return@runOnUiThread
                if (!isLiveLike() && timeMs > 0L) lastKnownPositionMs = timeMs
            }
        })
        applyVlcImageMode()
    }

    private fun startVlcPlayback(item: ContentItem, reconnect: Boolean, resumePositionMs: Long = 0L) {
        ensureVlcEngine()
        // Media3 is kept alive for VOD but never owns a live stream in V5.
        player?.stop()
        player?.clearMediaItems()
        playerView.visibility = View.GONE
        vlcEngine.videoLayout.visibility = View.VISIBLE
        playingWithVlc = true
        vlcCurrentItem = item
        lastPlayed = item
        currentEpg = null
        waitingFirstFrame = true
        vlcRecoveryToken++
        vlcBuffering = false
        vlcLastBufferPercent = -1f
        vlcLastBufferProgressMs = System.currentTimeMillis()
        diagnostics.width = 0
        diagnostics.height = 0

        if (!reconnect) {
            vlcReconnectAttempts = 0
            if (!isLiveLike(item)) vodVlcFallbackTried = true
        }

        if (reconnect) {
            hideLoading()
            hudBadge.text = "SEÑAL"
            hudBadge.background = rounded(WARNING, 7f)
            hudSubtitle.text = if (isLiveLike(item)) "Reconectando señal…" else "Recuperando reproducción…"
            showHud()
        } else {
            showLoading("Inicializando…")
        }

        val kind = if (isLiveLike(item)) "LIVE" else "VOD fallback"
        logPlaybackEvent("VLC OPEN $kind" + if (resumePositionMs > 0L) " · resume ${formatTime(resumePositionMs)}" else "")
        applyVlcImageMode()
        vlcEngine.play(item.url, resumePositionMs, live = isLiveLike(item))
        if (item.section == ContentSection.LIVE) loadEpg(item)

        val token = vlcRecoveryToken
        val timeout = if (isLiveLike(item)) 18_000L else 35_000L
        handler.postDelayed({
            if (token == vlcRecoveryToken && playingWithVlc && waitingFirstFrame && lastPlayed?.id == item.id) {
                if (isLiveLike(item)) scheduleVlcRecovery("Sin primer frame")
                else scheduleVlcVodRecovery("Sin primer frame")
            }
        }, timeout)
    }

    private fun scheduleVlcRecovery(reason: String) {
        val item = vlcCurrentItem ?: lastPlayed ?: return
        if (!isLiveLike(item) || !playingWithVlc) return
        if (vlcReconnectAttempts >= 5) {
            waitingFirstFrame = false
            vlcBuffering = false
            logPlaybackEvent("VLC LIVE terminal · $reason")
            showLoading("Canal no disponible")
            return
        }
        vlcReconnectAttempts++
        vlcRecoveryToken++
        val token = vlcRecoveryToken
        val delay = when (vlcReconnectAttempts) {
            1 -> 250L
            2 -> 650L
            3 -> 1_200L
            4 -> 2_200L
            else -> 3_500L
        }
        waitingFirstFrame = true
        vlcBuffering = false
        hideLoading()
        logPlaybackEvent("VLC LIVE recuperación $vlcReconnectAttempts/5 · $reason · URL original")
        hudBadge.text = "SEÑAL"
        hudBadge.background = rounded(WARNING, 7f)
        hudSubtitle.text = "Recuperando señal…"
        showHud()
        handler.postDelayed({
            if (token == vlcRecoveryToken && playingWithVlc && lastPlayed?.id == item.id) {
                startVlcPlayback(item, true)
            }
        }, delay)
    }

    private fun startVlcVodFallback(item: ContentItem, resumePositionMs: Long, reason: String) {
        if (vodVlcFallbackTried) {
            showVodTerminalError(reason)
            return
        }
        vodVlcFallbackTried = true
        logPlaybackEvent("VOD cambia Media3 -> VLC · $reason · resume ${formatTime(resumePositionMs)}")
        startVlcPlayback(item, true, resumePositionMs)
    }

    private fun scheduleVlcVodRecovery(reason: String) {
        val item = vlcCurrentItem ?: lastPlayed ?: return
        if (isLiveLike(item) || !playingWithVlc) return
        val resume = vlcEngine.currentTimeMs().takeIf { it > 0L } ?: lastKnownPositionMs
        lastKnownPositionMs = resume
        if (vlcReconnectAttempts >= 3) {
            waitingFirstFrame = false
            logPlaybackEvent("VLC VOD terminal · $reason · pos ${formatTime(resume)}")
            showLoading("No se pudo continuar")
            return
        }
        vlcReconnectAttempts++
        vlcRecoveryToken++
        val token = vlcRecoveryToken
        val delay = when (vlcReconnectAttempts) {
            1 -> 800L
            2 -> 1_800L
            else -> 3_500L
        }
        logPlaybackEvent("VLC VOD recuperación $vlcReconnectAttempts/3 · $reason · resume ${formatTime(resume)}")
        hideLoading()
        showHud()
        handler.postDelayed({
            if (token == vlcRecoveryToken && playingWithVlc && lastPlayed?.id == item.id) {
                startVlcPlayback(item, true, (resume - 1_500L).coerceAtLeast(0L))
            }
        }, delay)
    }

    private fun isPlaybackPlaying(): Boolean =
        if (playingWithVlc && ::vlcEngine.isInitialized) vlcEngine.isPlaying() else player?.isPlaying == true

    private fun applyVlcImageMode() {
        if (!::vlcEngine.isInitialized) return
        val mode = when (imageMode) {
            AspectRatioFrameLayout.RESIZE_MODE_FILL -> 1
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM -> 2
            else -> 0
        }
        vlcEngine.setScaleMode(mode)
    }

    private fun showVlcPlaybackOptions() {
        if (!playingWithVlc || !::vlcEngine.isInitialized) return
        val options = arrayOf("Audio e idioma", "Subtítulos", "Formato de imagen")
        AlertDialog.Builder(this)
            .setTitle("REPRODUCCIÓN · TV FULL PRO")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> showVlcAudioTracks()
                    1 -> showVlcSubtitleTracks()
                    2 -> showImageModes()
                }
            }
            .setNegativeButton("CERRAR", null)
            .setOnDismissListener { if (isFullscreen) showHud() }
            .show()
    }

    private fun showVlcAudioTracks() {
        val tracks = vlcEngine.audioTracks()
        val selected = vlcEngine.selectedAudioTrack()
        val labels = if (tracks.isEmpty()) arrayOf("No hay pistas alternativas") else
            tracks.map { it.name.ifBlank { "Audio ${it.id}" } + if (it.id == selected) "  ✓" else "" }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("AUDIO / IDIOMA")
            .setItems(labels) { _, which -> if (tracks.indices.contains(which)) vlcEngine.selectAudioTrack(tracks[which].id) }
            .setNegativeButton("VOLVER") { _, _ -> showVlcPlaybackOptions() }
            .show()
    }

    private fun showVlcSubtitleTracks() {
        val tracks = vlcEngine.subtitleTracks()
        val selected = vlcEngine.selectedSubtitleTrack()
        val labels = mutableListOf("Desactivados")
        labels += tracks.map { it.name.ifBlank { "Subtítulo ${it.id}" } + if (it.id == selected) "  ✓" else "" }
        AlertDialog.Builder(this)
            .setTitle("SUBTÍTULOS")
            .setItems(labels.toTypedArray()) { _, which ->
                if (which == 0) vlcEngine.selectSubtitleTrack(-1)
                else tracks.getOrNull(which - 1)?.let { vlcEngine.selectSubtitleTrack(it.id) }
            }
            .setNegativeButton("VOLVER") { _, _ -> showVlcPlaybackOptions() }
            .show()
    }

'''
tv = tv.replace(hybrid_helpers_anchor, hybrid_helpers + hybrid_helpers_anchor, 1)

# V5 policy: Live/Radio -> LibVLC primary. Movies/Series -> Media3 primary.
# Stop/hide the other engine whenever ownership changes.
start_pattern = r'    private fun startPlayback\(item: ContentItem, reconnect: Boolean, resumePositionMs: Long = 0L\) \{.*?\n    \}\n\n(?=    private fun playbackStarted)'
start_match = re.search(start_pattern, tv, flags=re.S)
if not start_match:
    raise SystemExit('V3 startPlayback function not found')
original_start = start_match.group(0)
if 'val p = ensurePlayerFor(item)' not in original_start:
    raise SystemExit('V3 ensurePlayerFor marker missing in startPlayback')
new_start = original_start.replace(
    '    private fun startPlayback(item: ContentItem, reconnect: Boolean, resumePositionMs: Long = 0L) {\n        val p = ensurePlayerFor(item)\n',
    '''    private fun startPlayback(item: ContentItem, reconnect: Boolean, resumePositionMs: Long = 0L) {
        if (isLiveLike(item)) {
            startVlcPlayback(item, reconnect, resumePositionMs)
            return
        }
        if (playingWithVlc && ::vlcEngine.isInitialized) {
            vlcEngine.stop()
            playingWithVlc = false
            vlcCurrentItem = null
        }
        playerView.visibility = View.VISIBLE
        val p = ensurePlayerFor(item)
''',
    1,
)
new_start = new_start.replace(
    '            vodRecoveryAttempts = 0\n',
    '            vodRecoveryAttempts = 0\n            vodVlcFallbackTried = false\n',
    1,
)
tv = tv[:start_match.start()] + new_start + tv[start_match.end():]

# Media3 VOD gets two automatic recoveries; then the alternative decoder takes over.
# This is a real engine fallback, not another infinite retry loop.
tv = replace_once(
    tv,
    '''        if (vodRecoveryAttempts >= MAX_VOD_RECOVERIES) {
            showVodTerminalError("No se pudo recuperar después de $MAX_VOD_RECOVERIES intentos")
            return
        }

        vodRecoveryAttempts++
''',
    '''        if (vodRecoveryAttempts >= 2) {
            startVlcVodFallback(item, lastKnownPositionMs, "Media3 agotó recuperación · $reason")
            return
        }

        vodRecoveryAttempts++
''',
    'VOD engine fallback threshold',
)

# HUD playback state and progress work with either engine.
tv = tv.replace(
    'hudSubtitle.text = "${if (player?.isPlaying == true) "Reproduciendo" else "Pausa"}  ·  ${videoResolutionLabel()}"',
    'hudSubtitle.text = "${if (isPlaybackPlaying()) "Reproduciendo" else "Pausa"}  ·  ${videoResolutionLabel()}"',
    1,
)

update_vod_pattern = r'    private fun updateVodProgress\(\) \{.*?\n    \}\n\n(?=    private fun formatTime)'
new_update_vod = r'''    private fun updateVodProgress() {
        val item = lastPlayed ?: return
        if (item.section == ContentSection.LIVE || item.section == ContentSection.RADIO) return
        val duration: Long
        val position: Long
        if (playingWithVlc && ::vlcEngine.isInitialized) {
            duration = vlcEngine.durationMs()
            position = vlcEngine.currentTimeMs()
        } else {
            val p = player ?: return
            duration = p.duration
            position = p.currentPosition.coerceAtLeast(0)
        }
        vodCurrent.text = formatTime(position)
        if (duration == C.TIME_UNSET || duration <= 0) {
            vodDuration.text = "--:--"
            vodProgress.progress = 0
        } else {
            vodDuration.text = formatTime(duration)
            vodProgress.progress = ((position.toDouble() / duration.toDouble()) * 1000).toInt().coerceIn(0, 1000)
        }
    }

'''
tv = replace_regex(tv, update_vod_pattern, new_update_vod, 'hybrid VOD progress')

seek_pattern = r'    private fun seekVod\(delta: Long\) \{.*?\n    \}\n\n(?=    private fun togglePause)'
new_seek = r'''    private fun seekVod(delta: Long) {
        if (isLiveLike()) return
        if (playingWithVlc && ::vlcEngine.isInitialized) {
            val duration = vlcEngine.durationMs()
            val max = if (duration <= 0L) Long.MAX_VALUE else duration
            vlcEngine.seekTo((vlcEngine.currentTimeMs() + delta).coerceAtLeast(0L).coerceAtMost(max))
            showHud()
            return
        }
        val p = player ?: return
        val duration = p.duration
        val max = if (duration == C.TIME_UNSET || duration <= 0) Long.MAX_VALUE else duration
        p.seekTo((p.currentPosition + delta).coerceAtLeast(0).coerceAtMost(max))
        showHud()
    }

'''
tv = replace_regex(tv, seek_pattern, new_seek, 'hybrid seek')

toggle_pattern = r'    private fun togglePause\(\) \{.*?\n    \}\n\n(?=    private fun enterFullscreen)'
new_toggle = r'''    private fun togglePause() {
        if (playingWithVlc && ::vlcEngine.isInitialized) vlcEngine.togglePause()
        else player?.let { if (it.isPlaying) it.pause() else it.play() }
        showHud()
    }

'''
tv = replace_regex(tv, toggle_pattern, new_toggle, 'hybrid pause')

# Playback options use the engine that actually owns the video.
tv = replace_once(
    tv,
    '''    private fun showPlaybackOptions() {
        if (!isFullscreen || player == null) return
''',
    '''    private fun showPlaybackOptions() {
        if (!isFullscreen) return
        if (playingWithVlc) {
            showVlcPlaybackOptions()
            return
        }
        if (player == null) return
''',
    'hybrid playback options',
)

# Image mode is applied to both surfaces; only the active one is visible.
tv = replace_once(
    tv,
    '''        imageMode = mode
        playerView.resizeMode = mode
        getSharedPreferences("tvfull_player_ui", MODE_PRIVATE).edit().putInt("image_mode", mode).apply()
''',
    '''        imageMode = mode
        playerView.resizeMode = mode
        applyVlcImageMode()
        getSharedPreferences("tvfull_player_ui", MODE_PRIVATE).edit().putInt("image_mode", mode).apply()
''',
    'hybrid image mode',
)

# Stop clears both engines without touching panel/catalog state.
stop_pattern = r'    private fun stopPlayback\(clear: Boolean\) \{.*?\n    \}\n\n(?=    private fun releasePlayer)'
stop_match = re.search(stop_pattern, tv, flags=re.S)
if not stop_match:
    raise SystemExit('stopPlayback not found')
stop_body = stop_match.group(0)
stop_body = stop_body.replace(
    '        reconnectAttempts = 0\n',
    '''        reconnectAttempts = 0
        vlcRecoveryToken++
        vlcReconnectAttempts = 0
        vlcBuffering = false
        if (::vlcEngine.isInitialized) vlcEngine.stop()
        playingWithVlc = false
        vlcCurrentItem = null
        playerView.visibility = View.VISIBLE
''',
    1,
)
tv = tv[:stop_match.start()] + stop_body + tv[stop_match.end():]

# releasePlayer remains Media3 lifecycle only. LibVLC is Activity-owned and released
# exactly once at destruction to avoid rapid detach/recreate churn while browsing.
tv = replace_once(
    tv,
    '''        if (::imageLoader.isInitialized) imageLoader.shutdown()
    }
''',
    '''        if (::imageLoader.isInitialized) imageLoader.shutdown()
        if (::vlcEngine.isInitialized) vlcEngine.release()
    }
''',
    'release VLC on destroy',
)

save(TV, tv)
print('Native TV Hybrid Player V5 patch applied successfully.')
