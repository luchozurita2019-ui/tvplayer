import 'dart:convert';
import 'dart:typed_data';

import 'channel_backup.dart';

/// Representa un canal de cualquiera de las fuentes soportadas.
class Channel {
  final String name;
  final String url;
  final String? logoUrl;
  final Uint8List? logoBytes;
  final String? drmKeyId;
  final String? drmKey;
  final String? streamMimeType;
  final String? playbackProfile;
  final String? group; // categoría (ej: "Deportes", "Noticias")
  final String? tvgId; // id XMLTV/EPG del proveedor
  final String? xtreamStreamId; // stream_id real para APIs Xtream (EPG, etc.)
  final String? dynamicStreamId; // identidad estable usada por el resolvedor
  final String? dynamicStreamPath; // ruta original de provider.json
  final String?
  providerGlobalIndex; // índice del catálogo si el proveedor lo usa

  // Compatibilidad histórica: seguimos exponiendo User-Agent y Referer de
  // forma explícita porque ya existen listas guardadas con estos campos.
  final String? httpUserAgent;
  final String? httpReferrer;

  // Headers adicionales que algunos proveedores requieren para autorizar el
  // stream (Origin, Cookie, Authorization, Accept, etc.). Nunca se inventan:
  // sólo se conservan cuando vienen declarados por la lista M3U/URL.
  final Map<String, String>? httpHeaders;
  final List<ChannelBackup> backups;

  const Channel({
    required this.name,
    required this.url,
    this.logoUrl,
    this.logoBytes,
    this.drmKeyId,
    this.drmKey,
    this.streamMimeType,
    this.playbackProfile,
    this.group,
    this.tvgId,
    this.xtreamStreamId,
    this.dynamicStreamId,
    this.dynamicStreamPath,
    this.providerGlobalIndex,
    this.httpUserAgent,
    this.httpReferrer,
    this.httpHeaders,
    this.backups = const [],
  });

  bool get hasClearKey => drmKeyId != null && drmKey != null;

  // También reconoce configuraciones incompletas para que fallen con un mensaje
  // claro en Media3, en lugar de enviarlas a un reproductor sin DRM.
  bool get hasDrmConfiguration => drmKeyId != null || drmKey != null;

  List<ChannelBackup> get validBackups {
    final primary = ChannelBackup.tryFromJson({
      'url': url,
      'headers': resolvedHttpHeaders('', includeDefaultUserAgent: false),
    });
    final seen = <String>{if (primary != null) primary.transportKey};
    final result = <ChannelBackup>[];
    for (final raw in backups) {
      final backup = ChannelBackup.tryFromJson(raw.toJson());
      if (backup != null && seen.add(backup.transportKey)) result.add(backup);
      if (result.length == 2) break;
    }
    return List.unmodifiable(result);
  }

  Map<String, String> resolvedHttpHeaders(
    String defaultUserAgent, {
    bool includeDefaultUserAgent = true,
  }) {
    final result = <String, String>{};

    void put(String rawKey, String rawValue) {
      final key = rawKey.trim();
      final value = rawValue.trim();
      if (key.isEmpty || value.isEmpty) return;

      // HTTP no distingue mayúsculas/minúsculas en nombres de headers. Evitar
      // pares duplicados como Referer/referer mejora compatibilidad con proxies
      // y servidores estrictos y permite que el proveedor reemplace defaults.
      String? duplicate;
      for (final existing in result.keys) {
        if (existing.toLowerCase() == key.toLowerCase()) {
          duplicate = existing;
          break;
        }
      }
      if (duplicate != null) result.remove(duplicate);
      result[_canonicalHeaderName(key)] = value;
    }

    if (httpUserAgent != null) {
      put('User-Agent', httpUserAgent!);
    } else if (includeDefaultUserAgent) {
      put('User-Agent', defaultUserAgent);
    }
    if (httpReferrer != null) put('Referer', httpReferrer!);

    final extras = httpHeaders;
    if (extras != null) {
      for (final entry in extras.entries) {
        put(entry.key, entry.value);
      }
    }
    return result;
  }

  static String _canonicalHeaderName(String key) {
    return switch (key.trim().toLowerCase()) {
      'user-agent' => 'User-Agent',
      'referer' => 'Referer',
      'referrer' => 'Referer',
      'origin' => 'Origin',
      'cookie' => 'Cookie',
      'authorization' => 'Authorization',
      'accept' => 'Accept',
      'accept-language' => 'Accept-Language',
      'connection' => 'Connection',
      'host' => 'Host',
      _ => key.trim(),
    };
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'logoUrl': logoUrl,
    'group': group,
    'tvgId': tvgId,
    'xtreamStreamId': xtreamStreamId,
    if (dynamicStreamId != null) 'dynamicStreamId': dynamicStreamId,
    if (dynamicStreamPath != null) 'dynamicStreamPath': dynamicStreamPath,
    if (providerGlobalIndex != null) 'providerGlobalIndex': providerGlobalIndex,
    'httpUserAgent': httpUserAgent,
    'httpReferrer': httpReferrer,
    if (httpHeaders != null) 'httpHeaders': httpHeaders,
    if (validBackups.isNotEmpty)
      'backups': validBackups.map((source) => source.toJson()).toList(),
    if (logoBytes != null) 'logoBase64': base64Encode(logoBytes!),
    if (drmKeyId != null) 'drmKeyId': drmKeyId,
    if (drmKey != null) 'drmKey': drmKey,
    if (streamMimeType != null) 'streamMimeType': streamMimeType,
    if (playbackProfile != null) 'playbackProfile': playbackProfile,
  };

  factory Channel.fromJson(Map<String, dynamic> json) {
    Uint8List? logoBytes;
    final rawLogo = json['logoBase64'];
    if (rawLogo is String) {
      try {
        logoBytes = base64Decode(rawLogo);
      } on FormatException {
        // Una imagen dañada no impide recuperar el canal.
      }
    }
    final keyId = json['drmKeyId'];
    final key = json['drmKey'];
    if (keyId != null || key != null) {
      final hex = RegExp(r'^[0-9a-fA-F]{32}$');
      if (keyId is! String ||
          key is! String ||
          !hex.hasMatch(keyId) ||
          !hex.hasMatch(key)) {
        throw const FormatException(
          'Configuración ClearKey guardada inválida.',
        );
      }
    }
    final rawHeaders = json['httpHeaders'];
    Map<String, String>? headers;
    if (rawHeaders is Map) {
      headers = <String, String>{};
      for (final entry in rawHeaders.entries) {
        final key = entry.key?.toString().trim() ?? '';
        final value = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) headers[key] = value;
      }
      if (headers.isEmpty) headers = null;
    }

    return Channel(
      name: json['name'] as String,
      url: json['url'] as String,
      logoUrl: json['logoUrl'] as String?,
      logoBytes: logoBytes,
      drmKeyId: keyId as String?,
      drmKey: key as String?,
      streamMimeType: json['streamMimeType'] is String
          ? json['streamMimeType'] as String
          : null,
      playbackProfile: json['playbackProfile'] is String
          ? json['playbackProfile'] as String
          : null,
      group: json['group'] as String?,
      tvgId: json['tvgId'] as String?,
      xtreamStreamId: json['xtreamStreamId'] as String?,
      dynamicStreamId: json['dynamicStreamId'] as String?,
      dynamicStreamPath: json['dynamicStreamPath'] as String?,
      providerGlobalIndex: json['providerGlobalIndex'] as String?,
      httpUserAgent: json['httpUserAgent'] as String?,
      httpReferrer: json['httpReferrer'] as String?,
      httpHeaders: headers,
      backups: json['backups'] is List
          ? (json['backups'] as List)
                .map(ChannelBackup.tryFromJson)
                .whereType<ChannelBackup>()
                .take(2)
                .toList(growable: false)
          : const [],
    );
  }

  /// Clave estable para identificar el canal (usada en favoritos).
  String get uniqueKey {
    final dynamicId = dynamicStreamId?.trim();
    return dynamicId == null || dynamicId.isEmpty
        ? '$name|$url'
        : '$name|dynamic:$dynamicId';
  }

  @override
  bool operator ==(Object other) =>
      other is Channel && other.uniqueKey == uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;
}
