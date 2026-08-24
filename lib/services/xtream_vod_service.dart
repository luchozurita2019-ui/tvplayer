import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'xtream_http_client.dart';
import 'xtream_service.dart';

const String _vodUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36';

class XtreamVodSummary {
  final String id;
  final String name;
  final String extension;
  final String? cover;
  final String? category;
  final String? rating;
  final String? releaseDate;
  final String? genre;
  final String? directSource;

  const XtreamVodSummary({
    required this.id,
    required this.name,
    required this.extension,
    this.cover,
    this.category,
    this.rating,
    this.releaseDate,
    this.genre,
    this.directSource,
  });

  Channel toChannel(XtreamConnectionResult connection) => Channel(
    name: name,
    url:
        _resolveDirect(connection.streamServer, directSource) ??
        _movieUrl(connection, id, extension),
    logoUrl: _resolveArtwork(connection.streamServer, cover),
    group: category,
  );
}

class XtreamVodDetails {
  final XtreamVodSummary movie;
  final String extension;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? rating;
  final String? duration;
  final String? country;
  final String? backdrop;
  final String? trailerUrl;
  final String? directSource;

  const XtreamVodDetails({
    required this.movie,
    required this.extension,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.rating,
    this.duration,
    this.country,
    this.backdrop,
    this.trailerUrl,
    this.directSource,
  });

  Channel toChannel(XtreamConnectionResult connection) => Channel(
    name: movie.name,
    url:
        _resolveDirect(connection.streamServer, directSource) ??
        _resolveDirect(connection.streamServer, movie.directSource) ??
        _movieUrl(connection, movie.id, extension),
    logoUrl: _resolveArtwork(connection.streamServer, movie.cover),
    group: movie.category,
  );

  Channel? trailerChannel() {
    final value = trailerUrl?.trim() ?? '';
    if (value.isEmpty) return null;
    return Channel(
      name: 'Tráiler · ${movie.name}',
      url: value,
      logoUrl: backdrop ?? movie.cover,
      group: 'Tráiler',
    );
  }
}

class XtreamVodService {
  XtreamVodService._();

  static final http.Client _client = XtreamHttpClient.instance;
  static const _headers = <String, String>{
    'User-Agent': _vodUserAgent,
    'Accept': 'application/json,text/plain,*/*',
    'Connection': 'keep-alive',
  };

  static Future<List<XtreamVodSummary>> fetchCatalog(
    XtreamConnectionResult connection, {
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final categoriesFuture = _safeActionList(
      connection,
      'get_vod_categories',
      const Duration(seconds: 12),
    );
    final streams = await _actionList(connection, 'get_vod_streams', timeout);
    final categories = _categoryMap(await categoriesFuture);
    final movies = <XtreamVodSummary>[];

    // Se conserva exactamente el orden entregado por el proveedor.
    for (final raw in streams) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = _text(item['stream_id']);
      final name = _text(item['name']);
      if (id == null || name == null) continue;
      final categoryId = _text(item['category_id']);
      movies.add(
        XtreamVodSummary(
          id: id,
          name: name,
          extension: _cleanExtension(
            _firstText(item, const ['container_extension', 'extension']),
            fallback: 'mp4',
          ),
          cover: _resolveArtwork(
            connection.streamServer,
            _firstText(item, const ['stream_icon', 'movie_image', 'cover']),
          ),
          category: categoryId == null
              ? _firstText(item, const ['category_name', 'category'])
              : categories[categoryId] ??
                    _firstText(item, const ['category_name', 'category']),
          rating: _firstText(item, const ['rating', 'rating_5based']),
          releaseDate: _firstText(item, const [
            'releasedate',
            'releaseDate',
            'year',
          ]),
          genre: _firstText(item, const ['genre']),
          directSource: _resolveDirect(
            connection.streamServer,
            _firstText(item, const ['direct_source']),
          ),
        ),
      );
    }
    return List.unmodifiable(movies);
  }

  static Future<XtreamVodDetails> fetchDetails(
    XtreamConnectionResult connection,
    XtreamVodSummary summary, {
    Duration timeout = const Duration(seconds: 16),
  }) async {
    XtreamHttpClient.cancelBrowsingRequests();

    var active = connection;
    try {
      active = await XtreamService.reconnectFromPlaylistUrl(
        connection.playlistUrl,
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {}

    final catalogPlayable =
        _resolveDirect(active.streamServer, summary.directSource) ??
        _movieUrl(active, summary.id, summary.extension);

    try {
      final uri = _endpoint(active.apiServer, {
        'username': active.username,
        'password': active.password,
        'action': 'get_vod_info',
        'vod_id': summary.id,
      });
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw Exception('get_vod_info HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Ficha VOD no válida.');
      final root = Map<String, dynamic>.from(decoded);
      final info = root['info'] is Map
          ? Map<String, dynamic>.from(root['info'] as Map)
          : <String, dynamic>{};
      final movieData = root['movie_data'] is Map
          ? Map<String, dynamic>.from(root['movie_data'] as Map)
          : <String, dynamic>{};

      String? pick(List<String> keys) =>
          _firstText(info, keys) ?? _firstText(movieData, keys);
      final extension = _cleanExtension(
        _firstText(movieData, const ['container_extension', 'extension']) ??
            _firstText(info, const ['container_extension', 'extension']) ??
            summary.extension,
        fallback: summary.extension,
      );
      final direct =
          _resolveDirect(
            active.streamServer,
            _firstText(movieData, const ['direct_source']) ??
                _firstText(info, const ['direct_source']),
          ) ??
          _resolveDirect(active.streamServer, summary.directSource) ??
          _movieUrl(active, summary.id, extension);
      final backdrop = _resolveArtwork(
        active.streamServer,
        _firstImage(
              info['backdrop_path'] ?? info['backdrop'] ?? info['backdrops'],
            ) ??
            pick(const ['backdrop_path', 'backdrop', 'cover_big']),
      );

      return XtreamVodDetails(
        movie: summary,
        extension: extension,
        plot: pick(const ['plot', 'description', 'overview']),
        cast: pick(const ['cast', 'actors']),
        director: pick(const ['director']),
        genre: pick(const ['genre']) ?? summary.genre,
        releaseDate:
            pick(const [
              'releasedate',
              'releaseDate',
              'release_date',
              'year',
            ]) ??
            summary.releaseDate,
        rating: pick(const ['rating', 'rating_5based']) ?? summary.rating,
        duration: pick(const ['duration', 'duration_secs']),
        country: pick(const ['country']),
        backdrop: backdrop,
        trailerUrl: _playableTrailer(
          _firstText(info, const [
                'trailer_url',
                'trailer',
                'youtube_trailer',
              ]) ??
              _firstText(movieData, const [
                'trailer_url',
                'trailer',
                'youtube_trailer',
              ]),
        ),
        directSource: direct,
      );
    } catch (_) {
      return XtreamVodDetails(
        movie: summary,
        extension: summary.extension,
        genre: summary.genre,
        releaseDate: summary.releaseDate,
        rating: summary.rating,
        directSource: catalogPlayable,
      );
    }
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
    final request = http.Request('GET', uri)..headers.addAll(_headers);
    final response = await _client.send(request).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('Xtream $action respondió HTTP ${response.statusCode}.');
    }
    final body = await response.stream
        .transform(utf8.decoder)
        .timeout(timeout)
        .join();
    final decoded = jsonDecode(body);
    return decoded is List ? decoded : const [];
  }

  static Map<String, String> _categoryMap(List<dynamic> raw) {
    final result = <String, String>{};
    for (final value in raw) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final id = _text(item['category_id']);
      final name = _text(item['category_name']);
      if (id != null && name != null) result[id] = name;
    }
    return result;
  }

  static String? _firstText(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = _text(source[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? _text(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null' || value == '0') {
      return null;
    }
    return value;
  }

  static String? _firstImage(dynamic raw) {
    if (raw is List) {
      for (final value in raw) {
        final text = _text(value);
        if (text != null) return text;
      }
    }
    if (raw is String) {
      final value = raw.trim();
      if (value.startsWith('[')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is List) return _firstImage(decoded);
        } catch (_) {}
      }
      return _text(value);
    }
    return null;
  }

  static String? _playableTrailer(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'null') return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty)
      return null;
    final host = uri.host.toLowerCase();
    if (host.contains('youtube.com') ||
        host == 'youtu.be' ||
        host.contains('vimeo.com')) {
      return null;
    }
    return uri.toString();
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

String _movieUrl(
  XtreamConnectionResult connection,
  String streamId,
  String extension,
) {
  final base = connection.streamServer;
  final prefix = base.pathSegments.where((e) => e.trim().isNotEmpty);
  return base
      .replace(
        pathSegments: [
          ...prefix,
          'movie',
          connection.username,
          connection.password,
          '$streamId.$extension',
        ],
        query: '',
        fragment: '',
      )
      .toString();
}

String _cleanExtension(String? raw, {required String fallback}) {
  final value = (raw ?? '').trim().toLowerCase().replaceFirst('.', '');
  if (value.isEmpty || !RegExp(r'^[a-z0-9]{2,6}$').hasMatch(value)) {
    return fallback;
  }
  return value;
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
