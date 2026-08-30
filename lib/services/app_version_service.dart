import 'package:flutter/services.dart';

class AppVersionInfo {
  final String versionName;
  final int versionCode;

  const AppVersionInfo({
    required this.versionName,
    required this.versionCode,
  });

  String get label => 'Versión $versionName • Build $versionCode';
  String get compactLabel => 'v$versionName+$versionCode';
}

class AppVersionService {
  AppVersionService._();

  static final AppVersionService instance = AppVersionService._();
  static const MethodChannel _channel = MethodChannel('tvfull/device_identity');

  AppVersionInfo? _cached;

  Future<AppVersionInfo> get current async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final raw =
          await _channel.invokeMapMethod<String, dynamic>('getAppVersion');
      final versionName = '${raw?['versionName'] ?? ''}'.trim();
      final rawCode = raw?['versionCode'];
      final versionCode =
          rawCode is num ? rawCode.toInt() : int.tryParse('$rawCode') ?? 0;
      if (versionName.isNotEmpty && versionCode > 0) {
        return _cached = AppVersionInfo(
          versionName: versionName,
          versionCode: versionCode,
        );
      }
    } catch (_) {
      // La identificación visual no debe bloquear la aplicación.
    }

    return const AppVersionInfo(versionName: 'desconocida', versionCode: 0);
  }
}
