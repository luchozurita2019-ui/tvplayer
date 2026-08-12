import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../services/content_classifier.dart';
import '../services/xtream_fast_catalog_service.dart';
import '../services/xtream_live_fast_service.dart';
import 'channel_list_screen.dart';

class XtreamLiveScreen extends StatefulWidget {
  final Playlist playlist;

  const XtreamLiveScreen({super.key, required this.playlist});

  @override
  State<XtreamLiveScreen> createState() => _XtreamLiveScreenState();
}

class _XtreamLiveScreenState extends State<XtreamLiveScreen> {
  late Future<Playlist> _future;
  String _progressLabel = 'Cargando información del servidor…';
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastProgressBytes = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Playlist> _load({bool forceNetwork = false}) async {
    final service = XtreamLiveFastService.instance;

    // Flujo normal: terminar LIVE 1/2 + 2/2 antes de entregar la pantalla.
    // Así no dejamos get_live_streams consumiendo ancho de banda mientras el
    // usuario ya intenta reproducir un canal.
    try {
      final fresh = await service.refresh(
        widget.playlist.source,
        forceSessionRefresh: forceNetwork,
        onProgress: _onProgress,
      );
      return _playlistFromChannels(_mergePlaybackChannels(fresh.channels));
    } catch (error) {
      // El catálogo local funciona como respaldo/offline, no como disparador de
      // una actualización pesada escondida detrás de la reproducción.
      final cached = await service.loadCached(widget.playlist.source);
      if (cached != null && cached.channels.isNotEmpty) {
        return _playlistFromChannels(_mergePlaybackChannels(cached.channels));
      }

      // Último fallback: los canales que ya estaban dentro de la M3U original.
      // Son especialmente valiosos porque conservan URL exacta y headers que
      // algunos proveedores necesitan para autorizar determinados canales.
      final fallback = _originalLiveChannels();
      if (fallback.isNotEmpty) return _playlistFromChannels(fallback);
      rethrow;
    }
  }

  List<Channel> _originalLiveChannels() => ContentClassifier.partition(
    widget.playlist.channels,
  ).forKind(IptvContentKind.live);

  /// El API rápido nos da nombres/categorías/logos actuales, pero para PLAY
  /// preferimos la URL exacta de la lista original cuando podemos identificar
  /// el mismo stream. Esto recupera headers, CDN, puerto y variantes de URL que
  /// se perderían al reconstruir /live/user/pass/id.ext manualmente.
  List<Channel> _mergePlaybackChannels(List<Channel> fastChannels) {
    final original = _originalLiveChannels();
    if (original.isEmpty) return List<Channel>.unmodifiable(fastChannels);

    final byStreamId = <String, Channel>{};
    final byName = <String, List<Channel>>{};

    for (final channel in original) {
      final streamId = _numericStreamId(channel.url);
      if (streamId != null) byStreamId.putIfAbsent(streamId, () => channel);
      final key = _normalizeName(channel.name);
      byName.putIfAbsent(key, () => <Channel>[]).add(channel);
    }

    final merged = <Channel>[];
    for (final fast in fastChannels) {
      Channel? compatible;
      final streamId = _numericStreamId(fast.url);
      if (streamId != null) compatible = byStreamId[streamId];

      compatible ??= _bestNameMatch(fast, byName[_normalizeName(fast.name)]);
      if (compatible == null) {
        merged.add(fast);
        continue;
      }

      merged.add(
        Channel(
          name: fast.name,
          url: compatible.url,
          logoUrl: fast.logoUrl ?? compatible.logoUrl,
          group: fast.group ?? compatible.group,
          tvgId: fast.tvgId ?? compatible.tvgId,
          httpUserAgent: compatible.httpUserAgent,
          httpReferrer: compatible.httpReferrer,
          httpHeaders: compatible.httpHeaders,
        ),
      );
    }
    return List<Channel>.unmodifiable(merged);
  }

  Channel? _bestNameMatch(Channel fast, List<Channel>? candidates) {
    if (candidates == null || candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;
    final fastGroup = fast.group?.trim().toLowerCase();
    if (fastGroup != null && fastGroup.isNotEmpty) {
      for (final candidate in candidates) {
        if (candidate.group?.trim().toLowerCase() == fastGroup)
          return candidate;
      }
    }
    return candidates.first;
  }

  String _normalizeName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String? _numericStreamId(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    final path = uri?.path ?? rawUrl;
    if (path.isEmpty) return null;
    final segments = path
        .split('/')
        .where((value) => value.isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;
    var file = segments.last;
    final dot = file.lastIndexOf('.');
    if (dot > 0) file = file.substring(0, dot);
    return RegExp(r'^\d+$').hasMatch(file) ? file : null;
  }

  Playlist _playlistFromChannels(List<Channel> channels) {
    return Playlist(
      id: '${widget.playlist.id}::live',
      name: '${widget.playlist.name} · TV en vivo',
      source: widget.playlist.source,
      isRemote: false,
      channels: List<Channel>.unmodifiable(channels),
      lastUpdated: DateTime.now(),
      sourceType: PlaylistSourceType.xtream,
    );
  }

  void _onProgress(XtreamCatalogProgress progress) {
    if (!mounted) return;
    final now = DateTime.now();
    final bytesDelta = progress.receivedBytes - _lastProgressBytes;
    final elapsed = now.difference(_lastProgressUpdate);
    if (progress.receivedBytes > 0 &&
        bytesDelta < 128 * 1024 &&
        elapsed < const Duration(milliseconds: 180)) {
      return;
    }
    _lastProgressUpdate = now;
    _lastProgressBytes = progress.receivedBytes;
    setState(() => _progressLabel = progress.label);
  }

  void _retry() {
    XtreamFastCatalogService.instance.invalidateSession(widget.playlist.source);
    setState(() {
      _progressLabel = 'Cargando información del servidor…';
      _lastProgressBytes = 0;
      _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      _future = _load(forceNetwork: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Playlist>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TV en vivo',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    widget.playlist.name,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _progressLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          final raw = snapshot.error.toString();
          final message = raw.contains('TimeoutException')
              ? 'El servidor Xtream dejó de enviar datos durante demasiado tiempo. Reintentá la carga de TV en vivo.'
              : raw.replaceFirst('Exception: ', '');
          return Scaffold(
            appBar: AppBar(title: const Text('TV en vivo')),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 50),
                        const SizedBox(height: 14),
                        Text(message, textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return ChannelListScreen(playlist: snapshot.data!);
      },
    );
  }
}
