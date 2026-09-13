from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label} marker not found')
    return text.replace(old, new, 1)


def patch_channel() -> None:
    path = Path('lib/models/channel.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        "  final String? xtreamStreamId; // stream_id real para APIs Xtream (EPG, etc.)\n",
        "  final String? xtreamStreamId; // stream_id real para APIs Xtream (EPG, etc.)\n"
        "  final String? streamType; // hls | dash\n"
        "  final Map<String, String>? manifestHeaders;\n"
        "  final Map<String, String>? urlHeaders;\n"
        "  final Map<String, String>? secondaryHeaders;\n"
        "  final bool protectedContent;\n"
        "  final String? protectionType;\n",
        'channel fields',
    )
    text = replace_once(
        text,
        "    this.xtreamStreamId,\n    this.httpUserAgent,",
        "    this.xtreamStreamId,\n"
        "    this.streamType,\n"
        "    this.manifestHeaders,\n"
        "    this.urlHeaders,\n"
        "    this.secondaryHeaders,\n"
        "    this.protectedContent = false,\n"
        "    this.protectionType,\n"
        "    this.httpUserAgent,",
        'channel constructor',
    )
    text = replace_once(
        text,
        "        'xtreamStreamId': xtreamStreamId,\n        'httpUserAgent': httpUserAgent,",
        "        'xtreamStreamId': xtreamStreamId,\n"
        "        if (streamType != null) 'streamType': streamType,\n"
        "        if (manifestHeaders != null) 'manifestHeaders': manifestHeaders,\n"
        "        if (urlHeaders != null) 'urlHeaders': urlHeaders,\n"
        "        if (secondaryHeaders != null) 'secondaryHeaders': secondaryHeaders,\n"
        "        'protectedContent': protectedContent,\n"
        "        if (protectionType != null) 'protectionType': protectionType,\n"
        "        'httpUserAgent': httpUserAgent,",
        'channel json',
    )
    text = replace_once(
        text,
        "  factory Channel.fromJson(Map<String, dynamic> json) {\n    final rawHeaders = json['httpHeaders'];\n    Map<String, String>? headers;\n    if (rawHeaders is Map) {\n      headers = <String, String>{};\n      for (final entry in rawHeaders.entries) {\n        final key = entry.key?.toString().trim() ?? '';\n        final value = entry.value?.toString().trim() ?? '';\n        if (key.isNotEmpty && value.isNotEmpty) headers[key] = value;\n      }\n      if (headers.isEmpty) headers = null;\n    }\n",
        "  factory Channel.fromJson(Map<String, dynamic> json) {\n"
        "    Map<String, String>? mapOf(dynamic raw) {\n"
        "      if (raw is! Map) return null;\n"
        "      final result = <String, String>{};\n"
        "      for (final entry in raw.entries) {\n"
        "        final key = entry.key?.toString().trim() ?? '';\n"
        "        final value = entry.value?.toString().trim() ?? '';\n"
        "        if (key.isNotEmpty && value.isNotEmpty) result[key] = value;\n"
        "      }\n"
        "      return result.isEmpty ? null : result;\n"
        "    }\n"
        "    final headers = mapOf(json['httpHeaders']);\n",
        'channel helper',
    )
    text = replace_once(
        text,
        "      xtreamStreamId: json['xtreamStreamId'] as String?,\n      httpUserAgent: json['httpUserAgent'] as String?,",
        "      xtreamStreamId: json['xtreamStreamId'] as String?,\n"
        "      streamType: json['streamType'] as String?,\n"
        "      manifestHeaders: mapOf(json['manifestHeaders']),\n"
        "      urlHeaders: mapOf(json['urlHeaders']),\n"
        "      secondaryHeaders: mapOf(json['secondaryHeaders']),\n"
        "      protectedContent: json['protectedContent'] == true,\n"
        "      protectionType: json['protectionType'] as String?,\n"
        "      httpUserAgent: json['httpUserAgent'] as String?,",
        'channel parse fields',
    )
    path.write_text(text, encoding='utf-8')


def patch_json_catalog() -> None:
    path = Path('lib/services/json_catalog_service.dart')
    text = path.read_text(encoding='utf-8')
    old = """        final icon = _clean(item['icono']);
        final headers = <String, String>{};
        for (final key in const ['headers', 'headersM3u8', 'headersUrl', 'headers2']) {
          headers.addAll(_stringMap(item[key]));
        }

        channels.add(Channel(
          name: name,
          url: parsed.toString(),
          logoUrl: icon != null && !icon.startsWith('data:') ? icon : null,
          group: categoryName ?? _clean(item['category']),
          httpHeaders: headers.isEmpty ? null : headers,
        ));
"""
    new = """        final icon = _clean(item['icono']);
        final baseHeaders = _stringMap(item['headers']);
        final manifestHeaders = _stringMap(item['headersM3u8']);
        final urlHeaders = _stringMap(item['headersUrl']);
        final secondaryHeaders = _stringMap(item['headers2']);
        final rawType = (_clean(item['type']) ?? '').toUpperCase();
        final cleanPath = parsed.path.toLowerCase();
        final streamType = cleanPath.endsWith('.mpd') || rawType == 'DASH'
            ? 'dash'
            : cleanPath.endsWith('.m3u8') || rawType == 'HLS'
                ? 'hls'
                : null;
        final protectedContent = _clean(item['drm_license_uri']) != null ||
            rawType == 'CLEARKEY' || rawType == 'WIDEVINE';

        channels.add(Channel(
          name: name,
          url: parsed.toString(),
          logoUrl: icon != null && !icon.startsWith('data:') ? icon : null,
          group: categoryName ?? _clean(item['category']),
          streamType: streamType,
          manifestHeaders: manifestHeaders.isEmpty ? null : manifestHeaders,
          urlHeaders: urlHeaders.isEmpty ? null : urlHeaders,
          secondaryHeaders: secondaryHeaders.isEmpty ? null : secondaryHeaders,
          protectedContent: protectedContent,
          protectionType: protectedContent ? rawType : null,
          httpHeaders: baseHeaders.isEmpty ? null : baseHeaders,
        ));
"""
    text = replace_once(text, old, new, 'json mapping')
    path.write_text(text, encoding='utf-8')


def patch_dart_player() -> None:
    path = Path('lib/screens/android_media3_texture_player_screen.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        "  Map<String, String> get _headers =>\n      _channel.resolvedHttpHeaders(_media3DefaultUserAgent);",
        "  Map<String, String> get _headers {\n"
        "    final result = _channel.resolvedHttpHeaders(_media3DefaultUserAgent);\n"
        "    final manifest = _channel.manifestHeaders;\n"
        "    if (manifest != null) result.addAll(manifest);\n"
        "    return result;\n"
        "  }",
        'player headers',
    )
    needle = """    try {
      await _player.invokeMethod<void>('prepare', {
        'url': _channel.url,
        'requestGeneration': generation,
        'headers': headers,
        'userAgent': userAgent ?? _media3DefaultUserAgent,
        'isLive': true,
      });
"""
    replacement = """    if (_channel.protectedContent) {
      _finishWithError(
        'Canal protegido',
        'PROTECTED_SOURCE · Falta la configuración de licencia autorizada del proveedor.',
      );
      return;
    }

    try {
      await _player.invokeMethod<void>('prepare', {
        'url': _channel.url,
        'requestGeneration': generation,
        'headers': headers,
        'userAgent': userAgent ?? _media3DefaultUserAgent,
        'isLive': true,
        'contentType': _channel.streamType,
      });
"""
    text = replace_once(text, needle, replacement, 'player prepare')
    path.write_text(text, encoding='utf-8')


def patch_android_player() -> None:
    path = Path('android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        "    private var currentUserAgent: String = DEFAULT_UA\n    private var isLive = false",
        "    private var currentUserAgent: String = DEFAULT_UA\n"
        "    private var currentContentType: String? = null\n"
        "    private var isLive = false",
        'android state',
    )
    text = replace_once(
        text,
        "                    isLive = call.argument<Boolean>(\"isLive\") ?: true\n                    prepare(url, headers, userAgent, position, requestGeneration)",
        "                    isLive = call.argument<Boolean>(\"isLive\") ?: true\n"
        "                    currentContentType = call.argument<String>(\"contentType\")\n"
        "                    prepare(url, headers, userAgent, position, requestGeneration)",
        'android call',
    )
    old_media = """        val factory = mediaSourceFactory(headers, userAgent, useFallbackDns)
        val useHlsMime = isLive && (currentSourceForcedHls || forceHls || looksLikeHls(url))
        currentSourceForcedHls = useHlsMime
        val itemBuilder = MediaItem.Builder()
            .setUri(Uri.parse(url))
            .setMediaId(clientGeneration.toString())
        if (useHlsMime) itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
        if (isLive) {
"""
    new_media = """        val factory = mediaSourceFactory(headers, userAgent, useFallbackDns)
        val requestedType = currentContentType?.trim()?.lowercase()
        val useDashMime = requestedType == "dash" || url.substringBefore('?').lowercase().endsWith(".mpd")
        val useHlsMime = !useDashMime &&
            (requestedType == "hls" ||
                (isLive && (currentSourceForcedHls || forceHls || looksLikeHls(url))))
        currentSourceForcedHls = useHlsMime
        val itemBuilder = MediaItem.Builder()
            .setUri(Uri.parse(url))
            .setMediaId(clientGeneration.toString())
        when {
            useDashMime -> itemBuilder.setMimeType(MimeTypes.APPLICATION_MPD)
            useHlsMime -> itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
        }
        if (isLive) {
"""
    text = replace_once(text, old_media, new_media, 'android content type')
    path.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    patch_channel()
    patch_json_catalog()
    patch_dart_player()
    patch_android_player()
