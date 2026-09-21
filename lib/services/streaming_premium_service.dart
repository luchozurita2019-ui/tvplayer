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
  final List<StreamingPremiumCookie> cookies;
  final bool shared;
  final String ref;
  final String phoneUrl;
  final String tvUrl;

  const StreamingPremiumSession({
    required this.platform,
    required this.mode,
    required this.url,
    required this.cookies,
    required this.shared,
    required this.ref,
    this.phoneUrl = '',
    this.tvUrl = '',
  });

  bool get isExternal => mode == 'external' || mode == 'netflix_handoff';
}

enum StreamingPremiumStage {
  authenticating,
  usingCachedSession,
  requestingSession,
  validatingSession,
  installingCookies,
  openingPreparedSession,
  openingExternalSession,
  openingOfficialFallback,
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
      case 'netflix_no_account':
        return 'No hay accesos de Netflix disponibles ahora mismo. '
            'Probá de nuevo en un rato.';
      case 'netflix_bridge_missing':
        return 'Falta el puente autorizado de Fútbol Total 3.6.';
      case 'free_without_session':
      case 'no_session':
        return detail.isEmpty
            ? 'No hay una sesión disponible en este momento.'
            : 'No hay una sesión disponible en este momento. $detail';
      default:
        final suffix = detail.isEmpty ? '' : ' · $detail';
        return 'FT no entregó la sesión ($status)$suffix';
    }
  }
}

class _CachedPremiumSession {
  final StreamingPremiumSession session;
  final DateTime fetchedAt;

  const _CachedPremiumSession(this.session, this.fetchedAt);
}

/// V68 test aislado:
/// - MAX / Prime / Crunchyroll siguen el ciclo observado en FT 3.6;
/// - no abre fallback oficial si la sesión preparada falla;
/// - replica UA/cookies/dominios legacy sin registrar valores sensibles;
/// - Netflix queda fuera de esta fase de prueba.
// V91 restore marker: exact known-good V76 streaming logic.
class StreamingPremiumService {
  StreamingPremiumService({
    RemoteProvisioningService? provisioning,
    http.Client? client,
  })  : _provisioning = provisioning ?? RemoteProvisioningService(),
        _client = client ?? http.Client();

  static const _endpoint =
      'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-streaming-premium-v67-platform-test';
  static const MethodChannel _webPlayback =
      MethodChannel('tvfull/web_playback');
  static const MethodChannel _ftPremiumDirect =
      MethodChannel('tvfull/ft_premium_direct');
  static const MethodChannel _deviceIdentity =
      MethodChannel('tvfull/device_identity');
  static const bool _androidTv =
      bool.fromEnvironment('TV_FULL_ANDROID_TV', defaultValue: false);

  static const String ftDesktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/150.0.0.0 Safari/537.36';

  static const Map<String, String> _defaultDomains = <String, String>{
    'hbomax': '.max.com',
    'prime': '.primevideo.com',
    'crunchyroll': '.crunchyroll.com',
  };

  static const Map<String, List<String>> _legacyExtraDomains =
      <String, List<String>>{
    'hbomax': <String>['.hbomax.com', '.max.com'],
    'prime': <String>['.amazon.com'],
    'crunchyroll': <String>[],
  };

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

    if (platform == 'hbomax' ||
        platform == 'prime' ||
        platform == 'crunchyroll') {
      return _prepareDirectFt(
        platform,
        intento: intento,
        onStage: onStage,
      );
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
    var url = data['url']?.toString().trim() ?? '';
    if (mode == 'external' && platform == 'netflix') {
      final preferred = _androidTv
          ? data['tv_url']?.toString().trim()
          : data['phone_url']?.toString().trim();
      if (preferred != null && preferred.isNotEmpty) {
        url = preferred;
      }
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.trim().isEmpty) {
      throw const FormatException('URL Streaming Premium inválida.');
    }
    if (mode == 'external' &&
        platform == 'netflix' &&
        !(uri.host == 'netflix.com' || uri.host.endsWith('.netflix.com'))) {
      throw const FormatException('Destino externo de Netflix inválido.');
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
            cookie.domain.isEmpty) {
          continue;
        }
        cookies.add(cookie);
      }
    }

    if (mode != 'external' && cookies.isEmpty) {
      throw const FormatException(
        'La sesión compartida no contiene cookies válidas.',
      );
    }

    final normalizedCookies =
        mode == 'external' ? cookies : _normalizeFtCookies(platform, cookies);

    final session = StreamingPremiumSession(
      platform: data['platform']?.toString() ?? platform,
      mode: mode,
      url: url,
      cookies: List.unmodifiable(normalizedCookies),
      shared: data['shared'] == true,
      ref: data['ref']?.toString().trim() ?? '',
    );

    _sessionCache[platform] = _CachedPremiumSession(
      session,
      DateTime.now(),
    );
    return session;
  }

  bool _isNetflixPhoneHandoff(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host != 'www.netflix.com' && host != 'netflix.com') return false;
    if (uri.path != '/unsupported') return false;
    return (uri.queryParameters['nftoken']?.trim() ?? '').isNotEmpty;
  }

  bool _isNetflixTvHandoff(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host != 'www.netflix.com' && host != 'netflix.com') return false;
    if (uri.path != '/tv8') return false;
    return (uri.queryParameters['nftoken']?.trim() ?? '').isNotEmpty;
  }

  Future<StreamingPremiumSession> generateNetflixAccess({
    required int intento,
    StreamingPremiumStageCallback? onStage,
  }) async {
    onStage?.call(StreamingPremiumStage.requestingSession);
    final raw = await _ftPremiumDirect.invokeMethod<dynamic>(
      'generateNetflixBridge',
      <String, dynamic>{'intento': intento},
    );
    if (raw is! Map) {
      throw const StreamingPremiumUnavailableException(
        'netflix_handoff_failed',
      );
    }
    final data = Map<String, dynamic>.from(raw);
    if (data['ok'] != true) {
      throw StreamingPremiumUnavailableException(
        data['status']?.toString() ?? 'netflix_handoff_failed',
      );
    }

    // El generador original de FT devuelve W0.b (Teléfono) y W0.c (TV).
    // Se conservan ambos strings tal como llegan; TV FULL no reconstruye nftoken.
    final phone = data['phone_url']?.toString().trim() ?? '';
    final tv = data['tv_url']?.toString().trim() ?? '';
    if (!_isNetflixPhoneHandoff(phone)) {
      throw const StreamingPremiumUnavailableException(
        'netflix_handoff_failed',
      );
    }
    // TV es opcional para no invalidar un acceso web correcto. Si FT lo
    // entrega, debe conservar el formato /tv8?nftoken= original.
    if (tv.isNotEmpty && !_isNetflixTvHandoff(tv)) {
      throw const StreamingPremiumUnavailableException(
        'netflix_handoff_failed',
      );
    }

    return StreamingPremiumSession(
      platform: 'netflix',
      mode: 'netflix_handoff',
      url: phone,
      cookies: const <StreamingPremiumCookie>[],
      shared: true,
      ref: '',
      phoneUrl: phone,
      tvUrl: tv,
    );
  }

  Future<void> openNetflixGeneratedUrl(String url) async {
    if (!_isNetflixPhoneHandoff(url) && !_isNetflixTvHandoff(url)) {
      throw const FormatException(
        'El generador no entregó un acceso temporal válido.',
      );
    }
    await _webPlayback.invokeMethod<dynamic>('openExternalBrowser', {
      'url': url,
      'platform': 'netflix',
    });
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

      if (session.isExternal) {
        onStage?.call(StreamingPremiumStage.openingExternalSession);
        debugPrint(
          '[StreamingPremium] $platform: abriendo handoff externo preparado',
        );
        await _webPlayback.invokeMethod<dynamic>('openExternal', {
          'url': session.url,
          'platform': platform,
        });
        return;
      }

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
          'User-Agent': ftDesktopUserAgent,
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
          'reportando sesión caída',
        );
        if (session.ref.isNotEmpty) {
          await _reportDead(platform, session.ref);
        }
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
    if (platform == 'netflix') {
      await _webPlayback.invokeMethod<dynamic>('openExternal', {
        'url': url,
        'platform': platform,
      });
      return;
    }
    await _webPlayback.invokeMethod<dynamic>('open', {
      'url': url,
      'headers': const <String, String>{
        'User-Agent': ftDesktopUserAgent,
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

  Future<StreamingPremiumSession> _prepareDirectFt(
    String platform, {
    required int intento,
    StreamingPremiumStageCallback? onStage,
  }) async {
    onStage?.call(StreamingPremiumStage.authenticating);
    onStage?.call(StreamingPremiumStage.requestingSession);
    debugPrint(
      '[StreamingPremium] $platform: petición directa compatible FT 3.6 '
      'intento=$intento',
    );

    dynamic raw = await _ftPremiumDirect.invokeMethod<dynamic>('prepare', {
      'platform': platform,
      'intento': intento,
    });
    if (raw is! Map) {
      throw const FormatException('Respuesta directa FT inválida.');
    }

    var data = Map<String, dynamic>.from(raw);
    if (data['available'] != true &&
        data['status']?.toString() == 'activation_required' &&
        data['activation_mode']?.toString() == 'web') {
      onStage?.call(StreamingPremiumStage.validatingSession);
      debugPrint(
        '[StreamingPremium] $platform: abriendo activación web autorizada',
      );

      final activationRaw =
          await _ftPremiumDirect.invokeMethod<dynamic>('activate');
      if (activationRaw is! Map) {
        throw const StreamingPremiumUnavailableException(
          'activation_failed',
          'respuesta de activación inválida',
        );
      }

      final activation = Map<String, dynamic>.from(activationRaw);
      final completed = activation['completed'] == true;
      final queda = (activation['queda'] as num?)?.toInt() ?? 0;
      final libre = activation['libre'] == true;
      final pro = activation['pro'] == true;

      if (!completed) {
        final parts = <String>[
          'etapa=activation',
          'queda=${queda}s',
          'libre=${libre ? 'sí' : 'no'}',
          'pro=${pro ? 'sí' : 'no'}',
        ];
        throw StreamingPremiumUnavailableException(
          'activation_pending',
          parts.join(' · '),
        );
      }

      onStage?.call(StreamingPremiumStage.requestingSession);
      raw = await _ftPremiumDirect.invokeMethod<dynamic>('prepare', {
        'platform': platform,
        'intento': intento,
      });
      if (raw is! Map) {
        throw const FormatException(
          'Respuesta FT inválida después de la activación.',
        );
      }
      data = Map<String, dynamic>.from(raw);
    }

    if (data['available'] != true) {
      final status = data['status']?.toString() ?? 'no_session';
      final stage = data['stage']?.toString() ?? '';
      final activationMode = data['activation_mode']?.toString() ?? '';
      final pingOk = data['ping_ok'];
      final hasRef = data['has_ref'];
      final sessionOk = data['session_ok'];
      final sessionHttp = data['session_http'];
      final sessionQueda = data['session_queda'];
      final sessionLibre = data['session_libre'];
      final sessionPro = data['session_pro'];
      final sessionToken = data['session_token'];
      final rawDetail = data['detail']?.toString().trim() ?? '';
      final parts = <String>[];
      if (stage.isNotEmpty) parts.add('etapa=$stage');
      if (activationMode.isNotEmpty) {
        parts.add('activación=$activationMode');
      }
      if (pingOk is bool) parts.add('ping=${pingOk ? 'ok' : 'falló'}');
      if (sessionOk is bool) {
        parts.add('sesión=${sessionOk ? 'ok' : 'falló'}');
      }
      if (sessionHttp is num) parts.add('sesión_http=${sessionHttp.toInt()}');
      if (sessionQueda is num) parts.add('queda=${sessionQueda.toInt()}s');
      if (sessionLibre is bool) {
        parts.add('libre=${sessionLibre ? 'sí' : 'no'}');
      }
      if (sessionPro is bool) parts.add('pro=${sessionPro ? 'sí' : 'no'}');
      if (sessionToken is bool) {
        parts.add('token=${sessionToken ? 'sí' : 'no'}');
      }
      if (hasRef is bool) parts.add('ref=${hasRef ? 'sí' : 'no'}');
      if (rawDetail.isNotEmpty) parts.add(rawDetail);
      throw StreamingPremiumUnavailableException(status, parts.join(' · '));
    }

    onStage?.call(StreamingPremiumStage.validatingSession);
    final url = data['url']?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('URL Streaming Premium inválida.');
    }

    final cookies = <StreamingPremiumCookie>[];
    final rawCookies = data['cookies'];
    if (rawCookies is List) {
      for (final rawCookie in rawCookies) {
        if (rawCookie is! Map) continue;
        final cookie = StreamingPremiumCookie.fromJson(
          Map<String, dynamic>.from(rawCookie),
        );
        if (cookie.name.isEmpty || cookie.domain.isEmpty) continue;
        cookies.add(cookie);
      }
    }
    if (cookies.isEmpty) {
      throw const FormatException('FT no entregó cookies de sesión.');
    }

    final session = StreamingPremiumSession(
      platform: data['platform']?.toString() ?? platform,
      mode: 'webview',
      url: url,
      cookies: List.unmodifiable(_normalizeFtCookies(platform, cookies)),
      shared: data['shared'] == true,
      ref: data['ref']?.toString().trim() ?? '',
    );
    _sessionCache[platform] = _CachedPremiumSession(session, DateTime.now());
    return session;
  }

  List<StreamingPremiumCookie> _normalizeFtCookies(
    String platform,
    List<StreamingPremiumCookie> incoming,
  ) {
    if (incoming.isEmpty) return incoming;

    final defaultDomain = _defaultDomains[platform];
    final extras = _legacyExtraDomains[platform] ?? const <String>[];
    if (defaultDomain == null || extras.isEmpty) {
      return List<StreamingPremiumCookie>.from(incoming);
    }

    String canonical(String value) =>
        value.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');

    final defaultCanonical = canonical(defaultDomain);
    final hasOtherDomain = incoming.any(
      (cookie) => canonical(cookie.domain) != defaultCanonical,
    );
    final hasHostOnly = incoming.any((cookie) => cookie.hostOnly);

    // FT 3.6 replica el formato legacy en el dominio base y extras.
    // Si ya llegan dominios específicos, respetamos cookiesFull sin tocarlo.
    if (hasOtherDomain || hasHostOnly) {
      return List<StreamingPremiumCookie>.from(incoming);
    }

    final domains = <String>[defaultDomain, ...extras];
    final seen = <String>{};
    final out = <StreamingPremiumCookie>[];

    for (final cookie in incoming) {
      for (final domain in domains) {
        final key =
            '${cookie.name}|${canonical(domain)}|${cookie.path}|${cookie.value}';
        if (!seen.add(key)) continue;
        out.add(
          StreamingPremiumCookie(
            name: cookie.name,
            value: cookie.value,
            domain: domain,
            path: cookie.path,
            hostOnly: false,
            secure: true,
          ),
        );
      }
    }

    return out;
  }

  Future<http.Response> _request(
    String platform,
    RemoteDeviceCredentials credentials,
    int intento,
  ) async {
    final compatId =
        await _deviceIdentity.invokeMethod<String>('getPremiumCompatId') ?? '';
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
            'compatId': compatId,
          }),
        )
        .timeout(const Duration(seconds: 18));
  }

  Future<void> _reportDead(String platform, String ref) async {
    if (platform == 'hbomax' ||
        platform == 'prime' ||
        platform == 'crunchyroll') {
      try {
        await _ftPremiumDirect.invokeMethod<dynamic>('reportDead', {
          'platform': platform,
          'ref': ref,
        });
      } catch (error) {
        debugPrint(
          '[StreamingPremium] $platform: reporte FT directo falló '
          '(${error.runtimeType})',
        );
      }
      return;
    }

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
