import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/services/provider_json_catalog_parser.dart';
import 'package:iptv_player/services/remote_provider_json_service.dart';

void main() {
  test('remote provider normaliza las irregularidades del catálogo de prueba', () async {
    const malformed = '''
{
  "summary": {"categories": 1, "streams": 1"},
  "categories": [
    {
      "name": "Interior",
      "samples": [
        {
          "name": "Canal prueba",
          "type": "HLS",
          "original_url": "https://example.test/live.m3u8",
          "globalIndex": ·,
          "category": "Interior",
          "source_group": "samples"
        }
      ]
    }
  ]
}
''';

    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response(
        malformed,
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final payload = await RemoteProviderJsonService.instance.fetch(client: client);

    expect(payload.sourceSamples, 1);
    expect(payload.usableSamples, 1);
    expect(payload.relativeUrlSamples, 0);

    final decoded = jsonDecode(payload.content) as Map<String, dynamic>;
    expect((decoded['summary'] as Map<String, dynamic>)['streams'], 1);
    final sample = (((decoded['categories'] as List).single
            as Map<String, dynamic>)['samples'] as List)
        .single as Map<String, dynamic>;
    expect(sample['globalIndex'], isNull);

    final catalog = const ProviderJsonCatalogParser().parse(payload.content);
    expect(catalog.channels.single.name, 'Canal prueba');
  });

  test('sintaxis desconocida sigue siendo rechazada', () async {
    const malformed = '{"categories": [ definitely-not-json ]}';
    final client = MockClient((request) async => http.Response(malformed, 200));

    expect(
      () => RemoteProviderJsonService.instance.fetch(client: client),
      throwsA(isA<FormatException>()),
    );
  });
}
