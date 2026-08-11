import 'package:http/http.dart' as http;

/// Cliente HTTP compartido para todas las llamadas Xtream.
///
/// Mantener una sola instancia permite que dart:io reutilice DNS, sockets,
/// conexiones TCP/TLS y keep-alive entre player_api.php, categorías, VOD,
/// series y fichas. Las imágenes usan su propio cliente porque su cola se
/// cancela/pausa de forma independiente durante la reproducción.
class XtreamHttpClient {
  XtreamHttpClient._();

  static final http.Client instance = http.Client();

  static const String browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  static const Map<String, String> jsonHeaders = <String, String>{
    'User-Agent': browserUserAgent,
    'Accept': 'application/json,text/plain,*/*',
    // dart:io negocia y descomprime gzip automáticamente. No fijamos
    // Accept-Encoding a mano para conservar ese comportamiento en clones raros.
    'Connection': 'keep-alive',
  };
}
