import 'package:flutter/services.dart';

import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import 'local_provider_json_store.dart';
import 'remote_provider_json_service.dart';
import 'tv_local_store.dart';

/// Descarga la fuente provider.json integrada y la deja lista antes de que
/// IptvProvider restaure sus servicios. Si la red falla, conserva intacta la
/// última copia funcional guardada en el dispositivo.
class RemoteProviderJsonBootstrap {
  RemoteProviderJsonBootstrap._();

  static final instance = RemoteProviderJsonBootstrap._();

  static const playlistId = 'tvf_builtin_provider_json';
  static const playlistName = 'TV FULL · Proveedor';
  static const playlist2Id = 'tvf_builtin_provider_2';
  static const playlist2Name = 'TV Full · Proveedor 2';
  static const playlist2Asset = 'assets/playlists/tvfull_proveedor_2.json';

  Future<void> prepare() async {
    try {
      // HomeScreen ya muestra su vista de inicio durante esta operación. El
      // catálogo del proveedor puede venir desde Archive.org y necesitar más
      // de 12 s en una conexión lenta; no cortamos antes que el propio fetch.
      final payload = await RemoteProviderJsonService.instance.fetch().timeout(
            const Duration(seconds: 35),
          );
      final imported = await LocalProviderJsonStore.instance.importContent(
        playlistId,
        payload.content,
      );

      final store = TvLocalStore.instance;
      final current = await store.loadServices();
      final index = current.indexWhere((item) => item.id == playlistId);
      final playlist = Playlist(
        id: playlistId,
        name: playlistName,
        source: imported.path,
        isRemote: true,
        channels: const [],
        lastUpdated: DateTime.now(),
        sourceType: PlaylistSourceType.localProviderJson,
      );

      final next = List<Playlist>.from(current);
      if (index < 0) {
        next.insert(0, playlist);
      } else {
        final previous = current[index];
        next[index] = playlist.copyWith(
          name: previous.name.trim().isEmpty ? playlistName : previous.name,
        );
      }
      // Lista 2 es independiente y viene dentro de la APK. Si su importación
      // falla, no se toca ni se elimina la Lista 1 ya preparada.
      try {
        final content2 = await rootBundle.loadString(playlist2Asset);
        final imported2 = await LocalProviderJsonStore.instance.importContent(
          playlist2Id,
          content2,
        );
        final index2 = next.indexWhere((item) => item.id == playlist2Id);
        final playlist2 = Playlist(
          id: playlist2Id,
          name: playlist2Name,
          source: imported2.path,
          isRemote: false,
          channels: const [],
          lastUpdated: DateTime.now(),
          sourceType: PlaylistSourceType.localProviderJson,
        );
        if (index2 < 0) {
          next.add(playlist2);
        } else {
          next[index2] = playlist2;
        }
      } catch (_) {
        // La Lista 1 sigue funcionando aunque el asset de Lista 2 falle.
      }
      await store.saveServices(next);
    } catch (_) {
      // La app sigue abriendo incluso si el catálogo remoto o la red fallan.
      // La última copia válida no se elimina.
    }
  }
}
