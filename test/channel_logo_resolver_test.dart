import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/channel_logo_resolver_service.dart';

void main() {
  test('normaliza etiquetas técnicas sin borrar el nombre real', () {
    expect(
      ChannelLogoResolverService.normalizeNameForLookup(
        '|AR| ESPN Premium FHD [H265]',
      ),
      'espnpremium',
    );
    expect(
      ChannelLogoResolverService.normalizeNameForLookup(
        'TyC Sports 1080P HEVC',
      ),
      'tycsports',
    );
    expect(
      ChannelLogoResolverService.normalizeNameForLookup('TV Pública HD'),
      'tvpublica',
    );
  });

  test('conserva números que forman parte del nombre del canal', () {
    expect(
      ChannelLogoResolverService.normalizeNameForLookup('Canal 26 HD'),
      'canal26',
    );
  });

  test('prioriza tvg-id y agrega nombre normalizado como respaldo', () {
    const channel = Channel(
      name: 'Telefe FHD',
      url: 'https://example.test/live',
      tvgId: 'Telefe.ar',
    );
    final keys = ChannelLogoResolverService.lookupKeysForChannel(channel);
    expect(keys, contains('id:telefe.ar'));
    expect(keys, contains('name:telefe'));
  });
}
