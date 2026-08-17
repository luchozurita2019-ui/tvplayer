enum PlaylistSourceType {
  m3u,
  xtream,
  stalker,
}

extension PlaylistSourceTypeLabel on PlaylistSourceType {
  String get label => switch (this) {
        PlaylistSourceType.m3u => 'Playlist M3U/M3U8',
        PlaylistSourceType.xtream => 'Xtream Codes',
        PlaylistSourceType.stalker => 'Portal Stalker',
      };
}
