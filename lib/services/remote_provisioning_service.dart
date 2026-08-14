import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RemoteDeviceCredentials {
  final String code;
  final String secret;

  const RemoteDeviceCredentials({required this.code, required this.secret});
}

class RemoteDeviceCredentialsInvalidException implements Exception {
  const RemoteDeviceCredentialsInvalidException();

  @override
  String toString() => 'La vinculación de este dispositivo ya no es válida.';
}

class RemoteProvisionedService {
  final String id;
  final String name;
  final String type;
  final String? url;
  final String? server;
  final String? username;
  final String? password;
  final DateTime? expiresAt;

  const RemoteProvisionedService({
    required this.id,
    required this.name,
    required this.type,
    this.url,
    this.server,
    this.username,
    this.password,
    this.expiresAt,
  });

  factory RemoteProvisionedService.fromJson(Map<String, dynamic> json) {
    final rawExpires = json['expires_at']?.toString();
    return RemoteProvisionedService(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'TV FULL',
      type: json['type']?.toString().toLowerCase() ?? '',
      url: json['url']?.toString(),
      server: json['server']?.toString(),
      username: json['username']?.toString(),
      password: json['password']?.toString(),
      expiresAt: rawExpires == null || rawExpires.isEmpty
          ? null
          : DateTime.tryParse(rawExpires),
    );
  }

  String get fingerprint {
    final payload = jsonEncode(<String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'url': url,
      'server': server,
      'username': username,
      'password': password,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }
}

class RemoteProvisioningConfiguration {
  final String deviceCode;
  final List<RemoteProvisionedService> services;
  final DateTime? syncedAt;

  const RemoteProvisioningConfiguration({
    required this.deviceCode,
    required this.services,
    this.syncedAt,
  });
}

class RemoteProvisioningService {
  static const _functionsBase =
      'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1';
  static const _deviceCodeKey = 'tv_full_remote_device_code_v1';
  static const _deviceSecretKey = 'tv_full_remote_device_secret_v1';
  static const _fingerprintsKey = 'tv_full_remote_service_fingerprints_v1';

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<RemoteDeviceCredentials?> loadCredentials() async {
    if (!isSupported) return null;
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_deviceCodeKey)?.trim() ?? '';
    final secret = prefs.getString(_deviceSecretKey)?.trim() ?? '';
    if (code.isEmpty || secret.isEmpty) return null;
    return RemoteDeviceCredentials(code: code, secret: secret);
  }

  Future<void> clearCredentials() async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceCodeKey);
    await prefs.remove(_deviceSecretKey);
  }

  Future<RemoteDeviceCredentials> ensureRegistered() async {
    final existing = await loadCredentials();
    if (existing != null) return existing;
    if (!isSupported) {
      throw StateError(
        'La vinculación remota está disponible en esta compilación para Android TV.',
      );
    }

    final response = await http
        .post(
          Uri.parse('$_functionsBase/tvf-device-register'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(const {
            'platform': 'android_tv',
            'device_name': 'TV FULL Android TV',
            'app_version': '1.0.0+1-android-tv-panel-v3-native-hw',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'El servidor de TV FULL no pudo registrar este dispositivo (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception(
        'El servidor de TV FULL devolvió una respuesta inválida.',
      );
    }
    final data = Map<String, dynamic>.from(decoded);
    final code = data['device_code']?.toString().trim() ?? '';
    final secret = data['device_secret']?.toString().trim() ?? '';
    if (code.isEmpty || secret.isEmpty) {
      throw Exception(
        'El servidor no devolvió las credenciales del dispositivo.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceCodeKey, code);
    await prefs.setString(_deviceSecretKey, secret);
    return RemoteDeviceCredentials(code: code, secret: secret);
  }

  Future<RemoteProvisioningConfiguration> fetchConfiguration(
    RemoteDeviceCredentials credentials,
  ) async {
    final response = await http
        .get(
          Uri.parse('$_functionsBase/tvf-device-config'),
          headers: {
            'Accept': 'application/json',
            'x-tvfull-device-code': credentials.code,
            'x-tvfull-device-secret': credentials.secret,
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 403) {
      throw Exception(
        'Este dispositivo fue desactivado desde el panel TV FULL.',
      );
    }
    if (response.statusCode == 401) {
      throw const RemoteDeviceCredentialsInvalidException();
    }
    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo sincronizar con TV FULL (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception(
        'El servidor de TV FULL devolvió una configuración inválida.',
      );
    }
    final data = Map<String, dynamic>.from(decoded);
    final rawDevice = data['device'];
    final device = rawDevice is Map
        ? Map<String, dynamic>.from(rawDevice)
        : const <String, dynamic>{};
    final rawServices = data['services'];
    final services = <RemoteProvisionedService>[];
    if (rawServices is List) {
      for (final item in rawServices) {
        if (item is! Map) continue;
        final service = RemoteProvisionedService.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (service.id.isEmpty) continue;
        if (service.type != 'm3u' && service.type != 'xtream') continue;
        services.add(service);
      }
    }

    return RemoteProvisioningConfiguration(
      deviceCode: device['code']?.toString() ?? credentials.code,
      services: services,
      syncedAt: DateTime.tryParse(data['synced_at']?.toString() ?? ''),
    );
  }

  Future<Map<String, String>> loadFingerprints() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_fingerprintsKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> saveFingerprints(Map<String, String> fingerprints) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fingerprintsKey, jsonEncode(fingerprints));
  }
}
