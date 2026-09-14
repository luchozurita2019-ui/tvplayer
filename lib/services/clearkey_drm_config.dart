import 'dart:convert';
import 'dart:typed_data';

/// Claves provistas por el usuario. No realiza peticiones ni registra secretos.
class ClearKeyDrmConfig {
  final String keyId;
  final String key;

  ClearKeyDrmConfig.fromHex(String keyId, String key)
    : keyId = _validate(keyId),
      key = _validate(key);

  factory ClearKeyDrmConfig.parse(String value) {
    final fields = <String, String>{};
    for (final part in value.split(',')) {
      final pair = part.split(':');
      if (pair.length != 2) {
        throw const FormatException(
          'ClearKey debe tener formato kid:HEX,k:HEX.',
        );
      }
      final name = pair[0].trim().toLowerCase();
      if ((name != 'kid' && name != 'k') || fields.containsKey(name)) {
        throw const FormatException(
          'ClearKey contiene campos inválidos o repetidos.',
        );
      }
      fields[name] = pair[1].trim();
    }
    if (fields.length != 2 ||
        !fields.containsKey('kid') ||
        !fields.containsKey('k')) {
      throw const FormatException('ClearKey requiere kid y k.');
    }
    return ClearKeyDrmConfig.fromHex(fields['kid']!, fields['k']!);
  }

  static String _validate(String value) {
    final hex = value.trim();
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)) {
      throw const FormatException(
        'kid y k deben tener 32 caracteres hexadecimales cada uno.',
      );
    }
    return hex.toLowerCase();
  }

  static String _base64Url(String hex) {
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String toJwkSet() => jsonEncode({
    'keys': [
      {'kty': 'oct', 'kid': _base64Url(keyId), 'k': _base64Url(key)},
    ],
    'type': 'temporary',
  });
}
