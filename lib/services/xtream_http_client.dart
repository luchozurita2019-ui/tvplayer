import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Cliente HTTP compartido para Xtream.
///
/// La v40 usa explícitamente dart:io/IOClient para tener un pool nativo
/// predecible: keep-alive, gzip automático, conexiones limitadas por host y
/// timeouts de conexión/idle. [instance] es estable aunque el pool interno se
/// reinicie al priorizar reproducción sobre navegación.
class XtreamHttpClient {
  XtreamHttpClient._();

  static final _RestartableXtreamClient instance = _RestartableXtreamClient();

  static void cancelBrowsingRequests() => instance.restart();

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

  void restart() {
    if (_closed) return;
    final previous = _inner;
    _inner = _newNativeClient();
    previous.close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _inner.close();
  }
}
