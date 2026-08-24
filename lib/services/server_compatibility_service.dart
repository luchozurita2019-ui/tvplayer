import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ServerCompatibilityMode {
  direct,
  nativeHttp,
  mpvHttp,
  tlsLegacy,
  compatible,
  liveRecovery,
  advanced,
  xtreamHls,
}

extension ServerCompatibilityModeLabel on ServerCompatibilityMode {
  String get label => switch (this) {
    ServerCompatibilityMode.direct => 'Directo',
    ServerCompatibilityMode.nativeHttp => 'HTTP nativo',
    ServerCompatibilityMode.mpvHttp => 'HTTP mpv',
    ServerCompatibilityMode.tlsLegacy => 'TLS compatible',
    ServerCompatibilityMode.compatible => 'Compatible',
    ServerCompatibilityMode.liveRecovery => 'Live Recovery',
    ServerCompatibilityMode.advanced => 'Compatibilidad avanzada',
    ServerCompatibilityMode.xtreamHls => 'Xtream HLS',
  };
}

class HostCompatibilityProfile {
  final String host;
  ServerCompatibilityMode preferredMode;
  int directFailures;
  int nativeHttpFailures;
  int mpvHttpFailures;
  int tlsLegacyFailures;
  int compatibleFailures;
  int liveRecoveryFailures;
  int advancedFailures;
  int xtreamHlsFailures;
  int liveEofRecoveries;
  int runtimeRecoveries;
  int normalProbeFallbacks;
  bool preferNormalProbe;
  int successes;
  int lastUpdatedEpochMs;

  HostCompatibilityProfile({
    required this.host,
    this.preferredMode = ServerCompatibilityMode.direct,
    this.directFailures = 0,
    this.nativeHttpFailures = 0,
    this.mpvHttpFailures = 0,
    this.tlsLegacyFailures = 0,
    this.compatibleFailures = 0,
    this.liveRecoveryFailures = 0,
    this.advancedFailures = 0,
    this.xtreamHlsFailures = 0,
    this.liveEofRecoveries = 0,
    this.runtimeRecoveries = 0,
    this.normalProbeFallbacks = 0,
    this.preferNormalProbe = false,
    this.successes = 0,
    this.lastUpdatedEpochMs = 0,
  });

  Map<String, dynamic> toJson() => {
    'host': host,
    'preferredMode': preferredMode.name,
    'directFailures': directFailures,
    'nativeHttpFailures': nativeHttpFailures,
    'mpvHttpFailures': mpvHttpFailures,
    'tlsLegacyFailures': tlsLegacyFailures,
    'compatibleFailures': compatibleFailures,
    'liveRecoveryFailures': liveRecoveryFailures,
    'advancedFailures': advancedFailures,
    'xtreamHlsFailures': xtreamHlsFailures,
    'liveEofRecoveries': liveEofRecoveries,
    'runtimeRecoveries': runtimeRecoveries,
    'normalProbeFallbacks': normalProbeFallbacks,
    'preferNormalProbe': preferNormalProbe,
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
      nativeHttpFailures: (json['nativeHttpFailures'] as num?)?.toInt() ?? 0,
      mpvHttpFailures: (json['mpvHttpFailures'] as num?)?.toInt() ?? 0,
      tlsLegacyFailures: (json['tlsLegacyFailures'] as num?)?.toInt() ?? 0,
      compatibleFailures: (json['compatibleFailures'] as num?)?.toInt() ?? 0,
      liveRecoveryFailures:
          (json['liveRecoveryFailures'] as num?)?.toInt() ?? 0,
      advancedFailures: (json['advancedFailures'] as num?)?.toInt() ?? 0,
      xtreamHlsFailures: (json['xtreamHlsFailures'] as num?)?.toInt() ?? 0,
      liveEofRecoveries: (json['liveEofRecoveries'] as num?)?.toInt() ?? 0,
      runtimeRecoveries: (json['runtimeRecoveries'] as num?)?.toInt() ?? 0,
      normalProbeFallbacks:
          (json['normalProbeFallbacks'] as num?)?.toInt() ?? 0,
      preferNormalProbe: json['preferNormalProbe'] as bool? ?? false,
      successes: (json['successes'] as num?)?.toInt() ?? 0,
      lastUpdatedEpochMs: (json['lastUpdatedEpochMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class ServerCompatibilityService {
  ServerCompatibilityService._();

  static final ServerCompatibilityService instance =
      ServerCompatibilityService._();

  // Conservamos la clave v1 para no perder lo aprendido por versiones previas.
  // Los campos nuevos son opcionales al decodificar perfiles antiguos.
  static const _storageKey = 'server_compatibility_v1';

  final Map<String, HostCompatibilityProfile> _profiles = {};
  bool _loaded = false;

  String hostForUrl(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.trim().toLowerCase() ?? '';
    if (host.isEmpty) return 'desconocido';

    // El mismo panel puede exponer API en :59000 y video en :8443 con reglas
    // distintas. Aprender por host+puerto evita mezclar esos comportamientos.
    if (uri != null && uri.hasPort) return '$host:${uri.port}';
    return host;
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

  Future<bool> normalProbePreferredForUrl(String url) async {
    final profile = await profileForUrl(url);
    return profile.preferNormalProbe;
  }

  List<ServerCompatibilityMode> planFor(ServerCompatibilityMode preferred) {
    const baseline = <ServerCompatibilityMode>[
      ServerCompatibilityMode.direct,
      ServerCompatibilityMode.nativeHttp,
      ServerCompatibilityMode.mpvHttp,
      ServerCompatibilityMode.tlsLegacy,
      ServerCompatibilityMode.compatible,
      ServerCompatibilityMode.liveRecovery,
      ServerCompatibilityMode.advanced,
      ServerCompatibilityMode.xtreamHls,
    ];

    // El modo aprendido se prueba primero; el resto conserva un orden estable.
    return <ServerCompatibilityMode>[
      preferred,
      ...baseline.where((mode) => mode != preferred),
    ];
  }

  Future<void> recordSuccess(String url, ServerCompatibilityMode mode) async {
    final profile = await profileForUrl(url);
    profile.successes++;
    profile.preferredMode = mode;
    profile.lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<void> recordFailure(String url, ServerCompatibilityMode mode) async {
    final profile = await profileForUrl(url);
    switch (mode) {
      case ServerCompatibilityMode.direct:
        profile.directFailures++;
        break;
      case ServerCompatibilityMode.nativeHttp:
        profile.nativeHttpFailures++;
        break;
      case ServerCompatibilityMode.mpvHttp:
        profile.mpvHttpFailures++;
        break;
      case ServerCompatibilityMode.tlsLegacy:
        profile.tlsLegacyFailures++;
        break;
      case ServerCompatibilityMode.compatible:
        profile.compatibleFailures++;
        break;
      case ServerCompatibilityMode.liveRecovery:
        profile.liveRecoveryFailures++;
        break;
      case ServerCompatibilityMode.advanced:
        profile.advancedFailures++;
        break;
      case ServerCompatibilityMode.xtreamHls:
        profile.xtreamHlsFailures++;
        break;
    }
    profile.lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<void> recordNormalProbeFallback(String url) async {
    final profile = await profileForUrl(url);
    profile.normalProbeFallbacks++;
    profile.preferNormalProbe = true;
    profile.lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<void> recordRuntimeRecovery(String url) async {
    final profile = await profileForUrl(url);
    profile.runtimeRecoveries++;
    profile.lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<void> recordLiveEof(
    String url,
    ServerCompatibilityMode recoveryMode,
  ) async {
    final profile = await profileForUrl(url);
    profile.liveEofRecoveries++;
    profile.preferredMode = recoveryMode;
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
