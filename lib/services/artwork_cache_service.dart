import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'device_performance_service.dart';

/// Caché de artwork de TV FULL PRO.
///
/// Sólo descarga imágenes retenidas por widgets visibles. El disco conserva un
/// LRU pequeño entre secciones/sesiones para evitar volver a bajar el mismo logo
/// o poster cada vez que el usuario navega.
class ArtworkCacheService {
  ArtworkCacheService._();
  static final ArtworkCacheService instance = ArtworkCacheService._();

  static const int _maxArtworkBytes = 3 * 1024 * 1024;

  int get _maxConcurrent =>
      DevicePerformanceService.instance.lowRam ? 2 : 3;
  int get _maxCacheBytes => DevicePerformanceService.instance.lowRam
      ? 40 * 1024 * 1024
      : 64 * 1024 * 1024;
  int get _trimToBytes => DevicePerformanceService.instance.lowRam
      ? 30 * 1024 * 1024
      : 48 * 1024 * 1024;
  static const Duration _connectTimeout = Duration(seconds: 7);
  static const Duration _chunkTimeout = Duration(seconds: 6);
  static const String _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  final Queue<_ArtworkRequest> _queue = Queue<_ArtworkRequest>();
  final Map<String, Future<File?>> _inFlight = {};
  final Map<String, int> _interest = {};
  final Map<String, File> _known = {};

  Directory? _directory;
  Future<Directory>? _directoryFuture;
  http.Client? _client;
  int _generation = 0;
  int _active = 0;
  int _downloads = 0;
  bool _pausedForPlayback = false;
  bool _pruning = false;

  bool get pausedForPlayback => _pausedForPlayback;

  Future<void> switchProvider(String providerId) async {
    await DevicePerformanceService.instance.init();
    _pausedForPlayback = false;
    _client ??= http.Client();
    await _ensureDirectory();
  }

  Future<void> warmProvider(dynamic playlist) async {}
  Future<void> warmSection(
    dynamic channels, {
    required int limit,
    Duration maxWait = const Duration(seconds: 1),
  }) async {}
  Future<void> warmUrls(
    Iterable<String> urls, {
    Duration maxWait = const Duration(seconds: 1),
  }) async {}

  Future<void> clearBrowsingSession() async {
    _cancelPendingNetwork();
    _interest.clear();
    _pausedForPlayback = false;
    _client ??= http.Client();
  }

  void retain(String? rawUrl) {
    final url = _validUrl(rawUrl);
    if (url == null) return;
    _interest[url] = (_interest[url] ?? 0) + 1;
  }

  void release(String? rawUrl) {
    final url = _validUrl(rawUrl);
    if (url == null) return;
    final count = _interest[url] ?? 0;
    if (count <= 1) {
      _interest.remove(url);
      _dropQueuedIfUnused(url);
    } else {
      _interest[url] = count - 1;
    }
  }

  void pauseForPlayback() {
    if (_pausedForPlayback) return;
    _pausedForPlayback = true;
    _cancelPendingNetwork();
  }

  void resumeBrowsing() {
    if (!_pausedForPlayback) return;
    _pausedForPlayback = false;
    _client ??= http.Client();
    _drain();
  }

  Future<File?> resolve(
    String? rawUrl, {
    bool allowNetwork = true,
    bool demandDriven = false,
  }) async {
    final url = _validUrl(rawUrl);
    if (url == null) return null;
    final known = _known[url];
    if (known != null && await known.exists()) {
      return known;
    }

    final directory = await _ensureDirectory();
    final file = File('${directory.path}/${_fileName(url)}.img');
    if (await file.exists()) {
      _known[url] = file;
      return file;
    }
    if (!allowNetwork || _pausedForPlayback) return null;
    if (demandDriven && (_interest[url] ?? 0) <= 0) return null;

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
    _inFlight[url] = completer.future;
    completer.future.whenComplete(() {
      if (identical(_inFlight[url], completer.future)) _inFlight.remove(url);
    });
    _drain();
    return completer.future;
  }

  Future<Directory> _ensureDirectory() {
    if (_directory != null) return Future.value(_directory!);
    if (_directoryFuture != null) return _directoryFuture!;
    final future = () async {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/tv_full_pro_artwork');
      if (!await directory.exists()) await directory.create(recursive: true);
      _directory = directory;
      return directory;
    }();
    _directoryFuture = future;
    future.whenComplete(() => _directoryFuture = null);
    return future;
  }

  bool _wanted(_ArtworkRequest request) {
    if (request.generation != _generation || _pausedForPlayback) return false;
    if (request.demandDriven && (_interest[request.url] ?? 0) <= 0)
      return false;
    return true;
  }

  void _drain() {
    if (_pausedForPlayback) return;
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      if (!_wanted(request)) {
        if (!request.completer.isCompleted) request.completer.complete(null);
        continue;
      }
      _active++;
      unawaited(
        _download(request).whenComplete(() {
          _active--;
          _drain();
        }),
      );
    }
  }

  Future<void> _download(_ArtworkRequest request) async {
    File? result;
    try {
      if (!_wanted(request)) return;
      final client = _client ??= http.Client();
      final httpRequest = http.Request('GET', Uri.parse(request.url))
        ..headers.addAll(const {
          'User-Agent': _userAgent,
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        });
      final response = await client.send(httpRequest).timeout(_connectTimeout);
      if (!_wanted(request)) return;
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      if ((response.contentLength ?? 0) > _maxArtworkBytes) return;

      final bytes = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.stream.timeout(_chunkTimeout)) {
        if (!_wanted(request)) return;
        total += chunk.length;
        if (total > _maxArtworkBytes) return;
        bytes.add(chunk);
      }
      if (total == 0 || !_wanted(request)) return;
      final directory = await _ensureDirectory();
      final file = File('${directory.path}/${_fileName(request.url)}.img');
      await file.writeAsBytes(bytes.takeBytes(), flush: false);
      _known[request.url] = file;
      result = file;
      _downloads++;
      if (_downloads % 20 == 0) _schedulePrune();
    } catch (_) {
      // Artwork is never critical for navigation or playback.
    } finally {
      if (!request.completer.isCompleted) request.completer.complete(result);
    }
  }

  void _cancelPendingNetwork() {
    _generation++;
    _client?.close();
    _client = null;
    while (_queue.isNotEmpty) {
      final item = _queue.removeFirst();
      if (!item.completer.isCompleted) item.completer.complete(null);
    }
  }

  void _dropQueuedIfUnused(String url) {
    if (_queue.isEmpty) return;
    final items = _queue.toList(growable: false);
    _queue.clear();
    for (final item in items) {
      if (item.url == url && item.demandDriven && (_interest[url] ?? 0) <= 0) {
        if (!item.completer.isCompleted) item.completer.complete(null);
      } else {
        _queue.add(item);
      }
    }
  }

  void _schedulePrune() {
    if (_pruning) return;
    _pruning = true;
    unawaited(_prune().whenComplete(() => _pruning = false));
  }

  Future<void> _prune() async {
    try {
      final directory = await _ensureDirectory();
      final entries = <_CacheEntry>[];
      var total = 0;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        total += stat.size;
        entries.add(_CacheEntry(entity, stat.size, stat.modified));
      }
      if (total <= _maxCacheBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in entries) {
        if (total <= _trimToBytes) break;
        try {
          await entry.file.delete();
          total -= entry.size;
          _known.removeWhere((_, file) => file.path == entry.file.path);
        } catch (_) {}
      }
    } catch (_) {}
  }

  String? _validUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) return null;
    return uri.toString();
  }

  String _fileName(String value) {
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

class _CacheEntry {
  final File file;
  final int size;
  final DateTime modified;
  const _CacheEntry(this.file, this.size, this.modified);
}
