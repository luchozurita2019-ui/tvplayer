import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/live_epg_service.dart';

void main() {
  test('Xtream short EPG maps current and next program', () {
    final now = DateTime.fromMillisecondsSinceEpoch(2000 * 1000);
    final payload = <String, dynamic>{
      'epg_listings': <Map<String, dynamic>>[
        <String, dynamic>{
          'title': base64.encode(utf8.encode('Partido en vivo')),
          'description': base64.encode(utf8.encode('Fecha principal')),
          'start_timestamp': '1900',
          'stop_timestamp': '2100',
        },
        <String, dynamic>{
          'title': 'Post partido',
          'start_timestamp': '2100',
          'stop_timestamp': '2200',
        },
      ],
    };

    final guide = parseXtreamEpgPayload(payload, clock: now);
    expect(guide, isNotNull);
    expect(guide!.now?.title, 'Partido en vivo');
    expect(guide.now?.description, 'Fecha principal');
    expect(guide.next?.title, 'Post partido');
  });

  test('Xtream simple data table envelope maps programming', () {
    final now = DateTime.fromMillisecondsSinceEpoch(2000 * 1000);
    final payload = <String, dynamic>{
      'data': <String, dynamic>{
        'epg_listings': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': 'Programa actual',
            'start_timestamp': '1900',
            'stop_timestamp': '2100',
          },
          <String, dynamic>{
            'title': 'Programa siguiente',
            'start_timestamp': '2100',
            'stop_timestamp': '2200',
          },
        ],
      },
    };

    final guide = parseXtreamEpgPayload(payload, clock: now);
    expect(guide?.now?.title, 'Programa actual');
    expect(guide?.next?.title, 'Programa siguiente');
  });

  test('Xtream short EPG gracefully handles missing data', () {
    expect(
        parseXtreamEpgPayload(<String, dynamic>{'epg_listings': []}), isNull);
    expect(parseXtreamEpgPayload(<String, dynamic>{}), isNull);
  });
}
