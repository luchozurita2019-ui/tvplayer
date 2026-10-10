import 'dart:convert';

/// Transporte alternativo del mismo canal; sus credenciales son independientes.
class ChannelBackup {
  final String url;
  final Map<String, String> headers;

  const ChannelBackup({required this.url, this.headers = const {}});

  static ChannelBackup? tryFromJson(dynamic raw) {
    if (raw is! Map || raw['url'] is! String) return null;
    final url = (raw['url'] as String).trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        url.contains(RegExp(r'[\r\n]'))) {
      return null;
    }
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.key is! String || entry.value is! String) continue;
        final key = (entry.key as String).trim().toLowerCase();
        final value = (entry.value as String).trim();
        if (RegExp(r'^[a-z0-9-]+$').hasMatch(key) &&
            value.isNotEmpty &&
            !value.contains(RegExp(r'[\r\n]'))) {
          headers[key] = value;
        }
      }
    }
    return ChannelBackup(url: url, headers: Map.unmodifiable(headers));
  }

  String get transportKey {
    final keys = headers.keys.toList()..sort();
    return jsonEncode([url, {for (final key in keys) key: headers[key]}]);
  }

  Map<String, dynamic> toJson() => {'url': url, 'headers': headers};
}
