import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/provider_json_catalog_parser.dart';

void main() {
  const parser = ProviderJsonCatalogParser();

  test('adapta groups -> stations -> options sin tocar el pipeline V50', () {
    final result = parser.parse(
      jsonEncode({
        'name': 'Lista 2',
        'groups': [
          {
            'name': 'Deportes',
            'stations': [
              {
                'name': 'ESPN',
                'options': [
                  {
                    'name': 'ESPN HD',
                    'url': 'https://example.test/espn.mpd',
                    'image': 'https://example.test/espn.png',
                    'headers': {
                      'Origin': 'https://example.test',
                    },
                    'license_type': 'clearkey',
                    'license_key': {
                      'keys': [
                        {
                          'kty': 'oct',
                          'kid': 'EjRWeJCrze8SNFZ4kKvN7w',
                          'k': '3q2-7_8A9QABEiM0RVZneA',
                        },
                      ],
                      'type': 'temporary',
                    },
                  },
                ],
              },
            ],
          },
        ],
      }),
    );

    final channel = result.channels.single;
    expect(result.categories, ['Deportes']);
    expect(channel.name, 'ESPN HD');
    expect(channel.url, 'https://example.test/espn.mpd');
    expect(channel.logoUrl, 'https://example.test/espn.png');
    expect(channel.drmKeyId, '1234567890abcdef1234567890abcdef');
    expect(channel.drmKey, 'deadbeefff00f5000112233445566778');
    expect(channel.streamMimeType, 'application/dash+xml');
    expect(channel.resolvedHttpHeaders('Default')['Origin'],
        'https://example.test');
  });

  test('acepta license_key JWK serializado como string', () {
    final result = parser.parse(
      jsonEncode({
        'groups': [
          {
            'name': 'Noticias',
            'stations': [
              {
                'name': 'Canal',
                'url': 'https://example.test/live.m3u8',
                'license_type': 'ClearKey',
                'license_key': jsonEncode({
                  'keys': [
                    {
                      'kty': 'oct',
                      'kid': 'EjRWeJCrze8SNFZ4kKvN7w',
                      'k': '3q2-7_8A9QABEiM0RVZneA',
                    },
                  ],
                  'type': 'temporary',
                }),
              },
            ],
          },
        ],
      }),
    );

    expect(result.channels.single.drmKeyId,
        '1234567890abcdef1234567890abcdef');
    expect(result.channels.single.drmKey,
        'deadbeefff00f5000112233445566778');
  });

  test('una station sin options se convierte en un sample', () {
    final result = parser.parse(
      jsonEncode({
        'groups': [
          {
            'name': 'Noticias',
            'stations': [
              {
                'name': 'Canal 1',
                'url': 'https://example.test/live.m3u8',
              },
            ],
          },
        ],
      }),
    );

    expect(result.channels.length, 1);
    expect(result.channels.single.name, 'Canal 1');
    expect(result.channels.single.group, 'Noticias');
  });

  test('conserva {token} como stream dinámico y no lo fuerza como URL final', () {
    final result = parser.parse(
      jsonEncode({
        'groups': [
          {
            'name': 'Token',
            'stations': [
              {
                'name': 'Canal token',
                'url': 'https://example.test/live/{token}/stream.mpd',
              },
            ],
          },
        ],
      }),
    );

    final channel = result.channels.single;
    expect(channel.dynamicStreamPath,
        'https://example.test/live/{token}/stream.mpd');
    expect(channel.dynamicStreamId,
        'https://example.test/live/{token}/stream.mpd');
    expect(channel.url, startsWith('tvfull-dynamic://stream/'));
  });
  test('hereda metadatos de station y permite override por option', () {
    final result = parser.parse(
      jsonEncode({
        'groups': [
          {
            'name': 'Test',
            'stations': [
              {
                'name': 'Canal',
                'image': 'https://example.test/logo.png',
                'type': 'DASH',
                'tvg_id': 'canal.test',
                'headers': {'Referer': 'https://station.test'},
                'options': [
                  {
                    'name': 'Canal HD',
                    'url': 'https://example.test/live.mpd',
                    'headers': {
                      'Origin': 'https://option.test',
                    },
                  },
                ],
              },
            ],
          },
        ],
      }),
    );
    final channel = result.channels.single;
    expect(channel.name, 'Canal HD');
    expect(channel.logoUrl, 'https://example.test/logo.png');
    expect(channel.tvgId, 'canal.test');
    expect(channel.streamMimeType, 'application/dash+xml');
    expect(channel.resolvedHttpHeaders('Default')['Referer'],
        'https://station.test');
    expect(channel.resolvedHttpHeaders('Default')['Origin'],
        'https://option.test');
  });

  test('no convierte una entrada website en un stream de video', () {
    final result = parser.parse(
      jsonEncode({
        'groups': [
          {
            'name': 'Extras',
            'stations': [
              {
                'name': 'Más listas',
                'url': 'https://example.test/',
                'license_type': 'website',
              },
            ],
          },
        ],
      }),
    );
    expect(result.channels.single.url, 'https://example.test/');
    expect(result.channels.single.streamMimeType, isNull);
  });

}
