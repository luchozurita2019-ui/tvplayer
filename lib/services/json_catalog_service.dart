import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';

class JsonCatalogException implements Exception {
  final String message;
  const JsonCatalogException(this.message);
  @override
  String toString() => message;
}

class JsonCatalogService {
  JsonCatalogService._();
  static final JsonCatalogService instance = JsonCatalogService._();

  static const String sourcePrefix = 'tvfull-json://';
  static const String bundledSource = '${sourcePrefix}remote';
  static const String _compiledCatalogUrl = String.fromEnvironment(
    'TV_FULL_JSON_CATALOG_URL',
    defaultValue: '',
  );

  final http.Client _client = http.Client();

  bool handlesSource(String source) => source.trim().startsWith(sourcePrefix);

  Future<List<Channel>> fetchCatalog(String source) async {
    if (!handlesSource(source)) {
      throw const JsonCatalogException('Fuente JSON invalida.');
    }
    final value = _compiledCatalogUrl.trim();
    if (value.isEmpty) {
      throw const JsonCatalogException('Falta configurar el catalogo JSON.');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw const JsonCatalogException('URL de catalogo JSON invalida.');
    }

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {
            'User-Agent': 'TV FULL PRO JSON Catalog Test/43',
            'Accept': 'application/json,text/plain,*/*',
          })
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const JsonCatalogException('El catalogo JSON no respondio a tiempo.');
    } catch (_) {
      throw const JsonCatalogException('No se pudo descargar el catalogo JSON.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JsonCatalogException('El catalogo JSON respondio HTTP ${response.statusCode}.');
    }

    return parse(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

  List<Channel> parse(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      final repaired = raw
          .replaceFirstMapped(
            RegExp(r'("streams"\s*:\s*\d+)"'),
            (match) => match.group(1)!,
          )
          .replaceAll('"globalIndex": ·,', '"globalIndex": null,');
      try {
        decoded = jsonDecode(repaired);
      } catch (error) {
        throw JsonCatalogException('Catalogo JSON invalido: $error');
      }
    }

    if (decoded is! Map) {
      throw const JsonCatalogException('El catalogo JSON debe contener un objeto principal.');
    }
    final rawCategories = decoded['categories'];
    if (rawCategories is! List) {
      throw const JsonCatalogException('El catalogo JSON no contiene categories.');
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
        final headers = <String, String>{};
        for (final key in const ['headers', 'headersM3u8', 'headersUrl', 'headers2']) {
          headers.addAll(_stringMap(item[key]));
        }

        channels.add(Channel(
          name: name,
          url: parsed.toString(),
          logoUrl: icon != null && !icon.startsWith('data:') ? icon : null,
          group: categoryName ?? _clean(item['category']),
          httpHeaders: headers.isEmpty ? null : headers,
        ));
      }
    }

    if (channels.isEmpty) {
      throw const JsonCatalogException('El catalogo JSON no contiene streams utilizables.');
    }
    return List<Channel>.unmodifiable(channels);
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
