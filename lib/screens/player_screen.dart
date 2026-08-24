import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import '../providers/iptv_provider.dart';
import '../services/artwork_cache_service.dart';
import '../services/m3u_fetcher.dart';
import '../services/remote_access_guard.dart';
import '../services/xtream_http_client.dart';
import 'android_media3_texture_player_screen.dart';
import 'android_media3_vod_player_screen.dart';
import 'tv_full_vod_player_screen.dart';

const bool _androidTvBuild = bool.fromEnvironment('TV_FULL_ANDROID_TV');

/// Router único de reproducción de TV FULL PRO.
/// LIVE y VOD están aislados y la reproducción siempre tiene prioridad de red.
class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final List<Channel> playlist;
  final int initialIndex;
  final PlaybackSettings settings;
  final bool isLiveContent;

  const PlayerScreen({
    super.key,
    required this.channel,
    required this.playlist,
    required this.initialIndex,
    required this.settings,
    this.isLiveContent = true,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    XtreamHttpClient.cancelBrowsingRequests();
    M3uFetcher.cancelBrowsingRequests();
    ArtworkCacheService.instance.pauseForPlayback();
  }

  @override
  void dispose() {
    ArtworkCacheService.instance.resumeBrowsing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final blocked = remoteAccessBlockMessage(provider);
    if (blocked != null) {
      // Al cambiar a este árbol, Flutter dispone el reproductor activo y corta
      // el stream, pero conserva intactos los snapshots locales.
      return _BlockedPlayback(message: blocked);
    }

    final androidTv = _androidTvBuild &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;

    if (androidTv) {
      if (widget.isLiveContent) {
        return AndroidMedia3TexturePlayerScreen(
          playlist: widget.playlist,
          initialIndex: widget.initialIndex,
        );
      }
      // Android TV usa Media3 también para VOD: evita el cierre nativo observado
      // con MediaKit y mantiene selector de audio/subtítulos.
      return AndroidMedia3VodPlayerScreen(
        playlist: widget.playlist,
        initialIndex: widget.initialIndex,
      );
    }

    return TvFullVodPlayerScreen(
      channel: widget.channel,
      settings: widget.settings,
    );
  }
}

class _BlockedPlayback extends StatelessWidget {
  final String message;
  const _BlockedPlayback({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 48),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Volver'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
