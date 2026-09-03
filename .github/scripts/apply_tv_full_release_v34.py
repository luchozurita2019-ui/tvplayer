from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"Expected block not found in {path}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


def replace_slice(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise SystemExit(f"Slice markers not found in {path}")
    file.write_text(text[:start] + replacement + text[end:], encoding="utf-8")


# Version
replace_once(
    "pubspec.yaml",
    "version: 1.4.1+33",
    "version: 1.4.2+34",
)
with Path("pubspec.yaml").open("a", encoding="utf-8") as handle:
    text = Path("pubspec.yaml").read_text(encoding="utf-8")
    if "# TV FULL PRO 1.4.2+34 EPG + manual refresh + double-back + player grid navigation" not in text:
        handle.write("\n# TV FULL PRO 1.4.2+34 EPG + manual refresh + double-back + player grid navigation\n")

# EPG: compatible endpoints, auth retry, no negative cache.
epg_path = "lib/services/live_epg_service.dart"
replace_once(
    epg_path,
    "import 'xtream_http_client.dart';",
    "import 'xtream_http_client.dart';\nimport 'xtream_service.dart';",
)
replace_slice(
    epg_path,
    "  static const Duration _timeout = Duration(seconds: 5);",
    "\n}\n\nLiveProgramGuide? parseXtreamEpgPayload",
    r'''  static const Duration _timeout = Duration(seconds: 5);
  static const Duration _cacheFreshFor = Duration(minutes: 3);
  static const int _maxCacheEntries = 24;

  final Map<String, _LiveEpgCacheEntry> _cache = <String, _LiveEpgCacheEntry>{};
  final Map<String, Future<LiveProgramGuide?>> _pending =
      <String, Future<LiveProgramGuide?>>{};

  Future<LiveProgramGuide?> loadXtreamNowNext(
    String playlistUrl,
    Channel channel,
  ) async {
    final source = playlistUrl.trim();
    if (source.isEmpty) return null;
    final streamId = _streamIdFromChannel(channel);
    if (streamId == null) return null;

    final key = '$source|$streamId';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.savedAt) < _cacheFreshFor) {
      return cached.guide;
    }

    final existing = _pending[key];
    if (existing != null) return existing;

    final future = _fetchXtream(source, streamId);
    _pending[key] = future;
    try {
      final guide = await future;
      if (guide != null && guide.hasPrograms) {
        _remember(key, guide);
      }
      return guide;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  void clearPlaylist(String playlistUrl) {
    final source = playlistUrl.trim();
    if (source.isEmpty) return;
    final prefix = '$source|';
    _cache.removeWhere((key, value) => key.startsWith(prefix));
    _pending.removeWhere((key, value) => key.startsWith(prefix));
  }

  Future<LiveProgramGuide?> _fetchXtream(
    String playlistUrl,
    String streamId,
  ) async {
    try {
      var connection = await XtreamFastCatalogService.instance
          .connectionForPlaylist(playlistUrl);
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await _fetchWithConnection(connection, streamId);
        } on _XtreamEpgHttpException catch (error) {
          if (attempt > 0 ||
              (error.statusCode != 401 && error.statusCode != 403)) {
            return null;
          }
          XtreamFastCatalogService.instance.invalidateSession(playlistUrl);
          connection = await XtreamFastCatalogService.instance
              .connectionForPlaylist(playlistUrl, forceRefresh: true);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<LiveProgramGuide?> _fetchWithConnection(
    XtreamConnectionResult connection,
    String streamId,
  ) async {
    const actions = <String>['get_short_epg', 'get_simple_data_table'];
    final http.Client client = XtreamHttpClient.instance;

    for (final action in actions) {
      try {
        final uri = _endpoint(
          connection.apiServer,
          username: connection.username,
          password: connection.password,
          streamId: streamId,
          action: action,
        );
        final response = await client
            .get(uri, headers: XtreamHttpClient.jsonHeaders)
            .timeout(_timeout);
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw _XtreamEpgHttpException(response.statusCode);
        }
        if (response.statusCode != 200 || response.body.trim().isEmpty) {
          continue;
        }
        final decoded = jsonDecode(response.body);
        final guide = parseXtreamEpgPayload(decoded);
        if (guide != null && guide.hasPrograms) return guide;
      } on _XtreamEpgHttpException {
        rethrow;
      } catch (_) {
        // Algunos paneles no implementan una de las variantes. Probamos la otra.
      }
    }
    return null;
  }

  Uri _endpoint(
    Uri apiServer, {
    required String username,
    required String password,
    required String streamId,
    required String action,
  }) {
    var prefix = apiServer.path;
    if (prefix.endsWith('/')) prefix = prefix.substring(0, prefix.length - 1);
    final path = prefix.isEmpty ? '/player_api.php' : '$prefix/player_api.php';
    final query = <String, String>{
      'username': username,
      'password': password,
      'action': action,
      'stream_id': streamId,
    };
    if (action == 'get_short_epg') query['limit'] = '4';
    return apiServer.replace(path: path, queryParameters: query, fragment: '');
  }

  String? _streamIdFromChannel(Channel channel) {
    final stored = channel.xtreamStreamId?.trim() ?? '';
    if (RegExp(r'^\d+$').hasMatch(stored)) return stored;

    final uri = Uri.tryParse(channel.url.trim());
    if (uri == null || uri.pathSegments.isEmpty) return null;
    for (final segment in uri.pathSegments.reversed) {
      final match = RegExp(r'^(\d+)(?:\.[A-Za-z0-9]+)?$').firstMatch(segment);
      if (match != null) return match.group(1);
    }
    return null;
  }

  void _remember(String key, LiveProgramGuide guide) {
    _cache.remove(key);
    _cache[key] = _LiveEpgCacheEntry(guide: guide, savedAt: DateTime.now());
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
'''
)
replace_once(
    epg_path,
    "  if (decoded is Map) {\n    rawListings = decoded['epg_listings'] ?? decoded['listings'];\n  }",
    "  if (decoded is Map) {\n    rawListings = decoded['epg_listings'] ?? decoded['listings'];\n    final data = decoded['data'];\n    if (rawListings == null && data is Map) {\n      rawListings = data['epg_listings'] ?? data['listings'];\n    } else if (rawListings == null && data is List) {\n      rawListings = data;\n    }\n  }",
)
replace_once(
    epg_path,
    "class _LiveEpgCacheEntry {\n  final LiveProgramGuide? guide;",
    "class _XtreamEpgHttpException implements Exception {\n  final int statusCode;\n  const _XtreamEpgHttpException(this.statusCode);\n}\n\nclass _LiveEpgCacheEntry {\n  final LiveProgramGuide guide;",
)

# Manual refresh service. Normal navigation remains lazy; this runs only by explicit user action.
manual_service = r'''import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import 'live_epg_service.dart';
import 'section_catalog_service.dart';
import 'xtream_fast_catalog_service.dart';
import 'xtream_live_fast_service.dart';

class ManualPlaylistRefreshService {
  ManualPlaylistRefreshService._();

  static final ManualPlaylistRefreshService instance =
      ManualPlaylistRefreshService._();

  final Map<String, int> _revisions = <String, int>{};
  final Map<String, Future<void>> _pending = <String, Future<void>>{};

  int revisionFor(Playlist playlist) => _revisions[playlist.id] ?? 0;

  Future<void> refresh(Playlist playlist) async {
    final key = '${playlist.id}|${playlist.source.trim()}';
    final existing = _pending[key];
    if (existing != null) return existing;

    final future = _refreshNow(playlist);
    _pending[key] = future;
    try {
      await future;
      _revisions[playlist.id] = (_revisions[playlist.id] ?? 0) + 1;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<void> _refreshNow(Playlist playlist) async {
    if (playlist.sourceType != PlaylistSourceType.xtream) {
      await SectionCatalogService.instance.refreshAll(playlist);
      return;
    }

    LiveEpgService.instance.clearPlaylist(playlist.source);
    XtreamFastCatalogService.instance.invalidateSession(playlist.source);

    var successes = 0;
    Object? lastError;

    try {
      final live = await XtreamLiveFastService.instance.refresh(
        playlist.source,
        forceSessionRefresh: true,
      );
      if (live.channels.isNotEmpty) successes++;
    } catch (error) {
      lastError = error;
    }

    try {
      final movies = await XtreamFastCatalogService.instance.refreshMovies(
        playlist.source,
      );
      if (movies.movies.isNotEmpty) successes++;
    } catch (error) {
      lastError = error;
    }

    try {
      final series = await XtreamFastCatalogService.instance.refreshSeries(
        playlist.source,
      );
      if (series.series.isNotEmpty) successes++;
    } catch (error) {
      lastError = error;
    }

    if (successes == 0) {
      throw Exception(
        'No se pudo actualizar ninguna sección de la lista. ${lastError ?? ''}',
      );
    }
  }
}
'''
Path("lib/services/manual_playlist_refresh_service.dart").write_text(
    manual_service, encoding="utf-8"
)

# Home screen: explicit manual refresh + double Back to exit.
source_path = "lib/screens/source_content_screen.dart"
replace_once(
    source_path,
    "import '../services/device_performance_service.dart';",
    "import '../services/device_performance_service.dart';\nimport '../services/manual_playlist_refresh_service.dart';",
)
replace_once(
    source_path,
    "  Timer? _updatePollTimer;",
    "  Timer? _updatePollTimer;\n  bool _refreshingLists = false;\n  DateTime? _lastBackPressedAt;",
)
replace_once(
    source_path,
    "    return Scaffold(\n      backgroundColor: Colors.transparent,",
    "    return PopScope<void>(\n      canPop: false,\n      onPopInvokedWithResult: (didPop, result) {\n        if (!didPop) unawaited(_handleRootBack());\n      },\n      child: Scaffold(\n      backgroundColor: Colors.transparent,",
)
replace_once(
    source_path,
    "        ),\n      ),\n    );\n  }\n\n  void _prewarmMovies",
    "        ),\n      ),\n      ),\n    );\n  }\n\n  Future<void> _handleRootBack() async {\n    final now = DateTime.now();\n    final previous = _lastBackPressedAt;\n    if (previous != null && now.difference(previous) <= const Duration(seconds: 2)) {\n      await SystemNavigator.pop();\n      return;\n    }\n    _lastBackPressedAt = now;\n    if (!mounted) return;\n    ScaffoldMessenger.of(context)\n      ..hideCurrentSnackBar()\n      ..showSnackBar(\n        const SnackBar(\n          duration: Duration(seconds: 2),\n          content: Text('Presioná Atrás nuevamente para salir de TV FULL PRO.'),\n        ),\n      );\n  }\n\n  Future<void> _refreshLists() async {\n    if (_refreshingLists) return;\n    setState(() => _refreshingLists = true);\n    try {\n      final provider = context.read<IptvProvider>();\n      final selectedId = provider.selectedPlaylistId ?? widget.playlist.id;\n      if (provider.remoteProvisioningSupported) {\n        await provider.syncRemoteServices();\n      }\n      final active = provider.playlistById(selectedId) ??\n          provider.selectedPlaylist ??\n          widget.playlist;\n      await ManualPlaylistRefreshService.instance.refresh(active);\n      if (!mounted) return;\n      ScaffoldMessenger.of(context)\n        ..hideCurrentSnackBar()\n        ..showSnackBar(\n          const SnackBar(\n            content: Text('Listas actualizadas correctamente.'),\n          ),\n        );\n    } catch (_) {\n      if (!mounted) return;\n      ScaffoldMessenger.of(context)\n        ..hideCurrentSnackBar()\n        ..showSnackBar(\n          const SnackBar(\n            content: Text('No se pudieron actualizar las listas. Revisá la conexión e intentá de nuevo.'),\n          ),\n        );\n    } finally {\n      if (mounted) setState(() => _refreshingLists = false);\n    }\n  }\n\n  void _prewarmMovies",
)
replace_once(
    source_path,
    "                    const SizedBox(width: 8),\n                    if (provider.hasMultiplePlaylists) ...[",
    "                    const SizedBox(width: 8),\n                    OutlinedButton.icon(\n                      onPressed: _refreshingLists\n                          ? null\n                          : () => unawaited(_refreshLists()),\n                      icon: _refreshingLists\n                          ? const SizedBox(\n                              width: 16,\n                              height: 16,\n                              child: CircularProgressIndicator(strokeWidth: 2),\n                            )\n                          : const Icon(Icons.refresh_rounded, size: 20),\n                      label: Text(\n                        _refreshingLists ? 'Actualizando…' : 'Actualizar listas',\n                      ),\n                    ),\n                    const SizedBox(width: 8),\n                    if (provider.hasMultiplePlaylists) ...[",
)

# Prepared VOD caches must be invalidated after a manual refresh.
for screen_path, data_type in [
    ("lib/screens/xtream_movies_screen.dart", "Movie"),
    ("lib/screens/xtream_series_screen.dart", "Series"),
]:
    replace_once(
        screen_path,
        "import '../services/device_performance_service.dart';",
        "import '../services/device_performance_service.dart';\nimport '../services/manual_playlist_refresh_service.dart';",
    )
    replace_once(
        screen_path,
        "      final key = widget.playlist.source.trim();",
        "      final key = _preparedCacheKey();",
    )
    replace_once(
        screen_path,
        "    _preparedKey = widget.playlist.source.trim();",
        "    _preparedKey = _preparedCacheKey();",
    )
    marker = f"  void _rememberPrepared(_{data_type}Data data) {{"
    helper = (
        "  String _preparedCacheKey() {\n"
        "    final revision = ManualPlaylistRefreshService.instance\n"
        "        .revisionFor(widget.playlist);\n"
        "    return '${widget.playlist.source.trim()}|$revision';\n"
        "  }\n\n"
        + marker
    )
    replace_once(screen_path, marker, helper)

# EPG parser regression for alternate Xtream response envelope.
test_path = "test/live_epg_service_test.dart"
replace_once(
    test_path,
    "  test('Xtream short EPG gracefully handles missing data', () {",
    "  test('Xtream simple data table envelope maps programming', () {\n    final now = DateTime.fromMillisecondsSinceEpoch(2000 * 1000);\n    final payload = <String, dynamic>{\n      'data': <String, dynamic>{\n        'epg_listings': <Map<String, dynamic>>[\n          <String, dynamic>{\n            'title': 'Programa actual',\n            'start_timestamp': '1900',\n            'stop_timestamp': '2100',\n          },\n          <String, dynamic>{\n            'title': 'Programa siguiente',\n            'start_timestamp': '2100',\n            'stop_timestamp': '2200',\n          },\n        ],\n      },\n    };\n\n    final guide = parseXtreamEpgPayload(payload, clock: now);\n    expect(guide?.now?.title, 'Programa actual');\n    expect(guide?.next?.title, 'Programa siguiente');\n  });\n\n  test('Xtream short EPG gracefully handles missing data', () {",
)

print("TV FULL PRO 1.4.2+34 patch applied")
