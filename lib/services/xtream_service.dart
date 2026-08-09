import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class XtreamConnectionResult {
  final String playlistUrl;
  final String? serverName;
  final String? status;
  final DateTime? expiration;

  const XtreamConnectionResult({
    required this.playlistUrl,
    this.serverName,
    this.status,
    this.expiration,
  });
}

class XtreamService {
  XtreamService._();

  static final http.Client _client = http.Client();

  static Future<XtreamConnectionResult> connect({
    required String serverUrl,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final server = _normalizeServer(serverUrl);
    final user = username.trim();
    final pass = password.trim();

    if (user.isEmpty || pass.isEmpty) {
      throw Exception('Ingresá usuario y contraseña de Xtream Codes.');
    }

    final authUri = _endpoint(
      server,
      'player_api.php',
      <String, String>{
        'username': user,
        'password': pass,
      },
    );

    final response = await _client.get(
      authUri,
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/96.0.4664.18 Safari/537.36',
        'Accept': 'application/json,text/plain,*/*',
      },
    ).timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception(
        'El servidor Xtream respondió HTTP ${response.statusCode}.',
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw Exception('La respuesta del servidor Xtream no es válida.');
    }

    final userInfoRaw = decoded['user_info'];
    if (userInfoRaw is! Map) {
      throw Exception('El servidor no devolvió información de usuario Xtream.');
    }

    final userInfo = Map<String, dynamic>.from(userInfoRaw);
    final authValue = userInfo['auth'];
    final authenticated = authValue == 1 ||
        authValue == '1' ||
        authValue == true ||
        userInfo['status']?.toString().toLowerCase() == 'active';

    if (!authenticated) {
      throw Exception('Usuario o contraseña Xtream incorrectos o inactivos.');
    }

    final status = userInfo['status']?.toString();
    final expRaw = userInfo['exp_date']?.toString();
    DateTime? expiration;
    if (expRaw != null && expRaw.isNotEmpty && expRaw != 'null') {
      final seconds = int.tryParse(expRaw);
      if (seconds != null && seconds > 0) {
        expiration = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }

    final serverInfoRaw = decoded['server_info'];
    final serverInfo = serverInfoRaw is Map
        ? Map<String, dynamic>.from(serverInfoRaw)
        : const <String, dynamic>{};

    final playlistUrl = _endpoint(
      server,
      'get.php',
      <String, String>{
        'username': user,
        'password': pass,
        'type': 'm3u_plus',
        'output': 'ts',
      },
    ).toString();

    return XtreamConnectionResult(
      playlistUrl: playlistUrl,
      serverName: serverInfo['url']?.toString(),
      status: status,
      expiration: expiration,
    );
  }

  static Uri _normalizeServer(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      throw Exception('Ingresá la URL del servidor Xtream.');
    }
    if (!value.contains('://')) value = 'http://$value';

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw Exception('La URL del servidor Xtream no es válida.');
    }
    return uri;
  }

  static Uri _endpoint(
    Uri base,
    String endpoint,
    Map<String, String> query,
  ) {
    var path = base.path;
    if (path.isEmpty || path == '/') {
      path = '/$endpoint';
    } else {
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      path = '$path/$endpoint';
    }

    return base.replace(
      path: path,
      queryParameters: query,
      fragment: '',
    );
  }
}
