import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/widgets/tv_cinematic_home.dart';
import 'package:iptv_player/widgets/tv_live_theater.dart';

void main() {
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('Live theater fits $size and fullscreen button works',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var fullscreen = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvLiveTheater(
              video: const ColoredBox(color: Colors.black),
              channels: ListView(
                children: const [
                  ListTile(title: Text('Canal de prueba')),
                  ListTile(title: Text('Segundo canal')),
                ],
              ),
              channelName:
                  'Canal de prueba con un nombre muy largo para comprobar el espacio',
              onFullscreen: () => fullscreen = true,
              onCategories: () {},
              onHome: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('TV EN VIVO'), findsWidgets);
      expect(find.text('CANALES'), findsOneWidget);
      await tester.tap(find.byTooltip('Pantalla completa'));
      expect(fullscreen, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Home keeps the live shortcut active for pointer input',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    CinematicSection? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvCinematicHome(
            playlistName: 'Mi proveedor',
            items: const [],
            actions: const [],
            footer: const Text('TV FULL PRO'),
            onOpenSection: (section) => opened = section,
            onOpenItem: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('TV en vivo'));
    await tester.pump();
    expect(opened, CinematicSection.live);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
