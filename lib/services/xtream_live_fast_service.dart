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

/// Pipeline LIVE Xtream compatible con el patrón observado en Hot Player:
/// categorías e items separados, descarga a disco, soporte JSON/GZIP real,
/// preparación fuera del isolate de UI y reutilización desde almacenamiento
/// local. No usa M3U como fallback para una fuente marcada como Xtream.
class XtreamLiveFastService {
  XtreamLiveFastService._();

  static final XtreamLiveFastService instance = XtreamLiveFastService._();

  static const int _cacheVersion = 3;
  static const Duration _categoryTimeout = Duration(seconds: 8);
  static const Duration _liveTimeout = Duration(seconds: 35);
  static const Duration _connectTimeout = Duration(seconds: 12);

  Directory? _cacheDirectory;
  Directory? _transferDirectory;
  String? _lastDiagnostics;

  String? get lastDiagnostics => _lastDiagnostics;

  Future<XtreamLiveCatalogSnapshot?> loadCached(String playlistUrl) async {
    final files = await _cacheFiles(playlistUrl);
    if (!await files.meta.exists() || !await files.items.exists()) return null;

    try {
      final decoded = jsonDecode(await files.meta.readAsString());
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
    final totalWatch = Stopwatch()..start();
    try {
      // Siempre resolvemos la sesión real al refrescar LIVE. Esto evita depender
      // de una conexión provisional y respeta host/protocolo/puerto server_info.
      var connection = await XtreamFastCatalogService.instance
          .connectionForPlaylist(playlistUrl, forceRefresh: true);

      try {
        return await _fetch(
          connection,
          playlistUrl,
          onProgress,
          totalWatch: totalWatch,
        );
      } on _XtreamLiveHttpException catch (error) {
        if (error.statusCode != 401 && error.statusCode != 403) rethrow;
        XtreamFastCatalogService.instance.invalidateSession(playlistUrl);
        connection = await XtreamFastCatalogService.instance
            .connectionForPlaylist(playlistUrl, forceRefresh: true);
        return _fetch(
          connection,
          playlistUrl,
          onProgress,
          totalWatch: totalWatch,
        );
      }
    } catch (error) {
      if (totalWatch.isRunning) totalWatch.stop();
      final diagnostic = <String>[
        'TV FULL · Diagnóstico LIVE v43',
        'Resultado: ERROR',
        'Tipo: ${error.runtimeType}',
        'Detalle: ${_sanitizeDiagnostic(error.toString())}',
        'TOTAL: ${_formatDuration(totalWatch.elapsed)}',
        'Fecha: ${DateTime.now().toIso8601String()}',
      ].join('\n');
      _lastDiagnostics = diagnostic;
      debugPrint(diagnostic);
      unawaited(_writeDiagnostics(diagnostic));
      rethrow;
    }
  }

  Future<XtreamLiveCatalogSnapshot> _fetch(
    XtreamConnectionResult connection,
    String playlistUrl,
    XtreamCatalogProgressCallback? onProgress, {
    required Stopwatch totalWatch,
  }) async {
    onProgress?.call(
      const XtreamCatalogProgress(
        section: 'LIVE',
        phase: 'Cargando categorías',
        step: 1,
        totalSteps: 3,
      ),
    );

    final categoryWatch = Stopwatch()..start();
    var categoryBytes = 0;
    var categorySuccess = true;
    String categoriesBody;
    try {
      final categoryResult = await _downloadActionBody(
        connection,
        'get_live_categories',
        _categoryTimeout,
        onBytes: (value) {
          categoryBytes = value;
          onProgress?.call(
            XtreamCatalogProgress(
              section: 'LIVE',
              phase: 'Cargando categorías',
              step: 1,
              totalSteps: 3,
              receivedBytes: value,
            ),
          );
        },
      );
      categoriesBody = categoryResult.body;
    } catch (_) {
      categoriesBody = '[]';
      categorySuccess = false;
    }
    categoryWatch.stop();

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

    final prepareWatch = Stopwatch()..start();
    final files = await _cacheFiles(playlistUrl);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final itemsTemp = File('${files.items.path}.tmp_$stamp');
    final metaTemp = File('${files.meta.path}.tmp_$stamp');

    Map<String, dynamic> prepared;
    try {
      prepared = await compute(_prepareLiveCatalogFromFile, <String, String>{
        'categories': categoriesBody,
        'itemsPath': transfer.file.path,
        'outputPath': itemsTemp.path,
        'streamServer': connection.streamServer.toString(),
        'username': connection.username,
        'password': connection.password,
      });
    } finally {
      unawaited(_deleteFileQuietly(transfer.file));
    }
    prepareWatch.stop();

    final count = (prepared['count'] as num?)?.toInt() ?? 0;
    if (count <= 0 || !await itemsTemp.exists()) {
      unawaited(_deleteFileQuietly(itemsTemp));
      throw const FormatException('get_live_streams no devolvió canales válidos.');
    }

    final savedAt = DateTime.now();
    final categories = _stringList(prepared['categories']);
    await metaTemp.writeAsString(
      jsonEncode(<String, dynamic>{
        'version': _cacheVersion,
        'kind': 'live',
        'savedAt': savedAt.millisecondsSinceEpoch,
        'count': count,
        'categories': categories,
      }),
      flush: true,
    );

    await _replaceFile(itemsTemp, files.items);
    await _replaceFile(metaTemp, files.meta);

    final cached = await loadCached(playlistUrl);
    if (cached == null || cached.channels.isEmpty) {
      throw const FormatException('No se pudo reconstruir el catálogo LIVE.');
    }

    XtreamFastCatalogService.instance.rememberConnection(connection);
    if (totalWatch.isRunning) totalWatch.stop();

    final diagnostic = <String>[
      'TV FULL · Diagnóstico LIVE v43',
      'Resultado: OK',
      'Ruta: get_live_categories → get_live_streams → archivo → formato → isolate → caché',
      'Servidor API: ${connection.apiServer.host}',
      'Categorías: ${_formatDuration(categoryWatch.elapsed)} · ${_formatBytes(categoryBytes)} · ${categorySuccess ? 'OK' : 'fallback vacío'}',
      'get_live_streams: HTTP ${transfer.statusCode} · ${_formatDuration(transfer.elapsed)} · ${_formatBytes(transfer.wireBytes)}',
      'Content-Type: ${transfer.contentType ?? 'sin declarar'}',
      'Content-Encoding: ${transfer.contentEncoding ?? 'sin declarar'}',
      'Formato detectado: ${transfer.format}',
      'Payload preparado: ${_formatBytes(transfer.decodedBytes)}',
      'JSON + preparación: ${_formatDuration(prepareWatch.elapsed)}',
      'Canales: ${cached.channels.length}',
      'Categorías finales: ${cached.categories.length}',
      'TOTAL: ${_formatDuration(totalWatch.elapsed)}',
      'Fecha: ${DateTime.now().toIso8601String()}',
    ].join('\n');
    _lastDiagnostics = diagnostic;
    debugPrint(diagnostic);
    unawaited(_writeDiagnostics(diagnostic));

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
        // Una línea dañada nunca invalida el catálogo completo.
      }
    }
    return channels;
  }

  Future<_BodyDownload> _downloadActionBody(
    XtreamConnectionResult connection,
    String action,
    Duration inactivityTimeout, {
    ValueChanged<int>? onBytes,
  }) async {
    final uri = _endpoint(connection.apiServer, action, connection);
    final response = await _sendWithRetry(uri);
    if (response.statusCode != 200) {
      throw _XtreamLiveHttpException(action, response.statusCode);
    }

    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream.timeout(inactivityTimeout)) {
      received += chunk.length;
      builder.add(chunk);
      onBytes?.call(received);
    }
    if (received == 0) {
      throw FormatException('Xtream $action devolvió una respuesta vacía.');
    }

    final raw = builder.takeBytes();
    final decoded = _decodeMaybeGzip(raw);
    return _BodyDownload(
      body: utf8.decode(decoded, allowMalformed: true),
      bytes: received,
    );
  }

  Future<_LiveTransfer> _downloadActionFile(
    XtreamConnectionResult connection,
    String action,
    Duration inactivityTimeout, {
    ValueChanged<int>? onBytes,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      File? file;
      try {
        final uri = _endpoint(connection.apiServer, action, connection);
        final watch = Stopwatch()..start();
        final response = await _sendOnce(uri);
        if (response.statusCode != 200) {
          throw _XtreamLiveHttpException(action, response.statusCode);
        }

        final directory = await _ensureTransferDirectory();
        file = File(
          '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$action.json',
        );
        final sink = file.openWrite();
        var received = 0;
        try {
          await for (final chunk in response.stream.timeout(inactivityTimeout)) {
            received += chunk.length;
            sink.add(chunk);
            onBytes?.call(received);
          }
          await sink.flush();
          await sink.close();
        } catch (_) {
          try {
            await sink.close();
          } catch (_) {}
          rethrow;
        }
        watch.stop();

        if (received == 0) {
          throw FormatException('Xtream $action devolvió una respuesta vacía.');
        }

        final normalized = await _normalizeJsonFile(file);
        file = null;
        return _LiveTransfer(
          file: normalized.file,
          wireBytes: received,
          decodedBytes: normalized.decodedBytes,
          elapsed: watch.elapsed,
          statusCode: response.statusCode,
          contentType: response.headers['content-type'],
          contentEncoding: response.headers['content-encoding'],
          format: normalized.format,
        );
      } catch (error) {
        lastError = error;
        if (file != null) unawaited(_deleteFileQuietly(file));
        if (error is _XtreamLiveHttpException ||
            attempt == 1 ||
            !_retryableConnectionError(error)) {
          rethrow;
        }
        XtreamHttpClient.cancelBrowsingRequests();
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
    }
    throw lastError ?? Exception('No se pudo descargar $action.');
  }

  Future<http.StreamedResponse> _sendWithRetry(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _sendOnce(uri);
      } catch (error) {
        lastError = error;
        if (attempt == 1 || !_retryableConnectionError(error)) rethrow;
        XtreamHttpClient.cancelBrowsingRequests();
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
    }
    throw lastError ?? Exception('No se pudo conectar con Xtream.');
  }

  Future<http.StreamedResponse> _sendOnce(Uri uri) {
    final request = http.Request('GET', uri)
      ..headers.addAll(XtreamHttpClient.jsonHeaders);
    return XtreamHttpClient.instance.send(request).timeout(_connectTimeout);
  }

  bool _retryableConnectionError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('timed out') ||
        text.contains('timeoutexception') ||
        text.contains('clientexception') ||
        text.contains('connection closed');
  }

  Future<_NormalizedJsonFile> _normalizeJsonFile(File source) async {
    final gzipPayload = await _hasGzipMagic(source);
    File usable = source;
    var format = 'JSON';

    if (gzipPayload) {
      format = 'GZIP';
      final decoded = File('${source.path}.decoded.json');
      try {
        await source.openRead().transform(gzip.decoder).pipe(decoded.openWrite());
        await source.delete();
        usable = decoded;
      } catch (_) {
        unawaited(_deleteFileQuietly(decoded));
        rethrow;
      }
    }

    if (!await _looksLikeJsonArray(usable)) {
      final preview = await _safePreview(usable);
      unawaited(_deleteFileQuietly(usable));
      throw FormatException(
        'get_live_streams no devolvió una lista JSON válida. Inicio: $preview',
      );
    }

    return _NormalizedJsonFile(
      file: usable,
      decodedBytes: await usable.length(),
      format: format,
    );
  }

  Future<bool> _hasGzipMagic(File file) async {
    final handle = await file.open();
    try {
      final bytes = await handle.read(2);
      return bytes.length == 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;
    } finally {
      await handle.close();
    }
  }

  Future<bool> _looksLikeJsonArray(File file) async {
    final handle = await file.open();
    try {
      final bytes = await handle.read(1024);
      if (bytes.isEmpty) return false;
      final prefix = utf8
          .decode(bytes, allowMalformed: true)
          .replaceFirst('\uFEFF', '')
          .trimLeft();
      return prefix.startsWith('[');
    } finally {
      await handle.close();
    }
  }

  Future<String> _safePreview(File file) async {
    try {
      final handle = await file.open();
      try {
        final bytes = await handle.read(160);
        return utf8
            .decode(bytes, allowMalformed: true)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      } finally {
        await handle.close();
      }
    } catch (_) {
      return '<sin vista previa>';
    }
  }

  Future<_LiveCacheFiles> _cacheFiles(String playlistUrl) async {
    final directory = await _ensureCacheDirectory();
    final digest = sha256.convert(utf8.encode(playlistUrl.trim())).toString();
    final key = digest.substring(0, 24);
    return _LiveCacheFiles(
      meta: File('${directory.path}/${key}_live_meta.json'),
      items: File('${directory.path}/${key}_live_items.ndjson'),
    );
  }

  Future<Directory> _ensureCacheDirectory() async {
    final current = _cacheDirectory;
    if (current != null) return current;
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/tv_full_xtream_live_cache_v3');
    if (!await directory.exists()) await directory.create(recursive: true);
    _cacheDirectory = directory;
    return directory;
  }

  Future<Directory> _ensureTransferDirectory() async {
    final current = _transferDirectory;
    if (current != null) return current;
    final base = await getTemporaryDirectory();
    final directory = Directory('${base.path}/tv_full_xtream_live_transfer_v3');
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

  Future<void> _writeDiagnostics(String content) async {
    try {
      final directory = await _ensureCacheDirectory();
      final file = File('${directory.path}/live_diagnostic.txt');
      await file.writeAsString(content, flush: true);
    } catch (_) {
      // El diagnóstico nunca debe romper el catálogo.
    }
  }

  Future<void> _deleteFileQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class _BodyDownload {
  final String body;
  final int bytes;

  const _BodyDownload({required this.body, required this.bytes});
}

class _LiveTransfer {
  final File file;
  final int wireBytes;
  final int decodedBytes;
  final Duration elapsed;
  final int statusCode;
  final String? contentType;
  final String? contentEncoding;
  final String format;

  const _LiveTransfer({
    required this.file,
    required this.wireBytes,
    required this.decodedBytes,
    required this.elapsed,
    required this.statusCode,
    required this.contentType,
    required this.contentEncoding,
    required this.format,
  });
}

class _NormalizedJsonFile {
  final File file;
  final int decodedBytes;
  final String format;

  const _NormalizedJsonFile({
    required this.file,
    required this.decodedBytes,
    required this.format,
  });
}

class _LiveCacheFiles {
  final File meta;
  final File items;

  const _LiveCacheFiles({required this.meta, required this.items});
}

class _XtreamLiveHttpException implements Exception {
  final String action;
  final int statusCode;

  const _XtreamLiveHttpException(this.action, this.statusCode);

  @override
  String toString() => 'Xtream $action respondió HTTP $statusCode.';
}

Map<String, dynamic> _prepareLiveCatalogFromFile(Map<String, String> input) {
  final itemsPath = input['itemsPath'];
  final outputPath = input['outputPath'];
  if (itemsPath == null ||
      itemsPath.isEmpty ||
      outputPath == null ||
      outputPath.isEmpty) {
    throw const FormatException('Archivo temporal LIVE inválido.');
  }

  final rawCategories = _optionalJsonList(input['categories']);
  final rawItems = _requiredJsonList(File(itemsPath).readAsStringSync());

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
    throw const FormatException('Servidor de streams Xtream inválido.');
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
      final fallbackCategory = _firstText(item, const <String>[
        'category_name',
        'category',
      ]);
      final category = categoryId == null
          ? fallbackCategory
          : categoryNames[categoryId] ?? fallbackCategory;
      if (category != null && seenCategories.add(category)) {
        orderedCategories.add(category);
      }

      final extension = _cleanExtension(
        _firstText(item, const <String>['container_extension', 'extension']),
        'ts',
      );
      final direct = _safeDirectSource(
        streamServer,
        _cleanText(item['direct_source']),
      );
      final url = direct ??
          _liveUrl(streamServer, username, password, id, extension);

      buffer.writeln(
        jsonEncode(<String, dynamic>{
          'name': name,
          'url': url,
          'logoUrl': _firstText(item, const <String>[
            'stream_icon',
            'logo',
            'icon',
          ]),
          'group': category,
          'tvgId': _firstText(item, const <String>[
            'epg_channel_id',
            'tvg_id',
          ]),
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

List<dynamic> _requiredJsonList(String raw) {
  final decoded = jsonDecode(raw.replaceFirst('\uFEFF', ''));
  if (decoded is! List) {
    throw const FormatException('get_live_streams no devolvió un array JSON.');
  }
  return decoded;
}

List<dynamic> _optionalJsonList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <dynamic>[];
  try {
    final decoded = jsonDecode(raw.replaceFirst('\uFEFF', ''));
    return decoded is List ? decoded : const <dynamic>[];
  } catch (_) {
    return const <dynamic>[];
  }
}

Uint8List _decodeMaybeGzip(Uint8List raw) {
  if (raw.length >= 2 && raw[0] == 0x1F && raw[1] == 0x8B) {
    return Uint8List.fromList(gzip.decode(raw));
  }
  return raw;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map(_cleanText)
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
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

String _cleanExtension(String? raw, String fallback) {
  final value = (raw ?? '').trim().toLowerCase().replaceFirst('.', '');
  if (value.isEmpty || !RegExp(r'^[a-z0-9]{2,6}$').hasMatch(value)) {
    return fallback;
  }
  return value;
}

String? _safeDirectSource(Uri base, String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0') {
    return null;
  }
  try {
    final parsed = Uri.tryParse(value);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) {
      return parsed.toString();
    }
    if (value.startsWith('/')) return base.resolve(value).toString();
  } catch (_) {
    return null;
  }
  return null;
}

String _liveUrl(
  Uri base,
  String username,
  String password,
  String streamId,
  String extension,
) {
  final prefix = base.pathSegments.where((e) => e.trim().isNotEmpty).toList();
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

DateTime? _dateFromMillis(dynamic raw) {
  final millis = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  if (millis == null || millis <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

Uri _endpoint(
  Uri base,
  String action,
  XtreamConnectionResult connection,
) {
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

String _formatDuration(Duration value) =>
    '${(value.inMicroseconds / 1000000).toStringAsFixed(3)} s';

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}

String _sanitizeDiagnostic(String value) {
  return value
      .replaceAll(RegExp(r'([?&]username=)[^&\s]+', caseSensitive: false), r'$1***')
      .replaceAll(RegExp(r'([?&]password=)[^&\s]+', caseSensitive: false), r'$1***');
}
