import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/clearkey_drm_config.dart';

import 'fixtures/provider_json_fixture.dart';

void main() {
  test('JWK usa base64url sin padding, claves oct y sesión temporal', () {
    final value = ClearKeyDrmConfig.fromHex(testKeyId, testKey).toJwkSet();
    expect(jsonDecode(value), {
      'keys': [
        {
          'kty': 'oct',
          'kid': 'ABEiM0RVZneImaq7zN3u_w',
          'k': '_-7dzLuqmYh3ZlVEMyIRAA',
        },
      ],
      'type': 'temporary',
    });
    expect(value, isNot(contains('=')));
    expect(value, isNot(contains('+')));
    expect(value, isNot(contains('/')));
  });

  test(
    'claves incompletas, longitud incorrecta o no hex fallan sin exponerlas',
    () {
      for (final value in [
        '',
        'aa',
        'ggggggggggggggggggggggggggggggggg',
        testKey + '00',
      ]) {
        expect(
          () => ClearKeyDrmConfig.fromHex(value, testKey),
          throwsFormatException,
        );
        expect(
          () => ClearKeyDrmConfig.fromHex(testKeyId, value),
          throwsFormatException,
        );
      }
    },
  );

  test('canales distintos generan licencias independientes', () {
    final a = ClearKeyDrmConfig.fromHex(testKeyId, testKey).toJwkSet();
    final b = ClearKeyDrmConfig.fromHex(testKey, testKeyId).toJwkSet();
    expect(a, isNot(b));
    expect(
      (jsonDecode(b)['keys'] as List).single['kid'],
      '_-7dzLuqmYh3ZlVEMyIRAA',
    );
  });
}
