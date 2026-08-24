import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Descarga el contenido de una lista M3U remota.
///
/// La conexión y la descarga se controlan por separado:
/// - [timeout] sólo limita cuánto esperamos a que el servidor responda con los
///   headers iniciales.
/// - Una vez que el servidor empezó a entregar la lista, no imponemos un límite
///   total de 15 segundos: sólo fallamos si deja de enviar datos durante
///   [idleTimeout].
/// - Nunca reintentamos automáticamente una descarga que ya había comenzado.
///   Esto evita volver a bajar decenas de MB desde cero y gastar varias veces el
///   ancho de banda con catálogos IPTV grandes.
/// - Los reintentos quedan reservados para fallos ANTES de recibir el cuerpo
///   (timeout de conexión, socket caído o HTTP 5xx).
class M3uFetcher {
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  static final http.Client _client = http.Client();

  static Future<String> fetch(
    String url, {
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 15),
    Duration idleTimeout = const Duration(seconds: 30),
  }) async {
    Object? lastError;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final request = http.Request('GET', Uri.parse(url))
          ..headers.addAll(const {
            'User-Agent': _browserUserAgent,
            'Accept': 'application/x-mpegURL,application/vnd.apple.mpegurl,text/plain,*/*',
          });

        // IMPORTANTE: send() completa cuando llegan los headers. El viejo
        // Client.get().timeout(15 s) esperaba el cuerpo ENTERO y abortaba listas
        // grandes aunque el servidor estuviera transfiriendo datos normalmente.
        final response = await _client.send(request).timeout(timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            // Timeout de inactividad, no de duración total. Una lista puede
            // tardar más de 30 s si es enorme, siempre que sigan llegando bytes.
            return await response.stream
                .timeout(idleTimeout)
                .transform(utf8.decoder)
                .join();
          } on TimeoutException {
            throw const _BodyDownloadException(
              'La descarga de la lista se interrumpió porque el servidor dejó de enviar datos.',
            );
          } on SocketException {
            throw const _BodyDownloadException(
              'La conexión se cortó mientras se estaba descargando la lista.',
            );
          } on http.ClientException {
            throw const _BodyDownloadException(
              'La conexión HTTP se interrumpió mientras se descargaba la lista.',
            );
          }
        }

        if (response.statusCode >= 500 && attempt < maxRetries) {
          lastError = Exception(
            'El servidor respondió con código ${response.statusCode}',
          );
          await _backoff(attempt);
          continue;
        }

        throw Exception(
          'El servidor respondió con código ${response.statusCode}',
        );
      } on _BodyDownloadException catch (e) {
        // Ya empezamos a recibir el catálogo: NO lo volvemos a descargar desde
        // cero automáticamente. Es la diferencia clave respecto de V3.7/V3.8.
        throw Exception(e.message);
      } on TimeoutException {
        lastError = Exception(
          'El servidor tardó demasiado en iniciar la respuesta',
        );
        if (attempt < maxRetries) {
          await _backoff(attempt);
          continue;
        }
      } on SocketException {
        lastError = Exception(
          'No hay conexión a internet o el servidor no responde',
        );
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
      } on http.ClientException {
        lastError = Exception(
          'Error HTTP al conectar con el servidor de la lista',
        );
        if (attempt < maxRetries) {
          await _backoff(attempt);
          continue;
        }
      }
    }

    throw lastError ?? Exception('No se pudo descargar la lista');
  }

  static Future<void> _backoff(int attempt) {
    // 1 s, 2 s... Sólo antes de que una descarga haya comenzado.
    final seconds = 1 << attempt;
    return Future.delayed(Duration(seconds: seconds));
  }
}

class _BodyDownloadException implements Exception {
  final String message;

  const _BodyDownloadException(this.message);
}
