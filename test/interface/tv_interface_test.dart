import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/screens/tv_full_dashboard_screen.dart';
import 'package:iptv_player/widgets/tv_live_theater.dart';

void main() {
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('Dashboard fits $size without overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvFullDashboardScreen(
              playlistName: 'Proveedor de prueba',
              actions: const [],
              footer: const Text('1.4.6+38'),
              onOpenSection: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('TV EN VIVO'), findsOneWidget);
      expect(find.text('PELÍCULAS'), findsOneWidget);
      expect(find.text('SERIES'), findsOneWidget);
      expect(find.text('DEPORTES'), findsOneWidget);
      expect(find.text('INFANTILES'), findsOneWidget);
      expect(find.text('ADULTOS'), findsOneWidget);
    });
  }

  testWidgets('D-pad right then OK opens Movies', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    TvFullDashboardSection? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFullDashboardScreen(
            playlistName: 'Proveedor de prueba',
            actions: const [],
            footer: const SizedBox.shrink(),
            onOpenSection: (section) => opened = section,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(opened, TvFullDashboardSection.movies);
  });

  testWidgets('D-pad down then OK opens Sports', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    TvFullDashboardSection? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFullDashboardScreen(
            playlistName: 'Proveedor de prueba',
            actions: const [],
            footer: const SizedBox.shrink(),
            onOpenSection: (section) => opened = section,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(opened, TvFullDashboardSection.sports);
  });

  testWidgets('Live theater still keeps the real fullscreen action',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
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
            channelName: 'Canal de prueba',
            onFullscreen: () => fullscreen = true,
            onCategories: () {},
            onHome: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Pantalla completa'));
    expect(fullscreen, isTrue);
  });
}
