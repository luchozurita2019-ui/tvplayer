import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';

/// Cache de logos y carátulas orientado a IPTV.
///
/// El catálogo nunca espera imágenes. Cada [CachedArtworkImage] mantiene interés
/// solamente mientras está visible (o muy cerca del viewport), de modo que la
/// red se usa para lo que el usuario está mirando en ese momento.
///
/// Las imágenes ya descargadas se conservan en disco para volver a mostrarlas
/// instantáneamente, pero el caché tiene un presupuesto global y poda LRU para
/// que no crezca indefinidamente.
class ArtworkCacheService {
  ArtworkCacheService._();

  static final ArtworkCacheService instance = ArtworkCacheService._();

  static const int _maxConcurrent = 3;
  static const int _maxArtworkBytes = 3 * 1024 * 1024;
  static const int _maxDiskCacheBytes = 128 * 1024 * 1024;
  static const int _trimDiskCacheToBytes = 96 * 1024 * 1024;
  static const int _pruneEveryDownloads = 24;
  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _chunkTimeout = Duration(seconds: 6);
  static const Duration _touchInterval = Duration(minutes: 15);
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  final Queue<_ArtworkRequest> _queue = Queue<_ArtworkRequest>();
  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};
  final Map<String, File> _knownFiles = <String, File>{};
  final Map<String, int> _interest = <String, int>{};
  final Map<String, DateTime> _lastTouch = <String, DateTime>{};

  Directory? _cacheDirectory;
  http.Client? _client;
  String? _providerId;
  int _generation = 0;
  int _active = 0;
  int _downloadsSincePrune = 0;
  bool _pausedForPlayback = false;
  bool _pruneRunning = false;

  bool get pausedForPlayback => _pausedForPlayback;

  /// Cambiar de proveedor cancela cualquier arte pendiente del proveedor
  /// anterior. No se realiza ninguna precarga de imágenes.
  Future<void> switchProvider(String providerId) async {
    if (_providerId == providerId && !_pausedForPlayback) {
      await _ensureCacheDirectory();
      return;
    }

    _providerId = providerId;
    _pausedForPlayback = false;
    _cancelNetworkWork();
    _client = http.Client();
    await _ensureCacheDirectory();
    _schedulePrune();
  }

  /// Compatibilidad con el flujo anterior: sólo prepara el proveedor. Antes
  /// esta función descargaba logos/posters y podía retrasar la apertura.
  Future<void> warmProvider(Playlist playlist) => switchProvider(playlist.id);

  /// Ya no precalentamos secciones. Las tarjetas visibles solicitan su propia
  /// imagen mediante [retain] + [resolve].
  Future<void> warmSection(
    List<Channel> channels, {
    required int limit,
    Duration maxWait = const Duration(milliseconds: 1800),
  }) async {}

  /// Se conserva la API para no romper llamadores antiguos, pero el modelo
  /// actual es estrictamente bajo demanda/viewport.
  Future<void> warmUrls(
    Iterable<String> urls, {
    Duration maxWait = const Duration(seconds: 2),
  }) async {}

  /// Registra que una tarjeta visible necesita esta imagen. Las solicitudes
  /// demand-driven sin consumidores son descartadas/canceladas.
  void retain(String? rawUrl) {
    final url = _validArtworkUrl(rawUrl);
    if (url == null) return;
    _interest[url] = (_interest[url] ?? 0) + 1;
  }

  /// Libera el interés de una tarjeta que dejó el viewport o fue destruida.
  void release(String? rawUrl) {
    final url = _validArtworkUrl(rawUrl);
    if (url == null) return;
    final current = _interest[url] ?? 0;
    if (current <= 1) {
      _interest.remove(url);
      _discardUnneededQueuedRequests(url);
    } else {
      _interest[url] = current - 1;
    }
  }

  void pauseForPlayback() {
    if (_pausedForPlayback) return;
    _pausedForPlayback = true;
    _cancelNetworkWork();
  }

  void resumeBrowsing() {
    if (!_pausedForPlayback) return;
    _pausedForPlayback = false;
    _client = http.Client();
    _drainQueue();
  }

  Future<File?> resolve(
    String? rawUrl, {
    bool allowNetwork = true,
    bool demandDriven = false,
  }) async {
    final url = _validArtworkUrl(rawUrl);
    if (url == null) return null;

    final known = _knownFiles[url];
    if (known != null && await known.exists()) {
      _touchFile(url, known);
      return known;
    }

    final directory = await _ensureCacheDirectory();
    final file = File('${directory.path}/${_fileNameFor(url)}.img');
    if (await file.exists()) {
      _knownFiles[url] = file;
      _touchFile(url, file);
      return file;
    }

    if (!allowNetwork || _pausedForPlayback) return null;
    if (demandDriven && !_hasInterest(url)) return null;

    final existing = _inFlight[url];
    if (existing != null) return existing;

    final completer = Completer<File?>();
    final request = _ArtworkRequest(
      url: url,
      generation: _generation,
      demandDriven: demandDriven,
      completer: completer,
    );
    _queue.add(request);
    final future = completer.future;
    _inFlight[url] = future;
    future.whenComplete(() {
      if (identical(_inFlight[url], future)) _inFlight.remove(url);
    });
    _drainQueue();
    return future;
  }

  Future<Directory> _ensureCacheDirectory() async {
    final current = _cacheDirectory;
    if (current != null) return current;
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/tv_full_artwork_cache');
    if (!await directory.exists()) await directory.create(recursive: true);
    _cacheDirectory = directory;
    return directory;
  }

  bool _hasInterest(String url) => (_interest[url] ?? 0) > 0;

  bool _requestStillWanted(_ArtworkRequest request) {
    if (request.generation != _generation || _pausedForPlayback) return false;
    if (request.demandDriven && !_hasInterest(request.url)) return false;
    return true;
  }

  void _discardUnneededQueuedRequests(String url) {
    if (_queue.isEmpty) return;
    final pending = _queue.toList(growable: false);
    _queue.clear();
    for (final request in pending) {
      if (request.url == url &&
          request.demandDriven &&
          !_hasInterest(url)) {
        if (!request.completer.isCompleted) request.completer.complete(null);
      } else {
        _queue.add(request);
      }
    }
  }

  void _cancelNetworkWork() {
    _generation++;
    _client?.close();
    _client = null;
    while (_queue.isNotEmpty) {
      final request = _queue.removeFirst();
      if (!request.completer.isCompleted) request.completer.complete(null);
    }
  }

  void _drainQueue() {
    if (_pausedForPlayback) return;
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      if (!_requestStillWanted(request)) {
        if (!request.completer.isCompleted) request.completer.complete(null);
        continue;
      }
      _active++;
      unawaited(
        _download(request).whenComplete(() {
          _active--;
          _drainQueue();
        }),
      );
    }
  }

  Future<void> _download(_ArtworkRequest request) async {
    File? result;
    try {
      if (!_requestStillWanted(request)) return;
      final client = _client ??= http.Client();
      final httpRequest = http.Request('GET', Uri.parse(request.url))
        ..headers.addAll(const {
          'User-Agent': _userAgent,
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        });
      final response = await client.send(httpRequest).timeout(_connectTimeout);
      if (!_requestStillWanted(request)) return;
      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final expected = response.contentLength;
      if (expected != null && expected > _maxArtworkBytes) return;

      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.stream.timeout(_chunkTimeout)) {
        if (!_requestStillWanted(request)) return;
        total += chunk.length;
        if (total > _maxArtworkBytes) return;
        builder.add(chunk);
      }
      if (total == 0 || !_requestStillWanted(request)) return;

      final directory = await _ensureCacheDirectory();
      final file = File('${directory.path}/${_fileNameFor(request.url)}.img');
      await file.writeAsBytes(builder.takeBytes(), flush: false);
      _knownFiles[request.url] = file;
      _lastTouch[request.url] = DateTime.now();
      result = file;

      _downloadsSincePrune++;
      if (_downloadsSincePrune >= _pruneEveryDownloads) {
        _downloadsSincePrune = 0;
        _schedulePrune();
      }
    } catch (_) {
      // El arte nunca debe bloquear catálogo o reproducción.
    } finally {
      if (!request.completer.isCompleted) request.completer.complete(result);
    }
  }

  void _touchFile(String url, File file) {
    final now = DateTime.now();
    final previous = _lastTouch[url];
    if (previous != null && now.difference(previous) < _touchInterval) return;
    _lastTouch[url] = now;
    unawaited(file.setLastModified(now).catchError((_) {}));
  }

  void _schedulePrune() {
    if (_pruneRunning) return;
    _pruneRunning = true;
    unawaited(_pruneDiskCache().whenComplete(() => _pruneRunning = false));
  }

  Future<void> _pruneDiskCache() async {
    try {
      final directory = await _ensureCacheDirectory();
      final entries = <_CachedArtworkEntry>[];
      var totalBytes = 0;

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || entity.path.endsWith('.tmp')) continue;
        try {
          final stat = await entity.stat();
          if (stat.type != FileSystemEntityType.file) continue;
          totalBytes += stat.size;
          entries.add(_CachedArtworkEntry(
            file: entity,
            size: stat.size,
            modified: stat.modified,
          ));
        } catch (_) {}
      }

      if (totalBytes <= _maxDiskCacheBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in entries) {
        if (totalBytes <= _trimDiskCacheToBytes) break;
        try {
          await entry.file.delete();
          totalBytes -= entry.size;
          _knownFiles.removeWhere((_, file) => file.path == entry.file.path);
        } catch (_) {}
      }
    } catch (_) {
      // La poda es mantenimiento; nunca debe afectar la navegación.
    }
  }

  String? _validArtworkUrl(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  String _fileNameFor(String value) {
    var h1 = 0x811c9dc5;
    var h2 = 5381;
    for (final unit in value.codeUnits) {
      h1 = ((h1 ^ unit) * 0x01000193) & 0xffffffff;
      h2 = ((h2 * 33) ^ unit) & 0xffffffff;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
  }
}

class _ArtworkRequest {
  final String url;
  final int generation;
  final bool demandDriven;
  final Completer<File?> completer;

  const _ArtworkRequest({
    required this.url,
    required this.generation,
    required this.demandDriven,
    required this.completer,
  });
}

class _CachedArtworkEntry {
  final File file;
  final int size;
  final DateTime modified;

  const _CachedArtworkEntry({
    required this.file,
    required this.size,
    required this.modified,
  });
}
