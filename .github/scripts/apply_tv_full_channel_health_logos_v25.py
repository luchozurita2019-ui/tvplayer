from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    content = read(path)
    if old not in content:
        raise SystemExit(f"Expected block not found in {path}: {old[:120]!r}")
    write(path, content.replace(old, new, 1))


pubspec = read("pubspec.yaml")
if "version: 1.3.3+25" in pubspec and (ROOT / "lib/services/channel_health_service.dart").exists():
    print("TV FULL PRO 1.3.3+25 already applied")
    raise SystemExit(0)

write(
    "lib/services/channel_health_service.dart",
    """import 'dart:async';

import '../models/channel.dart';
import 'tv_local_store.dart';

enum ChannelHealthState { unknown, ok, slow, dead }

class _ChannelHealthEntry {
  final ChannelHealthState state;
  final DateTime expiresAt;

  const _ChannelHealthEntry(this.state, this.expiresAt);
}

/// Memoria liviana de salud LIVE.
///
/// Los canales sanos se recuerdan sólo en RAM. Los canales que fallaron de
/// forma concluyente se persisten durante un cooldown corto para que el zapping
/// no vuelva a perder tiempo con la misma URL una y otra vez.
class ChannelHealthService {
  ChannelHealthService._();

  static final ChannelHealthService instance = ChannelHealthService._();

  static const Duration deadCooldown = Duration(minutes: 10);
  static const Duration healthyMemoryTtl = Duration(hours: 24);

  final Map<String, _ChannelHealthEntry> _entries =
      <String, _ChannelHealthEntry>{};
  bool _loaded = false;
  Future<void>? _loadFuture;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final active = _loadFuture;
    if (active != null) {
      await active;
      return;
    }

    final future = _loadPersisted();
    _loadFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loadFuture, future)) _loadFuture = null;
    }
  }

  Future<void> _loadPersisted() async {
    try {
      final rows = await TvLocalStore.instance.loadChannelHealthRows();
      final now = DateTime.now();
      for (final row in rows) {
        final key = row['channel_key']?.toString().trim() ?? '';
        final rawStatus = row['status']?.toString().trim() ?? '';
        final rawExpires = row['expires_at'];
        final expiresMillis = rawExpires is int
            ? rawExpires
            : int.tryParse(rawExpires?.toString() ?? '');
        if (key.isEmpty || expiresMillis == null) continue;
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresMillis);
        if (!expiresAt.isAfter(now)) continue;
        final state = switch (rawStatus) {
          'dead' => ChannelHealthState.dead,
          'slow' => ChannelHealthState.slow,
          'ok' => ChannelHealthState.ok,
          _ => ChannelHealthState.unknown,
        };
        if (state != ChannelHealthState.unknown) {
          _entries[key] = _ChannelHealthEntry(state, expiresAt);
        }
      }
      unawaited(TvLocalStore.instance.pruneChannelHealth());
    } catch (_) {
      // La salud es una optimización. Nunca debe impedir abrir el reproductor.
    } finally {
      _loaded = true;
    }
  }

  ChannelHealthState statusOf(Channel channel) {
    final key = channel.uniqueKey;
    final entry = _entries[key];
    if (entry == null) return ChannelHealthState.unknown;
    if (!entry.expiresAt.isAfter(DateTime.now())) {
      _entries.remove(key);
      if (entry.state == ChannelHealthState.dead) {
        unawaited(TvLocalStore.instance.deleteChannelHealth(key));
      }
      return ChannelHealthState.unknown;
    }
    return entry.state;
  }

  bool isTemporarilyDead(Channel channel) =>
      statusOf(channel) == ChannelHealthState.dead;

  void markHealthy(Channel channel, {required bool slow}) {
    final key = channel.uniqueKey;
    final previous = _entries[key];
    _entries[key] = _ChannelHealthEntry(
      slow ? ChannelHealthState.slow : ChannelHealthState.ok,
      DateTime.now().add(healthyMemoryTtl),
    );
    if (previous?.state == ChannelHealthState.dead) {
      unawaited(TvLocalStore.instance.deleteChannelHealth(key));
    }
  }

  void markDead(Channel channel, {String reason = ''}) {
    final key = channel.uniqueKey;
    final now = DateTime.now();
    final current = _entries[key];
    if (current?.state == ChannelHealthState.dead &&
        current!.expiresAt.difference(now) > const Duration(minutes: 9)) {
      return;
    }

    final expiresAt = now.add(deadCooldown);
    _entries[key] = _ChannelHealthEntry(ChannelHealthState.dead, expiresAt);
    unawaited(
      TvLocalStore.instance.upsertChannelHealth(
        channelKey: key,
        status: 'dead',
        reason: reason,
        expiresAt: expiresAt,
      ),
    );
  }
}
""",
)

write(
    "lib/services/channel_logo_resolver_service.dart",
    """import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'tv_local_store.dart';

class _LogoCandidate {
  final String url;
  final int score;

  const _LogoCandidate(this.url, this.score);
}

/// Resuelve logos faltantes sin descargar una base gigante a RAM.
///
/// TV FULL PRO consume logos.json como stream y conserva sólo coincidencias
/// exactas más la biblioteca argentina. El catálogo del proveedor siempre tiene
/// prioridad y esta fuente sólo actúa como respaldo.
class ChannelLogoResolverService {
  ChannelLogoResolverService._();

  static final ChannelLogoResolverService instance =
      ChannelLogoResolverService._();

  static final Uri _logosUri =
      Uri.parse('https://iptv-org.github.io/api/logos.json');
  static const Set<String> _technicalTokens = <String>{
    'hd',
    'fhd',
    'fullhd',
    'uhd',
    '4k',
    '2160p',
    '1080p',
    '720p',
    '576p',
    '480p',
    'hevc',
    'h265',
    'h264',
    'av1',
    'sd',
    'vip',
    'backup',
    'test',
    'alt',
  };
  static const Map<String, String> _aliases = <String, String>{
    'televisionpublica': 'tvpublica',
    'tvpublicaargentina': 'tvpublica',
    'tycsport': 'tycsports',
    'cronicahd': 'cronicatv',
    'cronica': 'cronicatv',
    'eltrecehd': 'eltrece',
  };
  static const Set<String> _rasterFormats = <String>{
    'PNG',
    'JPEG',
    'JPG',
    'WEBP',
  };

  final Map<String, String?> _values = <String, String?>{};
  final Set<String> _knownKeys = <String>{};
  final Set<String> _pendingKeys = <String>{};
  Future<void>? _scanFuture;

  @visibleForTesting
  static String normalizeNameForLookup(String raw) {
    var value = raw.toLowerCase();
    const accents = <String, String>{
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'ã': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    for (final entry in accents.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }

    final tokens = value
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(RegExp(r'\\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: true);
    if (tokens.isNotEmpty &&
        (tokens.first == 'ar' || tokens.first == 'arg')) {
      tokens.removeAt(0);
    }
    if (tokens.isNotEmpty &&
        (tokens.last == 'ar' || tokens.last == 'arg')) {
      tokens.removeLast();
    }
    tokens.removeWhere(_technicalTokens.contains);
    final normalized = tokens.join();
    return _aliases[normalized] ?? normalized;
  }

  @visibleForTesting
  static Set<String> lookupKeysForChannel(Channel channel) {
    final keys = <String>{};
    var tvgId = channel.tvgId?.trim() ?? '';
    if (tvgId.contains('@')) tvgId = tvgId.split('@').first.trim();
    if (tvgId.isNotEmpty) keys.add('id:${tvgId.toLowerCase()}');
    final name = normalizeNameForLookup(channel.name);
    if (name.length >= 2) keys.add('name:$name');
    return keys;
  }

  Future<void> primeChannels(Iterable<Channel> channels) async {
    final keys = <String>{};
    var missingCount = 0;
    for (final channel in channels) {
      final providerLogo = channel.logoUrl?.trim() ?? '';
      if (providerLogo.isNotEmpty) continue;
      keys.addAll(lookupKeysForChannel(channel));
      missingCount++;
      if (missingCount >= 32) break;
    }
    if (keys.isEmpty) return;
    await _ensureKeys(keys, allowNetwork: true);
  }

  Future<String?> resolveFallback(
    Channel channel, {
    bool allowNetwork = true,
  }) async {
    final keys = lookupKeysForChannel(channel);
    if (keys.isEmpty) return null;
    await _ensureKeys(keys, allowNetwork: allowNetwork);
    for (final key in keys) {
      final value = _values[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> _ensureKeys(
    Set<String> keys, {
    required bool allowNetwork,
  }) async {
    final unknown = keys.where((key) => !_knownKeys.contains(key)).toSet();
    if (unknown.isNotEmpty) {
      try {
        final cached = await TvLocalStore.instance.loadLogoFallbacks(unknown);
        for (final entry in cached.entries) {
          _knownKeys.add(entry.key);
          _values[entry.key] = entry.value;
        }
      } catch (_) {}
    }

    final unresolved = keys.where((key) => !_knownKeys.contains(key)).toSet();
    if (unresolved.isEmpty || !allowNetwork) return;
    await _requestScan(unresolved);

    final stillPending =
        unresolved.where((key) => !_knownKeys.contains(key)).toSet();
    if (stillPending.isNotEmpty &&
        stillPending.any(_pendingKeys.contains)) {
      await _requestScan(stillPending);
    }
  }

  Future<void> _requestScan(Set<String> keys) async {
    _pendingKeys.addAll(keys);
    final active = _scanFuture;
    if (active != null) {
      await active;
      return;
    }

    final future = _drainScan();
    _scanFuture = future;
    try {
      await future;
    } finally {
      if (identical(_scanFuture, future)) _scanFuture = null;
    }
  }

  Future<void> _drainScan() async {
    // Agrupa los pedidos de varios logos visibles en una sola descarga.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final targets = Set<String>.from(_pendingKeys);
    _pendingKeys.removeAll(targets);
    if (targets.isEmpty) return;
    await _scanRemote(targets);
  }

  Future<void> _scanRemote(Set<String> targets) async {
    final client = http.Client();
    final winners = <String, _LogoCandidate>{};
    var completed = false;
    try {
      final request = http.Request('GET', _logosUri)
        ..headers['Accept'] = 'application/json';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;

      await for (final objectText in _jsonObjects(
        response.stream.timeout(const Duration(seconds: 10)),
      )) {
        dynamic decoded;
        try {
          decoded = jsonDecode(objectText);
        } catch (_) {
          continue;
        }
        if (decoded is! Map) continue;

        final channelId = decoded['channel']?.toString().trim() ?? '';
        final url = decoded['url']?.toString().trim() ?? '';
        if (channelId.isEmpty || url.isEmpty || !url.startsWith('https://')) {
          continue;
        }

        final format = decoded['format']?.toString().trim().toUpperCase() ?? '';
        if (!_isRaster(format, url)) continue;
        final lowerId = channelId.toLowerCase();
        final idKey = 'id:$lowerId';
        final dot = channelId.indexOf('.');
        final base = dot > 0 ? channelId.substring(0, dot) : channelId;
        final normalizedBase = normalizeNameForLookup(base);
        final nameKey = normalizedBase.isEmpty ? '' : 'name:$normalizedBase';
        final argentina = lowerId.endsWith('.ar');
        final exactRequested = targets.contains(idKey);
        final nameRequested = nameKey.isNotEmpty && targets.contains(nameKey);
        if (!argentina && !exactRequested && !nameRequested) continue;

        final inUse = decoded['in_use'] != false;
        final width = _asInt(decoded['width']);
        final height = _asInt(decoded['height']);
        final area = width > 0 && height > 0 ? width * height : 0;
        var score = area;
        if (inUse) score += 1 << 54;
        if (argentina) score += 1 << 50;
        if (exactRequested) score += 1 << 58;

        if (argentina || exactRequested) {
          _consider(winners, idKey, url, score);
        }
        if (nameKey.isNotEmpty && (argentina || nameRequested)) {
          _consider(winners, nameKey, url, score);
        }
      }
      completed = true;
    } catch (_) {
      return;
    } finally {
      client.close();
    }

    if (!completed) return;
    final persisted = <String, String?>{};
    for (final entry in winners.entries) {
      persisted[entry.key] = entry.value.url;
    }
    for (final key in targets) {
      persisted.putIfAbsent(key, () => null);
    }

    for (final entry in persisted.entries) {
      _knownKeys.add(entry.key);
      _values[entry.key] = entry.value;
    }
    try {
      await TvLocalStore.instance.saveLogoFallbacks(persisted);
      unawaited(TvLocalStore.instance.pruneLogoFallbacks());
    } catch (_) {}
  }

  static void _consider(
    Map<String, _LogoCandidate> winners,
    String key,
    String url,
    int score,
  ) {
    final current = winners[key];
    if (current == null || score > current.score) {
      winners[key] = _LogoCandidate(url, score);
    }
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _isRaster(String format, String url) {
    if (_rasterFormats.contains(format)) return true;
    final lower = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  static Stream<String> _jsonObjects(Stream<List<int>> bytes) async* {
    final decoded = utf8.decoder.bind(bytes);
    var depth = 0;
    var inString = false;
    var escaped = false;
    StringBuffer? buffer;

    await for (final chunk in decoded) {
      for (final rune in chunk.runes) {
        final char = String.fromCharCode(rune);
        if (buffer == null) {
          if (char == '{') {
            buffer = StringBuffer()..write(char);
            depth = 1;
            inString = false;
            escaped = false;
          }
          continue;
        }

        buffer.write(char);
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (char == r'\\') {
            escaped = true;
          } else if (char == '"') {
            inString = false;
          }
          continue;
        }

        if (char == '"') {
          inString = true;
        } else if (char == '{') {
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth == 0) {
            yield buffer.toString();
            buffer = null;
          }
        }
      }
    }
  }
}
""",
)

write(
    "lib/widgets/channel_logo_image.dart",
    """import 'dart:async';

import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../services/channel_logo_resolver_service.dart';
import 'cached_artwork_image.dart';

/// Imagen de canal con prioridad estricta:
/// proveedor -> respaldo reconocido -> fallback genérico.
class ChannelLogoImage extends StatefulWidget {
  final Channel channel;
  final BoxFit fit;
  final Widget fallback;
  final bool allowNetwork;
  final int? cacheWidth;
  final int? cacheHeight;
  final int priority;
  final double prefetchExtent;

  const ChannelLogoImage({
    super.key,
    required this.channel,
    required this.fit,
    required this.fallback,
    this.allowNetwork = true,
    this.cacheWidth,
    this.cacheHeight,
    this.priority = 0,
    this.prefetchExtent = 96,
  });

  @override
  State<ChannelLogoImage> createState() => _ChannelLogoImageState();
}

class _ChannelLogoImageState extends State<ChannelLogoImage> {
  bool _providerFailed = false;
  bool _resolvingFallback = false;
  String? _fallbackUrl;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (_providerLogo.isEmpty) _scheduleFallback();
  }

  @override
  void didUpdateWidget(covariant ChannelLogoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.uniqueKey != widget.channel.uniqueKey ||
        oldWidget.channel.logoUrl != widget.channel.logoUrl ||
        oldWidget.allowNetwork != widget.allowNetwork) {
      _generation++;
      _providerFailed = false;
      _resolvingFallback = false;
      _fallbackUrl = null;
      if (_providerLogo.isEmpty) _scheduleFallback();
    }
  }

  String get _providerLogo => widget.channel.logoUrl?.trim() ?? '';

  void _scheduleFallback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resolveFallback());
    });
  }

  void _onProviderAvailability(bool available) {
    if (available || _providerFailed) return;
    setState(() => _providerFailed = true);
    _scheduleFallback();
  }

  Future<void> _resolveFallback() async {
    if (_resolvingFallback || _fallbackUrl != null) return;
    _resolvingFallback = true;
    final generation = ++_generation;
    final resolved = await ChannelLogoResolverService.instance.resolveFallback(
      widget.channel,
      allowNetwork: widget.allowNetwork,
    );
    if (!mounted || generation != _generation) return;
    _resolvingFallback = false;
    if (resolved == null || resolved.trim().isEmpty) return;
    setState(() => _fallbackUrl = resolved.trim());
  }

  @override
  Widget build(BuildContext context) {
    final provider = _providerLogo;
    if (provider.isNotEmpty && !_providerFailed) {
      return CachedArtworkImage(
        url: provider,
        fit: widget.fit,
        fallback: widget.fallback,
        allowNetwork: widget.allowNetwork,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        priority: widget.priority,
        prefetchExtent: widget.prefetchExtent,
        onAvailabilityChanged: _onProviderAvailability,
      );
    }

    final fallbackUrl = _fallbackUrl;
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      return CachedArtworkImage(
        url: fallbackUrl,
        fit: widget.fit,
        fallback: widget.fallback,
        allowNetwork: widget.allowNetwork,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        priority: widget.priority,
        prefetchExtent: widget.prefetchExtent,
      );
    }
    return widget.fallback;
  }
}
""",
)

write(
    "test/channel_logo_resolver_test.dart",
    """import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/channel_logo_resolver_service.dart';

void main() {
  test('normaliza etiquetas técnicas sin borrar el nombre real', () {
    expect(
      ChannelLogoResolverService.normalizeNameForLookup(
        '|AR| ESPN Premium FHD [H265]',
      ),
      'espnpremium',
    );
    expect(
      ChannelLogoResolverService.normalizeNameForLookup(
        'TyC Sports 1080P HEVC',
      ),
      'tycsports',
    );
    expect(
      ChannelLogoResolverService.normalizeNameForLookup('TV Pública HD'),
      'tvpublica',
    );
  });

  test('conserva números que forman parte del nombre del canal', () {
    expect(
      ChannelLogoResolverService.normalizeNameForLookup('Canal 26 HD'),
      'canal26',
    );
  });

  test('prioriza tvg-id y agrega nombre normalizado como respaldo', () {
    const channel = Channel(
      name: 'Telefe FHD',
      url: 'https://example.test/live',
      tvgId: 'Telefe.ar',
    );
    final keys = ChannelLogoResolverService.lookupKeysForChannel(channel);
    expect(keys, contains('id:telefe.ar'));
    expect(keys, contains('name:telefe'));
  });
}
""",
)

replace_once(
    "lib/services/tv_local_store.dart",
    """      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE services (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            source TEXT NOT NULL,
            source_type TEXT NOT NULL,
            is_remote INTEGER NOT NULL,
            display_order INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE app_state (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2: no se borra catalog_snapshots aquí. SectionCatalogService
        // migra cada snapshot válido a archivos y elimina la fila sólo después
        // de confirmar la escritura nueva.
      },
""",
    """      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE services (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            source TEXT NOT NULL,
            source_type TEXT NOT NULL,
            is_remote INTEGER NOT NULL,
            display_order INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE app_state (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await _createRuntimeTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2: no se borra catalog_snapshots aquí. SectionCatalogService
        // migra cada snapshot válido a archivos y elimina la fila sólo después
        // de confirmar la escritura nueva.
        if (oldVersion < 3) await _createRuntimeTables(db);
      },
""",
)

replace_once(
    "lib/services/tv_local_store.dart",
    """    _database = db;
    return db;
  }

  Future<List<Playlist>> loadServices() async {
""",
    """    _database = db;
    return db;
  }

  Future<void> _createRuntimeTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS channel_health (
        channel_key TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        reason TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS channel_logo_cache (
        lookup_key TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<List<Playlist>> loadServices() async {
""",
)

replace_once(
    "lib/services/tv_local_store.dart",
    """  Future<bool> _tableExists(Database db, String table) async {
""",
    """  Future<List<Map<String, Object?>>> loadChannelHealthRows() async {
    final db = await database;
    return db.query(
      'channel_health',
      where: 'expires_at > ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> upsertChannelHealth({
    required String channelKey,
    required String status,
    required String reason,
    required DateTime expiresAt,
  }) async {
    final db = await database;
    await db.insert(
      'channel_health',
      {
        'channel_key': channelKey,
        'status': status,
        'reason': reason,
        'expires_at': expiresAt.millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteChannelHealth(String channelKey) async {
    final db = await database;
    await db.delete(
      'channel_health',
      where: 'channel_key = ?',
      whereArgs: [channelKey],
    );
  }

  Future<void> pruneChannelHealth() async {
    final db = await database;
    await db.delete(
      'channel_health',
      where: 'expires_at <= ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<Map<String, String?>> loadLogoFallbacks(Set<String> keys) async {
    if (keys.isEmpty) return <String, String?>{};
    final db = await database;
    final output = <String, String?>{};
    final values = keys.toList(growable: false);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var offset = 0; offset < values.length; offset += 400) {
      final end = (offset + 400).clamp(0, values.length);
      final chunk = values.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT lookup_key, url FROM channel_logo_cache '
        'WHERE expires_at > ? AND lookup_key IN ($placeholders)',
        <Object?>[now, ...chunk],
      );
      for (final row in rows) {
        final key = row['lookup_key']?.toString() ?? '';
        if (key.isEmpty) continue;
        final rawUrl = row['url']?.toString().trim() ?? '';
        output[key] = rawUrl.isEmpty ? null : rawUrl;
      }
    }
    return output;
  }

  Future<void> saveLogoFallbacks(Map<String, String?> values) async {
    if (values.isEmpty) return;
    final db = await database;
    final now = DateTime.now();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in values.entries) {
        final url = entry.value?.trim() ?? '';
        final ttl = url.isEmpty ? const Duration(days: 1) : const Duration(days: 30);
        batch.insert(
          'channel_logo_cache',
          {
            'lookup_key': entry.key,
            'url': url,
            'expires_at': now.add(ttl).millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> pruneLogoFallbacks() async {
    final db = await database;
    await db.delete(
      'channel_logo_cache',
      where: 'expires_at <= ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<bool> _tableExists(Database db, String table) async {
""",
)

replace_once(
    "lib/widgets/channel_tile.dart",
    """import '../models/channel.dart';
import 'cached_artwork_image.dart';
""",
    """import '../models/channel.dart';
import 'channel_logo_image.dart';
""",
)
replace_once(
    "lib/widgets/channel_tile.dart",
    """          child: CachedArtworkImage(
            url: channel.logoUrl,
            fit: BoxFit.cover,
            cacheWidth: 96,
            allowNetwork: allowNetworkArtwork,
            fallback: const _FallbackIcon(),
          ),
""",
    """          child: ChannelLogoImage(
            channel: channel,
            fit: BoxFit.cover,
            cacheWidth: 96,
            allowNetwork: allowNetworkArtwork,
            fallback: const _FallbackIcon(),
          ),
""",
)

replace_once(
    "lib/screens/channel_list_screen.dart",
    """import '../services/artwork_cache_service.dart';
import '../services/parental_control_service.dart';
import '../widgets/cached_artwork_image.dart';
""",
    """import '../services/artwork_cache_service.dart';
import '../services/channel_logo_resolver_service.dart';
import '../services/parental_control_service.dart';
import '../widgets/cached_artwork_image.dart';
import '../widgets/channel_logo_image.dart';
""",
)
replace_once(
    "lib/screens/channel_list_screen.dart",
    """    final groups = counts.keys.toList()..sort();
    _groups = List.unmodifiable(groups);
    _groupCounts = Map.unmodifiable(counts);
  }
""",
    """    final groups = counts.keys.toList()..sort();
    _groups = List.unmodifiable(groups);
    _groupCounts = Map.unmodifiable(counts);
    if (_mode == _CatalogMode.live || _mode == _CatalogMode.radios) {
      unawaited(
        ChannelLogoResolverService.instance.primeChannels(playlist.channels),
      );
    }
  }
""",
)
replace_once(
    "lib/screens/channel_list_screen.dart",
    """  @override
  Widget build(BuildContext context) {
    final logo = channel.logoUrl?.trim();
    if (logo == null || logo.isEmpty) {
      return _ArtworkFallback(mode: mode);
    }

    return CachedArtworkImage(
      url: logo,
      fit: fit,
      cacheWidth: mode.usesPoster ? 420 : 300,
      fallback: _ArtworkFallback(mode: mode),
    );
  }
""",
    """  @override
  Widget build(BuildContext context) {
    if (!mode.usesPoster) {
      return ChannelLogoImage(
        channel: channel,
        fit: fit,
        cacheWidth: 300,
        fallback: _ArtworkFallback(mode: mode),
      );
    }

    final logo = channel.logoUrl?.trim();
    if (logo == null || logo.isEmpty) {
      return _ArtworkFallback(mode: mode);
    }
    return CachedArtworkImage(
      url: logo,
      fit: fit,
      cacheWidth: 420,
      fallback: _ArtworkFallback(mode: mode),
    );
  }
""",
)

replace_once(
    "lib/screens/xtream_live_screen.dart",
    """import '../services/catalog_index.dart';
import '../services/device_performance_service.dart';
""",
    """import '../services/catalog_index.dart';
import '../services/channel_logo_resolver_service.dart';
import '../services/device_performance_service.dart';
""",
)
replace_once(
    "lib/screens/xtream_live_screen.dart",
    """import '../widgets/cached_artwork_image.dart';
import '../widgets/tv_catalog_category_row.dart';
""",
    """import '../widgets/channel_logo_image.dart';
import '../widgets/tv_catalog_category_row.dart';
""",
)
replace_once(
    "lib/screens/xtream_live_screen.dart",
    """    final built = CatalogIndex<Channel>.build(
      items: data.channels,
      categoryOrder: data.categories,
      nameOf: (item) => item.name,
      categoryOf: (item) => item.group,
      include: (item) => _parental.canShowChannel(item),
    );
    _indexedData = data;
""",
    """    final built = CatalogIndex<Channel>.build(
      items: data.channels,
      categoryOrder: data.categories,
      nameOf: (item) => item.name,
      categoryOf: (item) => item.group,
      include: (item) => _parental.canShowChannel(item),
    );
    unawaited(ChannelLogoResolverService.instance.primeChannels(data.channels));
    _indexedData = data;
""",
)
replace_once(
    "lib/screens/xtream_live_screen.dart",
    """                        child: CachedArtworkImage(
                          url: widget.channel.logoUrl,
                          fit: BoxFit.contain,
                          cacheWidth: 84,
                          cacheHeight: 84,
                          priority: _focused ? 100 : 20,
                          prefetchExtent: 0,
                          fallback: Container(
""",
    """                        child: ChannelLogoImage(
                          channel: widget.channel,
                          fit: BoxFit.contain,
                          cacheWidth: 84,
                          cacheHeight: 84,
                          priority: _focused ? 100 : 20,
                          prefetchExtent: 0,
                          fallback: Container(
""",
)

replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """import '../models/channel.dart';
import '../services/device_performance_service.dart';
import '../widgets/cached_artwork_image.dart';
""",
    """import '../models/channel.dart';
import '../services/channel_health_service.dart';
import '../services/channel_logo_resolver_service.dart';
import '../services/device_performance_service.dart';
import '../widgets/channel_logo_image.dart';
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """  final FocusNode _retryFocus = FocusNode(debugLabel: 'tvfull-pro-live-retry');
  final ScrollController _channelScrollController = ScrollController();
  StreamSubscription<dynamic>? _eventSub;
""",
    """  final FocusNode _retryFocus = FocusNode(debugLabel: 'tvfull-pro-live-retry');
  final ScrollController _channelScrollController = ScrollController();
  final ChannelHealthService _health = ChannelHealthService.instance;
  StreamSubscription<dynamic>? _eventSub;
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """  int _openGeneration = 0;
  int _autoRetryCount = 0;
  List<_LiveAudioTrack> _audioTracks = const <_LiveAudioTrack>[];
""",
    """  int _openGeneration = 0;
  int _autoRetryCount = 0;
  int _healthRecordedGeneration = -1;
  DateTime? _prepareStartedAt;
  List<_LiveAudioTrack> _audioTracks = const <_LiveAudioTrack>[];
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """    try {
      final lowRam = DevicePerformanceService.instance.lowRam;
      var adaptiveLevel = 0;
""",
    """    try {
      final healthReady = _health.ensureLoaded();
      unawaited(ChannelLogoResolverService.instance.primeChannels(widget.playlist));
      final lowRam = DevicePerformanceService.instance.lowRam;
      var adaptiveLevel = 0;
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """      final id = await _player.invokeMethod<int>('initialize', {
        // Perfil aprendido por canal: la primera imagen sigue arrancando con
        // 1 s, pero canales problemáticos reciben más reserva de forma local.
        // LOW_RAM mantiene límites estrictos para no castigar hardware modesto.
        'minBuffer': lowRam ? lowRamMin : normalMin,
        'maxBuffer': lowRam ? lowRamMax : normalMax,
        'bufferForPlayback': 1000,
        'bufferForPlaybackAfterRebuffer':
            lowRam ? lowRamRebuffer : normalRebuffer,
      });
      if (!mounted) return;
""",
    """      final id = await _player.invokeMethod<int>('initialize', {
        // Perfil aprendido por canal: la primera imagen sigue arrancando con
        // 1 s, pero canales problemáticos reciben más reserva de forma local.
        // LOW_RAM mantiene límites estrictos para no castigar hardware modesto.
        'minBuffer': lowRam ? lowRamMin : normalMin,
        'maxBuffer': lowRam ? lowRamMax : normalMax,
        'bufferForPlayback': 1000,
        'bufferForPlaybackAfterRebuffer':
            lowRam ? lowRamRebuffer : normalRebuffer,
      });
      await healthReady;
      if (!mounted) return;
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """    final generation = ++_openGeneration;
    _retryTimer?.cancel();
    if (!preserveRetry) _autoRetryCount = 0;
""",
    """    final generation = ++_openGeneration;
    _retryTimer?.cancel();
    if (!preserveRetry) {
      _autoRetryCount = 0;
      _prepareStartedAt = DateTime.now();
    } else {
      _prepareStartedAt ??= DateTime.now();
    }
    _healthRecordedGeneration = -1;
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """  void _onNativeEvent(dynamic raw) {
""",
    """  void _recordHealthySignal() {
    if (_healthRecordedGeneration == _openGeneration) return;
    final startedAt = _prepareStartedAt;
    final slow = startedAt != null &&
        DateTime.now().difference(startedAt) >= const Duration(milliseconds: 5500);
    _health.markHealthy(_channel, slow: slow);
    _healthRecordedGeneration = _openGeneration;
  }

  void _onNativeEvent(dynamic raw) {
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """      case 'prepared':
      case 'bufferingEnd':
      case 'playing':
        _autoRetryCount = 0;
        setState(() {
""",
    """      case 'prepared':
      case 'bufferingEnd':
      case 'playing':
        _autoRetryCount = 0;
        _recordHealthySignal();
        setState(() {
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """        setState(() => _audioTracks = tracks);
        break;
""",
    """        _recordHealthySignal();
        setState(() => _audioTracks = tracks);
        break;
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """      case 'completed':
        // Media3 nativo ya hizo sus recuperaciones LIVE estilo Hot Player.
        // No repetimos otra cascada desde Dart.
        _finishWithError(
""",
    """      case 'completed':
        // Media3 nativo ya hizo sus recuperaciones LIVE estilo Hot Player.
        // No repetimos otra cascada desde Dart.
        _health.markDead(_channel, reason: 'stream_ended');
        _finishWithError(
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """    final permanentHttp = combined.contains('401') ||
        combined.contains('403') ||
        combined.contains('404');
""",
    """    final permanentHttp = combined.contains('401') ||
        combined.contains('403') ||
        combined.contains('404') ||
        combined.contains('410');
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """    _finishWithError(_friendlyMessage(combined), '$code · $detail');
  }
""",
    """    final shouldCooldown = permanentHttp ||
        combined.contains('tvfull_no_progress') ||
        combined.contains('tvfull_fast_io') ||
        combined.contains('io_bad_http_status') ||
        combined.contains('response_code_5') ||
        combined.contains('network') ||
        combined.contains('timeout') ||
        combined.contains('connection');
    if (shouldCooldown) {
      _health.markDead(_channel, reason: code);
    }
    _finishWithError(_friendlyMessage(combined), '$code · $detail');
  }
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """  void _previous() {
    if (widget.playlist.isEmpty) return;
    _index = (_index - 1 + widget.playlist.length) % widget.playlist.length;
    unawaited(_prepareCurrent());
    _showOverlay();
  }

  void _next() {
    if (widget.playlist.isEmpty) return;
    _index = (_index + 1) % widget.playlist.length;
    unawaited(_prepareCurrent());
    _showOverlay();
  }
""",
    """  int _nextPlayableIndex(int direction) {
    final length = widget.playlist.length;
    if (length <= 1) return _index;
    for (var step = 1; step <= length; step++) {
      final candidate = (_index + direction * step) % length;
      final normalized = candidate < 0 ? candidate + length : candidate;
      if (!_health.isTemporarilyDead(widget.playlist[normalized])) {
        return normalized;
      }
    }
    final fallback = (_index + direction) % length;
    return fallback < 0 ? fallback + length : fallback;
  }

  void _previous() {
    if (widget.playlist.isEmpty) return;
    _index = _nextPlayableIndex(-1);
    unawaited(_prepareCurrent());
    _showOverlay();
  }

  void _next() {
    if (widget.playlist.isEmpty) return;
    _index = _nextPlayableIndex(1);
    unawaited(_prepareCurrent());
    _showOverlay();
  }
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """                    child: CachedArtworkImage(
                      url: _channel.logoUrl,
                      fit: BoxFit.contain,
                      cacheWidth: 68,
                      cacheHeight: 68,
                      prefetchExtent: 0,
                      fallback: const Icon(Icons.live_tv_rounded, size: 20),
                    ),
""",
    """                    child: ChannelLogoImage(
                      channel: _channel,
                      fit: BoxFit.contain,
                      cacheWidth: 68,
                      cacheHeight: 68,
                      prefetchExtent: 0,
                      fallback: const Icon(Icons.live_tv_rounded, size: 20),
                    ),
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """                        final item = widget.playlist[index];
                        final selected = index == _index;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: ListTile(
""",
    """                        final item = widget.playlist[index];
                        final selected = index == _index;
                        final dead = _health.isTemporarilyDead(item);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Opacity(
                            opacity: dead && !selected ? .48 : 1,
                            child: ListTile(
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """                              child: CachedArtworkImage(
                                url: item.logoUrl,
                                fit: BoxFit.contain,
                                cacheWidth: 72,
                                cacheHeight: 72,
                                prefetchExtent: 0,
                                fallback: const Icon(
""",
    """                              child: ChannelLogoImage(
                                channel: item,
                                fit: BoxFit.contain,
                                cacheWidth: 72,
                                cacheHeight: 72,
                                prefetchExtent: 0,
                                fallback: const Icon(
""",
)
replace_once(
    "lib/screens/android_media3_texture_player_screen.dart",
    """                            title: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            onTap: () => _selectChannel(index),
                          ),
                        );
""",
    """                            title: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            subtitle: dead
                                ? const Text(
                                    'No disponible temporalmente',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                    ),
                                  )
                                : null,
                            trailing: dead
                                ? const Icon(
                                    Icons.tv_off_rounded,
                                    size: 18,
                                    color: Colors.white38,
                                  )
                                : null,
                            onTap: () => _selectChannel(index),
                          ),
                          ),
                        );
""",
)

replace_once(
    "pubspec.yaml",
    "version: 1.3.2+24",
    "version: 1.3.3+25",
)
replace_once(
    "pubspec.yaml",
    "# TV FULL PRO 1.3.2+24 live-slow-grace-v24",
    "# TV FULL PRO 1.3.2+24 live-slow-grace-v24\n\n# TV FULL PRO 1.3.3+25 channel-health-and-logo-fallback-v25",
)

print("Applied TV FULL PRO 1.3.3+25 channel health and logo fallback")
