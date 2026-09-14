import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/dynamic_stream_service.dart';
import 'package:iptv_player/services/provider_json_catalog_parser.dart';

void main() {
  test('provider.json conserva una ruta relativa como canal dinámico', () {
    final result = const ProviderJsonCatalogParser().parse(
      jsonEncode({
        'categories': [
          {
            'name': 'Deportes',
            'samples': [
              {
                'name': 'Canal demo',
                'type': 'DASH',
                'original_url': 'live/demo/manifest.mpd',
                'globalIndex': 42,
                'resolver_required': true,
              },
            ],
          },
        ],
      }),
    );

    final channel = result.channels.single;
    expect(channel.dynamicStreamId, '42');
    expect(channel.dynamicStreamPath, 'live/demo/manifest.mpd');
    expect(channel.providerGlobalIndex, '42');
    expect(channel.streamMimeType, 'application/dash+xml');
    expect(channel.url, startsWith(DynamicStreamService.streamPrefix));

    final restored = Channel.fromJson(channel.toJson());
    expect(restored.dynamicStreamId, '42');
    expect(restored.dynamicStreamPath, 'live/demo/manifest.mpd');
    expect(restored.providerGlobalIndex, '42');
  });

  test(
    'resolver-only usa id, path, globalIndex y Android ID al abrir',
    () async {
      const config = r'''
{
  "name": "Proveedor JSON",
  "server": "https://resolver.example",
  "resolver": {
    "path": "/resolve/{id}",
    "method": "POST",
    "form": {
      "id": "{id}",
      "path": "{path}",
      "index": "{globalIndex}",
      "device": "{androidId}"
    }
  },
  "playbackHeaders": {
    "X-Device": "{androidId}",
    "User-Agent": "TV FULL PRO provider test"
  }
}
''';

      final client = MockClient((request) async {
        expect(request.url.path, '/resolve/42');
        expect(request.bodyFields['id'], '42');
        expect(request.bodyFields['path'], 'live/demo/manifest.mpd');
        expect(request.bodyFields['index'], '42');
        expect(request.bodyFields['device'], 'device-demo');
        return http.Response('https://cdn.example/live/demo.mpd', 200);
      });

      final service = DynamicStreamService.forTesting(
        configJson: config,
        client: client,
        androidIdProvider: () async => 'device-demo',
      );

      const channel = Channel(
        name: 'Canal demo',
        url: 'tvfull-dynamic://stream/42',
        dynamicStreamId: '42',
        dynamicStreamPath: 'live/demo/manifest.mpd',
        providerGlobalIndex: '42',
      );
      final resolved = await service.resolve(channel);
      expect(resolved.url, 'https://cdn.example/live/demo.mpd');
      expect(resolved.headers['X-Device'], 'device-demo');
    },
  );

  test('sesión del proveedor agrega headers autorizados y respeta caché', () async {
    const config = r'''
{
  "name": "Proveedor JSON",
  "server": "https://resolver.example",
  "resolver": {
    "path": "/resolve/{id}",
    "method": "POST",
    "form": {
      "id": "{id}",
      "path": "{path}",
      "index": "{globalIndex}",
      "device": "{androidId}"
    }
  },
  "session": {
    "path": "/tvfull/session",
    "method": "POST",
    "scope": "stream",
    "ttlSeconds": 60,
    "form": {
      "device": "{androidId}",
      "stream_id": "{id}",
      "path": "{path}"
    }
  },
  "playbackHeaders": {
    "User-Agent": "TV FULL PRO provider test"
  }
}
''';

    var resolverCalls = 0;
    var sessionCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/resolve/42') {
        resolverCalls++;
        expect(request.bodyFields['path'], 'live/demo/manifest.mpd');
        return http.Response('https://cdn.example/live/demo.mpd', 200);
      }
      if (request.url.path == '/tvfull/session') {
        sessionCalls++;
        expect(request.bodyFields['device'], 'device-demo');
        expect(request.bodyFields['stream_id'], '42');
        expect(request.bodyFields['path'], 'live/demo/manifest.mpd');
        return http.Response(
          jsonEncode({
            'headers': {'X-Session-Token': 'issued-demo'},
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final service = DynamicStreamService.forTesting(
      configJson: config,
      client: client,
      androidIdProvider: () async => 'device-demo',
    );

    const channel = Channel(
      name: 'Canal demo',
      url: 'tvfull-dynamic://stream/42',
      dynamicStreamId: '42',
      dynamicStreamPath: 'live/demo/manifest.mpd',
      providerGlobalIndex: '42',
    );

    final first = await service.resolve(channel);
    final second = await service.resolve(channel);

    expect(first.url, 'https://cdn.example/live/demo.mpd');
    expect(first.headers['X-Session-Token'], 'issued-demo');
    expect(first.headers['X-Did'], 'device-demo');
    expect(second.headers['X-Session-Token'], 'issued-demo');
    expect(resolverCalls, 2);
    expect(sessionCalls, 1);
  });
}
