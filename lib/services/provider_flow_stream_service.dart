import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/channel.dart';

class ProviderFlowException implements Exception {
  final String message;
  final bool retryable;

  const ProviderFlowException(this.message, {this.retryable = false});

  @override
  String toString() => message;
}

class ProviderFlowResolvedStream {
  final String url;
  final Map<String, String> headers;

  const ProviderFlowResolvedStream({required this.url, required this.headers});
}

class _ProviderFlowToken {
  final String host;
  final String token;
  final DateTime expiresAt;

  const _ProviderFlowToken({
    required this.host,
    required this.token,
    required this.expiresAt,
  });
}

/// Adaptación del resolvedor suministrado por el proveedor para sus catálogos
/// provider.json. La identidad del catálogo (`globalIndex`) NO se usa como
/// stream_id: la URL reproducible se construye a partir de la ruta original
/// `live/c...` y de un host/token CDN fresco obtenido desde las seeds del
/// proveedor.
class ProviderFlowStreamService {
  ProviderFlowStreamService._({http.Client? client, Random? random})
    : _client = client ?? http.Client(),
      _random = random ?? Random();

  static final ProviderFlowStreamService instance =
      ProviderFlowStreamService._();

  final http.Client _client;
  final Random _random;
  _ProviderFlowToken? _cachedToken;
  Future<_ProviderFlowToken>? _refreshing;
  String? _lastResolvedPath;
  DateTime? _lastResolvedAt;

  static const String _defaultUserAgent = 'PlayTVPremium';

  // Seeds de compatibilidad incluidas por el proveedor en su APK de prueba.
  // Pueden reemplazarse en una futura entrega sin tocar el catálogo.
  static const List<String> _providerSeeds = <String>[
    'https://chromecast.cvattv.com.ar/live/c6eds/Viajar/SA_Live_dash_cenc/Viajar.mpd',
    'https://cdn-py.cvattv.com.ar/live/c6eds/EWTN/SA_Live_dash_enc/EWTN.mpd',
    'https://cdn-py.cvattv.com.ar/live/c4eds/UNICANAL_C4/SA_Live_dash_enc/UNICANAL_C4.mpd',
    'https://cdn-py.cvattv.com.ar/live/c4eds/TELEFUTURO_C4/SA_Live_dash_enc/TELEFUTURO_C4.mpd',
  ];

  bool handles(Channel channel) {
    final original = channel.dynamicStreamPath?.trim();
    if (original == null || original.isEmpty) return false;
    return _extractRelativePath(original) != null;
  }

  Future<ProviderFlowResolvedStream> resolve(
    Channel channel, {
    bool forceRefresh = false,
  }) async {
    final original = channel.dynamicStreamPath?.trim() ?? channel.url.trim();
    final relativePath = _extractRelativePath(original);
    if (relativePath == null || relativePath.isEmpty) {
      throw const ProviderFlowException(
        'El canal no contiene una ruta Flow válida.',
      );
    }

    final now = DateTime.now();
    final immediateSameChannelRetry =
        _lastResolvedPath == relativePath &&
        _lastResolvedAt != null &&
        now.difference(_lastResolvedAt!) < const Duration(seconds: 12);

    final token = await _freshToken(
      forceRefresh: forceRefresh || immediateSameChannelRetry,
      userAgent: _channelUserAgent(channel),
    );
    _lastResolvedPath = relativePath;
    _lastResolvedAt = now;

    final cleanPath = relativePath.replaceFirst(RegExp(r'^/+'), '');
    final url = 'https://${token.host}/${token.token}/$cleanPath';
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.isEmpty || parsed.scheme != 'https') {
      throw const ProviderFlowException(
        'El proveedor devolvió una URL Flow inválida.',
      );
    }

    return ProviderFlowResolvedStream(
      url: parsed.toString(),
      headers: channel.resolvedHttpHeaders(
        _defaultUserAgent,
        includeDefaultUserAgent: true,
      ),
    );
  }

  void invalidate() {
    _cachedToken = null;
  }

  Future<_ProviderFlowToken> _freshToken({
    required bool forceRefresh,
    required String userAgent,
  }) async {
    final now = DateTime.now();
    final cached = _cachedToken;
    if (!forceRefresh && cached != null && cached.expiresAt.isAfter(now)) {
      return cached;
    }
    if (forceRefresh) _cachedToken = null;

    final active = _refreshing;
    if (active != null) return active;

    final future = _refreshToken(userAgent);
    _refreshing = future;
    try {
      final token = await future;
      _cachedToken = token;
      return token;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<_ProviderFlowToken> _refreshToken(String userAgent) async {
    Object? lastError;
    for (final seed in _providerSeeds) {
      try {
        final found = await _probeSeed(seed, userAgent);
        if (found != null) {
          final ttl = Duration(milliseconds: 45000 + _random.nextInt(15001));
          return _ProviderFlowToken(
            host: found.$1,
            token: found.$2,
            expiresAt: DateTime.now().add(ttl),
          );
        }
      } catch (error) {
        lastError = error;
      }
    }
    throw ProviderFlowException(
      lastError == null
          ? 'No se pudo obtener una sesión CDN del proveedor.'
          : 'No se pudo renovar la sesión CDN del proveedor.',
      retryable: true,
    );
  }

  Future<(String, String)?> _probeSeed(String seed, String userAgent) async {
    var current = Uri.parse(seed);
    for (var hop = 0; hop < 5; hop++) {
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['User-Agent'] = userAgent;
      final response = await _client.send(request).timeout(
        const Duration(seconds: 10),
      );
      await response.stream.drain<void>().timeout(const Duration(seconds: 10));

      final location = response.headers['location'];
      if (location != null && location.trim().isNotEmpty) {
        final next = current.resolve(location.trim());
        final token = _extractToken(next);
        if (token != null) return token;
        current = next;
        continue;
      }

      final token = _extractToken(current);
      if (token != null) return token;
      if (!_redirectStatus(response.statusCode)) return null;
    }
    return null;
  }

  (String, String)? _extractToken(Uri uri) {
    final match = RegExp(r'/(tok_[^/]+)').firstMatch(uri.path);
    if (match == null || uri.host.isEmpty) return null;
    final token = match.group(1);
    if (token == null || token.isEmpty) return null;
    return (uri.host, token);
  }

  String? _extractRelativePath(String value) {
    final direct = RegExp(r'(live/c\d+eds/[^?#]*)', caseSensitive: false)
        .firstMatch(value);
    if (direct != null) return direct.group(1);
    final alternate = RegExp(r'(c\d+eds/[^?#]*)', caseSensitive: false)
        .firstMatch(value);
    final path = alternate?.group(1);
    return path == null ? null : 'live/$path';
  }

  String _channelUserAgent(Channel channel) {
    final headers = channel.resolvedHttpHeaders(
      _defaultUserAgent,
      includeDefaultUserAgent: true,
    );
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'user-agent' && entry.value.isNotEmpty) {
        return entry.value;
      }
    }
    return _defaultUserAgent;
  }

  bool _redirectStatus(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;
}
