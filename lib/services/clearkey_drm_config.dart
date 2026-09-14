import 'dart:convert';
import 'dart:typed_data';

/// ClearKey suministrado por el catálogo/proveedor. Internamente se normaliza
/// siempre a 16 bytes representados como 32 caracteres hexadecimales para que
/// Channel mantenga un formato estable al persistirlo.
class ClearKeyDrmConfig {
  final String keyId;
  final String key;

  ClearKeyDrmConfig.fromHex(String keyId, String key)
    : keyId = _normalize(keyId),
      key = _normalize(key);

  factory ClearKeyDrmConfig.parse(String value) {
    final fields = <String, String>{};
    for (final part in value.split(',')) {
      final separator = part.indexOf(':');
      if (separator <= 0 || separator == part.length - 1) {
        throw const FormatException(
          'ClearKey debe tener formato kid:VALOR,k:VALOR.',
        );
      }
      final name = part.substring(0, separator).trim().toLowerCase();
      if ((name != 'kid' && name != 'k') || fields.containsKey(name)) {
        throw const FormatException(
          'ClearKey contiene campos inválidos o repetidos.',
        );
      }
      fields[name] = part.substring(separator + 1).trim();
    }
    if (fields.length != 2 ||
        !fields.containsKey('kid') ||
        !fields.containsKey('k')) {
      throw const FormatException('ClearKey requiere kid y k.');
    }
    return ClearKeyDrmConfig.fromHex(fields['kid']!, fields['k']!);
  }

  static String _normalize(String value) {
    final raw = value.trim();
    if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(raw)) {
      return raw.toLowerCase();
    }

    // El APK/catálogo de integración del proveedor usa frecuentemente
    // Base64URL sin padding para kid/k. Deben decodificar exactamente 16 bytes.
    if (!RegExp(r'^[A-Za-z0-9_-]{20,24}={0,2}$').hasMatch(raw)) {
      throw const FormatException(
        'kid y k deben ser ClearKey de 16 bytes en HEX o Base64URL.',
      );
    }
    try {
      var padded = raw;
      final remainder = padded.length % 4;
      if (remainder != 0) padded += '=' * (4 - remainder);
      final bytes = base64Url.decode(padded);
      if (bytes.length != 16) {
        throw const FormatException(
          'kid y k deben representar exactamente 16 bytes.',
        );
      }
      final out = StringBuffer();
      for (final byte in bytes) {
        out.write(byte.toRadixString(16).padLeft(2, '0'));
      }
      return out.toString();
    } on FormatException {
      throw const FormatException(
        'kid y k deben ser ClearKey de 16 bytes en HEX o Base64URL.',
      );
    }
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
