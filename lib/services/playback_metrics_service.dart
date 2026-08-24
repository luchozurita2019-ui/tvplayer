import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/playback_settings.dart';

class HostPlaybackStats {
  final String host;
  int startupCount;
  int startupTotalMs;
  int fastestStartupMs;
  int slowestStartupMs;
  int failures;
  int stalls;
  int fastProbeFallbacks;
  int zapCount;
  int zapTotalMs;
  int fastestZapMs;
  int slowestZapMs;
  int lastUpdatedEpochMs;

  HostPlaybackStats({
    required this.host,
    this.startupCount = 0,
    this.startupTotalMs = 0,
    this.fastestStartupMs = 0,
    this.slowestStartupMs = 0,
    this.failures = 0,
    this.stalls = 0,
    this.fastProbeFallbacks = 0,
    this.zapCount = 0,
    this.zapTotalMs = 0,
    this.fastestZapMs = 0,
    this.slowestZapMs = 0,
    this.lastUpdatedEpochMs = 0,
  });

  double? get averageStartupMs =>
      startupCount == 0 ? null : startupTotalMs / startupCount;

  double? get averageZapMs => zapCount == 0 ? null : zapTotalMs / zapCount;

  double get failureRatio {
    final attempts = startupCount + failures;
    return attempts == 0 ? 0 : failures / attempts;
  }

  double get stallRatio => startupCount == 0 ? 0 : stalls / startupCount;

  int get sampleScore => startupCount + failures + stalls + zapCount;

  void recordStartup(int milliseconds) {
    startupCount++;
    startupTotalMs += milliseconds;
    if (fastestStartupMs == 0 || milliseconds < fastestStartupMs) {
      fastestStartupMs = milliseconds;
    }
    if (milliseconds > slowestStartupMs) slowestStartupMs = milliseconds;
    lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
  }

  void recordFailure() {
    failures++;
    lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
  }

  void recordStall() {
    stalls++;
    lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
  }

  void recordFastProbeFallback() {
    fastProbeFallbacks++;
    lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
  }

  void recordZap(int milliseconds) {
    zapCount++;
    zapTotalMs += milliseconds;
    if (fastestZapMs == 0 || milliseconds < fastestZapMs) {
      fastestZapMs = milliseconds;
    }
    if (milliseconds > slowestZapMs) slowestZapMs = milliseconds;
    lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'startupCount': startupCount,
        'startupTotalMs': startupTotalMs,
        'fastestStartupMs': fastestStartupMs,
        'slowestStartupMs': slowestStartupMs,
        'failures': failures,
        'stalls': stalls,
        'fastProbeFallbacks': fastProbeFallbacks,
        'zapCount': zapCount,
        'zapTotalMs': zapTotalMs,
        'fastestZapMs': fastestZapMs,
        'slowestZapMs': slowestZapMs,
        'lastUpdatedEpochMs': lastUpdatedEpochMs,
      };

  factory HostPlaybackStats.fromJson(Map<String, dynamic> json) {
    return HostPlaybackStats(
      host: json['host'] as String? ?? 'desconocido',
      startupCount: (json['startupCount'] as num?)?.toInt() ?? 0,
      startupTotalMs: (json['startupTotalMs'] as num?)?.toInt() ?? 0,
      fastestStartupMs: (json['fastestStartupMs'] as num?)?.toInt() ?? 0,
      slowestStartupMs: (json['slowestStartupMs'] as num?)?.toInt() ?? 0,
      failures: (json['failures'] as num?)?.toInt() ?? 0,
      stalls: (json['stalls'] as num?)?.toInt() ?? 0,
      fastProbeFallbacks: (json['fastProbeFallbacks'] as num?)?.toInt() ?? 0,
      zapCount: (json['zapCount'] as num?)?.toInt() ?? 0,
      zapTotalMs: (json['zapTotalMs'] as num?)?.toInt() ?? 0,
      fastestZapMs: (json['fastestZapMs'] as num?)?.toInt() ?? 0,
      slowestZapMs: (json['slowestZapMs'] as num?)?.toInt() ?? 0,
      lastUpdatedEpochMs: (json['lastUpdatedEpochMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdaptivePlaybackTuning {
  final PlaybackSettings settings;
  final String label;
  final bool useFastProbe;

  const AdaptivePlaybackTuning({
    required this.settings,
    required this.label,
    required this.useFastProbe,
  });
}

class PlaybackMetricsService {
  PlaybackMetricsService._();

  static final PlaybackMetricsService instance = PlaybackMetricsService._();
  static const _storageKey = 'playback_host_metrics_v1';

  final Map<String, HostPlaybackStats> _stats = {};
  bool _loaded = false;

  String hostForUrl(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.trim().toLowerCase() ?? '';
    return host.isEmpty ? 'desconocido' : host;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          final stats = HostPlaybackStats.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          _stats[stats.host] = stats;
        }
      } catch (_) {
        _stats.clear();
      }
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final values =
        _stats.values.where((stats) => stats.sampleScore > 0).toList()
          ..sort(
            (a, b) => b.lastUpdatedEpochMs.compareTo(a.lastUpdatedEpochMs),
          );

    final compact = values.take(100).map((e) => e.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(compact));
  }

  Future<HostPlaybackStats> statsForUrl(String url) async {
    await _ensureLoaded();
    final host = hostForUrl(url);
    return _stats.putIfAbsent(host, () => HostPlaybackStats(host: host));
  }

  Future<List<HostPlaybackStats>> allStats() async {
    await _ensureLoaded();
    final values = _stats.values.where((e) => e.sampleScore > 0).toList()
      ..sort((a, b) {
        final samples = b.sampleScore.compareTo(a.sampleScore);
        if (samples != 0) return samples;
        return b.lastUpdatedEpochMs.compareTo(a.lastUpdatedEpochMs);
      });
    return values;
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _stats.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<void> recordStartup(String url, int milliseconds) async {
    final stats = await statsForUrl(url);
    stats.recordStartup(milliseconds);
    await _save();
  }

  Future<void> recordFailure(String url) async {
    final stats = await statsForUrl(url);
    stats.recordFailure();
    await _save();
  }

  Future<void> recordStall(String url) async {
    final stats = await statsForUrl(url);
    stats.recordStall();
    await _save();
  }

  Future<void> recordFastProbeFallback(String url) async {
    final stats = await statsForUrl(url);
    stats.recordFastProbeFallback();
    await _save();
  }

  Future<void> recordZap(String url, int milliseconds) async {
    final stats = await statsForUrl(url);
    stats.recordZap(milliseconds);
    await _save();
  }

  Future<AdaptivePlaybackTuning> tuningFor(
    String url,
    PlaybackSettings requested,
  ) async {
    if (requested.profile != BufferProfile.auto) {
      return AdaptivePlaybackTuning(
        settings: requested,
        label: _fixedProfileLabel(requested.profile),
        useFastProbe: requested.profile == BufferProfile.ultraFast,
      );
    }

    final stats = await statsForUrl(url);
    final average = stats.averageStartupMs;

    if (stats.startupCount < 3) {
      return AdaptivePlaybackTuning(
        settings: PlaybackSettings.auto,
        label: 'Auto · aprendiendo',
        useFastProbe: true,
      );
    }

    final looksFast = average != null &&
        average <= 900 &&
        stats.failureRatio <= 0.10 &&
        stats.stallRatio <= 0.08;

    if (looksFast) {
      return AdaptivePlaybackTuning(
        settings: PlaybackSettings.auto.copyWith(
          bufferMb: 8,
          readaheadSeconds: 0.8,
          recoveryBufferSeconds: 0.5,
          connectTimeoutSeconds: 5,
          maxRetries: 3,
          stallThresholdSeconds: 6,
        ),
        label: 'Auto · rápido',
        useFastProbe: true,
      );
    }

    final looksUnstable = (average != null && average >= 1800) ||
        stats.failureRatio >= 0.20 ||
        stats.stallRatio >= 0.15;

    if (looksUnstable) {
      return AdaptivePlaybackTuning(
        settings: PlaybackSettings.auto.copyWith(
          bufferMb: 32,
          readaheadSeconds: 4.0,
          recoveryBufferSeconds: 2.0,
          connectTimeoutSeconds: 10,
          maxRetries: 5,
          stallThresholdSeconds: 12,
        ),
        label: 'Auto · reforzado',
        useFastProbe: false,
      );
    }

    return AdaptivePlaybackTuning(
      settings: PlaybackSettings.auto.copyWith(
        bufferMb: 16,
        readaheadSeconds: 1.8,
        recoveryBufferSeconds: 1.0,
        connectTimeoutSeconds: 7,
        maxRetries: 4,
        stallThresholdSeconds: 8,
      ),
      label: 'Auto · equilibrado',
      useFastProbe: true,
    );
  }

  String _fixedProfileLabel(BufferProfile profile) {
    return switch (profile) {
      BufferProfile.auto => 'Auto',
      BufferProfile.ultraFast => 'Ultra rápido',
      BufferProfile.balanced => 'Equilibrado',
      BufferProfile.stable => 'Estable',
      BufferProfile.slowConnection => 'Conexión lenta',
      BufferProfile.custom => 'Personalizado',
    };
  }
}
