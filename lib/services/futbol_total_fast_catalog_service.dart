import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/playlist.dart';
import 'catalog_file_store.dart';
import 'futbol_total_catalog_service.dart';
import 'futbol_total_embedded_config.dart';
import 'futbol_total_endpoints.dart';
import 'futbol_total_manifest_parser.dart';

class FutbolTotalFastCatalogSnapshot {
  final FutbolTotalManifest manifest;
  final FutbolTotalListDefinition source;
  final List<String> sourceNames;
  final List<Channel> channels;
  final List<String> categories;
  final bool fromCache;
  final bool stale;

  const FutbolTotalFastCatalogSnapshot({
    required this.manifest,
    required this.source,
    required this.sourceNames,
    required this.channels,
    required this.categories,
    required this.fromCache,
    required this.stale,
  });
}

class _FutbolTotalCachedSource {
  final List<Channel> channels;
  final List<String> categories;
  final DateTime updatedAt;

  const _FutbolTotalCachedSource({
    required this.channels,
    required this.categories,
    required this.updatedAt,
  });
}

/// Catálogo rápido exclusivo de Fútbol Total.
///
/// La estructura de TvLists sale de un manifiesto base empaquetado en el APK.
/// Cada TvList tiene un snapshot persistente independiente y se descarga
/// únicamente cuando el usuario la abre. Una copia vencida se muestra primero
/// y se renueva sin bloquear la navegación.
class FutbolTotalFastCatalogService {
  FutbolTotalFastCatalogService._();

  static final FutbolTotalFastCatalogService instance =
      FutbolTotalFastCatalogService._();

  static const String _embeddedManifestAsset =
      'assets/futbol_total/bootstrap_manifest.json';
  static const Duration _defaultSourceFreshFor = Duration(hours: 6);
  static const Duration _manifestFreshFor = Duration(hours: 6);

  final CatalogFileStore _files = CatalogFileStore.instance;
  final Map<String, FutbolTotalManifest> _manifestMemory =
      <String, FutbolTotalManifest>{};
  final Map<String, Future<FutbolTotalFastCatalogSnapshot>> _pendingSources =
      <String, Future<FutbolTotalFastCatalogSnapshot>>{};
  final Set<String> _manifestRefreshScheduled = <String>{};

  Future<FutbolTotalFastCatalogSnapshot> loadInitial(Playlist playlist) async {
    final manifest = await loadManifest(playlist);
    final definitions = _flowDefinitions(manifest);
    if (definitions.isEmpty) {
      throw const FormatException(
        'Fútbol Total no contiene listas LIVE reproducibles.',
      );
    }

    final first = definitions.first;
    final cached = await _loadCached(playlist, first);
    if (cached != null) {
      return _snapshot(manifest, first, cached, fromCache: true);
    }

    try {
      return await refreshSource(
        playlist,
        first.name,
        manifest: manifest,
      );
    } catch (_) {
      for (final definition in definitions.skip(1)) {
        final fallback = await _loadCached(playlist, definition);
        if (fallback != null) {
          return _snapshot(
            manifest,
            definition,
            fallback,
            fromCache: true,
          );
        }
      }
      rethrow;
    }
  }

  Future<FutbolTotalFastCatalogSnapshot> loadSource(
    Playlist playlist,
    String sourceName,
  ) async {
    final manifest = await loadManifest(playlist);
    final definition = _definitionByName(manifest, sourceName);
    final cached = await _loadCached(playlist, definition);
    if (cached != null) {
      return _snapshot(manifest, definition, cached, fromCache: true);
    }
    return refreshSource(
      playlist,
      definition.name,
      manifest: manifest,
    );
  }

  Future<FutbolTotalFastCatalogSnapshot?> refreshSourceIfStale(
    Playlist playlist,
    String sourceName,
  ) async {
    final manifest = await loadManifest(playlist);
    final definition = _definitionByName(manifest, sourceName);
    final cached = await _loadCached(playlist, definition);
    if (cached != null && !_isStale(definition, cached.updatedAt)) {
      return null;
    }
    return refreshSource(
      playlist,
      definition.name,
      manifest: manifest,
      forceNetwork: cached != null,
    );
  }

  Future<FutbolTotalFastCatalogSnapshot> refreshSource(
    Playlist playlist,
    String sourceName, {
    FutbolTotalManifest? manifest,
    bool forceNetwork = false,
  }) async {
    final resolvedManifest = manifest ?? await loadManifest(playlist);
    final definition = _definitionByName(resolvedManifest, sourceName);
    final pendingKey = '${playlist.id}|${definition.url}';
    final pending = _pendingSources[pendingKey];
    if (pending != null) return pending;

    final future = _refreshSourceImpl(
      playlist,
      resolvedManifest,
      definition,
      forceNetwork: forceNetwork,
    );
    _pendingSources[pendingKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_pendingSources[pendingKey], future)) {
        _pendingSources.remove(pendingKey);
      }
    }
  }

  Future<void> warm(Playlist playlist) async {
    try {
      final snapshot = await loadInitial(playlist);
      if (snapshot.stale) {
        unawaited(refreshSourceIfStale(playlist, snapshot.source.name));
      }
    } catch (_) {}
  }

  Future<FutbolTotalManifest> loadManifest(Playlist playlist) async {
    final memory = _manifestMemory[playlist.id];
    if (memory != null) {
      _scheduleManifestRefresh(playlist);
      return memory;
    }

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_manifestPreferenceKey(playlist));
    if (stored != null) {
      final parsed = _tryManifest(stored);
      if (parsed != null && parsed.lists.isNotEmpty) {
        _manifestMemory[playlist.id] = parsed;
        _scheduleManifestRefresh(playlist);
        return parsed;
      }
    }

    if (playlist.source == FutbolTotalEndpoints.manifestRaw) {
      final raw = await rootBundle.loadString(_embeddedManifestAsset);
      final embedded = const FutbolTotalManifestParser().parse(raw);
      _manifestMemory[playlist.id] = embedded;
      _scheduleManifestRefresh(playlist);
      return embedded;
    }

    return refreshManifest(playlist);
  }

  Future<FutbolTotalManifest> refreshManifest(Playlist playlist) async {
    final service = FutbolTotalCatalogService();
    try {
      final raw = await service.fetchRaw(playlist.source, noCache: true);
      final parsed = const FutbolTotalManifestParser().parse(raw);
      if (parsed.lists.isEmpty) {
        throw const FormatException(
          'El manifiesto de Fútbol Total no contiene listas.',
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_manifestPreferenceKey(playlist), raw);
      await prefs.setInt(
        _manifestUpdatedPreferenceKey(playlist),
        DateTime.now().millisecondsSinceEpoch,
      );
      _manifestMemory[playlist.id] = parsed;
      return parsed;
    } finally {
      service.close();
    }
  }

  Future<FutbolTotalFastCatalogSnapshot> _refreshSourceImpl(
    Playlist playlist,
    FutbolTotalManifest manifest,
    FutbolTotalListDefinition definition, {
    required bool forceNetwork,
  }) async {
    final previous = await _loadCached(playlist, definition);
    final service = FutbolTotalCatalogService();
    try {
      final catalog = await service.loadFlow(
        definition,
        noCache: forceNetwork,
      );
      if (catalog.channels.isEmpty) {
        throw const FormatException(
          'La TvList seleccionada no devolvió canales.',
        );
      }

      final channels = catalog.channels
          .map(
            (channel) => _withSource(
              channel,
              sourceName: definition.name,
            ),
          )
          .toList(growable: false);

      await _files.saveSnapshot(
        serviceId: playlist.id,
        kind: _sourceKind(definition),
        categories: catalog.categories,
        items: channels.map((channel) => channel.toJson()),
      );

      final fresh = _FutbolTotalCachedSource(
        channels: channels,
        categories: catalog.categories,
        updatedAt: DateTime.now(),
      );
      return _snapshot(
        manifest,
        definition,
        fresh,
        fromCache: false,
      );
    } catch (_) {
      if (previous != null) {
        return _snapshot(
          manifest,
          definition,
          previous,
          fromCache: true,
          forceStale: true,
        );
      }
      rethrow;
    } finally {
      service.close();
    }
  }

  Future<_FutbolTotalCachedSource?> _loadCached(
    Playlist playlist,
    FutbolTotalListDefinition definition,
  ) async {
    final source = await _files.loadSource(
      playlist.id,
      _sourceKind(definition),
    );
    if (source == null) return null;

    final channels = <Channel>[];
    try {
      final lines = source.itemsFile
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        final raw = line.trim();
        if (raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final channel = Channel.fromJson(
              Map<String, dynamic>.from(decoded),
            );
            channels.add(
              (channel.catalogSource ?? '').trim().isEmpty
                  ? _withSource(channel, sourceName: definition.name)
                  : channel,
            );
          }
        } catch (_) {}
      }
    } catch (_) {
      return null;
    }
    if (channels.isEmpty) return null;

    return _FutbolTotalCachedSource(
      channels: List<Channel>.unmodifiable(channels),
      categories: source.categories,
      updatedAt: source.updatedAt,
    );
  }

  FutbolTotalFastCatalogSnapshot _snapshot(
    FutbolTotalManifest manifest,
    FutbolTotalListDefinition definition,
    _FutbolTotalCachedSource cached, {
    required bool fromCache,
    bool forceStale = false,
  }) {
    final definitions = _flowDefinitions(manifest);
    return FutbolTotalFastCatalogSnapshot(
      manifest: manifest,
      source: definition,
      sourceNames:
          definitions.map((item) => item.name).toList(growable: false),
      channels: cached.channels,
      categories: cached.categories,
      fromCache: fromCache,
      stale: forceStale || _isStale(definition, cached.updatedAt),
    );
  }

  List<FutbolTotalListDefinition> _flowDefinitions(
    FutbolTotalManifest manifest,
  ) {
    final values = manifest.flowLists.toList(growable: false);
    if (values.isNotEmpty) return values;
    return FutbolTotalEmbeddedConfig.fallbackManifest()
        .flowLists
        .toList(growable: false);
  }

  FutbolTotalListDefinition _definitionByName(
    FutbolTotalManifest manifest,
    String sourceName,
  ) {
    final definitions = _flowDefinitions(manifest);
    for (final definition in definitions) {
      if (definition.name == sourceName) return definition;
    }
    throw FormatException(
      'La TvList de Fútbol Total ya no está disponible: $sourceName',
    );
  }

  bool _isStale(
    FutbolTotalListDefinition definition,
    DateTime updatedAt,
  ) {
    final seconds = definition.ttlSeconds;
    final freshFor = seconds > 0
        ? Duration(seconds: seconds)
        : _defaultSourceFreshFor;
    return DateTime.now().difference(updatedAt) >= freshFor;
  }

  String _sourceKind(FutbolTotalListDefinition definition) {
    final digest = sha256
        .convert(utf8.encode(definition.url.trim()))
        .toString()
        .substring(0, 16);
    return 'ft_v62_$digest';
  }

  String _manifestPreferenceKey(Playlist playlist) {
    final digest = sha256
        .convert(utf8.encode(playlist.source.trim()))
        .toString()
        .substring(0, 16);
    return 'tvfull_ft_manifest_v62_$digest';
  }

  String _manifestUpdatedPreferenceKey(Playlist playlist) =>
      '${_manifestPreferenceKey(playlist)}_updated';

  FutbolTotalManifest? _tryManifest(String raw) {
    try {
      return const FutbolTotalManifestParser().parse(raw);
    } catch (_) {
      return null;
    }
  }

  void _scheduleManifestRefresh(Playlist playlist) {
    if (!_manifestRefreshScheduled.add(playlist.id)) return;
    unawaited(_refreshManifestIfStale(playlist));
  }

  Future<void> _refreshManifestIfStale(Playlist playlist) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updated = prefs.getInt(_manifestUpdatedPreferenceKey(playlist));
      final stale = updated == null ||
          DateTime.now().difference(
                DateTime.fromMillisecondsSinceEpoch(updated),
              ) >=
              _manifestFreshFor;
      if (stale) await refreshManifest(playlist);
    } catch (_) {}
  }

  Channel _withSource(
    Channel channel, {
    required String sourceName,
  }) {
    return Channel(
      name: channel.name,
      url: channel.url,
      logoUrl: channel.logoUrl,
      logoBytes: channel.logoBytes,
      drmKeyId: channel.drmKeyId,
      drmKey: channel.drmKey,
      streamMimeType: channel.streamMimeType,
      group: channel.group,
      catalogSource: sourceName,
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
}
