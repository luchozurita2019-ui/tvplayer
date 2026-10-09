import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/app_update_service.dart';
import 'package:iptv_player/widgets/app_update_banner.dart';

void main() {
  Widget page(AppUpdateBanner banner) => MaterialApp(home: Scaffold(body: banner));

  testWidgets('shows percentage, MB and progress while disabling duplicate action', (tester) async {
    await tester.pumpWidget(page(AppUpdateBanner(
      versionName: '1.4.22',
      onUpdate: () {},
      phase: AppUpdatePhase.downloading,
      busy: true,
      progress: .7,
      downloadedBytes: 70 * 1024 * 1024,
      totalBytes: 100 * 1024 * 1024,
    )));
    expect(find.text('Descargando 70% · 70.0 / 100.0 MB'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, .7);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
  });

  testWidgets('unknown length shows MB and indeterminate progress without false percentage', (tester) async {
    await tester.pumpWidget(page(AppUpdateBanner(
      versionName: '1.4.22', onUpdate: () {},
      phase: AppUpdatePhase.downloading, busy: true,
      downloadedBytes: 5 * 1024 * 1024,
    )));
    expect(find.text('Descargando… 5.0 MB'), findsOneWidget);
    expect(find.text('DESCARGANDO…'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, isNull);
  });

  testWidgets('permission state explains saved APK and enables continue', (tester) async {
    var pressed = false;
    await tester.pumpWidget(page(AppUpdateBanner(
      versionName: '1.4.22', phase: AppUpdatePhase.permission,
      onUpdate: () { pressed = true; },
    )));
    expect(find.textContaining('APK guardada.'), findsOneWidget);
    await tester.tap(find.text('CONTINUAR INSTALACIÓN'));
    expect(pressed, isTrue);
  });
}
