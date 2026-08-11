import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'xtream_http_client.dart';
import 'xtream_series_service.dart';
import 'xtream_service.dart';
import 'xtream_vod_service.dart';

typedef XtreamCatalogProgressCallback = void Function(
  XtreamCatalogProgress progress,
);

class XtreamCatalogProgress {
  final String section;
  final String phase;
  final int step;
  final int totalSteps;
  final int receivedBytes;

  const XtreamCatalogProgress({
    required this.section,
    required this.phase,
    required this.step,
    required this.totalSteps,
    this.receivedBytes = 0,
  });

  String get label {
    final kb = receivedBytes / 1024;
    final size = receivedBytes <= 0 ? '' : ' (${kb.toStringAsFixed(kb < 10 ? 2 : 1)} KB)';
    return '$phase $section… $step/$totalSteps$size';
  }
}

class XtreamMovieCatalogSnapshot {
  final XtreamConnectionResult connection;
  final List<XtreamVodSummary> movies;
  final List<String> categories;
  final DateTime savedAt;
  final bool fromCache;

  const XtreamMovieCatalogSnapshot({
    required this.connection,
    required this.movies,
    required this.categories,
    required this.savedAt,
    required this.fromCache,
  });
}

class XtreamSeriesCatalogSnapshot {
  final XtreamConnectionResult connection;
  final List<XtreamSeriesSummary> series;
  final List<String> categories;
  final DateTime savedAt;
  final bool fromCache;

  const XtreamSeriesCatalogSnapshot({
    required this.connection,
    required this.series,
    required this.categories,
    required this.savedAt,
    required this.fromCache,
  });
}

/// Motor rápido de catálogos Xtream inspirado en el pipeline observado en
/// Hot Player, pero manteniendo los fallbacks de TV FULL.
///
/// Principios:
/// - la autenticación Xtream se conserva en memoria durante la sesión;
/// - categorías y contenido reutilizan un mismo cliente HTTP keep-alive;
/// - el cuerpo se recibe como stream con timeout por inactividad;
/// - jsonDecode, normalización y ordenamiento se ejecutan en un isolate;
/// - el catálogo normalizado se guarda en disco para apertura inmediata;
/// - las imágenes NO forman parte de esta carga y siguen su cola independiente.
class XtreamFastCatalogService {
  XtreamFastCatalogService._();

  static final XtreamFastCatalogService instance = XtreamFastCatalogService._();

  static const int _cacheVersion = 1;
  static const Duration _categoryTimeout = Duration(seconds: 12);
  static const Duration _movieTimeout = Duration(seconds: 35);
  static const Duration _seriesTimeout = Duration(seconds: 35);

  final Map<String, XtreamConnectionResult> _sessions =
      <String, XtreamConnectionResult>{};
  final Map<String, Future<XtreamConnectionResult>> _pendingSessions =
      <String, Future<XtreamConnectionResult>>{};

  Directory? _cacheDirectory;

  Future<XtreamConnectionResult> connectionForPlaylist(
    String playlistUrl, {
    bool forceRefresh = false,
  }) async {
    final key = playlistUrl.trim();
    if (!forceRefresh) {
      final cached = _sessions[key];
      if (cached != null) return cached;
      final pending = _pendingSessions[key];
      if (pending != null) return pending;
    }

    final future = XtreamService.reconnectFromPlaylistUrl(key);
    _pendingSessions[key] = future;
    try {
      final connection = await future;
      _sessions[key] = connection;
      _sessions[connection.playlistUrl] = connection;
      return connection;
    } finally {
      if (identical(_pendingSessions[key], future)) {
        _pendingSessions.remove(key);
      }
    }
  }

  void rememberConnection(XtreamConnectionResult connection) {
    _sessions[connection.playlistUrl] = connection;
  }

  void invalidateSession(String playlistUrl) {
    _sessions.remove(playlistUrl.trim());
  }

  Future<XtreamMovieCatalogSnapshot?> loadCachedMovies(
    String playlistUrl,
  ) async {
    final raw = await _readCache(playlistUrl, 'movies');
    if (raw == null) return null;
    try {
      final payload = await compute(_decodeCachePayload, raw);
      if (payload['version'] != _cacheVersion || payload['kind'] != 'movies') {
        return null;
      }
      final connection = _connectionFromMap(payload['connection']);
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

  Future<XtreamSeriesCatalogSnapshot?> loadCachedSeries(
    String playlistUrl,
  ) async {
    final raw = await _readCache(playlistUrl, 'series');
    if (raw == null) return null;
    try {
      final payload = await compute(_decodeCachePayload, raw);
      if (payload['version'] != _cacheVersion || payload['kind'] != 'series') {
        return null;
      }
      final connection = _connectionFromMap(payload['connection']);
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

  Future<XtreamMovieCatalogSnapshot> refreshMovies(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    var connection = await connectionForPlaylist(
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
    } catch (error) {
      // Compatibilidad: si un clon Xtream devuelve una estructura que nuestro
      // preparador rápido no entiende, conservamos el cargador probado anterior.
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

  Future<XtreamSeriesCatalogSnapshot> refreshSeries(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    var connection = await connectionForPlaylist(
      playlistUrl,
      forceRefresh: forceSessionRefresh,
    );

    try {
      return await _fetchSeries(connection, playlistUrl, onProgress);
    } on _XtreamHttpException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 403) rethrow;
      invalidateSession(playlistUrl);
      connection = await connectionForPlaylist(playlistUrl, forceRefresh: true);
      return _fetchSeries(connection, playlistUrl, onProgress);
    } catch (error) {
      try {
        final series = await XtreamSeriesService.fetchCatalog(connection);
        final categories = _categoriesFromSeries(series);
        final snapshot = XtreamSeriesCatalogSnapshot(
          connection: connection,
          series: series,
          categories: categories,
          savedAt: DateTime.now(),
          fromCache: false,
        );
        unawaited(_writeSeriesCache(playlistUrl, snapshot));
        return snapshot;
      } catch (_) {
        throw error;
      }
    }
  }

  Future<XtreamMovieCatalogSnapshot> _fetchMovies(
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
        onBytes: (bytes) => onProgress?.call(XtreamCatalogProgress(
          section: 'MOVIE',
          phase: 'Cargando categorías',
          step: 1,
          totalSteps: 2,
          receivedBytes: bytes,
        )),
      );
    } catch (_) {
      // Muchos clones entregan category_name dentro de get_vod_streams.
      categoriesBody = '[]';
    }

    onProgress?.call(const XtreamCatalogProgress(
      section: 'MOVIE',
      phase: 'Cargando lista',
      step: 2,
      totalSteps: 2,
    ));
    final itemsBody = await _downloadActionBody(
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
    final prepared = await compute(_prepareMovieCatalog, <String, String>{
      'categories': categoriesBody,
      'items': itemsBody,
    });
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
    rememberConnection(connection);
    unawaited(_writeMovieCache(playlistUrl, snapshot));
    return snapshot;
  }

  Future<XtreamSeriesCatalogSnapshot> _fetchSeries(
    XtreamConnectionResult connection,
    String playlistUrl,
    XtreamCatalogProgressCallback? onProgress,
  ) async {
    onProgress?.call(const XtreamCatalogProgress(
      section: 'SERIES',
      phase: 'Cargando categorías',
      step: 1,
      totalSteps: 2,
    ));

    String categoriesBody = '[]';
    try {
      categoriesBody = await _downloadActionBody(
        connection,
        'get_series_categories',
        _categoryTimeout,
        onBytes: (bytes) => onProgress?.call(XtreamCatalogProgress(
          section: 'SERIES',
          phase: 'Cargando categorías',
          step: 1,
          totalSteps: 2,
          receivedBytes: bytes,
        )),
      );
    } catch (_) {
      categoriesBody = '[]';
    }

    onProgress?.call(const XtreamCatalogProgress(
      section: 'SERIES',
      phase: 'Cargando lista',
      step: 2,
      totalSteps: 2,
    ));
    final itemsBody = await _downloadActionBody(
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
    final prepared = await compute(_prepareSeriesCatalog, <String, String>{
      'categories': categoriesBody,
      'items': itemsBody,
    });
    final series = _seriesListFromPrepared(prepared['items']);
    if (series.isEmpty) {
      throw const FormatException('Xtream no devolvió series válidas.');
    }
    final categories = _stringList(prepared['categories']);
    final snapshot = XtreamSeriesCatalogSnapshot(
      connection: connection,
      series: List<XtreamSeriesSummary>.unmodifiable(series),
      categories: List<String>.unmodifiable(categories),
      savedAt: DateTime.now(),
      fromCache: false,
    );
    rememberConnection(connection);
    unawaited(_writeSeriesCache(playlistUrl, snapshot));
    return snapshot;
  }

  Future<String> _downloadActionBody(
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
        .timeout(inactivityTimeout);
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

  Future<String?> _readCache(String playlistUrl, String kind) async {
    try {
      final file = await _cacheFile(playlistUrl, kind);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMovieCache(
    String playlistUrl,
    XtreamMovieCatalogSnapshot snapshot,
  ) async {
    final payload = <String, dynamic>{
      'version': _cacheVersion,
      'kind': 'movies',
      'savedAt': snapshot.savedAt.millisecondsSinceEpoch,
      'connection': _connectionToMap(snapshot.connection),
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
      'connection': _connectionToMap(snapshot.connection),
      'categories': snapshot.categories,
      'items': snapshot.series.map(_seriesToMap).toList(growable: false),
    };
    await _writeCache(playlistUrl, 'series', payload);
  }

  Future<void> _writeCache(
    String playlistUrl,
    String kind,
    Map<String, dynamic> payload,
  ) async {
    try {
      final encoded = await compute(_encodeCachePayload, payload);
      final file = await _cacheFile(playlistUrl, kind);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(encoded, flush: false);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (_) {
      // Un fallo de caché nunca debe impedir usar el catálogo descargado.
    }
  }

  Future<File> _cacheFile(String playlistUrl, String kind) async {
    final directory = await _ensureCacheDirectory();
    final digest = sha256.convert(utf8.encode(playlistUrl.trim())).toString();
    return File('${directory.path}/${digest.substring(0, 24)}_$kind.json');
  }

  Future<Directory> _ensureCacheDirectory() async {
    final current = _cacheDirectory;
    if (current != null) return current;
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/tv_full_xtream_catalog_cache');
    if (!await directory.exists()) await directory.create(recursive: true);
    _cacheDirectory = directory;
    return directory;
  }
}

class _XtreamHttpException implements Exception {
  final String action;
  final int statusCode;

  const _XtreamHttpException(this.action, this.statusCode);

  @override
  String toString() => 'Xtream $action respondió HTTP $statusCode.';
}

Map<String, dynamic> _prepareMovieCatalog(Map<String, String> input) {
  final categories = _categoryMapFromJson(input['categories'] ?? '[]');
  final rawItems = _jsonList(input['items'] ?? '[]');
  final items = <Map<String, dynamic>>[];
  final foundCategories = <String>{};

  for (final raw in rawItems) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    final id = _cleanText(item['stream_id']);
    final name = _cleanText(item['name']);
    if (id == null || name == null) continue;
    final categoryId = _cleanText(item['category_id']);
    final fallbackCategory =
        _firstText(item, const <String>['category_name', 'category']);
    final category = categoryId == null
        ? fallbackCategory
        : categories[categoryId] ?? fallbackCategory;
    if (category != null) foundCategories.add(category);

    items.add(<String, dynamic>{
      'id': id,
      'name': name,
      'extension': _cleanExtension(
        _firstText(item, const <String>['container_extension', 'extension']),
        'mp4',
      ),
      'cover': _firstText(
        item,
        const <String>['stream_icon', 'movie_image', 'cover'],
      ),
      'category': category,
      'rating': _firstText(item, const <String>['rating', 'rating_5based']),
      'releaseDate': _firstText(
        item,
        const <String>['releasedate', 'releaseDate', 'year'],
      ),
      'genre': _cleanText(item['genre']),
      'directSource': _cleanText(item['direct_source']),
    });
  }

  items.sort((a, b) =>
      (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
  final categoryList = foundCategories.toList()..sort();
  return <String, dynamic>{
    'items': items,
    'categories': categoryList,
  };
}

Map<String, dynamic> _prepareSeriesCatalog(Map<String, String> input) {
  final categories = _categoryMapFromJson(input['categories'] ?? '[]');
  final rawItems = _jsonList(input['items'] ?? '[]');
  final items = <Map<String, dynamic>>[];
  final foundCategories = <String>{};

  for (final raw in rawItems) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    final id = _cleanText(item['series_id']);
    final name = _cleanText(item['name']);
    if (id == null || name == null) continue;
    final categoryId = _cleanText(item['category_id']);
    final fallbackCategory =
        _firstText(item, const <String>['category_name', 'category']);
    final category = categoryId == null
        ? fallbackCategory
        : categories[categoryId] ?? fallbackCategory;
    if (category != null) foundCategories.add(category);

    items.add(<String, dynamic>{
      'id': id,
      'name': name,
      'cover': _cleanText(item['cover']),
      'category': category,
      'plot': _cleanText(item['plot']),
      'cast': _cleanText(item['cast']),
      'director': _cleanText(item['director']),
      'genre': _cleanText(item['genre']),
      'releaseDate': _firstText(
        item,
        const <String>['releaseDate', 'release_date'],
      ),
      'rating': _firstText(item, const <String>['rating', 'rating_5based']),
      'backdrops': _stringListDynamic(item['backdrop_path']),
    });
  }

  items.sort((a, b) =>
      (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
  final categoryList = foundCategories.toList()..sort();
  return <String, dynamic>{
    'items': items,
    'categories': categoryList,
  };
}

Map<String, dynamic> _decodeCachePayload(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) throw const FormatException('Caché Xtream inválida.');
  return Map<String, dynamic>.from(decoded);
}

String _encodeCachePayload(Map<String, dynamic> payload) => jsonEncode(payload);

List<dynamic> _jsonList(String raw) {
  final decoded = jsonDecode(raw);
  return decoded is List ? decoded : const <dynamic>[];
}

Map<String, String> _categoryMapFromJson(String raw) {
  final result = <String, String>{};
  try {
    for (final value in _jsonList(raw)) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final id = _cleanText(item['category_id']);
      final name = _cleanText(item['category_name']);
      if (id != null && name != null) result[id] = name;
    }
  } catch (_) {}
  return result;
}

List<XtreamVodSummary> _movieListFromPrepared(dynamic raw) {
  if (raw is! List) return const <XtreamVodSummary>[];
  final result = <XtreamVodSummary>[];
  for (final value in raw) {
    if (value is! Map) continue;
    final item = Map<String, dynamic>.from(value);
    final id = _cleanText(item['id']);
    final name = _cleanText(item['name']);
    if (id == null || name == null) continue;
    result.add(XtreamVodSummary(
      id: id,
      name: name,
      extension: _cleanExtension(_cleanText(item['extension']), 'mp4'),
      cover: _cleanText(item['cover']),
      category: _cleanText(item['category']),
      rating: _cleanText(item['rating']),
      releaseDate: _cleanText(item['releaseDate']),
      genre: _cleanText(item['genre']),
      directSource: _cleanText(item['directSource']),
    ));
  }
  return result;
}

List<XtreamSeriesSummary> _seriesListFromPrepared(dynamic raw) {
  if (raw is! List) return const <XtreamSeriesSummary>[];
  final result = <XtreamSeriesSummary>[];
  for (final value in raw) {
    if (value is! Map) continue;
    final item = Map<String, dynamic>.from(value);
    final id = _cleanText(item['id']);
    final name = _cleanText(item['name']);
    if (id == null || name == null) continue;
    result.add(XtreamSeriesSummary(
      id: id,
      name: name,
      cover: _cleanText(item['cover']),
      category: _cleanText(item['category']),
      plot: _cleanText(item['plot']),
      cast: _cleanText(item['cast']),
      director: _cleanText(item['director']),
      genre: _cleanText(item['genre']),
      releaseDate: _cleanText(item['releaseDate']),
      rating: _cleanText(item['rating']),
      backdrops: _stringList(item['backdrops']),
    ));
  }
  return result;
}

Map<String, dynamic> _movieToMap(XtreamVodSummary movie) => <String, dynamic>{
      'id': movie.id,
      'name': movie.name,
      'extension': movie.extension,
      'cover': movie.cover,
      'category': movie.category,
      'rating': movie.rating,
      'releaseDate': movie.releaseDate,
      'genre': movie.genre,
      'directSource': movie.directSource,
    };

Map<String, dynamic> _seriesToMap(XtreamSeriesSummary series) => <String, dynamic>{
      'id': series.id,
      'name': series.name,
      'cover': series.cover,
      'category': series.category,
      'plot': series.plot,
      'cast': series.cast,
      'director': series.director,
      'genre': series.genre,
      'releaseDate': series.releaseDate,
      'rating': series.rating,
      'backdrops': series.backdrops,
    };

Map<String, dynamic> _connectionToMap(XtreamConnectionResult connection) =>
    <String, dynamic>{
      'playlistUrl': connection.playlistUrl,
      'apiServer': connection.apiServer.toString(),
      'streamServer': connection.streamServer.toString(),
      'username': connection.username,
      'password': connection.password,
      'serverName': connection.serverName,
      'status': connection.status,
      'expiration': connection.expiration?.millisecondsSinceEpoch,
    };

XtreamConnectionResult? _connectionFromMap(dynamic raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  final playlistUrl = _cleanText(map['playlistUrl']);
  final apiServerRaw = _cleanText(map['apiServer']);
  final streamServerRaw = _cleanText(map['streamServer']);
  final username = _cleanText(map['username']);
  final password = _cleanText(map['password']);
  final apiServer = apiServerRaw == null ? null : Uri.tryParse(apiServerRaw);
  final streamServer =
      streamServerRaw == null ? null : Uri.tryParse(streamServerRaw);
  if (playlistUrl == null ||
      apiServer == null ||
      streamServer == null ||
      username == null ||
      password == null) {
    return null;
  }
  return XtreamConnectionResult(
    playlistUrl: playlistUrl,
    apiServer: apiServer,
    streamServer: streamServer,
    username: username,
    password: password,
    serverName: _cleanText(map['serverName']),
    status: _cleanText(map['status']),
    expiration: _dateFromMillis(map['expiration']),
  );
}

List<String> _categoriesFromMovies(List<XtreamVodSummary> movies) {
  final categories = <String>{};
  for (final movie in movies) {
    final value = movie.category?.trim();
    if (value != null && value.isNotEmpty) categories.add(value);
  }
  final result = categories.toList()..sort();
  return List<String>.unmodifiable(result);
}

List<String> _categoriesFromSeries(List<XtreamSeriesSummary> series) {
  final categories = <String>{};
  for (final item in series) {
    final value = item.category?.trim();
    if (value != null && value.isNotEmpty) categories.add(value);
  }
  final result = categories.toList()..sort();
  return List<String>.unmodifiable(result);
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map(_cleanText)
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

List<String> _stringListDynamic(dynamic raw) {
  if (raw is List) return _stringList(raw);
  if (raw is String) {
    final value = raw.trim();
    if (value.startsWith('[')) {
      try {
        return _stringList(jsonDecode(value));
      } catch (_) {}
    }
    final clean = _cleanText(value);
    return clean == null ? const <String>[] : <String>[clean];
  }
  return const <String>[];
}

String? _firstText(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = _cleanText(source[key]);
    if (value != null) return value;
  }
  return null;
}

String? _cleanText(dynamic raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty || value.toLowerCase() == 'null') return null;
  return value;
}

String _cleanExtension(String? raw, String fallback) {
  final value = (raw ?? '').trim().toLowerCase().replaceFirst('.', '');
  if (value.isEmpty || !RegExp(r'^[a-z0-9]{2,6}$').hasMatch(value)) {
    return fallback;
  }
  return value;
}

DateTime? _dateFromMillis(dynamic raw) {
  final millis = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  if (millis == null || millis <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

Uri _endpoint(Uri base, Map<String, String> query) {
  var path = base.path;
  if (path.isEmpty || path == '/') {
    path = '/player_api.php';
  } else {
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    path = '$path/player_api.php';
  }
  return base.replace(path: path, queryParameters: query, fragment: '');
}
