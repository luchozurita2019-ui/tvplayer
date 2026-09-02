import 'dart:async';
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
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: true);
    if (tokens.isNotEmpty && (tokens.first == 'ar' || tokens.first == 'arg')) {
      tokens.removeAt(0);
    }
    if (tokens.isNotEmpty && (tokens.last == 'ar' || tokens.last == 'arg')) {
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
    if (stillPending.isNotEmpty && stillPending.any(_pendingKeys.contains)) {
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
    try {
      final request = http.Request('GET', _logosUri)
        ..headers['Accept'] = 'application/json';
      final response =
          await client.send(request).timeout(const Duration(seconds: 8));
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
    } catch (_) {
      return;
    } finally {
      client.close();
    }

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
          } else if (char == r'\') {
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
