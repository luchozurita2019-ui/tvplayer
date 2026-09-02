import 'dart:convert';
import 'dart:math' as math;

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

  /// Una descarga M3U por lista. El Future sólo representa descarga + escritura
  /// a disco; cada pantalla materializa después únicamente su sección.
  final Map<String, Future<void>> _pending = <String, Future<void>>{};
  final Map<String, DateTime> _lastNetworkRefresh = <String, DateTime>{};
  final Map<String, TvSectionKind> _lastRequestedKind =
      <String, TvSectionKind>{};

  /// LRU global para todas las listas M3U, no un límite independiente por lista.
  final Map<String, SectionCatalogSnapshot> _memory =
      <String, SectionCatalogSnapshot>{};
  final Map<String, int> _memoryWeights = <String, int>{};
  int _memoryBytes = 0;

  Future<SectionCatalogSnapshot?> loadCached(
    Playlist playlist,
    TvSectionKind kind,
  ) async {
    _lastRequestedKind[playlist.id] = kind;
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
    _lastRequestedKind[playlist.id] = kind;
    if (!forceNetwork) {
      final cached = await loadCached(playlist, kind);
      if (cached != null) return cached;
    }

    await _refreshToDisk(playlist);
    final fresh = await loadCached(playlist, kind);
    return fresh ??
        const SectionCatalogSnapshot(
          channels: [],
          categories: [],
          fromCache: false,
        );
  }

  Future<Map<TvSectionKind, SectionCatalogSnapshot>> refreshAll(
    Playlist playlist,
  ) async {
    await _refreshToDisk(playlist);
    final result = <TvSectionKind, SectionCatalogSnapshot>{};
    for (final kind in TvSectionKind.values) {
      final snapshot = await loadCached(playlist, kind);
      result[kind] = snapshot ??
          const SectionCatalogSnapshot(
            channels: [],
            categories: [],
            fromCache: false,
          );
    }
    return result;
  }

  Future<Map<TvSectionKind, SectionCatalogSnapshot>?> refreshIfStale(
    Playlist playlist, {
    Duration freshFor = _defaultFreshFor,
    TvSectionKind? kind,
  }) async {
    final targetKind = kind ?? _lastRequestedKind[playlist.id];
    final key = '${playlist.id}|${playlist.source}';
    final pending = _pending[key];
    if (pending != null) {
      await pending;
      return _loadRefreshResult(playlist, targetKind);
    }

    final now = DateTime.now();
    final memory = _lastNetworkRefresh[key];
    if (memory != null && now.difference(memory) < freshFor) return null;

    DateTime? persisted;
    for (final sectionKind in TvSectionKind.values) {
      final snapshotKey = 'm3u_${sectionKind.name}';
      persisted = await _catalogFiles.loadUpdatedAt(playlist.id, snapshotKey);
      persisted ??=
          await _store.loadLegacySnapshotUpdatedAt(playlist.id, snapshotKey);
      if (persisted != null) break;
    }
    if (persisted != null && now.difference(persisted) < freshFor) {
      _lastNetworkRefresh[key] = persisted;
      return null;
    }

    await _refreshToDisk(playlist);
    return _loadRefreshResult(playlist, targetKind);
  }

  Future<Map<TvSectionKind, SectionCatalogSnapshot>> _loadRefreshResult(
    Playlist playlist,
    TvSectionKind? targetKind,
  ) async {
    if (targetKind != null) {
      final snapshot = await loadCached(playlist, targetKind);
      if (snapshot == null) return <TvSectionKind, SectionCatalogSnapshot>{};
      return <TvSectionKind, SectionCatalogSnapshot>{targetKind: snapshot};
    }

    final result = <TvSectionKind, SectionCatalogSnapshot>{};
    for (final sectionKind in TvSectionKind.values) {
      final snapshot = await loadCached(playlist, sectionKind);
      if (snapshot != null) result[sectionKind] = snapshot;
    }
    return result;
  }

  Future<void> _refreshToDisk(Playlist playlist) async {
    final key = '${playlist.id}|${playlist.source}';
    final existing = _pending[key];
    if (existing != null) return existing;

    final future = _downloadAndPartitionToDisk(playlist);
    _pending[key] = future;
    try {
      await future;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  /// Descarga una M3U una sola vez y escribe LIVE/Películas/Series directamente
  /// en generaciones temporales independientes. No se crean tres listas de
  /// Channel en RAM: sólo viven el parser incremental y las categorías únicas.
  Future<void> _downloadAndPartitionToDisk(Playlist playlist) async {
    final parser = M3uLineParser();
    final writers = <TvSectionKind, CatalogFileWriter>{};
    final categorySets = <TvSectionKind, Set<String>>{
      for (final kind in TvSectionKind.values) kind: <String>{},
    };
    final categories = <TvSectionKind, List<String>>{
      for (final kind in TvSectionKind.values) kind: <String>[],
    };

    for (final kind in TvSectionKind.values) {
      writers[kind] = await _catalogFiles.beginSnapshot(
        serviceId: playlist.id,
        kind: 'm3u_${kind.name}',
      );
    }

    var parsedCount = 0;
    try {
      await for (final line in M3uFetcher.fetchLines(playlist.source)) {
        final channel = parser.addLine(line);
        if (channel == null) continue;
        parsedCount++;

        final kind = _classify(channel);
        writers[kind]!.add(channel.toJson());
        final group = channel.group?.trim();
        if (group != null &&
            group.isNotEmpty &&
            categorySets[kind]!.add(group)) {
          categories[kind]!.add(group);
        }
      }

      if (parsedCount == 0) {
        throw const FormatException(
          'La lista M3U descargada no contiene entradas válidas.',
        );
      }

      for (final kind in TvSectionKind.values) {
        final writer = writers[kind]!;
        if (writer.count == 0) {
          // Conservamos la última generación funcional de una sección si una
          // actualización válida no trae entradas para ella.
          await writer.abort();
          continue;
        }
        await writer.commit(categories: categories[kind]!);
      }

      _lastNetworkRefresh['${playlist.id}|${playlist.source}'] = DateTime.now();
    } catch (_) {
      for (final writer in writers.values) {
        await writer.abort();
      }
      rethrow;
    }
  }

  void _remember(String key, SectionCatalogSnapshot snapshot) {
    _forget(key);
    _memory[key] = snapshot;
    final weight = _estimateSnapshotBytes(snapshot);
    _memoryWeights[key] = weight;
    _memoryBytes += weight;

    final profile = DevicePerformanceService.instance;
    final maxSections = profile.lowRam ? 1 : 3;
    final budget = _memoryBudgetBytes(profile);

    while (_memory.length > 1 &&
        (_memory.length > maxSections || _memoryBytes > budget)) {
      _forget(_memory.keys.first);
    }
  }

  void _forget(String key) {
    _memory.remove(key);
    final weight = _memoryWeights.remove(key);
    if (weight != null) _memoryBytes = math.max(0, _memoryBytes - weight);
  }

  int _memoryBudgetBytes(DevicePerformanceService profile) {
    const mb = 1024 * 1024;
    final memoryClass = profile.memoryClassMb;
    if (profile.lowRam) {
      final calculated = memoryClass > 0 ? memoryClass * mb ~/ 8 : 12 * mb;
      return math.max(8 * mb, math.min(16 * mb, calculated));
    }
    final calculated = memoryClass > 0 ? memoryClass * mb ~/ 8 : 32 * mb;
    return math.max(24 * mb, math.min(48 * mb, calculated));
  }

  int _estimateSnapshotBytes(SectionCatalogSnapshot snapshot) {
    var bytes = 256;
    for (final category in snapshot.categories) {
      bytes += 32 + _stringBytes(category);
    }
    for (final channel in snapshot.channels) {
      bytes += 176;
      bytes += _stringBytes(channel.name);
      bytes += _stringBytes(channel.url);
      bytes += _stringBytes(channel.logoUrl);
      bytes += _stringBytes(channel.group);
      bytes += _stringBytes(channel.tvgId);
      bytes += _stringBytes(channel.httpUserAgent);
      bytes += _stringBytes(channel.httpReferrer);
      final headers = channel.httpHeaders;
      if (headers != null) {
        bytes += 48;
        for (final entry in headers.entries) {
          bytes += 40 + _stringBytes(entry.key) + _stringBytes(entry.value);
        }
      }
    }
    return bytes;
  }

  int _stringBytes(String? value) => value == null ? 0 : value.length * 2;

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
