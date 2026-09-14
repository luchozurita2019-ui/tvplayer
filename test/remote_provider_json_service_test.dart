import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/services/remote_provider_json_service.dart';

void main() {
  test(
    'la fuente remota conserva directos y marca los que requieren resolver',
    () async {
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
                'name': 'Protegido',
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

      final normalized = jsonDecode(payload.content) as Map<String, dynamic>;
      final category =
          (normalized['categories'] as List).single as Map<String, dynamic>;
      final samples = category['samples'] as List<dynamic>;
      expect(samples, hasLength(3));
      expect((samples[0] as Map)['resolver_required'], isNull);
      expect((samples[1] as Map)['resolver_required'], isTrue);
      expect((samples[2] as Map)['resolver_required'], isTrue);
      expect((samples[2] as Map).containsKey('drm_license_uri'), isFalse);
    },
  );
}
