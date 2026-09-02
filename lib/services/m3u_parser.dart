import 'dart:convert';

import '../models/channel.dart';

/// Parsea el contenido M3U y devuelve la lista de canales.
///
/// Es una función TOP-LEVEL (no un método de instancia) a propósito:
/// así se puede ejecutar con `compute()` dentro de un isolate separado.
List<Channel> parseM3uInBackground(String content) {
  return M3uParser.parse(content);
}

/// Parser M3U/M3U8 orientado a compatibilidad IPTV.
///
/// Además de #EXTINF reconoce headers frecuentes en reproductores IPTV:
/// - #EXTVLCOPT:http-user-agent / http-referrer / http-origin / http-cookie
/// - #EXTVLCOPT:http-authorization / http-header
/// - #EXTHTTP:{"Header":"valor"}
/// - #KODIPROP:inputstream.adaptive.stream_headers / manifest_headers
/// - URL|User-Agent=...&Referer=...&Origin=...
class M3uParser {
  static List<Channel> parse(String content) {
    final channels = <Channel>[];
    final parser = M3uLineParser();
    for (final line in const LineSplitter().convert(content)) {
      final channel = parser.addLine(line);
      if (channel != null) channels.add(channel);
    }
    return channels;
  }

  static String? _extractAttr(String line, String attr) {
    final pattern = '$attr="';
    final start = line.indexOf(pattern);
    if (start == -1) return null;
    final valueStart = start + pattern.length;
    final end = line.indexOf('"', valueStart);
    if (end == -1) return null;
    final value = line.substring(valueStart, end).trim();
    return value.isEmpty ? null : value;
  }

  static void _parseExtHttp(String raw, Map<String, String> target) {
    final value = raw.trim();
    if (value.isEmpty) return;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = entry.key.toString().trim();
          final headerValue = entry.value?.toString().trim() ?? '';
          if (key.isNotEmpty && headerValue.isNotEmpty) {
            target[key] = headerValue;
          }
        }
      }
    } catch (_) {}
  }

  static void _parseHeaderLine(String value, Map<String, String> target) {
    final colon = value.indexOf(':');
    if (colon <= 0) return;
    final key = value.substring(0, colon).trim();
    final headerValue = value.substring(colon + 1).trim();
    if (key.isNotEmpty && headerValue.isNotEmpty) target[key] = headerValue;
  }

  static void _parseHeaderQuery(String raw, Map<String, String> target) {
    final value = raw.trim();
    if (value.isEmpty) return;
    for (final part in value.split('&')) {
      final equals = part.indexOf('=');
      if (equals <= 0) continue;
      final key = _safeDecode(part.substring(0, equals)).trim();
      final headerValue = _safeDecode(part.substring(equals + 1)).trim();
      if (key.isNotEmpty && headerValue.isNotEmpty) target[key] = headerValue;
    }
  }

  static _ParsedStreamUrl _splitUrlAndInlineHeaders(String line) {
    final pipe = line.indexOf('|');
    if (pipe <= 0 || pipe == line.length - 1) {
      return _ParsedStreamUrl(line.trim(), const {});
    }

    final url = line.substring(0, pipe).trim();
    final headers = <String, String>{};
    _parseHeaderQuery(line.substring(pipe + 1), headers);
    return _ParsedStreamUrl(url, headers);
  }

  static String _safeDecode(String value) {
    try {
      return Uri.decodeComponent(value.replaceAll('+', '%20'));
    } catch (_) {
      return value;
    }
  }

  static String? _headerValue(Map<String, String> headers, String name) {
    final wanted = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }
}

/// Parser incremental: conserva sólo los metadatos pendientes de una entrada y
/// produce un canal en cuanto aparece su URL. Permite consumir listas grandes
/// directamente desde la respuesta HTTP sin `join()` ni `split()` globales.
class M3uLineParser {
  String? pendingName;
  String? pendingLogo;
  String? pendingGroup;
  String? pendingTvgId;
  String? pendingUserAgent;
  String? pendingReferrer;
  final Map<String, String> pendingHeaders = <String, String>{};

  Channel? addLine(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;

    if (line.startsWith('#EXTINF')) {
      final commaIndex = line.indexOf(',');
      pendingName = commaIndex != -1
          ? line.substring(commaIndex + 1).trim()
          : 'Canal sin nombre';

      pendingLogo = M3uParser._extractAttr(line, 'tvg-logo');
      pendingGroup = M3uParser._extractAttr(line, 'group-title');
      pendingTvgId = M3uParser._extractAttr(line, 'tvg-id');
    } else if (line.startsWith('#EXTVLCOPT:')) {
      final rawOption = line.substring('#EXTVLCOPT:'.length).trim();
      final equals = rawOption.indexOf('=');
      if (equals > 0) {
        final key = rawOption.substring(0, equals).trim().toLowerCase();
        final value = rawOption.substring(equals + 1).trim();
        if (value.isNotEmpty) {
          switch (key) {
            case 'http-user-agent':
              pendingUserAgent = value;
              pendingHeaders['User-Agent'] = value;
              break;
            case 'http-referrer':
            case 'http-referer':
              pendingReferrer = value;
              pendingHeaders['Referer'] = value;
              break;
            case 'http-origin':
              pendingHeaders['Origin'] = value;
              break;
            case 'http-cookie':
              pendingHeaders['Cookie'] = value;
              break;
            case 'http-authorization':
              pendingHeaders['Authorization'] = value;
              break;
            case 'http-header':
              M3uParser._parseHeaderLine(value, pendingHeaders);
              break;
          }
        }
      }
    } else if (line.startsWith('#EXTHTTP:')) {
      M3uParser._parseExtHttp(
          line.substring('#EXTHTTP:'.length), pendingHeaders);
    } else if (line.startsWith(
          '#KODIPROP:inputstream.adaptive.stream_headers=',
        ) ||
        line.startsWith('#KODIPROP:inputstream.adaptive.manifest_headers=')) {
      final equals = line.indexOf('=');
      if (equals != -1) {
        M3uParser._parseHeaderQuery(line.substring(equals + 1), pendingHeaders);
      }
    } else if (!line.startsWith('#')) {
      final parsed = M3uParser._splitUrlAndInlineHeaders(line);
      pendingHeaders.addAll(parsed.headers);

      // Sincronizamos los campos históricos para listas guardadas y código
      // existente que todavía los consulta directamente.
      pendingUserAgent ??= M3uParser._headerValue(pendingHeaders, 'User-Agent');
      pendingReferrer ??= M3uParser._headerValue(pendingHeaders, 'Referer');

      final channel = pendingName != null
          ? Channel(
              name: pendingName!,
              url: parsed.url,
              logoUrl: pendingLogo,
              group: pendingGroup,
              tvgId: pendingTvgId,
              httpUserAgent: pendingUserAgent,
              httpReferrer: pendingReferrer,
              httpHeaders: pendingHeaders.isEmpty
                  ? null
                  : Map<String, String>.from(pendingHeaders),
            )
          : Channel(
              name: parsed.url,
              url: parsed.url,
              httpUserAgent: pendingUserAgent,
              httpReferrer: pendingReferrer,
              httpHeaders: pendingHeaders.isEmpty
                  ? null
                  : Map<String, String>.from(pendingHeaders),
            );

      pendingName = null;
      pendingLogo = null;
      pendingGroup = null;
      pendingTvgId = null;
      pendingUserAgent = null;
      pendingReferrer = null;
      pendingHeaders.clear();
      return channel;
    }
    return null;
  }
}

class _ParsedStreamUrl {
  final String url;
  final Map<String, String> headers;

  const _ParsedStreamUrl(this.url, this.headers);
}
