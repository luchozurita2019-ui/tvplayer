import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'app_version_service.dart';

class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final String downloaderUrl;

  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloaderUrl,
  });

  String get downloaderCode {
    final uri = Uri.tryParse(downloaderUrl);
    if (uri == null || uri.pathSegments.isEmpty) return '';
    final last = uri.pathSegments.last.trim();
    return RegExp(r'^\d+$').hasMatch(last) ? last : '';
  }
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const MethodChannel _deviceChannel = MethodChannel(
    'tvfull/device_identity',
  );

  static final Uri _endpoint = Uri.parse(
    'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-update',
  );

  bool _checked = false;
  bool _checking = false;
  DateTime? _nextAllowedCheckAt;
  AppUpdateInfo? _availableUpdate;

  bool get checked => _checked;
  bool get checking => _checking;
  AppUpdateInfo? get availableUpdate => _availableUpdate;
  bool get hasUpdate => _availableUpdate != null;

  Future<void> checkOnce({bool force = false}) async {
    if (_checking) return;
    final now = DateTime.now();
    final next = _nextAllowedCheckAt;
    if (!force && next != null && now.isBefore(next)) return;

    // Si la red falla, se permite otro intento a los 30 s. Una respuesta válida
    // se vuelve a consultar a los 5 min para detectar updates sin reiniciar la TV.
    _checking = true;
    _nextAllowedCheckAt = now.add(const Duration(seconds: 30));
    try {
      final installed = await AppVersionService.instance.current;
      final response = await http.get(_endpoint).timeout(
            const Duration(seconds: 4),
          );
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) return;

      final enabled = decoded['update_available'] == true;
      final versionCode = _toInt(decoded['version_code']);
      final versionName = '${decoded['version_name'] ?? ''}'.trim();
      final downloaderUrl = '${decoded['downloader_url'] ?? ''}'.trim();
      final uri = Uri.tryParse(downloaderUrl);
      final validUrl = uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          (uri.host == 'aftv.news' || uri.host == 'www.aftv.news');

      _checked = true;
      _nextAllowedCheckAt = DateTime.now().add(const Duration(minutes: 5));
      if (enabled &&
          versionCode > installed.versionCode &&
          versionName.isNotEmpty &&
          validUrl) {
        _availableUpdate = AppUpdateInfo(
          versionCode: versionCode,
          versionName: versionName,
          downloaderUrl: downloaderUrl,
        );
      } else {
        _availableUpdate = null;
      }
    } catch (_) {
      // Nunca bloquea la TV; el próximo intento queda habilitado rápidamente.
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<bool> openInstaller() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _deviceChannel.invokeMethod<bool>('openTvFullInstaller') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openUpdate() async {
    final update = _availableUpdate;
    if (update == null) return false;
    final uri = Uri.tryParse(update.downloaderUrl);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
