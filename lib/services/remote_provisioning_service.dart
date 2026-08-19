import 'dart:convert';

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

class RemoteDeviceAccessBlockedException implements Exception {
  final String reason;
  final String title;
  final String message;

  const RemoteDeviceAccessBlockedException({
    required this.reason,
    required this.title,
    required this.message,
  });

  bool get isPaymentDue => reason == 'payment_due';

  @override
  String toString() => message;
}

class RemoteProvisioningService {
  static const _functionsBase =
      'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1';
  static const _deviceCodeKey = 'tv_full_mobile_device_code_v1';
  static const _deviceSecretKey = 'tv_full_mobile_device_secret_v1';

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
      throw StateError('La vinculación remota requiere Android.');
    }

    final response = await http
        .post(
          Uri.parse('$_functionsBase/tvf-device-register'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(const {
            'platform': 'android',
            'device_name': 'TV FULL Android Celular',
            'app_version': '1.0.0+1-android-mobile-payment-status-v1',
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
      throw Exception('El servidor de TV FULL devolvió una respuesta inválida.');
    }
    final data = Map<String, dynamic>.from(decoded);
    final code = data['device_code']?.toString().trim() ?? '';
    final secret = data['device_secret']?.toString().trim() ?? '';
    if (code.isEmpty || secret.isEmpty) {
      throw Exception('El servidor no devolvió las credenciales del dispositivo.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceCodeKey, code);
    await prefs.setString(_deviceSecretKey, secret);
    return RemoteDeviceCredentials(code: code, secret: secret);
  }

  Future<void> verifyAccess(RemoteDeviceCredentials credentials) async {
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
      String reason = 'device_disabled';
      String title = 'Acceso suspendido';
      String message =
          'Este dispositivo fue desactivado desde el panel TV FULL.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final data = Map<String, dynamic>.from(decoded);
          final serverReason = data['error']?.toString().trim() ?? '';
          final serverTitle = data['title']?.toString().trim() ?? '';
          final serverMessage = data['message']?.toString().trim() ?? '';
          if (serverReason.isNotEmpty) reason = serverReason;
          if (serverTitle.isNotEmpty) title = serverTitle;
          if (serverMessage.isNotEmpty) message = serverMessage;
        }
      } catch (_) {
        // Si el servidor no devuelve JSON válido se conserva el mensaje genérico.
      }
      throw RemoteDeviceAccessBlockedException(
        reason: reason,
        title: title,
        message: message,
      );
    }

    if (response.statusCode == 401) {
      throw const RemoteDeviceCredentialsInvalidException();
    }

    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo verificar el acceso con TV FULL (HTTP ${response.statusCode}).',
      );
    }
  }
}
