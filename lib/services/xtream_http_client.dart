import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Cliente HTTP compartido para Xtream.
///
/// Mantiene un pool nativo predecible para navegación, pero permite suspender
/// TODA solicitud nueva mientras el reproductor tiene prioridad. Cerrar sockets
/// no alcanza: una tarea vieja puede capturar el error y volver a intentar con
/// un cliente nuevo. Por eso [send] rechaza explícitamente cualquier petición
/// mientras playback está activo.
class XtreamHttpClient {
  XtreamHttpClient._();

  static final _RestartableXtreamClient instance = _RestartableXtreamClient();

  /// Compatibilidad con llamadas existentes. Durante playback deja el cliente
  /// suspendido en vez de simplemente reemplazar el pool.
  static void cancelBrowsingRequests() => pauseBrowsingForPlayback();

  static void pauseBrowsingForPlayback() => instance.pauseForPlayback();

  static void resumeBrowsingAfterPlayback() => instance.resumeAfterPlayback();

  static bool get browsingSuspended => instance.suspended;

  static int get browsingGeneration => instance.generation;

  static const String browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  static const Map<String, String> jsonHeaders = <String, String>{
    'User-Agent': browserUserAgent,
    'Accept': 'application/json,text/plain,*/*',
    'Connection': 'keep-alive',
  };
}

/// Error deliberado: no es un fallo del proveedor y no debe convertirse en
/// fallback, reintento de catálogo ni marca de servicio caído.
class XtreamBrowsingSuspendedException implements Exception {
  const XtreamBrowsingSuspendedException();

  @override
  String toString() => 'Xtream browsing suspended for playback';
}

http.Client _newNativeClient() {
  final io = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 4
    ..autoUncompress = true;
  return IOClient(io);
}

class _RestartableXtreamClient extends http.BaseClient {
  http.Client _inner = _newNativeClient();
  bool _closed = false;
  int _playbackPauseDepth = 0;
  int _generation = 0;

  bool get suspended => _playbackPauseDepth > 0;
  int get generation => _generation;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) {
      return Future<http.StreamedResponse>.error(
        StateError('El cliente Xtream ya fue cerrado.'),
      );
    }
    if (suspended) {
      return Future<http.StreamedResponse>.error(
        const XtreamBrowsingSuspendedException(),
      );
    }
    final client = _inner;
    return client.send(request);
  }

  /// Reinicio normal de pool. No cambia el estado de prioridad de playback.
  void restart() {
    if (_closed) return;
    _generation++;
    final previous = _inner;
    _inner = _newNativeClient();
    previous.close();
  }

  /// Ref-counted: evita que una ruta secundaria reanude navegación mientras
  /// todavía existe otra pantalla/sesión de reproducción activa.
  void pauseForPlayback() {
    if (_closed) return;
    _playbackPauseDepth++;
    if (_playbackPauseDepth > 1) return;
    _generation++;
    final previous = _inner;
    _inner = _newNativeClient();
    previous.close();
  }

  void resumeAfterPlayback() {
    if (_closed || _playbackPauseDepth == 0) return;
    _playbackPauseDepth--;
    if (_playbackPauseDepth > 0) return;
    _generation++;
    final previous = _inner;
    _inner = _newNativeClient();
    previous.close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _generation++;
    _inner.close();
  }
}
