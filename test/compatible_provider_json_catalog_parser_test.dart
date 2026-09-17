import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/compatible_provider_json_catalog_parser.dart';

void main() {
  test('imports data.channelList as dynamic Lista TV 3 channels', () {
    const token = 'SECRET_TOKEN_SHOULD_NOT_REACH_CHANNEL';
    final source = jsonEncode({
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

    final catalog = const CompatibleProviderJsonCatalogParser().parse(source);

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
}
