import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class XtreamRequestCancelled implements Exception {
  const XtreamRequestCancelled();

  @override
  String toString() => 'La operación Xtream fue reemplazada por una más nueva.';
}

/// Cliente HTTP compartido para Xtream con pool nativo y cancelación por generación.
class XtreamHttpClient {
  XtreamHttpClient._();

  static final _RestartableXtreamClient instance = _RestartableXtreamClient();

  static int get generation => instance.generation;

  /// Comienza una navegación nueva y corta transferencias de navegación viejas.
  static int beginBrowsingOperation() => instance.cancelBrowsing();

  static void ensureGeneration(int expected) =>
      instance.ensureGeneration(expected);

  /// Se conserva para los sitios que priorizan reproducción sobre navegación.
  static void cancelBrowsingRequests() => instance.cancelBrowsing();

  /// Reinicia solamente sockets/pool para un retry interno de la misma operación.
  static void restartTransport() => instance.restartTransport();

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
  int _generation = 0;

  int get generation => _generation;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) {
      return Future<http.StreamedResponse>.error(
        StateError('El cliente Xtream ya fue cerrado.'),
      );
    }
    final client = _inner;
    return client.send(request);
  }

  int cancelBrowsing() {
    if (_closed) throw StateError('El cliente Xtream ya fue cerrado.');
    _generation++;
    restartTransport();
    return _generation;
  }

  void ensureGeneration(int expected) {
    if (_closed || expected != _generation) {
      throw const XtreamRequestCancelled();
    }
  }

  void restartTransport() {
    if (_closed) return;
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
