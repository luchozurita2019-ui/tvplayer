import 'package:http/http.dart' as http;

/// Cliente HTTP compartido para todas las llamadas Xtream.
///
/// Mantener una sola instancia permite que dart:io reutilice DNS, sockets,
/// conexiones TCP/TLS y keep-alive entre player_api.php, categorías, VOD,
/// series y fichas. La instancia es reiniciable: cuando el usuario va a
/// reproducir, podemos cancelar una descarga de catálogo que haya quedado en
/// segundo plano sin dejar inutilizables los servicios que conservan una
/// referencia estática a este cliente.
class XtreamHttpClient {
  XtreamHttpClient._();

  static final _RestartableXtreamClient instance = _RestartableXtreamClient();

  /// Corta las solicitudes Xtream que siguen en vuelo (por ejemplo un refresh
  /// completo de get_vod_streams) y abre un pool HTTP limpio para la siguiente
  /// operación. Las referencias existentes a [instance] siguen siendo válidas.
  static void cancelBrowsingRequests() => instance.restart();

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

class _RestartableXtreamClient extends http.BaseClient {
  http.Client _inner = http.Client();
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) {
      return Future<http.StreamedResponse>.error(
        StateError('El cliente Xtream ya fue cerrado.'),
      );
    }
    // Capturamos el cliente actual para que restart() pueda cerrar exactamente
    // las solicitudes que estaban usando el pool anterior.
    final client = _inner;
    return client.send(request);
  }

  void restart() {
    if (_closed) return;
    final previous = _inner;
    _inner = http.Client();
    previous.close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _inner.close();
  }
}
