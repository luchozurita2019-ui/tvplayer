import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/provider_flow_stream_service.dart';

void main() {
  test('reintentar el mismo canal renueva el token Flow', () async {
    var probes = 0;
    final flow = ProviderFlowStreamService.forTesting(
      client: MockClient((request) async {
        probes++;
        final token = probes == 1 ? 'tok_first' : 'tok_second';
        return http.Response(
          '',
          302,
          headers: {
            'location':
                'https://edge.example/$token/live/c6eds/Seed/manifest.mpd',
          },
        );
      }),
      seeds: const ['https://seed.example/live/c6eds/Seed/manifest.mpd'],
    );

    const channel = Channel(
      name: 'Canal proveedor',
      url: 'tvfull-dynamic://stream/37',
      dynamicStreamId: '37',
      dynamicStreamPath: 'live/c3eds/Demo/SA_Live_dash_enc/Demo.mpd',
      httpHeaders: {'User-Agent': 'Provider Integration Test'},
    );

    final first = await flow.resolve(channel);
    final retry = await flow.resolve(channel);

    expect(first.url, contains('/tok_first/live/c3eds/Demo/'));
    expect(retry.url, contains('/tok_second/live/c3eds/Demo/'));
    expect(probes, 2, reason: 'el reintento no debe reutilizar el token previo');
  });
}
