import 'dart:convert';

import '../models/channel.dart';
import '../models/playlist.dart';
import 'catalog_file_store.dart';
import 'content_classifier.dart';
import 'device_performance_service.dart';
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
  final Map<String, SectionCatalogSnapshot> _memory =
      <String, SectionCatalogSnapshot>{};

  Future<SectionCatalogSnapshot?> loadCached(
    Playlist playlist,
    TvSectionKind kind,
  ) async {
    final key = 'm3u_${kind.name}';
    final memoryKey = '${playlist.id}|$key';
    final memory = _memory.remove(memoryKey);
    if (memory != null) {
      _memory[memoryKey] = memory;
      return memory;
    }

    final fileSource = await _catalogFiles.loadSource(playlist.id, key);
    if (fileSource != null) {
      final decoded = await _decodeFileSource(fileSource);
      if (decoded != null) {
        _remember(memoryKey, decoded);
        return decoded;
      }
    }

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
      } catch (_) {}
    }
    if (migrated != null) _remember(memoryKey, migrated);
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
    final parser = M3uLineParser();
    var parsedCount = 0;
    final buckets = <TvSectionKind, List<Channel>>{
      TvSectionKind.live: <Channel>[],
      TvSectionKind.movies: <Channel>[],
      TvSectionKind.series: <Channel>[],
    };
    await for (final line in M3uFetcher.fetchLines(playlist.source)) {
      final channel = parser.addLine(line);
      if (channel == null) continue;
      parsedCount++;
      buckets[_classify(channel)]!.add(channel);
    }
    if (parsedCount == 0) {
      throw const FormatException(
        'La lista M3U descargada no contiene entradas válidas.',
      );
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
      _remember('${playlist.id}|m3u_${kind.name}', snapshot);
      writes.add(
        _catalogFiles.saveSnapshot(
          serviceId: playlist.id,
          kind: 'm3u_${kind.name}',
          categories: categories,
          items: channels.map((channel) => channel.toJson()),
        ),
      );
    }

    await Future.wait(writes);
    _lastNetworkRefresh['${playlist.id}|${playlist.source}'] = DateTime.now();
    return result;
  }

  void _remember(String key, SectionCatalogSnapshot snapshot) {
    _memory.remove(key);
    _memory[key] = snapshot;
    final limit = DevicePerformanceService.instance.lowRam ? 1 : 3;
    while (_memory.length > limit) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<SectionCatalogSnapshot?> _decodeFileSource(
    CatalogFileSource source,
  ) async {
    final channels = <Channel>[];
    try {
      final lines = source.itemsFile
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        final value = line.trim();
        if (value.isEmpty) continue;
        try {
          final decoded = jsonDecode(value);
          if (decoded is! Map) continue;
          channels.add(Channel.fromJson(Map<String, dynamic>.from(decoded)));
        } catch (_) {}
      }
    } catch (_) {
      return null;
    }
    if (channels.isEmpty) return null;
    return SectionCatalogSnapshot(
      channels: List<Channel>.unmodifiable(channels),
      categories: List<String>.unmodifiable(
        source.categories.isEmpty ? _categories(channels) : source.categories,
      ),
      fromCache: true,
    );
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
    return switch (ContentClassifier.classify(channel)) {
      IptvContentKind.movies => TvSectionKind.movies,
      IptvContentKind.series => TvSectionKind.series,
      IptvContentKind.live => TvSectionKind.live,
      IptvContentKind.radios => TvSectionKind.live,
    };
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
}
