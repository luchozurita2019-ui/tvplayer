from pathlib import Path

ROOT = Path('.')


def replace_once(path: str, old: str, new: str, label: str) -> None:
    file = ROOT / path
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    file.write_text(text.replace(old, new, 1))


def write_file(path: str, content: str) -> None:
    file = ROOT / path
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(content)


# Channel: persist a stable logical stream id without changing normal M3U/Xtream URLs.
replace_once(
    'lib/models/channel.dart',
    "  final String? xtreamStreamId; // stream_id real para APIs Xtream (EPG, etc.)\n",
    "  final String? xtreamStreamId; // stream_id real para APIs Xtream (EPG, etc.)\n  final String? dynamicStreamId; // id lógico resuelto al abrir el canal\n",
    'Channel dynamicStreamId field',
)
replace_once(
    'lib/models/channel.dart',
    "    this.xtreamStreamId,\n    this.httpUserAgent,\n",
    "    this.xtreamStreamId,\n    this.dynamicStreamId,\n    this.httpUserAgent,\n",
    'Channel constructor dynamicStreamId',
)
replace_once(
    'lib/models/channel.dart',
    "        'xtreamStreamId': xtreamStreamId,\n        'httpUserAgent': httpUserAgent,\n",
    "        'xtreamStreamId': xtreamStreamId,\n        if (dynamicStreamId != null) 'dynamicStreamId': dynamicStreamId,\n        'httpUserAgent': httpUserAgent,\n",
    'Channel toJson dynamicStreamId',
)
replace_once(
    'lib/models/channel.dart',
    "      xtreamStreamId: json['xtreamStreamId'] as String?,\n      httpUserAgent: json['httpUserAgent'] as String?,\n",
    "      xtreamStreamId: json['xtreamStreamId'] as String?,\n      dynamicStreamId: json['dynamicStreamId'] as String?,\n      httpUserAgent: json['httpUserAgent'] as String?,\n",
    'Channel fromJson dynamicStreamId',
)
replace_once(
    'lib/models/channel.dart',
    "  String get uniqueKey => '$name|$url';\n",
    "  String get uniqueKey {\n    final dynamicId = dynamicStreamId?.trim();\n    return dynamicId == null || dynamicId.isEmpty\n        ? '$name|$url'\n        : '$name|dynamic:$dynamicId';\n  }\n",
    'Channel dynamic uniqueKey',
)

# Configurable, authorized dynamic catalog + stream resolver. No provider host,
# credentials, reverse-engineered hash, or third-party secret is embedded here.
write_file(
    'lib/services/dynamic_stream_service.dart',
    r'''import 'dart:async';
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
    return body.replaceAll(RegExp(r'^["\']|["\']$'), '').trim();
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
''',
)

# Add a built-in dynamic playlist only when an authorized configuration exists.
replace_once(
    'lib/providers/iptv_provider.dart',
    "import '../services/m3u_parser.dart';\n",
    "import '../services/dynamic_stream_service.dart';\nimport '../services/m3u_parser.dart';\n",
    'Provider dynamic service import',
)
replace_once(
    'lib/providers/iptv_provider.dart',
    "  static const _classicPlaylistSource =\n      'asset://assets/playlists/lista_clasica.m3u';\n",
    "  static const _classicPlaylistSource =\n      'asset://assets/playlists/lista_clasica.m3u';\n  static const _dynamicPlaylistId = 'tvf_builtin_dynamic_classic_2';\n",
    'Provider dynamic playlist id',
)
replace_once(
    'lib/providers/iptv_provider.dart',
    "    await _ensureClassicPlaylist();\n    _normalizeSelection();\n",
    "    await _ensureClassicPlaylist();\n    await _ensureDynamicPlaylist();\n    _normalizeSelection();\n",
    'Provider ensure dynamic playlist',
)
replace_once(
    'lib/providers/iptv_provider.dart',
    "  Playlist? playlistById(String playlistId) {\n",
    r'''  Future<void> _ensureDynamicPlaylist() async {
    final service = DynamicStreamService.instance;
    final index =
        _playlists.indexWhere((item) => item.id == _dynamicPlaylistId);

    if (!service.isConfigured) {
      if (index < 0) return;
      _playlists = _playlists
          .where((item) => item.id != _dynamicPlaylistId)
          .toList(growable: false);
      await _localStore.clearServiceCatalogs(_dynamicPlaylistId);
      await _localStore.saveServices(_playlists);
      return;
    }

    final dynamicPlaylist = Playlist(
      id: _dynamicPlaylistId,
      name: service.playlistName,
      source: service.playlistSource,
      isRemote: true,
      channels: const <Channel>[],
      lastUpdated: DateTime.now(),
      sourceType: PlaylistSourceType.m3u,
    );

    if (index < 0) {
      _playlists = [..._playlists, dynamicPlaylist];
      await _localStore.saveServices(_playlists);
      return;
    }

    final current = _playlists[index];
    if (current.name == dynamicPlaylist.name &&
        current.source == dynamicPlaylist.source) {
      return;
    }

    final next = List<Playlist>.from(_playlists);
    next[index] = dynamicPlaylist.copyWith(lastUpdated: current.lastUpdated);
    _playlists = next;
    await _localStore.clearServiceCatalogs(_dynamicPlaylistId);
    await _localStore.saveServices(_playlists);
  }

  Playlist? playlistById(String playlistId) {
''',
    'Provider dynamic playlist method',
)

# Route the special source through the existing on-disk catalog/cache pipeline.
replace_once(
    'lib/services/section_catalog_service.dart',
    "import 'device_performance_service.dart';\n",
    "import 'device_performance_service.dart';\nimport 'dynamic_stream_service.dart';\n",
    'Section catalog dynamic import',
)
replace_once(
    'lib/services/section_catalog_service.dart',
    "  Future<void> _downloadAndPartitionToDisk(Playlist playlist) async {\n    final parser = M3uLineParser();\n",
    "  Future<void> _downloadAndPartitionToDisk(Playlist playlist) async {\n    if (DynamicStreamService.instance.handlesSource(playlist.source)) {\n      await _downloadDynamicAndPartitionToDisk(playlist);\n      return;\n    }\n\n    final parser = M3uLineParser();\n",
    'Section catalog dynamic dispatch',
)
replace_once(
    'lib/services/section_catalog_service.dart',
    "  void _remember(String key, SectionCatalogSnapshot snapshot) {\n",
    r'''  Future<void> _downloadDynamicAndPartitionToDisk(Playlist playlist) async {
    final channels = await DynamicStreamService.instance.fetchCatalog();
    final writers = <TvSectionKind, CatalogFileWriter>{};
    final categorySets = <TvSectionKind, Set<String>>{
      for (final kind in TvSectionKind.values) kind: <String>{},
    };
    final categories = <TvSectionKind, List<String>>{
      for (final kind in TvSectionKind.values) kind: <String>[],
    };

    for (final kind in TvSectionKind.values) {
      writers[kind] = await _catalogFiles.beginSnapshot(
        serviceId: playlist.id,
        kind: 'm3u_${kind.name}',
      );
    }

    try {
      for (final channel in channels) {
        final kind = _classify(channel);
        writers[kind]!.add(channel.toJson());
        final group = channel.group?.trim();
        if (group != null &&
            group.isNotEmpty &&
            categorySets[kind]!.add(group)) {
          categories[kind]!.add(group);
        }
      }

      for (final kind in TvSectionKind.values) {
        final writer = writers[kind]!;
        if (writer.count == 0) {
          await writer.abort();
          continue;
        }
        final committed = await writer.commit(categories: categories[kind]!);
        if (committed) _forget('${playlist.id}|m3u_${kind.name}');
      }
      _lastNetworkRefresh['${playlist.id}|${playlist.source}'] = DateTime.now();
    } catch (_) {
      for (final writer in writers.values) {
        await writer.abort();
      }
      rethrow;
    }
  }

  void _remember(String key, SectionCatalogSnapshot snapshot) {
''',
    'Section catalog dynamic writer',
)
replace_once(
    'lib/services/section_catalog_service.dart',
    "      bytes += _stringBytes(channel.tvgId);\n      bytes += _stringBytes(channel.httpUserAgent);\n",
    "      bytes += _stringBytes(channel.tvgId);\n      bytes += _stringBytes(channel.dynamicStreamId);\n      bytes += _stringBytes(channel.httpUserAgent);\n",
    'Section catalog dynamic memory estimate',
)

# Resolve only dynamic channels immediately before Media3 prepare. Normal channels
# continue to use the exact V38 path, including retries and first-frame logic.
replace_once(
    'lib/screens/android_media3_texture_player_screen.dart',
    "import '../services/device_performance_service.dart';\n",
    "import '../services/device_performance_service.dart';\nimport '../services/dynamic_stream_service.dart';\n",
    'Media3 dynamic resolver import',
)
replace_once(
    'lib/screens/android_media3_texture_player_screen.dart',
    r'''    final headers = Map<String, String>.from(_headers);
    String? userAgent;
    for (final key in headers.keys.toList()) {
      if (key.toLowerCase() == 'user-agent') {
        userAgent = headers.remove(key);
        break;
      }
    }

    try {
      await _player.invokeMethod<void>('prepare', {
        'url': _channel.url,
        'requestGeneration': generation,
        'headers': headers,
        'userAgent': userAgent ?? _media3DefaultUserAgent,
        'isLive': true,
      });
    } on PlatformException catch (error) {
      if (!mounted || generation != _openGeneration) return;
      _handleTechnicalError(error.code, error.message ?? error.code);
    }
''',
    r'''    var playbackUrl = _channel.url;
    final headers = Map<String, String>.from(_headers);

    try {
      if ((_channel.dynamicStreamId?.trim().isNotEmpty ?? false)) {
        final resolved = await DynamicStreamService.instance.resolve(_channel);
        if (!mounted || generation != _openGeneration) return;
        playbackUrl = resolved.url;
        headers.addAll(resolved.headers);
      }

      String? userAgent;
      for (final key in headers.keys.toList()) {
        if (key.toLowerCase() == 'user-agent') {
          userAgent = headers.remove(key);
          break;
        }
      }

      await _player.invokeMethod<void>('prepare', {
        'url': playbackUrl,
        'requestGeneration': generation,
        'headers': headers,
        'userAgent': userAgent ?? _media3DefaultUserAgent,
        'isLive': true,
      });
    } on DynamicStreamException catch (error) {
      if (!mounted || generation != _openGeneration) return;
      _handleTechnicalError(
        'DYNAMIC_RESOLVE',
        error.message,
        retryable: error.retryable,
        category: error.retryable ? 'network' : 'configuration',
      );
    } on PlatformException catch (error) {
      if (!mounted || generation != _openGeneration) return;
      _handleTechnicalError(error.code, error.message ?? error.code);
    }
''',
    'Media3 resolve before prepare',
)

write_file(
    'test/dynamic_stream_service_test.dart',
    r'''import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/dynamic_stream_service.dart';

void main() {
  const config = '''
{
  "name": "TV clásica 2",
  "catalog": {
    "url": "https://authorized.example/catalog",
    "method": "GET",
    "itemsPath": "channels",
    "fields": {
      "id": ["id"],
      "name": ["name"],
      "group": ["category"],
      "logo": ["logo"]
    }
  },
  "resolver": {
    "url": "https://authorized.example/resolve/{id}",
    "method": "POST",
    "form": {
      "stream_id": "{id}",
      "device_id": "{androidId}"
    },
    "urlPath": "url"
  },
  "playbackHeaders": {
    "X-Device": "{androidId}"
  }
}
''';

  test('catalog creates logical dynamic channels and resolver runs on demand', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/catalog') {
        return http.Response(
          jsonEncode({
            'channels': [
              {
                'id': 1111,
                'name': 'Canal Uno',
                'category': 'Noticias',
                'logo': 'https://img.example/logo.png',
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/resolve/1111') {
        expect(request.method, 'POST');
        expect(request.body, contains('stream_id=1111'));
        expect(request.body, contains('device_id=device-test'));
        return http.Response(
          jsonEncode({'url': 'https://cdn.example/live/1111.m3u8'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final service = DynamicStreamService.forTesting(
      configJson: config,
      client: client,
      androidIdProvider: () async => 'device-test',
    );

    final channels = await service.fetchCatalog();
    expect(channels, hasLength(1));
    expect(channels.single.name, 'Canal Uno');
    expect(channels.single.group, 'Noticias');
    expect(channels.single.dynamicStreamId, '1111');
    expect(channels.single.url, 'tvfull-dynamic://stream/1111');

    final resolved = await service.resolve(channels.single);
    expect(resolved.url, 'https://cdn.example/live/1111.m3u8');
    expect(resolved.headers['X-Device'], 'device-test');
  });

  test('dynamic stream id survives Channel JSON cache roundtrip', () {
    const original = Channel(
      name: 'Canal',
      url: 'tvfull-dynamic://stream/9',
      dynamicStreamId: '9',
    );
    final restored = Channel.fromJson(original.toJson());
    expect(restored.dynamicStreamId, '9');
    expect(restored.uniqueKey, 'Canal|dynamic:9');
  });
}
''',
)

write_file(
    'docs/dynamic_stream_source.md',
    r'''# Fuente dinámica de TV FULL PRO

Esta integración mantiene intactas las listas M3U/Xtream existentes y sólo se
activa cuando el build recibe `TV_FULL_DYNAMIC_SOURCE_JSON`.

No se deben guardar credenciales de terceros ni secretos obtenidos de otra
aplicación en el repositorio. La configuración debe corresponder a un servicio
propio o autorizado.

## Flujo

1. TV FULL descarga el catálogo configurado.
2. Guarda nombre, categoría, logo y un `dynamicStreamId` estable.
3. Al abrir o cambiar de canal, solicita una URL temporal al resolvedor.
4. Entrega esa URL y los headers de reproducción a Media3.
5. Un reintento vuelve a resolver el canal, por lo que no reutiliza una URL
   temporal vencida.

## Configuración

Ejemplo de esquema (dominios ficticios):

```json
{
  "name": "TV clásica 2",
  "catalog": {
    "url": "https://authorized.example/catalog",
    "method": "GET",
    "headers": {},
    "form": {},
    "itemsPath": "channels",
    "fields": {
      "id": ["id", "stream_id"],
      "name": ["name", "title"],
      "group": ["category"],
      "logo": ["logo"],
      "tvgId": ["tvg_id"]
    }
  },
  "resolver": {
    "url": "https://authorized.example/resolve/{id}",
    "method": "POST",
    "headers": {},
    "form": {
      "stream_id": "{id}",
      "device_id": "{androidId}"
    },
    "urlPath": "url"
  },
  "playbackHeaders": {
    "X-Device": "{androidId}"
  }
}
```

Placeholders admitidos: `{id}`, `{androidId}`, `{name}` y `{group}`.

Para producción conviene entregar esta configuración desde el backend/panel de
TV FULL en vez de compilar secretos dentro del APK.
''',
)

print('Dynamic stream resolver V40 patch applied.')
