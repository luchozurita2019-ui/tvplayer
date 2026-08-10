/// Representa un único canal/entrada dentro de una lista M3U.
class Channel {
  final String name;
  final String url;
  final String? logoUrl;
  final String? group; // categoría (ej: "Deportes", "Noticias")
  final String? tvgId; // id para cruzar con EPG en el futuro

  // Compatibilidad histórica: seguimos exponiendo User-Agent y Referer de
  // forma explícita porque ya existen listas guardadas con estos campos.
  final String? httpUserAgent;
  final String? httpReferrer;

  // Headers adicionales que algunos proveedores requieren para autorizar el
  // stream (Origin, Cookie, Authorization, Accept, etc.). Nunca se inventan:
  // sólo se conservan cuando vienen declarados por la lista M3U/URL.
  final Map<String, String>? httpHeaders;

  const Channel({
    required this.name,
    required this.url,
    this.logoUrl,
    this.group,
    this.tvgId,
    this.httpUserAgent,
    this.httpReferrer,
    this.httpHeaders,
  });

  Map<String, String> resolvedHttpHeaders(
    String defaultUserAgent, {
    bool includeDefaultUserAgent = true,
  }) {
    final result = <String, String>{};

    void put(String rawKey, String rawValue) {
      final key = rawKey.trim();
      final value = rawValue.trim();
      if (key.isEmpty || value.isEmpty) return;

      // HTTP no distingue mayúsculas/minúsculas en nombres de headers. Evitar
      // pares duplicados como Referer/referer mejora compatibilidad con proxies
      // y servidores estrictos y permite que el proveedor reemplace defaults.
      String? duplicate;
      for (final existing in result.keys) {
        if (existing.toLowerCase() == key.toLowerCase()) {
          duplicate = existing;
          break;
        }
      }
      if (duplicate != null) result.remove(duplicate);
      result[_canonicalHeaderName(key)] = value;
    }

    if (httpUserAgent != null) {
      put('User-Agent', httpUserAgent!);
    } else if (includeDefaultUserAgent) {
      put('User-Agent', defaultUserAgent);
    }
    if (httpReferrer != null) put('Referer', httpReferrer!);

    final extras = httpHeaders;
    if (extras != null) {
      for (final entry in extras.entries) {
        put(entry.key, entry.value);
      }
    }
    return result;
  }

  static String _canonicalHeaderName(String key) {
    return switch (key.trim().toLowerCase()) {
      'user-agent' => 'User-Agent',
      'referer' => 'Referer',
      'referrer' => 'Referer',
      'origin' => 'Origin',
      'cookie' => 'Cookie',
      'authorization' => 'Authorization',
      'accept' => 'Accept',
      'accept-language' => 'Accept-Language',
      'connection' => 'Connection',
      'host' => 'Host',
      _ => key.trim(),
    };
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'logoUrl': logoUrl,
        'group': group,
        'tvgId': tvgId,
        'httpUserAgent': httpUserAgent,
        'httpReferrer': httpReferrer,
        if (httpHeaders != null) 'httpHeaders': httpHeaders,
      };

  factory Channel.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['httpHeaders'];
    Map<String, String>? headers;
    if (rawHeaders is Map) {
      headers = <String, String>{};
      for (final entry in rawHeaders.entries) {
        final key = entry.key?.toString().trim() ?? '';
        final value = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) headers[key] = value;
      }
      if (headers.isEmpty) headers = null;
    }

    return Channel(
      name: json['name'] as String,
      url: json['url'] as String,
      logoUrl: json['logoUrl'] as String?,
      group: json['group'] as String?,
      tvgId: json['tvgId'] as String?,
      httpUserAgent: json['httpUserAgent'] as String?,
      httpReferrer: json['httpReferrer'] as String?,
      httpHeaders: headers,
    );
  }

  /// Clave estable para identificar el canal (usada en favoritos).
  String get uniqueKey => '$name|$url';

  @override
  bool operator ==(Object other) =>
      other is Channel && other.uniqueKey == uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;
}
