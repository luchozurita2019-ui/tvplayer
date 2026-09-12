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
/// Flujo:
/// 1. player_api.php?action=get_live_categories
/// 2. player_api.php?action=get_live_streams
/// 3. el usuario abre un canal (stream_id estable)
/// 4. POST al endpoint de resolución (por defecto /stream/gen/{id})
/// 5. el cuerpo de la respuesta contiene la URL HLS temporal
/// 6. Media3 recibe esa URL y los headers de reproducción configurados.
///
/// La configuración se inyecta con TV_FULL_DYNAMIC_SOURCE_JSON. X-Hash es
/// opcional y nunca se genera copiando lógica de otra aplicación: puede
/// proporcionarse en la configuración o con TV_FULL_DYNAMIC_X_HASH.
class DynamicStreamService {
  DynamicStreamService._({
    String? rawConfig,
    http.Client? client,
    Future<String?> Function()? androidIdProvider,
    String? xHashOverride,
  })  : _rawConfigOverride = rawConfig,
        _client = client ?? http.Client(),
        _androidIdProvider = androidIdProvider ?? _platformAndroidId,
        _xHashOverride = xHashOverride;

  static final DynamicStreamService instance = DynamicStreamService._();

  static const String sourcePrefix = 'tvfull-dynamic://catalog/';
  static const String streamPrefix = 'tvfull-dynamic://stream/';
  static const MethodChannel _deviceChannel =
      MethodChannel('tvfull/device_identity');

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
    final fingerprint =
        sha256.convert(utf8.encode(raw)).toString().substring(0, 12);
    return '$sourcePrefix$fingerprint';
  }

  bool handlesSource(String source) =>
      isConfigured && source.trim().startsWith(sourcePrefix);

  Future<List<Channel>> fetchCatalog() async {
    final config = _requireConfig();

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
          logoUrl: _clean(item['stream_icon']) ??
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
    final id = (channel.dynamicStreamId ?? channel.xtreamStreamId)?.trim() ?? '';
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
    };

    final resolverUri = _resolverUri(config, id);
    final resolverHeaders = _expandMap(
      config.resolverHeaders,
      vars,
      keepEmpty: false,
    );
    final form = _expandMap(
      config.resolverForm,
      vars,
      keepEmpty: true,
    );

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
        retryable: response.statusCode == 408 ||
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

    // En las capturas el mismo ANDROID_ID viaja como device= y X-Did.
    if (androidId != null && androidId.isNotEmpty) {
      _putIfMissingCaseInsensitive(playbackHeaders, 'X-Did', androidId);
    }

    // X-Hash queda deliberadamente opcional. Sirve para una prueba A/B sin
    // atar TV FULL a un algoritmo nativo de otra aplicación.
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
        retryable: response.statusCode == 408 ||
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

  Uri _resolverUri(_DynamicSourceConfig config, String id) {
    final path = config.resolverPath.replaceAll('{id}', Uri.encodeComponent(id));
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

    // Compatibilidad defensiva por si otra implementación devuelve JSON.
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
      ...cleanPath
          .split('/')
          .where((segment) => segment.trim().isNotEmpty),
    ];
    return base.replace(
      pathSegments: pathSegments,
      query: '',
      fragment: '',
    );
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
    final target = key.toLowerCase();
    for (final current in headers.keys) {
      if (current.toLowerCase() == target) return;
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
      return (await _deviceChannel.invokeMethod<String>('getAndroidId'))?.trim();
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
  });

  factory _DynamicSourceConfig.fromMap(Map<String, dynamic> map) {
    final rawServer = map['server']?.toString().trim() ?? '';
    final server = Uri.tryParse(rawServer);
    if (server == null ||
        !(server.scheme == 'http' || server.scheme == 'https') ||
        server.host.isEmpty) {
      throw const FormatException('Servidor Xtream dinámico inválido.');
    }

    final username = map['username']?.toString().trim() ?? '';
    final password = map['password']?.toString().trim() ?? '';
    if (username.isEmpty || password.isEmpty) {
      throw const FormatException('Faltan usuario o contraseña Xtream.');
    }

    final resolverRaw = map['resolver'];
    final resolver = resolverRaw is Map
        ? Map<String, dynamic>.from(resolverRaw)
        : const <String, dynamic>{};

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
          : 'TV clásica 2',
      server: server.replace(query: '', fragment: ''),
      username: username,
      password: password,
      catalogHeaders: _stringMap(map['catalogHeaders']),
      catalogTimeout:
          Duration(milliseconds: catalogTimeoutMs.clamp(1000, 30000)),
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
      resolverTimeout:
          Duration(milliseconds: resolverTimeoutMs.clamp(1000, 30000)),
      playbackHeaders: _stringMap(map['playbackHeaders']),
      xHash: map['xHash']?.toString().trim() ?? '',
    );
  }
}

Map<String, String> _stringMap(dynamic raw) {
  if (raw is! Map) return const <String, String>{};
  final result = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key.toString().trim();
    final value = entry.value?.toString() ?? '';
    if (key.isNotEmpty) result[key] = value;
  }
  return result;
}
