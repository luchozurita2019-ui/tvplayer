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
/// - Los reintentos quedan reservados para fallos ANTES de recibir el cuerpo.
/// - Algunos paneles IPTV bloquean perfiles HTTP de navegador con 401/403 pero
///   permiten reproductores. En ese caso probamos perfiles compatibles sin
///   modificar la URL ni las credenciales entregadas por el proveedor.
class M3uFetcher {
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  static const List<_HttpProfile> _profiles = <_HttpProfile>[
    _HttpProfile(
      name: 'browser',
      headers: <String, String>{
        'User-Agent': _browserUserAgent,
        'Accept': 'application/x-mpegURL,application/vnd.apple.mpegurl,text/plain,*/*',
        'Connection': 'keep-alive',
      },
    ),
    _HttpProfile(
      name: 'vlc',
      headers: <String, String>{
        'User-Agent': 'VLC/3.0.21 LibVLC/3.0.21',
        'Accept': '*/*',
        'Connection': 'close',
      },
    ),
    _HttpProfile(
      name: 'android-iptv',
      headers: <String, String>{
        'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 9; Android TV Build/PPR2.180905.006)',
        'Accept': '*/*',
        'Connection': 'close',
      },
    ),
    _HttpProfile(
      name: 'minimal',
      headers: <String, String>{'Accept': '*/*', 'Connection': 'close'},
    ),
  ];

  static Future<String> fetch(
    String url, {
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 15),
    Duration idleTimeout = const Duration(seconds: 30),
  }) async {
    Object? lastError;
    int? lastStatus;

    for (
      var profileIndex = 0;
      profileIndex < _profiles.length;
      profileIndex++
    ) {
      final profile = _profiles[profileIndex];

      for (var attempt = 0; attempt <= maxRetries; attempt++) {
        final client = http.Client();
        try {
          final request = http.Request('GET', Uri.parse(url))
            ..headers.addAll(profile.headers);

          // send() completa cuando llegan los headers. El cuerpo puede tardar
          // mucho más si la lista es grande; allí usamos timeout de inactividad.
          final response = await client.send(request).timeout(timeout);
          lastStatus = response.statusCode;

          if (response.statusCode >= 200 && response.statusCode < 300) {
            try {
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

          // 401/403 en paneles IPTV puede ser una restricción por User-Agent o
          // headers. Cambiamos de perfil inmediatamente, sin repetir el mismo.
          if (response.statusCode == 401 || response.statusCode == 403) {
            lastError = Exception(
              'El servidor respondió con código ${response.statusCode}',
            );
            break;
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
          // Ya empezamos a recibir el catálogo: NO lo volvemos a descargar
          // desde cero automáticamente.
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
          lastError = Exception(
            'Error al conectar con el servidor de la lista',
          );
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
        } finally {
          client.close();
        }
      }
    }

    if (lastStatus == 401 || lastStatus == 403) {
      throw Exception(
        'El servidor rechazó la lista con código $lastStatus incluso usando perfiles IPTV compatibles.',
      );
    }
    throw lastError ?? Exception('No se pudo descargar la lista');
  }

  static Future<void> _backoff(int attempt) {
    // 1 s, 2 s... Sólo antes de que una descarga haya comenzado.
    final seconds = 1 << attempt;
    return Future.delayed(Duration(seconds: seconds));
  }
}

class _HttpProfile {
  final String name;
  final Map<String, String> headers;

  const _HttpProfile({required this.name, required this.headers});
}

class _BodyDownloadException implements Exception {
  final String message;

  const _BodyDownloadException(this.message);
}
