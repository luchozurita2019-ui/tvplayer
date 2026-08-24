import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';
import 'xtream_fast_catalog_service.dart';
import 'xtream_http_client.dart';
import 'xtream_service.dart';

class XtreamLiveCatalogSnapshot {
  final List<Channel> channels;
  final List<String> categories;
  final DateTime savedAt;
  final bool fromCache;

  const XtreamLiveCatalogSnapshot({
    required this.channels,
    required this.categories,
    required this.savedAt,
    required this.fromCache,
  });
}

/// Cargador LIVE nativo con el mismo pipeline rápido de Películas/Series.
///
/// - reutiliza la sesión Xtream ya autenticada;
/// - reutiliza el cliente HTTP keep-alive compartido;
/// - muestra progreso en dos fases (categorías 1/2, canales 2/2);
/// - usa timeout por inactividad, no por duración total;
/// - prepara el catálogo en un isolate;
/// - persiste el último catálogo LIVE para apertura local inmediata;
/// - nunca descarga logos dentro de esta carga.
class XtreamLiveFastService {
  XtreamLiveFastService._();

  static final XtreamLiveFastService instance = XtreamLiveFastService._();

  static const int _cacheVersion = 1;
  static const Duration _categoryTimeout = Duration(seconds: 6);
  static const Duration _liveTimeout = Duration(seconds: 35);

  Directory? _cacheDirectory;

  Future<XtreamLiveCatalogSnapshot?> loadCached(String playlistUrl) async {
    final file = await _cacheFile(playlistUrl);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final payload = await compute(_decodeLiveCachePayload, raw);
      if (payload['version'] != _cacheVersion || payload['kind'] != 'live') {
        return null;
      }
      final channels = _channelsFromPrepared(payload['items']);
      if (channels.isEmpty) return null;
      return XtreamLiveCatalogSnapshot(
        channels: List<Channel>.unmodifiable(channels),
        categories: List<String>.unmodifiable(
          _stringList(payload['categories']),
        ),
        savedAt: _dateFromMillis(payload['savedAt']) ?? DateTime.now(),
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<XtreamLiveCatalogSnapshot> refresh(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    var connection = await XtreamFastCatalogService.instance
        .connectionForPlaylist(playlistUrl, forceRefresh: forceSessionRefresh);

    try {
      return await _fetch(connection, playlistUrl, onProgress);
    } on _XtreamLiveHttpException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 403) rethrow;
      XtreamFastCatalogService.instance.invalidateSession(playlistUrl);
      connection = await XtreamFastCatalogService.instance
          .connectionForPlaylist(playlistUrl, forceRefresh: true);
      return _fetch(connection, playlistUrl, onProgress);
    }
  }

  Future<XtreamLiveCatalogSnapshot> _fetch(
    XtreamConnectionResult connection,
    String playlistUrl,
    XtreamCatalogProgressCallback? onProgress,
  ) async {
    onProgress?.call(
      const XtreamCatalogProgress(
        section: 'LIVE',
        phase: 'Cargando categoría',
        step: 1,
        totalSteps: 2,
      ),
    );

    String categoriesBody = '[]';
    try {
      categoriesBody = await _downloadActionBody(
        connection,
        'get_live_categories',
        _categoryTimeout,
        onBytes: (bytes) => onProgress?.call(
          XtreamCatalogProgress(
            section: 'LIVE',
            phase: 'Cargando categoría',
            step: 1,
            totalSteps: 2,
            receivedBytes: bytes,
          ),
        ),
      );
    } catch (_) {
      // Algunos clones no implementan categorías o responden demasiado lento.
      // get_live_streams suele incluir category_id/category_name suficiente.
      categoriesBody = '[]';
    }

    onProgress?.call(
      const XtreamCatalogProgress(
        section: 'LIVE',
        phase: 'Cargando lista',
        step: 2,
        totalSteps: 2,
      ),
    );

    final streamsBody = await _downloadActionBody(
      connection,
      'get_live_streams',
      _liveTimeout,
      onBytes: (bytes) => onProgress?.call(
        XtreamCatalogProgress(
          section: 'LIVE',
          phase: 'Cargando lista',
          step: 2,
          totalSteps: 2,
          receivedBytes: bytes,
        ),
      ),
    );

    final prepared = await compute(_prepareLiveCatalog, <String, String>{
      'categories': categoriesBody,
      'items': streamsBody,
      'streamServer': connection.streamServer.toString(),
      'username': connection.username,
      'password': connection.password,
    });

    final channels = _channelsFromPrepared(prepared['items']);
    if (channels.isEmpty) {
      throw const FormatException('Xtream no devolvió canales LIVE válidos.');
    }

    final snapshot = XtreamLiveCatalogSnapshot(
      channels: List<Channel>.unmodifiable(channels),
      categories: List<String>.unmodifiable(
        _stringList(prepared['categories']),
      ),
      savedAt: DateTime.now(),
      fromCache: false,
    );
    XtreamFastCatalogService.instance.rememberConnection(connection);
    unawaited(_writePreparedCache(playlistUrl, prepared, snapshot.savedAt));
    return snapshot;
  }

  Future<String> _downloadActionBody(
    XtreamConnectionResult connection,
    String action,
    Duration inactivityTimeout, {
    void Function(int receivedBytes)? onBytes,
  }) async {
    final uri = _endpoint(connection.apiServer, action, connection);
    final request = http.Request('GET', uri)
      ..headers.addAll(XtreamHttpClient.jsonHeaders);
    final response = await XtreamHttpClient.instance
        .send(request)
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _XtreamLiveHttpException(response.statusCode, action);
    }

    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.stream.timeout(inactivityTimeout)) {
      total += chunk.length;
      builder.add(chunk);
      onBytes?.call(total);
    }
    if (total == 0) throw const FormatException('Respuesta Xtream vacía.');
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  Future<void> _writePreparedCache(
    String playlistUrl,
    Map<String, dynamic> prepared,
    DateTime savedAt,
  ) async {
    try {
      final payload = <String, dynamic>{
        'version': _cacheVersion,
        'kind': 'live',
        'savedAt': savedAt.millisecondsSinceEpoch,
        'categories': prepared['categories'] ?? const <String>[],
        'items': prepared['items'] ?? const <dynamic>[],
      };
      final encoded = await compute(_encodeLiveCachePayload, payload);
      final file = await _cacheFile(playlistUrl);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(encoded, flush: false);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (_) {
      // El caché local es una optimización; nunca debe romper LIVE.
    }
  }

  Future<File> _cacheFile(String playlistUrl) async {
    final directory = await _ensureCacheDirectory();
    final digest = sha1.convert(utf8.encode(playlistUrl.trim())).toString();
    return File('${directory.path}/live_$digest.json');
  }

  Future<Directory> _ensureCacheDirectory() async {
    final existing = _cacheDirectory;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/tv_full_xtream_fast_cache');
    if (!await directory.exists()) await directory.create(recursive: true);
    _cacheDirectory = directory;
    return directory;
  }
}

class _XtreamLiveHttpException implements Exception {
  final int statusCode;
  final String action;

  const _XtreamLiveHttpException(this.statusCode, this.action);

  @override
  String toString() => 'Xtream $action respondió HTTP $statusCode.';
}

Map<String, dynamic> _prepareLiveCatalog(Map<String, String> input) {
  final rawCategories = _decodeList(input['categories']);
  final rawItems = _decodeList(input['items']);
  final categoryNames = <String, String>{};
  final orderedCategories = <String>[];
  final seenCategories = <String>{};

  for (final raw in rawCategories) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    final id = _cleanText(item['category_id']);
    final name = _cleanText(item['category_name']);
    if (id == null || name == null) continue;
    categoryNames[id] = name;
    if (seenCategories.add(name)) orderedCategories.add(name);
  }

  final streamServer = Uri.tryParse(input['streamServer'] ?? '');
  final username = input['username'] ?? '';
  final password = input['password'] ?? '';
  if (streamServer == null || streamServer.host.isEmpty) {
    throw const FormatException('Servidor Xtream LIVE inválido.');
  }

  final prepared = <Map<String, dynamic>>[];
  for (final raw in rawItems) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    final id = _cleanText(item['stream_id']);
    final name = _cleanText(item['name']);
    if (id == null || name == null) continue;

    final categoryId = _cleanText(item['category_id']);
    final categoryFallback = _firstText(item, const [
      'category_name',
      'category',
    ]);
    final category = categoryId == null
        ? categoryFallback
        : categoryNames[categoryId] ?? categoryFallback;
    if (category != null && seenCategories.add(category)) {
      orderedCategories.add(category);
    }

    final extension = _cleanExtension(
      _firstText(item, const ['container_extension', 'extension']),
      fallback: 'ts',
    );
    final direct = _resolveDirect(
      streamServer,
      _cleanText(item['direct_source']),
    );
    final url =
        direct ?? _liveUrl(streamServer, username, password, id, extension);

    prepared.add(<String, dynamic>{
      'name': name,
      'url': url,
      'logoUrl': _firstText(item, const ['stream_icon', 'logo', 'icon']),
      'group': category,
      'tvgId': _firstText(item, const ['epg_channel_id', 'tvg_id']),
    });
  }

  return <String, dynamic>{'items': prepared, 'categories': orderedCategories};
}

List<dynamic> _decodeList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <dynamic>[];
  final decoded = jsonDecode(raw);
  return decoded is List ? decoded : const <dynamic>[];
}

Map<String, dynamic> _decodeLiveCachePayload(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) throw const FormatException('Caché LIVE inválido.');
  return Map<String, dynamic>.from(decoded);
}

String _encodeLiveCachePayload(Map<String, dynamic> payload) =>
    jsonEncode(payload);

List<Channel> _channelsFromPrepared(dynamic raw) {
  if (raw is! List) return const <Channel>[];
  final channels = <Channel>[];
  for (final value in raw) {
    if (value is! Map) continue;
    final item = Map<String, dynamic>.from(value);
    final name = _cleanText(item['name']);
    final url = _cleanText(item['url']);
    if (name == null || url == null) continue;
    channels.add(
      Channel(
        name: name,
        url: url,
        logoUrl: _cleanText(item['logoUrl']),
        group: _cleanText(item['group']),
        tvgId: _cleanText(item['tvgId']),
      ),
    );
  }
  return channels;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  final result = <String>[];
  for (final value in raw) {
    final text = _cleanText(value);
    if (text != null) result.add(text);
  }
  return result;
}

DateTime? _dateFromMillis(dynamic raw) {
  final millis = int.tryParse(raw?.toString() ?? '');
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}

String? _firstText(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = _cleanText(source[key]);
    if (value != null) return value;
  }
  return null;
}

String? _cleanText(dynamic raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0')
    return null;
  return value;
}

String _cleanExtension(String? raw, {required String fallback}) {
  final value = (raw ?? '').trim().toLowerCase().replaceFirst('.', '');
  if (value.isEmpty || !RegExp(r'^[a-z0-9]{2,6}$').hasMatch(value)) {
    return fallback;
  }
  return value;
}

String? _resolveDirect(Uri base, String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0')
    return null;
  final parsed = Uri.tryParse(value);
  if (parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty) {
    return parsed.toString();
  }
  return value.startsWith('/') ? base.resolve(value).toString() : null;
}

String _liveUrl(
  Uri base,
  String username,
  String password,
  String streamId,
  String extension,
) {
  final prefix = base.pathSegments.where(
    (segment) => segment.trim().isNotEmpty,
  );
  return base
      .replace(
        pathSegments: <String>[
          ...prefix,
          'live',
          username,
          password,
          '$streamId.$extension',
        ],
        query: '',
        fragment: '',
      )
      .toString();
}

Uri _endpoint(Uri base, String action, XtreamConnectionResult connection) {
  var path = base.path;
  if (path.isEmpty || path == '/') {
    path = '/player_api.php';
  } else {
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    path = '$path/player_api.php';
  }
  return base.replace(
    path: path,
    queryParameters: <String, String>{
      'username': connection.username,
      'password': connection.password,
      'action': action,
    },
    fragment: '',
  );
}
