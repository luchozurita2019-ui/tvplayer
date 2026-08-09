import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import 'content_classifier.dart';

/// Cache de arte orientado a IPTV.
///
/// Objetivos:
/// - precargar solo el primer bloque de logos/posters antes de mostrar la grilla;
/// - limitar la concurrencia para no competir con el stream;
/// - guardar imágenes en disco para no descargarlas otra vez;
/// - cancelar la cola del proveedor anterior al cambiar de lista;
/// - detener toda descarga de arte mientras hay reproducción activa.
class ArtworkCacheService {
  ArtworkCacheService._();

  static final ArtworkCacheService instance = ArtworkCacheService._();

  static const int _maxConcurrent = 3;
  static const int _maxArtworkBytes = 3 * 1024 * 1024;
  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _chunkTimeout = Duration(seconds: 6);
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  final Queue<_ArtworkRequest> _queue = Queue<_ArtworkRequest>();
  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};
  final Map<String, File> _knownFiles = <String, File>{};

  Directory? _cacheDirectory;
  http.Client? _client;
  String? _providerId;
  int _generation = 0;
  int _active = 0;
  bool _pausedForPlayback = false;

  bool get pausedForPlayback => _pausedForPlayback;

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
  }

  Future<void> warmProvider(Playlist playlist) async {
    await switchProvider(playlist.id);

    final buckets = ContentClassifier.partition(playlist.channels);
    final urls = <String>[];
    final seen = <String>{};

    void addFrom(List<Channel> channels, int limit) {
      var added = 0;
      for (final channel in channels) {
        final url = _validArtworkUrl(channel.logoUrl);
        if (url == null || !seen.add(url)) continue;
        urls.add(url);
        added++;
        if (added >= limit) break;
      }
    }

    // TV en vivo prioriza más logos porque son pequeños y son la forma más
    // rápida de reconocer un canal. Posters VOD se precargan en un bloque menor.
    addFrom(buckets.forKind(IptvContentKind.live), 20);
    addFrom(buckets.forKind(IptvContentKind.movies), 5);
    addFrom(buckets.forKind(IptvContentKind.series), 5);
    addFrom(buckets.forKind(IptvContentKind.radios), 4);

    await warmUrls(urls, maxWait: const Duration(milliseconds: 2400));
  }

  Future<void> warmSection(
    List<Channel> channels, {
    required int limit,
    Duration maxWait = const Duration(milliseconds: 1800),
  }) async {
    final urls = <String>[];
    final seen = <String>{};
    for (final channel in channels) {
      final url = _validArtworkUrl(channel.logoUrl);
      if (url == null || !seen.add(url)) continue;
      urls.add(url);
      if (urls.length >= limit) break;
    }
    await warmUrls(urls, maxWait: maxWait);
  }

  Future<void> warmUrls(
    Iterable<String> urls, {
    Duration maxWait = const Duration(seconds: 2),
  }) async {
    if (_pausedForPlayback) return;
    final futures = urls
        .map((url) => resolve(url, allowNetwork: true))
        .toList(growable: false);
    if (futures.isEmpty) return;

    await Future.any<void>([
      Future.wait(futures).then((_) {}),
      Future<void>.delayed(maxWait),
    ]);
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
  }) async {
    final url = _validArtworkUrl(rawUrl);
    if (url == null) return null;

    final known = _knownFiles[url];
    if (known != null && await known.exists()) return known;

    final directory = await _ensureCacheDirectory();
    final file = File('${directory.path}/${_fileNameFor(url)}.img');
    if (await file.exists()) {
      _knownFiles[url] = file;
      return file;
    }

    if (!allowNetwork || _pausedForPlayback) return null;

    final existing = _inFlight[url];
    if (existing != null) return existing;

    final completer = Completer<File?>();
    final request = _ArtworkRequest(
      url: url,
      generation: _generation,
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
      if (request.generation != _generation) {
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
      if (_pausedForPlayback || request.generation != _generation) return;
      final client = _client ??= http.Client();
      final httpRequest = http.Request('GET', Uri.parse(request.url))
        ..headers.addAll(const {
          'User-Agent': _userAgent,
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        });
      final response = await client.send(httpRequest).timeout(_connectTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final expected = response.contentLength;
      if (expected != null && expected > _maxArtworkBytes) return;

      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.stream.timeout(_chunkTimeout)) {
        if (_pausedForPlayback || request.generation != _generation) return;
        total += chunk.length;
        if (total > _maxArtworkBytes) return;
        builder.add(chunk);
      }
      if (total == 0 || request.generation != _generation) return;

      final directory = await _ensureCacheDirectory();
      final file = File('${directory.path}/${_fileNameFor(request.url)}.img');
      await file.writeAsBytes(builder.takeBytes(), flush: false);
      _knownFiles[request.url] = file;
      result = file;
    } catch (_) {
      // El arte nunca debe bloquear catálogo o reproducción.
    } finally {
      if (!request.completer.isCompleted) request.completer.complete(result);
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
  final Completer<File?> completer;

  const _ArtworkRequest({
    required this.url,
    required this.generation,
    required this.completer,
  });
}
