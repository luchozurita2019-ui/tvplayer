import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import 'live_epg_service.dart';
import 'section_catalog_service.dart';
import 'xtream_fast_catalog_service.dart';
import 'xtream_live_fast_service.dart';

class ManualPlaylistRefreshResult {
  final bool liveUpdated;
  final bool moviesUpdated;
  final bool seriesUpdated;

  const ManualPlaylistRefreshResult({
    required this.liveUpdated,
    required this.moviesUpdated,
    required this.seriesUpdated,
  });

  const ManualPlaylistRefreshResult.complete()
      : liveUpdated = true,
        moviesUpdated = true,
        seriesUpdated = true;

  int get updatedSections =>
      (liveUpdated ? 1 : 0) + (moviesUpdated ? 1 : 0) + (seriesUpdated ? 1 : 0);

  bool get isComplete => updatedSections == 3;
  bool get isPartial => updatedSections > 0 && !isComplete;

  List<String> get failedSectionNames => <String>[
        if (!liveUpdated) 'TV en vivo',
        if (!moviesUpdated) 'Películas',
        if (!seriesUpdated) 'Series',
      ];
}

class ManualPlaylistRefreshService {
  ManualPlaylistRefreshService._();

  static final ManualPlaylistRefreshService instance =
      ManualPlaylistRefreshService._();

  final Map<String, int> _revisions = <String, int>{};
  final Map<String, Future<ManualPlaylistRefreshResult>> _pending =
      <String, Future<ManualPlaylistRefreshResult>>{};

  int revisionFor(Playlist playlist) => _revisions[playlist.id] ?? 0;

  Future<ManualPlaylistRefreshResult> refresh(Playlist playlist) async {
    final key = '${playlist.id}|${playlist.source.trim()}';
    final existing = _pending[key];
    if (existing != null) return existing;

    final future = _refreshNow(playlist);
    _pending[key] = future;
    try {
      final result = await future;
      if (result.updatedSections > 0) {
        _revisions[playlist.id] = (_revisions[playlist.id] ?? 0) + 1;
      }
      return result;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<ManualPlaylistRefreshResult> _refreshNow(Playlist playlist) async {
    if (playlist.sourceType != PlaylistSourceType.xtream) {
      await SectionCatalogService.instance.refreshAll(playlist);
      return const ManualPlaylistRefreshResult.complete();
    }

    LiveEpgService.instance.clearPlaylist(playlist.source);
    XtreamFastCatalogService.instance.invalidateSession(playlist.source);

    var liveUpdated = false;
    var moviesUpdated = false;
    var seriesUpdated = false;
    Object? lastError;

    try {
      await XtreamLiveFastService.instance.refresh(
        playlist.source,
        forceSessionRefresh: true,
      );
      liveUpdated = true;
    } catch (error) {
      lastError = error;
    }

    try {
      await XtreamFastCatalogService.instance.refreshMovies(
        playlist.source,
      );
      moviesUpdated = true;
    } catch (error) {
      lastError = error;
    }

    try {
      await XtreamFastCatalogService.instance.refreshSeries(
        playlist.source,
      );
      seriesUpdated = true;
    } catch (error) {
      lastError = error;
    }

    final result = ManualPlaylistRefreshResult(
      liveUpdated: liveUpdated,
      moviesUpdated: moviesUpdated,
      seriesUpdated: seriesUpdated,
    );

    if (result.updatedSections == 0) {
      throw Exception(
        'No se pudo actualizar ninguna sección de la lista. ${lastError ?? ''}',
      );
    }
    return result;
  }
}
