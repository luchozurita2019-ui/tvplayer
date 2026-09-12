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
  "catalog": {
    "url": "https://authorized.example/catalog",
    "method": "GET",
    "itemsPath": "channels",
    "fields": {
      "id": ["id"],
      "name": ["name"],
      "group": ["category"],
      "logo": ["logo"]
    }
  },
  "resolver": {
    "url": "https://authorized.example/resolve/{id}",
    "method": "POST",
    "form": {
      "stream_id": "{id}",
      "device_id": "{androidId}"
    },
    "urlPath": "url"
  },
  "playbackHeaders": {
    "X-Device": "{androidId}"
  }
}
""";

  test('catalog creates logical dynamic channels and resolver runs on demand', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/catalog') {
        return http.Response(
          jsonEncode({
            'channels': [
              {
                'id': 1111,
                'name': 'Canal Uno',
                'category': 'Noticias',
                'logo': 'https://img.example/logo.png',
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/resolve/1111') {
        expect(request.method, 'POST');
        expect(request.body, contains('stream_id=1111'));
        expect(request.body, contains('device_id=device-test'));
        return http.Response(
          jsonEncode({'url': 'https://cdn.example/live/1111.m3u8'}),
          200,
          headers: {'content-type': 'application/json'},
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
    expect(channels.single.dynamicStreamId, '1111');
    expect(channels.single.url, 'tvfull-dynamic://stream/1111');

    final resolved = await service.resolve(channels.single);
    expect(resolved.url, 'https://cdn.example/live/1111.m3u8');
    expect(resolved.headers['X-Device'], 'device-test');
  });

  test('dynamic stream id survives Channel JSON cache roundtrip', () {
    const original = Channel(
      name: 'Canal',
      url: 'tvfull-dynamic://stream/9',
      dynamicStreamId: '9',
    );
    final restored = Channel.fromJson(original.toJson());
    expect(restored.dynamicStreamId, '9');
    expect(restored.uniqueKey, 'Canal|dynamic:9');
  });
}
