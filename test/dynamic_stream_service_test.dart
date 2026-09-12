import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/dynamic_stream_service.dart';

void main() {
  const config = """
{
  "name": "TV clásica 2",
  "server": "https://resolver.example",
  "username": "demo-user",
  "password": "demo-pass",
  "resolver": {
    "path": "/stream/gen/{id}",
    "method": "POST"
  },
  "playbackHeaders": {
    "X-App": "tvfull",
    "X-Version": "40",
    "X-Did": "{androidId}",
    "User-Agent": "TV FULL PRO/40"
  }
}
""";

  test('Xtream catalog keeps stream_id and resolves URL only on playback', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path} ${request.url.query}');

      if (request.url.path == '/player_api.php' &&
          request.url.queryParameters['action'] == 'get_live_categories') {
        expect(request.url.queryParameters['username'], 'demo-user');
        expect(request.url.queryParameters['password'], 'demo-pass');
        return http.Response(
          jsonEncode([
            {'category_id': '7', 'category_name': 'Noticias'}
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/player_api.php' &&
          request.url.queryParameters['action'] == 'get_live_streams') {
        return http.Response(
          jsonEncode([
            {
              'stream_id': 1111,
              'name': 'Canal Uno',
              'category_id': '7',
              'stream_icon': 'https://img.example/logo.png',
              'epg_channel_id': 'canal.uno'
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/stream/gen/1111') {
        expect(request.method, 'POST');
        expect(request.bodyFields['id'], '1111');
        expect(request.bodyFields['cast'], 'false');
        expect(request.bodyFields['device'], 'device-test');
        expect(request.bodyFields['code'], '');
        return http.Response(
          'https://resolver.example/stream/secure/session123/1111.m3u8',
          200,
          headers: {'content-type': 'text/plain'},
        );
      }

      return http.Response('not found', 404);
    });

    final service = DynamicStreamService.forTesting(
      configJson: config,
      client: client,
      androidIdProvider: () async => 'device-test',
    );

    final channels = await service.fetchCatalog();
    expect(channels, hasLength(1));
    expect(channels.single.name, 'Canal Uno');
    expect(channels.single.group, 'Noticias');
    expect(channels.single.xtreamStreamId, '1111');
    expect(channels.single.dynamicStreamId, '1111');
    expect(channels.single.url, 'tvfull-dynamic://stream/1111');

    // El catálogo no debe generar todavía ninguna URL temporal.
    expect(calls.where((entry) => entry.contains('/stream/gen/')), isEmpty);

    final resolved = await service.resolve(channels.single);
    expect(
      resolved.url,
      'https://resolver.example/stream/secure/session123/1111.m3u8',
    );
    expect(resolved.headers['X-Did'], 'device-test');
    expect(resolved.headers['User-Agent'], 'TV FULL PRO/40');
    expect(resolved.headers.containsKey('X-Hash'), isFalse);
    expect(calls.where((entry) => entry.contains('/stream/gen/1111')), hasLength(1));
  });

  test('X-Hash is optional and can be injected without changing resolver flow', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/stream/gen/9') {
        return http.Response(
          'https://resolver.example/stream/secure/session456/9.m3u8',
          200,
        );
      }
      return http.Response('[]', 200);
    });

    final service = DynamicStreamService.forTesting(
      configJson: config,
      client: client,
      androidIdProvider: () async => 'device-test',
      xHashOverride: 'session-hash',
    );

    const channel = Channel(
      name: 'Canal 9',
      url: 'tvfull-dynamic://stream/9',
      xtreamStreamId: '9',
      dynamicStreamId: '9',
    );

    final resolved = await service.resolve(channel);
    expect(resolved.headers['X-Did'], 'device-test');
    expect(resolved.headers['X-Hash'], 'session-hash');
  });

  test('dynamic stream id survives Channel JSON cache roundtrip', () {
    const original = Channel(
      name: 'Canal',
      url: 'tvfull-dynamic://stream/9',
      xtreamStreamId: '9',
      dynamicStreamId: '9',
    );
    final restored = Channel.fromJson(original.toJson());
    expect(restored.dynamicStreamId, '9');
    expect(restored.xtreamStreamId, '9');
    expect(restored.uniqueKey, 'Canal|dynamic:9');
  });
}
