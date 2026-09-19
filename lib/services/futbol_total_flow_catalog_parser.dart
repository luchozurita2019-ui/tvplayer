import 'dart:convert';

import '../models/channel.dart';
import 'clearkey_drm_config.dart';

class FutbolTotalFlowCatalog {
  final List<Channel> channels;
  final List<String> categories;
  final List<String> seeds;
  final String? seedUserAgent;
  final List<String> warnings;
  final int skippedWeb;
  final int skippedDrm;

  FutbolTotalFlowCatalog({
    required List<Channel> channels,
    required List<String> categories,
    required List<String> seeds,
    required this.seedUserAgent,
    required List<String> warnings,
    required this.skippedWeb,
    required this.skippedDrm,
  }) : channels = List.unmodifiable(channels),
       categories = List.unmodifiable(categories),
       seeds = List.unmodifiable(seeds),
       warnings = List.unmodifiable(warnings);
}

class FutbolTotalFlowCatalogParser {
  static const String dynamicStreamPrefix = 'tvfull-dynamic://stream/';

  const FutbolTotalFlowCatalogParser();

  FutbolTotalFlowCatalog parse(\n    String content, {\n    bool allowWebPlayback = false,\n  }) {
    dynamic decoded;
    try {
      decoded = jsonDecode(
        content.startsWith('\uFEFF') ? content.substring(1) : content,
      );
    } on FormatException {
      throw const FormatException('El catálogo Flow no es JSON válido.');
    }
    if (decoded is! Map) {
      throw const FormatException('El catálogo Flow debe ser un objeto JSON.');
    }
    final root = Map<String, dynamic>.from(decoded);

    final seeds = <String>[];
    final rawSeeds = root['seeds'];
    if (rawSeeds is List) {
      for (final value in rawSeeds) {
        final text = _text(value);
        if (text != null && _isHttpUrl(text)) seeds.add(text);
      }
    }

    final channels = <Channel>[];
    final categories = <String>[];
    final categorySet = <String>{};
    final warnings = <String>[];
    var skippedWeb = 0;
    var skippedDrm = 0;

    final rawCategories = root['categories'];
    if (rawCategories is! List) {
      throw const FormatException('El catálogo Flow no contiene categories[].');
    }

    for (var i = 0; i < rawCategories.length; i++) {
      final rawCategory = rawCategories[i];
      if (rawCategory is! Map) {
        warnings.add('categories[$i]: categoría inválida; omitida.');
        continue;
      }
      final category = Map<String, dynamic>.from(rawCategory);
      final group = _text(category['name']) ?? 'Sin categoría';
      final samples = category['samples'];
      if (samples is! List) {
        warnings.add('categories[$i]: falta samples[]; categoría omitida.');
        continue;
      }

      for (var j = 0; j < samples.length; j++) {
        final rawSample = samples[j];
        if (rawSample is! Map) {
          warnings.add('categories[$i].samples[$j]: entrada inválida.');
          continue;
        }
        final sample = Map<String, dynamic>.from(rawSample);

        final type = (_text(sample['type']) ?? 'CLEARKEY').toUpperCase();
        final webOnlyType =
            type == 'WEBVIEW' || type == 'WEB' || type == 'IFRAME';
        if (webOnlyType && !allowWebPlayback) {
          skippedWeb++;
          continue;
        }

        final drm = _text(sample['drm_license_uri']) ?? _text(sample['drm']);
        ClearKeyDrmConfig? clearKey;
        if (drm != null) {
          try {
            clearKey = ClearKeyDrmConfig.parse(drm);
          } on FormatException {
            skippedDrm++;
            warnings.add(
              'categories[$i].samples[$j]: DRM no compatible; canal omitido.',
            );
            continue;
          }
        }

        final originalUrl =
            _text(sample['original_url']) ?? _text(sample['url']);
        if (originalUrl == null || !_isHttpUrl(originalUrl)) {
          warnings.add(
            'categories[$i].samples[$j]: URL directa HTTP/HTTPS ausente; omitida.',
          );
          continue;
        }

        final headers = _headers(sample['headers'], warnings, i, j);
        final logo = _text(sample['icono']) ?? _text(sample['logo']);
        final name = _text(sample['name']) ?? 'Canal';
        final globalIndex = _valueText(sample['globalIndex']);
        final dynamicId =
            _firstValueText(sample, const ['resolver_id', 'stream_id', 'id']) ??
            globalIndex ??
            originalUrl;
        final providerFlow = _looksLikeProviderFlow(
          sample,
          originalUrl,
          headers,
        );
        final playbackUrl = providerFlow
            ? '$dynamicStreamPrefix${Uri.encodeComponent(dynamicId)}'
            : originalUrl;
        final detectedMime = _streamMimeType(type, originalUrl);
        final webPlayback =
            allowWebPlayback &&
            !providerFlow &&
            (webOnlyType ||
                ((type == 'DIRECTO' || type == 'DIRECT') &&
                    detectedMime == null));
        final streamMimeType = webPlayback ? 'text/html' : detectedMime;

        channels.add(
          Channel(
            name: name,
            url: playbackUrl,
            logoUrl: logo != null && _isHttpUrl(logo) ? logo : null,
            group: group,
            drmKeyId: clearKey?.keyId,
            drmKey: clearKey?.key,
            streamMimeType: streamMimeType,
            dynamicStreamId: providerFlow ? dynamicId : null,
            dynamicStreamPath: providerFlow ? originalUrl : null,
            providerGlobalIndex: globalIndex,
            httpUserAgent: _headerValue(headers, 'user-agent'),
            httpReferrer:
                _headerValue(headers, 'referer') ??
                _headerValue(headers, 'referrer'),
            httpHeaders: headers.isEmpty ? null : Map.unmodifiable(headers),
          ),
        );

        if (categorySet.add(group)) categories.add(group);
      }
    }

    if (channels.isEmpty) {
      final details = <String>[
        if (skippedWeb > 0) '$skippedWeb WEB/IFRAME',
        if (skippedDrm > 0) '$skippedDrm DRM',
      ];
      throw FormatException(
        details.isEmpty
            ? 'El catálogo Flow no contiene streams directos reproducibles.'
            : 'El catálogo Flow no contiene streams directos reproducibles; se omitieron ${details.join(' y ')}.',
      );
    }

    return FutbolTotalFlowCatalog(
      channels: channels,
      categories: categories,
      seeds: seeds,
      seedUserAgent: _text(root['seed_ua']),
      warnings: warnings,
      skippedWeb: skippedWeb,
      skippedDrm: skippedDrm,
    );
  }

  Map<String, String> _headers(
    dynamic raw,
    List<String> warnings,
    int categoryIndex,
    int sampleIndex,
  ) {
    if (raw == null) return <String, String>{};
    if (raw is! Map) {
      warnings.add(
        'categories[$categoryIndex].samples[$sampleIndex].headers: objeto inválido; ignorado.',
      );
      return <String, String>{};
    }

    final result = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString().trim() ?? '';
      final value = entry.value?.toString().trim() ?? '';
      if (key.isEmpty || value.isEmpty) continue;
      if (value.contains('\r') ||
          value.contains('\n') ||
          value.contains('\u0000')) {
        continue;
      }
      result[key] = value;
    }
    return result;
  }

  String? _headerValue(Map<String, String> headers, String wanted) {
    final lower = wanted.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  String? _text(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _valueText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  String? _firstValueText(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      final value = _valueText(raw[key]);
      if (value != null) return value;
    }
    return null;
  }

  bool _looksLikeProviderFlow(
    Map<String, dynamic> sample,
    String originalUrl,
    Map<String, String> headers,
  ) {
    if (!RegExp(r'live/c\d+eds/', caseSensitive: false)
        .hasMatch(originalUrl)) {
      return false;
    }

    final lowerUrl = originalUrl.toLowerCase();
    if (lowerUrl.contains('flow.com.ar') ||
        lowerUrl.contains('cvattv.com.ar')) {
      return true;
    }

    for (final entry in headers.entries) {
      final key = entry.key.toLowerCase();
      if (key != 'referer' && key != 'referrer' && key != 'origin') continue;
      final value = entry.value.toLowerCase();
      if (value.contains('flow.com.ar') || value.contains('cvattv.com.ar')) {
        return true;
      }
    }

    final source = _valueText(sample['source'])?.toLowerCase();
    return source == 'flow';
  }

  String? _streamMimeType(String type, String originalUrl) {
    final parsedPath = Uri.tryParse(originalUrl)?.path.toLowerCase() ?? '';
    String? extensionMime = parsedPath.endsWith('.mpd')
        ? 'application/dash+xml'
        : parsedPath.endsWith('.m3u8')
        ? 'application/x-mpegURL'
        : null;

    final lowerUrl = originalUrl.toLowerCase();
    extensionMime ??= lowerUrl.contains('.mpd')
        ? 'application/dash+xml'
        : lowerUrl.contains('.m3u8')
        ? 'application/x-mpegURL'
        : null;

    return switch (type.trim().toUpperCase()) {
      'HLS' || 'M3U8' => 'application/x-mpegURL',
      'DASH' || 'MPD' => 'application/dash+xml',
      'CLEARKEY' => extensionMime ?? 'application/dash+xml',
      'DIRECTO' || 'DIRECT' => extensionMime,
      _ => extensionMime,
    };
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
