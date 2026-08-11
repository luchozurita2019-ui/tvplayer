from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 match, found {count}")
    p.write_text(text.replace(old, new, 1))


# Shared HTTP client across Xtream auth, VOD and Series.
for path in [
    'lib/services/xtream_service.dart',
    'lib/services/xtream_vod_service.dart',
    'lib/services/xtream_series_service.dart',
]:
    text = Path(path).read_text()
    if "import 'xtream_http_client.dart';" not in text:
        anchor = "import 'xtream_service.dart';\n" if path != 'lib/services/xtream_service.dart' else "import '../models/channel.dart';\n"
        replacement = anchor + "import 'xtream_http_client.dart';\n"
        if text.count(anchor) != 1:
            raise SystemExit(f'{path}: shared-client import anchor mismatch')
        text = text.replace(anchor, replacement, 1)
    old = 'static final http.Client _client = http.Client();'
    new = 'static final http.Client _client = XtreamHttpClient.instance;'
    if text.count(old) != 1:
        raise SystemExit(f'{path}: client declaration mismatch')
    text = text.replace(old, new, 1)
    Path(path).write_text(text)


# Movies screen: fast cache/session pipeline + throttled progress.
movies = 'lib/screens/xtream_movies_screen.dart'
replace_once(
    movies,
    "import '../services/parental_control_service.dart';\n",
    "import '../services/parental_control_service.dart';\nimport '../services/xtream_fast_catalog_service.dart';\n",
)
replace_once(
    movies,
    """  List<String> _catalogCategories = const <String>[];

  static const double _sidebarMinWidth = 230;
""",
    """  List<String> _catalogCategories = const <String>[];
  String _progressLabel = 'Cargando información del servidor…';
  int _loadGeneration = 0;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastProgressBytes = 0;

  static const double _sidebarMinWidth = 230;
""",
)
old_movie_load = """  Future<_MovieCatalogData> _load() async {
    await _parental.init();
    final connection =
        await XtreamService.reconnectFromPlaylistUrl(widget.playlist.source);
    final movies = await XtreamVodService.fetchCatalog(connection);
    final categories = movies
        .map((item) => item.category)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (mounted) {
      setState(() => _catalogCategories = List.unmodifiable(categories));
    } else {
      _catalogCategories = List.unmodifiable(categories);
    }
    return _MovieCatalogData(connection: connection, movies: movies);
  }
"""
new_movie_load = """  Future<_MovieCatalogData> _load({bool forceNetwork = false}) async {
    await _parental.init();
    final generation = ++_loadGeneration;
    final fast = XtreamFastCatalogService.instance;

    if (!forceNetwork) {
      final cached = await fast.loadCachedMovies(widget.playlist.source);
      if (cached != null && cached.movies.isNotEmpty) {
        _setCatalogCategories(cached.categories);
        // La UI se abre con disco inmediatamente y la red se actualiza detrás.
        unawaited(_refreshMovieCatalog(generation));
        return _MovieCatalogData(
          connection: cached.connection,
          movies: cached.movies,
        );
      }
    }

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
  }

  void _setCatalogCategories(List<String> categories) {
    final value = List<String>.unmodifiable(categories);
    if (mounted) {
      setState(() => _catalogCategories = value);
    } else {
      _catalogCategories = value;
    }
  }

  void _onCatalogProgress(XtreamCatalogProgress progress) {
    if (!mounted) return;
    final now = DateTime.now();
    final bytesDelta = progress.receivedBytes - _lastProgressBytes;
    final elapsed = now.difference(_lastProgressUpdate);
    if (progress.receivedBytes > 0 &&
        bytesDelta < 128 * 1024 &&
        elapsed < const Duration(milliseconds: 180)) {
      return;
    }
    _lastProgressUpdate = now;
    _lastProgressBytes = progress.receivedBytes;
    setState(() => _progressLabel = progress.label);
  }

  Future<void> _refreshMovieCatalog(int generation) async {
    try {
      final fresh = await XtreamFastCatalogService.instance.refreshMovies(
        widget.playlist.source,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _catalogCategories = List<String>.unmodifiable(fresh.categories);
        if (_category != null && !_catalogCategories.contains(_category)) {
          _category = null;
        }
        _future = Future<_MovieCatalogData>.value(
          _MovieCatalogData(
            connection: fresh.connection,
            movies: fresh.movies,
          ),
        );
      });
    } catch (_) {
      // Si falla la actualización, el catálogo local permanece disponible.
    }
  }
"""
replace_once(movies, old_movie_load, new_movie_load)
replace_once(
    movies,
    "  void _retry() => setState(() => _future = _load());\n",
    """  void _retry() {
    XtreamFastCatalogService.instance.invalidateSession(widget.playlist.source);
    setState(() {
      _progressLabel = 'Cargando información del servidor…';
      _lastProgressBytes = 0;
      _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      _future = _load(forceNetwork: true);
    });
  }
""",
)
replace_once(
    movies,
    """          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Cargando catálogo de películas por Xtream…'),
                ],
              ),
            );
          }
""",
    """          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(_progressLabel),
                ],
              ),
            );
          }
""",
)
old_movie_build = """    final allCategories = data.movies
        .map((item) => item.category)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final categories = _parental.visibleGroups(allCategories);
    final categoryCounts = <String, int>{};
    for (final item in data.movies) {
      if (!_parental.canShowItem(name: item.name, group: item.category)) continue;
      final category = item.category?.trim();
      if (category == null || category.isEmpty) continue;
      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    }
    final visibleTotal = data.movies
        .where((item) =>
            _parental.canShowItem(name: item.name, group: item.category))
        .length;

    final normalized = _query.trim().toLowerCase();
    final visible = data.movies.where((item) {
      if (!_parental.canShowItem(name: item.name, group: item.category)) {
        return false;
      }
      if (_category != null && item.category != _category) return false;
      if (normalized.isEmpty) return true;
      return item.name.toLowerCase().contains(normalized) ||
          (item.genre?.toLowerCase().contains(normalized) ?? false) ||
          (item.category?.toLowerCase().contains(normalized) ?? false);
    }).toList(growable: false);
"""
new_movie_build = """    final categories = _parental.visibleGroups(_catalogCategories);
    final categoryCounts = <String, int>{};
    final visible = <XtreamVodSummary>[];
    var visibleTotal = 0;
    final normalized = _query.trim().toLowerCase();

    // Una sola pasada: parental + conteos + categoría + búsqueda.
    for (final item in data.movies) {
      if (!_parental.canShowItem(name: item.name, group: item.category)) continue;
      visibleTotal++;
      final category = item.category?.trim();
      if (category != null && category.isNotEmpty) {
        categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
      }
      if (_category != null && item.category != _category) continue;
      if (normalized.isNotEmpty &&
          !item.name.toLowerCase().contains(normalized) &&
          !(item.genre?.toLowerCase().contains(normalized) ?? false) &&
          !(item.category?.toLowerCase().contains(normalized) ?? false)) {
        continue;
      }
      visible.add(item);
    }
"""
replace_once(movies, old_movie_build, new_movie_build)


# Series screen: same fast pipeline.
series = 'lib/screens/xtream_series_screen.dart'
replace_once(
    series,
    "import '../services/parental_control_service.dart';\n",
    "import '../services/parental_control_service.dart';\nimport '../services/xtream_fast_catalog_service.dart';\n",
)
replace_once(
    series,
    """  List<String> _catalogCategories = const <String>[];

  static const double _sidebarMinWidth = 230;
""",
    """  List<String> _catalogCategories = const <String>[];
  String _progressLabel = 'Cargando información del servidor…';
  int _loadGeneration = 0;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastProgressBytes = 0;

  static const double _sidebarMinWidth = 230;
""",
)
old_series_load = """  Future<_SeriesCatalogData> _load() async {
    await _parental.init();
    final connection =
        await XtreamService.reconnectFromPlaylistUrl(widget.playlist.source);
    final series = await XtreamSeriesService.fetchCatalog(connection);
    final categories = series
        .map((item) => item.category)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (mounted) {
      setState(() => _catalogCategories = List.unmodifiable(categories));
    } else {
      _catalogCategories = List.unmodifiable(categories);
    }
    return _SeriesCatalogData(connection: connection, series: series);
  }

  void _retry() => setState(() => _future = _load());
"""
new_series_load = """  Future<_SeriesCatalogData> _load({bool forceNetwork = false}) async {
    await _parental.init();
    final generation = ++_loadGeneration;
    final fast = XtreamFastCatalogService.instance;

    if (!forceNetwork) {
      final cached = await fast.loadCachedSeries(widget.playlist.source);
      if (cached != null && cached.series.isNotEmpty) {
        _setCatalogCategories(cached.categories);
        unawaited(_refreshSeriesCatalog(generation));
        return _SeriesCatalogData(
          connection: cached.connection,
          series: cached.series,
        );
      }
    }

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
  }

  void _setCatalogCategories(List<String> categories) {
    final value = List<String>.unmodifiable(categories);
    if (mounted) {
      setState(() => _catalogCategories = value);
    } else {
      _catalogCategories = value;
    }
  }

  void _onCatalogProgress(XtreamCatalogProgress progress) {
    if (!mounted) return;
    final now = DateTime.now();
    final bytesDelta = progress.receivedBytes - _lastProgressBytes;
    final elapsed = now.difference(_lastProgressUpdate);
    if (progress.receivedBytes > 0 &&
        bytesDelta < 128 * 1024 &&
        elapsed < const Duration(milliseconds: 180)) {
      return;
    }
    _lastProgressUpdate = now;
    _lastProgressBytes = progress.receivedBytes;
    setState(() => _progressLabel = progress.label);
  }

  Future<void> _refreshSeriesCatalog(int generation) async {
    try {
      final fresh = await XtreamFastCatalogService.instance.refreshSeries(
        widget.playlist.source,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _catalogCategories = List<String>.unmodifiable(fresh.categories);
        if (_category != null && !_catalogCategories.contains(_category)) {
          _category = null;
        }
        _future = Future<_SeriesCatalogData>.value(
          _SeriesCatalogData(
            connection: fresh.connection,
            series: fresh.series,
          ),
        );
      });
    } catch (_) {
      // Conservamos la copia local cuando el proveedor no responde.
    }
  }

  void _retry() {
    XtreamFastCatalogService.instance.invalidateSession(widget.playlist.source);
    setState(() {
      _progressLabel = 'Cargando información del servidor…';
      _lastProgressBytes = 0;
      _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      _future = _load(forceNetwork: true);
    });
  }
"""
replace_once(series, old_series_load, new_series_load)
replace_once(
    series,
    """          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Cargando catálogo de series por Xtream…'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return _SeriesError(
              message: snapshot.error.toString().replaceFirst('Exception: ', ''),
              onRetry: _retry,
            );
          }
""",
    """          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(_progressLabel),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            final rawError = snapshot.error.toString();
            final message = rawError.contains('TimeoutException')
                ? 'El servidor Xtream dejó de enviar datos durante demasiado tiempo. Reintentá la carga de Series.'
                : rawError.replaceFirst('Exception: ', '');
            return _SeriesError(
              message: message,
              onRetry: _retry,
            );
          }
""",
)
old_series_build = """    final allCategories = data.series
        .map((item) => item.category)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final categories = _parental.visibleGroups(allCategories);
    final categoryCounts = <String, int>{};
    for (final item in data.series) {
      if (!_parental.canShowItem(name: item.name, group: item.category)) continue;
      final category = item.category?.trim();
      if (category == null || category.isEmpty) continue;
      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    }
    final visibleTotal = data.series
        .where((item) =>
            _parental.canShowItem(name: item.name, group: item.category))
        .length;

    final normalized = _query.trim().toLowerCase();
    final visible = data.series.where((item) {
      if (!_parental.canShowItem(name: item.name, group: item.category)) {
        return false;
      }
      if (_category != null && item.category != _category) return false;
      if (normalized.isEmpty) return true;
      return item.name.toLowerCase().contains(normalized) ||
          (item.genre?.toLowerCase().contains(normalized) ?? false) ||
          (item.category?.toLowerCase().contains(normalized) ?? false);
    }).toList(growable: false);
"""
new_series_build = """    final categories = _parental.visibleGroups(_catalogCategories);
    final categoryCounts = <String, int>{};
    final visible = <XtreamSeriesSummary>[];
    var visibleTotal = 0;
    final normalized = _query.trim().toLowerCase();

    for (final item in data.series) {
      if (!_parental.canShowItem(name: item.name, group: item.category)) continue;
      visibleTotal++;
      final category = item.category?.trim();
      if (category != null && category.isNotEmpty) {
        categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
      }
      if (_category != null && item.category != _category) continue;
      if (normalized.isNotEmpty &&
          !item.name.toLowerCase().contains(normalized) &&
          !(item.genre?.toLowerCase().contains(normalized) ?? false) &&
          !(item.category?.toLowerCase().contains(normalized) ?? false)) {
        continue;
      }
      visible.add(item);
    }
"""
replace_once(series, old_series_build, new_series_build)


# Guardrails: no playback engine or TV screen may be changed by this patch.
required = {
    'lib/services/xtream_service.dart': ['XtreamHttpClient.instance'],
    'lib/services/xtream_vod_service.dart': ['XtreamHttpClient.instance'],
    'lib/services/xtream_series_service.dart': ['XtreamHttpClient.instance'],
    movies: [
        'loadCachedMovies',
        '_refreshMovieCatalog',
        'Una sola pasada: parental + conteos + categoría + búsqueda.',
    ],
    series: [
        'loadCachedSeries',
        '_refreshSeriesCatalog',
        'final visible = <XtreamSeriesSummary>[];',
    ],
}
for path, needles in required.items():
    text = Path(path).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f'{path}: missing validation marker {needle}')

for forbidden in ['lib/screens/player_screen.dart', 'lib/screens/channel_list_screen.dart']:
    # This script deliberately never writes these files.
    if not Path(forbidden).exists():
        raise SystemExit(f'missing expected untouched file {forbidden}')
