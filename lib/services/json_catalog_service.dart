import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

class JsonCatalogException implements Exception {
  final String message;

  const JsonCatalogException(this.message);

  @override
  String toString() => message;
}

/// Catálogo JSON simple para fuentes LIVE empaquetadas en la APK.
///
/// Formato esperado:
/// {
///   "categories": [
///     {
///       "name": "Categoría",
///       "samples": [
///         {
///           "name": "Canal",
///           "type": "HLS",
///           "original_url": "https://example.invalid/live.m3u8",
///           "icono": "https://example.invalid/logo.png",
///           "headers": {"User-Agent": "...", "Referer": "..."}
///         }
///       ]
///     }
///   ]
/// }
///
/// Para esta prueba sólo se materializan entradas HLS con URL http/https.
class JsonCatalogService {
  JsonCatalogService._();

  static final JsonCatalogService instance = JsonCatalogService._();

  static const String sourcePrefix = 'tvfull-json://';
  static const String bundledSource =
      '${sourcePrefix}assets/playlists/tv_clasica_2.json';
  static const String bundledAssetPath = 'assets/playlists/tv_clasica_2.json';

  bool handlesSource(String source) => source.trim().startsWith(sourcePrefix);

  Future<List<Channel>> fetchCatalog(String source) async {
    final assetPath = _assetPath(source);
    if (assetPath == null) {
      throw const JsonCatalogException('Fuente JSON local inválida.');
    }
    final raw = await rootBundle.loadString(assetPath);
    return parse(raw);
  }

  @visibleForTesting
  List<Channel> parse(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error) {
      throw JsonCatalogException('Catálogo JSON inválido: $error');
    }

    if (decoded is! Map) {
      throw const JsonCatalogException(
        'El catálogo JSON debe contener un objeto principal.',
      );
    }

    final rawCategories = decoded['categories'];
    if (rawCategories is! List) {
      throw const JsonCatalogException(
        'El catálogo JSON no contiene categories.',
      );
    }

    final channels = <Channel>[];
    for (final rawCategory in rawCategories) {
      if (rawCategory is! Map) continue;
      final category = Map<String, dynamic>.from(rawCategory);
      final categoryName = _clean(category['name']);
      final samples = category['samples'];
      if (samples is! List) continue;

      for (final rawSample in samples) {
        if (rawSample is! Map) continue;
        final item = Map<String, dynamic>.from(rawSample);
        final type = (_clean(item['type']) ?? '').toUpperCase();
        if (type != 'HLS') continue;

        final name = _clean(item['name']);
        final url = _clean(item['original_url']) ?? _clean(item['url']);
        if (name == null || url == null) continue;

        final parsed = Uri.tryParse(url);
        if (parsed == null ||
            !(parsed.scheme == 'http' || parsed.scheme == 'https') ||
            parsed.host.isEmpty) {
          continue;
        }

        final icon = _clean(item['icono']);
        final headers = _stringMap(item['headers']);

        channels.add(
          Channel(
            name: name,
            url: parsed.toString(),
            logoUrl: icon != null && !icon.startsWith('data:') ? icon : null,
            group: categoryName ?? _clean(item['category']),
            httpHeaders: headers.isEmpty ? null : headers,
          ),
        );
      }
    }

    if (channels.isEmpty) {
      throw const JsonCatalogException(
        'El catálogo JSON no contiene streams HLS utilizables.',
      );
    }

    return List<Channel>.unmodifiable(channels);
  }

  String? _assetPath(String source) {
    final value = source.trim();
    if (!value.startsWith(sourcePrefix)) return null;
    final path = value.substring(sourcePrefix.length).trim();
    return path.isEmpty ? null : path;
  }

  String? _clean(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  Map<String, String> _stringMap(dynamic raw) {
    if (raw is! Map) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim();
      final value = entry.value?.toString().trim() ?? '';
      if (key.isNotEmpty && value.isNotEmpty) result[key] = value;
    }
    return result;
  }
}
