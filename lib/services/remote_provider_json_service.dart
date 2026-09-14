import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider_json_catalog_parser.dart';
import 'provider_json_document_decoder.dart';

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

/// Descarga el catálogo provider.json y lo entrega al parser sin reescribir
/// sus datos semánticos. Sólo normaliza las irregularidades sintácticas
/// conocidas del archivo de integración del proveedor para producir JSON
/// estricto antes de persistirlo.
class RemoteProviderJsonService {
  RemoteProviderJsonService._();

  static final instance = RemoteProviderJsonService._();

  // Debe coincidir con el catálogo que carga la APK de integración entregada
  // por el proveedor. Sigue siendo reemplazable por dart-define para futuras
  // entregas sin necesidad de modificar el código.
  static const catalogUrl = String.fromEnvironment(
    'TV_FULL_PROVIDER_JSON_URL',
    defaultValue:
        'https://archive.org/download/prueba9_202607/prueba.9/prueba9.json',
  );

  static const _userAgent =
      'TV-FULL-PRO/1.4.18 (Android TV; provider-json-resolver)';

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
        decoded = decodeProviderJsonDocument(text);
      } on FormatException {
        throw const FormatException(
          'El catálogo remoto no contiene JSON compatible.',
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

      for (final rawCategory in decoded['categories'] as List) {
        if (rawCategory is! Map || rawCategory['samples'] is! List) continue;
        for (final rawSample in rawCategory['samples'] as List) {
          if (rawSample is! Map) continue;
          sourceSamples++;

          final url = rawSample['original_url'];
          if (url is! String || url.trim().isEmpty) continue;
          usableSamples++;
          if (!_absoluteHttpUrl(url.trim())) relativeUrlSamples++;

          final license = rawSample['drm_license_uri'];
          if (license is String && license.trim().isNotEmpty) {
            protectedSamples++;
          }
        }
      }

      if (usableSamples == 0) {
        throw const FormatException(
          'El catálogo remoto no contiene canales utilizables.',
        );
      }

      // Persistimos JSON estricto. De esta forma las siguientes lecturas desde
      // disco no vuelven a depender de la sintaxis tolerante del archivo remoto.
      final normalizedContent = jsonEncode(decoded);
      if (utf8.encode(normalizedContent).length >
          ProviderJsonCatalogParser.maxCatalogBytes) {
        throw const FormatException(
          'El catálogo normalizado supera el límite de 16 MB.',
        );
      }

      return RemoteProviderJsonPayload(
        content: normalizedContent,
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
