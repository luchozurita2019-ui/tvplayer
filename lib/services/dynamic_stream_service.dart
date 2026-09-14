import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/channel.dart';

class DynamicStreamException implements Exception {
  final String message;
  final bool retryable;

  const DynamicStreamException(this.message, {this.retryable = false});

  @override
  String toString() => message;
}

class ResolvedDynamicStream {
  final String url;
  final Map<String, String> headers;

  const ResolvedDynamicStream({required this.url, required this.headers});
}

/// Fuente LIVE compatible con servidores que exponen catálogo Xtream y
/// requieren resolver el stream_id justo antes de iniciar la reproducción.
///
/// El catálogo provider.json puede usar el mismo resolvedor sin credenciales
/// Xtream: el JSON aporta la identidad estable del canal y `resolve` obtiene la
/// URL temporal justo al abrirlo. El bloque opcional `session` permite pedir al
/// proveedor headers/tokens emitidos específicamente para TV FULL.
///
/// La configuración se inyecta con TV_FULL_DYNAMIC_SOURCE_JSON. X-Hash es un
/// fallback heredado opcional; el flujo preferido es `session`, que evita fijar
/// valores capturados de otra instalación.
class DynamicStreamService {
  DynamicStreamService._({
    String? rawConfig,
    http.Client? client,
    Future<String?> Function()? androidIdProvider,
    String? xHashOverride,
  }) : _rawConfigOverride = rawConfig,
       _client = client ?? http.Client(),
       _androidIdProvider = androidIdProvider ?? _platformAndroidId,
       _xHashOverride = xHashOverride;

  static final DynamicStreamService instance = DynamicStreamService._();

  static const String sourcePrefix = 'tvfull-dynamic://catalog/';
  static const String streamPrefix = 'tvfull-dynamic://stream/';
  static const MethodChannel _deviceChannel = MethodChannel(
    'tvfull/device_identity',
  );

  static const String _compiledConfig = String.fromEnvironment(
    'TV_FULL_DYNAMIC_SOURCE_JSON',
    defaultValue: '',
  );
  static const String _compiledXHash = String.fromEnvironment(
    'TV_FULL_DYNAMIC_X_HASH',
    defaultValue: '',
  );

  final String? _rawConfigOverride;
  final http.Client _client;
  final Future<String?> Function() _androidIdProvider;
  final String? _xHashOverride;

  _DynamicSourceConfig? _config;
  bool _configLoaded = false;
  String? _configurationError;
  final Map<String, _SessionCacheEntry> _sessionCache =
      <String, _SessionCacheEntry>{};

  @visibleForTesting
  factory DynamicStreamService.forTesting({
    required String configJson,
    required http.Client client,
    Future<String?> Function()? androidIdProvider,
    String? xHashOverride,
  }) {
    return DynamicStreamService._(
      rawConfig: configJson,
      client: client,
      androidIdProvider: androidIdProvider,
      xHashOverride: xHashOverride,
    );
  }

  String get _rawConfig => _rawConfigOverride ?? _compiledConfig;

  bool get isConfigured => _loadConfig() != null;

  String get playlistName => _loadConfig()?.name ?? 'TV clásica 2';

  String get playlistSource {
    final raw = _rawConfig.trim();
    if (raw.isEmpty) return '${sourcePrefix}disabled';
    final fingerprint = sha256
        .convert(utf8.encode(raw))
        .toString()
        .substring(0, 12);
    return '$sourcePrefix$fingerprint';
  }

  bool handlesSource(String source) =>
      isConfigured && source.trim().startsWith(sourcePrefix);

  Future<List<Channel>> fetchCatalog() async {
    final config = _requireConfig();
    if (config.username.isEmpty || config.password.isEmpty) {
      throw const DynamicStreamException(
        'El catálogo Xtream dinámico requiere usuario y contraseña.',
      );
    }

    final results = await Future.wait<List<dynamic>>([
      _xtreamList(config, 'get_live_categories'),
      _xtreamList(config, 'get_live_streams'),
    ]);

    final categories = <String, String>{};
    for (final raw in results[0]) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = _clean(item['category_id']);
      final name = _clean(item['category_name']);
      if (id != null && name != null) categories[id] = name;
    }

    final channels = <Channel>[];
    final seen = <String>{};
    for (final raw in results[1]) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = _clean(item['stream_id']);
      final name = _clean(item['name']);
      if (id == null || name == null || !seen.add(id)) continue;

      final categoryId = _clean(item['category_id']);
      final fallbackCategory =
          _clean(item['category_name']) ?? _clean(item['category']);
      final group = categoryId == null
          ? fallbackCategory
          : categories[categoryId] ?? fallbackCategory;

      channels.add(
        Channel(
          name: name,
          // La URL final NO se persiste. El stream_id es la identidad estable.
          url: '$streamPrefix${Uri.encodeComponent(id)}',
          logoUrl:
              _clean(item['stream_icon']) ??
              _clean(item['logo']) ??
              _clean(item['icon']),
          group: group,
          tvgId: _clean(item['epg_channel_id']) ?? _clean(item['tvg_id']),
          xtreamStreamId: id,
          dynamicStreamId: id,
        ),
      );
    }

    if (channels.isEmpty) {
      throw const DynamicStreamException(
        'get_live_streams no devolvió canales válidos.',
      );
    }

    return List<Channel>.unmodifiable(channels);
  }

  Future<ResolvedDynamicStream> resolve(Channel channel) async {
    final config = _requireConfig();
    final id =
        (channel.dynamicStreamId ?? channel.xtreamStreamId)?.trim() ?? '';
    if (id.isEmpty) {
      return ResolvedDynamicStream(
        url: channel.url,
        headers: const <String, String>{},
      );
    }

    final androidId = await _safeAndroidId();
    final vars = <String, String>{
      'id': id,
      'androidId': androidId ?? '',
      'name': channel.name,
      'group': channel.group ?? '',
      'path': channel.dynamicStreamPath ?? '',
      'globalIndex': channel.providerGlobalIndex ?? '',
    };

    final resolverUri = _resolverUri(config, vars);
    final resolverHeaders = _expandMap(
      config.resolverHeaders,
      vars,
      keepEmpty: false,
    );
    final form = _expandMap(config.resolverForm, vars, keepEmpty: true);

    http.Response response;
    try {
      if (config.resolverMethod == 'GET') {
        final uri = resolverUri.replace(
          queryParameters: <String, String>{
            ...resolverUri.queryParameters,
            ...form,
          },
        );
        response = await _client
            .get(uri, headers: resolverHeaders)
            .timeout(config.resolverTimeout);
      } else {
        response = await _client
            .post(
              resolverUri,
              headers: resolverHeaders,
              body: form,
              encoding: utf8,
            )
            .timeout(config.resolverTimeout);
      }
    } on TimeoutException {
      throw const DynamicStreamException(
        'Tiempo de espera agotado al generar la URL del canal.',
        retryable: true,
      );
    } catch (_) {
      throw const DynamicStreamException(
        'No se pudo generar la URL del canal.',
        retryable: true,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DynamicStreamException(
        'El resolvedor respondió HTTP ${response.statusCode}.',
        retryable:
            response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500,
      );
    }

    final url = _resolvedUrl(
      utf8.decode(response.bodyBytes, allowMalformed: true).trim(),
    );
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        !(parsed.scheme == 'http' || parsed.scheme == 'https') ||
        parsed.host.isEmpty) {
      throw const DynamicStreamException(
        'El resolvedor devolvió una URL de reproducción inválida.',
      );
    }

    final playbackHeaders = _expandMap(
      config.playbackHeaders,
      vars,
      keepEmpty: false,
    );

    // El ANDROID_ID real sigue siendo la identidad por dispositivo. No se fija
    // un X-Did capturado de otra instalación.
    if (androidId != null && androidId.isNotEmpty) {
      _putIfMissingCaseInsensitive(playbackHeaders, 'X-Did', androidId);
    }

    // Si el proveedor dispone de un emisor de sesión para TV FULL, sus headers
    // tienen prioridad sobre la configuración estática. El emisor puede
    // devolver headers de reproducción autorizados para esa sesión.
    final sessionHeaders = await _resolveProviderSessionHeaders(config, vars);
    for (final entry in sessionHeaders.entries) {
      _putCaseInsensitive(
        playbackHeaders,
        entry.key,
        entry.value,
        replace: true,
      );
    }

    // Compatibilidad heredada: un valor configurado manualmente sólo se usa si
    // el emisor de sesión no entregó ya X-Hash.
    final xHash = (_xHashOverride ?? '').trim().isNotEmpty
        ? _xHashOverride!.trim()
        : _compiledXHash.trim().isNotEmpty
        ? _compiledXHash.trim()
        : config.xHash.trim();
    if (xHash.isNotEmpty) {
      _putIfMissingCaseInsensitive(playbackHeaders, 'X-Hash', xHash);
    }

    return ResolvedDynamicStream(
      url: parsed.toString(),
      headers: playbackHeaders,
    );
  }

  Future<Map<String, String>> _resolveProviderSessionHeaders(
    _DynamicSourceConfig config,
    Map<String, String> vars,
  ) async {
    final session = config.session;
    if (session == null) return const <String, String>{};

    final cacheKey = _sessionCacheKey(config, session, vars);
    final cached = _sessionCache[cacheKey];
    final now = DateTime.now();
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return Map<String, String>.from(cached.headers);
    }

    final uri = _sessionUri(config, session, vars);
    final headers = _expandMap(session.headers, vars, keepEmpty: false);
    final form = _expandMap(session.form, vars, keepEmpty: true);

    http.Response response;
    try {
      if (session.method == 'GET') {
        final requestUri = uri.replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            ...form,
          },
        );
        response = await _client
            .get(requestUri, headers: headers)
            .timeout(session.timeout);
      } else {
        response = await _client
            .post(
              uri,
              headers: headers,
              body: form,
              encoding: utf8,
            )
            .timeout(session.timeout);
      }
    } on TimeoutException {
      throw const DynamicStreamException(
        'Tiempo de espera agotado al solicitar la sesión del proveedor.',
        retryable: true,
      );
    } catch (_) {
      throw const DynamicStreamException(
        'No se pudo solicitar la sesión del proveedor.',
        retryable: true,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DynamicStreamException(
        'La sesión del proveedor respondió HTTP ${response.statusCode}.',
        retryable:
            response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500,
      );
    }

    final result = _sessionResponseHeaders(response);
    if (result.isEmpty) {
      throw const DynamicStreamException(
        'La sesión del proveedor no devolvió headers de reproducción.',
        retryable: true,
      );
    }

    if (session.ttl > Duration.zero) {
      _sessionCache[cacheKey] = _SessionCacheEntry(
        headers: Map<String, String>.unmodifiable(result),
        expiresAt: now.add(session.ttl),
      );
    }
    return result;
  }

  Map<String, String> _sessionResponseHeaders(http.Response response) {
    final result = <String, String>{};

    for (final entry in response.headers.entries) {
      final canonical = _sessionHeaderName(entry.key);
      if (canonical != null && entry.value.trim().isNotEmpty) {
        result[canonical] = entry.value.trim();
      }
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) return result;

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final headers = map['headers'];
        if (headers is Map) {
          for (final entry in headers.entries) {
            final key = entry.key?.toString().trim() ?? '';
            final value = entry.value?.toString().trim() ?? '';
            if (key.isEmpty || value.isEmpty) continue;
            result[key] = value;
          }
        }

        for (final key in const [
          'x_hash',
          'x-hash',
          'xHash',
          'X-Hash',
          'x_hash2',
          'x-hash2',
          'xHash2',
          'X-Hash2',
        ]) {
          final value = map[key]?.toString().trim();
          if (value == null || value.isEmpty) continue;
          final canonical = key.toLowerCase().contains('hash2')
              ? 'X-Hash2'
              : 'X-Hash';
          result[canonical] = value;
        }
      }
    } catch (_) {
      // Un body no JSON no invalida headers HTTP ya recibidos.
    }

    return result;
  }

  String? _sessionHeaderName(String raw) {
    final key = raw.trim();
    if (key.isEmpty) return null;
    final lower = key.toLowerCase();
    if (lower == 'x-hash') return 'X-Hash';
    if (lower == 'x-hash2') return 'X-Hash2';
    if (lower == 'x-app') return 'X-App';
    if (lower == 'x-version') return 'X-Version';
    if (lower == 'x-did') return 'X-Did';
    if (lower == 'user-agent') return 'User-Agent';
    if (lower == 'referer') return 'Referer';
    if (lower == 'origin') return 'Origin';
    return null;
  }

  String _sessionCacheKey(
    _DynamicSourceConfig config,
    _ProviderSessionConfig session,
    Map<String, String> vars,
  ) {
    final device = vars['androidId'] ?? '';
    final stream = session.scope == 'stream' ? vars['id'] ?? '' : '';
    return '${config.server}|${session.path}|${session.scope}|$device|$stream';
  }

  Uri _sessionUri(
    _DynamicSourceConfig config,
    _ProviderSessionConfig session,
    Map<String, String> vars,
  ) {
    final rawPath = _expand(session.path, vars).trim();
    final parsed = Uri.tryParse(rawPath);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) {
      return parsed;
    }
    return _endpoint(config.server, rawPath);
  }

  Future<List<dynamic>> _xtreamList(
    _DynamicSourceConfig config,
    String action,
  ) async {
    final uri = _endpoint(config.server, 'player_api.php').replace(
      queryParameters: <String, String>{
        'username': config.username,
        'password': config.password,
        'action': action,
      },
    );

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: config.catalogHeaders)
          .timeout(config.catalogTimeout);
    } on TimeoutException {
      throw DynamicStreamException(
        'Tiempo de espera agotado al consultar $action.',
        retryable: true,
      );
    } catch (_) {
      throw DynamicStreamException(
        'No se pudo consultar $action.',
        retryable: true,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DynamicStreamException(
        'Xtream $action respondió HTTP ${response.statusCode}.',
        retryable:
            response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500,
      );
    }

    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is List) return decoded;
    } catch (_) {}

    throw DynamicStreamException(
      'Xtream $action no devolvió una lista JSON válida.',
    );
  }

  Uri _resolverUri(_DynamicSourceConfig config, Map<String, String> vars) {
    final path = _expand(config.resolverPath, vars);
    final parsed = Uri.tryParse(path);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) {
      return parsed;
    }
    return _endpoint(config.server, path);
  }

  _DynamicSourceConfig? _loadConfig() {
    if (_configLoaded) return _config;
    _configLoaded = true;

    final raw = _rawConfig.trim();
    if (raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _configurationError =
            'La configuración dinámica debe ser un objeto JSON.';
        return null;
      }
      _config = _DynamicSourceConfig.fromMap(
        Map<String, dynamic>.from(decoded),
      );
    } catch (error) {
      _configurationError = 'Configuración dinámica inválida: $error';
      _config = null;
    }
    return _config;
  }

  _DynamicSourceConfig _requireConfig() {
    final value = _loadConfig();
    if (value != null) return value;
    throw DynamicStreamException(
      _configurationError ?? 'La fuente dinámica no está configurada.',
    );
  }

  String _resolvedUrl(String body) {
    if (body.isEmpty) {
      throw const DynamicStreamException(
        'El resolvedor respondió vacío.',
        retryable: true,
      );
    }

    if (body.startsWith('http://') || body.startsWith('https://')) {
      return body;
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is String) return decoded.trim();
      if (decoded is Map) {
        for (final key in const [
          'url',
          'stream_url',
          'streamUrl',
          'stream',
          'link',
          'm3u8',
        ]) {
          final value = decoded[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            return value.toString().trim();
          }
        }
      }
    } catch (_) {}

    var cleaned = body.trim();
    if (cleaned.length >= 2 &&
        ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
            (cleaned.startsWith("'") && cleaned.endsWith("'")))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    return cleaned;
  }

  Uri _endpoint(Uri base, String rawPath) {
    final cleanPath = rawPath.trim();
    final pathSegments = <String>[
      ...base.pathSegments.where((segment) => segment.trim().isNotEmpty),
      ...cleanPath.split('/').where((segment) => segment.trim().isNotEmpty),
    ];
    return base.replace(pathSegments: pathSegments, query: '', fragment: '');
  }

  Map<String, String> _expandMap(
    Map<String, String> values,
    Map<String, String> vars, {
    required bool keepEmpty,
  }) {
    final result = <String, String>{};
    for (final entry in values.entries) {
      final key = _expand(entry.key, vars).trim();
      final value = _expand(entry.value, vars);
      if (key.isEmpty) continue;
      if (!keepEmpty && value.trim().isEmpty) continue;
      result[key] = value;
    }
    return result;
  }

  String _expand(String value, Map<String, String> vars) {
    var result = value;
    for (final entry in vars.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  void _putIfMissingCaseInsensitive(
    Map<String, String> headers,
    String key,
    String value,
  ) {
    _putCaseInsensitive(headers, key, value, replace: false);
  }

  void _putCaseInsensitive(
    Map<String, String> headers,
    String key,
    String value, {
    required bool replace,
  }) {
    final target = key.toLowerCase();
    String? existing;
    for (final current in headers.keys) {
      if (current.toLowerCase() == target) {
        existing = current;
        break;
      }
    }
    if (existing != null) {
      if (!replace) return;
      headers.remove(existing);
    }
    headers[key] = value;
  }

  Future<String?> _safeAndroidId() async {
    try {
      final value = (await _androidIdProvider())?.trim();
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _platformAndroidId() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return (await _deviceChannel.invokeMethod<String>('getAndroidId'))
          ?.trim();
    } on PlatformException {
      return null;
    }
  }

  String? _clean(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }
}

class _DynamicSourceConfig {
  final String name;
  final Uri server;
  final String username;
  final String password;
  final Map<String, String> catalogHeaders;
  final Duration catalogTimeout;
  final String resolverPath;
  final String resolverMethod;
  final Map<String, String> resolverHeaders;
  final Map<String, String> resolverForm;
  final Duration resolverTimeout;
  final Map<String, String> playbackHeaders;
  final String xHash;
  final _ProviderSessionConfig? session;

  const _DynamicSourceConfig({
    required this.name,
    required this.server,
    required this.username,
    required this.password,
    required this.catalogHeaders,
    required this.catalogTimeout,
    required this.resolverPath,
    required this.resolverMethod,
    required this.resolverHeaders,
    required this.resolverForm,
    required this.resolverTimeout,
    required this.playbackHeaders,
    required this.xHash,
    required this.session,
  });

  factory _DynamicSourceConfig.fromMap(Map<String, dynamic> map) {
    final rawServer = map['server']?.toString().trim() ?? '';
    final server = Uri.tryParse(rawServer);
    if (server == null ||
        !(server.scheme == 'http' || server.scheme == 'https') ||
        server.host.isEmpty) {
      throw const FormatException('Servidor dinámico inválido.');
    }

    final username = map['username']?.toString().trim() ?? '';
    final password = map['password']?.toString().trim() ?? '';

    final resolverRaw = map['resolver'];
    final resolver = resolverRaw is Map
        ? Map<String, dynamic>.from(resolverRaw)
        : const <String, dynamic>{};
    final sessionRaw = map['session'];
    final session = sessionRaw is Map
        ? _ProviderSessionConfig.fromMap(
            Map<String, dynamic>.from(sessionRaw),
          )
        : null;

    final catalogTimeoutMs =
        int.tryParse(map['catalogTimeoutMs']?.toString() ?? '') ?? 12000;
    final resolverTimeoutMs =
        int.tryParse(resolver['timeoutMs']?.toString() ?? '') ?? 8000;

    final resolverMethod =
        resolver['method']?.toString().trim().toUpperCase() ?? 'POST';
    if (resolverMethod != 'GET' && resolverMethod != 'POST') {
      throw const FormatException('El resolvedor sólo admite GET o POST.');
    }

    final resolverForm = _stringMap(resolver['form']);

    return _DynamicSourceConfig(
      name: map['name']?.toString().trim().isNotEmpty == true
          ? map['name'].toString().trim()
          : 'TV FULL · Proveedor',
      server: server.replace(query: '', fragment: ''),
      username: username,
      password: password,
      catalogHeaders: _stringMap(map['catalogHeaders']),
      catalogTimeout: Duration(
        milliseconds: catalogTimeoutMs.clamp(1000, 30000),
      ),
      resolverPath: resolver['path']?.toString().trim().isNotEmpty == true
          ? resolver['path'].toString().trim()
          : '/stream/gen/{id}',
      resolverMethod: resolverMethod,
      resolverHeaders: _stringMap(resolver['headers']),
      resolverForm: resolverForm.isEmpty
          ? const <String, String>{
              'id': '{id}',
              'cast': 'false',
              'device': '{androidId}',
              'code': '',
            }
          : resolverForm,
      resolverTimeout: Duration(
        milliseconds: resolverTimeoutMs.clamp(1000, 30000),
      ),
      playbackHeaders: _stringMap(map['playbackHeaders']),
      xHash: map['xHash']?.toString().trim() ?? '',
      session: session,
    );
  }
}

class _ProviderSessionConfig {
  final String path;
  final String method;
  final Map<String, String> headers;
  final Map<String, String> form;
  final Duration timeout;
  final Duration ttl;
  final String scope;

  const _ProviderSessionConfig({
    required this.path,
    required this.method,
    required this.headers,
    required this.form,
    required this.timeout,
    required this.ttl,
    required this.scope,
  });

  factory _ProviderSessionConfig.fromMap(Map<String, dynamic> map) {
    final path = map['path']?.toString().trim() ?? '';
    if (path.isEmpty) {
      throw const FormatException('Falta session.path.');
    }

    final method = map['method']?.toString().trim().toUpperCase() ?? 'POST';
    if (method != 'GET' && method != 'POST') {
      throw const FormatException('session.method sólo admite GET o POST.');
    }

    final timeoutMs =
        int.tryParse(map['timeoutMs']?.toString() ?? '') ?? 6000;
    final ttlSeconds = int.tryParse(map['ttlSeconds']?.toString() ?? '') ?? 0;
    final scope = map['scope']?.toString().trim().toLowerCase() ?? 'device';
    if (scope != 'device' && scope != 'stream') {
      throw const FormatException('session.scope debe ser device o stream.');
    }

    return _ProviderSessionConfig(
      path: path,
      method: method,
      headers: _stringMap(map['headers']),
      form: _stringMap(map['form']),
      timeout: Duration(milliseconds: timeoutMs.clamp(1000, 30000)),
      ttl: Duration(seconds: ttlSeconds.clamp(0, 3600)),
      scope: scope,
    );
  }
}

class _SessionCacheEntry {
  final Map<String, String> headers;
  final DateTime expiresAt;

  const _SessionCacheEntry({required this.headers, required this.expiresAt});
}

Map<String, String> _stringMap(dynamic raw) {
  if (raw is! Map) return const <String, String>{};
  final result = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key?.toString().trim() ?? '';
    final value = entry.value?.toString() ?? '';
    if (key.isEmpty) continue;
    result[key] = value;
  }
  return Map<String, String>.unmodifiable(result);
}
