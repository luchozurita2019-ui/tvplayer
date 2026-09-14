import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/services/remote_provider_json_service.dart';

void main() {
  test('la fuente remota conserva solo URLs directas sin DRM', () async {
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
              'headers': {'Referer': 'https://example.test/'},
            },
            {
              'name': 'Relativo',
              'type': 'DASH',
              'original_url': 'live/relativo/manifest.mpd',
            },
            {
              'name': 'Protegido',
              'type': 'DASH',
              'original_url': 'https://example.test/live/protegido.mpd',
              'drm_license_uri': 'kid:AAAAAAAAAAAAAAAAAAAAAA,k:BBBBBBBBBBBBBBBBBBBBBB',
            },
          ],
        },
      ],
    });

    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.headers['User-Agent'], contains('TV-FULL-PRO'));
      return http.Response(
        body,
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final payload = await RemoteProviderJsonService.instance.fetch(
      client: client,
    );

    expect(payload.sourceSamples, 3);
    expect(payload.usableSamples, 1);
    expect(payload.relativeUrlSamples, 1);
    expect(payload.protectedSamples, 1);

    final normalized = jsonDecode(payload.content) as Map<String, dynamic>;
    final summary = normalized['summary'] as Map<String, dynamic>;
    expect(summary['categories'], 1);
    expect(summary['streams'], 1);

    final categories = normalized['categories'] as List<dynamic>;
    final category = categories.single as Map<String, dynamic>;
    final samples = category['samples'] as List<dynamic>;
    final sample = samples.single as Map<String, dynamic>;
    expect(sample['name'], 'Directo');
    expect(sample['original_url'], 'https://example.test/live/directo.m3u8');
    expect(sample.containsKey('drm_license_uri'), isFalse);
  });
}
