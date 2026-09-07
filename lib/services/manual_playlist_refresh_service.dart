import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import 'live_epg_service.dart';
import 'section_catalog_service.dart';
import 'xtream_fast_catalog_service.dart';
import 'xtream_live_fast_service.dart';

class ManualPlaylistRefreshService {
  ManualPlaylistRefreshService._();

  static final ManualPlaylistRefreshService instance =
      ManualPlaylistRefreshService._();

  final Map<String, int> _revisions = <String, int>{};
  final Map<String, Future<void>> _pending = <String, Future<void>>{};

  int revisionFor(Playlist playlist) => _revisions[playlist.id] ?? 0;

  Future<void> refresh(Playlist playlist) async {
    final key = '${playlist.id}|${playlist.source.trim()}';
    final existing = _pending[key];
    if (existing != null) return existing;

    final future = _refreshNow(playlist);
    _pending[key] = future;
    try {
      await future;
      _revisions[playlist.id] = (_revisions[playlist.id] ?? 0) + 1;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<void> _refreshNow(Playlist playlist) async {
    if (playlist.sourceType != PlaylistSourceType.xtream) {
      await SectionCatalogService.instance.refreshAll(playlist);
      return;
    }

    LiveEpgService.instance.clearPlaylist(playlist.source);
    XtreamFastCatalogService.instance.invalidateSession(playlist.source);

    var successes = 0;
    Object? lastError;

    try {
      final live = await XtreamLiveFastService.instance.refresh(
        playlist.source,
        forceSessionRefresh: true,
      );
      if (live.channels.isNotEmpty) successes++;
    } catch (error) {
      lastError = error;
    }

    try {
      final movies = await XtreamFastCatalogService.instance.refreshMovies(
        playlist.source,
      );
      if (movies.movies.isNotEmpty) successes++;
    } catch (error) {
      lastError = error;
    }

    try {
      final series = await XtreamFastCatalogService.instance.refreshSeries(
        playlist.source,
      );
      if (series.series.isNotEmpty) successes++;
    } catch (error) {
      lastError = error;
    }

    if (successes == 0) {
      throw Exception(
        'No se pudo actualizar ninguna sección de la lista. ${lastError ?? ''}',
      );
    }
  }
}
