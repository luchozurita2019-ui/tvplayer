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

class XtreamLiveFastService {
  XtreamLiveFastService._();

  static final XtreamLiveFastService instance = XtreamLiveFastService._();

  static const int _cacheVersion = 2;
  static const Duration _categoryTimeout = Duration(seconds: 6);
  static const Duration _liveTimeout = Duration(seconds: 35);

  Directory? _cacheDirectory;
  Directory? _transferDirectory;

  Future<XtreamLiveCatalogSnapshot?> loadCached(String playlistUrl) async {
    final files = await _cacheFiles(playlistUrl);
    if (!await files.meta.exists() || !await files.items.exists()) {
      unawaited(_deleteLegacyCache(playlistUrl));
      return null;
    }

    try {
      final rawMeta = await files.meta.readAsString();
      final decoded = jsonDecode(rawMeta);
      if (decoded is! Map) return null;
      final meta = Map<String, dynamic>.from(decoded);
      if (meta['version'] != _cacheVersion || meta['kind'] != 'live') {
        return null;
      }

      final channels = await _readCachedChannels(files.items);
      if (channels.isEmpty) return null;

      return XtreamLiveCatalogSnapshot(
        channels: List<Channel>.unmodifiable(channels),
        categories: List<String>.unmodifiable(_stringList(meta['categories'])),
        savedAt: _dateFromMillis(meta['savedAt']) ?? DateTime.now(),
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
        phase: 'Cargando categorías',
        step: 1,
        totalSteps: 3,
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
            phase: 'Cargando categorías',
            step: 1,
            totalSteps: 3,
            receivedBytes: bytes,
          ),
        ),
      );
    } catch (_) {
      categoriesBody = '[]';
    }

    onProgress?.call(
      const XtreamCatalogProgress(
        section: 'LIVE',
        phase: 'Cargando lista',
        step: 2,
        totalSteps: 3,
      ),
    );

    final transfer = await _downloadActionFile(
      connection,
      'get_live_streams',
      _liveTimeout,
      onBytes: (bytes) => onProgress?.call(
        XtreamCatalogProgress(
          section: 'LIVE',
          phase: 'Cargando lista',
          step: 2,
          totalSteps: 3,
          receivedBytes: bytes,
        ),
      ),
    );

    onProgress?.call(
      const XtreamCatalogProgress(
        section: 'LIVE',
        phase: 'Preparando catálogo',
        step: 3,
        totalSteps: 3,
      ),
    );

    final files = await _cacheFiles(playlistUrl);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final itemsTemp = File('${files.items.path}.tmp_$stamp');
    final metaTemp = File('${files.meta.path}.tmp_$stamp');

    Map<String, dynamic> prepared;
    try {
      prepared = await compute(_prepareLiveCacheFromFile, <String, String>{
        'categories': categoriesBody,
        'itemsPath': transfer.file.path,
        'outputPath': itemsTemp.path,
        'streamServer': connection.streamServer.toString(),
        'artworkBase': connection.apiServer.toString(),
        'username': connection.username,
        'password': connection.password,
      });
    } finally {
      unawaited(_deleteFileQuietly(transfer.file));
    }

    final count = (prepared['count'] as num?)?.toInt() ?? 0;
    if (count <= 0 || !await itemsTemp.exists()) {
      unawaited(_deleteFileQuietly(itemsTemp));
      throw const FormatException('Xtream no devolvió canales LIVE válidos.');
    }

    final savedAt = DateTime.now();
    final meta = <String, dynamic>{
      'version': _cacheVersion,
      'kind': 'live',
      'savedAt': savedAt.millisecondsSinceEpoch,
      'count': count,
      'categories': prepared['categories'] ?? const <String>[],
    };
    await metaTemp.writeAsString(jsonEncode(meta), flush: true);

    await _replaceFile(itemsTemp, files.items);
    await _replaceFile(metaTemp, files.meta);
    unawaited(_deleteLegacyCache(playlistUrl));

    final cached = await loadCached(playlistUrl);
    if (cached == null || cached.channels.isEmpty) {
      throw const FormatException('No se pudo reconstruir el catálogo LIVE.');
    }

    XtreamFastCatalogService.instance.rememberConnection(connection);
    return XtreamLiveCatalogSnapshot(
      channels: cached.channels,
      categories: cached.categories,
      savedAt: savedAt,
      fromCache: false,
    );
  }

  Future<List<Channel>> _readCachedChannels(File file) async {
    final channels = <Channel>[];
    final lines = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final item = Map<String, dynamic>.from(decoded);
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
      } catch (_) {
        // Una línea dañada no invalida decenas de miles de canales sanos.
      }
    }
    return channels;
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

  Future<_LiveFileDownload> _downloadActionFile(
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

    final directory = await _ensureTransferDirectory();
    final file = File(
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$action.json',
    );
    final sink = file.openWrite();
    var total = 0;
    try {
      await for (final chunk in response.stream.timeout(inactivityTimeout)) {
        total += chunk.length;
        sink.add(chunk);
        onBytes?.call(total);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      unawaited(_deleteFileQuietly(file));
      rethrow;
    }

    if (total == 0) {
      unawaited(_deleteFileQuietly(file));
      throw const FormatException('Respuesta Xtream vacía.');
    }
    return _LiveFileDownload(file: file);
  }

  Future<_LiveCacheFiles> _cacheFiles(String playlistUrl) async {
    final directory = await _ensureCacheDirectory();
    final digest = sha1.convert(utf8.encode(playlistUrl.trim())).toString();
    return _LiveCacheFiles(
      meta: File('${directory.path}/live_$digest.meta.json'),
      items: File('${directory.path}/live_$digest.ndjson'),
    );
  }

  Future<File> _legacyCacheFile(String playlistUrl) async {
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

  Future<Directory> _ensureTransferDirectory() async {
    final existing = _transferDirectory;
    if (existing != null) return existing;
    final temporary = await getTemporaryDirectory();
    final directory = Directory('${temporary.path}/tv_full_xtream_live_transfer');
    if (!await directory.exists()) await directory.create(recursive: true);
    _transferDirectory = directory;
    unawaited(_cleanupStaleTransfers(directory));
    return directory;
  }

  Future<void> _cleanupStaleTransfers(Directory directory) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 6));
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _replaceFile(File source, File target) async {
    if (await target.exists()) await target.delete();
    await source.rename(target.path);
  }

  Future<void> _deleteLegacyCache(String playlistUrl) async {
    try {
      final legacy = await _legacyCacheFile(playlistUrl);
      if (await legacy.exists()) await legacy.delete();
    } catch (_) {}
  }

  Future<void> _deleteFileQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class _XtreamLiveHttpException implements Exception {
  final int statusCode;
  final String action;

  const _XtreamLiveHttpException(this.statusCode, this.action);

  @override
  String toString() => 'Xtream $action respondió HTTP $statusCode.';
}

class _LiveFileDownload {
  final File file;

  const _LiveFileDownload({required this.file});
}

class _LiveCacheFiles {
  final File meta;
  final File items;

  const _LiveCacheFiles({required this.meta, required this.items});
}

Map<String, dynamic> _prepareLiveCacheFromFile(Map<String, String> input) {
  final itemsPath = input['itemsPath'];
  final outputPath = input['outputPath'];
  if (itemsPath == null ||
      itemsPath.isEmpty ||
      outputPath == null ||
      outputPath.isEmpty) {
    throw const FormatException('Archivo temporal LIVE inválido.');
  }

  final rawCategories = _decodeList(input['categories']);
  final rawItems = _decodeList(File(itemsPath).readAsStringSync());

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
  final artworkBase = Uri.tryParse(input['artworkBase'] ?? '');
  final username = input['username'] ?? '';
  final password = input['password'] ?? '';
  if (streamServer == null || streamServer.host.isEmpty) {
    throw const FormatException('Servidor Xtream LIVE inválido.');
  }

  final out = File(outputPath).openSync(mode: FileMode.write);
  final buffer = StringBuffer();
  var count = 0;

  try {
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
      final logo = _resolveArtwork(
        artworkBase,
        _firstText(item, const ['stream_icon', 'logo', 'icon']),
      );

      buffer.writeln(
        jsonEncode(<String, dynamic>{
          'name': name,
          'url': url,
          'logoUrl': logo,
          'group': category,
          'tvgId': _firstText(item, const ['epg_channel_id', 'tvg_id']),
        }),
      );
      count++;

      if (count % 256 == 0) {
        out.writeStringSync(buffer.toString());
        buffer.clear();
      }
    }

    if (buffer.isNotEmpty) out.writeStringSync(buffer.toString());
    out.flushSync();
  } finally {
    out.closeSync();
  }

  return <String, dynamic>{
    'count': count,
    'categories': orderedCategories,
  };
}

List<dynamic> _decodeList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <dynamic>[];
  final decoded = jsonDecode(raw);
  return decoded is List ? decoded : const <dynamic>[];
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
  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0') {
    return null;
  }
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
  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0') {
    return null;
  }
  final parsed = Uri.tryParse(value);
  if (parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty) {
    return parsed.toString();
  }
  return value.startsWith('/') ? base.resolve(value).toString() : null;
}

String? _resolveArtwork(Uri? base, String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0') {
    return null;
  }
  if (value.startsWith('//') && base != null) return '${base.scheme}:$value';
  final parsed = Uri.tryParse(value);
  if (parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty) {
    return parsed.toString();
  }
  if (base == null || base.host.isEmpty) return value;
  return base.resolve(value).toString();
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
  return base.replace(
    pathSegments: <String>[
      ...prefix,
      'live',
      username,
      password,
      '$streamId.$extension',
    ],
    query: '',
    fragment: '',
  ).toString();
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
