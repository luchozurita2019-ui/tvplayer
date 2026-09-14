import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/dynamic_stream_service.dart';
import 'package:iptv_player/services/provider_flow_stream_service.dart';
import 'package:iptv_player/services/provider_json_catalog_parser.dart';

void main() {
  test('canal c7eds del interior usa el resolver Flow y conserva DRM', () {
    final catalog = const ProviderJsonCatalogParser().parse(
      jsonEncode({
        'categories': [
          {
            'name': 'INTERIOR DE ARGENTINA',
            'samples': [
              {
                'name': 'Canal local de prueba',
                'type': 'CLEARKEY',
                'original_url':
                    'live/c7eds/Ch10_Tucuman/SA_Live_dash_enc/Ch10_Tucuman.mpd',
                'drm_license_uri':
                    'kid:AAECAwQFBgcICQoLDA0ODw,k:EBESExQVFhcYGRobHB0eHw',
                'headers': {
                  'Origin': 'https://portal.app.flow.com.ar',
                  'Referer': 'https://portal.app.flow.com.ar/',
                  'User-Agent': 'Provider channel playback agent',
                },
                'globalIndex': 68,
              },
            ],
          },
        ],
      }),
    );

    final channel = catalog.channels.single;
    expect(channel.group, 'INTERIOR DE ARGENTINA');
    expect(channel.dynamicStreamId, '68');
    expect(channel.providerGlobalIndex, '68');
    expect(
      channel.dynamicStreamPath,
      'live/c7eds/Ch10_Tucuman/SA_Live_dash_enc/Ch10_Tucuman.mpd',
    );
    expect(channel.url, startsWith(DynamicStreamService.streamPrefix));
    expect(channel.streamMimeType, 'application/dash+xml');
    expect(channel.hasDrmConfiguration, isTrue);
    expect(ProviderFlowStreamService.instance.handles(channel), isTrue);
  });
}
