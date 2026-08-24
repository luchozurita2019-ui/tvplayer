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
/// - Si comienza una reproducción, [cancelBrowsingRequests] invalida la
///   navegación actual y ninguna excepción derivada de ese cierre puede iniciar
///   otro intento.
/// - Los reintentos quedan reservados para fallos ANTES de recibir el cuerpo.
class M3uFetcher {
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  static http.Client _client = http.Client();
  static int _generation = 0;

  static void cancelBrowsingRequests() {
    final previous = _client;
    _client = http.Client();
    _generation++;
    previous.close();
  }

  static Future<String> fetch(
    String url, {
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 15),
    Duration idleTimeout = const Duration(seconds: 30),
  }) async {
    final generation = _generation;
    Object? lastError;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      _ensureCurrent(generation);
      try {
        final request = http.Request('GET', Uri.parse(url))
          ..headers.addAll(const {
            'User-Agent': _browserUserAgent,
            'Accept':
                'application/x-mpegURL,application/vnd.apple.mpegurl,text/plain,*/*',
          });

        // send() completa cuando llegan los headers. No limitamos con un timeout
        // corto la duración total de listas grandes que siguen enviando bytes.
        final response = await _client.send(request).timeout(timeout);
        _ensureCurrent(generation);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            return await response.stream
                .timeout(idleTimeout)
                .transform(utf8.decoder)
                .join();
          } on TimeoutException {
            _ensureCurrent(generation);
            throw const _BodyDownloadException(
              'La descarga de la lista se interrumpió porque el servidor dejó de enviar datos.',
            );
          } on SocketException {
            _ensureCurrent(generation);
            throw const _BodyDownloadException(
              'La conexión se cortó mientras se estaba descargando la lista.',
            );
          } on http.ClientException {
            _ensureCurrent(generation);
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
          _ensureCurrent(generation);
          continue;
        }

        throw Exception(
          'El servidor respondió con código ${response.statusCode}',
        );
      } on _BrowsingCancelledException {
        rethrow;
      } on _BodyDownloadException catch (error) {
        _ensureCurrent(generation);
        // Si el catálogo ya empezó a llegar, no se vuelve a bajar desde cero.
        throw Exception(error.message);
      } on TimeoutException {
        _ensureCurrent(generation);
        lastError = Exception(
          'El servidor tardó demasiado en iniciar la respuesta',
        );
        if (attempt < maxRetries) {
          await _backoff(attempt);
          _ensureCurrent(generation);
          continue;
        }
      } on SocketException {
        _ensureCurrent(generation);
        lastError = Exception(
          'No hay conexión a internet o el servidor no responde',
        );
        if (attempt < maxRetries) {
          await _backoff(attempt);
          _ensureCurrent(generation);
          continue;
        }
      } on HttpException {
        _ensureCurrent(generation);
        lastError = Exception('Error al conectar con el servidor de la lista');
        if (attempt < maxRetries) {
          await _backoff(attempt);
          _ensureCurrent(generation);
          continue;
        }
      } on http.ClientException {
        _ensureCurrent(generation);
        lastError = Exception(
          'Error HTTP al conectar con el servidor de la lista',
        );
        if (attempt < maxRetries) {
          await _backoff(attempt);
          _ensureCurrent(generation);
          continue;
        }
      }
    }

    _ensureCurrent(generation);
    throw lastError ?? Exception('No se pudo descargar la lista');
  }

  static void _ensureCurrent(int generation) {
    if (generation != _generation) {
      throw const _BrowsingCancelledException();
    }
  }

  static Future<void> _backoff(int attempt) {
    final seconds = 1 << attempt;
    return Future.delayed(Duration(seconds: seconds));
  }
}

class _BodyDownloadException implements Exception {
  final String message;

  const _BodyDownloadException(this.message);
}

class _BrowsingCancelledException implements Exception {
  const _BrowsingCancelledException();

  @override
  String toString() =>
      'La actualización M3U fue pausada para priorizar la reproducción.';
}
