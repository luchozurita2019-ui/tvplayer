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

    final channels =
        lines.map(parser.addLine).whereType<Channel>().toList(growable: false);

    expect(channels, hasLength(2));
    expect(channels.first.name, 'Canal Uno');
    expect(channels.first.group, 'Noticias');
    expect(channels.first.httpUserAgent, 'TVFULL-Test');
    expect(channels.first.httpHeaders?['Referer'], 'https://referer.test/');
    expect(channels.first.httpHeaders?['Origin'], 'https://origin.test');
    expect(channels.last.name, 'Película Dos');
    expect(channels.last.httpHeaders, isNull);
  });

  test('EXTINF acepta comas dentro de atributos entre comillas', () {
    final channels = M3uParser.parse('''
#EXTM3U
#EXTINF:-1 tvg-name="Noticias, Tucumán" group-title="News, Local",Canal 24
https://stream.test/live/24.m3u8
''');

    expect(channels, hasLength(1));
    expect(channels.single.name, 'Canal 24');
    expect(channels.single.group, 'News, Local');
  });

  test('BOM inicial no impide reconocer la cabecera ni el canal', () {
    final channels = M3uParser.parse(
      '\uFEFF#EXTM3U\n#EXTINF:-1 group-title="TV",Canal BOM\nhttps://stream.test/bom.ts',
    );

    expect(channels, hasLength(1));
    expect(channels.single.name, 'Canal BOM');
    expect(channels.single.group, 'TV');
  });

  test('HTML o JSON de error con HTTP 200 no se convierten en canal', () {
    final parser = M3uLineParser();
    expect(parser.addLine('#EXTINF:-1 group-title="TV",Canal Real'), isNull);
    expect(parser.addLine('<html><body>Access denied</body></html>'), isNull);
    final channel = parser.addLine('https://stream.test/real.ts');

    expect(channel, isNotNull);
    expect(channel!.name, 'Canal Real');
    expect(channel.url, 'https://stream.test/real.ts');
  });

  test('un EXTINF nuevo limpia headers huérfanos de la entrada anterior', () {
    final parser = M3uLineParser();
    parser.addLine('#EXTINF:-1,Entrada incompleta');
    parser.addLine('#EXTVLCOPT:http-user-agent=NO-DEBE-FILTRARSE');
    parser.addLine('#EXTINF:-1,Entrada válida');
    final channel = parser.addLine('https://stream.test/valid.ts');

    expect(channel, isNotNull);
    expect(channel!.name, 'Entrada válida');
    expect(channel.httpUserAgent, isNull);
    expect(channel.httpHeaders, isNull);
  });
}
