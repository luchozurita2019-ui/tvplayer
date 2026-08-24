import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceIdentityService {
  DeviceIdentityService._();
  static final DeviceIdentityService instance = DeviceIdentityService._();
  static const MethodChannel _channel = MethodChannel('tvfull/device_identity');
  String? _cachedHash;

  Future<String?> hardwareHash() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    if (_cachedHash != null) return _cachedHash;
    try {
      final value = (await _channel.invokeMethod<String>('getAndroidId'))?.trim();
      if (value == null || value.isEmpty) return null;
      final hash = sha256.convert(utf8.encode('tvfull-pro|android-id|$value')).toString();
      _cachedHash = hash;
      return hash;
    } on PlatformException {
      return null;
    }
  }
}
