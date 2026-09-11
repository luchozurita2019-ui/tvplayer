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
  static List<Channel> parse(String content, {Uri? baseUri}) {
    final channels = <Channel>[];
    final parser = M3uLineParser(baseUri: baseUri);
    var first = true;
    for (var line in const LineSplitter().convert(content)) {
      if (first) {
        line = _stripBom(line);
        first = false;
      }
      final channel = parser.addLine(line);
      if (channel != null) channels.add(channel);
    }
    return channels;
  }

  static String _stripBom(String value) =>
      value.startsWith('\uFEFF') ? value.substring(1) : value;

  static String? _extractAttr(String line, String attr) {
    final escaped = RegExp.escape(attr);
    final doubleQuoted = RegExp(
      '(?:^|\\s)$escaped\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(line);
    final singleQuoted = doubleQuoted == null
        ? RegExp(
            "(?:^|\\s)$escaped\\s*=\\s*'([^']*)'",
            caseSensitive: false,
          ).firstMatch(line)
        : null;
    final value = (doubleQuoted?.group(1) ?? singleQuoted?.group(1))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Devuelve la primera coma que no esté dentro de comillas. EXTINF permite
  /// comas en atributos/títulos y cortar en la primera coma literal corrompe
  /// metadatos perfectamente válidos.
  static int _metadataComma(String line) {
    var quote = 0;
    for (var i = 0; i < line.length; i++) {
      final unit = line.codeUnitAt(i);
      if (unit == 0x22 || unit == 0x27) {
        if (quote == 0) {
          quote = unit;
        } else if (quote == unit) {
          quote = 0;
        }
      } else if (unit == 0x2C && quote == 0) {
        return i;
      }
    }
    return -1;
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
  final Uri? baseUri;
  bool _firstLine = true;

  String? pendingName;
  String? pendingLogo;
  String? pendingGroup;
  String? pendingTvgId;
  String? pendingUserAgent;
  String? pendingReferrer;
  final Map<String, String> pendingHeaders = <String, String>{};

  M3uLineParser({this.baseUri});

  Channel? addLine(String rawLine) {
    var line = rawLine.trim();
    if (_firstLine) {
      line = M3uParser._stripBom(line);
      _firstLine = false;
    }
    if (line.isEmpty) return null;

    if (line.toUpperCase().startsWith('#EXTINF')) {
      // Un EXTINF nuevo invalida cualquier entrada anterior incompleta. Evita
      // que headers/metadatos huérfanos contaminen el siguiente canal.
      _resetPending();
      final commaIndex = M3uParser._metadataComma(line);
      pendingName = commaIndex != -1
          ? line.substring(commaIndex + 1).trim()
          : 'Canal sin nombre';

      pendingLogo = M3uParser._extractAttr(line, 'tvg-logo');
      pendingGroup = M3uParser._extractAttr(line, 'group-title');
      pendingTvgId = M3uParser._extractAttr(line, 'tvg-id');
    } else if (line.toUpperCase().startsWith('#EXTVLCOPT:')) {
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
    } else if (line.toUpperCase().startsWith('#EXTHTTP:')) {
      M3uParser._parseExtHttp(
        line.substring('#EXTHTTP:'.length),
        pendingHeaders,
      );
    } else if (line.toLowerCase().startsWith(
          '#kodiprop:inputstream.adaptive.stream_headers=',
        ) ||
        line.toLowerCase().startsWith(
          '#kodiprop:inputstream.adaptive.manifest_headers=',
        )) {
      final equals = line.indexOf('=');
      if (equals != -1) {
        M3uParser._parseHeaderQuery(line.substring(equals + 1), pendingHeaders);
      }
    } else if (!line.startsWith('#')) {
      final parsed = M3uParser._splitUrlAndInlineHeaders(line);
      final normalizedUrl = _normalizeStreamUrl(parsed.url);
      if (normalizedUrl == null) {
        // HTML/texto de error con HTTP 200 no debe transformarse en canales.
        // Conservamos metadatos pendientes por si la siguiente línea sí es URL.
        return null;
      }
      pendingHeaders.addAll(parsed.headers);

      // Sincronizamos los campos históricos para listas guardadas y código
      // existente que todavía los consulta directamente.
      pendingUserAgent ??= M3uParser._headerValue(pendingHeaders, 'User-Agent');
      pendingReferrer ??= M3uParser._headerValue(pendingHeaders, 'Referer');

      final channel = pendingName != null
          ? Channel(
              name: pendingName!,
              url: normalizedUrl,
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
              name: normalizedUrl,
              url: normalizedUrl,
              httpUserAgent: pendingUserAgent,
              httpReferrer: pendingReferrer,
              httpHeaders: pendingHeaders.isEmpty
                  ? null
                  : Map<String, String>.from(pendingHeaders),
            );

      _resetPending();
      return channel;
    }
    return null;
  }

  String? _normalizeStreamUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.startsWith('<')) return null;
    final lowered = value.toLowerCase();
    if (lowered.startsWith('<!doctype') ||
        lowered.startsWith('<html') ||
        lowered.startsWith('{"error"') ||
        lowered.startsWith('{"message"')) {
      return null;
    }

    final parsed = Uri.tryParse(value);
    if (parsed == null) return null;
    if (parsed.hasScheme) {
      const supported = <String>{
        'http',
        'https',
        'rtsp',
        'rtmp',
        'rtp',
        'udp',
      };
      if (!supported.contains(parsed.scheme.toLowerCase())) return null;
      if ((parsed.scheme == 'http' || parsed.scheme == 'https') &&
          parsed.host.isEmpty) {
        return null;
      }
      return parsed.toString();
    }

    final base = baseUri;
    if (base == null || !base.hasScheme) return null;
    try {
      return base.resolveUri(parsed).toString();
    } catch (_) {
      return null;
    }
  }

  void _resetPending() {
    pendingName = null;
    pendingLogo = null;
    pendingGroup = null;
    pendingTvgId = null;
    pendingUserAgent = null;
    pendingReferrer = null;
    pendingHeaders.clear();
  }
}

class _ParsedStreamUrl {
  final String url;
  final Map<String, String> headers;

  const _ParsedStreamUrl(this.url, this.headers);
}
