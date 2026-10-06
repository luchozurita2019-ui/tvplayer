import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Cifrado local del respaldo del catálogo.
class ProviderJsonBackupCipher {
  static final Uint8List _key = Uint8List.fromList(
    utf8.encode('TV_FULL_PRO_PROVIDER_BACKUP_V3_2026'),
  );

  static String encrypt(String plaintext) {
    final nonce = Uint8List(16);
    final seed = sha256.convert([
      ..._key,
      ...utf8.encode(DateTime.now().microsecondsSinceEpoch.toString()),
    ]).bytes;
    nonce.setRange(0, nonce.length, seed.take(nonce.length));

    final input = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = _xorWithKeystream(input, nonce);
    final mac = Hmac(sha256, _key).convert([...nonce, ...encrypted]).bytes;
    return 'TVF3.' + base64UrlEncode(nonce) + '.' +
        base64UrlEncode(mac) + '.' + base64UrlEncode(encrypted);
  }

  static String decrypt(String payload) {
    final parts = payload.split('.');
    if (parts.length != 4 || parts[0] != 'TVF3') {
      throw const FormatException('Respaldo de catálogo inválido.');
    }
    final nonce = base64Url.decode(parts[1]);
    final expectedMac = base64Url.decode(parts[2]);
    final encrypted = base64Url.decode(parts[3]);
    final actualMac = Hmac(sha256, _key).convert([...nonce, ...encrypted]).bytes;
    if (!_constantTimeEquals(expectedMac, actualMac)) {
      throw const FormatException('Respaldo de catálogo no válido.');
    }
    return utf8.decode(_xorWithKeystream(
      Uint8List.fromList(encrypted),
      Uint8List.fromList(nonce),
    ));
  }

  static Uint8List _xorWithKeystream(Uint8List input, Uint8List nonce) {
    final output = Uint8List(input.length);
    var offset = 0;
    var counter = 0;
    while (offset < input.length) {
      final block = sha256.convert([
        ..._key, ...nonce,
        counter & 0xff, (counter >> 8) & 0xff,
        (counter >> 16) & 0xff, (counter >> 24) & 0xff,
      ]).bytes;
      final length = (input.length - offset) < block.length
          ? input.length - offset : block.length;
      for (var i = 0; i < length; i++) {
        output[offset + i] = input[offset + i] ^ block[i];
      }
      offset += length;
      counter++;
    }
    return output;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}