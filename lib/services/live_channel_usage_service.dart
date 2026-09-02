import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';

class LiveChannelUsageService {
  LiveChannelUsageService._();

  static final LiveChannelUsageService instance = LiveChannelUsageService._();

  static const String _storageKey = 'tvfull_live_usage_v1';
  static const int _maxRecords = 80;

  final Map<String, _LiveUsageRecord> _records = <String, _LiveUsageRecord>{};
  bool _loaded = false;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final pending = _loading;
    if (pending != null) return pending;
    final future = _load();
    _loading = future;
    return future;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final key = entry.key.toString();
            final value = entry.value;
            if (value is! Map) continue;
            final count = (value['count'] as num?)?.toInt() ?? 0;
            final last = (value['last'] as num?)?.toInt() ?? 0;
            if (count <= 0 || last <= 0) continue;
            _records[key] = _LiveUsageRecord(count: count, lastEpochMs: last);
          }
        }
      }
    } catch (_) {
      _records.clear();
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  Future<void> record(Channel channel) async {
    await ensureLoaded();
    final key = _keyFor(channel);
    final now = DateTime.now().millisecondsSinceEpoch;
    final previous = _records[key];
    _records[key] = _LiveUsageRecord(
      count: (previous?.count ?? 0) + 1,
      lastEpochMs: now,
    );
    _trim();
    await _persist();
  }

  List<Channel> featuredChannels(
    List<Channel> channels, {
    required bool Function(Channel channel) isFavorite,
    int limit = 7,
  }) {
    if (channels.isEmpty || limit <= 0) return const <Channel>[];

    final sports = channels.where(isSportsChannel).toList(growable: false);
    final primary = sports.isEmpty
        ? List<Channel>.from(channels)
        : List<Channel>.from(sports);
    primary.sort(
      (a, b) => _score(b, isFavorite).compareTo(_score(a, isFavorite)),
    );

    final result = <Channel>[];
    final seen = <String>{};
    for (final channel in primary) {
      if (seen.add(channel.uniqueKey)) result.add(channel);
      if (result.length >= limit) return result;
    }

    final fallback = List<Channel>.from(channels)
      ..sort(
        (a, b) => _score(b, isFavorite).compareTo(_score(a, isFavorite)),
      );
    for (final channel in fallback) {
      if (seen.add(channel.uniqueKey)) result.add(channel);
      if (result.length >= limit) break;
    }
    return result;
  }

  List<Channel> recentChannels(List<Channel> channels, {int limit = 7}) {
    if (channels.isEmpty || limit <= 0) return const <Channel>[];
    final values =
        channels.where((channel) => _recordFor(channel) != null).toList();
    values.sort((a, b) {
      final aLast = _recordFor(a)?.lastEpochMs ?? 0;
      final bLast = _recordFor(b)?.lastEpochMs ?? 0;
      return bLast.compareTo(aLast);
    });
    if (values.length <= limit) return values;
    return values.sublist(0, limit);
  }

  static bool isSportsChannel(Channel channel) {
    final value = '${channel.group ?? ''} ${channel.name}'.toLowerCase();
    const keywords = <String>[
      'deporte',
      'sport',
      'futbol',
      'fútbol',
      'football',
      'soccer',
      'liga',
      'copa',
      'champion',
      'partido',
      'racing',
      'motor',
      'tenis',
      'tennis',
      'basket',
    ];
    for (final keyword in keywords) {
      if (value.contains(keyword)) return true;
    }
    return false;
  }

  int _score(Channel channel, bool Function(Channel) isFavorite) {
    final record = _recordFor(channel);
    var score = 0;
    if (isFavorite(channel)) score += 120000;
    if (isSportsChannel(channel)) score += 40000;
    if (record != null) {
      score += record.count.clamp(0, 500) * 900;
      final age = DateTime.now().millisecondsSinceEpoch - record.lastEpochMs;
      if (age < const Duration(days: 1).inMilliseconds) {
        score += 16000;
      } else if (age < const Duration(days: 7).inMilliseconds) {
        score += 8000;
      } else if (age < const Duration(days: 30).inMilliseconds) {
        score += 3000;
      }
    }
    return score;
  }

  _LiveUsageRecord? _recordFor(Channel channel) => _records[_keyFor(channel)];

  String _keyFor(Channel channel) {
    final digest = sha1.convert(utf8.encode(channel.uniqueKey)).toString();
    return digest.substring(0, 20);
  }

  void _trim() {
    if (_records.length <= _maxRecords) return;
    final entries = _records.entries.toList()
      ..sort((a, b) => b.value.lastEpochMs.compareTo(a.value.lastEpochMs));
    _records
      ..clear()
      ..addEntries(entries.take(_maxRecords));
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = <String, Map<String, int>>{};
      for (final entry in _records.entries) {
        encoded[entry.key] = <String, int>{
          'count': entry.value.count,
          'last': entry.value.lastEpochMs,
        };
      }
      await prefs.setString(_storageKey, jsonEncode(encoded));
    } catch (_) {}
  }
}

class _LiveUsageRecord {
  final int count;
  final int lastEpochMs;

  const _LiveUsageRecord({
    required this.count,
    required this.lastEpochMs,
  });
}
