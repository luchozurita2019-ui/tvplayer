import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/widgets/tv_live_theater.dart';

void main() {
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('V39 live theater fits $size without overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? requestedSection;
      var refreshed = false;
      var parental = false;

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
              channelGroup: 'Noticias',
              onFullscreen: () {},
              onCategories: () {},
              onHome: () {},
              onRefreshLists: () => refreshed = true,
              onParentalControl: () => parental = true,
              onSectionRequested: (value) => requestedSection = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Canales en Vivo'), findsOneWidget);
      expect(find.textContaining('Canal de prueba'), findsWidgets);

      await tester.tap(find.byIcon(Icons.movie_rounded));
      await tester.pump();
      expect(requestedSection, 'movies');

      final refreshFinder = find.byIcon(Icons.refresh_rounded);
      if (refreshFinder.evaluate().isNotEmpty) {
        await tester.tap(refreshFinder.first);
        expect(refreshed, isTrue);
      }

      final parentalFinder = find.byIcon(Icons.shield_outlined);
      if (parentalFinder.evaluate().isNotEmpty) {
        await tester.tap(parentalFinder.first);
        expect(parental, isTrue);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('V39 rail exposes only the six approved sections',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvLiveTheater(
            video: const ColoredBox(color: Colors.black),
            channels: const SizedBox.shrink(),
            channelName: 'Canal',
            onFullscreen: () {},
            onCategories: () {},
            onHome: () {},
            onSectionRequested: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.live_tv_rounded), findsWidgets);
    expect(find.byIcon(Icons.movie_rounded), findsOneWidget);
    expect(find.byIcon(Icons.video_library_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sports_soccer_rounded), findsOneWidget);
    expect(find.byIcon(Icons.child_care_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

    expect(find.byIcon(Icons.home_rounded), findsNothing);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
