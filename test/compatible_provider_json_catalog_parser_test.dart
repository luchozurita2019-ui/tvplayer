import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/compatible_provider_json_catalog_parser.dart';

String _catalog({String token = 'SECRET_TOKEN_SHOULD_NOT_REACH_CHANNEL'}) {
  return jsonEncode({
    'data': {
      'channelList': [
        {
          'name': 'Canal de prueba',
          'channelCode': 'cyx_demo_720p',
          'channelNumber': '101',
          'posterUrl': 'https://example.com/logo.png',
          'liveAddressList': [
            {
              'playCode': 'cyx_demo_720p',
              'cdnType': '4',
              'quality': '1',
              'AVFormat': 'ts',
              'tag': 'free',
              'license': 'media_code=cyx_demo_720p&token=$token',
            },
          ],
        },
      ],
    },
  });
}

void main() {
  test('imports data.channelList as dynamic Lista TV 3 channels', () {
    const token = 'SECRET_TOKEN_SHOULD_NOT_REACH_CHANNEL';
    final catalog = const CompatibleProviderJsonCatalogParser().parse(
      _catalog(token: token),
    );

    expect(catalog.channels, hasLength(1));
    final channel = catalog.channels.single;
    expect(channel.name, 'Canal de prueba');
    expect(channel.group, 'Lista TV 3');
    expect(channel.tvgId, 'cyx_demo_720p');
    expect(channel.dynamicStreamId, 'cyx_demo_720p');
    expect(channel.dynamicStreamPath, 'cyx_demo_720p');
    expect(channel.providerGlobalIndex, '101');
    expect(channel.url, 'tvfull-dynamic://stream/cyx_demo_720p');
    expect(channel.streamMimeType, 'video/mp2t');
    expect(channel.toJson().toString(), isNot(contains(token)));
  });

  test('uses an authorized HTTP resolver without changing the normal player', () {
    const parser = CompatibleProviderJsonCatalogParser(
      resolverUrl: 'https://resolver.example.test/resolve?source=lista3',
    );
    final catalog = parser.parse(_catalog());
    final channel = catalog.channels.single;
    final uri = Uri.parse(channel.url);

    expect(uri.scheme, 'https');
    expect(uri.host, 'resolver.example.test');
    expect(uri.path, '/resolve');
    expect(uri.queryParameters['source'], 'lista3');
    expect(uri.queryParameters['channelCode'], 'cyx_demo_720p');
    expect(uri.queryParameters['playCode'], 'cyx_demo_720p');
    expect(uri.queryParameters['name'], 'Canal de prueba');
    expect(uri.queryParameters['channelNumber'], '101');
    expect(channel.dynamicStreamId, isNull);
    expect(channel.dynamicStreamPath, 'cyx_demo_720p');
  });
}
