import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider_json_catalog_parser.dart';

class RemoteProviderJsonPayload {
  final String content;
  final int sourceSamples;
  final int usableSamples;
  final int protectedSamples;
  final int relativeUrlSamples;

  const RemoteProviderJsonPayload({
    required this.content,
    required this.sourceSamples,
    required this.usableSamples,
    required this.protectedSamples,
    required this.relativeUrlSamples,
  });
}

/// Fuente remota integrada para la prueba automática del catálogo provider.json.
///
/// La URL queda compilada dentro de la APK, pero puede reemplazarse en CI con
/// --dart-define=TV_FULL_PROVIDER_JSON_URL=... sin tocar M3U/Xtream/Stalker.
///
/// La fuente remota conserva el catálogo completo. Las rutas relativas y las
/// entradas protegidas se marcan para resolución justo antes de reproducir.
/// El material DRM remoto no se propaga: un resolvedor autorizado debe
/// devolver la URL/sesión reproducible. El ClearKey local sigue disponible.
class RemoteProviderJsonService {
  RemoteProviderJsonService._();

  static final instance = RemoteProviderJsonService._();

  static const catalogUrl = String.fromEnvironment(
    'TV_FULL_PROVIDER_JSON_URL',
    defaultValue: 'https://raw.githubusercontent.com/monchotv/MonchoApps/main/original_url.json',
  );

  static const _userAgent =
      'TV-FULL-PRO/1.4.15 (Android TV; provider-json-remote-test)';

  Future<RemoteProviderJsonPayload> fetch({http.Client? client}) async {
    final ownClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.tryParse(catalogUrl);
      if (uri == null ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.host.isEmpty) {
        throw const FormatException('La URL del catálogo remoto es inválida.');
      }

      final request = http.Request('GET', uri)
        ..headers.addAll(const {
          'Accept': 'application/json,text/plain;q=0.9,*/*;q=0.1',
          'User-Agent': _userAgent,
          'Cache-Control': 'no-cache',
        });
      final response = await httpClient
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException(
          'El servidor del catálogo respondió ${response.statusCode}.',
        );
      }

      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (bytes.length + chunk.length >
            ProviderJsonCatalogParser.maxCatalogBytes) {
          throw const FormatException(
            'El catálogo remoto supera el límite de 16 MB.',
          );
        }
        bytes.addAll(chunk);
      }

      final text = utf8.decode(bytes);
      dynamic decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw const FormatException(
          'El catálogo remoto no contiene JSON válido.',
        );
      }
      if (decoded is! Map || decoded['categories'] is! List) {
        throw const FormatException(
          'El catálogo remoto no contiene categories válidas.',
        );
      }

      var sourceSamples = 0;
      var usableSamples = 0;
      var protectedSamples = 0;
      var relativeUrlSamples = 0;
      final categories = <Map<String, Object?>>[];

      for (final rawCategory in decoded['categories'] as List) {
        if (rawCategory is! Map || rawCategory['samples'] is! List) continue;
        final samples = <Map<String, Object?>>[];
        for (final rawSample in rawCategory['samples'] as List) {
          if (rawSample is! Map) continue;
          sourceSamples++;
          final sample = Map<String, Object?>.from(rawSample);
          final url = sample['original_url'];
          if (url is! String || url.trim().isEmpty) continue;
          final relative = !_absoluteHttpUrl(url.trim());
          if (relative) relativeUrlSamples++;

          final drm = sample['drm_license_uri'];
          final protected = drm is String && drm.trim().isNotEmpty;
          if (protected) protectedSamples++;

          if (relative || protected) {
            sample['resolver_required'] = true;
          }
          sample.remove('drm_license_uri');
          samples.add(sample);
          usableSamples++;
        }

        if (samples.isEmpty) continue;
        categories.add({
          'name': rawCategory['name'] is String
              ? rawCategory['name'] as String
              : 'Sin categoría',
          'samples': samples,
        });
      }

      if (usableSamples == 0) {
        throw const FormatException(
          'El catálogo remoto no contiene canales utilizables.',
        );
      }

      final normalized = <String, Object?>{
        'summary': {'categories': categories.length, 'streams': usableSamples},
        'categories': categories,
      };

      return RemoteProviderJsonPayload(
        content: jsonEncode(normalized),
        sourceSamples: sourceSamples,
        usableSamples: usableSamples,
        protectedSamples: protectedSamples,
        relativeUrlSamples: relativeUrlSamples,
      );
    } finally {
      if (ownClient) httpClient.close();
    }
  }

  bool _absoluteHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }
}
