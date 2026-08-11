import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'xtream_service.dart';
import 'xtream_http_client.dart';

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
    // Algunos paneles Xtream entregan una URL exacta por episodio. Si existe,
    // es más fiable que reconstruir /series/... porque puede apuntar a otro
    // host, CDN, puerto o contenedor.
    final direct = _resolvedEpisodeDirectSource(
      connection.streamServer,
      directSource,
    );

    final prefix = connection.streamServer.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    final generated = connection.streamServer
        .replace(
          pathSegments: [
            ...prefix,
            'series',
            connection.username,
            connection.password,
            '$id.$extension',
          ],
          query: '',
          fragment: '',
        )
        .toString();

    return Channel(
      name: title,
      url: direct ?? generated,
      logoUrl: image,
      group: group,
    );
  }

  static String? _resolvedEpisodeDirectSource(Uri base, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'null' || value == '0') {
      return null;
    }
    final parsed = Uri.tryParse(value);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) {
      return parsed.toString();
    }
    if (value.startsWith('/')) return base.resolve(value).toString();
    return null;
  }
}

class XtreamSeriesDetails {
  final XtreamSeriesSummary series;
  final Map<int, List<XtreamSeriesEpisode>> seasons;

  const XtreamSeriesDetails({
    required this.series,
    required this.seasons,
  });

  List<int> get seasonNumbers {
    final values = seasons.keys.toList()..sort();
    return values;
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
    Duration timeout = const Duration(seconds: 18),
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
      final id = item['category_id']?.toString().trim() ?? '';
      final name = item['category_name']?.toString().trim() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) categories[id] = name;
    }

    final series = <XtreamSeriesSummary>[];
    for (final raw in rawSeries) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = item['series_id']?.toString().trim() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final categoryId = _cleanText(item['category_id']);
      final categoryName = _firstText(
        item,
        const ['category_name', 'category'],
      );
      series.add(
        XtreamSeriesSummary(
          id: id,
          name: name,
          cover: _cleanText(item['cover']),
          category: categoryId == null
              ? categoryName
              : categories[categoryId] ?? categoryName,
          plot: _cleanText(item['plot']),
          cast: _cleanText(item['cast']),
          director: _cleanText(item['director']),
          genre: _cleanText(item['genre']),
          releaseDate: _firstText(item, const ['releaseDate', 'release_date']),
          rating: _firstText(item, const ['rating', 'rating_5based']),
          backdrops: _stringList(item['backdrop_path']),
        ),
      );
    }

    series.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(series);
  }

  static Future<XtreamSeriesDetails> fetchDetails(
    XtreamConnectionResult connection,
    XtreamSeriesSummary summary, {
    Duration timeout = const Duration(seconds: 18),
  }) async {
    // Una selección de serie tiene prioridad sobre cualquier refresco completo
    // que haya quedado descargándose detrás del catálogo local.
    XtreamHttpClient.cancelBrowsingRequests();

    var activeConnection = connection;
    try {
      activeConnection = await XtreamService.reconnectFromPlaylistUrl(
        connection.playlistUrl,
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {
      // Conservamos como fallback la conexión con la que se abrió el catálogo.
    }

    final uri = _endpoint(
      activeConnection.apiServer,
      <String, String>{
        'username': activeConnection.username,
        'password': activeConnection.password,
        'action': 'get_series_info',
        'series_id': summary.id,
      },
    );

    final response = await _client.get(uri, headers: _headers).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        'Xtream get_series_info respondió HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('El proveedor no devolvió información válida de la serie.');
    }
    final root = Map<String, dynamic>.from(decoded);
    final infoRaw = root['info'];
    final info = infoRaw is Map
        ? Map<String, dynamic>.from(infoRaw)
        : const <String, dynamic>{};

    final enriched = XtreamSeriesSummary(
      id: summary.id,
      name: _cleanText(info['name']) ?? summary.name,
      cover: _cleanText(info['cover']) ?? summary.cover,
      category: summary.category,
      plot: _cleanText(info['plot']) ?? summary.plot,
      cast: _cleanText(info['cast']) ?? summary.cast,
      director: _cleanText(info['director']) ?? summary.director,
      genre: _cleanText(info['genre']) ?? summary.genre,
      releaseDate: _firstText(info, const ['releaseDate', 'release_date']) ??
          summary.releaseDate,
      rating:
          _firstText(info, const ['rating', 'rating_5based']) ?? summary.rating,
      backdrops: _stringList(info['backdrop_path']).isNotEmpty
          ? _stringList(info['backdrop_path'])
          : summary.backdrops,
    );

    final seasons = <int, List<XtreamSeriesEpisode>>{};
    final episodesRaw = root['episodes'];
    if (episodesRaw is Map) {
      for (final entry in episodesRaw.entries) {
        final seasonFromKey = int.tryParse(entry.key.toString()) ?? 0;
        final values = entry.value;
        if (values is! List) continue;
        for (final rawEpisode in values) {
          final episode = _parseEpisode(
            rawEpisode,
            seasonFromKey,
            activeConnection,
          );
          if (episode == null) continue;
          seasons
              .putIfAbsent(episode.season, () => <XtreamSeriesEpisode>[])
              .add(episode);
        }
      }
    } else if (episodesRaw is List) {
      for (final rawEpisode in episodesRaw) {
        final episode = _parseEpisode(rawEpisode, 0, activeConnection);
        if (episode == null) continue;
        seasons
            .putIfAbsent(episode.season, () => <XtreamSeriesEpisode>[])
            .add(episode);
      }
    }

    for (final list in seasons.values) {
      list.sort((a, b) => a.number.compareTo(b.number));
    }

    if (seasons.isEmpty) {
      throw Exception(
        'La serie existe, pero el proveedor no devolvió episodios mediante get_series_info.',
      );
    }

    return XtreamSeriesDetails(series: enriched, seasons: seasons);
  }

  static XtreamSeriesEpisode? _parseEpisode(
    dynamic raw,
    int seasonFallback,
    XtreamConnectionResult activeConnection,
  ) {
    if (raw is! Map) return null;
    final item = Map<String, dynamic>.from(raw);
    final id = item['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;

    final infoRaw = item['info'];
    final info = infoRaw is Map
        ? Map<String, dynamic>.from(infoRaw)
        : const <String, dynamic>{};
    final season = int.tryParse(item['season']?.toString() ?? '') ??
        int.tryParse(info['season']?.toString() ?? '') ??
        seasonFallback;
    final number = int.tryParse(item['episode_num']?.toString() ?? '') ??
        int.tryParse(info['episode_num']?.toString() ?? '') ??
        0;
    final title = _cleanText(item['title']) ??
        _cleanText(info['name']) ??
        'S${season.toString().padLeft(2, '0')} · Episodio ${number > 0 ? number : id}';
    final directSource = _firstText(
          item,
          const ['direct_source', 'directSource', 'stream_source'],
        ) ??
        _firstText(
          info,
          const ['direct_source', 'directSource', 'stream_source'],
        );

    final extension = _firstValidExtension([
      item['container_extension'],
      item['containerExtension'],
      item['extension'],
      info['container_extension'],
      info['containerExtension'],
      info['extension'],
      _extensionFromUrl(directSource),
    ]);

    // Igual que VOD: el episodio conserva una URL absoluta creada con la
    // conexión recién validada. La pantalla puede haber nacido desde caché,
    // pero PLAY no queda atado a un streamServer antiguo.
    final playableDirect = XtreamSeriesEpisode._resolvedEpisodeDirectSource(
          activeConnection.streamServer,
          directSource,
        ) ??
        _seriesUrl(activeConnection, id, extension);

    return XtreamSeriesEpisode(
      id: id,
      season: season <= 0 ? 1 : season,
      number: number <= 0 ? 1 : number,
      title: title,
      extension: extension,
      directSource: playableDirect,
      plot: _cleanText(info['plot']),
      duration: _cleanText(info['duration']),
      image: _firstText(info, const ['movie_image', 'cover_big', 'cover']),
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
    } on TimeoutException {
      return const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }

  static Future<List<dynamic>> _actionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
    final uri = _endpoint(
      connection.apiServer,
      <String, String>{
        'username': connection.username,
        'password': connection.password,
        'action': action,
      },
    );
    final response = await _client.get(uri, headers: _headers).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('Xtream $action respondió HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;
    return const <dynamic>[];
  }

  static Uri _endpoint(Uri base, Map<String, String> query) {
    var path = base.path;
    if (path.isEmpty || path == '/') {
      path = '/player_api.php';
    } else {
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      path = '$path/player_api.php';
    }
    return base.replace(path: path, queryParameters: query, fragment: '');
  }

  static String _seriesUrl(
    XtreamConnectionResult connection,
    String episodeId,
    String extension,
  ) {
    final prefix = connection.streamServer.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    return connection.streamServer
        .replace(
          pathSegments: <String>[
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

  static String _firstValidExtension(Iterable<dynamic> candidates) {
    for (final candidate in candidates) {
      final value = candidate
              ?.toString()
              .trim()
              .toLowerCase()
              .replaceFirst('.', '') ??
          '';
      if (value.isNotEmpty && RegExp(r'^[a-z0-9]{2,6}$').hasMatch(value)) {
        return value;
      }
    }
    return 'mp4';
  }

  static String? _extensionFromUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    final path = uri?.path ?? value;
    final slash = path.lastIndexOf('/');
    final file = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = file.lastIndexOf('.');
    if (dot < 0 || dot == file.length - 1) return null;
    return file.substring(dot + 1);
  }

  static String? _cleanText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  static String? _firstText(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = _cleanText(map[key]);
      if (value != null) return value;
    }
    return null;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((value) => _cleanText(value))
        .whereType<String>()
        .toList(growable: false);
  }
}
