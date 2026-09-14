import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/clearkey_drm_config.dart';
import 'package:iptv_player/services/dynamic_stream_service.dart';
import 'package:iptv_player/services/provider_flow_stream_service.dart';
import 'package:iptv_player/services/provider_json_catalog_parser.dart';

void main() {
  test('ClearKey del proveedor acepta Base64URL de 16 bytes', () {
    final config = ClearKeyDrmConfig.parse(
      'kid:AAECAwQFBgcICQoLDA0ODw,k:_____________________w',
    );

    expect(config.keyId, '000102030405060708090a0b0c0d0e0f');
    expect(config.key, 'ffffffffffffffffffffffffffffffff');

    final jwk = jsonDecode(config.toJwkSet()) as Map<String, dynamic>;
    final keys = jwk['keys'] as List<dynamic>;
    expect(keys.single['kid'], 'AAECAwQFBgcICQoLDA0ODw');
    expect(keys.single['k'], '_____________________w');
  });

  test('provider.json marca Flow absoluto como dinámico y conserva ClearKey', () {
    final catalog = const ProviderJsonCatalogParser().parse(
      jsonEncode({
        'categories': [
          {
            'name': 'Prueba',
            'samples': [
              {
                'name': 'Canal Flow demo',
                'type': 'CLEARKEY',
                'original_url':
                    'https://cdn-token.app.flow.com.ar/generator?path=https://cdn-flow.example/live/c3eds/Demo/SA_Live_dash_enc/Demo.mpd',
                'drm_license_uri':
                    'kid:AAECAwQFBgcICQoLDA0ODw,k:_____________________w',
                'headers': {
                  'Origin': 'https://portal.app.flow.com.ar',
                  'Referer': 'https://portal.app.flow.com.ar/',
                  'User-Agent': 'Provider Integration Test',
                },
                'globalIndex': 37,
              },
            ],
          },
        ],
      }),
    );

    final channel = catalog.channels.single;
    expect(channel.dynamicStreamId, '37');
    expect(channel.dynamicStreamPath, contains('live/c3eds/Demo/'));
    expect(channel.providerGlobalIndex, '37');
    expect(channel.url, startsWith(DynamicStreamService.streamPrefix));
    expect(channel.streamMimeType, 'application/dash+xml');
    expect(channel.drmKeyId, '000102030405060708090a0b0c0d0e0f');
    expect(channel.drmKey, 'ffffffffffffffffffffffffffffffff');
  });

  test('Flow resolver obtiene host/token por redirect y arma URL del canal', () async {
    var probes = 0;
    final flowClient = MockClient((request) async {
      probes++;
      expect(request.method, 'GET');
      expect(
        request.headers['User-Agent'],
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/132.0.0.0 Safari/537.36',
      );
      return http.Response(
        '',
        302,
        headers: {
          'location':
              'https://edge.example/tok_demo_session/live/c6eds/Seed/manifest.mpd',
        },
      );
    });

    final flow = ProviderFlowStreamService.forTesting(
      client: flowClient,
      seeds: const ['https://seed.example/live/c6eds/Seed/manifest.mpd'],
    );

    const first = Channel(
      name: 'Canal A',
      url: 'tvfull-dynamic://stream/37',
      dynamicStreamId: '37',
      dynamicStreamPath: 'live/c3eds/Demo/SA_Live_dash_enc/Demo.mpd',
      httpHeaders: {
        'Referer': 'https://portal.app.flow.com.ar/',
        'User-Agent': 'Provider Integration Test',
      },
    );
    const second = Channel(
      name: 'Canal B',
      url: 'tvfull-dynamic://stream/38',
      dynamicStreamId: '38',
      dynamicStreamPath: 'live/c4eds/Other/SA_Live_dash_enc/Other.mpd',
      httpHeaders: {'User-Agent': 'Provider Integration Test'},
    );

    final resolvedA = await flow.resolve(first);
    final resolvedB = await flow.resolve(second);

    expect(
      resolvedA.url,
      'https://edge.example/tok_demo_session/live/c3eds/Demo/SA_Live_dash_enc/Demo.mpd',
    );
    expect(
      resolvedB.url,
      'https://edge.example/tok_demo_session/live/c4eds/Other/SA_Live_dash_enc/Other.mpd',
    );
    expect(resolvedA.headers['Referer'], 'https://portal.app.flow.com.ar/');
    expect(resolvedA.headers['User-Agent'], 'Provider Integration Test');
    expect(probes, 1, reason: 'el segundo canal debe reutilizar el token fresco');
  });

  test('DynamicStreamService prioriza Flow sobre el resolver stream_id', () async {
    var flowCalls = 0;
    var legacyCalls = 0;

    final flow = ProviderFlowStreamService.forTesting(
      client: MockClient((request) async {
        flowCalls++;
        return http.Response(
          '',
          302,
          headers: {
            'location':
                'https://edge.example/tok_flow/live/c6eds/Seed/manifest.mpd',
          },
        );
      }),
      seeds: const ['https://seed.example/live/c6eds/Seed/manifest.mpd'],
    );

    final service = DynamicStreamService.forTesting(
      configJson: jsonEncode({
        'server': 'https://legacy-resolver.example',
        'resolver': {'path': '/stream/gen/{id}', 'method': 'POST'},
      }),
      client: MockClient((request) async {
        legacyCalls++;
        return http.Response('https://legacy.example/stream.m3u8', 200);
      }),
      androidIdProvider: () async => 'device-test',
      flowService: flow,
    );

    const channel = Channel(
      name: 'Canal proveedor',
      url: 'tvfull-dynamic://stream/37',
      dynamicStreamId: '37',
      dynamicStreamPath: 'live/c3eds/Demo/SA_Live_dash_enc/Demo.mpd',
      providerGlobalIndex: '37',
      httpHeaders: {'User-Agent': 'Provider Integration Test'},
    );

    final resolved = await service.resolve(channel);
    expect(resolved.url, contains('/tok_flow/live/c3eds/Demo/'));
    expect(flowCalls, 1);
    expect(legacyCalls, 0);
  });
}
