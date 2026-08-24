import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import 'android_media3_texture_player_screen.dart';
import 'tv_full_vod_player_screen.dart';

const bool _androidTvBuild = bool.fromEnvironment('TV_FULL_ANDROID_TV');

/// Router único de reproducción de TV FULL PRO.
///
/// LIVE y VOD no comparten motor ni interfaz. Esto impide que una película
/// vuelva a aparecer dentro del menú de canales o que VOD llegue al Media3 LIVE.
class PlayerScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final androidTv = _androidTvBuild &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;

    if (androidTv && isLiveContent) {
      return AndroidMedia3TexturePlayerScreen(
        playlist: playlist,
        initialIndex: initialIndex,
      );
    }

    return TvFullVodPlayerScreen(
      channel: channel,
      settings: settings,
    );
  }
}
