import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/channel_backup.dart';
import 'package:iptv_player/screens/android_media3_texture_player_screen.dart';
import 'package:iptv_player/services/channel_health_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('tvfull/media3_texture');
  const events = MethodChannel('tvfull/media3_texture_events');
  const sqlite = MethodChannel('com.tekartik.sqflite');
  final prepares = <Map<String, dynamic>>[];

  setUp(() {
    prepares.clear();
    SharedPreferences.setMockInitialValues({});
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(sqlite, (call) async => switch (call.method) {
      'getDatabasesPath' => '/test',
      'openDatabase' => {'id': 1},
      'query' => <Map<String, Object?>>[],
      'batch' => <Object?>[],
      _ => 0,
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(player, (call) async {
      if (call.method == 'prepare') {
        prepares.add(Map<String, dynamic>.from(call.arguments as Map));
      }
      if (call.method == 'initialize') return 1;
      if (call.method == 'getLiveAdaptiveLevel') return 0;
      return null;
    });
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(player, null);
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(sqlite, null);
  });

  Future<void> emit(WidgetTester tester, String type, int generation) async {
    // El canal simulado entrega exactamente el protocolo de eventos nativo.
    // ignore: deprecated_member_use
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'eventType': type, 'generation': generation,
        if (type == 'videoError') ...{
          'errorCodeName': 'ERROR_CODE_IO_BAD_HTTP_STATUS',
          'httpStatus': 403, 'retryable': false,
        },
      }),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, List<Channel> channels) async {
    await tester.pumpWidget(MaterialApp(home: AndroidMedia3TexturePlayerScreen(
      playlist: channels, initialIndex: 0,
    )));
    for (var i = 0; i < 12 && prepares.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(prepares, hasLength(1));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  const backed = Channel(
    name: 'Canal con respaldo', url: 'https://primary.test/live',
    httpHeaders: {'Cookie': 'primary-only'},
    backups: [
      ChannelBackup(url: 'https://second.test/live', headers: {'Authorization': 'second-only'}),
      ChannelBackup(url: 'https://third.test/live'),
    ],
  );

  testWidgets('403 cambia al respaldo y descarta eventos de la señal anterior', (tester) async {
    await open(tester, [backed]);
    final oldGeneration = prepares.first['requestGeneration'] as int;
    await emit(tester, 'videoError', oldGeneration);
    expect(prepares, hasLength(2));
    expect(prepares.last['url'], 'https://second.test/live');
    expect(prepares.last['headers'], {'authorization': 'second-only'});
    expect(ChannelHealthService.instance.isTemporarilyDead(backed), isFalse);
    expect(find.text('Probando respaldo 1…'), findsOneWidget);
    await emit(tester, 'videoError', oldGeneration);
    expect(prepares, hasLength(2));
    await emit(tester, 'playing', prepares.last['requestGeneration'] as int);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(backed.url, 'https://primary.test/live');
    await close(tester);
  });

  testWidgets('agotados los dos respaldos termina sin un bucle de reconexión', (tester) async {
    await open(tester, [backed]);
    for (var i = 0; i < 3; i++) {
      await emit(tester, 'videoError', prepares.last['requestGeneration'] as int);
    }
    expect(prepares.map((p) => p['url']), [backed.url, 'https://second.test/live', 'https://third.test/live']);
    expect(find.text('No hay señales disponibles para este canal'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(prepares, hasLength(3));
    await close(tester);
  });

  testWidgets('una señal terminada prueba respaldo y cambiar canal vuelve a su principal', (tester) async {
    const other = Channel(name: 'Otro canal', url: 'https://other.test/live');
    await open(tester, [backed, other]);
    final oldGeneration = prepares.first['requestGeneration'] as int;
    await emit(tester, 'completed', oldGeneration);
    expect(prepares.last['url'], 'https://second.test/live');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(prepares.last['url'], other.url);
    await emit(tester, 'videoError', oldGeneration);
    expect(prepares, hasLength(3));
    await close(tester);
  });

  testWidgets('sin respaldos conserva los reintentos de la V54 y cancela los del canal anterior', (tester) async {
    const first = Channel(name: 'Sin respaldo', url: 'https://only.test/live');
    const next = Channel(name: 'Siguiente', url: 'https://next.test/live');
    await open(tester, [first, next]);
    // 403 conserva el refresco/reintento histórico de fuentes sin respaldo.
    await emit(tester, 'videoError', prepares.first['requestGeneration'] as int);
    expect(prepares, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(prepares.map((p) => p['url']), [first.url, next.url]);
    await close(tester);
  });
}
