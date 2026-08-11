import 'dart:async';

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

    if (!forceNetwork) {
      final cached = await service.loadCached(widget.playlist.source);
      if (cached != null && cached.channels.isNotEmpty) {
        // Igual que Películas/Series: abrir con el catálogo local y refrescar
        // silenciosamente. No reemplazamos la UI mientras el usuario navega.
        unawaited(service.refresh(widget.playlist.source));
        return _playlistFromChannels(cached.channels);
      }
    }

    try {
      final fresh = await service.refresh(
        widget.playlist.source,
        forceSessionRefresh: forceNetwork,
        onProgress: _onProgress,
      );
      return _playlistFromChannels(fresh.channels);
    } catch (error) {
      // Fallback inmediato al LIVE ya persistido dentro de la playlist. Esto
      // conserva compatibilidad con paneles/clones Xtream que no implementan
      // correctamente get_live_categories/get_live_streams.
      final fallback = ContentClassifier.partition(widget.playlist.channels)
          .forKind(IptvContentKind.live);
      if (fallback.isNotEmpty) return _playlistFromChannels(fallback);
      rethrow;
    }
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
