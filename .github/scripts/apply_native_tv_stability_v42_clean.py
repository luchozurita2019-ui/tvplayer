from pathlib import Path

ROOT = Path('native-tv-complete')
TV = ROOT / 'app/src/main/java/com/tvfull/pro/TvHomeActivity.kt'
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


tv = load(TV)

# V4.2 CLEAN deliberately keeps the proven V3 Activity/player lifecycle.
# Do not change onStart(), stopPlayback(), releasePlayer(), provisioning or panel loading.

# 1) Never switch Xtream live streams automatically to a fabricated .m3u8 URL.
# The provider's original TS URL remains authoritative during this clean test.
tv = replace_once(
    tv,
    '        if (maybeTryXtreamHlsFallback(reason)) return\n',
    '        // V4.2 CLEAN: stay on the provider original transport; no automatic TS -> HLS switch.\n',
    'disable automatic HLS fallback',
)

old_playback_url = '''    private fun playbackUrlFor(item: ContentItem): String {
        currentPlaybackUsesHls = false
        if (item.section != ContentSection.LIVE || !looksLikeXtreamLiveTs(item.url)) return item.url
        val useHls = forceHlsNextAttempt || isHlsPreferred(item.url)
        forceHlsNextAttempt = false
        if (!useHls) return item.url
        val alternative = xtreamHlsAlternative(item.url) ?: return item.url
        currentPlaybackUsesHls = true
        return alternative
    }
'''
new_playback_url = '''    private fun playbackUrlFor(item: ContentItem): String {
        // V4.2 CLEAN: the original URL supplied by Xtream/M3U is the source of truth.
        // Clear any learned V3 HLS preference so an older installation cannot force .m3u8.
        currentPlaybackUsesHls = false
        forceHlsNextAttempt = false
        if (item.section == ContentSection.LIVE) setHlsPreferred(item.url, false)
        return item.url
    }
'''
tv = replace_once(tv, old_playback_url, new_playback_url, 'force original playback URL')

# 2) VOD gets a longer first-frame window. Live keeps the fast timeout.
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
    '''        handler.postDelayed({
            if (token == startupToken && waitingFirstFrame && lastPlayed?.id == item.id) {
                if (isLiveLike()) {
                    scheduleReconnect("Inicio sin señal")
                } else {
                    scheduleVodRecovery("No llegó el primer frame")
                }
            }
        }, if (isLiveLike(item)) LIVE_START_TIMEOUT else 30_000L)
''',
    'separate live and VOD startup timeout',
)

# 3) Keep V3 player initialization exactly as-is. Only hide the idle spinner visually.
# initPlayer still creates an idle ExoPlayer, but no network stream is opened until
# startPlayback() calls setMediaItem()+prepare().
tv = replace_once(
    tv,
    '''            loading = LinearLayout(this@TvHomeActivity).apply {
                orientation = LinearLayout.VERTICAL
''',
    '''            loading = LinearLayout(this@TvHomeActivity).apply {
                orientation = LinearLayout.VERTICAL
                visibility = View.GONE
''',
    'hide idle loading spinner',
)

# 4) A normal VOD rebuffer keeps the same Media3 session instead of placing a large
# blocking recovery card over the movie. Terminal errors still use V3 recovery logic.
tv = replace_once(
    tv,
    '''                        if (waitingFirstFrame) showLoading("Inicializando…")
                        else if (isLiveLike()) scheduleStallWatch()
                        else showLoading("Recuperando reproducción…")
''',
    '''                        if (waitingFirstFrame) showLoading("Inicializando…")
                        else if (isLiveLike()) scheduleStallWatch()
                        else {
                            hideLoading()
                            showHud()
                        }
''',
    'non-blocking VOD rebuffer UI',
)

save(TV, tv)

gradle = load(GRADLE)
gradle = replace_once(gradle, 'versionCode 9', 'versionCode 12', 'V4.2 version code')
gradle = replace_once(
    gradle,
    "versionName '3.0-native-tv-stability-premium'",
    "versionName '4.2-native-tv-stability-clean'",
    'V4.2 version name',
)
save(GRADLE, gradle)

print('Native TV Stability V4.2 CLEAN patch applied successfully.')
