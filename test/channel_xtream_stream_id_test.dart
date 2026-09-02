import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';

void main() {
  test('Channel conserva xtreamStreamId al serializar', () {
    const channel = Channel(
      name: 'Canal prueba',
      url: 'https://cdn.example.test/direct/live-token',
      tvgId: 'guide.channel',
      xtreamStreamId: '12345',
    );

    final restored = Channel.fromJson(channel.toJson());
    expect(restored.xtreamStreamId, '12345');
    expect(restored.tvgId, 'guide.channel');
    expect(restored.url, channel.url);
  });

  test('JSON antiguo sin xtreamStreamId sigue siendo compatible', () {
    final restored = Channel.fromJson(<String, dynamic>{
      'name': 'Canal viejo',
      'url': 'https://example.test/live/u/p/77.ts',
      'logoUrl': null,
      'group': 'TV',
      'tvgId': null,
      'httpUserAgent': null,
      'httpReferrer': null,
    });

    expect(restored.xtreamStreamId, isNull);
    expect(restored.name, 'Canal viejo');
  });
}
