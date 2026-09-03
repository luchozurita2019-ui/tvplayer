import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'xtream_fast_catalog_service.dart';
import 'xtream_http_client.dart';
import 'xtream_service.dart';

class LiveProgram {
  final String title;
  final String? description;
  final DateTime? start;
  final DateTime? end;

  const LiveProgram({
    required this.title,
    this.description,
    this.start,
    this.end,
  });
}

class LiveProgramGuide {
  final LiveProgram? now;
  final LiveProgram? next;

  const LiveProgramGuide({this.now, this.next});

  bool get hasPrograms => now != null || next != null;
}

typedef LiveProgramGuideLoader = Future<LiveProgramGuide?> Function(
  Channel channel,
);

class LiveEpgService {
  LiveEpgService._();

  static final LiveEpgService instance = LiveEpgService._();

  static const Duration _timeout = Duration(seconds: 5);
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
}

LiveProgramGuide? parseXtreamEpgPayload(
  Object? decoded, {
  DateTime? clock,
}) {
  Object? rawListings = decoded;
  if (decoded is Map) {
    rawListings = decoded['epg_listings'] ?? decoded['listings'];
    final data = decoded['data'];
    if (rawListings == null && data is Map) {
      rawListings = data['epg_listings'] ?? data['listings'];
    } else if (rawListings == null && data is List) {
      rawListings = data;
    }
  }
  if (rawListings is! List || rawListings.isEmpty) return null;

  final programs = <LiveProgram>[];
  for (final raw in rawListings) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    final title = _decodeXtreamText(item['title'] ?? item['name']);
    if (title.isEmpty) continue;
    programs.add(
      LiveProgram(
        title: title,
        description: _nullableText(
          _decodeXtreamText(item['description'] ?? item['desc']),
        ),
        start: _readProgramTime(
          item,
          const <String>['start_timestamp', 'start', 'start_time'],
        ),
        end: _readProgramTime(
          item,
          const <String>['stop_timestamp', 'end_timestamp', 'stop', 'end'],
        ),
      ),
    );
  }
  if (programs.isEmpty) return null;

  programs.sort((a, b) {
    final left = a.start;
    final right = b.start;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  });

  if (programs.every((item) => item.start == null && item.end == null)) {
    return LiveProgramGuide(
      now: programs.first,
      next: programs.length > 1 ? programs[1] : null,
    );
  }

  final nowTime = clock ?? DateTime.now();
  LiveProgram? current;
  for (final program in programs) {
    final start = program.start;
    final end = program.end;
    if (start == null || end == null) continue;
    if (!nowTime.isBefore(start) && nowTime.isBefore(end)) {
      current = program;
      break;
    }
  }

  LiveProgram? upcoming;
  if (current != null) {
    final currentIndex = programs.indexOf(current);
    for (var index = currentIndex + 1; index < programs.length; index++) {
      if (programs[index].title.isNotEmpty) {
        upcoming = programs[index];
        break;
      }
    }
  } else {
    for (final program in programs) {
      final start = program.start;
      if (start != null && start.isAfter(nowTime)) {
        upcoming = program;
        break;
      }
    }
  }

  final guide = LiveProgramGuide(now: current, next: upcoming);
  return guide.hasPrograms ? guide : null;
}

DateTime? _readProgramTime(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final raw = item[key];
    if (raw == null) continue;
    if (raw is num) {
      final value = raw.toInt();
      if (value <= 0) continue;
      final millis = value < 100000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    final text = raw.toString().trim();
    if (text.isEmpty || text == '0' || text == 'null') continue;
    final numeric = int.tryParse(text);
    if (numeric != null && numeric > 0) {
      final millis = numeric < 100000000000 ? numeric * 1000 : numeric;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed.toLocal();
  }
  return null;
}

String _decodeXtreamText(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty || value == 'null') return '';
  final compact = value.replaceAll(RegExp(r'\s+'), '');
  final looksEncoded = compact.length >= 8 &&
      RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(compact) &&
      (compact.contains('=') || compact.length >= 16);
  if (!looksEncoded) return value;
  try {
    final missingPadding = compact.length % 4;
    final padded = missingPadding == 0
        ? compact
        : compact.padRight(compact.length + (4 - missingPadding), '=');
    final decoded =
        utf8.decode(base64.decode(padded), allowMalformed: false).trim();
    if (decoded.isEmpty) return value;
    final printable =
        decoded.runes.where((rune) => rune >= 32 || rune == 10).length;
    if (printable * 100 < decoded.runes.length * 85) return value;
    return decoded;
  } catch (_) {
    return value;
  }
}

String? _nullableText(String value) =>
    value.trim().isEmpty ? null : value.trim();

class _XtreamEpgHttpException implements Exception {
  final int statusCode;
  const _XtreamEpgHttpException(this.statusCode);
}

class _LiveEpgCacheEntry {
  final LiveProgramGuide guide;
  final DateTime savedAt;

  const _LiveEpgCacheEntry({required this.guide, required this.savedAt});
}
