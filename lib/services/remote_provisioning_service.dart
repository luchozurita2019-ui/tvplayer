import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity_service.dart';

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
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : 'TV FULL PRO',
      type: json['type']?.toString().trim().toLowerCase() ?? '',
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
    final payload = jsonEncode({
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
  static const _identityBoundKey = 'tv_full_remote_identity_bound_v1';
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
    await prefs.remove(_identityBoundKey);
  }

  Future<RemoteDeviceCredentials> ensureRegistered() async {
    if (!isSupported) {
      throw StateError('La vinculación remota requiere Android TV.');
    }
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadCredentials();
    final hardwareHash = await DeviceIdentityService.instance.hardwareHash();

    if (existing != null && prefs.getBool(_identityBoundKey) == true) {
      return existing;
    }

    final body = <String, dynamic>{
      'platform': 'android_tv',
      'device_name': 'TV FULL PRO Android TV',
      'app_version': '1.1.0+2-tv-full-pro-clean',
      if (hardwareHash != null) 'hardware_hash': hardwareHash,
      if (existing != null) 'device_code': existing.code,
      if (existing != null) 'device_secret': existing.secret,
    };

    try {
      final response = await http
          .post(
            Uri.parse('$_functionsBase/tvf-device-register'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 && response.statusCode != 201) {
        if (existing != null) return existing;
        throw Exception('No se pudo registrar la TV (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Registro inválido.');
      final data = Map<String, dynamic>.from(decoded);
      final code = data['device_code']?.toString().trim() ?? '';
      final secret = data['device_secret']?.toString().trim() ?? '';
      if (code.isEmpty || secret.isEmpty) {
        if (existing != null) return existing;
        throw const FormatException('Registro sin credenciales.');
      }
      await prefs.setString(_deviceCodeKey, code);
      await prefs.setString(_deviceSecretKey, secret);
      if (hardwareHash != null) await prefs.setBool(_identityBoundKey, true);
      return RemoteDeviceCredentials(code: code, secret: secret);
    } catch (_) {
      if (existing != null) return existing;
      rethrow;
    }
  }

  Future<RemoteProvisioningConfiguration> fetchConfiguration(
    RemoteDeviceCredentials credentials,
  ) async {
    final response = await http.get(
      Uri.parse('$_functionsBase/tvf-device-config'),
      headers: {
        'Accept': 'application/json',
        'x-tvfull-device-code': credentials.code,
        'x-tvfull-device-secret': credentials.secret,
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 401) {
      throw const RemoteDeviceCredentialsInvalidException();
    }
    if (response.statusCode == 403) {
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          throw Exception(body['message'].toString());
        }
      } catch (error) {
        if (error is Exception) rethrow;
      }
      throw Exception('Este dispositivo fue desactivado desde TV FULL PRO.');
    }
    if (response.statusCode != 200) {
      throw Exception('No se pudo sincronizar TV FULL PRO (HTTP ${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Configuración inválida.');
    final data = Map<String, dynamic>.from(decoded);
    final rawDevice = data['device'];
    final device = rawDevice is Map
        ? Map<String, dynamic>.from(rawDevice)
        : const <String, dynamic>{};
    final services = <RemoteProvisionedService>[];
    final rawServices = data['services'];
    if (rawServices is List) {
      for (final raw in rawServices) {
        if (raw is! Map) continue;
        final service = RemoteProvisionedService.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (service.id.isEmpty) continue;
        if (service.type != 'm3u' && service.type != 'xtream') continue;
        services.add(service);
      }
    }
    return RemoteProvisioningConfiguration(
      deviceCode: device['code']?.toString() ?? credentials.code,
      services: List.unmodifiable(services),
      syncedAt: DateTime.tryParse(data['synced_at']?.toString() ?? ''),
    );
  }

  Future<Map<String, String>> loadFingerprints() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_fingerprintsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveFingerprints(Map<String, String> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fingerprintsKey, jsonEncode(values));
  }
}
