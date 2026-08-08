import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ServerCompatibilityMode {
  direct,
  compatible,
  liveRecovery,
}

extension ServerCompatibilityModeLabel on ServerCompatibilityMode {
  String get label => switch (this) {
        ServerCompatibilityMode.direct => 'Directo',
        ServerCompatibilityMode.compatible => 'Compatible',
        ServerCompatibilityMode.liveRecovery => 'Live Recovery',
      };
}

class HostCompatibilityProfile {
  final String host;
  ServerCompatibilityMode preferredMode;
  int directFailures;
  int compatibleFailures;
  int liveRecoveryFailures;
  int liveEofRecoveries;
  int successes;
  int lastUpdatedEpochMs;

  HostCompatibilityProfile({
    required this.host,
    this.preferredMode = ServerCompatibilityMode.direct,
    this.directFailures = 0,
    this.compatibleFailures = 0,
    this.liveRecoveryFailures = 0,
    this.liveEofRecoveries = 0,
    this.successes = 0,
    this.lastUpdatedEpochMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'preferredMode': preferredMode.name,
        'directFailures': directFailures,
        'compatibleFailures': compatibleFailures,
        'liveRecoveryFailures': liveRecoveryFailures,
        'liveEofRecoveries': liveEofRecoveries,
        'successes': successes,
        'lastUpdatedEpochMs': lastUpdatedEpochMs,
      };

  factory HostCompatibilityProfile.fromJson(Map<String, dynamic> json) {
    final rawMode = json['preferredMode'] as String?;
    final mode = ServerCompatibilityMode.values.firstWhere(
      (value) => value.name == rawMode,
      orElse: () => ServerCompatibilityMode.direct,
    );

    return HostCompatibilityProfile(
      host: json['host'] as String? ?? 'desconocido',
      preferredMode: mode,
      directFailures: (json['directFailures'] as num?)?.toInt() ?? 0,
      compatibleFailures: (json['compatibleFailures'] as num?)?.toInt() ?? 0,
      liveRecoveryFailures:
          (json['liveRecoveryFailures'] as num?)?.toInt() ?? 0,
      liveEofRecoveries: (json['liveEofRecoveries'] as num?)?.toInt() ?? 0,
      successes: (json['successes'] as num?)?.toInt() ?? 0,
      lastUpdatedEpochMs:
          (json['lastUpdatedEpochMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class ServerCompatibilityService {
  ServerCompatibilityService._();

  static final ServerCompatibilityService instance =
      ServerCompatibilityService._();

  static const _storageKey = 'server_compatibility_v1';

  final Map<String, HostCompatibilityProfile> _profiles = {};
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
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final profile = HostCompatibilityProfile.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          _profiles[profile.host] = profile;
        }
      } catch (_) {
        _profiles.clear();
      }
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final values = _profiles.values.toList()
      ..sort((a, b) => b.lastUpdatedEpochMs.compareTo(a.lastUpdatedEpochMs));
    await prefs.setString(
      _storageKey,
      jsonEncode(values.take(100).map((e) => e.toJson()).toList()),
    );
  }

  Future<HostCompatibilityProfile> profileForUrl(String url) async {
    await _ensureLoaded();
    final host = hostForUrl(url);
    return _profiles.putIfAbsent(
      host,
      () => HostCompatibilityProfile(host: host),
    );
  }

  Future<ServerCompatibilityMode> preferredModeForUrl(String url) async {
    final profile = await profileForUrl(url);
    return profile.preferredMode;
  }

  List<ServerCompatibilityMode> planFor(ServerCompatibilityMode preferred) {
    return switch (preferred) {
      ServerCompatibilityMode.direct => const [
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.liveRecovery,
        ],
      ServerCompatibilityMode.compatible => const [
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.liveRecovery,
        ],
      ServerCompatibilityMode.liveRecovery => const [
          ServerCompatibilityMode.liveRecovery,
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.compatible,
        ],
    };
  }

  Future<void> recordSuccess(
    String url,
    ServerCompatibilityMode mode,
  ) async {
    final profile = await profileForUrl(url);
    profile.successes++;
    profile.preferredMode = mode;
    profile.lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<void> recordFailure(
    String url,
    ServerCompatibilityMode mode,
  ) async {
    final profile = await profileForUrl(url);
    switch (mode) {
      case ServerCompatibilityMode.direct:
        profile.directFailures++;
      case ServerCompatibilityMode.compatible:
        profile.compatibleFailures++;
      case ServerCompatibilityMode.liveRecovery:
        profile.liveRecoveryFailures++;
    }
    profile.lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<void> recordLiveEof(String url) async {
    final profile = await profileForUrl(url);
    profile.liveEofRecoveries++;
    profile.preferredMode = ServerCompatibilityMode.liveRecovery;
    profile.lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _profiles.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
