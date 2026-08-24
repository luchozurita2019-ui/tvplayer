import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import '../services/artwork_cache_service.dart';
import '../services/m3u_fetcher.dart';
import '../services/xtream_http_client.dart';
import 'android_media3_texture_player_screen.dart';
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
    // Al comenzar reproducción, toda navegación de catálogo cede la red.
    // Media3 LIVE y MediaKit VOD usan sus propios clientes, por lo que cancelar
    // Xtream/M3U/artwork no corta el stream que se está abriendo.
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
    final androidTv = _androidTvBuild &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;

    if (androidTv && widget.isLiveContent) {
      return AndroidMedia3TexturePlayerScreen(
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
