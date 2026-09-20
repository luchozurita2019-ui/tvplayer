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
  final String mode;
  final String url;
  final String phoneUrl;
  final String tvUrl;
  final int expires;
  final List<StreamingPremiumCookie> cookies;
  final bool shared;
  final String ref;

  const StreamingPremiumSession({
    required this.platform,
    required this.mode,
    required this.url,
    required this.phoneUrl,
    required this.tvUrl,
    required this.expires,
    required this.cookies,
    required this.shared,
    required this.ref,
  });

  bool get opensExternally => mode == 'external';
}

enum StreamingPremiumStage {
  authenticating,
  usingCachedSession,
  requestingSession,
  validatingSession,
  installingCookies,
  openingPreparedSession,
  openingExternalAccess,
}

typedef StreamingPremiumStageCallback = void Function(
  StreamingPremiumStage stage,
);

class StreamingPremiumUnavailableException implements Exception {
  final String status;
  final String detail;

  const StreamingPremiumUnavailableException(this.status, [this.detail = '']);

  @override
  String toString() {
    switch (status) {
      case 'disabled':
        return 'La plataforma está deshabilitada temporalmente.';
      case 'free_without_session':
      case 'no_session':
        return detail.isEmpty
            ? 'No hay una sesión disponible en este momento.'
            : 'No hay una sesión disponible en este momento. $detail';
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

/// V68 exact-routing test:
/// - conserva V65/V66/V67 intactas;
/// - separa Netflix (navegador/app oficial) del WebView premium;
/// - no registra valores de cookies ni tokens;
/// - no usa fallback oficial: sólo abre cuando FT/Rafael entrega sesión.
class StreamingPremiumService {
  StreamingPremiumService({
    RemoteProvisioningService? provisioning,
    http.Client? client,
  })  : _provisioning = provisioning ?? RemoteProvisioningService(),
        _client = client ?? http.Client();

  static const _endpoint =
      'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-streaming-premium-v68-test';
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
      var detail = '';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          if (decoded['status'] != null) {
            status = decoded['status'].toString();
          }
          final stage = decoded['stage']?.toString() ?? '';
          final pingOk = decoded['ping_ok'];
          final source = decoded['source']?.toString() ?? '';
          final hasRef = decoded['has_ref'];
          final attempt = decoded['intento'];
          final parts = <String>[];
          if (stage.isNotEmpty) parts.add('etapa=$stage');
          if (pingOk is bool) parts.add('ping=${pingOk ? 'ok' : 'falló'}');
          if (source.isNotEmpty) parts.add('origen=$source');
          if (hasRef is bool) parts.add('ref=${hasRef ? 'sí' : 'no'}');
          if (attempt is num) parts.add('intento=${attempt.toInt()}');
          detail = parts.join(' · ');
        }
      } catch (_) {}
      debugPrint(
        '[StreamingPremium] $platform: sin sesión status=$status $detail',
      );
      throw StreamingPremiumUnavailableException(status, detail);
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

    final mode = data['mode']?.toString().trim().toLowerCase() ?? 'webview';
    final url = data['url']?.toString().trim() ?? '';
    final phoneUrl = data['phone_url']?.toString().trim() ?? '';
    final tvUrl = data['tv_url']?.toString().trim() ?? '';

    bool validHttps(String value) {
      final uri = Uri.tryParse(value);
      return uri != null &&
          uri.scheme == 'https' &&
          uri.host.trim().isNotEmpty;
    }

    final cookies = <StreamingPremiumCookie>[];
    if (mode == 'webview') {
      if (!validHttps(url)) {
        throw const FormatException('URL Streaming Premium inválida.');
      }
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
    } else if (mode == 'external') {
      if (!validHttps(phoneUrl) || !validHttps(tvUrl)) {
        throw const FormatException(
          'El acceso externo generado no contiene URLs válidas.',
        );
      }
    } else {
      throw FormatException('Modo Streaming Premium no soportado: $mode');
    }

    final rawExpires = data['expires'];
    final expires = rawExpires is num
        ? rawExpires.toInt()
        : int.tryParse(rawExpires?.toString() ?? '') ?? 0;

    final session = StreamingPremiumSession(
      platform: data['platform']?.toString() ?? platform,
      mode: mode,
      url: url,
      phoneUrl: phoneUrl,
      tvUrl: tvUrl,
      expires: expires,
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

  Future<StreamingPremiumSession> generate(
    String platform, {
    StreamingPremiumStageCallback? onStage,
  }) async {
    final intento = _nextAttempt(platform);
    return prepare(
      platform,
      intento: intento,
      onStage: onStage,
    );
  }

  Future<void> open(
    String platform, {
    StreamingPremiumStageCallback? onStage,
  }) async {
    final session = await generate(platform, onStage: onStage);

    if (session.opensExternally) {
      onStage?.call(StreamingPremiumStage.openingExternalAccess);
      await openExternalUrl(session.phoneUrl);
      return;
    }

    onStage?.call(StreamingPremiumStage.installingCookies);
    debugPrint(
      '[StreamingPremium] $platform: preparando '
      '${session.cookies.length} cookies',
    );

    onStage?.call(StreamingPremiumStage.openingPreparedSession);
    debugPrint('[StreamingPremium] $platform: abriendo sesión preparada');

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
      'clearCookiesOnExit': false,
      'streamingPremium': true,
      if (session.ref.isNotEmpty) 'sessionRef': session.ref,
    });

    if (result is Map && result['deadDetected'] == true) {
      _sessionCache.remove(platform);
      debugPrint(
        '[StreamingPremium] $platform: login detectado; '
        'reportando sesión caída',
      );
      if (session.ref.isNotEmpty) {
        await _reportDead(platform, session.ref);
      }
    }
  }

  Future<void> openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.trim().isEmpty) {
      throw const FormatException('URL externa inválida.');
    }
    await _webPlayback.invokeMethod<dynamic>('openExternal', {
      'url': url,
    });
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

  Future<void> _reportDead(String platform, String ref) async {
    try {
      final credentials =
          await _provisioning.loadCredentials() ??
          await _provisioning.ensureRegistered();
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'x-tvfull-device-code': credentials.code,
              'x-tvfull-device-secret': credentials.secret,
            },
            body: jsonEncode({
              'action': 'dead',
              'platform': platform,
              'ref': ref,
            }),
          )
          .timeout(const Duration(seconds: 8));
      debugPrint(
        '[StreamingPremium] $platform: reporte dead HTTP ${response.statusCode}',
      );
    } catch (error) {
      debugPrint(
        '[StreamingPremium] $platform: no se pudo reportar dead '
        '(${error.runtimeType})',
      );
    }
  }

  void close() => _client.close();
}
