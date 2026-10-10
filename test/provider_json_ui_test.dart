import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:iptv_player/models/playlist_source_type.dart';
import 'package:iptv_player/providers/iptv_provider.dart';
import 'package:iptv_player/screens/add_source_screen.dart';
import 'package:iptv_player/services/provider_json_catalog_parser.dart';
import 'package:iptv_player/widgets/channel_logo_image.dart';

import 'fixtures/provider_json_fixture.dart';

class _ImportProvider extends IptvProvider {
  String? importedContent;
  String? importError;

  @override
  String? get error => importError;

  @override
  Future<ProviderJsonCatalog?> addLocalProviderJson(
    String name,
    String content,
  ) async {
    importedContent = content;
    try {
      return const ProviderJsonCatalogParser().parse(content);
    } on FormatException catch (error) {
      importError = error.message;
      notifyListeners();
      return null;
    }
  }
}

void main() {
  Future<void> open(WidgetTester tester, _ImportProvider provider) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<IptvProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AddSourceScreen(
                      initialType: PlaylistSourceType.localProviderJson,
                    ),
                  ),
                ),
                child: const Text('Abrir importación'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir importación'));
    await tester.pumpAndSettle();
  }

  testWidgets('permite pegar JSON e importarlo desde la nueva opción', (
    tester,
  ) async {
    final provider = _ImportProvider();
    addTearDown(provider.dispose);
    await open(tester, provider);
    expect(find.text('Cargar provider.json local'), findsOneWidget);
    await tester.tap(find.text('Pegar JSON'));
    await tester.pumpAndSettle();
    final content = providerFixture([providerSample(drm: false)]);
    await tester.enterText(find.byType(TextField).last, content);
    await tester.scrollUntilVisible(
      find.text('Importar catálogo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar catálogo'));
    await tester.pumpAndSettle();
    expect(provider.importedContent, content);
    expect(find.text('Abrir importación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('JSON incorrecto permanece en la pantalla y muestra un error', (
    tester,
  ) async {
    final provider = _ImportProvider();
    addTearDown(provider.dispose);
    await open(tester, provider);
    await tester.tap(find.text('Pegar JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '{');
    await tester.scrollUntilVisible(
      find.text('Importar catálogo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar catálogo'));
    await tester.pumpAndSettle();
    expect(find.byType(AddSourceScreen), findsOneWidget);
    expect(find.textContaining('JSON inválido'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un icono base64 se presenta como MemoryImage sin URL de red', (
    tester,
  ) async {
    final channel = const ProviderJsonCatalogParser()
        .parse(providerFixture())
        .channels
        .single;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: ChannelLogoImage(
              channel: channel,
              fit: BoxFit.contain,
              allowNetwork: false,
              fallback: const Icon(Icons.live_tv),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(tester.takeException(), isNull);
  });
}
