import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/channel_backup.dart';
import 'package:iptv_player/services/m3u_parser.dart';

void main() {
  test('una entrada visible guarda dos respaldos con headers independientes', () {
    final channels = M3uParser.parse('''#EXTM3U
#EXTINF:-1 tvg-name="Canal, original" group-title="Noticias",Canal Uno
#EXTHTTP:{"Cookie":"principal"}
#EXT-X-TVFULL-BACKUP:{"url":"https://backup.test/one.ts","headers":{"Authorization":"respaldo"}}
#EXT-X-TVFULL-BACKUP:{"url":"https://third.test/one.m3u8","headers":{}}
https://primary.test/one.ts
#EXTINF:-1,Canal Dos
https://primary.test/two.ts
''');
    expect(channels, hasLength(2));
    final channel = channels.first;
    expect(channel.name, 'Canal Uno');
    expect(channel.httpHeaders?['Cookie'], 'principal');
    expect(channel.validBackups, hasLength(2));
    expect(channel.validBackups.first.headers, {'authorization': 'respaldo'});
    expect(channel.validBackups.last.headers, isEmpty);
    expect(channels.last.backups, isEmpty);
    final restored = Channel.fromJson(jsonDecode(jsonEncode(channel.toJson())));
    expect(restored.validBackups.last.url, 'https://third.test/one.m3u8');
    expect(restored.validBackups.first.headers, {'authorization': 'respaldo'});
    expect(restored.uniqueKey, channel.uniqueKey);
  });

  test('M3U antigua sigue funcionando y un respaldo inválido se ignora', () {
    final channels = M3uParser.parse('''#EXTINF:-1,Canal
#EXT-X-TVFULL-BACKUP:{invalid
#EXT-X-TVFULL-BACKUP:{"url":"file:///private"}
https://primary.test/live
''');
    expect(channels.single.url, 'https://primary.test/live');
    expect(channels.single.validBackups, isEmpty);
    expect(Channel.fromJson({'name': 'Canal', 'url': 'https://a.test'}).backups, isEmpty);
  });

  test('no duplica la señal principal ni acepta inyección de headers', () {
    const channel = Channel(
      name: 'Canal', url: 'https://primary.test/live',
      httpHeaders: {'Cookie': 'main'},
      backups: [
        ChannelBackup(url: 'https://primary.test/live', headers: {'cookie': 'main'}),
        ChannelBackup(url: 'https://backup.test/live', headers: {'Cookie': 'bad\r\nX-Test: injected', 'Origin': 'https://valid.test'}),
        ChannelBackup(url: 'https://backup.test/live', headers: {'origin': 'https://valid.test'}),
      ],
    );
    expect(channel.validBackups, hasLength(1));
    expect(channel.validBackups.single.headers, {'origin': 'https://valid.test'});
  });

  test('una entrada incompleta no traslada permisos ni respaldos a la siguiente', () {
    final channel = M3uParser.parse('''#EXTINF:-1,Incompleta
#EXTHTTP:{"Cookie":"private"}
#EXT-X-TVFULL-BACKUP:{"url":"https://backup.test/other"}
#EXTINF:-1,Canal válido
https://primary.test/live
''').single;
    expect(channel.httpHeaders, isNull);
    expect(channel.backups, isEmpty);
  });
}
