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

  test('acepta Base64 estándar del catálogo y lo normaliza a Base64URL', () {
    final config = ClearKeyDrmConfig.parse(
      'kid:+LIHwQ8/dq66MqNg7FK55A,k:r61J0g6zlnDpPjccHWaZIQ',
    );

    expect(config.keyId, 'f8b207c10f3f76aeba32a360ec52b9e4');
    expect(config.key, 'afad49d20eb39670e93e371c1d669921');

    final jwk = jsonDecode(config.toJwkSet()) as Map<String, dynamic>;
    final keys = jwk['keys'] as List<dynamic>;
    expect(keys.single['kid'], '-LIHwQ8_dq66MqNg7FK55A');
    expect(keys.single['k'], 'r61J0g6zlnDpPjccHWaZIQ');
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
