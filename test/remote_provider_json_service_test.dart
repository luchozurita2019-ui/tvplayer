import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/services/remote_provider_json_service.dart';

void main() {
  test('usa por defecto el mismo catálogo que la APK del proveedor', () {
    expect(
      RemoteProviderJsonService.catalogUrl,
      'https://archive.org/download/prueba9_202607/prueba.9/prueba9.json',
    );
  });

  test('la fuente remota conserva intactos los registros del proveedor', () async {
    final body = jsonEncode({
      'summary': {'categories': 1, 'streams': 3},
      'categories': [
        {
          'name': 'Prueba',
          'samples': [
            {
              'name': 'Directo',
              'type': 'HLS',
              'original_url': 'https://example.test/live/directo.m3u8',
            },
            {
              'name': 'Relativo',
              'type': 'DASH',
              'original_url': 'live/relativo/manifest.mpd',
              'globalIndex': 22,
            },
            {
              'name': 'Con licencia de prueba',
              'type': 'DASH',
              'original_url': 'https://example.test/live/protegido.mpd',
              'drm_license_uri': 'synthetic-test-marker',
              'globalIndex': 23,
            },
          ],
        },
      ],
    });

    final client = MockClient((request) async => http.Response(body, 200));
    final payload = await RemoteProviderJsonService.instance.fetch(
      client: client,
    );

    expect(payload.sourceSamples, 3);
    expect(payload.usableSamples, 3);
    expect(payload.relativeUrlSamples, 1);
    expect(payload.protectedSamples, 1);

    final received = jsonDecode(payload.content) as Map<String, dynamic>;
    final category =
        (received['categories'] as List).single as Map<String, dynamic>;
    final samples = category['samples'] as List<dynamic>;
    expect(samples, hasLength(3));
    expect((samples[0] as Map)['resolver_required'], isNull);
    expect((samples[1] as Map)['resolver_required'], isNull);
    expect((samples[1] as Map)['globalIndex'], 22);
    expect((samples[2] as Map)['drm_license_uri'], 'synthetic-test-marker');
    expect(payload.content, body);
  });
  test('normaliza groups -> stations -> options antes de persistir', () async {
    final body = jsonEncode({
      'groups': [
        {
          'name': 'Lista 2',
          'stations': [
            {
              'name': 'Canal normal',
              'options': [
                {
                  'name': 'Canal normal HD',
                  'url': 'https://example.test/live/canal.m3u8',
                  'headers': {'Referer': 'https://example.test/'},
                },
                {
                  'name': 'Canal protegido',
                  'url': 'https://example.test/live/protegido.mpd',
                  'license_type': 'clearkey',
                  'license_key': {
                    'keys': [
                      {
                        'kty': 'oct',
                        'kid': '00112233445566778899aabbccddeeff',
                        'k': 'ffeeddccbbaa99887766554433221100',
                      },
                    ],
                    'type': 'temporary',
                  },
                },
              ],
            },
          ],
        },
      ],
    });

    final client = MockClient((request) async => http.Response(body, 200));
    final payload = await RemoteProviderJsonService.instance.fetch(
      client: client,
    );

    final received = jsonDecode(payload.content) as Map<String, dynamic>;
    expect(received['groups'], isNull);
    final categories = received['categories'] as List<dynamic>;
    expect(categories, hasLength(1));

    final category = categories.single as Map<String, dynamic>;
    final samples = category['samples'] as List<dynamic>;
    expect(samples, hasLength(2));
    expect((samples[0] as Map)['original_url'],
        'https://example.test/live/canal.m3u8');
    expect((samples[0] as Map)['headers']['Referer'],
        'https://example.test/');
    expect((samples[1] as Map)['drm_license_uri'],
        'kid:00112233445566778899aabbccddeeff,k:ffeeddccbbaa99887766554433221100');

    expect(payload.sourceSamples, 2);
    expect(payload.usableSamples, 2);
    expect(payload.protectedSamples, 1);
    expect(payload.relativeUrlSamples, 0);
  });

}
