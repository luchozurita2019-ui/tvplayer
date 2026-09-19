enum PlaylistSourceType { m3u, xtream, stalker, localProviderJson, futbolTotalBridge }

extension PlaylistSourceTypeLabel on PlaylistSourceType {
  String get label => switch (this) {
        PlaylistSourceType.m3u => 'Playlist M3U/M3U8',
        PlaylistSourceType.xtream => 'Xtream Codes',
        PlaylistSourceType.stalker => 'Portal Stalker',
        PlaylistSourceType.localProviderJson => 'provider.json local',
        PlaylistSourceType.futbolTotalBridge => 'Fútbol Total · Puente',
      };
}
