import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

/// Fallback de logos local y liviano.
///
/// A diferencia de v25, nunca recorre un catálogo remoto durante la navegación.
/// El índice se genera al compilar a partir de la Lista clásica empaquetada y se
/// carga una sola vez, sólo cuando realmente falta un logo del proveedor.
class ChannelLogoResolverService {
  ChannelLogoResolverService._();

  static final ChannelLogoResolverService instance =
      ChannelLogoResolverService._();

  static const String _indexAsset =
      'assets/playlists/lista_clasica_logo_index.json';

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
    'opc',
    'opcion',
  };

  static const Map<String, String> _aliases = <String, String>{
    'televisionpublica': 'tvpublica',
    'tvpublicaargentina': 'tvpublica',
    'tycsport': 'tycsports',
    'cronicahd': 'cronicatv',
    'cronica': 'cronicatv',
    'eltrecehd': 'eltrece',
  };

  final Map<String, String> _values = <String, String>{};
  bool _loaded = false;
  Future<void>? _loadFuture;

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

  /// v26: no se hace ningún trabajo de logos al entrar al catálogo.
  Future<void> primeChannels(Iterable<Channel> channels) async {}

  Future<String?> resolveFallback(
    Channel channel, {
    bool allowNetwork = true,
  }) async {
    await _ensureLoaded();
    for (final key in lookupKeysForChannel(channel)) {
      final value = _values[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final active = _loadFuture;
    if (active != null) {
      await active;
      return;
    }

    final future = _loadLocalIndex();
    _loadFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loadFuture, future)) _loadFuture = null;
    }
  }

  Future<void> _loadLocalIndex() async {
    try {
      final raw = await rootBundle.loadString(_indexAsset);
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = entry.key.toString().trim();
          final value = entry.value?.toString().trim() ?? '';
          if (key.isNotEmpty && value.isNotEmpty) _values[key] = value;
        }
      }
    } catch (_) {
      // El fallback visual es opcional y nunca debe trabar TV FULL PRO.
    } finally {
      _loaded = true;
    }
  }
}
