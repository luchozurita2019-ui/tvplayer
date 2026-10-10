import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tvfull/device_identity');
  final payload = List<int>.generate(4096, (index) => index % 251);
  late Directory temp;
  late bool permitted;
  late String installResult;
  late int requests;
  late List<String> installedPaths;
  final services = <AppUpdateService>[];

  AppUpdateInfo update() => AppUpdateInfo(
        versionCode: 3054,
        versionName: '1.4.22',
        downloaderUrl: '',
        apkUrl: 'https://github.com/example/app/releases/download/v54/app.apk',
        sha256: sha256.convert(payload).toString(),
      );

  AppUpdateService service({http.Client Function()? clientFactory}) {
    final result = AppUpdateService.forTesting(
      update: update(),
      temporaryDirectory: () async => temp,
      clientFactory: clientFactory ?? () => MockClient.streaming((request, body) async {
        requests++;
        return http.StreamedResponse(Stream.value(payload), 200, contentLength: payload.length);
      }),
    );
    services.add(result);
    return result;
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    temp = await Directory.systemTemp.createTemp('tvfull-update-test-');
    permitted = false;
    installResult = 'permission_required';
    requests = 0;
    installedPaths = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'canInstallTvFullApk') return permitted;
      if (call.method == 'installTvFullApk') {
        final args = call.arguments as Map;
        final path = args['path'] as String;
        expect(await File(path).readAsBytes(), payload);
        installedPaths.add(path);
        return installResult;
      }
      return null;
    });
  });

  tearDown(() async {
    for (final value in services) { value.dispose(); }
    services.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await temp.delete(recursive: true);
  });

  test('retains verified APK and resumes after permissions and process restart', () async {
    final first = service();
    expect(await first.downloadAndInstall(), 'permission_required');
    expect(first.phase, AppUpdatePhase.permission);
    expect(await File(installedPaths.single).exists(), isTrue);
    expect(requests, 1);

    final restored = service();
    expect(await restored.resumePendingInstallation(), isNull);
    expect(restored.phase, AppUpdatePhase.permission);
    expect(installedPaths.length, 1);
    expect(requests, 1);

    permitted = true;
    installResult = 'installer_opened';
    expect(await restored.resumePendingInstallation(), 'installer_opened');
    expect(requests, 1);
    expect(installedPaths, [installedPaths.first, installedPaths.first]);
    expect(restored.phase, AppUpdatePhase.ready);
    expect(await restored.resumePendingInstallation(), isNull);
    expect(installedPaths.length, 2);
  });

  test('manual retry after cancelling Android installer reuses verified APK', () async {
    installResult = 'installer_opened';
    final value = service();
    expect(await value.downloadAndInstall(), 'installer_opened');
    expect(await value.downloadAndInstall(), 'installer_opened');
    expect(requests, 1);
    expect(installedPaths.length, 2);
  });

  test('modified cache is rejected and downloaded again before installation', () async {
    installResult = 'installer_opened';
    final value = service();
    expect(await value.downloadAndInstall(), 'installer_opened');
    await File(installedPaths.single).writeAsBytes([1, 2, 3]);
    expect(await value.downloadAndInstall(), 'installer_opened');
    expect(requests, 2);
  });

  test('reports actual progress and prevents duplicate downloads', () async {
    final stream = StreamController<List<int>>();
    final started = Completer<void>();
    final halfway = Completer<void>();
    final value = service(clientFactory: () => MockClient.streaming((request, body) async {
      requests++;
      started.complete();
      return http.StreamedResponse(stream.stream, 200, contentLength: payload.length);
    }));
    value.addListener(() {
      if (value.downloadedBytes == payload.length ~/ 2 && !halfway.isCompleted) {
        halfway.complete();
      }
    });
    final download = value.downloadAndInstall();
    await started.future;
    expect(await value.downloadAndInstall(), 'already_downloading');
    stream.add(payload.sublist(0, payload.length ~/ 2));
    await halfway.future;
    expect(value.phase, AppUpdatePhase.downloading);
    expect(value.downloadProgress, .5);
    expect(value.totalBytes, payload.length);
    stream.add(payload.sublist(payload.length ~/ 2));
    await stream.close();
    expect(await download, 'permission_required');
    expect(requests, 1);
    expect(value.downloadProgress, 1);
  });

  test('wrong hash is never installed and incomplete file is removed', () async {
    final value = service(clientFactory: () => MockClient.streaming((request, body) async =>
      http.StreamedResponse(Stream.value([1, 2, 3]), 200, contentLength: 3)));
    expect(await value.downloadAndInstall(), 'hash_mismatch');
    expect(value.phase, AppUpdatePhase.error);
    expect(installedPaths, isEmpty);
    expect(await temp.list().toList(), isEmpty);
  });

  test('truncated response is not promoted to a reusable APK', () async {
    final value = service(clientFactory: () => MockClient.streaming((request, body) async =>
      http.StreamedResponse(Stream.value(payload.sublist(0, 100)), 200, contentLength: payload.length)));
    expect(await value.downloadAndInstall(), 'download_incomplete');
    expect(installedPaths, isEmpty);
    expect(await temp.list().toList(), isEmpty);
  });

  test('download without Content-Length succeeds after hash verification', () async {
    final value = service(clientFactory: () => MockClient.streaming((request, body) async =>
      http.StreamedResponse(Stream.value(payload), 200)));
    bool sawUnknownLength = false;
    value.addListener(() {
      if (value.phase == AppUpdatePhase.downloading && value.downloadedBytes > 0) {
        sawUnknownLength = value.totalBytes == null;
      }
    });
    expect(await value.downloadAndInstall(), 'permission_required');
    expect(sawUnknownLength, isTrue);
  });
}
