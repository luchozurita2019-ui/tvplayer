import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
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
    this.plot,
    this.duration,
    this.image,
    this.rating,
  });

  Channel toChannel(XtreamConnectionResult connection, {String? group}) {
    final prefix = connection.streamServer.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    final url = connection.streamServer
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
      url: url,
      logoUrl: image,
      group: group,
    );
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

  static final http.Client _client = http.Client();

  static const Map<String, String> _headers = {
    'User-Agent': _seriesUserAgent,
    'Accept': 'application/json,text/plain,*/*',
    'Connection': 'keep-alive',
  };

  static Future<List<XtreamSeriesSummary>> fetchCatalog(
    XtreamConnectionResult connection, {
    Duration timeout = const Duration(seconds: 18),
  }) async {
    final results = await Future.wait<List<dynamic>>([
      _actionList(connection, 'get_series_categories', timeout),
      _actionList(connection, 'get_series', timeout),
    ]);

    final categories = <String, String>{};
    for (final raw in results[0]) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = item['category_id']?.toString().trim() ?? '';
      final name = item['category_name']?.toString().trim() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) categories[id] = name;
    }

    final series = <XtreamSeriesSummary>[];
    for (final raw in results[1]) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = item['series_id']?.toString().trim() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final categoryId = item['category_id']?.toString();
      series.add(
        XtreamSeriesSummary(
          id: id,
          name: name,
          cover: _cleanText(item['cover']),
          category: categoryId == null ? null : categories[categoryId],
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
    final uri = _endpoint(
      connection.apiServer,
      <String, String>{
        'username': connection.username,
        'password': connection.password,
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
      rating: _firstText(info, const ['rating', 'rating_5based']) ?? summary.rating,
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
          final episode = _parseEpisode(rawEpisode, seasonFromKey);
          if (episode == null) continue;
          seasons.putIfAbsent(episode.season, () => <XtreamSeriesEpisode>[]).add(episode);
        }
      }
    } else if (episodesRaw is List) {
      for (final rawEpisode in episodesRaw) {
        final episode = _parseEpisode(rawEpisode, 0);
        if (episode == null) continue;
        seasons.putIfAbsent(episode.season, () => <XtreamSeriesEpisode>[]).add(episode);
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

  static XtreamSeriesEpisode? _parseEpisode(dynamic raw, int seasonFallback) {
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
    final extension = _cleanExtension(item['container_extension']?.toString());

    return XtreamSeriesEpisode(
      id: id,
      season: season <= 0 ? 1 : season,
      number: number <= 0 ? 1 : number,
      title: title,
      extension: extension,
      plot: _cleanText(info['plot']),
      duration: _cleanText(info['duration']),
      image: _firstText(info, const ['movie_image', 'cover_big', 'cover']),
      rating: _firstText(info, const ['rating', 'rating_5based']),
    );
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

  static String _cleanExtension(String? raw) {
    final value = (raw ?? '').trim().toLowerCase().replaceFirst('.', '');
    if (value.isEmpty || !RegExp(r'^[a-z0-9]{2,6}$').hasMatch(value)) {
      return 'mp4';
    }
    return value;
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
