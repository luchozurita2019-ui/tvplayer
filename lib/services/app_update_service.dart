import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_version_service.dart';

class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final String downloaderUrl;
  final String? apkUrl;
  final String? sha256;
  final String releaseNotes;
  final bool forceUpdate;

  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloaderUrl,
    this.apkUrl,
    this.sha256,
    this.releaseNotes = '',
    this.forceUpdate = false,
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

  // Canal de prueba. No se habilitan actualizaciones hasta publicar un JSON
  // válido con update_available=true, enlace directo y SHA-256 real.
  static final Uri _endpoint = Uri.parse(
    'https://raw.githubusercontent.com/luchozurita2019-ui/tvplayer/auto-update-json-test/update.json',
  );

  static const Duration _requestTimeout = Duration(seconds: 12);
  static const int _maxApkBytes = 400 * 1024 * 1024;

  bool _checked = false;
  bool _checking = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _lastUpdateError;
  DateTime? _nextAllowedCheckAt;
  AppUpdateInfo? _availableUpdate;

  bool get checked => _checked;
  bool get checking => _checking;
  bool get downloading => _downloading;
  double get downloadProgress => _downloadProgress;
  String? get lastUpdateError => _lastUpdateError;
  AppUpdateInfo? get availableUpdate => _availableUpdate;
  bool get hasUpdate => _availableUpdate != null;

  Future<void> checkOnce({bool force = false}) async {
    if (_checking) return;
    final now = DateTime.now();
    final next = _nextAllowedCheckAt;
    if (!force && next != null && now.isBefore(next)) return;

    _checking = true;
    _nextAllowedCheckAt = now.add(const Duration(seconds: 30));
    try {
      final installed = await AppVersionService.instance.current;
      final response = await http.get(_endpoint).timeout(_requestTimeout);
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;

      final enabled = decoded['update_available'] == true;
      final versionCode = _toInt(decoded['version_code']);
      final versionName = '${decoded['version_name'] ?? ''}'.trim();
      final apkUrl = '${decoded['apk_url'] ?? ''}'.trim();
      final sha = '${decoded['sha256'] ?? ''}'.trim().toLowerCase();
      final legacyUrl = '${decoded['downloader_url'] ?? ''}'.trim();
      final uri = Uri.tryParse(apkUrl);
      final validApkUrl = uri != null && _isAllowedDownloadUri(uri);
      final validHash = RegExp(r'^[a-f0-9]{64}$').hasMatch(sha);

      _checked = true;
      _nextAllowedCheckAt = DateTime.now().add(const Duration(minutes: 5));
      if (enabled &&
          versionCode > installed.versionCode &&
          versionName.isNotEmpty &&
          validApkUrl &&
          validHash) {
        _availableUpdate = AppUpdateInfo(
          versionCode: versionCode,
          versionName: versionName,
          downloaderUrl: legacyUrl,
          apkUrl: apkUrl,
          sha256: sha,
          releaseNotes: '${decoded['release_notes'] ?? ''}'.trim(),
          forceUpdate: decoded['force_update'] == true,
        );
        _lastUpdateError = null;
      } else {
        // Actualizador exclusivamente por update.json: sin fallback a Supabase.
        _availableUpdate = null;
        _lastUpdateError = null;
      }
    } catch (_) {
      // Una caída de red no bloquea la reproducción ni el panel de clientes.
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<String> downloadAndInstall() async {
    final update = _availableUpdate;
    if (update == null || update.apkUrl == null || update.sha256 == null) {
      return 'no_direct_update';
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return 'android_only';
    }
    if (_downloading) return 'already_downloading';

    final uri = Uri.tryParse(update.apkUrl!);
    if (uri == null || !_isAllowedDownloadUri(uri)) return 'invalid_url';

    _downloading = true;
    _downloadProgress = 0;
    _lastUpdateError = null;
    notifyListeners();

    File? apkFile;
    try {
      final temp = await getTemporaryDirectory();
      apkFile = File('${temp.path}/tvfull-pro-update-${update.versionCode}.apk');
      if (await apkFile.exists()) await apkFile.delete();

      final client = http.Client();
      try {
        final request = http.Request('GET', uri);
        final response = await client.send(request).timeout(_requestTimeout);
        if (response.statusCode != 200) return 'download_http_error';
        final length = response.contentLength ?? 0;
        if (length > _maxApkBytes) return 'file_too_large';

        final sink = apkFile.openWrite();
        var received = 0;
        try {
          await for (final chunk in response.stream) {
            received += chunk.length;
            if (received > _maxApkBytes) {
              throw const _UpdateException('file_too_large');
            }
            sink.add(chunk);
            if (length > 0) _downloadProgress = received / length;
            notifyListeners();
          }
        } finally {
          await sink.close();
        }
      } finally {
        client.close();
      }

      final digest = await sha256.bind(apkFile.openRead()).first;
      if (digest.toString().toLowerCase() != update.sha256!.toLowerCase()) {
        await apkFile.delete().catchError((_) => apkFile!);
        return 'hash_mismatch';
      }

      final installResult = await _deviceChannel.invokeMethod<String>(
        'installTvFullApk',
        <String, Object>{'path': apkFile.path},
      );
      return installResult ?? 'install_failed';
    } on _UpdateException catch (error) {
      _lastUpdateError = error.message;
      return error.message;
    } on TimeoutException {
      return 'timeout';
    } on PlatformException catch (error) {
      _lastUpdateError = error.message ?? error.code;
      return error.code == 'INSTALL_PERMISSION_REQUIRED'
          ? 'permission_required'
          : 'install_failed';
    } catch (error) {
      _lastUpdateError = error.toString();
      return 'update_failed';
    } finally {
      _downloading = false;
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
    if (uri == null || !_isLegacyDownloader(update.downloaderUrl)) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static bool _isAllowedDownloadUri(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'github.com' ||
        host == 'raw.githubusercontent.com' ||
        host == 'objects.githubusercontent.com' ||
        host == 'release-assets.githubusercontent.com' ||
        host.endsWith('.supabase.co');
  }

  static bool _isLegacyDownloader(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        (uri.host == 'aftv.news' || uri.host == 'www.aftv.news');
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

class _UpdateException implements Exception {
  final String message;
  const _UpdateException(this.message);
}
