import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'xtream_http_client.dart';
import 'xtream_service.dart';

const String _seriesUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/96.0.4664.18 Safari/537.36';

class XtreamSeriesSummary {
  final String id;
  final String name;
  final String? cover;
  final String? category;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? rating;
  final List<String> backdrops;

  const XtreamSeriesSummary({
    required this.id,
    required this.name,
    this.cover,
    this.category,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.rating,
    this.backdrops = const [],
  });
}

class XtreamSeriesEpisode {
  final String id;
  final int season;
  final int number;
  final String title;
  final String extension;
  final String? directSource;
  final String? plot;
  final String? duration;
  final String? image;
  final String? rating;

  const XtreamSeriesEpisode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    required this.extension,
    this.directSource,
    this.plot,
    this.duration,
    this.image,
    this.rating,
  });

  Channel toChannel(XtreamConnectionResult connection, {String? group}) {
    final direct = _resolveDirect(connection.streamServer, directSource);
    return Channel(
      name: title,
      url: direct ?? _seriesUrl(connection, id, extension),
      logoUrl: _resolveArtwork(connection.streamServer, image),
      group: group,
    );
  }
}

class XtreamSeriesDetails {
  final XtreamSeriesSummary series;
  final Map<int, List<XtreamSeriesEpisode>> seasons;
  const XtreamSeriesDetails({required this.series, required this.seasons});

  List<int> get seasonNumbers {
    // Season order follows provider insertion order where possible. Xtream keys
    // are generally numeric; this getter is only a safe fallback for consumers.
    return seasons.keys.toList(growable: false);
  }
}

class XtreamSeriesService {
  XtreamSeriesService._();
  static final http.Client _client = XtreamHttpClient.instance;
  static const Map<String, String> _headers = {
    'User-Agent': _seriesUserAgent,
    'Accept': 'application/json,text/plain,*/*',
    'Connection': 'keep-alive',
  };

  static Future<List<XtreamSeriesSummary>> fetchCatalog(
    XtreamConnectionResult connection, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final categoriesFuture = _safeActionList(
      connection,
      'get_series_categories',
      const Duration(seconds: 12),
    );
    final rawSeries = await _actionList(connection, 'get_series', timeout);
    final rawCategories = await categoriesFuture;
    final categories = <String, String>{};
    for (final raw in rawCategories) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = _cleanText(item['category_id']);
      final name = _cleanText(item['category_name']);
      if (id != null && name != null) categories[id] = name;
    }

    final series = <XtreamSeriesSummary>[];
    // No A-Z: preserve provider order exactly.
    for (final raw in rawSeries) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = _cleanText(item['series_id']);
      final name = _cleanText(item['name']);
      if (id == null || name == null) continue;
      final categoryId = _cleanText(item['category_id']);
      final categoryName = _firstText(item, const [
        'category_name',
        'category',
      ]);
      series.add(
        XtreamSeriesSummary(
          id: id,
          name: name,
          cover: _resolveArtwork(
            connection.streamServer,
            _cleanText(item['cover']),
          ),
          category: categoryId == null
              ? categoryName
              : categories[categoryId] ?? categoryName,
          plot: _cleanText(item['plot']),
          cast: _cleanText(item['cast']),
          director: _cleanText(item['director']),
          genre: _cleanText(item['genre']),
          releaseDate: _firstText(item, const [
            'releaseDate',
            'release_date',
            'year',
          ]),
          rating: _firstText(item, const ['rating', 'rating_5based']),
          backdrops: _stringList(item['backdrop_path'])
              .map((value) => _resolveArtwork(connection.streamServer, value))
              .whereType<String>()
              .toList(growable: false),
        ),
      );
    }
    return List.unmodifiable(series);
  }

  static Future<XtreamSeriesDetails> fetchDetails(
    XtreamConnectionResult connection,
    XtreamSeriesSummary summary, {
    Duration timeout = const Duration(seconds: 18),
  }) async {
    XtreamHttpClient.cancelBrowsingRequests();
    var active = connection;
    try {
      active = await XtreamService.reconnectFromPlaylistUrl(
        connection.playlistUrl,
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {}

    final uri = _endpoint(active.apiServer, {
      'username': active.username,
      'password': active.password,
      'action': 'get_series_info',
      'series_id': summary.id,
    });
    final response = await _client.get(uri, headers: _headers).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('get_series_info HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Información de serie inválida.');
    }
    final root = Map<String, dynamic>.from(decoded);
    final info = root['info'] is Map
        ? Map<String, dynamic>.from(root['info'] as Map)
        : <String, dynamic>{};
    final enriched = XtreamSeriesSummary(
      id: summary.id,
      name: _cleanText(info['name']) ?? summary.name,
      cover:
          _resolveArtwork(active.streamServer, _cleanText(info['cover'])) ??
          summary.cover,
      category: summary.category,
      plot: _cleanText(info['plot']) ?? summary.plot,
      cast: _cleanText(info['cast']) ?? summary.cast,
      director: _cleanText(info['director']) ?? summary.director,
      genre: _cleanText(info['genre']) ?? summary.genre,
      releaseDate:
          _firstText(info, const ['releaseDate', 'release_date', 'year']) ??
          summary.releaseDate,
      rating:
          _firstText(info, const ['rating', 'rating_5based']) ?? summary.rating,
      backdrops: _stringList(info['backdrop_path']).isEmpty
          ? summary.backdrops
          : _stringList(info['backdrop_path'])
                .map((value) => _resolveArtwork(active.streamServer, value))
                .whereType<String>()
                .toList(growable: false),
    );

    final seasons = <int, List<XtreamSeriesEpisode>>{};
    final rawEpisodes = root['episodes'];
    if (rawEpisodes is Map) {
      for (final entry in rawEpisodes.entries) {
        final fallbackSeason = int.tryParse(entry.key.toString()) ?? 1;
        final values = entry.value;
        if (values is! List) continue;
        for (final raw in values) {
          final episode = _parseEpisode(raw, fallbackSeason, active);
          if (episode == null) continue;
          seasons.putIfAbsent(episode.season, () => []).add(episode);
        }
      }
    } else if (rawEpisodes is List) {
      for (final raw in rawEpisodes) {
        final episode = _parseEpisode(raw, 1, active);
        if (episode == null) continue;
        seasons.putIfAbsent(episode.season, () => []).add(episode);
      }
    }
    if (seasons.isEmpty) {
      throw Exception('El proveedor no devolvió episodios para esta serie.');
    }
    return XtreamSeriesDetails(series: enriched, seasons: seasons);
  }

  static XtreamSeriesEpisode? _parseEpisode(
    dynamic raw,
    int fallbackSeason,
    XtreamConnectionResult connection,
  ) {
    if (raw is! Map) return null;
    final item = Map<String, dynamic>.from(raw);
    final id = _cleanText(item['id']);
    if (id == null) return null;
    final info = item['info'] is Map
        ? Map<String, dynamic>.from(item['info'] as Map)
        : <String, dynamic>{};
    final season =
        int.tryParse(item['season']?.toString() ?? '') ??
        int.tryParse(info['season']?.toString() ?? '') ??
        fallbackSeason;
    final number =
        int.tryParse(item['episode_num']?.toString() ?? '') ??
        int.tryParse(info['episode_num']?.toString() ?? '') ??
        1;
    final rawDirect =
        _firstText(item, const [
          'direct_source',
          'directSource',
          'stream_source',
        ]) ??
        _firstText(info, const [
          'direct_source',
          'directSource',
          'stream_source',
        ]);
    final extension = _firstValidExtension([
      item['container_extension'],
      item['containerExtension'],
      item['extension'],
      info['container_extension'],
      info['containerExtension'],
      info['extension'],
      _extensionFromUrl(rawDirect),
    ]);
    return XtreamSeriesEpisode(
      id: id,
      season: season <= 0 ? 1 : season,
      number: number <= 0 ? 1 : number,
      title:
          _cleanText(item['title']) ??
          _cleanText(info['name']) ??
          'Episodio ${number <= 0 ? id : number}',
      extension: extension,
      directSource:
          _resolveDirect(connection.streamServer, rawDirect) ??
          _seriesUrl(connection, id, extension),
      plot: _cleanText(info['plot']),
      duration: _cleanText(info['duration']),
      image: _resolveArtwork(
        connection.streamServer,
        _firstText(info, const ['movie_image', 'cover_big', 'cover']),
      ),
      rating: _firstText(info, const ['rating', 'rating_5based']),
    );
  }

  static Future<List<dynamic>> _safeActionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
    try {
      return await _actionList(connection, action, timeout);
    } catch (_) {
      return const [];
    }
  }

  static Future<List<dynamic>> _actionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
    final uri = _endpoint(connection.apiServer, {
      'username': connection.username,
      'password': connection.password,
      'action': action,
    });
    final response = await _client.get(uri, headers: _headers).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('Xtream $action respondió HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    return decoded is List ? decoded : const [];
  }
}

String? _resolveDirect(Uri base, String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0')
    return null;
  if (value.startsWith('//')) return '${base.scheme}:$value';
  final parsed = Uri.tryParse(value);
  if (parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty)
    return parsed.toString();
  return value.startsWith('/') ? base.resolve(value).toString() : null;
}

String? _resolveArtwork(Uri base, String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0')
    return null;
  if (value.startsWith('//')) return '${base.scheme}:$value';
  final parsed = Uri.tryParse(value);
  if (parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty)
    return parsed.toString();
  return base.resolve(value).toString();
}

String _seriesUrl(
  XtreamConnectionResult connection,
  String episodeId,
  String extension,
) {
  final prefix = connection.streamServer.pathSegments.where(
    (segment) => segment.trim().isNotEmpty,
  );
  return connection.streamServer
      .replace(
        pathSegments: [
          ...prefix,
          'series',
          connection.username,
          connection.password,
          '$episodeId.$extension',
        ],
        query: '',
        fragment: '',
      )
      .toString();
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

String _firstValidExtension(Iterable<dynamic> candidates) {
  for (final candidate in candidates) {
    final value =
        candidate?.toString().trim().toLowerCase().replaceFirst('.', '') ?? '';
    if (value.isNotEmpty && RegExp(r'^[a-z0-9]{2,6}$').hasMatch(value))
      return value;
  }
  return 'mp4';
}

String? _extensionFromUrl(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  final path = Uri.tryParse(value)?.path ?? value;
  final file = path.substring(path.lastIndexOf('/') + 1);
  final dot = file.lastIndexOf('.');
  return dot < 0 || dot == file.length - 1 ? null : file.substring(dot + 1);
}

String? _cleanText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null' || text == '0') return null;
  return text;
}

String? _firstText(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = _cleanText(map[key]);
    if (value != null) return value;
  }
  return null;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map(_cleanText).whereType<String>().toList(growable: false);
}
