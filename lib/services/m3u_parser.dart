import '../models/channel.dart';

/// Parsea el contenido M3U y devuelve la lista de canales.
///
/// Es una función TOP-LEVEL (no un método de instancia) a propósito:
/// así se puede ejecutar con `compute()` dentro de un isolate separado.
/// Con listas de 10.000+ canales, parsear en el hilo principal congela
/// la UI un momento notorio (jank); en un isolate, la app sigue fluida
/// mientras se procesa en segundo plano.
List<Channel> parseM3uInBackground(String content) {
  return M3uParser.parse(content);
}

/// Parser de archivos M3U/M3U8 extendidos (formato #EXTM3U / #EXTINF).
///
/// Diseñado para listas grandes (10k+ canales, común en IPTV):
/// - Una sola pasada por el texto (O(n)), sin regex pesadas por línea.
/// - No crea objetos intermedios innecesarios.
/// - Reconoce líneas #EXTVLCOPT (User-Agent / Referer por canal), que
///   algunos proveedores incluyen porque su servidor exige headers
///   específicos para dejar pasar la conexión.
class M3uParser {
  static List<Channel> parse(String content) {
    final lines = content.split('\n');
    final channels = <Channel>[];

    String? pendingName;
    String? pendingLogo;
    String? pendingGroup;
    String? pendingTvgId;
    String? pendingUserAgent;
    String? pendingReferrer;

    for (var rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF')) {
        // Ejemplo:
        // #EXTINF:-1 tvg-id="cnn" tvg-logo="http://x/cnn.png" group-title="Noticias",CNN HD
        final commaIndex = line.indexOf(',');
        pendingName = commaIndex != -1
            ? line.substring(commaIndex + 1).trim()
            : 'Canal sin nombre';

        pendingLogo = _extractAttr(line, 'tvg-logo');
        pendingGroup = _extractAttr(line, 'group-title');
        pendingTvgId = _extractAttr(line, 'tvg-id');
      } else if (line.startsWith('#EXTVLCOPT:http-user-agent=')) {
        pendingUserAgent =
            line.substring('#EXTVLCOPT:http-user-agent='.length).trim();
      } else if (line.startsWith('#EXTVLCOPT:http-referrer=')) {
        pendingReferrer =
            line.substring('#EXTVLCOPT:http-referrer='.length).trim();
      } else if (!line.startsWith('#')) {
        // Es la URL del stream, cierra la entrada pendiente.
        if (pendingName != null) {
          channels.add(Channel(
            name: pendingName,
            url: line,
            logoUrl: pendingLogo,
            group: pendingGroup,
            tvgId: pendingTvgId,
            httpUserAgent: pendingUserAgent,
            httpReferrer: pendingReferrer,
          ));
        } else {
          // M3U simple sin #EXTINF: usamos la URL como nombre.
          channels.add(Channel(name: line, url: line));
        }
        pendingName = null;
        pendingLogo = null;
        pendingGroup = null;
        pendingTvgId = null;
        pendingUserAgent = null;
        pendingReferrer = null;
      }
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
}
