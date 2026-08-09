from pathlib import Path

SERVICE = r'''import 'dart:async';
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
'''

WIDGET = r'''import 'dart:io';

import 'package:flutter/material.dart';

import '../services/artwork_cache_service.dart';

class CachedArtworkImage extends StatefulWidget {
  final String? url;
  final BoxFit fit;
  final Widget fallback;
  final bool allowNetwork;
  final int? cacheWidth;
  final int? cacheHeight;

  const CachedArtworkImage({
    super.key,
    required this.url,
    required this.fit,
    required this.fallback,
    this.allowNetwork = true,
    this.cacheWidth,
    this.cacheHeight,
  });

  @override
  State<CachedArtworkImage> createState() => _CachedArtworkImageState();
}

class _CachedArtworkImageState extends State<CachedArtworkImage> {
  late Future<File?> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant CachedArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.allowNetwork != widget.allowNetwork) {
      _reload();
    }
  }

  void _reload() {
    _future = ArtworkCacheService.instance.resolve(
      widget.url,
      allowNetwork: widget.allowNetwork,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return widget.fallback;
        return Image.file(
          file,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => widget.fallback,
        );
      },
    );
  }
}
'''

Path('lib/services/artwork_cache_service.dart').write_text(SERVICE, encoding='utf-8')
Path('lib/widgets/cached_artwork_image.dart').write_text(WIDGET, encoding='utf-8')


def replace_once(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'{label}: expected text not found in {path}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')

# ChannelTile: use cache service and allow cached-only mode during playback.
replace_once(
    'lib/widgets/channel_tile.dart',
    "import 'package:flutter/material.dart';\nimport '../models/channel.dart';",
    "import 'package:flutter/material.dart';\nimport '../models/channel.dart';\nimport 'cached_artwork_image.dart';",
    'channel tile import',
)
replace_once(
    'lib/widgets/channel_tile.dart',
    "  final VoidCallback onTap;\n\n  const ChannelTile({",
    "  final VoidCallback onTap;\n  final bool allowNetworkArtwork;\n\n  const ChannelTile({",
    'channel tile field',
)
replace_once(
    'lib/widgets/channel_tile.dart',
    "    required this.onFavoriteToggle,\n    required this.onTap,\n  });",
    "    required this.onFavoriteToggle,\n    required this.onTap,\n    this.allowNetworkArtwork = true,\n  });",
    'channel tile constructor',
)
old_logo = """        child: channel.logoUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  channel.logoUrl!,
                  fit: BoxFit.cover,
                  // Si el logo falla o tarda, no bloquea la lista:
                  // cae a un ícono genérico al instante.
                  errorBuilder: (_, __, ___) => const _FallbackIcon(),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const _FallbackIcon();
                  },
                ),
              )
            : const _FallbackIcon(),
"""
new_logo = """        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedArtworkImage(
            url: channel.logoUrl,
            fit: BoxFit.cover,
            cacheWidth: 96,
            allowNetwork: allowNetworkArtwork,
            fallback: const _FallbackIcon(),
          ),
        ),
"""
replace_once('lib/widgets/channel_tile.dart', old_logo, new_logo, 'channel tile logo')

# Player: never start artwork downloads while a stream is active.
replace_once(
    'lib/screens/player_screen.dart',
    "                            onTap: () => _switchToChannel(realIndex),\n                          ),",
    "                            onTap: () => _switchToChannel(realIndex),\n                            allowNetworkArtwork: false,\n                          ),",
    'player cached-only sidebar',
)

# Channel list imports & initial artwork gate.
replace_once(
    'lib/screens/channel_list_screen.dart',
    "import '../providers/iptv_provider.dart';\nimport 'player_screen.dart';",
    "import '../providers/iptv_provider.dart';\nimport '../services/artwork_cache_service.dart';\nimport '../widgets/cached_artwork_image.dart';\nimport 'player_screen.dart';",
    'catalog imports',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "  late Map<String, int> _groupCounts;",
    "  late Map<String, int> _groupCounts;\n  bool _initialArtworkReady = false;",
    'catalog ready field',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "    _rebuildCategoryCache(widget.playlist);\n  }",
    "    _rebuildCategoryCache(widget.playlist);\n    unawaited(_prepareInitialArtwork());\n  }",
    'catalog init warmup',
)
# dart:async required for unawaited
replace_once(
    'lib/screens/channel_list_screen.dart',
    "import 'package:flutter/material.dart';",
    "import 'dart:async';\n\nimport 'package:flutter/material.dart';",
    'catalog async import',
)
insert_after_cache = """  void _rebuildCategoryCache(Playlist playlist) {
    final counts = <String, int>{};
    for (final channel in playlist.channels) {
      final group = channel.group?.trim();
      if (group == null || group.isEmpty) continue;
      counts[group] = (counts[group] ?? 0) + 1;
    }
    final groups = counts.keys.toList()..sort();
    _groups = List.unmodifiable(groups);
    _groupCounts = Map.unmodifiable(counts);
  }
"""
insert_new = insert_after_cache + """
  Future<void> _prepareInitialArtwork() async {
    final limit = _mode.usesPoster ? 12 : 24;
    await ArtworkCacheService.instance.warmSection(
      widget.playlist.channels,
      limit: limit,
    );
    if (!mounted) return;
    setState(() => _initialArtworkReady = true);
  }
"""
replace_once('lib/screens/channel_list_screen.dart', insert_after_cache, insert_new, 'catalog warmup method')
replace_once(
    'lib/screens/channel_list_screen.dart',
    "      body: LayoutBuilder(\n        builder: (context, constraints) {",
    "      body: !_initialArtworkReady\n          ? const Center(\n              child: Column(\n                mainAxisSize: MainAxisSize.min,\n                children: [\n                  CircularProgressIndicator(),\n                  SizedBox(height: 14),\n                  Text('Preparando logos y portadas…'),\n                ],\n              ),\n            )\n          : LayoutBuilder(\n              builder: (context, constraints) {",
    'catalog loading gate start',
)
# Close indentation remains syntactically same: only ternary prefix changed; LayoutBuilder closing already works.
replace_once(
    'lib/screens/channel_list_screen.dart',
    "          cacheExtent: 700,",
    "          cacheExtent: 80,",
    'catalog cache extent',
)
old_art = """    return Image.network(
      logo,
      fit: fit,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => _ArtworkFallback(mode: mode),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress.expectedTotalBytes == null
                  ? null
                  : progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!,
            ),
          ),
        );
      },
    );
"""
new_art = """    return CachedArtworkImage(
      url: logo,
      fit: fit,
      cacheWidth: mode.usesPoster ? 420 : 300,
      fallback: _ArtworkFallback(mode: mode),
    );
"""
replace_once('lib/screens/channel_list_screen.dart', old_art, new_art, 'catalog artwork')
# Make channel open async + pause/resume artwork network.
old_open_sig = """  void _openChannel(
    BuildContext context,
    List<Channel> channels,
    Channel channel,
    IptvProvider provider,
  ) {
"""
new_open_sig = """  Future<void> _openChannel(
    BuildContext context,
    List<Channel> channels,
    Channel channel,
    IptvProvider provider,
  ) async {
"""
replace_once('lib/screens/channel_list_screen.dart', old_open_sig, new_open_sig, 'catalog open async')
old_push = """    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          channel: channel,
          playlist: channels,
          initialIndex: index,
          settings: provider.playbackSettings,
          isLiveContent:
              _mode == _CatalogMode.live || _mode == _CatalogMode.radios,
        ),
      ),
    );
"""
new_push = """    ArtworkCacheService.instance.pauseForPlayback();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          channel: channel,
          playlist: channels,
          initialIndex: index,
          settings: provider.playbackSettings,
          isLiveContent:
              _mode == _CatalogMode.live || _mode == _CatalogMode.radios,
        ),
      ),
    );
    ArtworkCacheService.instance.resumeBrowsing();
"""
replace_once('lib/screens/channel_list_screen.dart', old_push, new_push, 'catalog player pause/resume')

# Home: warm initial artwork before opening provider.
replace_once(
    'lib/screens/home_screen.dart',
    "import '../providers/iptv_provider.dart';\nimport 'add_source_screen.dart';",
    "import '../providers/iptv_provider.dart';\nimport '../services/artwork_cache_service.dart';\nimport 'add_source_screen.dart';",
    'home artwork import',
)
old_tap = """      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SourceContentScreen(playlist: playlist),
          ),
        ),
"""
new_tap = """      child: InkWell(
        onTap: () => _openPlaylist(context),
"""
replace_once('lib/screens/home_screen.dart', old_tap, new_tap, 'home playlist tap')
needle = """  @override
  Widget build(BuildContext context) {
    final provider = context.read<IptvProvider>();
"""
method = """  Future<void> _openPlaylist(BuildContext context) async {
    final navigator = Navigator.of(context);
    final cache = ArtworkCacheService.instance;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Preparando canales, logos y portadas…')),
          ],
        ),
      ),
    );

    try {
      await cache.warmProvider(playlist);
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => SourceContentScreen(playlist: playlist),
      ),
    );
  }

""" + needle
replace_once('lib/screens/home_screen.dart', needle, method, 'home warmup method')

print('Artwork cache experiment applied')
