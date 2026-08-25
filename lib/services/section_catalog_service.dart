import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import 'catalog_file_store.dart';
import 'm3u_fetcher.dart';
import 'm3u_parser.dart';
import 'tv_local_store.dart';

enum TvSectionKind { live, movies, series }

class SectionCatalogSnapshot {
  final List<Channel> channels;
  final List<String> categories;
  final bool fromCache;

  const SectionCatalogSnapshot({
    required this.channels,
    required this.categories,
    required this.fromCache,
  });
}

class SectionCatalogService {
  SectionCatalogService._();
  static final SectionCatalogService instance = SectionCatalogService._();

  final TvLocalStore _store = TvLocalStore.instance;
  final CatalogFileStore _catalogFiles = CatalogFileStore.instance;
  static const Duration _defaultFreshFor = Duration(minutes: 5);

  final Map<String, Future<Map<TvSectionKind, SectionCatalogSnapshot>>>
      _pending = {};
  final Map<String, DateTime> _lastNetworkRefresh = {};

  Future<SectionCatalogSnapshot?> loadCached(
    Playlist playlist,
    TvSectionKind kind,
  ) async {
    final key = 'm3u_${kind.name}';

    final fileSnapshot = await _catalogFiles.loadSnapshot(playlist.id, key);
    if (fileSnapshot != null) {
      return _decodeSnapshot(fileSnapshot.payload);
    }

    // Migración única desde la arquitectura vieja. La fila SQLite se elimina
    // sólo después de confirmar que el catálogo quedó persistido en archivos.
    final legacy = await _store.loadLegacySnapshot(playlist.id, key);
    final migrated = _decodeSnapshot(legacy);
    if (migrated != null) {
      try {
        await _catalogFiles.saveSnapshot(
          serviceId: playlist.id,
          kind: key,
          categories: migrated.categories,
          items: migrated.channels.map((channel) => channel.toJson()),
        );
        await _store.deleteLegacySnapshot(playlist.id, key);
      } catch (_) {
        // Si la migración falla, se conserva la fila antigua y se sigue usando
        // este snapshot en la sesión actual. Nunca destruimos el último bueno.
      }
    }
    return migrated;
  }

  Future<SectionCatalogSnapshot> loadOrRefresh(
    Playlist playlist,
    TvSectionKind kind, {
    bool forceNetwork = false,
  }) async {
    if (!forceNetwork) {
      final cached = await loadCached(playlist, kind);
      if (cached != null) return cached;
    }
    final all = await _refreshAll(playlist);
    return all[kind] ??
        const SectionCatalogSnapshot(
          channels: [],
          categories: [],
          fromCache: false,
        );
  }

  Future<Map<TvSectionKind, SectionCatalogSnapshot>> refreshAll(
    Playlist playlist,
  ) =>
      _refreshAll(playlist);

  Future<Map<TvSectionKind, SectionCatalogSnapshot>?> refreshIfStale(
    Playlist playlist, {
    Duration freshFor = _defaultFreshFor,
  }) async {
    final key = '${playlist.id}|${playlist.source}';
    final pending = _pending[key];
    if (pending != null) return pending;

    final now = DateTime.now();
    final memory = _lastNetworkRefresh[key];
    if (memory != null && now.difference(memory) < freshFor) return null;

    DateTime? persisted;
    for (final kind in TvSectionKind.values) {
      final snapshotKey = 'm3u_${kind.name}';
      persisted = await _catalogFiles.loadUpdatedAt(playlist.id, snapshotKey);
      persisted ??=
          await _store.loadLegacySnapshotUpdatedAt(playlist.id, snapshotKey);
      if (persisted != null) break;
    }
    if (persisted != null && now.difference(persisted) < freshFor) {
      _lastNetworkRefresh[key] = persisted;
      return null;
    }
    return _refreshAll(playlist);
  }

  Future<Map<TvSectionKind, SectionCatalogSnapshot>> _refreshAll(
    Playlist playlist,
  ) async {
    final key = '${playlist.id}|${playlist.source}';
    final existing = _pending[key];
    if (existing != null) return existing;
    final future = _downloadAndPartition(playlist);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<Map<TvSectionKind, SectionCatalogSnapshot>> _downloadAndPartition(
    Playlist playlist,
  ) async {
    final content = await M3uFetcher.fetch(playlist.source);
    final parsed = await compute(parseM3uInBackground, content);
    if (parsed.isEmpty) {
      throw const FormatException(
        'La lista M3U descargada no contiene entradas válidas.',
      );
    }
    final buckets = <TvSectionKind, List<Channel>>{
      TvSectionKind.live: <Channel>[],
      TvSectionKind.movies: <Channel>[],
      TvSectionKind.series: <Channel>[],
    };
    for (final channel in parsed) {
      buckets[_classify(channel)]!.add(channel);
    }

    final result = <TvSectionKind, SectionCatalogSnapshot>{};
    final writes = <Future<void>>[];

    for (final kind in TvSectionKind.values) {
      final downloaded = buckets[kind]!;
      if (downloaded.isEmpty) {
        final previous = await loadCached(playlist, kind);
        result[kind] = previous ??
            const SectionCatalogSnapshot(
              channels: [],
              categories: [],
              fromCache: false,
            );
        continue;
      }

      final channels = List<Channel>.unmodifiable(downloaded);
      final categories = List<String>.unmodifiable(_categories(channels));
      final snapshot = SectionCatalogSnapshot(
        channels: channels,
        categories: categories,
        fromCache: false,
      );
      result[kind] = snapshot;
      writes.add(
        _catalogFiles.saveSnapshot(
          serviceId: playlist.id,
          kind: 'm3u_${kind.name}',
          categories: categories,
          items: channels.map((channel) => channel.toJson()),
        ),
      );
    }

    // La primera carga sólo termina cuando las secciones no vacías quedaron
    // confirmadas en Application Support. Un refresh vacío conserva la versión
    // anterior y nunca reemplaza el último catálogo bueno.
    await Future.wait(writes);
    _lastNetworkRefresh['${playlist.id}|${playlist.source}'] = DateTime.now();
    return result;
  }

  SectionCatalogSnapshot? _decodeSnapshot(dynamic raw) {
    if (raw is! Map) return null;
    final rawItems = raw['items'];
    final rawCategories = raw['categories'];
    if (rawItems is! List) return null;

    final channels = <Channel>[];
    for (final item in rawItems) {
      if (item is! Map) continue;
      try {
        channels.add(Channel.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {}
    }
    if (channels.isEmpty) return null;

    final categories = rawCategories is List
        ? rawCategories.map((e) => e.toString()).toList(growable: false)
        : _categories(channels);
    return SectionCatalogSnapshot(
      channels: List<Channel>.unmodifiable(channels),
      categories: List<String>.unmodifiable(categories),
      fromCache: true,
    );
  }

  TvSectionKind _classify(Channel channel) {
    final url = channel.url.toLowerCase();
    final uri = Uri.tryParse(channel.url);
    final path = (uri?.path ?? url).toLowerCase();

    // El nombre de la carpeta no decide el tipo. Si el proveedor llama
    // "Series 24/7", "Novelas" o "Cine" a un canal lineal, sigue siendo LIVE.
    if (path.contains('/series/')) return TvSectionKind.series;
    if (path.contains('/movie/')) return TvSectionKind.movies;

    if (_hasVideoFile(path)) return TvSectionKind.movies;
    return TvSectionKind.live;
  }

  List<String> _categories(Iterable<Channel> channels) {
    final seen = <String>{};
    final values = <String>[];
    for (final channel in channels) {
      final group = channel.group?.trim();
      if (group == null || group.isEmpty) continue;
      if (seen.add(group)) values.add(group);
    }
    return values;
  }

  bool _hasVideoFile(String path) => const [
        '.mp4',
        '.mkv',
        '.avi',
        '.mov',
        '.m4v',
        '.webm',
        '.wmv',
        '.flv',
      ].any(path.endsWith);
}
