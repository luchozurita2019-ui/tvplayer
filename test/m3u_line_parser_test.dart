import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/m3u_parser.dart';

void main() {
  test('parsea M3U incremental conservando headers por canal', () {
    final parser = M3uLineParser();
    final lines = <String>[
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="uno" tvg-logo="https://img/uno.png" group-title="Noticias",Canal Uno',
      '#EXTVLCOPT:http-user-agent=TVFULL-Test',
      '#EXTVLCOPT:http-referrer=https://referer.test/',
      'https://stream.test/uno.m3u8|Origin=https%3A%2F%2Forigin.test',
      '#EXTINF:-1 group-title="Cine",Película Dos',
      'https://stream.test/dos.mp4',
    ];

    final channels = lines
        .map(parser.addLine)
        .whereType<Channel>()
        .toList(growable: false);

    expect(channels, hasLength(2));
    expect(channels.first.name, 'Canal Uno');
    expect(channels.first.group, 'Noticias');
    expect(channels.first.httpUserAgent, 'TVFULL-Test');
    expect(channels.first.httpHeaders?['Referer'], 'https://referer.test/');
    expect(channels.first.httpHeaders?['Origin'], 'https://origin.test');
    expect(channels.last.name, 'Película Dos');
    expect(channels.last.httpHeaders, isNull);
  });
}
