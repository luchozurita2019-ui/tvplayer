import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Descarga el contenido de una lista M3U remota.
///
/// Robustez ante servidores IPTV lentos o inestables (muy común):
/// - Timeout por intento, para que la UI nunca se sienta "colgada".
/// - Reintentos automáticos con backoff exponencial (1s, 2s, 4s) antes
///   de rendirse, porque muchos servidores IPTV fallan de forma
///   intermitente y un segundo intento suele funcionar.
/// - Cliente HTTP reutilizado (keep-alive) en vez de crear uno nuevo
///   por request, más rápido en descargas sucesivas.
class M3uFetcher {
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';
  static final http.Client _client = http.Client();

  static Future<String> fetch(
    String url, {
    int maxRetries = 3,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Object? lastError;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await _client.get(
          Uri.parse(url),
          headers: const {
            'User-Agent': _browserUserAgent,
            'Accept': 'application/x-mpegURL,application/vnd.apple.mpegurl,text/plain,*/*',
          },
        ).timeout(timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.body;
        }

        if (response.statusCode >= 500 && attempt < maxRetries) {
          // Error del servidor: vale la pena reintentar.
          lastError = Exception(
              'El servidor respondió con código ${response.statusCode}');
          await _backoff(attempt);
          continue;
        }

        throw Exception(
            'El servidor respondió con código ${response.statusCode}');
      } on TimeoutException {
        lastError = Exception('El servidor tardó demasiado en responder');
        if (attempt < maxRetries) {
          await _backoff(attempt);
          continue;
        }
      } on SocketException {
        lastError =
            Exception('No hay conexión a internet o el servidor no responde');
        if (attempt < maxRetries) {
          await _backoff(attempt);
          continue;
        }
      } on HttpException {
        lastError = Exception('Error al conectar con el servidor de la lista');
        if (attempt < maxRetries) {
          await _backoff(attempt);
          continue;
        }
      }
    }

    throw lastError ?? Exception('No se pudo descargar la lista');
  }

  static Future<void> _backoff(int attempt) {
    // 1s, 2s, 4s...
    final seconds = 1 << attempt;
    return Future.delayed(Duration(seconds: seconds));
  }
}
