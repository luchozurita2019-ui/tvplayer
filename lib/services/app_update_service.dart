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

enum AppUpdatePhase { idle, downloading, verifying, installing, permission, ready, error }

class AppUpdateService extends ChangeNotifier {
  AppUpdateService._()
      : _temporaryDirectory = getTemporaryDirectory,
        _clientFactory = http.Client.new;

  @visibleForTesting
  AppUpdateService.forTesting({
    required AppUpdateInfo update,
    required Future<Directory> Function() temporaryDirectory,
    required http.Client Function() clientFactory,
  })  : _availableUpdate = update,
        _temporaryDirectory = temporaryDirectory,
        _clientFactory = clientFactory;

  final Future<Directory> Function() _temporaryDirectory;
  final http.Client Function() _clientFactory;

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
  int _downloadedBytes = 0;
  int? _totalBytes;
  AppUpdatePhase _phase = AppUpdatePhase.idle;
  String? _lastUpdateError;
  DateTime? _nextAllowedCheckAt;
  AppUpdateInfo? _availableUpdate;

  bool get checked => _checked;
  bool get checking => _checking;
  bool get downloading => _downloading;
  double get downloadProgress => _downloadProgress;
  int get downloadedBytes => _downloadedBytes;
  int? get totalBytes => _totalBytes;
  AppUpdatePhase get phase => _phase;
  String? get lastUpdateError => _lastUpdateError;
  AppUpdateInfo? get availableUpdate => _availableUpdate;
  bool get hasUpdate => _availableUpdate != null;

  Future<void> checkOnce({bool force = false}) async {
    if (_checking || _downloading) return;
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
        final changed = _availableUpdate?.versionCode != versionCode ||
            _availableUpdate?.sha256 != sha;
        _availableUpdate = AppUpdateInfo(
          versionCode: versionCode,
          versionName: versionName,
          downloaderUrl: legacyUrl,
          apkUrl: apkUrl,
          sha256: sha,
          releaseNotes: '${decoded['release_notes'] ?? ''}'.trim(),
          forceUpdate: decoded['force_update'] == true,
        );
        if (changed) {
          _phase = AppUpdatePhase.idle;
          _lastUpdateError = null;
          _downloadProgress = 0;
          _downloadedBytes = 0;
          _totalBytes = null;
        }
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
    _downloadedBytes = 0;
    _totalBytes = null;
    _phase = AppUpdatePhase.verifying;
    _lastUpdateError = null;
    notifyListeners();

    File? partialFile;
    try {
      final temp = await _temporaryDirectory();
      final apkFile = _apkFile(temp, update);
      if (!await _isVerifiedApk(apkFile, update)) {
        if (await apkFile.exists()) await apkFile.delete();
        partialFile = File('${apkFile.path}.part');
        _phase = AppUpdatePhase.downloading;
        notifyListeners();
        final client = _clientFactory();
        try {
          final request = http.Request('GET', uri);
          final response = await client.send(request).timeout(_requestTimeout);
          if (response.statusCode != 200) {
            throw const _UpdateException('download_http_error');
          }
          final length = response.contentLength;
          if (length != null && length > _maxApkBytes) {
            throw const _UpdateException('file_too_large');
          }
          _totalBytes = length != null && length > 0 ? length : null;
          final sink = partialFile.openWrite();
          var lastPercent = -1;
          var lastNotice = DateTime.now();
          try {
            await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
              _downloadedBytes += chunk.length;
              if (_downloadedBytes > _maxApkBytes) {
                throw const _UpdateException('file_too_large');
              }
              sink.add(chunk);
              if (_totalBytes != null) {
                _downloadProgress = (_downloadedBytes / _totalBytes!).clamp(0.0, 1.0).toDouble();
              }
              final percent = (_downloadProgress * 100).floor();
              final now = DateTime.now();
              if (percent != lastPercent || now.difference(lastNotice).inMilliseconds >= 250) {
                lastPercent = percent;
                lastNotice = now;
                notifyListeners();
              }
            }
          } finally {
            await sink.close();
          }
          if (_downloadedBytes == 0 ||
              (_totalBytes != null && _downloadedBytes != _totalBytes)) {
            throw const _UpdateException('download_incomplete');
          }
        } finally {
          client.close();
        }
        _phase = AppUpdatePhase.verifying;
        notifyListeners();
        if (!await _isVerifiedApk(partialFile, update)) {
          throw const _UpdateException('hash_mismatch');
        }
        await partialFile.rename(apkFile.path);
      }

      _downloadedBytes = await apkFile.length();
      _totalBytes = _downloadedBytes;
      _downloadProgress = 1;
      // Se guarda antes de salir a Ajustes: Android puede cerrar el proceso.
      await _pendingFile(temp).writeAsString(jsonEncode({
        'version_code': update.versionCode,
        'sha256': update.sha256!.toLowerCase(),
      }), flush: true);
      _phase = AppUpdatePhase.installing;
      notifyListeners();
      final installResult = await _deviceChannel.invokeMethod<String>(
        'installTvFullApk',
        <String, Object>{'path': apkFile.path},
      );
      if (installResult == 'permission_required') {
        _phase = AppUpdatePhase.permission;
        return 'permission_required';
      }
      if (installResult != 'installer_opened') {
        throw const _UpdateException('install_failed');
      }
      _phase = AppUpdatePhase.ready;
      await _deleteIfPresent(_pendingFile(temp));
      return 'installer_opened';
    } on _UpdateException catch (error) {
      _phase = AppUpdatePhase.error;
      _lastUpdateError = error.message;
      return error.message;
    } on TimeoutException {
      _phase = AppUpdatePhase.error;
      _lastUpdateError = 'timeout';
      return 'timeout';
    } on PlatformException catch (error) {
      _lastUpdateError = error.message ?? error.code;
      if (error.code == 'INSTALL_PERMISSION_REQUIRED') {
        _phase = AppUpdatePhase.permission;
        return 'permission_required';
      }
      _phase = AppUpdatePhase.error;
      return 'install_failed';
    } catch (error) {
      _phase = AppUpdatePhase.error;
      _lastUpdateError = error.toString();
      return 'update_failed';
    } finally {
      if (partialFile != null) await _deleteIfPresent(partialFile);
      _downloading = false;
      notifyListeners();
    }
  }

  Future<String?> resumePendingInstallation() async {
    final update = _availableUpdate;
    if (_downloading || update == null || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final temp = await _temporaryDirectory();
      final pending = _pendingFile(temp);
      if (!await pending.exists()) return null;
      final metadata = jsonDecode(await pending.readAsString());
      if (metadata is! Map<String, dynamic> ||
          metadata['version_code'] != update.versionCode ||
          metadata['sha256'] != update.sha256?.toLowerCase()) {
        await _deleteIfPresent(pending);
        return null;
      }
      if (!await _apkFile(temp, update).exists()) {
        await _deleteIfPresent(pending);
        return null;
      }
      final permitted = await _deviceChannel.invokeMethod<bool>('canInstallTvFullApk') ?? false;
      if (!permitted) {
        _phase = AppUpdatePhase.permission;
        notifyListeners();
        return null;
      }
      // downloadAndInstall vuelve a validar el SHA-256 antes de reutilizarla.
      return await downloadAndInstall();
    } catch (_) {
      return null;
    }
  }

  static File _apkFile(Directory temp, AppUpdateInfo update) =>
      File('${temp.path}/tvfull-pro-update-${update.versionCode}.apk');

  static File _pendingFile(Directory temp) =>
      File('${temp.path}/tvfull-pro-update-pending.json');

  static Future<bool> _isVerifiedApk(File file, AppUpdateInfo update) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length <= 0 || length > _maxApkBytes) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == update.sha256?.toLowerCase();
  }

  static Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Un fallo de limpieza no invalida una APK verificada ni bloquea la UI.
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

