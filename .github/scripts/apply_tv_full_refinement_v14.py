from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'marker not found: {label}')
    return text.replace(old, new, 1)


def replace_between(text: str, start_marker: str, end_marker: str, new_block: str, label: str) -> str:
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'start marker not found: {label}')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'end marker not found: {label}')
    return text[:start] + new_block + text[end:]


# 1) Unified category row: Todos/Todas separated, gold focus, no blur/shadow.
Path('lib/widgets/tv_catalog_category_row.dart').write_text(r'''import 'package:flutter/material.dart';

class TvCatalogCategoryRow extends StatefulWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final bool primary;
  final VoidCallback onTap;

  const TvCatalogCategoryRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
    this.primary = false,
  });

  @override
  State<TvCatalogCategoryRow> createState() => _TvCatalogCategoryRowState();
}

class _TvCatalogCategoryRowState extends State<TvCatalogCategoryRow> {
  static const Color _gold = Color(0xFFD7B45A);
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _focused || widget.selected;
    final borderColor = _focused
        ? _gold
        : widget.primary
            ? const Color(0x66D7B45A)
            : widget.selected
                ? const Color(0x88D7B45A)
                : Colors.transparent;

    final row = Material(
      color: highlighted ? const Color(0xFF252A2F) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(
          color: borderColor,
          width: _focused ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: widget.autofocus,
        onFocusChange: (value) => setState(() => _focused = value),
        onTap: widget.onTap,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _focused ? _gold : Colors.white,
                  fontSize: 14,
                  fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: 2, bottom: widget.primary ? 10 : 2),
      child: widget.primary
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                row,
                const SizedBox(height: 7),
                const Divider(height: 1, thickness: 1, color: Colors.white10),
              ],
            )
          : row,
    );
  }
}
''', encoding='utf-8')


# 2) Artwork priority without increasing concurrent downloads.
Path('lib/widgets/cached_artwork_image.dart').write_text(r'''import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/artwork_cache_service.dart';
import '../services/device_performance_service.dart';

class CachedArtworkImage extends StatefulWidget {
  final String? url;
  final BoxFit fit;
  final Widget fallback;
  final bool allowNetwork;
  final int? cacheWidth;
  final int? cacheHeight;
  final int priority;
  final ValueChanged<bool>? onAvailabilityChanged;
  final double prefetchExtent;

  const CachedArtworkImage({
    super.key,
    required this.url,
    required this.fit,
    required this.fallback,
    this.allowNetwork = true,
    this.cacheWidth,
    this.cacheHeight,
    this.priority = 0,
    this.onAvailabilityChanged,
    this.prefetchExtent = 96,
  });

  @override
  State<CachedArtworkImage> createState() => _CachedArtworkImageState();
}

class _CachedArtworkImageState extends State<CachedArtworkImage> {
  File? _file;
  bool _loading = false;
  bool _interestHeld = false;
  int _requestGeneration = 0;
  String? _retainedUrl;

  @override
  void initState() {
    super.initState();
    _scheduleResolve();
  }

  @override
  void didUpdateWidget(covariant CachedArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.allowNetwork != widget.allowNetwork) {
      _requestGeneration++;
      _loading = false;
      _file = null;
      _releaseInterest();
      widget.onAvailabilityChanged?.call(false);
      _scheduleResolve();
      return;
    }
    if (oldWidget.priority != widget.priority && _file == null) {
      ArtworkCacheService.instance.promote(widget.url, widget.priority);
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _releaseInterest();
    super.dispose();
  }

  void _scheduleResolve() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensureResolved());
    });
  }

  Future<void> _ensureResolved() async {
    if (_file != null || _loading) return;
    final rawUrl = widget.url?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return;

    final service = ArtworkCacheService.instance;
    service.retain(rawUrl);
    _interestHeld = true;
    _retainedUrl = rawUrl;
    _loading = true;
    final generation = ++_requestGeneration;

    final file = await service.resolve(
      rawUrl,
      allowNetwork: widget.allowNetwork,
      demandDriven: true,
      priority: widget.priority,
    );

    if (!mounted || generation != _requestGeneration) return;
    _loading = false;
    _releaseInterest();
    if (file == null) {
      widget.onAvailabilityChanged?.call(false);
      return;
    }
    setState(() => _file = file);
    widget.onAvailabilityChanged?.call(true);
  }

  void _releaseInterest() {
    if (!_interestHeld) return;
    ArtworkCacheService.instance.release(_retainedUrl);
    _interestHeld = false;
    _retainedUrl = null;
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return widget.fallback;
    final profile = DevicePerformanceService.instance;
    return Image.file(
      file,
      fit: widget.fit,
      cacheWidth: profile.artworkDecodeWidth(widget.cacheWidth),
      cacheHeight: profile.artworkDecodeHeight(widget.cacheHeight),
      filterQuality: profile.lowRam ? FilterQuality.low : FilterQuality.medium,
      errorBuilder: (_, __, ___) {
        widget.onAvailabilityChanged?.call(false);
        return widget.fallback;
      },
    );
  }
}
''', encoding='utf-8')

artwork = Path('lib/services/artwork_cache_service.dart')
text = artwork.read_text(encoding='utf-8')
text = replace_once(
    text,
    "  Future<File?> resolve(\n    String? rawUrl, {\n    bool allowNetwork = true,\n    bool demandDriven = false,\n  }) async {",
    "  Future<File?> resolve(\n    String? rawUrl, {\n    bool allowNetwork = true,\n    bool demandDriven = false,\n    int priority = 0,\n  }) async {",
    'artwork resolve priority',
)
text = replace_once(
    text,
    "    final request = _ArtworkRequest(\n      url: url,\n      generation: _generation,\n      demandDriven: demandDriven,\n      completer: completer,\n    );\n    _queue.add(request);",
    "    final request = _ArtworkRequest(\n      url: url,\n      generation: _generation,\n      demandDriven: demandDriven,\n      priority: priority,\n      completer: completer,\n    );\n    _enqueueByPriority(request);",
    'artwork enqueue priority',
)
text = replace_once(
    text,
    "  void _drain() {\n    if (_pausedForPlayback) return;",
    "  void promote(String? rawUrl, int priority) {\n    final url = _validUrl(rawUrl);\n    if (url == null || _queue.isEmpty || priority <= 0) return;\n    final items = _queue.toList(growable: false);\n    var changed = false;\n    for (final item in items) {\n      if (item.url == url && priority > item.priority) {\n        item.priority = priority;\n        changed = true;\n      }\n    }\n    if (!changed) return;\n    items.sort((a, b) => b.priority.compareTo(a.priority));\n    _queue\n      ..clear()\n      ..addAll(items);\n  }\n\n  void _enqueueByPriority(_ArtworkRequest request) {\n    if (_queue.isEmpty) {\n      _queue.addLast(request);\n      return;\n    }\n    final items = _queue.toList(growable: true)..add(request);\n    items.sort((a, b) => b.priority.compareTo(a.priority));\n    _queue\n      ..clear()\n      ..addAll(items);\n  }\n\n  void _drain() {\n    if (_pausedForPlayback) return;",
    'artwork queue helpers',
)
text = replace_once(
    text,
    "class _ArtworkRequest {\n  final String url;\n  final int generation;\n  final bool demandDriven;\n  final Completer<File?> completer;\n  const _ArtworkRequest({\n    required this.url,\n    required this.generation,\n    required this.demandDriven,\n    required this.completer,\n  });\n}",
    "class _ArtworkRequest {\n  final String url;\n  final int generation;\n  final bool demandDriven;\n  int priority;\n  final Completer<File?> completer;\n  _ArtworkRequest({\n    required this.url,\n    required this.generation,\n    required this.demandDriven,\n    required this.priority,\n    required this.completer,\n  });\n}",
    'artwork request priority',
)
artwork.write_text(text, encoding='utf-8')


# 3) Bounded in-memory Xtream snapshots and deduplicated disk cache reads.
fast = Path('lib/services/xtream_fast_catalog_service.dart')
text = fast.read_text(encoding='utf-8')
text = replace_once(
    text,
    "  final Map<String, Future<XtreamConnectionResult>> _pendingSessions =\n      <String, Future<XtreamConnectionResult>>{};\n\n  Directory? _cacheDirectory;",
    "  final Map<String, Future<XtreamConnectionResult>> _pendingSessions =\n      <String, Future<XtreamConnectionResult>>{};\n\n  final Map<String, XtreamMovieCatalogSnapshot> _movieMemory =\n      <String, XtreamMovieCatalogSnapshot>{};\n  final Map<String, XtreamSeriesCatalogSnapshot> _seriesMemory =\n      <String, XtreamSeriesCatalogSnapshot>{};\n  final Map<String, Future<XtreamMovieCatalogSnapshot?>>\n      _pendingMovieCacheReads =\n      <String, Future<XtreamMovieCatalogSnapshot?>>{};\n  final Map<String, Future<XtreamSeriesCatalogSnapshot?>>\n      _pendingSeriesCacheReads =\n      <String, Future<XtreamSeriesCatalogSnapshot?>>{};\n\n  Directory? _cacheDirectory;",
    'xtream memory fields',
)
movie_loader = r'''  Future<XtreamMovieCatalogSnapshot?> loadCachedMovies(
    String playlistUrl,
  ) async {
    final key = playlistUrl.trim();
    final memory = _movieMemory[key];
    if (memory != null) {
      _touchMovieMemory(key, memory);
      return memory;
    }
    final pending = _pendingMovieCacheReads[key];
    if (pending != null) return pending;

    final future = _loadCachedMoviesFromDisk(key);
    _pendingMovieCacheReads[key] = future;
    try {
      final snapshot = await future;
      if (snapshot != null) _rememberMovieSnapshot(key, snapshot);
      return snapshot;
    } finally {
      if (identical(_pendingMovieCacheReads[key], future)) {
        _pendingMovieCacheReads.remove(key);
      }
    }
  }

  Future<XtreamMovieCatalogSnapshot?> _loadCachedMoviesFromDisk(
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

  Future<void> prewarmCachedMovies(String playlistUrl) async {
    await loadCachedMovies(playlistUrl);
  }

'''
text = replace_between(text, '  Future<XtreamMovieCatalogSnapshot?> loadCachedMovies(', '  Future<XtreamSeriesCatalogSnapshot?> loadCachedSeries(', movie_loader, 'movie cache loader')
series_loader = r'''  Future<XtreamSeriesCatalogSnapshot?> loadCachedSeries(
    String playlistUrl,
  ) async {
    final key = playlistUrl.trim();
    final memory = _seriesMemory[key];
    if (memory != null) {
      _touchSeriesMemory(key, memory);
      return memory;
    }
    final pending = _pendingSeriesCacheReads[key];
    if (pending != null) return pending;

    final future = _loadCachedSeriesFromDisk(key);
    _pendingSeriesCacheReads[key] = future;
    try {
      final snapshot = await future;
      if (snapshot != null) _rememberSeriesSnapshot(key, snapshot);
      return snapshot;
    } finally {
      if (identical(_pendingSeriesCacheReads[key], future)) {
        _pendingSeriesCacheReads.remove(key);
      }
    }
  }

  Future<XtreamSeriesCatalogSnapshot?> _loadCachedSeriesFromDisk(
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

  Future<void> prewarmCachedSeries(String playlistUrl) async {
    await loadCachedSeries(playlistUrl);
  }

  void _rememberMovieSnapshot(String key, XtreamMovieCatalogSnapshot snapshot) {
    _movieMemory.remove(key);
    _movieMemory[key] = snapshot;
    while (_movieMemory.length > 2) {
      _movieMemory.remove(_movieMemory.keys.first);
    }
  }

  void _rememberSeriesSnapshot(String key, XtreamSeriesCatalogSnapshot snapshot) {
    _seriesMemory.remove(key);
    _seriesMemory[key] = snapshot;
    while (_seriesMemory.length > 2) {
      _seriesMemory.remove(_seriesMemory.keys.first);
    }
  }

  void _touchMovieMemory(String key, XtreamMovieCatalogSnapshot snapshot) {
    _movieMemory.remove(key);
    _movieMemory[key] = snapshot;
  }

  void _touchSeriesMemory(String key, XtreamSeriesCatalogSnapshot snapshot) {
    _seriesMemory.remove(key);
    _seriesMemory[key] = snapshot;
  }

'''
text = replace_between(text, '  Future<XtreamSeriesCatalogSnapshot?> loadCachedSeries(', '  Future<XtreamMovieCatalogSnapshot> refreshMovies(', series_loader, 'series cache loader')
movie_refresh = r'''  Future<XtreamMovieCatalogSnapshot> refreshMovies(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    final key = playlistUrl.trim();
    var connection = await _connectionForCatalog(
      playlistUrl,
      forceRefresh: forceSessionRefresh,
    );

    try {
      final snapshot = await _fetchMovies(connection, playlistUrl, onProgress);
      _rememberMovieSnapshot(key, snapshot);
      return snapshot;
    } on _XtreamHttpException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 403) rethrow;
      invalidateSession(playlistUrl);
      connection = await connectionForPlaylist(playlistUrl, forceRefresh: true);
      final snapshot = await _fetchMovies(connection, playlistUrl, onProgress);
      _rememberMovieSnapshot(key, snapshot);
      return snapshot;
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
        await _writeMovieCache(playlistUrl, snapshot);
        _rememberMovieSnapshot(key, snapshot);
        return snapshot;
      } catch (_) {
        throw error;
      }
    }
  }

'''
text = replace_between(text, '  Future<XtreamMovieCatalogSnapshot> refreshMovies(', '  Future<XtreamSeriesCatalogSnapshot> refreshSeries(', movie_refresh, 'movie refresh memory')
series_refresh = r'''  Future<XtreamSeriesCatalogSnapshot> refreshSeries(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    final key = playlistUrl.trim();
    final totalWatch = Stopwatch()..start();
    final connectionWatch = Stopwatch()..start();
    var connection = await _connectionForCatalog(
      playlistUrl,
      forceRefresh: forceSessionRefresh,
    );
    connectionWatch.stop();
    var connectionElapsed = connectionWatch.elapsed;

    try {
      final snapshot = await _fetchSeries(
        connection,
        playlistUrl,
        onProgress,
        totalWatch: totalWatch,
        connectionElapsed: connectionElapsed,
      );
      _rememberSeriesSnapshot(key, snapshot);
      return snapshot;
    } on _XtreamHttpException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 403) rethrow;
      invalidateSession(playlistUrl);
      final authWatch = Stopwatch()..start();
      connection = await connectionForPlaylist(playlistUrl, forceRefresh: true);
      authWatch.stop();
      connectionElapsed += authWatch.elapsed;
      final snapshot = await _fetchSeries(
        connection,
        playlistUrl,
        onProgress,
        totalWatch: totalWatch,
        connectionElapsed: connectionElapsed,
      );
      _rememberSeriesSnapshot(key, snapshot);
      return snapshot;
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
        final snapshot = XtreamSeriesCatalogSnapshot(
          connection: connection,
          series: series,
          categories: categories,
          savedAt: DateTime.now(),
          fromCache: false,
        );
        await _writeSeriesCache(playlistUrl, snapshot);
        _rememberSeriesSnapshot(key, snapshot);
        return snapshot;
      } catch (_) {
        throw error;
      }
    }
  }

'''
text = replace_between(text, '  Future<XtreamSeriesCatalogSnapshot> refreshSeries(', '  Future<XtreamMovieCatalogSnapshot> _fetchMovies(', series_refresh, 'series refresh memory')
fast.write_text(text, encoding='utf-8')


# 4) Home: local-cache prewarm only when focus lands on Movies/Series.
source = Path('lib/screens/source_content_screen.dart')
text = source.read_text(encoding='utf-8')
text = replace_once(text, "import '../models/playlist.dart';", "import '../models/playlist.dart';\nimport '../models/playlist_source_type.dart';", 'source playlist type import')
text = replace_once(text, "import '../services/app_update_service.dart';", "import '../services/app_update_service.dart';\nimport '../services/device_performance_service.dart';", 'source profile import')
text = replace_once(text, "import '../services/parental_control_service.dart';", "import '../services/parental_control_service.dart';\nimport '../services/xtream_fast_catalog_service.dart';", 'source prewarm import')
text = replace_once(text, "                        icon: Icons.movie_outlined,\n                        onTap: () => Navigator.of(context).push(", "                        icon: Icons.movie_outlined,\n                        onFocused: () => _prewarmMovies(active),\n                        onTap: () => Navigator.of(context).push(", 'movie focus prewarm')
text = replace_once(text, "                        icon: Icons.video_library_outlined,\n                        onTap: () => Navigator.of(context).push(", "                        icon: Icons.video_library_outlined,\n                        onFocused: () => _prewarmSeries(active),\n                        onTap: () => Navigator.of(context).push(", 'series focus prewarm')
text = replace_once(text, '  Future<void> _handleParentalLock() async {', "  void _prewarmMovies(Playlist playlist) {\n    if (playlist.sourceType != PlaylistSourceType.xtream) return;\n    unawaited(\n      XtreamFastCatalogService.instance.prewarmCachedMovies(playlist.source),\n    );\n  }\n\n  void _prewarmSeries(Playlist playlist) {\n    if (playlist.sourceType != PlaylistSourceType.xtream) return;\n    unawaited(\n      XtreamFastCatalogService.instance.prewarmCachedSeries(playlist.source),\n    );\n  }\n\n  Future<void> _handleParentalLock() async {", 'source prewarm methods')
section_button = r'''class _SectionButton extends StatefulWidget {
  final String eyebrow;
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onFocused;
  final bool autofocus;

  const _SectionButton({
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.onTap,
    this.onFocused,
    this.autofocus = false,
  });

  @override
  State<_SectionButton> createState() => _SectionButtonState();
}

class _SectionButtonState extends State<_SectionButton> {
  static const Color _gold = Color(0xFFD7B45A);
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return AnimatedScale(
      scale: _focused ? (lowRam ? 1.012 : 1.022) : 1,
      duration: Duration(milliseconds: lowRam ? 70 : 100),
      curve: Curves.easeOut,
      child: Material(
        color: _focused ? const Color(0xFF252A2F) : const Color(0xFF0B1622),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: _focused ? _gold : Colors.white10,
            width: _focused ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: widget.autofocus,
          onFocusChange: (value) {
            if (_focused != value) setState(() => _focused = value);
            if (value) widget.onFocused?.call();
          },
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.icon,
                  size: 34,
                  color: _focused ? _gold : Colors.white70,
                ),
                const Spacer(),
                Text(
                  widget.eyebrow,
                  style: TextStyle(
                    color: _focused ? _gold : const Color(0x73FFFFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
'''
start = text.find('class _SectionButton extends StatefulWidget {')
if start < 0:
    raise SystemExit('source section button marker not found')
text = text[:start] + section_button
source.write_text(text, encoding='utf-8')


# 5) LIVE: unified category row, gold/gray focus, logo priority, double-open guard.
live = Path('lib/screens/xtream_live_screen.dart')
text = live.read_text(encoding='utf-8')
text = replace_once(text, "import '../widgets/cached_artwork_image.dart';", "import '../widgets/cached_artwork_image.dart';\nimport '../widgets/tv_catalog_category_row.dart';", 'live category import')
text = replace_once(text, '  bool _searchOpen = false;', '  bool _searchOpen = false;\n  bool _openingPlayer = false;', 'live opening state')
text = replace_once(text, "                return _CategoryRow(\n                  label: category ?? 'Todos',\n                  selected: selected,\n                  autofocus: !_searchOpen && index == 0,", "                return TvCatalogCategoryRow(\n                  label: category ?? 'Todos',\n                  selected: selected,\n                  primary: index == 0,\n                  autofocus: !_searchOpen && index == 0,", 'live primary row')
category_start = text.find('class _CategoryRow extends StatefulWidget {')
channel_start = text.find('class _ChannelRow extends StatefulWidget {')
if category_start < 0 or channel_start <= category_start:
    raise SystemExit('live category class markers not found')
text = text[:category_start] + text[channel_start:]
text = replace_once(text, "  Future<void> _openPlayer(List<Channel> channels, int index) async {\n    final provider = context.read<IptvProvider>();\n    await Navigator.of(context).push(\n      MaterialPageRoute(\n        builder: (_) => PlayerScreen(\n          channel: channels[index],\n          playlist: channels,\n          initialIndex: index,\n          settings: provider.playbackSettings,\n          isLiveContent: true,\n        ),\n      ),\n    );\n  }", "  Future<void> _openPlayer(List<Channel> channels, int index) async {\n    if (_openingPlayer) return;\n    _openingPlayer = true;\n    try {\n      final provider = context.read<IptvProvider>();\n      await Navigator.of(context).push(\n        MaterialPageRoute(\n          builder: (_) => PlayerScreen(\n            channel: channels[index],\n            playlist: channels,\n            initialIndex: index,\n            settings: provider.playbackSettings,\n            isLiveContent: true,\n          ),\n        ),\n      );\n    } finally {\n      _openingPlayer = false;\n    }\n  }", 'live player guard')
text = replace_once(text, "      child: Material(\n        color: _focused ? const Color(0xFF10283B) : const Color(0xFF0A141E),\n        borderRadius: BorderRadius.circular(10),\n        child: InkWell(", "      child: Material(\n        color: _focused ? const Color(0xFF252A2F) : const Color(0xFF0A141E),\n        shape: RoundedRectangleBorder(\n          borderRadius: BorderRadius.circular(10),\n          side: BorderSide(\n            color: _focused ? const Color(0xFFD7B45A) : Colors.white10,\n            width: _focused ? 2 : 1,\n          ),\n        ),\n        clipBehavior: Clip.antiAlias,\n        child: InkWell(", 'live focus surface')
text = replace_once(text, "                      cacheWidth: 80,\n                      cacheHeight: 80,\n                      prefetchExtent: 0,", "                      cacheWidth: 80,\n                      cacheHeight: 80,\n                      priority: _focused ? 100 : 20,\n                      prefetchExtent: 0,", 'live logo priority')
live.write_text(text, encoding='utf-8')


# 6) Movies: preserve provider categories, prepared cache, guard, gold focus.
movies = Path('lib/screens/xtream_movies_screen.dart')
text = movies.read_text(encoding='utf-8')
text = replace_once(text, '  bool _searchOpen = false;', '  bool _searchOpen = false;\n  bool _openingMovie = false;\n  static String? _preparedKey;\n  static _MovieData? _preparedData;', 'movie state')
text = replace_once(text, "  Future<_MovieData> _loadInitial() async {\n    if (widget.playlist.sourceType == PlaylistSourceType.xtream) {\n      final fast = XtreamFastCatalogService.instance;", "  Future<_MovieData> _loadInitial() async {\n    if (widget.playlist.sourceType == PlaylistSourceType.xtream) {\n      final key = widget.playlist.source.trim();\n      final prepared = _preparedData;\n      if (!DevicePerformanceService.instance.lowRam &&\n          _preparedKey == key &&\n          prepared != null) {\n        if (DateTime.now().difference(prepared.savedAt) >= _cacheFreshFor) {\n          unawaited(_refreshXtream());\n        }\n        return prepared;\n      }\n\n      final fast = XtreamFastCatalogService.instance;", 'movie prepared fast path')
text = replace_once(text, '        return _MovieData.xtream(cached.connection, cached.movies);', "        final data = _MovieData.xtream(\n          cached.connection,\n          cached.movies,\n          categories: cached.categories,\n          savedAt: cached.savedAt,\n        );\n        _rememberPrepared(data);\n        return data;", 'movie cached data')
text = replace_once(text, '          return _MovieData.xtream(fresh.connection, fresh.movies);', "          final data = _MovieData.xtream(\n            fresh.connection,\n            fresh.movies,\n            categories: fresh.categories,\n            savedAt: fresh.savedAt,\n          );\n          _rememberPrepared(data);\n          return data;", 'movie fresh data')
text = replace_once(text, "      setState(\n        () => _future = Future.value(\n          _MovieData.xtream(fresh.connection, fresh.movies),\n        ),\n      );", "      final data = _MovieData.xtream(\n        fresh.connection,\n        fresh.movies,\n        categories: fresh.categories,\n        savedAt: fresh.savedAt,\n      );\n      _rememberPrepared(data);\n      setState(() => _future = Future.value(data));", 'movie refreshed data')
text = replace_once(text, '  Future<void> _refreshM3u() async {', "  void _rememberPrepared(_MovieData data) {\n    if (DevicePerformanceService.instance.lowRam) return;\n    _preparedKey = widget.playlist.source.trim();\n    _preparedData = data;\n  }\n\n  Future<void> _refreshM3u() async {", 'movie prepared helper')
text = replace_once(text, "                  label: value ?? 'Todas',\n                  selected: selected,\n                  autofocus: !_searchOpen && index == 0,", "                  label: value ?? 'Todas',\n                  selected: selected,\n                  primary: index == 0,\n                  autofocus: !_searchOpen && index == 0,", 'movie primary row')
old_open_movie = r'''  Future<void> _openMovie(_MovieData data, _MovieItem item) async {
    if (item.summary != null && data.connection != null) {
      XtreamVodDetails details;
      try {
        details = await XtreamVodService.fetchDetails(
          data.connection!,
          item.summary!,
        );
      } catch (_) {
        details = XtreamVodDetails(
          movie: item.summary!,
          extension: item.summary!.extension,
          genre: item.summary!.genre,
          releaseDate: item.summary!.releaseDate,
          rating: item.summary!.rating,
          directSource: item.summary!.directSource,
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _MovieDetailScreen(
            title: item.name,
            poster: item.cover,
            category: item.category,
            plot: details.plot,
            genre: details.genre,
            releaseDate: details.releaseDate,
            rating: details.rating,
            duration: details.duration,
            country: details.country,
            language: details.language,
            originalLanguage: details.originalLanguage,
            audioInfo: details.audioInfo,
            translation: details.translation,
            channel: details.toChannel(data.connection!),
          ),
        ),
      );
      return;
    }

    if (item.channel != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _MovieDetailScreen(
            title: item.name,
            poster: item.cover,
            category: item.category,
            channel: item.channel!,
          ),
        ),
      );
    }
  }
'''
new_open_movie = r'''  Future<void> _openMovie(_MovieData data, _MovieItem item) async {
    if (_openingMovie) return;
    _openingMovie = true;
    try {
      if (item.summary != null && data.connection != null) {
        XtreamVodDetails details;
        try {
          details = await XtreamVodService.fetchDetails(
            data.connection!,
            item.summary!,
          );
        } catch (_) {
          details = XtreamVodDetails(
            movie: item.summary!,
            extension: item.summary!.extension,
            genre: item.summary!.genre,
            releaseDate: item.summary!.releaseDate,
            rating: item.summary!.rating,
            directSource: item.summary!.directSource,
          );
        }
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _MovieDetailScreen(
              title: item.name,
              poster: item.cover,
              category: item.category,
              plot: details.plot,
              genre: details.genre,
              releaseDate: details.releaseDate,
              rating: details.rating,
              duration: details.duration,
              country: details.country,
              language: details.language,
              originalLanguage: details.originalLanguage,
              audioInfo: details.audioInfo,
              translation: details.translation,
              channel: details.toChannel(data.connection!),
            ),
          ),
        );
        return;
      }

      if (item.channel != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _MovieDetailScreen(
              title: item.name,
              poster: item.cover,
              category: item.category,
              channel: item.channel!,
            ),
          ),
        );
      }
    } finally {
      _openingMovie = false;
    }
  }
'''
text = replace_once(text, old_open_movie, new_open_movie, 'movie double open guard')
text = text.replace('const Color(0xFF58B9FF)', 'const Color(0xFFD7B45A)')
text = replace_once(text, "                    cacheWidth: 320,\n                    cacheHeight: 480,\n                    prefetchExtent: 0,", "                    cacheWidth: 320,\n                    cacheHeight: 480,\n                    priority: _focused ? 100 : 10,\n                    prefetchExtent: 0,", 'movie poster priority')
movie_data = r'''class _MovieData {
  final XtreamConnectionResult? connection;
  final List<_MovieItem> items;
  final List<String> categories;
  final DateTime savedAt;

  const _MovieData(
    this.connection,
    this.items,
    this.categories,
    this.savedAt,
  );

  factory _MovieData.xtream(
    XtreamConnectionResult connection,
    List<XtreamVodSummary> movies, {
    List<String> categories = const <String>[],
    DateTime? savedAt,
  }) {
    final items = movies
        .map(
          (item) => _MovieItem(
            name: item.name,
            cover: _resolveArtwork(connection.streamServer, item.cover),
            category: item.category,
            summary: item,
          ),
        )
        .toList(growable: false);
    final resolvedCategories =
        categories.isEmpty ? _collectCategories(items) : categories;
    return _MovieData(
      connection,
      List<_MovieItem>.unmodifiable(items),
      List<String>.unmodifiable(resolvedCategories),
      savedAt ?? DateTime.now(),
    );
  }

  factory _MovieData.m3u(List<Channel> channels) {
    final items = channels
        .map(
          (item) => _MovieItem(
            name: item.name,
            cover: item.logoUrl,
            category: item.group,
            channel: item,
          ),
        )
        .toList(growable: false);
    return _MovieData(
      null,
      List<_MovieItem>.unmodifiable(items),
      List<String>.unmodifiable(_collectCategories(items)),
      DateTime.now(),
    );
  }

  static List<String> _collectCategories(List<_MovieItem> items) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in items) {
      final value = item.category?.trim();
      if (value != null && value.isNotEmpty && seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }
}

'''
text = replace_between(text, 'class _MovieData {', 'class _MovieItem {', movie_data, 'movie data categories')
movies.write_text(text, encoding='utf-8')


# 7) Series mirrors Movies.
series = Path('lib/screens/xtream_series_screen.dart')
text = series.read_text(encoding='utf-8')
text = replace_once(text, '  bool _searchOpen = false;', '  bool _searchOpen = false;\n  bool _openingSeries = false;\n  static String? _preparedKey;\n  static _SeriesData? _preparedData;', 'series state')
text = replace_once(text, "  Future<_SeriesData> _loadInitial() async {\n    if (widget.playlist.sourceType == PlaylistSourceType.xtream) {\n      final fast = XtreamFastCatalogService.instance;", "  Future<_SeriesData> _loadInitial() async {\n    if (widget.playlist.sourceType == PlaylistSourceType.xtream) {\n      final key = widget.playlist.source.trim();\n      final prepared = _preparedData;\n      if (!DevicePerformanceService.instance.lowRam &&\n          _preparedKey == key &&\n          prepared != null) {\n        if (DateTime.now().difference(prepared.savedAt) >= _cacheFreshFor) {\n          unawaited(_refreshXtream());\n        }\n        return prepared;\n      }\n\n      final fast = XtreamFastCatalogService.instance;", 'series prepared fast path')
text = replace_once(text, '        return _SeriesData.xtream(cached.connection, cached.series);', "        final data = _SeriesData.xtream(\n          cached.connection,\n          cached.series,\n          categories: cached.categories,\n          savedAt: cached.savedAt,\n        );\n        _rememberPrepared(data);\n        return data;", 'series cached data')
text = replace_once(text, '          return _SeriesData.xtream(fresh.connection, fresh.series);', "          final data = _SeriesData.xtream(\n            fresh.connection,\n            fresh.series,\n            categories: fresh.categories,\n            savedAt: fresh.savedAt,\n          );\n          _rememberPrepared(data);\n          return data;", 'series fresh data')
text = replace_once(text, "      setState(\n        () => _future = Future.value(\n          _SeriesData.xtream(fresh.connection, fresh.series),\n        ),\n      );", "      final data = _SeriesData.xtream(\n        fresh.connection,\n        fresh.series,\n        categories: fresh.categories,\n        savedAt: fresh.savedAt,\n      );\n      _rememberPrepared(data);\n      setState(() => _future = Future.value(data));", 'series refreshed data')
text = replace_once(text, '  Future<void> _refreshM3u() async {', "  void _rememberPrepared(_SeriesData data) {\n    if (DevicePerformanceService.instance.lowRam) return;\n    _preparedKey = widget.playlist.source.trim();\n    _preparedData = data;\n  }\n\n  Future<void> _refreshM3u() async {", 'series prepared helper')
text = replace_once(text, "                  label: value ?? 'Todas',\n                  selected: selected,\n                  autofocus: !_searchOpen && index == 0,", "                  label: value ?? 'Todas',\n                  selected: selected,\n                  primary: index == 0,\n                  autofocus: !_searchOpen && index == 0,", 'series primary row')
old_open_series = r'''  Future<void> _openSeries(_SeriesData data, _SeriesItem item) async {
    _SeriesDetailModel model;
    if (item.summary != null && data.connection != null) {
      try {
        final details = await XtreamSeriesService.fetchDetails(
          data.connection!,
          item.summary!,
        );
        model = _SeriesDetailModel.fromXtream(data.connection!, details);
      } catch (_) {
        final fallback = await _findM3uSeriesFallback(
          item,
          data.connection!,
        );
        if (fallback == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'El proveedor no devolvió episodios para esta serie.',
              ),
            ),
          );
          return;
        }
        model = _SeriesDetailModel.fromM3u(fallback);
      }
    } else {
      model = _SeriesDetailModel.fromM3u(item);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _SeriesDetailScreen(model: model)),
    );
  }
'''
new_open_series = r'''  Future<void> _openSeries(_SeriesData data, _SeriesItem item) async {
    if (_openingSeries) return;
    _openingSeries = true;
    try {
      _SeriesDetailModel model;
      if (item.summary != null && data.connection != null) {
        try {
          final details = await XtreamSeriesService.fetchDetails(
            data.connection!,
            item.summary!,
          );
          model = _SeriesDetailModel.fromXtream(data.connection!, details);
        } catch (_) {
          final fallback = await _findM3uSeriesFallback(
            item,
            data.connection!,
          );
          if (fallback == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'El proveedor no devolvió episodios para esta serie.',
                ),
              ),
            );
            return;
          }
          model = _SeriesDetailModel.fromM3u(fallback);
        }
      } else {
        model = _SeriesDetailModel.fromM3u(item);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _SeriesDetailScreen(model: model)),
      );
    } finally {
      _openingSeries = false;
    }
  }
'''
text = replace_once(text, old_open_series, new_open_series, 'series double open guard')
text = text.replace('const Color(0xFF58B9FF)', 'const Color(0xFFD7B45A)')
text = replace_once(text, "                    cacheWidth: 320,\n                    cacheHeight: 480,\n                    prefetchExtent: 0,", "                    cacheWidth: 320,\n                    cacheHeight: 480,\n                    priority: _focused ? 100 : 10,\n                    prefetchExtent: 0,", 'series poster priority')
series_data = r'''class _SeriesData {
  final XtreamConnectionResult? connection;
  final List<_SeriesItem> items;
  final List<String> categories;
  final DateTime savedAt;

  const _SeriesData(
    this.connection,
    this.items,
    this.categories,
    this.savedAt,
  );

  factory _SeriesData.xtream(
    XtreamConnectionResult connection,
    List<XtreamSeriesSummary> series, {
    List<String> categories = const <String>[],
    DateTime? savedAt,
  }) {
    final items = series
        .map(
          (item) => _SeriesItem(
            name: item.name,
            cover: _resolveArtwork(connection.streamServer, item.cover),
            category: item.category,
            summary: item,
          ),
        )
        .toList(growable: false);
    final resolvedCategories =
        categories.isEmpty ? _collectCategories(items) : categories;
    return _SeriesData(
      connection,
      List<_SeriesItem>.unmodifiable(items),
      List<String>.unmodifiable(resolvedCategories),
      savedAt ?? DateTime.now(),
    );
  }

  factory _SeriesData.m3u(List<Channel> channels) {
    final byKey = <String, _SeriesItem>{};
    for (final channel in channels) {
      final parsed = _parseM3uEpisode(channel);
      final key = _normalizeSeriesKey(parsed.seriesTitle);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = _SeriesItem(
          name: parsed.seriesTitle,
          cover: channel.logoUrl,
          category: channel.group,
          m3uEpisodes: [parsed],
        );
      } else {
        existing.m3uEpisodes!.add(parsed);
      }
    }
    final items = byKey.values.toList(growable: false);
    return _SeriesData(
      null,
      List<_SeriesItem>.unmodifiable(items),
      List<String>.unmodifiable(_collectCategories(items)),
      DateTime.now(),
    );
  }

  static List<String> _collectCategories(List<_SeriesItem> items) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in items) {
      final value = item.category?.trim();
      if (value != null && value.isNotEmpty && seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }
}

'''
text = replace_between(text, 'class _SeriesData {', 'class _SeriesItem {', series_data, 'series data categories')
series.write_text(text, encoding='utf-8')


# 8) Version bump only. Signing, package id, Media3, DNS and buffers untouched.
pubspec = Path('pubspec.yaml')
text = pubspec.read_text(encoding='utf-8')
text = replace_once(text, 'version: 1.2.1+13', 'version: 1.2.2+14', 'v14 pubspec')
pubspec.write_text(text, encoding='utf-8')

updates = Path('lib/services/app_update_service.dart')
text = updates.read_text(encoding='utf-8')
text = replace_once(text, "  static const int currentVersionCode = 13;\n  static const String currentVersionName = '1.2.1';", "  static const int currentVersionCode = 14;\n  static const String currentVersionName = '1.2.2';", 'v14 updater version')
updates.write_text(text, encoding='utf-8')

print('TV FULL PRO 1.2.2+14 UX/performance patch prepared successfully')
