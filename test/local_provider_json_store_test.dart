import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/local_provider_json_store.dart';

import 'fixtures/provider_json_fixture.dart';

void main() {
  late Directory directory;
  late LocalProviderJsonStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('provider-store-');
    store = LocalProviderJsonStore(supportDirectory: () async => directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'el catálogo y sus claves se recuperan desde una nueva instancia',
    () async {
      final source = File(directory.path + '/provider.json');
      await source.writeAsString(providerFixture());
      final imported = await store.importContent(
        'provider-json-test',
        await source.readAsString(),
      );
      await source.delete();
      final reopened = LocalProviderJsonStore(
        supportDirectory: () async => directory,
      );
      final catalog = await reopened.load('provider-json-test');
      expect(catalog.channels.single.drmKey, testKey);
      expect(catalog.channels.single.logoBytes, isNotNull);
      expect(await File(imported.path).exists(), isTrue);
      expect(imported.path, endsWith('.private.json'));
    },
  );

  test('importación inválida conserva íntegro el catálogo anterior', () async {
    final original = providerFixture([providerSample(drm: false)]);
    final imported = await store.importContent('provider-json-test', original);
    await expectLater(
      store.importContent('provider-json-test', '{}'),
      throwsFormatException,
    );
    expect(await File(imported.path).readAsString(), original);
    expect((await store.load('provider-json-test')).channels.length, 1);
  });

  test('eliminar una fuente sólo elimina su copia privada', () async {
    final first = await store.importContent(
      'provider-json-first',
      providerFixture(),
    );
    final second = await store.importContent(
      'provider-json-second',
      providerFixture(),
    );
    await store.remove('provider-json-first');
    expect(await File(first.path).exists(), isFalse);
    expect(await File(second.path).exists(), isTrue);
    await expectLater(store.load('provider-json-first'), throwsFormatException);
    await expectLater(store.remove('../escape'), throwsFormatException);
  });
}
