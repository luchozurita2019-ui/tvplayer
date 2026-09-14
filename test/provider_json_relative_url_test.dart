import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/provider_json_catalog_parser.dart';

void main() {
  const parser = ProviderJsonCatalogParser();

  Map<String, Object?> sample(String url) => {
    'name': 'Canal de prueba',
    'type': 'DASH',
    'original_url': url,
    'headers': {
      'Origin': 'https://provider.example.test',
      'Referer': 'https://provider.example.test/',
    },
  };

  String catalog({String? baseUrl, String? streamBaseUrl, required String url}) {
    return jsonEncode({
      if (baseUrl != null) 'base_url': baseUrl,
      if (streamBaseUrl != null) 'stream_base_url': streamBaseUrl,
      'categories': [
        {
          'name': 'Pruebas',
          'samples': [sample(url)],
        },
      ],
    });
  }

  test('resuelve original_url relativa con base_url', () {
    final result = parser.parse(
      catalog(
        baseUrl: 'https://provider.example.test/content/',
        url: 'live/channel/manifest.mpd',
      ),
    );

    expect(result.channels.single.url,
        'https://provider.example.test/content/live/channel/manifest.mpd');
    expect(result.channels.single.streamMimeType, 'application/dash+xml');
    expect(result.warnings, isEmpty);
  });

  test('acepta stream_base_url como alias', () {
    final result = parser.parse(
      catalog(
        streamBaseUrl: 'https://provider.example.test/root',
        url: 'live/channel/manifest.mpd',
      ),
    );

    expect(result.channels.single.url,
        'https://provider.example.test/root/live/channel/manifest.mpd');
  });

  test('ruta relativa sin base del proveedor no se acepta', () {
    expect(
      () => parser.parse(catalog(url: 'live/channel/manifest.mpd')),
      throwsFormatException,
    );
  });

  test('base_url no HTTP/HTTPS se rechaza', () {
    expect(
      () => parser.parse(
        catalog(
          baseUrl: 'file:///tmp/provider/',
          url: 'live/channel/manifest.mpd',
        ),
      ),
      throwsFormatException,
    );
  });
}
