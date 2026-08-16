from pathlib import Path

ROOT = Path('native-tv-complete')
SRC = ROOT / 'app/src/main/java/com/tvfull/pro'


def load(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def save(path: Path, text: str) -> None:
    path.write_text(text, encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Native TV player/home: professional blue UI + clean fullscreen + HUD + tracks
# ---------------------------------------------------------------------------
tv_path = SRC / 'TvHomeActivity.kt'
tv = load(tv_path)

tv = replace_once(
    tv,
    'import androidx.media3.common.Player\n',
    'import androidx.media3.common.Player\nimport androidx.media3.common.TrackSelectionOverride\n',
    'track override import',
)

# Match the Android TV FULL PRO palette without touching playback engine values.
replacements = {
    'private val BG = Color.rgb(6, 10, 18)': 'private val BG = Color.rgb(7, 11, 18)',
    'private val TOP = Color.rgb(10, 16, 27)': 'private val TOP = Color.rgb(13, 20, 30)',
    'private val PANEL = Color.rgb(13, 21, 34)': 'private val PANEL = Color.rgb(13, 20, 30)',
    'private val PANEL_ALT = Color.rgb(18, 28, 44)': 'private val PANEL_ALT = Color.rgb(17, 27, 40)',
    'private val CARD = Color.rgb(25, 37, 56)': 'private val CARD = Color.rgb(17, 27, 40)',
    'private val BORDER = Color.rgb(48, 65, 91)': 'private val BORDER = Color.rgb(35, 48, 67)',
    'private val TEXT = Color.rgb(241, 245, 250)': 'private val TEXT = Color.rgb(244, 247, 251)',
    'private val MUTED = Color.rgb(154, 167, 187)': 'private val MUTED = Color.rgb(141, 154, 173)',
    'private val ACCENT = Color.rgb(229, 9, 20)': 'private val ACCENT = Color.rgb(22, 168, 255)\n        private val ACCENT_DEEP = Color.rgb(8, 117, 209)\n        private val GOLD = Color.rgb(228, 185, 79)',
    'private val LIVE = Color.rgb(220, 23, 38)': 'private val LIVE = Color.rgb(222, 42, 58)',
}
for old, new in replacements.items():
    if old not in tv:
        raise SystemExit(f'palette marker missing: {old}')
    tv = tv.replace(old, new, 1)

# Keep the informational panel addressable so fullscreen can really become fullscreen.
tv = replace_once(
    tv,
    'private lateinit var infoTitle: TextView\n',
    'private lateinit var infoPanel: LinearLayout\n    private lateinit var infoTitle: TextView\n',
    'info panel field',
)

tv = replace_once(
    tv,
    'private var diagnostics = PlaybackDiagnostics()\n',
    'private var diagnostics = PlaybackDiagnostics()\n    private var imageMode = AspectRatioFrameLayout.RESIZE_MODE_FIT\n',
    'image mode field',
)

tv = replace_once(
    tv,
    'imageLoader = LiteImageLoader(this)\n        setContentView(buildUi())',
    'imageLoader = LiteImageLoader(this)\n        imageMode = getSharedPreferences("tvfull_player_ui", MODE_PRIVATE)\n            .getInt("image_mode", AspectRatioFrameLayout.RESIZE_MODE_FIT)\n        setContentView(buildUi())',
    'load image mode',
)

tv = replace_once(
    tv,
    'resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT',
    'resizeMode = imageMode',
    'player resize mode',
)

tv = replace_once(tv, 'val info = LinearLayout(this@TvHomeActivity).apply {', 'infoPanel = LinearLayout(this@TvHomeActivity).apply {', 'info panel assignment')
tv = replace_once(tv, 'info.addView(infoTitle)\n            info.addView(infoBody)', 'infoPanel.addView(infoTitle)\n            infoPanel.addView(infoBody)', 'info children')
tv = replace_once(
    tv,
    'addView(info, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.30f).apply { topMargin = dp(8) })',
    'addView(infoPanel, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.22f).apply { topMargin = dp(8) })',
    'info panel layout',
)
tv = replace_once(
    tv,
    'addView(videoFrame, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.70f))',
    'addView(videoFrame, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.78f))',
    'video panel weight',
)
tv = replace_once(
    tv,
    'videoFrame.addView(hud, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(126), Gravity.BOTTOM))',
    'videoFrame.addView(hud, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(150), Gravity.BOTTOM))',
    'hud height',
)

# More premium focus language: deep blue surface + bright blue outline.
tv = tv.replace(
    '(v as Button).background = rounded(if (focused) ACCENT else Color.TRANSPARENT, 8f)',
    '(v as Button).background = rounded(if (focused) ACCENT_DEEP else Color.TRANSPARENT, 10f, if (focused) ACCENT else null, if (focused) 2 else 0)',
)
tv = tv.replace(
    'b.background = rounded(if (s == section) Color.rgb(72, 18, 28) else Color.TRANSPARENT, 8f)',
    'b.background = rounded(if (s == section) Color.rgb(7, 55, 92) else Color.TRANSPARENT, 10f, if (s == section) ACCENT else null, if (s == section) 1 else 0)',
)
tv = tv.replace(
    'rounded(if (focused) ACCENT else CARD, 9f, if (focused) ACCENT else BORDER, 1)',
    'rounded(if (focused) ACCENT_DEEP else CARD, 10f, if (focused) ACCENT else BORDER, if (focused) 2 else 1)',
)

# Keep HUD metadata current when decoder reveals the real output size.
tv = replace_once(
    tv,
    'diagnostics.width = videoSize.width\n                diagnostics.height = videoSize.height',
    'diagnostics.width = videoSize.width\n                diagnostics.height = videoSize.height\n                if (::hud.isInitialized && hud.visibility == View.VISIBLE) showHud()',
    'video size HUD refresh',
)

# Live/VOD HUD now carries resolution and TV-first control hints.
tv = replace_once(
    tv,
    'hudSubtitle.text = currentEpg?.title?.ifBlank { "EN VIVO" } ?: "EN VIVO"\n                hudHint.text = "↓ canales · OK pausa · BACK volver"',
    'val program = currentEpg?.title?.ifBlank { "EN VIVO" } ?: "EN VIVO"\n                hudSubtitle.text = "$program  ·  ${videoResolutionLabel()}"\n                hudHint.text = "↑ información · ↓ canales · MENU audio/subtítulos/imagen · BACK volver"',
    'live HUD metadata',
)
tv = replace_once(
    tv,
    'hudSubtitle.text = if (player?.isPlaying == true) "Reproduciendo" else "Pausa"\n                hudHint.text = "← -10s · → +10s · OK pausa · BACK volver"',
    'hudSubtitle.text = "${if (player?.isPlaying == true) "Reproduciendo" else "Pausa"}  ·  ${videoResolutionLabel()}"\n                hudHint.text = "← -10s · → +10s · OK pausa · MENU audio/subtítulos/imagen · BACK volver"',
    'vod HUD metadata',
)

# Fullscreen must contain video/HUD only. No persistent channel information card.
tv = replace_once(
    tv,
    'detailPanel.visibility = View.GONE\n        body.setPadding(0, 0, 0, 0)',
    'detailPanel.visibility = View.GONE\n        infoPanel.visibility = View.GONE\n        body.setPadding(0, 0, 0, 0)',
    'fullscreen hide info panel',
)
tv = replace_once(
    tv,
    'topBar.visibility = View.VISIBLE\n        navRail.visibility = View.VISIBLE\n        body.setPadding(dp(12), dp(10), dp(12), dp(12))',
    'topBar.visibility = View.VISIBLE\n        navRail.visibility = View.VISIBLE\n        infoPanel.visibility = View.VISIBLE\n        body.setPadding(dp(12), dp(10), dp(12), dp(12))',
    'fullscreen restore info panel',
)
tv = replace_once(
    tv,
    '(videoFrame.layoutParams as LinearLayout.LayoutParams).apply { height = 0; weight = 0.70f }.also { videoFrame.layoutParams = it }',
    '(videoFrame.layoutParams as LinearLayout.LayoutParams).apply { height = 0; weight = 0.78f }.also { videoFrame.layoutParams = it }',
    'restore video weight',
)

# Professional player options. Media3 only exposes options that the stream actually has.
anchor = '    private fun showSettings() {\n'
if anchor not in tv:
    raise SystemExit('showSettings anchor missing')
player_options = r'''    private fun videoResolutionLabel(): String {
        val w = diagnostics.width
        val h = diagnostics.height
        if (w <= 0 || h <= 0) return "Resolución automática"
        val quality = when {
            h >= 2160 -> "4K"
            h >= 1080 -> "Full HD"
            h >= 720 -> "HD"
            else -> "SD"
        }
        return "${w}×${h} · $quality"
    }

    private fun showPlaybackOptions() {
        if (!isFullscreen || player == null) return
        handler.removeCallbacks(hideHud)
        showHud()
        val options = arrayOf("Audio e idioma", "Subtítulos", "Formato de imagen")
        AlertDialog.Builder(this)
            .setTitle("REPRODUCCIÓN · TV FULL PRO")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> showAudioTracks()
                    1 -> showSubtitleTracks()
                    2 -> showImageModes()
                }
            }
            .setNegativeButton("CERRAR", null)
            .setOnDismissListener { if (isFullscreen) showHud() }
            .show()
    }

    private fun showAudioTracks() {
        val p = player ?: return
        val groups = p.currentTracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        val labels = mutableListOf("Automático")
        val actions = mutableListOf<() -> Unit>({
            p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                .build()
        })
        groups.forEach { group ->
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue
                val format = group.getTrackFormat(i)
                val selected = if (group.isTrackSelected(i)) "  ✓" else ""
                labels += "${trackDisplayName(format.label, format.language, "Audio ${labels.size}")}$selected"
                actions += {
                    p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
                        .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                        .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                        .build()
                }
            }
        }
        if (labels.size == 1) labels[0] = "No hay pistas de audio alternativas"
        AlertDialog.Builder(this)
            .setTitle("AUDIO / IDIOMA")
            .setItems(labels.toTypedArray()) { _, which -> if (actions.indices.contains(which)) actions[which]() }
            .setNegativeButton("VOLVER") { _, _ -> showPlaybackOptions() }
            .show()
    }

    private fun showSubtitleTracks() {
        val p = player ?: return
        val groups = p.currentTracks.groups.filter { it.type == C.TRACK_TYPE_TEXT }
        val labels = mutableListOf("Desactivados")
        val actions = mutableListOf<() -> Unit>({
            p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
        })
        groups.forEach { group ->
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue
                val format = group.getTrackFormat(i)
                val selected = if (group.isTrackSelected(i)) "  ✓" else ""
                labels += "${trackDisplayName(format.label, format.language, "Subtítulo ${labels.size}")}$selected"
                actions += {
                    p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                        .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                        .build()
                }
            }
        }
        if (labels.size == 1) labels += "El contenido no proporciona subtítulos"
        AlertDialog.Builder(this)
            .setTitle("SUBTÍTULOS")
            .setItems(labels.toTypedArray()) { _, which -> if (actions.indices.contains(which)) actions[which]() }
            .setNegativeButton("VOLVER") { _, _ -> showPlaybackOptions() }
            .show()
    }

    private fun trackDisplayName(label: String?, language: String?, fallback: String): String {
        val cleanLabel = label?.trim().orEmpty()
        val lang = languageName(language)
        return when {
            cleanLabel.isNotBlank() && lang.isNotBlank() && !cleanLabel.equals(lang, true) -> "$cleanLabel · $lang"
            cleanLabel.isNotBlank() -> cleanLabel
            lang.isNotBlank() -> lang
            else -> fallback
        }
    }

    private fun languageName(code: String?): String {
        val value = code?.trim()?.lowercase(Locale.ROOT).orEmpty()
        if (value.isBlank() || value == "und") return ""
        return when (value.substringBefore('-').substringBefore('_')) {
            "es", "spa" -> "Español"
            "en", "eng" -> "Inglés"
            "pt", "por" -> "Portugués"
            "fr", "fra", "fre" -> "Francés"
            "de", "deu", "ger" -> "Alemán"
            "it", "ita" -> "Italiano"
            "ru", "rus" -> "Ruso"
            "ja", "jpn" -> "Japonés"
            "ko", "kor" -> "Coreano"
            "zh", "zho", "chi" -> "Chino"
            "ar", "ara" -> "Árabe"
            else -> code?.uppercase(Locale.ROOT).orEmpty()
        }
    }

    private fun showImageModes() {
        val labels = arrayOf("Ajustar · imagen completa", "Llenar pantalla", "Expandir / Zoom")
        val modes = intArrayOf(
            AspectRatioFrameLayout.RESIZE_MODE_FIT,
            AspectRatioFrameLayout.RESIZE_MODE_FILL,
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM
        )
        AlertDialog.Builder(this)
            .setTitle("FORMATO DE IMAGEN")
            .setSingleChoiceItems(labels, modes.indexOf(imageMode).coerceAtLeast(0)) { dialog, which ->
                applyImageMode(modes[which])
                dialog.dismiss()
                showHud()
            }
            .setNegativeButton("VOLVER") { _, _ -> showPlaybackOptions() }
            .show()
    }

    private fun applyImageMode(mode: Int) {
        imageMode = mode
        playerView.resizeMode = mode
        getSharedPreferences("tvfull_player_ui", MODE_PRIVATE).edit().putInt("image_mode", mode).apply()
    }

'''
tv = tv.replace(anchor, player_options + anchor, 1)

# MENU / INFO opens the real player menu. Existing playback key behavior stays intact.
dispatch_marker = '            when (event.keyCode) {\n                KeyEvent.KEYCODE_BACK -> {'
if dispatch_marker not in tv:
    raise SystemExit('dispatch marker missing')
tv = tv.replace(
    dispatch_marker,
    '            when (event.keyCode) {\n                KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_INFO, KeyEvent.KEYCODE_SETTINGS -> if (isFullscreen && !channelOverlayVisible) { showPlaybackOptions(); return true }\n                KeyEvent.KEYCODE_BACK -> {',
    1,
)

# Any relevant direction/control interaction can wake the HUD again.
tv = replace_once(
    tv,
    'if (isFullscreen && !channelOverlayVisible) {\n                when (event.keyCode) {',
    'if (isFullscreen && !channelOverlayVisible) {\n                if (event.keyCode in listOf(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER)) showHud()\n                when (event.keyCode) {',
    'wake HUD on remote',
)

save(tv_path, tv)


# ---------------------------------------------------------------------------
# Remote payment state. Distinguish PAYMENT_DUE from generic inactive/blocked.
# ---------------------------------------------------------------------------
remote_path = SRC / 'RemoteProvisioning.kt'
remote = load(remote_path)
remote = replace_once(
    remote,
    'enum class RemoteConfigState { READY, UNASSIGNED, DISABLED, INVALID, ERROR }',
    'enum class RemoteConfigState { READY, UNASSIGNED, PAYMENT_DUE, DISABLED, INVALID, ERROR }',
    'payment enum',
)
remote = replace_once(
    remote,
    '403 -> RemoteConfigResult(RemoteConfigState.DISABLED, message = "Dispositivo deshabilitado desde el panel")',
    '403 -> {\n                    val error = runCatching { JSONObject(text).optString("error") }.getOrDefault("")\n                    val message = runCatching { JSONObject(text).optString("message") }.getOrDefault("")\n                    if (error == "payment_due") {\n                        RemoteConfigResult(RemoteConfigState.PAYMENT_DUE, message = message.ifBlank { "Servicio suspendido por falta de pago" })\n                    } else {\n                        RemoteConfigResult(RemoteConfigState.DISABLED, message = message.ifBlank { "Dispositivo deshabilitado desde el panel" })\n                    }\n                }',
    'payment 403 parser',
)
save(remote_path, remote)


# ---------------------------------------------------------------------------
# Provisioning / blocked screen: professional palette and dedicated payment UI.
# ---------------------------------------------------------------------------
prov_path = SRC / 'ProvisioningActivity.kt'
prov = load(prov_path)
prov = replace_once(
    prov,
    'private lateinit var codeText: TextView\n',
    'private lateinit var modeTitle: TextView\n    private lateinit var codeText: TextView\n',
    'mode title field',
)
prov = prov.replace('setBackgroundColor(Color.rgb(12, 20, 36))', 'setBackgroundColor(Color.rgb(7, 11, 18))')
prov = replace_once(
    prov,
    'root.addView(TextView(this).apply {\n            text = "ACTIVACIÓN REMOTA"',
    'modeTitle = TextView(this).apply {\n            text = "ACTIVACIÓN REMOTA"',
    'mode title assignment',
)
prov = replace_once(
    prov,
    'setTextColor(Color.rgb(241, 214, 44))\n        }, LinearLayout.LayoutParams(dp(760), dp(46)))',
    'setTextColor(Color.rgb(22, 168, 255))\n        }\n        root.addView(modeTitle, LinearLayout.LayoutParams(dp(760), dp(46)))',
    'mode title add',
)
prov = prov.replace('setBackgroundColor(Color.rgb(30, 43, 65))', 'setBackgroundColor(Color.rgb(17, 27, 40))')
prov = prov.replace('setBackgroundColor(Color.rgb(38, 53, 76))', 'setBackgroundColor(Color.rgb(17, 27, 40))')
prov = prov.replace('Color.rgb(241, 214, 44)', 'Color.rgb(22, 168, 255)')
prov = prov.replace('setTextColor(if (focused) Color.BLACK else Color.WHITE)', 'setTextColor(Color.WHITE)')

payment_case = '''                    RemoteConfigState.PAYMENT_DUE -> {
                        modeTitle.text = "SERVICIO SUSPENDIDO"
                        modeTitle.setTextColor(Color.rgb(228, 185, 79))
                        statusText.text = result.message.ifBlank { "Tu servicio está suspendido por falta de pago. Regularizá el servicio y elegí REINTENTAR." }
                        statusText.setTextColor(Color.rgb(244, 247, 251))
                        codeText.setTextColor(Color.rgb(228, 185, 79))
                        schedulePoll(15_000)
                    }
'''
case_anchor = '                    RemoteConfigState.DISABLED -> {\n'
if case_anchor not in prov:
    raise SystemExit('disabled provisioning case missing')
prov = prov.replace(case_anchor, payment_case + case_anchor, 1)
prov = replace_once(
    prov,
    'RemoteConfigState.READY -> {\n                        RemotePrefs.enableRemote(this)',
    'RemoteConfigState.READY -> {\n                        modeTitle.text = "ACTIVACIÓN REMOTA"\n                        modeTitle.setTextColor(Color.rgb(22, 168, 255))\n                        statusText.setTextColor(Color.rgb(185, 193, 204))\n                        RemotePrefs.enableRemote(this)',
    'ready resets payment screen',
)
prov = replace_once(
    prov,
    'RemoteConfigState.DISABLED -> {\n                        statusText.text = "Este dispositivo está DESHABILITADO desde el panel."',
    'RemoteConfigState.DISABLED -> {\n                        modeTitle.text = "DISPOSITIVO INACTIVO"\n                        modeTitle.setTextColor(Color.rgb(242, 80, 80))\n                        statusText.text = result.message.ifBlank { "Este dispositivo está inactivo desde el panel." }',
    'inactive screen',
)
save(prov_path, prov)


# ---------------------------------------------------------------------------
# Playlist selector and manual login: same professional palette as Android.
# ---------------------------------------------------------------------------
playlist_path = SRC / 'PlaylistActivity.kt'
playlist = load(playlist_path)
playlist = playlist.replace('Color.rgb(8, 15, 29)', 'Color.rgb(7, 11, 18)')
playlist = playlist.replace('Color.rgb(27, 39, 58)', 'Color.rgb(17, 27, 40)')
playlist = playlist.replace('Color.rgb(91, 108, 134)', 'Color.rgb(35, 48, 67)')
playlist = playlist.replace('Color.rgb(229, 9, 20)', 'Color.rgb(22, 168, 255)')
playlist = playlist.replace('Color.rgb(159, 171, 190)', 'Color.rgb(141, 154, 173)')
playlist = playlist.replace('Color.rgb(70, 20, 30)', 'Color.rgb(7, 55, 92)')
save(playlist_path, playlist)

login_path = SRC / 'LoginActivity.kt'
login = load(login_path)
login = login.replace('Color.rgb(12, 20, 36)', 'Color.rgb(7, 11, 18)')
login = login.replace('Color.rgb(242, 13, 22)', 'Color.rgb(22, 168, 255)')
login = login.replace('Color.rgb(185, 193, 204)', 'Color.rgb(141, 154, 173)')
login = login.replace('Color.rgb(145, 155, 170)', 'Color.rgb(141, 154, 173)')
login = login.replace('Color.rgb(140, 150, 165)', 'Color.rgb(35, 48, 67)')
save(login_path, login)


# Version this as a separate professional TV release.
build_path = ROOT / 'app/build.gradle'
build = load(build_path)
build = replace_once(build, 'versionCode 7', 'versionCode 8', 'version code')
build = replace_once(build, "versionName '1.6-native-xtream-movie-settings'", "versionName '2.0-native-tv-professional'", 'version name')
save(build_path, build)

print('Native TV Professional V2 patch applied successfully')
