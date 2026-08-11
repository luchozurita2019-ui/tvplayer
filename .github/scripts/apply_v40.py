from pathlib import Path
import re


def replace_between(text, start_marker, end_marker, replacement, label):
    try:
        start = text.index(start_marker)
        end = text.index(end_marker, start)
    except ValueError as exc:
        raise SystemExit(f"No se pudo localizar {label}: {exc}")
    return text[:start] + replacement + text[end:]


# ---------------------------------------------------------------------------
# 1) HTTP Xtream: pool nativo explícito, keep-alive y reinicio limpio.
# ---------------------------------------------------------------------------
Path("lib/services/xtream_http_client.dart").write_text(
    r'''import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Cliente HTTP compartido para Xtream.
///
/// La v40 usa explícitamente dart:io/IOClient para tener un pool nativo
/// predecible: keep-alive, gzip automático, conexiones limitadas por host y
/// timeouts de conexión/idle. [instance] es estable aunque el pool interno se
/// reinicie al priorizar reproducción sobre navegación.
class XtreamHttpClient {
  XtreamHttpClient._();

  static final _RestartableXtreamClient instance = _RestartableXtreamClient();

  static void cancelBrowsingRequests() => instance.restart();

  static const String browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  static const Map<String, String> jsonHeaders = <String, String>{
    'User-Agent': browserUserAgent,
    'Accept': 'application/json,text/plain,*/*',
    'Connection': 'keep-alive',
  };
}

http.Client _newNativeClient() {
  final io = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 4
    ..autoUncompress = true;
  return IOClient(io);
}

class _RestartableXtreamClient extends http.BaseClient {
  http.Client _inner = _newNativeClient();
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) {
      return Future<http.StreamedResponse>.error(
        StateError('El cliente Xtream ya fue cerrado.'),
      );
    }
    final client = _inner;
    return client.send(request);
  }

  void restart() {
    if (_closed) return;
    final previous = _inner;
    _inner = _newNativeClient();
    previous.close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _inner.close();
  }
}
'''
)


# ---------------------------------------------------------------------------
# 2) Artwork: sólo sesión/sección. Nada sobrevive al reinicio.
# ---------------------------------------------------------------------------
Path("lib/services/artwork_cache_service.dart").write_text(
    r'''import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';

/// Logos y carátulas estrictamente bajo demanda.
///
/// v40 elimina la persistencia de artwork en Application Support. Las imágenes
/// viven en un directorio TEMPORAL de la sección actual, con presupuesto bajo,
/// y cada nueva entrada a TV/Películas/Series usa una generación distinta.
/// Esto evita que una segunda entrada parezca rápida por posters viejos y evita
/// acumular cientos de MB en televisores con poco almacenamiento.
class ArtworkCacheService {
  ArtworkCacheService._();

  static final ArtworkCacheService instance = ArtworkCacheService._();

  static const int _maxConcurrent = 3;
  static const int _maxArtworkBytes = 3 * 1024 * 1024;
  static const int _maxSessionCacheBytes = 32 * 1024 * 1024;
  static const int _trimSessionCacheToBytes = 24 * 1024 * 1024;
  static const int _pruneEveryDownloads = 18;
  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _chunkTimeout = Duration(seconds: 6);
  static const Duration _touchInterval = Duration(minutes: 10);
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  final Queue<_ArtworkRequest> _queue = Queue<_ArtworkRequest>();
  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};
  final Map<String, File> _knownFiles = <String, File>{};
  final Map<String, int> _interest = <String, int>{};
  final Map<String, DateTime> _lastTouch = <String, DateTime>{};

  Directory? _rootDirectory;
  Future<Directory>? _rootDirectoryFuture;
  Directory? _cacheDirectory;
  Future<Directory>? _cacheDirectoryFuture;
  http.Client? _client;
  String? _providerId;
  int _generation = 0;
  int _sessionGeneration = 0;
  int _active = 0;
  int _downloadsSincePrune = 0;
  bool _pausedForPlayback = false;
  bool _pruneRunning = false;

  bool get pausedForPlayback => _pausedForPlayback;

  Future<void> switchProvider(String providerId) async {
    if (_providerId != providerId) {
      await clearBrowsingSession();
      _providerId = providerId;
    }
    _pausedForPlayback = false;
    _client ??= http.Client();
    await _ensureCacheDirectory();
  }

  Future<void> warmProvider(Playlist playlist) => switchProvider(playlist.id);

  Future<void> warmSection(
    List<Channel> channels, {
    required int limit,
    Duration maxWait = const Duration(milliseconds: 1800),
  }) async {}

  Future<void> warmUrls(
    Iterable<String> urls, {
    Duration maxWait = const Duration(seconds: 2),
  }) async {}

  /// Inicia una sección limpia. El cambio de generación es sincrónico: aunque
  /// el borrado físico del directorio anterior continúe unos milisegundos, la
  /// nueva sección escribe en otra ruta y nunca reutiliza esas imágenes.
  Future<void> clearBrowsingSession() {
    final oldDirectory = _cacheDirectory;
    _cancelNetworkWork();
    _knownFiles.clear();
    _interest.clear();
    _lastTouch.clear();
    _inFlight.clear();
    _downloadsSincePrune = 0;
    _pausedForPlayback = false;
    _cacheDirectory = null;
    _cacheDirectoryFuture = null;
    _sessionGeneration++;
    if (oldDirectory != null) {
      unawaited(_deleteDirectoryQuietly(oldDirectory));
    }
    return Future<void>.value();
  }

  void retain(String? rawUrl) {
    final url = _validArtworkUrl(rawUrl);
    if (url == null) return;
    _interest[url] = (_interest[url] ?? 0) + 1;
  }

  void release(String? rawUrl) {
    final url = _validArtworkUrl(rawUrl);
    if (url == null) return;
    final current = _interest[url] ?? 0;
    if (current <= 1) {
      _interest.remove(url);
      _discardUnneededQueuedRequests(url);
    } else {
      _interest[url] = current - 1;
    }
  }

  void pauseForPlayback() {
    if (_pausedForPlayback) return;
    _pausedForPlayback = true;
    _cancelNetworkWork();
  }

  void resumeBrowsing() {
    if (!_pausedForPlayback) return;
    _pausedForPlayback = false;
    _client = http.Client();
    _drainQueue();
  }

  Future<File?> resolve(
    String? rawUrl, {
    bool allowNetwork = true,
    bool demandDriven = false,
  }) async {
    final url = _validArtworkUrl(rawUrl);
    if (url == null) return null;

    final known = _knownFiles[url];
    if (known != null && await known.exists()) {
      _touchFile(url, known);
      return known;
    }

    final directory = await _ensureCacheDirectory();
    final file = File('${directory.path}/${_fileNameFor(url)}.img');
    if (await file.exists()) {
      _knownFiles[url] = file;
      _touchFile(url, file);
      return file;
    }

    if (!allowNetwork || _pausedForPlayback) return null;
    if (demandDriven && !_hasInterest(url)) return null;

    final existing = _inFlight[url];
    if (existing != null) return existing;

    final completer = Completer<File?>();
    final request = _ArtworkRequest(
      url: url,
      generation: _generation,
      demandDriven: demandDriven,
      completer: completer,
    );
    _queue.add(request);
    final future = completer.future;
    _inFlight[url] = future;
    future.whenComplete(() {
      if (identical(_inFlight[url], future)) _inFlight.remove(url);
    });
    _drainQueue();
    return future;
  }

  Future<Directory> _ensureRootDirectory() {
    final current = _rootDirectory;
    if (current != null) return Future<Directory>.value(current);
    final pending = _rootDirectoryFuture;
    if (pending != null) return pending;

    final future = () async {
      final base = await getTemporaryDirectory();
      final root = Directory('${base.path}/tv_full_artwork_session');
      // Primera utilización del proceso: elimina cualquier resto de una
      // ejecución anterior. Por eso cerrar/abrir TV FULL nunca conserva posters.
      if (await root.exists()) {
        try {
          await root.delete(recursive: true);
        } catch (_) {}
      }
      await root.create(recursive: true);
      _rootDirectory = root;
      return root;
    }();
    _rootDirectoryFuture = future;
    future.whenComplete(() => _rootDirectoryFuture = null);
    return future;
  }

  Future<Directory> _ensureCacheDirectory() {
    final current = _cacheDirectory;
    if (current != null) return Future<Directory>.value(current);
    final pending = _cacheDirectoryFuture;
    if (pending != null) return pending;
    final generation = _sessionGeneration;

    final future = () async {
      final root = await _ensureRootDirectory();
      final directory = Directory('${root.path}/section_$generation');
      if (!await directory.exists()) await directory.create(recursive: true);
      if (generation == _sessionGeneration) _cacheDirectory = directory;
      return directory;
    }();
    _cacheDirectoryFuture = future;
    future.whenComplete(() => _cacheDirectoryFuture = null);
    return future;
  }

  Future<void> _deleteDirectoryQuietly(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  bool _hasInterest(String url) => (_interest[url] ?? 0) > 0;

  bool _requestStillWanted(_ArtworkRequest request) {
    if (request.generation != _generation || _pausedForPlayback) return false;
    if (request.demandDriven && !_hasInterest(request.url)) return false;
    return true;
  }

  void _discardUnneededQueuedRequests(String url) {
    if (_queue.isEmpty) return;
    final pending = _queue.toList(growable: false);
    _queue.clear();
    for (final request in pending) {
      if (request.url == url &&
          request.demandDriven &&
          !_hasInterest(url)) {
        if (!request.completer.isCompleted) request.completer.complete(null);
      } else {
        _queue.add(request);
      }
    }
  }

  void _cancelNetworkWork() {
    _generation++;
    _client?.close();
    _client = null;
    while (_queue.isNotEmpty) {
      final request = _queue.removeFirst();
      if (!request.completer.isCompleted) request.completer.complete(null);
    }
  }

  void _drainQueue() {
    if (_pausedForPlayback) return;
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      if (!_requestStillWanted(request)) {
        if (!request.completer.isCompleted) request.completer.complete(null);
        continue;
      }
      _active++;
      unawaited(
        _download(request).whenComplete(() {
          _active--;
          _drainQueue();
        }),
      );
    }
  }

  Future<void> _download(_ArtworkRequest request) async {
    File? result;
    try {
      if (!_requestStillWanted(request)) return;
      final client = _client ??= http.Client();
      final httpRequest = http.Request('GET', Uri.parse(request.url))
        ..headers.addAll(const <String, String>{
          'User-Agent': _userAgent,
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        });
      final response = await client.send(httpRequest).timeout(_connectTimeout);
      if (!_requestStillWanted(request)) return;
      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final expected = response.contentLength;
      if (expected != null && expected > _maxArtworkBytes) return;

      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.stream.timeout(_chunkTimeout)) {
        if (!_requestStillWanted(request)) return;
        total += chunk.length;
        if (total > _maxArtworkBytes) return;
        builder.add(chunk);
      }
      if (total == 0 || !_requestStillWanted(request)) return;

      final directory = await _ensureCacheDirectory();
      if (!_requestStillWanted(request)) return;
      final file = File('${directory.path}/${_fileNameFor(request.url)}.img');
      await file.writeAsBytes(builder.takeBytes(), flush: false);
      _knownFiles[request.url] = file;
      _lastTouch[request.url] = DateTime.now();
      result = file;

      _downloadsSincePrune++;
      if (_downloadsSincePrune >= _pruneEveryDownloads) {
        _downloadsSincePrune = 0;
        _schedulePrune();
      }
    } catch (_) {
      // Las imágenes nunca bloquean catálogo o reproducción.
    } finally {
      if (!request.completer.isCompleted) request.completer.complete(result);
    }
  }

  void _touchFile(String url, File file) {
    final now = DateTime.now();
    final previous = _lastTouch[url];
    if (previous != null && now.difference(previous) < _touchInterval) return;
    _lastTouch[url] = now;
    unawaited(file.setLastModified(now).catchError((_) {}));
  }

  void _schedulePrune() {
    if (_pruneRunning) return;
    _pruneRunning = true;
    unawaited(_pruneSessionCache().whenComplete(() => _pruneRunning = false));
  }

  Future<void> _pruneSessionCache() async {
    try {
      final directory = await _ensureCacheDirectory();
      final entries = <_CachedArtworkEntry>[];
      var totalBytes = 0;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          totalBytes += stat.size;
          entries.add(_CachedArtworkEntry(
            file: entity,
            size: stat.size,
            modified: stat.modified,
          ));
        } catch (_) {}
      }
      if (totalBytes <= _maxSessionCacheBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in entries) {
        if (totalBytes <= _trimSessionCacheToBytes) break;
        try {
          await entry.file.delete();
          totalBytes -= entry.size;
          _knownFiles.removeWhere((_, file) => file.path == entry.file.path);
        } catch (_) {}
      }
    } catch (_) {}
  }

  String? _validArtworkUrl(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  String _fileNameFor(String value) {
    var h1 = 0x811c9dc5;
    var h2 = 5381;
    for (final unit in value.codeUnits) {
      h1 = ((h1 ^ unit) * 0x01000193) & 0xffffffff;
      h2 = ((h2 * 33) ^ unit) & 0xffffffff;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
  }
}

class _ArtworkRequest {
  final String url;
  final int generation;
  final bool demandDriven;
  final Completer<File?> completer;

  const _ArtworkRequest({
    required this.url,
    required this.generation,
    required this.demandDriven,
    required this.completer,
  });
}

class _CachedArtworkEntry {
  final File file;
  final int size;
  final DateTime modified;

  const _CachedArtworkEntry({
    required this.file,
    required this.size,
    required this.modified,
  });
}
'''
)


# ---------------------------------------------------------------------------
# 3) Quitar cargas visuales ficticias al abrir lista/catálogo.
# ---------------------------------------------------------------------------
home = Path("lib/screens/home_screen.dart")
text = home.read_text()
new_open = r'''  Future<void> _openPlaylist(BuildContext context) async {
    final navigator = Navigator.of(context);
    await ParentalControlService.instance.init();
    if (!context.mounted) return;

    // Sólo cambia la sesión de artwork. No mostramos un diálogo de "preparar"
    // porque desde v38 no existe ninguna precarga real en este punto.
    await ArtworkCacheService.instance.switchProvider(playlist.id);
    if (!context.mounted) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => SourceContentScreen(playlist: playlist),
      ),
    );
  }

'''
text = replace_between(
    text,
    "  Future<void> _openPlaylist(BuildContext context) async {",
    "  Future<void> _editPlaylist(BuildContext context) async {",
    new_open,
    "Home._openPlaylist",
)
home.write_text(text)

channel = Path("lib/screens/channel_list_screen.dart")
text = channel.read_text()
text = text.replace("  bool _initialArtworkReady = false;\n", "")
text = text.replace("    unawaited(_prepareInitialArtwork());\n", "")
if "  Future<void> _prepareInitialArtwork() async {" in text:
    text = replace_between(
        text,
        "  Future<void> _prepareInitialArtwork() async {",
        "  @override\n  Widget build(BuildContext context) {",
        "",
        "ChannelList._prepareInitialArtwork",
    )
pattern = re.compile(
    r"      body: !_initialArtworkReady\n.*?          : LayoutBuilder\(\n",
    re.S,
)
text, count = pattern.subn("      body: LayoutBuilder(\n", text, count=1)
if count != 1:
    raise SystemExit("No se pudo quitar el gate ficticio de artwork en ChannelList")
channel.write_text(text)

source = Path("lib/screens/source_content_screen.dart")
text = source.read_text()
if "import '../services/artwork_cache_service.dart';" not in text:
    text = text.replace(
        "import '../models/playlist_source_type.dart';\n",
        "import '../models/playlist_source_type.dart';\nimport '../services/artwork_cache_service.dart';\n",
    )
marker = "  void _openKind(BuildContext context, IptvContentKind kind) {\n"
if marker not in text:
    raise SystemExit("No se encontró SourceContent._openKind")
text = text.replace(
    marker,
    marker + "    ArtworkCacheService.instance.clearBrowsingSession();\n",
    1,
)
source.write_text(text)


# ---------------------------------------------------------------------------
# 4) Películas/Series: network-first. Caché sólo fallback real.
# ---------------------------------------------------------------------------
movies = Path("lib/screens/xtream_movies_screen.dart")
text = movies.read_text()
text = text.replace("  int _loadGeneration = 0;\n", "")
new_load_movies = r'''  Future<_MovieCatalogData> _load({bool forceNetwork = false}) async {
    await _parental.init();
    final fast = XtreamFastCatalogService.instance;

    try {
      final fresh = await fast.refreshMovies(
        widget.playlist.source,
        forceSessionRefresh: forceNetwork,
        onProgress: _onCatalogProgress,
      );
      _setCatalogCategories(fresh.categories);
      return _MovieCatalogData(
        connection: fresh.connection,
        movies: fresh.movies,
      );
    } catch (_) {
      // La copia local es únicamente respaldo/offline. Nunca dispara una
      // actualización pesada escondida detrás de la interfaz.
      final cached = await fast.loadCachedMovies(widget.playlist.source);
      if (cached != null && cached.movies.isNotEmpty) {
        _setCatalogCategories(cached.categories);
        return _MovieCatalogData(
          connection: cached.connection,
          movies: cached.movies,
        );
      }
      rethrow;
    }
  }

'''
text = replace_between(
    text,
    "  Future<_MovieCatalogData> _load({bool forceNetwork = false}) async {",
    "  void _setCatalogCategories(List<String> categories) {",
    new_load_movies,
    "Movies._load",
)
if "  Future<void> _refreshMovieCatalog(int generation) async {" in text:
    text = replace_between(
        text,
        "  Future<void> _refreshMovieCatalog(int generation) async {",
        "  Future<void> _loadSidebarPreferences() async {",
        "",
        "Movies._refreshMovieCatalog",
    )
movies.write_text(text)

series_screen = Path("lib/screens/xtream_series_screen.dart")
text = series_screen.read_text()
text = text.replace("  int _loadGeneration = 0;\n", "")
new_load_series = r'''  Future<_SeriesCatalogData> _load({bool forceNetwork = false}) async {
    await _parental.init();
    final fast = XtreamFastCatalogService.instance;

    try {
      final fresh = await fast.refreshSeries(
        widget.playlist.source,
        forceSessionRefresh: forceNetwork,
        onProgress: _onCatalogProgress,
      );
      _setCatalogCategories(fresh.categories);
      return _SeriesCatalogData(
        connection: fresh.connection,
        series: fresh.series,
      );
    } catch (_) {
      final cached = await fast.loadCachedSeries(widget.playlist.source);
      if (cached != null && cached.series.isNotEmpty) {
        _setCatalogCategories(cached.categories);
        return _SeriesCatalogData(
          connection: cached.connection,
          series: cached.series,
        );
      }
      rethrow;
    }
  }

'''
text = replace_between(
    text,
    "  Future<_SeriesCatalogData> _load({bool forceNetwork = false}) async {",
    "  void _setCatalogCategories(List<String> categories) {",
    new_load_series,
    "Series._load",
)
if "  Future<void> _refreshSeriesCatalog(int generation) async {" in text:
    text = replace_between(
        text,
        "  Future<void> _refreshSeriesCatalog(int generation) async {",
        "  void _retry() {",
        "",
        "Series._refreshSeriesCatalog",
    )
first_poster = """              child: CachedArtworkImage(\n                url: series.cover,\n                fit: BoxFit.cover,\n"""
if first_poster in text:
    text = text.replace(
        first_poster,
        first_poster + "                cacheWidth: 420,\n",
        1,
    )
series_screen.write_text(text)


# ---------------------------------------------------------------------------
# 5) Motor de catálogo: conexión directa, secuencial para no competir,
#    payload pesado a archivo temporal y JSON fuera del isolate UI.
# ---------------------------------------------------------------------------
fast = Path("lib/services/xtream_fast_catalog_service.dart")
text = fast.read_text()
text = text.replace(
    "  static const int _cacheVersion = 1;",
    "  static const int _cacheVersion = 2;",
)
text = text.replace(
    "  static const Duration _categoryTimeout = Duration(seconds: 6);",
    "  static const Duration _categoryTimeout = Duration(seconds: 4);",
)

diag_start = text.index("  // Build temporal de diagnóstico:")
diag_end = text.index(
    "  final Map<String, XtreamConnectionResult> _sessions", diag_start
)
text = (
    text[:diag_start]
    + "  String? _lastSeriesDiagnostics;\n\n"
    + "  String? get lastSeriesDiagnostics => _lastSeriesDiagnostics;\n\n"
    + text[diag_end:]
)
text = text.replace(
    "  Directory? _cacheDirectory;\n",
    "  Directory? _cacheDirectory;\n  Directory? _transferDirectory;\n",
    1,
)

connection_block = r'''  /// Para listar catálogos no hace falta esperar player_api.php sin action.
  /// get.php ya contiene host/puerto/usuario/contraseña. Si el panel rechaza
  /// esta ruta con 401/403, refreshMovies/refreshSeries hacen el fallback a la
  /// conexión autenticada y resuelta por server_info.
  Future<XtreamConnectionResult> _connectionForCatalog(
    String playlistUrl, {
    bool forceRefresh = false,
  }) async {
    final key = playlistUrl.trim();
    if (!forceRefresh) {
      final cached = _sessions[key];
      if (cached != null) return cached;
      final provisional = _provisionalConnectionFromPlaylistUrl(key);
      if (provisional != null) return provisional;
    }
    return connectionForPlaylist(key, forceRefresh: forceRefresh);
  }

'''
text = replace_between(
    text,
    "  /// Para listar Series no necesitamos esperar player_api.php sin action.",
    "  void rememberConnection(XtreamConnectionResult connection) {",
    connection_block,
    "FastCatalog._connectionForCatalog",
)

cached_movies = r'''  Future<XtreamMovieCatalogSnapshot?> loadCachedMovies(
    String playlistUrl,
  ) async {
    final raw = await _readCache(playlistUrl, 'movies');
    if (raw == null) return null;
    try {
      final payload = await compute(_decodeCachePayload, raw);
      if (payload['version'] != _cacheVersion || payload['kind'] != 'movies') {
        unawaited(_deleteCacheFile(playlistUrl, 'movies'));
        return null;
      }
      final connection = _provisionalConnectionFromPlaylistUrl(playlistUrl);
      if (connection == null) return null;
      final movies = _movieListFromPrepared(payload['items']);
      if (movies.isEmpty) return null;
      final categories = _stringList(payload['categories']);
      final savedAt = _dateFromMillis(payload['savedAt']) ?? DateTime.now();
      return XtreamMovieCatalogSnapshot(
        connection: connection,
        movies: List<XtreamVodSummary>.unmodifiable(movies),
        categories: List<String>.unmodifiable(categories),
        savedAt: savedAt,
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

'''
text = replace_between(
    text,
    "  Future<XtreamMovieCatalogSnapshot?> loadCachedMovies(",
    "  Future<XtreamSeriesCatalogSnapshot?> loadCachedSeries(",
    cached_movies,
    "FastCatalog.loadCachedMovies",
)

cached_series = r'''  Future<XtreamSeriesCatalogSnapshot?> loadCachedSeries(
    String playlistUrl,
  ) async {
    final raw = await _readCache(playlistUrl, 'series');
    if (raw == null) return null;
    try {
      final payload = await compute(_decodeCachePayload, raw);
      if (payload['version'] != _cacheVersion || payload['kind'] != 'series') {
        unawaited(_deleteCacheFile(playlistUrl, 'series'));
        return null;
      }
      final connection = _provisionalConnectionFromPlaylistUrl(playlistUrl);
      if (connection == null) return null;
      final series = _seriesListFromPrepared(payload['items']);
      if (series.isEmpty) return null;
      final categories = _stringList(payload['categories']);
      final savedAt = _dateFromMillis(payload['savedAt']) ?? DateTime.now();
      return XtreamSeriesCatalogSnapshot(
        connection: connection,
        series: List<XtreamSeriesSummary>.unmodifiable(series),
        categories: List<String>.unmodifiable(categories),
        savedAt: savedAt,
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

'''
text = replace_between(
    text,
    "  Future<XtreamSeriesCatalogSnapshot?> loadCachedSeries(",
    "  Future<XtreamMovieCatalogSnapshot> refreshMovies(",
    cached_series,
    "FastCatalog.loadCachedSeries",
)

refresh_movies = r'''  Future<XtreamMovieCatalogSnapshot> refreshMovies(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    var connection = await _connectionForCatalog(
      playlistUrl,
      forceRefresh: forceSessionRefresh,
    );

    try {
      return await _fetchMovies(connection, playlistUrl, onProgress);
    } on _XtreamHttpException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 403) rethrow;
      invalidateSession(playlistUrl);
      connection = await connectionForPlaylist(playlistUrl, forceRefresh: true);
      return _fetchMovies(connection, playlistUrl, onProgress);
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (error) {
      try {
        final movies = await XtreamVodService.fetchCatalog(connection);
        final categories = _categoriesFromMovies(movies);
        final snapshot = XtreamMovieCatalogSnapshot(
          connection: connection,
          movies: movies,
          categories: categories,
          savedAt: DateTime.now(),
          fromCache: false,
        );
        unawaited(_writeMovieCache(playlistUrl, snapshot));
        return snapshot;
      } catch (_) {
        throw error;
      }
    }
  }

'''
text = replace_between(
    text,
    "  Future<XtreamMovieCatalogSnapshot> refreshMovies(",
    "  Future<XtreamSeriesCatalogSnapshot> refreshSeries(",
    refresh_movies,
    "FastCatalog.refreshMovies",
)

refresh_series = r'''  Future<XtreamSeriesCatalogSnapshot> refreshSeries(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    final totalWatch = Stopwatch()..start();
    final connectionWatch = Stopwatch()..start();
    var connection = await _connectionForCatalog(
      playlistUrl,
      forceRefresh: forceSessionRefresh,
    );
    connectionWatch.stop();
    var connectionElapsed = connectionWatch.elapsed;

    try {
      return await _fetchSeries(
        connection,
        playlistUrl,
        onProgress,
        totalWatch: totalWatch,
        connectionElapsed: connectionElapsed,
      );
    } on _XtreamHttpException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 403) rethrow;
      invalidateSession(playlistUrl);
      final authWatch = Stopwatch()..start();
      connection = await connectionForPlaylist(playlistUrl, forceRefresh: true);
      authWatch.stop();
      connectionElapsed += authWatch.elapsed;
      return _fetchSeries(
        connection,
        playlistUrl,
        onProgress,
        totalWatch: totalWatch,
        connectionElapsed: connectionElapsed,
      );
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (error) {
      try {
        final fallbackWatch = Stopwatch()..start();
        final series = await XtreamSeriesService.fetchCatalog(connection);
        fallbackWatch.stop();
        final categories = _categoriesFromSeries(series);
        if (totalWatch.isRunning) totalWatch.stop();
        final diagnostic = <String>[
          'TV FULL · Diagnóstico Series v40',
          'Ruta: FALLBACK XtreamSeriesService',
          'Conexión: ${_formatDiagnosticDuration(connectionElapsed)}',
          'Fallback catálogo: ${_formatDiagnosticDuration(fallbackWatch.elapsed)}',
          'TOTAL: ${_formatDiagnosticDuration(totalWatch.elapsed)}',
          'Elementos: ${series.length}',
          'Fecha: ${DateTime.now().toIso8601String()}',
        ].join('\n');
        _lastSeriesDiagnostics = diagnostic;
        debugPrint(diagnostic);
        unawaited(_writeSeriesDiagnostic(diagnostic));
        return XtreamSeriesCatalogSnapshot(
          connection: connection,
          series: series,
          categories: categories,
          savedAt: DateTime.now(),
          fromCache: false,
        );
      } catch (_) {
        throw error;
      }
    }
  }

'''
text = replace_between(
    text,
    "  Future<XtreamSeriesCatalogSnapshot> refreshSeries(",
    "  Future<XtreamMovieCatalogSnapshot> _fetchMovies(",
    refresh_series,
    "FastCatalog.refreshSeries",
)

fetch_movies = r'''  Future<XtreamMovieCatalogSnapshot> _fetchMovies(
    XtreamConnectionResult connection,
    String playlistUrl,
    XtreamCatalogProgressCallback? onProgress,
  ) async {
    onProgress?.call(const XtreamCatalogProgress(
      section: 'MOVIE',
      phase: 'Cargando categorías',
      step: 1,
      totalSteps: 2,
    ));

    String categoriesBody = '[]';
    try {
      categoriesBody = await _downloadActionBody(
        connection,
        'get_vod_categories',
        _categoryTimeout,
      );
    } catch (_) {
      categoriesBody = '[]';
    }

    onProgress?.call(const XtreamCatalogProgress(
      section: 'MOVIE',
      phase: 'Cargando lista',
      step: 2,
      totalSteps: 2,
    ));
    final transfer = await _downloadActionFile(
      connection,
      'get_vod_streams',
      _movieTimeout,
      onBytes: (bytes) => onProgress?.call(XtreamCatalogProgress(
        section: 'MOVIE',
        phase: 'Cargando lista',
        step: 2,
        totalSteps: 2,
        receivedBytes: bytes,
      )),
    );

    onProgress?.call(const XtreamCatalogProgress(
      section: 'MOVIE',
      phase: 'Preparando catálogo',
      step: 2,
      totalSteps: 2,
    ));
    Map<String, dynamic> prepared;
    try {
      prepared = await compute(_prepareMovieCatalogFromFile, <String, String>{
        'categories': categoriesBody,
        'itemsPath': transfer.file.path,
      });
    } finally {
      unawaited(_deleteFileQuietly(transfer.file));
    }

    final movies = _movieListFromPrepared(prepared['items']);
    if (movies.isEmpty) {
      throw const FormatException('Xtream no devolvió películas válidas.');
    }
    final categories = _stringList(prepared['categories']);
    final snapshot = XtreamMovieCatalogSnapshot(
      connection: connection,
      movies: List<XtreamVodSummary>.unmodifiable(movies),
      categories: List<String>.unmodifiable(categories),
      savedAt: DateTime.now(),
      fromCache: false,
    );
    if (connection.serverName != null ||
        connection.status != null ||
        connection.expiration != null) {
      rememberConnection(connection);
    }
    unawaited(_writePreparedCache(
      playlistUrl,
      'movies',
      prepared,
      snapshot.savedAt,
    ));
    return snapshot;
  }

'''
text = replace_between(
    text,
    "  Future<XtreamMovieCatalogSnapshot> _fetchMovies(",
    "  Future<XtreamSeriesCatalogSnapshot> _fetchSeries(",
    fetch_movies,
    "FastCatalog._fetchMovies",
)

fetch_series = r'''  Future<XtreamSeriesCatalogSnapshot> _fetchSeries(
    XtreamConnectionResult connection,
    String playlistUrl,
    XtreamCatalogProgressCallback? onProgress, {
    required Stopwatch totalWatch,
    required Duration connectionElapsed,
  }) async {
    onProgress?.call(const XtreamCatalogProgress(
      section: 'SERIES',
      phase: 'Cargando categorías',
      step: 1,
      totalSteps: 2,
    ));

    final categoryWatch = Stopwatch()..start();
    var categoryBytes = 0;
    var categorySuccess = true;
    String categoriesBody;
    try {
      categoriesBody = await _downloadActionBody(
        connection,
        'get_series_categories',
        _categoryTimeout,
        onBytes: (value) => categoryBytes = value,
      );
    } catch (_) {
      categoriesBody = '[]';
      categorySuccess = false;
    }
    categoryWatch.stop();

    // Importante: get_series comienza DESPUÉS de categorías. No abrimos dos
    // conexiones pesadas simultáneas contra paneles que pueden repartir/throttle
    // ancho de banda por cuenta o IP.
    onProgress?.call(const XtreamCatalogProgress(
      section: 'SERIES',
      phase: 'Cargando lista',
      step: 2,
      totalSteps: 2,
    ));
    final transfer = await _downloadActionFile(
      connection,
      'get_series',
      _seriesTimeout,
      onBytes: (bytes) => onProgress?.call(XtreamCatalogProgress(
        section: 'SERIES',
        phase: 'Cargando lista',
        step: 2,
        totalSteps: 2,
        receivedBytes: bytes,
      )),
    );

    onProgress?.call(const XtreamCatalogProgress(
      section: 'SERIES',
      phase: 'Preparando catálogo',
      step: 2,
      totalSteps: 2,
    ));
    final prepareWatch = Stopwatch()..start();
    Map<String, dynamic> prepared;
    try {
      prepared = await compute(_prepareSeriesCatalogFromFile, <String, String>{
        'categories': categoriesBody,
        'itemsPath': transfer.file.path,
      });
    } finally {
      unawaited(_deleteFileQuietly(transfer.file));
    }
    prepareWatch.stop();

    final materializeWatch = Stopwatch()..start();
    final series = _seriesListFromPrepared(prepared['items']);
    if (series.isEmpty) {
      throw const FormatException('Xtream no devolvió series válidas.');
    }
    final categories = _stringList(prepared['categories']);
    materializeWatch.stop();

    final snapshot = XtreamSeriesCatalogSnapshot(
      connection: connection,
      series: List<XtreamSeriesSummary>.unmodifiable(series),
      categories: List<String>.unmodifiable(categories),
      savedAt: DateTime.now(),
      fromCache: false,
    );

    if (connection.serverName != null ||
        connection.status != null ||
        connection.expiration != null) {
      rememberConnection(connection);
    }

    if (totalWatch.isRunning) totalWatch.stop();
    final diagnostic = <String>[
      'TV FULL · Diagnóstico Series v40',
      'Ruta: categorías → get_series → archivo temporal → isolate',
      'Conexión: ${_formatDiagnosticDuration(connectionElapsed)}',
      'Categorías: ${_formatDiagnosticDuration(categoryWatch.elapsed)} · ${_formatDiagnosticBytes(categoryBytes)} · ${categorySuccess ? 'OK' : 'fallback vacío'}',
      'get_series red: ${_formatDiagnosticDuration(transfer.elapsed)} · ${_formatDiagnosticBytes(transfer.bytes)}',
      'JSON + preparación isolate: ${_formatDiagnosticDuration(prepareWatch.elapsed)}',
      'Materializar objetos: ${_formatDiagnosticDuration(materializeWatch.elapsed)}',
      'TOTAL: ${_formatDiagnosticDuration(totalWatch.elapsed)}',
      'Series: ${series.length}',
      'Categorías finales: ${categories.length}',
      'Fecha: ${DateTime.now().toIso8601String()}',
    ].join('\n');
    _lastSeriesDiagnostics = diagnostic;
    debugPrint(diagnostic);
    unawaited(_writeSeriesDiagnostic(diagnostic));

    unawaited(_writePreparedCache(
      playlistUrl,
      'series',
      prepared,
      snapshot.savedAt,
    ));
    return snapshot;
  }

'''
text = replace_between(
    text,
    "  Future<XtreamSeriesCatalogSnapshot> _fetchSeries(",
    "  Future<String> _downloadActionBody(",
    fetch_series,
    "FastCatalog._fetchSeries",
)

downloads = r'''  Future<String> _downloadActionBody(
    XtreamConnectionResult connection,
    String action,
    Duration inactivityTimeout, {
    ValueChanged<int>? onBytes,
  }) async {
    final uri = _endpoint(connection.apiServer, <String, String>{
      'username': connection.username,
      'password': connection.password,
      'action': action,
    });
    final request = http.Request('GET', uri)
      ..headers.addAll(XtreamHttpClient.jsonHeaders);
    final response = await XtreamHttpClient.instance
        .send(request)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw _XtreamHttpException(action, response.statusCode);
    }

    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream.timeout(inactivityTimeout)) {
      received += chunk.length;
      builder.add(chunk);
      onBytes?.call(received);
    }
    if (received == 0) {
      throw FormatException('Xtream $action devolvió una respuesta vacía.');
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  Future<_CatalogFileDownload> _downloadActionFile(
    XtreamConnectionResult connection,
    String action,
    Duration inactivityTimeout, {
    ValueChanged<int>? onBytes,
  }) async {
    final uri = _endpoint(connection.apiServer, <String, String>{
      'username': connection.username,
      'password': connection.password,
      'action': action,
    });
    final request = http.Request('GET', uri)
      ..headers.addAll(XtreamHttpClient.jsonHeaders);
    final watch = Stopwatch()..start();
    final response = await XtreamHttpClient.instance
        .send(request)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw _XtreamHttpException(action, response.statusCode);
    }

    final directory = await _ensureTransferDirectory();
    final safeAction = action.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$safeAction.json',
    );
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(inactivityTimeout)) {
        received += chunk.length;
        sink.add(chunk);
        onBytes?.call(received);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      unawaited(_deleteFileQuietly(file));
      rethrow;
    }
    watch.stop();
    if (received == 0) {
      unawaited(_deleteFileQuietly(file));
      throw FormatException('Xtream $action devolvió una respuesta vacía.');
    }
    return _CatalogFileDownload(
      file: file,
      bytes: received,
      elapsed: watch.elapsed,
    );
  }

'''
text = replace_between(
    text,
    "  Future<String> _downloadActionBody(",
    "  Future<String?> _readCache(",
    downloads,
    "FastCatalog.download methods",
)

cache_writers = r'''  Future<void> _writePreparedCache(
    String playlistUrl,
    String kind,
    Map<String, dynamic> prepared,
    DateTime savedAt,
  ) async {
    await Future<void>.delayed(Duration.zero);
    final payload = <String, dynamic>{
      'version': _cacheVersion,
      'kind': kind,
      'savedAt': savedAt.millisecondsSinceEpoch,
      'categories': prepared['categories'] ?? const <String>[],
      'items': prepared['items'] ?? const <dynamic>[],
    };
    await _writeCache(playlistUrl, kind, payload);
  }

  Future<void> _writeMovieCache(
    String playlistUrl,
    XtreamMovieCatalogSnapshot snapshot,
  ) async {
    final payload = <String, dynamic>{
      'version': _cacheVersion,
      'kind': 'movies',
      'savedAt': snapshot.savedAt.millisecondsSinceEpoch,
      'categories': snapshot.categories,
      'items': snapshot.movies.map(_movieToMap).toList(growable: false),
    };
    await _writeCache(playlistUrl, 'movies', payload);
  }

  Future<void> _writeSeriesCache(
    String playlistUrl,
    XtreamSeriesCatalogSnapshot snapshot,
  ) async {
    final payload = <String, dynamic>{
      'version': _cacheVersion,
      'kind': 'series',
      'savedAt': snapshot.savedAt.millisecondsSinceEpoch,
      'categories': snapshot.categories,
      'items': snapshot.series.map(_seriesToMap).toList(growable: false),
    };
    await _writeCache(playlistUrl, 'series', payload);
  }

'''
text = replace_between(
    text,
    "  Future<void> _writePreparedCache(",
    "  Future<void> _writeCache(",
    cache_writers,
    "FastCatalog.cache writers",
)

transfer_helpers = r'''  Future<Directory> _ensureTransferDirectory() async {
    final current = _transferDirectory;
    if (current != null) return current;
    final base = await getTemporaryDirectory();
    final directory = Directory('${base.path}/tv_full_xtream_transfer');
    if (!await directory.exists()) await directory.create(recursive: true);
    _transferDirectory = directory;
    unawaited(_cleanupStaleTransfers(directory));
    return directory;
  }

  Future<void> _cleanupStaleTransfers(Directory directory) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 6));
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _deleteFileQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _deleteCacheFile(String playlistUrl, String kind) async {
    try {
      final file = await _cacheFile(playlistUrl, kind);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

'''
marker = "  Future<File> _cacheFile(String playlistUrl, String kind) async {\n"
if marker not in text:
    raise SystemExit("No se encontró FastCatalog._cacheFile")
text = text.replace(marker, transfer_helpers + marker, 1)

text = replace_between(
    text,
    "class _SeriesTimedBody {",
    "String _formatDiagnosticDuration(Duration value) =>",
    r'''class _CatalogFileDownload {
  final File file;
  final int bytes;
  final Duration elapsed;

  const _CatalogFileDownload({
    required this.file,
    required this.bytes,
    required this.elapsed,
  });
}

''',
    "FastCatalog._CatalogFileDownload",
)

prepare_file_helpers = r'''Map<String, dynamic> _prepareMovieCatalogFromFile(
  Map<String, String> input,
) {
  final path = input['itemsPath'];
  if (path == null || path.isEmpty) {
    throw const FormatException('Archivo temporal MOVIE inválido.');
  }
  final items = File(path).readAsStringSync();
  return _prepareMovieCatalog(<String, String>{
    'categories': input['categories'] ?? '[]',
    'items': items,
  });
}

Map<String, dynamic> _prepareSeriesCatalogFromFile(
  Map<String, String> input,
) {
  final path = input['itemsPath'];
  if (path == null || path.isEmpty) {
    throw const FormatException('Archivo temporal SERIES inválido.');
  }
  final items = File(path).readAsStringSync();
  return _prepareSeriesCatalog(<String, String>{
    'categories': input['categories'] ?? '[]',
    'items': items,
  });
}

'''
marker = "Map<String, dynamic> _prepareMovieCatalog(Map<String, String> input) {\n"
if marker not in text:
    raise SystemExit("No se encontró _prepareMovieCatalog")
text = text.replace(marker, prepare_file_helpers + marker, 1)

item_sort = """  items.sort((a, b) => (a['name'] as String)\n      .toLowerCase()\n      .compareTo((b['name'] as String).toLowerCase()));\n"""
if text.count(item_sort) < 2:
    raise SystemExit("No se encontraron los dos sorts globales esperados")
text = text.replace(item_sort, "", 2)

conn_start = text.index("Map<String, dynamic> _connectionToMap(")
conn_end = text.index(
    "XtreamConnectionResult? _provisionalConnectionFromPlaylistUrl(", conn_start
)
text = text[:conn_start] + text[conn_end:]

fast.write_text(text)
