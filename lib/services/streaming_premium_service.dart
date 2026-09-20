import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'remote_provisioning_service.dart';

class StreamingPremiumCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;

  const StreamingPremiumCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    required this.secure,
  });

  factory StreamingPremiumCookie.fromJson(Map<String, dynamic> json) {
    return StreamingPremiumCookie(
      name: json['name']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      path: json['path']?.toString().startsWith('/') == true
          ? json['path'].toString()
          : '/',
      hostOnly: json['hostOnly'] == true,
      secure: json['secure'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'hostOnly': hostOnly,
        'secure': secure,
      };
}

class StreamingPremiumSession {
  final String platform;
  final String url;
  final List<StreamingPremiumCookie> cookies;
  final bool shared;

  const StreamingPremiumSession({
    required this.platform,
    required this.url,
    required this.cookies,
    required this.shared,
  });
}

class StreamingPremiumUnavailableException implements Exception {
  final String status;

  const StreamingPremiumUnavailableException(this.status);

  @override
  String toString() {
    switch (status) {
      case 'disabled':
        return 'La plataforma está deshabilitada temporalmente.';
      case 'free_without_session':
      case 'no_session':
        return 'No hay una sesión disponible en este momento.';
      default:
        return 'La plataforma no está disponible en este momento.';
    }
  }
}

class StreamingPremiumService {
  StreamingPremiumService({
    RemoteProvisioningService? provisioning,
    http.Client? client,
  })  : _provisioning = provisioning ?? RemoteProvisioningService(),
        _client = client ?? http.Client();

  static const _endpoint =
      'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-streaming-premium';
  static const MethodChannel _webPlayback =
      MethodChannel('tvfull/web_playback');

  final RemoteProvisioningService _provisioning;
  final http.Client _client;

  Future<StreamingPremiumSession> prepare(String platform) async {
    var credentials =
        await _provisioning.loadCredentials() ??
        await _provisioning.ensureRegistered();

    var response = await _request(platform, credentials);
    if (response.statusCode == 401) {
      await _provisioning.clearCredentials();
      credentials = await _provisioning.ensureRegistered();
      response = await _request(platform, credentials);
    }

    if (response.statusCode == 404) {
      var status = 'no_session';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['status'] != null) {
          status = decoded['status'].toString();
        }
      } catch (_) {}
      throw StreamingPremiumUnavailableException(status);
    }

    if (response.statusCode == 403) {
      throw const StreamingPremiumUnavailableException('disabled');
    }

    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo preparar Streaming Premium (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Sesión Streaming Premium inválida.');
    }
    final data = Map<String, dynamic>.from(decoded);
    if (data['available'] != true) {
      throw StreamingPremiumUnavailableException(
        data['status']?.toString() ?? 'no_session',
      );
    }

    final url = data['url']?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.trim().isEmpty) {
      throw const FormatException('URL Streaming Premium inválida.');
    }

    final cookies = <StreamingPremiumCookie>[];
    final rawCookies = data['cookies'];
    if (rawCookies is List) {
      for (final raw in rawCookies) {
        if (raw is! Map) continue;
        final cookie = StreamingPremiumCookie.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (cookie.name.isEmpty ||
            cookie.value.isEmpty ||
            cookie.domain.isEmpty) {
          continue;
        }
        cookies.add(cookie);
      }
    }
    if (cookies.isEmpty) {
      throw const FormatException(
        'La sesión compartida no contiene cookies válidas.',
      );
    }

    return StreamingPremiumSession(
      platform: data['platform']?.toString() ?? platform,
      url: url,
      cookies: List.unmodifiable(cookies),
      shared: data['shared'] == true,
    );
  }

  Future<void> open(String platform) async {
    final session = await prepare(platform);
    await _webPlayback.invokeMethod<void>('open', {
      'url': session.url,
      'headers': const <String, String>{
        'Accept-Language': 'es-AR,es;q=0.9,en;q=0.7',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/126.0.0.0 Safari/537.36',
      },
      'cookies': session.cookies
          .map((cookie) => cookie.toJson())
          .toList(growable: false),
      'clearCookiesOnExit': true,
      'streamingPremium': true,
    });
  }

  Future<http.Response> _request(
    String platform,
    RemoteDeviceCredentials credentials,
  ) {
    return _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'x-tvfull-device-code': credentials.code,
            'x-tvfull-device-secret': credentials.secret,
          },
          body: jsonEncode({'platform': platform}),
        )
        .timeout(const Duration(seconds: 18));
  }

  void close() => _client.close();
}
