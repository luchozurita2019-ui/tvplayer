import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
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
  final Map<String, Future<Map<TvSectionKind, SectionCatalogSnapshot>>> _pending = {};

  Future<SectionCatalogSnapshot?> loadCached(
    Playlist playlist,
    TvSectionKind kind,
  ) async {
    final raw = await _store.loadSnapshot(playlist.id, 'm3u_${kind.name}');
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
      channels: List.unmodifiable(channels),
      categories: List.unmodifiable(categories),
      fromCache: true,
    );
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
    return all[kind] ?? const SectionCatalogSnapshot(
      channels: [],
      categories: [],
      fromCache: false,
    );
  }

  Future<Map<TvSectionKind, SectionCatalogSnapshot>> refreshAll(
    Playlist playlist,
  ) => _refreshAll(playlist, force: true);

  Future<Map<TvSectionKind, SectionCatalogSnapshot>> _refreshAll(
    Playlist playlist, {
    bool force = false,
  }) async {
    final key = '${playlist.id}|${playlist.source}';
    if (!force) {
      final existing = _pending[key];
      if (existing != null) return existing;
    }
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
    final buckets = <TvSectionKind, List<Channel>>{
      TvSectionKind.live: <Channel>[],
      TvSectionKind.movies: <Channel>[],
      TvSectionKind.series: <Channel>[],
    };
    for (final channel in parsed) {
      buckets[_classify(channel)]!.add(channel);
    }

    final result = <TvSectionKind, SectionCatalogSnapshot>{};
    for (final kind in TvSectionKind.values) {
      final channels = List<Channel>.unmodifiable(buckets[kind]!);
      final categories = List<String>.unmodifiable(_categories(channels));
      final snapshot = SectionCatalogSnapshot(
        channels: channels,
        categories: categories,
        fromCache: false,
      );
      result[kind] = snapshot;
      unawaited(
        _store.saveSnapshot(
          playlist.id,
          'm3u_${kind.name}',
          {
            'categories': categories,
            'items': channels.map((e) => e.toJson()).toList(growable: false),
          },
        ),
      );
    }
    return result;
  }

  TvSectionKind _classify(Channel channel) {
    final url = channel.url.toLowerCase();
    final uri = Uri.tryParse(channel.url);
    final path = (uri?.path ?? url).toLowerCase();
    final group = _normalize(channel.group ?? '');

    if (path.contains('/series/')) return TvSectionKind.series;
    if (path.contains('/movie/')) return TvSectionKind.movies;

    // En M3U el group-title es estructura explícita del proveedor. Hot Player
    // conserva esa estructura; TV FULL PRO la respeta en vez de forzar .ts=LIVE.
    if (_containsAny(group, const [
      'series', 'serie', 'temporada', 'episodios', 'episodio', 'novelas',
    ])) {
      return TvSectionKind.series;
    }
    if (_containsAny(group, const [
      'peliculas', 'pelicula', 'movies', 'movie', 'vod', 'cine', 'films', 'film',
    ])) {
      return TvSectionKind.movies;
    }

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
        '.mp4', '.mkv', '.avi', '.mov', '.m4v', '.webm', '.wmv', '.flv',
      ].any(path.endsWith);

  bool _containsAny(String value, List<String> terms) {
    for (final term in terms) {
      if (value.contains(term)) return true;
    }
    return false;
  }

  String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}
