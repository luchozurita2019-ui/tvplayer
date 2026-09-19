import 'dart:convert';

import 'package:http/http.dart' as http;

import 'futbol_total_endpoints.dart';
import 'm3u_fetcher.dart';
import 'remote_provisioning_service.dart';

class FutbolTotalAdRequiredException implements Exception {
  final String adUrl;
  final int retryAfterSeconds;

  const FutbolTotalAdRequiredException({
    required this.adUrl,
    this.retryAfterSeconds = 2,
  });

  @override
  String toString() => 'Fútbol Total requiere completar la publicidad.';
}

/// Descarga documentos de Fútbol Total sin exponer el mecanismo de firma
/// original dentro del APK de TV FULL.
///
/// - URLs públicas: descarga directa.
/// - URLs privadas de ByRafaelSystem: proxy privado TV FULL.
/// - El proxy exige las mismas credenciales de dispositivo que ya usa
///   tvf-device-config.
class FutbolTotalAuthorizedFetcher {
  FutbolTotalAuthorizedFetcher({
    RemoteProvisioningService? provisioning,
    http.Client? client,
  }) : _provisioning = provisioning ?? RemoteProvisioningService(),
       _client = client ?? http.Client();

  final RemoteProvisioningService _provisioning;
  final http.Client _client;

  static bool requiresAuthorizedProxy(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https') return false;

    if (uri.host == 'raw.githubusercontent.com') {
      final path = uri.path.toLowerCase();
      return path.contains('/byrafaelsystem/futboltotal-data/') ||
          path.contains('/byrafaelsystem/futboltotal-links/');
    }

    if (uri.host == 'api.github.com') {
      final path = uri.path.toLowerCase();
      return path.contains('/repos/byrafaelsystem/futboltotal-data/contents/') ||
          path.contains('/repos/byrafaelsystem/futboltotal-links/contents/');
    }

    return false;
  }

  Future<String> fetch(
    String url, {
    bool noCache = false,
  }) async {
    if (!requiresAuthorizedProxy(url)) {
      return M3uFetcher.fetch(url);
    }

    var credentials =
        await _provisioning.loadCredentials() ??
        await _provisioning.ensureRegistered();

    http.Response response = await _proxyRequest(
      url,
      credentials,
      noCache: noCache,
    );

    if (response.statusCode == 401) {
      await _provisioning.clearCredentials();
      credentials = await _provisioning.ensureRegistered();
      response = await _proxyRequest(
        url,
        credentials,
        noCache: noCache,
      );
    }

    if (response.statusCode == 403) {
      throw Exception(
        'El dispositivo no tiene acceso activo al puente Fútbol Total.',
      );
    }

    if (response.statusCode == 402) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map &&
            decoded['error']?.toString() == 'futboltotal_ad_required') {
          final adUrl = decoded['ad_url']?.toString().trim() ?? '';
          final retryAfter =
              int.tryParse(decoded['retry_after_seconds']?.toString() ?? '') ??
                  2;
          if (adUrl.startsWith('http://') || adUrl.startsWith('https://')) {
            throw FutbolTotalAdRequiredException(
              adUrl: adUrl,
              retryAfterSeconds: retryAfter,
            );
          }
        }
      } on FutbolTotalAdRequiredException {
        rethrow;
      } catch (_) {}
    }

    if (response.statusCode != 200) {
      var code = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          code = decoded['error'].toString();
        }
      } catch (_) {}
      throw Exception('No se pudo obtener Fútbol Total ($code).');
    }

    final body = response.body;
    if (body.trim().isEmpty) {
      throw const FormatException(
        'Fútbol Total devolvió un documento vacío.',
      );
    }
    return body;
  }

  Future<http.Response> _proxyRequest(
    String url,
    RemoteDeviceCredentials credentials, {
    required bool noCache,
  }) {
    return _client
        .post(
          Uri.parse(FutbolTotalEndpoints.authorizedProxy),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'x-tvfull-device-code': credentials.code,
            'x-tvfull-device-secret': credentials.secret,
          },
          body: jsonEncode({
            'url': url,
            'no_cache': noCache,
          }),
        )
        .timeout(const Duration(seconds: 20));
  }

  void close() => _client.close();
}
