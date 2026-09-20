import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'remote_provisioning_service.dart';

class StreamingPremiumCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;

  const StreamingPremiumCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    required this.secure,
  });

  factory StreamingPremiumCookie.fromJson(Map<String, dynamic> json) {
    return StreamingPremiumCookie(
      name: json['name']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      path: json['path']?.toString().startsWith('/') == true
          ? json['path'].toString()
          : '/',
      hostOnly: json['hostOnly'] == true,
      secure: json['secure'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'hostOnly': hostOnly,
        'secure': secure,
      };
}

class StreamingPremiumSession {
  final String platform;
  final String url;
  final List<StreamingPremiumCookie> cookies;
  final bool shared;
  final String ref;

  const StreamingPremiumSession({
    required this.platform,
    required this.url,
    required this.cookies,
    required this.shared,
    required this.ref,
  });
}

enum StreamingPremiumStage {
  authenticating,
  usingCachedSession,
  requestingSession,
  validatingSession,
  installingCookies,
  openingPreparedSession,
  openingOfficialFallback,
}

typedef StreamingPremiumStageCallback = void Function(
  StreamingPremiumStage stage,
);

class StreamingPremiumUnavailableException implements Exception {
  final String status;

  const StreamingPremiumUnavailableException(this.status);

  @override
  String toString() {
    switch (status) {
      case 'disabled':
        return 'La plataforma está deshabilitada temporalmente.';
      case 'free_without_session':
      case 'no_session':
        return 'No hay una sesión disponible en este momento.';
      default:
        return 'La plataforma no está disponible en este momento.';
    }
  }
}

class _CachedPremiumSession {
  final StreamingPremiumSession session;
  final DateTime fetchedAt;

  const _CachedPremiumSession(this.session, this.fetchedAt);
}

/// V66 test:
/// - conserva V65 intacta;
/// - replica el ciclo de entrada/reintento observado en FT 3.6;
/// - no registra valores de cookies ni tokens;
/// - la sesión siempre llega de forma opaca desde el backend.
class StreamingPremiumService {
  StreamingPremiumService({
    RemoteProvisioningService? provisioning,
    http.Client? client,
  })  : _provisioning = provisioning ?? RemoteProvisioningService(),
        _client = client ?? http.Client();

  static const _endpoint =
      'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-streaming-premium';
  static const MethodChannel _webPlayback =
      MethodChannel('tvfull/web_playback');

  static const Duration _rapidRetryWindow = Duration(minutes: 3);
  static const Duration _sessionMapCacheTtl = Duration(minutes: 15);

  final RemoteProvisioningService _provisioning;
  final http.Client _client;

  final Map<String, DateTime> _lastOpenAt = <String, DateTime>{};
  final Map<String, int> _attemptByPlatform = <String, int>{};
  final Map<String, _CachedPremiumSession> _sessionCache =
      <String, _CachedPremiumSession>{};

  int _nextAttempt(String platform) {
    final now = DateTime.now();
    final previous = _lastOpenAt[platform];
    final previousAttempt = _attemptByPlatform[platform] ?? 0;

    final attempt = previous != null &&
            now.difference(previous) < _rapidRetryWindow
        ? previousAttempt + 1
        : 0;

    _lastOpenAt[platform] = now;
    _attemptByPlatform[platform] = attempt;
    return attempt;
  }

  Future<StreamingPremiumSession> prepare(
    String platform, {
    required int intento,
    StreamingPremiumStageCallback? onStage,
  }) async {
    if (intento == 0) {
      final cached = _sessionCache[platform];
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) < _sessionMapCacheTtl) {
        onStage?.call(StreamingPremiumStage.usingCachedSession);
        debugPrint(
          '[StreamingPremium] $platform: mapa reciente, reutilizando sesión',
        );
        return cached.session;
      }
    }

    onStage?.call(StreamingPremiumStage.authenticating);
    debugPrint('[StreamingPremium] $platform: autenticando dispositivo');
    var credentials =
        await _provisioning.loadCredentials() ??
        await _provisioning.ensureRegistered();

    onStage?.call(StreamingPremiumStage.requestingSession);
    debugPrint(
      '[StreamingPremium] $platform: solicitando sesión intento=$intento',
    );
    var response = await _request(platform, credentials, intento);
    if (response.statusCode == 401) {
      await _provisioning.clearCredentials();
      credentials = await _provisioning.ensureRegistered();
      onStage?.call(StreamingPremiumStage.requestingSession);
      response = await _request(platform, credentials, intento);
    }

    if (response.statusCode == 404) {
      var status = 'no_session';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['status'] != null) {
          status = decoded['status'].toString();
        }
      } catch (_) {}
      throw StreamingPremiumUnavailableException(status);
    }

    if (response.statusCode == 403) {
      throw const StreamingPremiumUnavailableException('disabled');
    }

    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo preparar Streaming Premium (HTTP ${response.statusCode}).',
      );
    }

    onStage?.call(StreamingPremiumStage.validatingSession);
    debugPrint('[StreamingPremium] $platform: validando respuesta');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Sesión Streaming Premium inválida.');
    }

    final data = Map<String, dynamic>.from(decoded);
    if (data['available'] != true) {
      throw StreamingPremiumUnavailableException(
        data['status']?.toString() ?? 'no_session',
      );
    }

    final url = data['url']?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.trim().isEmpty) {
      throw const FormatException('URL Streaming Premium inválida.');
    }

    final cookies = <StreamingPremiumCookie>[];
    final rawCookies = data['cookies'];
    if (rawCookies is List) {
      for (final raw in rawCookies) {
        if (raw is! Map) continue;
        final cookie = StreamingPremiumCookie.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (cookie.name.isEmpty ||
            cookie.value.isEmpty ||
            cookie.domain.isEmpty) {
          continue;
        }
        cookies.add(cookie);
      }
    }

    if (cookies.isEmpty) {
      throw const FormatException(
        'La sesión compartida no contiene cookies válidas.',
      );
    }

    final session = StreamingPremiumSession(
      platform: data['platform']?.toString() ?? platform,
      url: url,
      cookies: List.unmodifiable(cookies),
      shared: data['shared'] == true,
      ref: data['ref']?.toString().trim() ?? '',
    );

    _sessionCache[platform] = _CachedPremiumSession(
      session,
      DateTime.now(),
    );
    return session;
  }

  Future<void> open(
    String platform, {
    StreamingPremiumStageCallback? onStage,
    bool allowOfficialFallback = true,
  }) async {
    final intento = _nextAttempt(platform);

    try {
      final session = await prepare(
        platform,
        intento: intento,
        onStage: onStage,
      );

      onStage?.call(StreamingPremiumStage.installingCookies);
      debugPrint(
        '[StreamingPremium] $platform: preparando '
        '${session.cookies.length} cookies',
      );

      onStage?.call(StreamingPremiumStage.openingPreparedSession);
      debugPrint(
        '[StreamingPremium] $platform: abriendo sesión preparada '
        'intento=$intento',
      );

      final result = await _webPlayback.invokeMethod<dynamic>('open', {
        'url': session.url,
        'headers': const <String, String>{
          'Accept-Language': 'es-AR,es;q=0.9,en;q=0.7',
        },
        'cookies': session.cookies
            .map((cookie) => cookie.toJson())
            .toList(growable: false),
        'platform': platform,
        'replacePlatformCookies': true,
        // FT 3.6 conserva la sesión al salir y sólo limpia antes de
        // instalar una sesión nueva.
        'clearCookiesOnExit': false,
        'streamingPremium': true,
        if (session.ref.isNotEmpty) 'sessionRef': session.ref,
      });

      if (result is Map && result['deadDetected'] == true) {
        _sessionCache.remove(platform);
        debugPrint(
          '[StreamingPremium] $platform: login detectado; '
          'la próxima entrada forzará sesión nueva',
        );
      }
      return;
    } catch (error) {
      _sessionCache.remove(platform);
      if (!allowOfficialFallback) rethrow;
      debugPrint(
        '[StreamingPremium] $platform: sesión preparada no disponible; '
        'abriendo acceso oficial (${error.runtimeType})',
      );
    }

    await openOfficial(platform, onStage: onStage);
  }

  Future<void> openOfficial(
    String platform, {
    StreamingPremiumStageCallback? onStage,
  }) async {
    final url = _officialUrlFor(platform);
    onStage?.call(StreamingPremiumStage.openingOfficialFallback);
    debugPrint('[StreamingPremium] $platform: abriendo acceso oficial');
    await _webPlayback.invokeMethod<dynamic>('open', {
      'url': url,
      'headers': const <String, String>{
        'Accept-Language': 'es-AR,es;q=0.9,en;q=0.7',
      },
      'cookies': const <Map<String, dynamic>>[],
      'platform': platform,
      'replacePlatformCookies': false,
      'clearCookiesOnExit': false,
      'streamingPremium': true,
    });
  }

  String _officialUrlFor(String platform) {
    switch (platform) {
      case 'netflix':
        return 'https://www.netflix.com/browse';
      case 'hbomax':
        return 'https://play.max.com/';
      case 'prime':
        return 'https://www.primevideo.com/';
      case 'crunchyroll':
        return 'https://www.crunchyroll.com/';
      default:
        throw ArgumentError.value(
          platform,
          'platform',
          'Plataforma Streaming Premium no soportada',
        );
    }
  }

  Future<http.Response> _request(
    String platform,
    RemoteDeviceCredentials credentials,
    int intento,
  ) {
    return _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'x-tvfull-device-code': credentials.code,
            'x-tvfull-device-secret': credentials.secret,
          },
          body: jsonEncode({
            'platform': platform,
            'intento': intento,
          }),
        )
        .timeout(const Duration(seconds: 18));
  }

  void close() => _client.close();
}
