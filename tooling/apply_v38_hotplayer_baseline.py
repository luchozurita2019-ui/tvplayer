from pathlib import Path
import re


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'{label}: expected text not found in {path}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


player = Path('lib/screens/player_screen.dart')
fetcher = Path('lib/services/m3u_fetcher.dart')
xtream = Path('lib/services/xtream_service.dart')
workflow = Path('.github/workflows/validate-feature-source.yml')

# 1) HotPlayer Mac exposes this browser-style UA in its AOT binary. Keep a VLC
# UA only as a compatibility fallback for servers that specifically prefer it.
replace_once(
    player,
    "const String _defaultUserAgent =\n    'VLC/3.0.20 LibVLC/3.0.20 (iptv_player; +https://github.com)';",
    "const String _defaultUserAgent =\n    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '\n    'AppleWebKit/537.36 (KHTML, like Gecko) '\n    'Chrome/96.0.4664.18 Safari/537.36';\nconst String _legacyVlcUserAgent =\n    'VLC/3.0.20 LibVLC/3.0.20 (iptv_player; +https://github.com)';",
    'default user agent',
)

replace_once(
    player,
    "static const Duration _liveTransientErrorGrace = Duration(seconds: 6);",
    "static const Duration _liveTransientErrorGrace = Duration(seconds: 15);",
    'transient live grace',
)

# 2) Restore mpv native buffering. mpv defaults cache-pause to yes; disabling it
# was making poor connections surface as visible stalls/reopens instead of a
# normal refill cycle.
replace_once(
    player,
    "await platform.setProperty('cache-pause', 'no');",
    "await platform.setProperty('cache-pause', 'yes');",
    'cache-pause',
)

# 3) Do not use aggressive fast probing for live IPTV. HotPlayer does not expose
# custom probesize/probescore strings and format detection is more important than
# shaving a few milliseconds from a live channel open.
replace_once(
    player,
    "_currentOpenUsesFastProbe = _useFastProbe &&\n        !forceNormalProbe &&",
    "_currentOpenUsesFastProbe = !widget.isLiveContent &&\n        _useFastProbe &&\n        !forceNormalProbe &&",
    'disable fast probe for live',
)

# 4) FFmpeg options passed through demuxer-lavf-o must propagate to nested HLS
# connections/segments. V3.7 explicitly disabled this, which breaks providers
# whose playlist opens recursively.
replace_once(
    player,
    "await platform.setProperty('demuxer-lavf-propagate-opts', 'no');",
    "await platform.setProperty('demuxer-lavf-propagate-opts', 'yes');",
    'lavf option propagation',
)

# 5) Keep the HotPlayer-confirmed seg_max_retry=5. Remove our forced last-segment
# start (not observed in HotPlayer). For compatibility modes only, relax unusual
# HLS segment extensions; Direct remains on FFmpeg's safer default allow-list.
old_hls = """        // Hallazgo confirmado en HotPlayer Mac: seg_max_retry=5. Hacemos que
        // FFmpeg reintente el segmento HLS antes de considerar caído el canal.
        // live_start_index=-1 mantiene una reapertura pegada al borde en vivo.
        if (isLiveHls) {
          await platform.setProperty(
            'demuxer-lavf-o',
            'seg_max_retry=$_hlsSegmentRetryCount,live_start_index=-1',
          );
        }

        // En live HTTP la recuperación de transporte trabaja desde la primera
        // apertura, no sólo después de que Flutter reinicie el Media. Esto evita
        // muchos cortes visibles y repeticiones de escenas.
        if (isLiveHttp) {
          final reconnectOptions = <String>[
            'reconnect=1',
            'reconnect_streamed=1',
            'reconnect_on_network_error=1',
            'reconnect_at_eof=1',
            if (recoveryMode) 'reconnect_on_http_error=5xx',
            'reconnect_delay_max=${isAdvanced ? 2 : 1}',
          ].join(',');
          await platform.setProperty('stream-lavf-o', reconnectOptions);
        } else if (recoveryMode) {
          // VOD puede reconectar errores de red, pero nunca reabrimos por EOF:
          // el final de una película o episodio es un final real.
          final reconnectOptions = <String>[
            'reconnect=1',
            'reconnect_streamed=1',
            'reconnect_on_network_error=1',
            'reconnect_on_http_error=5xx',
            'reconnect_delay_max=${isAdvanced ? 2 : 1}',
          ].join(',');
          await platform.setProperty('stream-lavf-o', reconnectOptions);
        }
"""
new_hls = """        // HotPlayer Mac contiene seg_max_retry=5: dejamos que FFmpeg
        // recupere un segmento HLS antes de reconstruir toda la reproducción.
        // En modos de compatibilidad también aceptamos extensiones HLS atípicas,
        // algo frecuente en paneles/proxies IPTV. Direct conserva el filtro
        // estándar de FFmpeg.
        if (isLiveHls) {
          final relaxedHlsExtensions =
              _compatibilityMode != ServerCompatibilityMode.direct;
          final hlsOptions = <String>[
            'seg_max_retry=$_hlsSegmentRetryCount',
            if (relaxedHlsExtensions) 'allowed_extensions=ALL',
          ].join(',');
          await platform.setProperty('demuxer-lavf-o', hlsOptions);
        }

        // V3.8 vuelve a una base más cercana a HotPlayer: no inyectamos una
        // batería global de reconnect_* en stream-lavf-o. Esos flags no aparecen
        // en el binario analizado y en ciertos servidores cambian el tratamiento
        // de EOF/HTTP de forma contraproducente. El fallback de TV FULL queda a
        // nivel de sesión sólo si mpv realmente no logra recuperar.
"""
replace_once(player, old_hls, new_hls, 'HLS/reconnect baseline')

# Remove variables that only existed for the stream-lavf reconnect block.
replace_once(
    player,
    "        final recoveryMode =\n            _compatibilityMode == ServerCompatibilityMode.liveRecovery ||\n                _compatibilityMode == ServerCompatibilityMode.advanced;\n        final isAdvanced =\n            _compatibilityMode == ServerCompatibilityMode.advanced;\n        final isLiveHttp = widget.isLiveContent && _isHttpUrl(channel.url);\n        final isLiveHls = widget.isLiveContent && _looksLikeHls(channel.url);",
    "        final isLiveHls = widget.isLiveContent && _looksLikeHls(channel.url);",
    'remove reconnect-only variables',
)

# _isHttpUrl is no longer used after removing stream-lavf reconnect injection.
text = player.read_text(encoding='utf-8')
text, count = re.subn(
    r"\n  bool _isHttpUrl\(String url\) \{\n    final uri = Uri\.tryParse\(url\);\n    return uri != null && \(uri\.scheme == 'http' \|\| uri\.scheme == 'https'\);\n  \}\n",
    "\n",
    text,
    count=1,
)
if count != 1:
    raise SystemExit('remove _isHttpUrl: expected block not found')
player.write_text(text, encoding='utf-8')

# 6) Give native buffering much more room before the app tears down a live
# session. Restarting Media is the expensive last resort and can cause repeats.
replace_once(
    player,
    "seconds: _stallThreshold.inSeconds < 15\n                ? 15",
    "seconds: _stallThreshold.inSeconds < 30\n                ? 30",
    'live stall grace',
)
replace_once(
    player,
    "seconds: _stallThreshold.inSeconds + 8 < 20\n                ? 20\n                : _stallThreshold.inSeconds + 8,",
    "seconds: _stallThreshold.inSeconds + 20 < 45\n                ? 45\n                : _stallThreshold.inSeconds + 20,",
    'live buffering grace',
)

# If mpv is already in native buffering, the transient error timer must not
# immediately promote/reopen the stream. The watchdog remains the last resort.
replace_once(
    player,
    "          _opening ||\n          _reconnecting ||\n          _errorMessage != null) {",
    "          _opening ||\n          _reconnecting ||\n          _isBuffering ||\n          _errorMessage != null) {",
    'transient buffering guard',
)

# 7) Browser UA by default, with VLC only after compatibility fallback. Explicit
# per-channel UA from the playlist still wins inside resolvedHttpHeaders().
replace_once(
    player,
    "      final headers = channel.resolvedHttpHeaders(_defaultUserAgent);",
    "      final fallbackUserAgent =\n          _compatibilityMode == ServerCompatibilityMode.compatible ||\n                  _compatibilityMode == ServerCompatibilityMode.advanced\n              ? _legacyVlcUserAgent\n              : _defaultUserAgent;\n      final headers = channel.resolvedHttpHeaders(fallbackUserAgent);",
    'per-mode UA fallback',
)

# 8) Remote M3U fetch: many panels reject Dart's default UA or expect a browser.
replace_once(
    fetcher,
    "class M3uFetcher {\n  static final http.Client _client = http.Client();",
    "class M3uFetcher {\n  static const String _browserUserAgent =\n      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '\n      'AppleWebKit/537.36 (KHTML, like Gecko) '\n      'Chrome/96.0.4664.18 Safari/537.36';\n  static final http.Client _client = http.Client();",
    'fetcher UA constant',
)
replace_once(
    fetcher,
    "        final response =\n            await _client.get(Uri.parse(url)).timeout(timeout);\n\n        if (response.statusCode == 200) {",
    "        final response = await _client.get(\n          Uri.parse(url),\n          headers: const {\n            'User-Agent': _browserUserAgent,\n            'Accept': 'application/x-mpegURL,application/vnd.apple.mpegurl,text/plain,*/*',\n          },\n        ).timeout(timeout);\n\n        if (response.statusCode >= 200 && response.statusCode < 300) {",
    'fetcher headers/status',
)

# 9) Xtream auth should use the same provider-friendly UA as HotPlayer-like
# requests instead of advertising TV FULL/1.0 to strict panels.
replace_once(
    xtream,
    "        'User-Agent': 'TV FULL/1.0',",
    "        'User-Agent':\n            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '\n                'AppleWebKit/537.36 (KHTML, like Gecko) '\n                'Chrome/96.0.4664.18 Safari/537.36',",
    'xtream UA',
)

# 10) Build/package this isolated V3.8 branch too.
replace_once(
    workflow,
    "      - performance-engine-v37-compatibility",
    "      - performance-engine-v37-compatibility\n      - performance-engine-v38-hotplayer-baseline",
    'CI V3.8 branch',
)

print('V3.8 HotPlayer baseline patch applied successfully')
