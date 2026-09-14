import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/provider_json_catalog_parser.dart';

import 'fixtures/provider_json_fixture.dart';

void main() {
  const parser = ProviderJsonCatalogParser();

  test('importa la estructura del proveedor, DRM, categoría y headers', () {
    final result = parser.parse(providerFixture());
    final channel = result.channels.single;
    expect(channel.name, 'ESPN HD');
    expect(result.categories, ['Lista de deportes']);
    expect(channel.drmKeyId, testKeyId);
    expect(channel.drmKey, testKey);
    expect(channel.streamMimeType, 'application/x-mpegURL');
    expect(channel.resolvedHttpHeaders('Default'), {
      'Origin': 'https://provider.example.test',
      'Referer': 'https://provider.example.test/',
      'User-Agent': 'Provider test agent',
    });
    // El APK de integración del proveedor aplica ClearKey también sobre HLS;
    // por eso esta combinación ya no debe degradarse ni generar advertencia.
    expect(result.warnings, isEmpty);
  });

  test('sin drm_license_uri produce un canal sin DRM', () {
    final result = parser.parse(providerFixture([providerSample(drm: false)]));
    expect(result.channels.single.hasDrmConfiguration, isFalse);
    expect(result.channels.single.drmKeyId, isNull);
    expect(result.channels.single.drmKey, isNull);
    expect(result.warnings, isEmpty);
  });

  test('decodifica icono data:image a bytes y nunca lo guarda como URL', () {
    final channel = parser.parse(providerFixture()).channels.single;
    expect(channel.logoBytes, base64Decode(testPngBase64));
    expect(channel.logoUrl, isNull);
  });

  test(
    'icono truncado usa fallback sin perder el canal ni crear URL de red',
    () {
      final sample = providerSample(drm: false)
        ..['icono'] = 'data:image/png;base64,iVBORw0KG...';
      final result = parser.parse(providerFixture([sample]));
      expect(result.channels.single.logoBytes, isNull);
      expect(result.channels.single.logoUrl, isNull);
      expect(result.warnings.single, contains('.icono'));
    },
  );

  test('permite logo HTTP de un sample que no contiene data:image', () {
    final sample = providerSample(drm: false)
      ..['icono'] = 'https://provider.example.test/logo.png';
    final channel = parser.parse(providerFixture([sample])).channels.single;
    expect(channel.logoBytes, isNull);
    expect(channel.logoUrl, 'https://provider.example.test/logo.png');
  });

  for (final value in [
    '',
    'kid:$testKeyId',
    'k:$testKey',
    'kid:zz,k:$testKey',
    'kid:$testKeyId,k:$testKey,k:$testKey',
    'kid:$testKeyId;k:$testKey',
    'https://license.example.test',
    123,
    <String, Object?>{},
  ]) {
    test(
      'DRM inválido se omite con aviso, no se degrada a canal sin DRM ($value)',
      () {
        final broken = providerSample()..['drm_license_uri'] = value;
        final good = providerSample(drm: false)..['name'] = 'Canal válido';
        final result = parser.parse(providerFixture([broken, good]));
        expect(result.channels.map((c) => c.name), ['Canal válido']);
        expect(result.warnings.single, contains('categories[0].samples[0]'));
        expect(result.warnings.single, isNot(contains(testKey)));
        expect(result.warnings.single, isNot(contains(testKeyId)));
      },
    );
  }

  test('normaliza mayúsculas, espacios y orden de campos ClearKey', () {
    final sample = providerSample()
      ..['type'] = 'DASH'
      ..['original_url'] = 'https://provider.example.test/manifest'
      ..['drm_license_uri'] =
          ' k: ' + testKey.toUpperCase() + ' , kid: ' + testKeyId.toUpperCase();
    final result = parser.parse(providerFixture([sample]));
    expect(result.channels.single.drmKeyId, testKeyId);
    expect(result.channels.single.drmKey, testKey);
    expect(result.channels.single.streamMimeType, 'application/dash+xml');
    expect(result.warnings, isEmpty);
  });

  test('tolera categorías y samples inválidos y conserva el orden válido', () {
    final result = parser.parse(
      jsonEncode({
        'categories': [
          null,
          {'name': 'Inválida', 'samples': 2},
          {
            'samples': [null, {}, providerSample(drm: false, icon: false)],
          },
          {
            'name': 'Noticias',
            'samples': [providerSample(drm: false)],
          },
        ],
      }),
    );
    expect(result.channels.length, 2);
    expect(result.categories, ['Sin categoría', 'Noticias']);
    expect(result.warnings.length, 5);
  });

  test('headers con tipos incorrectos o saltos de línea no se envían', () {
    for (final headers in [
      [],
      {'Origin': 4},
      {'Bad Header': 'x'},
      {'Origin': 'x\r\nAuthorization: x'},
    ]) {
      final bad = providerSample()..['headers'] = headers;
      final result = parser.parse(
        providerFixture([bad, providerSample(drm: false)]),
      );
      expect(result.channels.length, 1);
      expect(result.warnings.single, contains('headers'));
    }
  });

  test('URL o nombre faltante no produce excepciones sin capturar', () {
    final result = parser.parse(
      providerFixture([
        providerSample()..remove('name'),
        providerSample()..['original_url'] = 123,
        providerSample()..['original_url'] = 'file:///tmp/video',
        providerSample(drm: false),
      ]),
    );
    expect(result.channels.length, 1);
    expect(result.warnings.length, 3);
  });

  test(
    'JSON inválido, raíz incorrecta o catálogo vacío reportan error claro',
    () {
      for (final value in [
        '{secret',
        '[]',
        '{}',
        '{"categories":[]}',
        providerFixture([{}]),
      ]) {
        expect(() => parser.parse(value), throwsFormatException);
      }
      try {
        parser.parse('{"secret":"sensitive-value",');
        fail('Debe rechazar el JSON incompleto');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('sensitive-value')));
      }
    },
  );

  test(
    'lee File y ruta local; un archivo ausente reporta error sin filtrar ruta',
    () async {
      final temp = await Directory.systemTemp.createTemp('provider-parser-');
      addTearDown(() => temp.delete(recursive: true));
      final file = File(temp.path + '/provider.json');
      await file.writeAsString(providerFixture([providerSample(drm: false)]));
      expect((await parser.parseFile(file)).channels.length, 1);
      expect((await parser.parsePath(file.path)).channels.length, 1);
      await file.delete();
      await expectLater(parser.parseFile(file), throwsFormatException);
    },
  );
}
