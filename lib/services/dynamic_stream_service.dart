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

/// Catálogo dinámico y resolución on-demand para fuentes autorizadas.
///
/// La configuración NO se guarda en el repositorio. Se inyecta al compilar con
/// `--dart-define=TV_FULL_DYNAMIC_SOURCE_JSON=...` o desde un constructor de
/// pruebas. Los canales normales M3U/Xtream nunca pasan por este servicio.
class DynamicStreamService {
  DynamicStreamService._({
    String? rawConfig,
    http.Client? client,
    Future<String?> Function()? androidIdProvider,
  })  : _rawConfigOverride = rawConfig,
        _client = client ?? http.Client(),
        _androidIdProvider = androidIdProvider ?? _platformAndroidId;

  static final DynamicStreamService instance = DynamicStreamService._();
  static const String sourcePrefix = 'tvfull-dynamic://catalog/';
  static const String streamPrefix = 'tvfull-dynamic://stream/';
  static const MethodChannel _deviceChannel =
      MethodChannel('tvfull/device_identity');
  static const String _compiledConfig = String.fromEnvironment(
    'TV_FULL_DYNAMIC_SOURCE_JSON',
    defaultValue: '',
  );

  final String? _rawConfigOverride;
  final http.Client _client;
  final Future<String?> Function() _androidIdProvider;
  _DynamicSourceConfig? _config;
  bool _configLoaded = false;
  String? _configurationError;

  @visibleForTesting
  factory DynamicStreamService.forTesting({
    required String configJson,
    required http.Client client,
    Future<String?> Function()? androidIdProvider,
  }) {
    return DynamicStreamService._(
      rawConfig: configJson,
      client: client,
      androidIdProvider: androidIdProvider,
    );
  }

  String get _rawConfig => _rawConfigOverride ?? _compiledConfig;

  bool get isConfigured => _loadConfig() != null;

  String get playlistName => _loadConfig()?.name ?? 'TV clásica 2';

  String get playlistSource {
    final raw = _rawConfig.trim();
    if (raw.isEmpty) return '${sourcePrefix}disabled';
    final fingerprint = sha256.convert(utf8.encode(raw)).toString().substring(0, 12);
    return '$sourcePrefix$fingerprint';
  }

  bool handlesSource(String source) =>
      isConfigured && source.trim().startsWith(sourcePrefix);

  Future<List<Channel>> fetchCatalog() async {
    final config = _requireConfig();
    final androidId = await _safeAndroidId();
    final vars = <String, String>{'androidId': androidId ?? ''};
    final response = await _send(config.catalog, vars);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) {
      throw const DynamicStreamException(
        'El catálogo dinámico respondió vacío.',
        retryable: true,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const DynamicStreamException(
        'El catálogo dinámico no devolvió JSON válido.',
      );
    }

    final items = _catalogItems(decoded, config.itemsPath);
    final channels = <Channel>[];
    final seen = <String>{};
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = _pick(item, config.idKeys);
      if (id == null || id.isEmpty || !seen.add(id)) continue;
      final name = _pick(item, config.nameKeys) ?? 'Canal $id';
      final group = _pick(item, config.groupKeys);
      final logo = _pick(item, config.logoKeys);
      final tvgId = _pick(item, config.tvgIdKeys);
      channels.add(
        Channel(
          name: name,
          url: '$streamPrefix${Uri.encodeComponent(id)}',
          logoUrl: logo,
          group: group,
          tvgId: tvgId,
          dynamicStreamId: id,
        ),
      );
    }

    if (channels.isEmpty) {
      throw const DynamicStreamException(
        'El catálogo dinámico no contiene canales válidos.',
      );
    }
    return List<Channel>.unmodifiable(channels);
  }

  Future<ResolvedDynamicStream> resolve(Channel channel) async {
    final config = _requireConfig();
    final id = channel.dynamicStreamId?.trim() ?? '';
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
    final response = await _send(config.resolver, vars);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    final url = _resolvedUrl(body, config.resolverUrlPath);
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        !(parsed.scheme == 'http' || parsed.scheme == 'https') ||
        parsed.host.isEmpty) {
      throw const DynamicStreamException(
        'El resolvedor devolvió una URL de reproducción inválida.',
      );
    }

    return ResolvedDynamicStream(
      url: parsed.toString(),
      headers: _expandMap(config.playbackHeaders, vars),
    );
  }

  _DynamicSourceConfig? _loadConfig() {
    if (_configLoaded) return _config;
    _configLoaded = true;
    final raw = _rawConfig.trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _configurationError = 'La configuración dinámica debe ser un objeto JSON.';
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

  Future<http.Response> _send(
    _DynamicRequest request,
    Map<String, String> vars,
  ) async {
    final method = request.method.toUpperCase();
    if (method != 'GET' && method != 'POST') {
      throw DynamicStreamException(
        'Método dinámico no admitido: $method.',
      );
    }

    var uri = Uri.tryParse(_expand(request.url, vars));
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw const DynamicStreamException('URL dinámica inválida.');
    }
    final headers = _expandMap(request.headers, vars);
    final form = _expandMap(request.form, vars);

    if (method == 'GET' && form.isNotEmpty) {
      final merged = Map<String, String>.from(uri.queryParameters)..addAll(form);
      uri = uri.replace(queryParameters: merged);
    }

    final outgoing = http.Request(method, uri)..headers.addAll(headers);
    if (method == 'POST' && form.isNotEmpty) {
      outgoing.headers.putIfAbsent(
        'Content-Type',
        () => 'application/x-www-form-urlencoded',
      );
      outgoing.body = form.entries
          .map(
            (entry) =>
                '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
          )
          .join('&');
    }

    http.StreamedResponse streamed;
    try {
      streamed = await _client.send(outgoing).timeout(request.timeout);
    } on TimeoutException {
      throw DynamicStreamException(
        'Tiempo de espera agotado al consultar ${_safeTarget(uri)}.',
        retryable: true,
      );
    } catch (error) {
      throw DynamicStreamException(
        'No se pudo consultar ${_safeTarget(uri)}.',
        retryable: true,
      );
    }

    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final retryable = response.statusCode == 408 ||
          response.statusCode == 429 ||
          response.statusCode >= 500;
      throw DynamicStreamException(
        'El servicio dinámico respondió HTTP ${response.statusCode}.',
        retryable: retryable,
      );
    }
    return response;
  }

  List<dynamic> _catalogItems(dynamic decoded, String path) {
    dynamic value = path.trim().isEmpty ? decoded : _valueAtPath(decoded, path);
    if (value is List) return value;
    if (value is Map) {
      for (final key in const ['channels', 'items', 'data', 'results', 'live']) {
        final candidate = value[key];
        if (candidate is List) return candidate;
      }
      for (final candidate in value.values) {
        if (candidate is List) return candidate;
      }
    }
    throw const DynamicStreamException(
      'No se encontró la colección de canales en la respuesta del catálogo.',
    );
  }

  String _resolvedUrl(String body, String path) {
    if (body.isEmpty) {
      throw const DynamicStreamException(
        'El resolvedor respondió vacío.',
        retryable: true,
      );
    }
    if (body.startsWith('http://') || body.startsWith('https://')) return body;

    try {
      final decoded = jsonDecode(body);
      if (decoded is String) return decoded.trim();
      if (path.trim().isNotEmpty) {
        final value = _valueAtPath(decoded, path);
        if (value != null) return value.toString().trim();
      }
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        for (final key in const [
          'url',
          'stream_url',
          'streamUrl',
          'stream',
          'link',
          'm3u8',
        ]) {
          final value = map[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            return value.toString().trim();
          }
        }
        for (final nestedKey in const ['data', 'result']) {
          final nested = map[nestedKey];
          if (nested is Map) {
            for (final key in const ['url', 'stream_url', 'streamUrl', 'link']) {
              final value = nested[key];
              if (value != null && value.toString().trim().isNotEmpty) {
                return value.toString().trim();
              }
            }
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

  dynamic _valueAtPath(dynamic value, String rawPath) {
    if (rawPath.trim().isEmpty) return value;
    dynamic current = value;
    for (final segment in rawPath.split('.')) {
      if (current is! Map) return null;
      current = current[segment];
    }
    return current;
  }

  String? _pick(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = _valueAtPath(item, key);
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }

  Map<String, String> _expandMap(
    Map<String, String> values,
    Map<String, String> vars,
  ) {
    return {
      for (final entry in values.entries)
        _expand(entry.key, vars): _expand(entry.value, vars),
    };
  }

  String _expand(String value, Map<String, String> vars) {
    var result = value;
    for (final entry in vars.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  String _safeTarget(Uri uri) => '${uri.scheme}://${uri.host}${uri.path}';

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
      return await _deviceChannel.invokeMethod<String>('getAndroidId');
    } on PlatformException {
      return null;
    }
  }
}

class _DynamicSourceConfig {
  final String name;
  final _DynamicRequest catalog;
  final _DynamicRequest resolver;
  final String itemsPath;
  final String resolverUrlPath;
  final List<String> idKeys;
  final List<String> nameKeys;
  final List<String> groupKeys;
  final List<String> logoKeys;
  final List<String> tvgIdKeys;
  final Map<String, String> playbackHeaders;

  const _DynamicSourceConfig({
    required this.name,
    required this.catalog,
    required this.resolver,
    required this.itemsPath,
    required this.resolverUrlPath,
    required this.idKeys,
    required this.nameKeys,
    required this.groupKeys,
    required this.logoKeys,
    required this.tvgIdKeys,
    required this.playbackHeaders,
  });

  factory _DynamicSourceConfig.fromMap(Map<String, dynamic> map) {
    final catalogRaw = map['catalog'];
    final resolverRaw = map['resolver'];
    if (catalogRaw is! Map || resolverRaw is! Map) {
      throw const FormatException('Faltan catalog/resolver.');
    }
    final catalog = Map<String, dynamic>.from(catalogRaw);
    final resolver = Map<String, dynamic>.from(resolverRaw);
    final fieldsRaw = catalog['fields'];
    final fields = fieldsRaw is Map
        ? Map<String, dynamic>.from(fieldsRaw)
        : const <String, dynamic>{};

    return _DynamicSourceConfig(
      name: map['name']?.toString().trim().isNotEmpty == true
          ? map['name'].toString().trim()
          : 'TV clásica 2',
      catalog: _DynamicRequest.fromMap(catalog),
      resolver: _DynamicRequest.fromMap(resolver),
      itemsPath: catalog['itemsPath']?.toString().trim() ?? '',
      resolverUrlPath: resolver['urlPath']?.toString().trim() ?? '',
      idKeys: _keys(fields['id'], const ['id', 'stream_id', 'channel_id']),
      nameKeys: _keys(fields['name'], const ['name', 'title', 'channel_name']),
      groupKeys: _keys(
        fields['group'],
        const ['group', 'category', 'category_name', 'group_title'],
      ),
      logoKeys: _keys(fields['logo'], const ['logo', 'logo_url', 'stream_icon']),
      tvgIdKeys: _keys(fields['tvgId'], const ['tvg_id', 'epg_id', 'xmltv_id']),
      playbackHeaders: _stringMap(map['playbackHeaders']),
    );
  }

  static List<String> _keys(dynamic raw, List<String> fallback) {
    if (raw is List) {
      final values = raw
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (values.isNotEmpty) return values;
    }
    if (raw is String && raw.trim().isNotEmpty) return [raw.trim()];
    return fallback;
  }
}

class _DynamicRequest {
  final String url;
  final String method;
  final Map<String, String> headers;
  final Map<String, String> form;
  final Duration timeout;

  const _DynamicRequest({
    required this.url,
    required this.method,
    required this.headers,
    required this.form,
    required this.timeout,
  });

  factory _DynamicRequest.fromMap(Map<String, dynamic> map) {
    final url = map['url']?.toString().trim() ?? '';
    if (url.isEmpty) throw const FormatException('Falta URL dinámica.');
    final timeoutMs = int.tryParse(map['timeoutMs']?.toString() ?? '') ?? 8000;
    return _DynamicRequest(
      url: url,
      method: map['method']?.toString().trim().toUpperCase() ?? 'GET',
      headers: _stringMap(map['headers']),
      form: _stringMap(map['form']),
      timeout: Duration(milliseconds: timeoutMs.clamp(1000, 30000)),
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
