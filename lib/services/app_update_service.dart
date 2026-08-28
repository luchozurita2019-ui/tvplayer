import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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

  static const int currentVersionCode = 14;
  static const String currentVersionName = '1.2.2';
  static final Uri _endpoint = Uri.parse(
    'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-update',
  );

  bool _checked = false;
  bool _checking = false;
  AppUpdateInfo? _availableUpdate;

  bool get checked => _checked;
  bool get checking => _checking;
  AppUpdateInfo? get availableUpdate => _availableUpdate;
  bool get hasUpdate => _availableUpdate != null;

  Future<void> checkOnce() async {
    if (_checked || _checking) return;

    // Una sola consulta por apertura: se marca antes de salir a red y no se
    // repite aunque falle Internet o el usuario navegue entre catálogos.
    _checked = true;
    _checking = true;
    try {
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

      if (enabled &&
          versionCode > currentVersionCode &&
          versionName.isNotEmpty &&
          validUrl) {
        _availableUpdate = AppUpdateInfo(
          versionCode: versionCode,
          versionName: versionName,
          downloaderUrl: downloaderUrl,
        );
      }
    } catch (_) {
      // La comprobación de actualización nunca debe molestar ni bloquear la TV.
    } finally {
      _checking = false;
      notifyListeners();
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
