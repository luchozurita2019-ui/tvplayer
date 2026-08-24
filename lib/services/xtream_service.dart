import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'xtream_http_client.dart';

const String _xtreamBrowserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/96.0.4664.18 Safari/537.36';

class XtreamConnectionResult {
  final String playlistUrl;
  final Uri apiServer;
  final Uri streamServer;
  final String username;
  final String password;
  final String? serverName;
  final String? status;
  final DateTime? expiration;

  const XtreamConnectionResult({
    required this.playlistUrl,
    required this.apiServer,
    required this.streamServer,
    required this.username,
    required this.password,
    this.serverName,
    this.status,
    this.expiration,
  });
}

class XtreamNativeCatalog {
  final List<Channel> live;
  final List<Channel> vod;

  const XtreamNativeCatalog({required this.live, required this.vod});

  bool get isEmpty => live.isEmpty && vod.isEmpty;
}

class XtreamService {
  XtreamService._();

  static final http.Client _client = XtreamHttpClient.instance;

  static const Map<String, String> _jsonHeaders = {
    'User-Agent': _xtreamBrowserUserAgent,
    'Accept': 'application/json,text/plain,*/*',
    'Connection': 'keep-alive',
  };

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

    final authUri = _endpoint(server, 'player_api.php', <String, String>{
      'username': user,
      'password': pass,
    });

    final response = await _getJsonWithAndroidRetry(authUri, timeout);

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
    final authenticated =
        authValue == 1 ||
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

    // player_api.php suele indicar el host/protocolo/puerto que el panel desea
    // usar para los streams. Es importante respetarlo: varios paneles reciben
    // la API por HTTP en un puerto y sirven video por HTTPS en otro.
    final streamServer = _resolveStreamServer(server, serverInfo);

    final playlistUrl = _endpoint(server, 'get.php', <String, String>{
      'username': user,
      'password': pass,
      'type': 'm3u_plus',
      'output': 'ts',
    }).toString();

    return XtreamConnectionResult(
      playlistUrl: playlistUrl,
      apiServer: server,
      streamServer: streamServer,
      username: user,
      password: pass,
      serverName: serverInfo['url']?.toString(),
      status: status,
      expiration: expiration,
    );
  }

  /// Detecta el formato de enlace que suelen entregar los paneles Xtream:
  /// get.php?username=...&password=...&type=m3u_plus. La detección se confirma
  /// después contra player_api.php; no alcanza con que la URL se parezca.
  static bool looksLikeXtreamPlaylistUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return false;
    }
    final path = uri.path.toLowerCase();
    final isGetPhp = path.endsWith('/get.php') || path.endsWith('get.php');
    if (!isGetPhp) return false;
    final username = uri.queryParameters['username']?.trim() ?? '';
    final password = uri.queryParameters['password']?.trim() ?? '';
    return username.isNotEmpty && password.isNotEmpty;
  }

  /// Intenta convertir una URL M3U entregada por el proveedor en una conexión
  /// Xtream real. Si player_api.php no valida, devuelve null y el llamador puede
  /// continuar con el pipeline M3U tradicional sin romper compatibilidad.
  static Future<XtreamConnectionResult?> tryConnectFromPlaylistUrl(
    String playlistUrl, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!looksLikeXtreamPlaylistUrl(playlistUrl)) return null;
    try {
      return await reconnectFromPlaylistUrl(playlistUrl, timeout: timeout);
    } catch (_) {
      return null;
    }
  }

  /// Reconstruye una cuenta guardada desde su get.php. Esto mantiene
  /// compatibilidad con las fuentes Xtream que TV FULL ya tenía persistidas.
  static Future<XtreamConnectionResult> reconnectFromPlaylistUrl(
    String playlistUrl, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final uri = Uri.tryParse(playlistUrl);
    if (uri == null || uri.host.isEmpty) {
      throw Exception('La fuente Xtream guardada no es válida.');
    }
    final username = uri.queryParameters['username'] ?? '';
    final password = uri.queryParameters['password'] ?? '';
    if (username.isEmpty || password.isEmpty) {
      throw Exception('La fuente Xtream guardada no contiene credenciales.');
    }

    var path = uri.path;
    final lower = path.toLowerCase();
    if (lower.endsWith('/get.php')) {
      path = path.substring(0, path.length - '/get.php'.length);
    } else if (lower.endsWith('get.php')) {
      path = path.substring(0, path.length - 'get.php'.length);
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    }

    final server = uri
        .replace(path: path.isEmpty ? '/' : path, query: '', fragment: '')
        .toString()
        .replaceAll(RegExp(r'/$'), '');

    return connect(
      serverUrl: server,
      username: username,
      password: password,
      timeout: timeout,
    );
  }

  /// Carga TV en vivo y VOD directamente desde player_api.php. El resultado
  /// conserva stream_id/container_extension y utiliza direct_source cuando el
  /// panel lo entrega, evitando depender de cómo get.php haya serializado la URL.
  static Future<XtreamNativeCatalog> fetchNativeCatalog(
    XtreamConnectionResult connection, {
    Duration timeout = const Duration(seconds: 18),
  }) async {
    final results = await Future.wait<List<dynamic>>([
      _safeActionList(connection, 'get_live_categories', timeout),
      _safeActionList(connection, 'get_live_streams', timeout),
      _safeActionList(connection, 'get_vod_categories', timeout),
      _safeActionList(connection, 'get_vod_streams', timeout),
    ]);

    final liveCategories = _categoryMap(results[0]);
    final live = _liveChannels(
      connection,
      categories: liveCategories,
      rawStreams: results[1],
    );

    final vodCategories = _categoryMap(results[2]);
    final vod = _vodChannels(
      connection,
      categories: vodCategories,
      rawStreams: results[3],
    );

    return XtreamNativeCatalog(
      live: List.unmodifiable(live),
      vod: List.unmodifiable(vod),
    );
  }

  static Future<List<dynamic>> _safeActionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
    try {
      return await _actionList(connection, action, timeout);
    } catch (_) {
      // Algunos paneles implementan sólo una parte de la API Xtream. Una
      // sección ausente no debe impedir que las demás se carguen.
      return const <dynamic>[];
    }
  }

  static Future<List<dynamic>> _actionList(
    XtreamConnectionResult connection,
    String action,
    Duration timeout,
  ) async {
    final uri = _endpoint(
      connection.apiServer,
      'player_api.php',
      <String, String>{
        'username': connection.username,
        'password': connection.password,
        'action': action,
      },
    );

    final response = await _getJsonWithAndroidRetry(uri, timeout);
    if (response.statusCode != 200) {
      throw Exception('Xtream $action respondió HTTP ${response.statusCode}.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;
    return const <dynamic>[];
  }

  static bool get _isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _retryableAndroidConnectionError(Object error) {
    if (!_isAndroidRuntime) return false;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('timed out') ||
        text.contains('timeoutexception') ||
        text.contains('clientexception');
  }

  static Future<http.Response> _getJsonWithAndroidRetry(
    Uri uri,
    Duration timeout,
  ) async {
    final attempts = _isAndroidRuntime ? 2 : 1;
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await _client.get(uri, headers: _jsonHeaders).timeout(timeout);
      } catch (error) {
        lastError = error;
        if (attempt + 1 >= attempts ||
            !_retryableAndroidConnectionError(error)) {
          rethrow;
        }
        XtreamHttpClient.cancelBrowsingRequests();
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    throw lastError ?? Exception('No se pudo conectar con Xtream.');
  }

  static Map<String, String> _categoryMap(List<dynamic> raw) {
    final result = <String, String>{};
    for (final value in raw) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final id = item['category_id']?.toString().trim() ?? '';
      final name = item['category_name']?.toString().trim() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) result[id] = name;
    }
    return result;
  }

  static List<Channel> _liveChannels(
    XtreamConnectionResult connection, {
    required Map<String, String> categories,
    required List<dynamic> rawStreams,
  }) {
    final channels = <Channel>[];
    for (final value in rawStreams) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final streamId = item['stream_id']?.toString().trim() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      if (streamId.isEmpty || name.isEmpty) continue;

      final extension = _cleanExtension(
        item['container_extension']?.toString(),
        fallback: 'ts',
      );
      final directSource = _resolvedDirectSource(
        connection.streamServer,
        item['direct_source']?.toString(),
      );
      final url =
          directSource ??
          _streamUrl(
            connection.streamServer,
            section: 'live',
            username: connection.username,
            password: connection.password,
            streamId: streamId,
            extension: extension,
          );

      final categoryId = item['category_id']?.toString();
      final group = categoryId == null ? null : categories[categoryId];
      final logo = item['stream_icon']?.toString().trim();
      final epgId = item['epg_channel_id']?.toString().trim();

      channels.add(
        Channel(
          name: name,
          url: url,
          logoUrl: logo == null || logo.isEmpty ? null : logo,
          group: group,
          tvgId: epgId == null || epgId.isEmpty ? null : epgId,
        ),
      );
    }
    return channels;
  }

  static List<Channel> _vodChannels(
    XtreamConnectionResult connection, {
    required Map<String, String> categories,
    required List<dynamic> rawStreams,
  }) {
    final channels = <Channel>[];
    for (final value in rawStreams) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final streamId = item['stream_id']?.toString().trim() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      if (streamId.isEmpty || name.isEmpty) continue;

      final extension = _cleanExtension(
        item['container_extension']?.toString(),
        fallback: 'mp4',
      );
      final directSource = _resolvedDirectSource(
        connection.streamServer,
        item['direct_source']?.toString(),
      );
      final url =
          directSource ??
          _streamUrl(
            connection.streamServer,
            section: 'movie',
            username: connection.username,
            password: connection.password,
            streamId: streamId,
            extension: extension,
          );

      final categoryId = item['category_id']?.toString();
      final group = categoryId == null ? null : categories[categoryId];
      final cover = item['stream_icon']?.toString().trim();

      channels.add(
        Channel(
          name: name,
          url: url,
          logoUrl: cover == null || cover.isEmpty ? null : cover,
          group: group,
        ),
      );
    }
    return channels;
  }

  static String? _resolvedDirectSource(Uri base, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value == 'null') return null;

    final parsed = Uri.tryParse(value);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) {
      return parsed.toString();
    }

    if (value.startsWith('/')) {
      return base.resolve(value).toString();
    }
    return null;
  }

  static String _streamUrl(
    Uri base, {
    required String section,
    required String username,
    required String password,
    required String streamId,
    required String extension,
  }) {
    final prefix = base.pathSegments.where((e) => e.trim().isNotEmpty).toList();
    final segments = <String>[
      ...prefix,
      section,
      username,
      password,
      '$streamId.$extension',
    ];
    return base
        .replace(pathSegments: segments, query: '', fragment: '')
        .toString();
  }

  static String _cleanExtension(String? raw, {required String fallback}) {
    final value = (raw ?? '').trim().toLowerCase().replaceFirst('.', '');
    if (value.isEmpty || !RegExp(r'^[a-z0-9]{2,6}$').hasMatch(value)) {
      return fallback;
    }
    return value;
  }

  static Uri _resolveStreamServer(
    Uri apiServer,
    Map<String, dynamic> serverInfo,
  ) {
    final rawProtocol = serverInfo['server_protocol']?.toString().toLowerCase();
    final scheme = rawProtocol == 'https' || rawProtocol == 'http'
        ? rawProtocol!
        : apiServer.scheme;

    var host = apiServer.host;
    final rawUrl = serverInfo['url']?.toString().trim() ?? '';
    if (rawUrl.isNotEmpty) {
      final candidate = Uri.tryParse(
        rawUrl.contains('://') ? rawUrl : '$scheme://$rawUrl',
      );
      if (candidate != null && candidate.host.isNotEmpty) host = candidate.host;
    }

    int? port;
    final portRaw = scheme == 'https'
        ? serverInfo['https_port'] ?? serverInfo['port']
        : serverInfo['port'];
    port = int.tryParse(portRaw?.toString() ?? '');
    if (port == null || port <= 0 || port > 65535) {
      port = apiServer.hasPort ? apiServer.port : null;
    }

    return Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: apiServer.path.isEmpty ? '/' : apiServer.path,
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

  static Uri _endpoint(Uri base, String endpoint, Map<String, String> query) {
    var path = base.path;
    if (path.isEmpty || path == '/') {
      path = '/$endpoint';
    } else {
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      path = '$path/$endpoint';
    }

    return base.replace(path: path, queryParameters: query, fragment: '');
  }
}
