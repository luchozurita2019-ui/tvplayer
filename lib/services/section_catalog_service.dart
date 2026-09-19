import 'dart:convert';
import 'dart:math' as math;

import '../models/channel.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import 'catalog_file_store.dart';
import 'content_classifier.dart';
import 'device_performance_service.dart';
import 'futbol_total_catalog_service.dart';
import 'futbol_total_endpoints.dart';
import 'futbol_total_flow_catalog_parser.dart';
import 'futbol_total_manifest_parser.dart';
import 'm3u_fetcher.dart';
import 'm3u_parser.dart';
import 'local_provider_json_store.dart';
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
    if (playlist.sourceType == PlaylistSourceType.localProviderJson) {
      return _loadLocalProviderJson(playlist, kind);
    }
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
        if (playlist.sourceType == PlaylistSourceType.futbolTotal &&
            (decoded.channels.any(
                  (channel) => (channel.catalogSource ?? '').trim().isEmpty,
                ) ||
                decoded.channels.any(_needsFutbolTotalPlaybackUpgrade))) {
          await _catalogFiles.clearSection(playlist.id, key);
          _forget(memoryKey);
        } else {
          _remember(memoryKey, decoded);
          return decoded;
        }
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
      result[kind] =
          snapshot ??
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
    // Esta fuente es una copia importada localmente, sin actualización de red.
    if (playlist.sourceType == PlaylistSourceType.localProviderJson)
      return null;
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
      persisted ??= await _store.loadLegacySnapshotUpdatedAt(
        playlist.id,
        snapshotKey,
      );
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
    if (playlist.sourceType == PlaylistSourceType.localProviderJson) {
      await _loadLocalProviderJson(playlist, TvSectionKind.live, reload: true);
      return;
    }
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

  void invalidateLocalProviderJson(String playlistId) {
    _forget('$playlistId|provider_json_live');
  }

  Future<SectionCatalogSnapshot> _loadLocalProviderJson(
    Playlist playlist,
    TvSectionKind kind, {
    bool reload = false,
  }) async {
    // HLS/DASH describen el transporte. El formato samples contiene canales
    // en vivo, no una clasificación de películas o episodios.
    if (kind != TvSectionKind.live) {
      return const SectionCatalogSnapshot(
        channels: [],
        categories: [],
        fromCache: true,
      );
    }
    final memoryKey = playlist.id + '|provider_json_live';
    if (!reload) {
      final cached = _memory.remove(memoryKey);
      if (cached != null) {
        _memory[memoryKey] = cached;
        return cached;
      }
    }
    final catalog = await LocalProviderJsonStore.instance.load(playlist.id);
    final snapshot = SectionCatalogSnapshot(
      channels: catalog.channels,
      categories: catalog.categories,
      fromCache: !reload,
    );
    _remember(memoryKey, snapshot);
    return snapshot;
  }

  /// Descarga una M3U una sola vez y escribe LIVE/Películas/Series directamente
  /// en generaciones temporales independientes. No se crean tres listas de
  /// Channel en RAM: sólo viven el parser incremental y las categorías únicas.
  Future<void> _downloadAndPartitionToDisk(Playlist playlist) async {
    if (playlist.sourceType == PlaylistSourceType.futbolTotal) {
      await _downloadFutbolTotalToDisk(playlist);
      return;
    }

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
        final committed = await writer.commit(categories: categories[kind]!);
        if (committed) {
          // La próxima lectura debe materializar la generación nueva, no una
          // instantánea RAM anterior que todavía estaba visible en pantalla.
          _forget('${playlist.id}|m3u_${kind.name}');
        }
      }

      _lastNetworkRefresh['${playlist.id}|${playlist.source}'] = DateTime.now();
    } catch (_) {
      for (final writer in writers.values) {
        await writer.abort();
      }
      rethrow;
    }
  }

  Future<void> _downloadFutbolTotalToDisk(Playlist playlist) async {
    // El último catálogo confirmado queda como red de seguridad. Si una de las
    // listas remotas falla durante una actualización, conservamos para esa
    // TvList los canales de la última generación buena en lugar de publicar
    // un catálogo incompleto.
    SectionCatalogSnapshot? previous;
    final previousSource = await _catalogFiles.loadSource(
      playlist.id,
      'm3u_${TvSectionKind.live.name}',
    );
    if (previousSource != null) {
      final decoded = await _decodeFileSource(previousSource);
      if (decoded != null &&
          decoded.channels.every(
            (channel) => (channel.catalogSource ?? '').trim().isNotEmpty,
          ) &&
          !decoded.channels.any(_needsFutbolTotalPlaybackUpgrade)) {
        previous = decoded;
      }
    }

    final service = FutbolTotalCatalogService();
    final catalogs =
        <({String sourceName, FutbolTotalFlowCatalog catalog})>[];
    FutbolTotalManifest? manifest;
    final failedDefinitions = <FutbolTotalListDefinition>[];

    try {
      final raw = await service.fetchRaw(playlist.source);

      try {
        final parsedManifest = const FutbolTotalManifestParser().parse(raw);
        if (parsedManifest.lists.isNotEmpty) {
          manifest = parsedManifest;
        }
      } on FormatException {
        // Puede ser un catálogo Flow directo; se prueba debajo.
      }

      if (manifest != null) {
        Future<bool> loadDefinition(
          FutbolTotalListDefinition definition, {
          bool noCache = false,
        }) async {
          try {
            final catalog = noCache
                ? const FutbolTotalFlowCatalogParser().parse(
                    await service.fetchRaw(definition.url, noCache: true),
                  )
                : await service.loadFlow(definition);
            if (catalog.channels.isEmpty) return false;
            catalogs.add((sourceName: definition.name, catalog: catalog));
            return true;
          } catch (_) {
            return false;
          }
        }

        // Primera pasada: mantiene el orden oficial del manifiesto.
        for (final definition in manifest.flowLists) {
          if (!await loadDefinition(definition)) {
            failedDefinitions.add(definition);
          }
        }

        // Segunda pasada sin caché HTTP sólo para las listas que fallaron.
        // Evita que un error temporal publique un catálogo recortado.
        if (failedDefinitions.isNotEmpty) {
          final retry = List<FutbolTotalListDefinition>.from(failedDefinitions);
          failedDefinitions.clear();
          for (final definition in retry) {
            if (!await loadDefinition(definition, noCache: true)) {
              failedDefinitions.add(definition);
            }
          }
        }

        // Si toda la red falló pero ya había una generación buena, no la
        // reemplazamos ni obligamos al usuario a volver a descargar todo.
        if (catalogs.isEmpty && previous != null) {
          _lastNetworkRefresh['${playlist.id}|${playlist.source}'] =
              DateTime.now();
          return;
        }

        // Sólo en una instalación sin caché funcional usamos el Flow principal
        // conocido como último recurso.
        if (catalogs.isEmpty) {
          try {
            final fallbackRaw = await service.fetchRaw(
              FutbolTotalEndpoints.defaultFlowRaw,
              noCache: true,
            );
            final fallback =
                const FutbolTotalFlowCatalogParser().parse(fallbackRaw);
            if (fallback.channels.isNotEmpty) {
              catalogs.add((
                sourceName: 'Fútbol Total',
                catalog: fallback,
              ));
            }
          } catch (_) {}
        }

        if (catalogs.isEmpty && manifest.futbolLists.isNotEmpty) {
          throw const FormatException(
            'El manifiesto sólo contiene agenda de fútbol. '
            'El resolvedor de canal_id todavía no está conectado al reproductor.',
          );
        }
      } else {
        final direct = const FutbolTotalFlowCatalogParser().parse(raw);
        if (direct.channels.isNotEmpty) {
          catalogs.add((
            sourceName: playlist.name.trim().isEmpty
                ? 'Fútbol Total'
                : playlist.name.trim(),
            catalog: direct,
          ));
        }
      }
    } finally {
      service.close();
    }

    if (catalogs.isEmpty) {
      throw FormatException(
        failedDefinitions.isNotEmpty
            ? 'Fútbol Total no pudo cargar ninguna de sus listas disponibles '
                '(${failedDefinitions.length} fallaron).'
            : 'Fútbol Total no contiene catálogos Flow reproducibles.',
      );
    }

    final freshBySource = <String, FutbolTotalFlowCatalog>{};
    for (final loaded in catalogs) {
      freshBySource.putIfAbsent(loaded.sourceName, () => loaded.catalog);
    }

    final orderedSources =
        <({String sourceName, Iterable<Channel> channels})>[];

    if (manifest != null && manifest.flowLists.isNotEmpty) {
      for (final definition in manifest.flowLists) {
        final fresh = freshBySource[definition.name];
        if (fresh != null) {
          orderedSources.add((
            sourceName: definition.name,
            channels: fresh.channels,
          ));
          continue;
        }

        // Una TvList que falló se completa desde la generación anterior si
        // existe. Así una actualización parcial nunca hace desaparecer listas
        // que ya estaban disponibles.
        final cached = previous?.channels.where(
          (channel) => channel.catalogSource == definition.name,
        );
        if (cached != null && cached.isNotEmpty) {
          orderedSources.add((
            sourceName: definition.name,
            channels: cached,
          ));
        }
      }

      // El fallback principal no tiene por qué compartir el nombre de una
      // TvList del manifiesto. Se usa sólo si no pudimos construir ninguna.
      if (orderedSources.isEmpty) {
        for (final loaded in catalogs) {
          orderedSources.add((
            sourceName: loaded.sourceName,
            channels: loaded.catalog.channels,
          ));
        }
      }
    } else {
      for (final loaded in catalogs) {
        orderedSources.add((
          sourceName: loaded.sourceName,
          channels: loaded.catalog.channels,
        ));
      }
    }

    final liveWriter = await _catalogFiles.beginSnapshot(
      serviceId: playlist.id,
      kind: 'm3u_${TvSectionKind.live.name}',
    );
    final categorySet = <String>{};
    final categories = <String>[];
    final seen = <String>{};
    var count = 0;

    try {
      for (final loaded in orderedSources) {
        final sourceName = loaded.sourceName.trim().isEmpty
            ? 'Fútbol Total'
            : loaded.sourceName.trim();

        for (final channel in loaded.channels) {
          final categoryName = channel.group?.trim() ?? '';
          final scopedKey =
              '$sourceName|$categoryName|${channel.uniqueKey}';
          if (!seen.add(scopedKey)) continue;

          final grouped = _withFutbolTotalSource(
            channel,
            sourceName: sourceName,
          );
          count++;
          liveWriter.add(grouped.toJson());

          final group = grouped.group?.trim();
          if (group != null && group.isNotEmpty && categorySet.add(group)) {
            categories.add(group);
          }
        }
      }

      if (count == 0) {
        throw const FormatException(
          'Fútbol Total no devolvió canales reproducibles.',
        );
      }

      final committed = await liveWriter.commit(categories: categories);
      if (!committed) {
        throw const FormatException(
          'Fútbol Total no pudo guardar el catálogo LIVE.',
        );
      }

      // Fútbol Total es una fuente exclusivamente LIVE.
      await _catalogFiles.clearSection(
        playlist.id,
        'm3u_${TvSectionKind.movies.name}',
      );
      await _catalogFiles.clearSection(
        playlist.id,
        'm3u_${TvSectionKind.series.name}',
      );
      await _store.deleteLegacySnapshot(
        playlist.id,
        'm3u_${TvSectionKind.movies.name}',
      );
      await _store.deleteLegacySnapshot(
        playlist.id,
        'm3u_${TvSectionKind.series.name}',
      );

      for (final kind in TvSectionKind.values) {
        _forget('${playlist.id}|m3u_${kind.name}');
      }
      _lastNetworkRefresh['${playlist.id}|${playlist.source}'] =
          DateTime.now();
    } catch (_) {
      await liveWriter.abort();
      rethrow;
    }
  }

  Channel _withFutbolTotalSource(
    Channel channel, {
    required String sourceName,
  }) {
    final listName =
        sourceName.trim().isEmpty ? 'Fútbol Total' : sourceName.trim();

    return Channel(
      name: channel.name,
      url: channel.url,
      logoUrl: channel.logoUrl,
      logoBytes: channel.logoBytes,
      drmKeyId: channel.drmKeyId,
      drmKey: channel.drmKey,
      streamMimeType: channel.streamMimeType,
      group: channel.group,
      catalogSource: listName,
      tvgId: channel.tvgId,
      xtreamStreamId: channel.xtreamStreamId,
      dynamicStreamId: channel.dynamicStreamId,
      dynamicStreamPath: channel.dynamicStreamPath,
      providerGlobalIndex: channel.providerGlobalIndex,
      httpUserAgent: channel.httpUserAgent,
      httpReferrer: channel.httpReferrer,
      httpHeaders: channel.httpHeaders,
    );
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
      bytes += channel.logoBytes?.lengthInBytes ?? 0;
      bytes += _stringBytes(channel.drmKeyId);
      bytes += _stringBytes(channel.drmKey);
      bytes += _stringBytes(channel.streamMimeType);
      bytes += _stringBytes(channel.group);
      bytes += _stringBytes(channel.catalogSource);
      bytes += _stringBytes(channel.tvgId);
      bytes += _stringBytes(channel.dynamicStreamId);
      bytes += _stringBytes(channel.dynamicStreamPath);
      bytes += _stringBytes(channel.providerGlobalIndex);
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

  bool _needsFutbolTotalPlaybackUpgrade(Channel channel) {
    final dynamicPath = channel.dynamicStreamPath?.trim();
    if (dynamicPath != null && dynamicPath.isNotEmpty) return false;

    final url = channel.url.trim();
    if (url.startsWith('tvfull-dynamic://')) return true;
    if (!RegExp(r'live/c\\d+eds/', caseSensitive: false).hasMatch(url)) {
      return false;
    }
    final lower = url.toLowerCase();
    return lower.contains('flow.com.ar') || lower.contains('cvattv.com.ar');
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
