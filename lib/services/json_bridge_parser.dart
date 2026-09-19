import 'dart:convert';

import '../models/channel.dart';

/// Normaliza catálogos JSON autorizados al modelo interno de TV FULL.
///
/// Formatos admitidos:
/// 1) Catálogo TV estilo categories[]/samples[] (Flow/Mundo TV/provider JSON).
/// 2) Agenda estilo array de eventos con canales[].
/// 3) Wrapper de agenda con events[] y un mapa streams/channel_map/resolver.
///
/// El parser NO intenta resolver iframes, páginas web, DRM ni IDs remotos.
/// Para una entrada de agenda basada sólo en canal_id, el JSON puede incluir
/// un mapa autorizado `streams` con la URL reproducible y sus headers.
class JsonBridgeParser {
  const JsonBridgeParser._();

  static JsonBridgeParseResult parse(String content) {
    final decoded = jsonDecode(content);
    final channels = <Channel>[];
    final categories = <String>[];
    final seenCategories = <String>{};
    var unresolved = 0;
    var skippedWeb = 0;
    var skippedDrm = 0;

    void addCategory(String? raw) {
      final value = raw?.trim() ?? '';
      if (value.isNotEmpty && seenCategories.add(value)) {
        categories.add(value);
      }
    }

    void addChannel({
      required Map<String, dynamic> raw,
      required String group,
      Map<String, dynamic>? resolved,
    }) {
      final merged = <String, dynamic>{...raw, if (resolved != null) ...resolved};
      final type = _firstString(merged, const ['type', 'kind']).toUpperCase();

      if (type == 'WEBVIEW' || type == 'WEB' || type == 'IFRAME') {
        skippedWeb++;
        return;
      }

      final drm = _firstString(
        merged,
        const ['drm_license_uri', 'drm', 'clearkey', 'license'],
      );
      if (drm.isNotEmpty) {
        skippedDrm++;
        return;
      }

      final url = _firstString(
        merged,
        const [
          'original_url',
          'url',
          'playback_url',
          'stream_url',
          'media_url',
          'm3u8',
          'mpd',
        ],
      );
      if (!_isHttpUrl(url)) {
        unresolved++;
        return;
      }

      final name = _firstString(
        merged,
        const ['name', 'canal', 'title', 'channel_name'],
      );
      final logo = _firstString(
        merged,
        const ['icono', 'logo', 'logo_url', 'logoUrl'],
      );
      final headers = _headers(merged);
      final userAgent = _takeHeader(headers, 'user-agent');
      final referrer = _takeHeader(headers, 'referer') ??
          _takeHeader(headers, 'referrer');

      channels.add(
        Channel(
          name: name.isEmpty ? 'Canal' : name,
          url: url,
          logoUrl: logo.isEmpty ? null : logo,
          group: group.isEmpty ? null : group,
          httpUserAgent: userAgent,
          httpReferrer: referrer,
          httpHeaders: headers.isEmpty ? null : headers,
        ),
      );
      addCategory(group);
    }

    if (decoded is Map) {
      final root = _asStringMap(decoded);
      final resolver = _resolverMap(root);

      final rawCategories = root['categories'];
      if (rawCategories is List) {
        for (final categoryRaw in rawCategories) {
          if (categoryRaw is! Map) continue;
          final category = _asStringMap(categoryRaw);
          final group = _firstString(category, const ['name', 'category']);
          final samples = category['samples'];
          if (samples is! List) continue;
          for (final sampleRaw in samples) {
            if (sampleRaw is! Map) continue;
            addChannel(raw: _asStringMap(sampleRaw), group: group);
          }
        }
      } else {
        final events = root['events'];
        if (events is List) {
          _parseAgenda(
            events,
            resolver,
            addChannel,
          );
        } else {
          final flat = root['channels'];
          if (flat is List) {
            for (final itemRaw in flat) {
              if (itemRaw is! Map) continue;
              final item = _asStringMap(itemRaw);
              final group = _firstString(
                item,
                const ['group', 'category', 'categoria'],
              );
              addChannel(raw: item, group: group);
            }
          } else {
            throw const FormatException(
              'JSON no reconocido: faltan categories, events o channels.',
            );
          }
        }
      }
    } else if (decoded is List) {
      _parseAgenda(decoded, const <String, dynamic>{}, addChannel);
    } else {
      throw const FormatException('El puente JSON espera un objeto o un array.');
    }

    return JsonBridgeParseResult(
      channels: List<Channel>.unmodifiable(channels),
      categories: List<String>.unmodifiable(categories),
      unresolved: unresolved,
      skippedWeb: skippedWeb,
      skippedDrm: skippedDrm,
    );
  }

  static void _parseAgenda(
    List<dynamic> events,
    Map<String, dynamic> resolver,
    void Function({
      required Map<String, dynamic> raw,
      required String group,
      Map<String, dynamic>? resolved,
    }) addChannel,
  ) {
    for (final eventRaw in events) {
      if (eventRaw is! Map) continue;
      final event = _asStringMap(eventRaw);
      final status = _firstString(event, const ['status']).toLowerCase();
      if (status.contains('final')) continue;

      final title = _firstString(
        event,
        const ['titulo', 'title', 'categoria', 'category'],
      );
      final safeTitle = title.isEmpty ? 'Partido' : title;
      final group = status.contains('vivo') || status.contains('live')
          ? '🔴 EN VIVO · $safeTitle'
          : safeTitle;

      final rawChannels = event['canales'] ?? event['channels'];
      if (rawChannels is! List) continue;

      for (final channelRaw in rawChannels) {
        if (channelRaw is! Map) continue;
        final channel = _asStringMap(channelRaw);
        if (_asBool(channel['con_anuncios'])) continue;

        final canalId = _firstString(
          channel,
          const ['canal_id', 'channel_id', 'id'],
        );
        final resolvedRaw = canalId.isEmpty ? null : resolver[canalId];
        Map<String, dynamic>? resolved;
        if (resolvedRaw is String) {
          resolved = <String, dynamic>{'url': resolvedRaw};
        } else if (resolvedRaw is Map) {
          resolved = _asStringMap(resolvedRaw);
        }
        addChannel(raw: channel, group: group, resolved: resolved);
      }
    }
  }

  static Map<String, dynamic> _resolverMap(Map<String, dynamic> root) {
    final raw = root['streams'] ?? root['channel_map'] ?? root['resolver'];
    if (raw is! Map) return const <String, dynamic>{};
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim();
      if (key.isNotEmpty) result[key] = entry.value;
    }
    return result;
  }

  static Map<String, String> _headers(Map<String, dynamic> raw) {
    final headers = <String, String>{};

    void put(String key, dynamic value) {
      final cleanKey = key.trim();
      final cleanValue = value?.toString().trim() ?? '';
      if (cleanKey.isEmpty || cleanValue.isEmpty) return;
      headers[cleanKey] = cleanValue;
    }

    final map = raw['headers'] ?? raw['http_headers'] ?? raw['httpHeaders'];
    if (map is Map) {
      for (final entry in map.entries) {
        put(entry.key.toString(), entry.value);
      }
    }

    put('User-Agent', raw['user_agent'] ?? raw['userAgent'] ?? raw['httpUserAgent']);
    put('Referer', raw['referer'] ?? raw['referrer'] ?? raw['httpReferrer']);
    put('Origin', raw['origin']);
    return headers;
  }

  static String? _takeHeader(Map<String, String> headers, String name) {
    String? foundKey;
    for (final key in headers.keys) {
      if (key.toLowerCase() == name.toLowerCase()) {
        foundKey = key;
        break;
      }
    }
    if (foundKey == null) return null;
    return headers.remove(foundKey);
  }

  static String _firstString(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == '1' || text == 'true' || text == 'yes' || text == 'si';
  }

  static Map<String, dynamic> _asStringMap(Map<dynamic, dynamic> raw) =>
      <String, dynamic>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
}

class JsonBridgeParseResult {
  final List<Channel> channels;
  final List<String> categories;
  final int unresolved;
  final int skippedWeb;
  final int skippedDrm;

  const JsonBridgeParseResult({
    required this.channels,
    required this.categories,
    required this.unresolved,
    required this.skippedWeb,
    required this.skippedDrm,
  });
}
