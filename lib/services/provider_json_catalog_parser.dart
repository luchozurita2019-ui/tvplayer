import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/channel.dart';
import 'clearkey_drm_config.dart';

class ProviderJsonCatalog {
  final List<Channel> channels;
  final List<String> warnings;

  ProviderJsonCatalog(List<Channel> channels, List<String> warnings)
    : channels = List.unmodifiable(channels),
      warnings = List.unmodifiable(warnings);

  List<String> get categories =>
      channels.map((c) => c.group!).toSet().toList(growable: false);
}

/// Parser local y sin red. Los errores nunca incluyen JSON, URLs o claves.
///
/// Un proveedor autorizado puede entregar URLs absolutas en `original_url` o
/// rutas relativas acompañadas por `base_url` (también se acepta
/// `stream_base_url`) en la raíz del catálogo.
class ProviderJsonCatalogParser {
  static const maxCatalogBytes = 16 * 1024 * 1024;
  static const maxIconBytes = 2 * 1024 * 1024;
  static const dynamicStreamPrefix = 'tvfull-dynamic://stream/';

  const ProviderJsonCatalogParser();

  Future<ProviderJsonCatalog> parseFile(File file) async {
    try {
      if (await file.length() > maxCatalogBytes) {
        throw const FormatException('El catálogo supera el límite de 16 MB.');
      }
      return parse(await file.readAsString());
    } on FileSystemException {
      throw const FormatException('No se pudo leer el archivo JSON local.');
    }
  }

  Future<ProviderJsonCatalog> parsePath(String path) => parseFile(File(path));

  ProviderJsonCatalog parse(String content) {
    if (content.length > maxCatalogBytes ||
        utf8.encode(content).length > maxCatalogBytes) {
      throw const FormatException('El catálogo supera el límite de 16 MB.');
    }
    dynamic root;
    try {
      root = jsonDecode(
        content.startsWith('\uFEFF') ? content.substring(1) : content,
      );
    } on FormatException {
      throw const FormatException(
        'JSON inválido. Revisá comas, comillas y llaves.',
      );
    }
    if (root is! Map || root['categories'] is! List) {
      throw const FormatException(
        'El JSON debe contener una lista categories.',
      );
    }

    final warnings = <String>[];
    final channels = <Channel>[];
    final baseUri = _catalogBaseUri(root);
    final resolveAll =
        root['resolver_mode']?.toString().trim().toLowerCase() == 'all';
    final categories = root['categories'] as List;
    for (var i = 0; i < categories.length; i++) {
      final category = categories[i];
      final path = 'categories[$i]';
      if (category is! Map || category['samples'] is! List) {
        warnings.add(
          '$path: falta una lista samples válida; categoría omitida.',
        );
        continue;
      }
      final rawName = category['name'];
      final group = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : 'Sin categoría';
      if (group == 'Sin categoría' && rawName != group) {
        warnings.add('$path.name: se usó Sin categoría.');
      }
      final samples = category['samples'] as List;
      for (var j = 0; j < samples.length; j++) {
        final samplePath = '$path.samples[$j]';
        try {
          channels.add(
            _sample(
              samples[j],
              group,
              samplePath,
              warnings,
              baseUri,
              resolveAll,
            ),
          );
        } on FormatException catch (error) {
          warnings.add('$samplePath: ${error.message} Canal omitido.');
        }
      }
    }

    // summary es informativo: los conteos reales provienen de samples.
    if (channels.isEmpty) {
      final detail = warnings.isEmpty ? '' : ' ${warnings.take(3).join(' ')}';
      throw FormatException('El catálogo no contiene canales válidos.$detail');
    }
    return ProviderJsonCatalog(channels, warnings);
  }

  Uri? _catalogBaseUri(Map root) {
    final rawBase = root.containsKey('base_url')
        ? root['base_url']
        : root['stream_base_url'];
    if (rawBase == null) return null;
    if (rawBase is! String || !_isHttpUrl(rawBase.trim())) {
      throw const FormatException(
        'base_url debe ser una URL HTTP/HTTPS absoluta válida.',
      );
    }
    final value = rawBase.trim();
    final normalized = value.endsWith('/') ? value : '$value/';
    return Uri.parse(normalized);
  }

  Channel _sample(
    dynamic raw,
    String group,
    String path,
    List<String> warnings,
    Uri? baseUri,
    bool resolveAll,
  ) {
    if (raw is! Map) {
      throw const FormatException('El sample debe ser un objeto.');
    }
    final name = raw['name'];
    final rawUrl = raw['original_url'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Falta un name de tipo texto.');
    }
    if (rawUrl is! String || rawUrl.trim().isEmpty) {
      throw const FormatException('Falta original_url de tipo texto.');
    }

    final originalUrl = rawUrl.trim();
    final parsedOriginal = Uri.tryParse(originalUrl);
    final direct = _isHttpUrl(originalUrl);
    if (!direct &&
        (parsedOriginal == null ||
            parsedOriginal.hasScheme ||
            parsedOriginal.hasAuthority ||
            originalUrl.startsWith('//') ||
            RegExp(r'[\x00-\x20]').hasMatch(originalUrl))) {
      throw const FormatException('original_url relativa inválida.');
    }
    final explicitResolverId = _firstText(raw, const [
      'resolver_id',
      'stream_id',
      'id',
    ]);
    final globalIndexRaw = raw['globalIndex']?.toString().trim();
    final globalIndex = globalIndexRaw == null || globalIndexRaw.isEmpty
        ? null
        : globalIndexRaw;
    final dynamicId = explicitResolverId ?? globalIndex ?? originalUrl;
    final sampleResolverRequired =
        raw['resolver_required'] == true ||
        raw['resolver_required']?.toString().toLowerCase() == 'true';
    final shouldResolve =
        resolveAll || sampleResolverRequired || (!direct && baseUri == null);
    final url = shouldResolve
        ? '$dynamicStreamPrefix${Uri.encodeComponent(dynamicId)}'
        : _resolveStreamUrl(originalUrl, baseUri);

    ClearKeyDrmConfig? drm;
    final rawDrm = raw['drm_license_uri'];
    if (raw.containsKey('drm_license_uri') && rawDrm != null) {
      if (rawDrm is! String) {
        throw const FormatException('drm_license_uri debe ser texto.');
      }
      drm = ClearKeyDrmConfig.parse(rawDrm);
    }

    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders != null && rawHeaders is! Map) {
      throw const FormatException('headers debe ser un objeto de textos.');
    }
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String ||
            value is! String ||
            !RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$").hasMatch(key) ||
            value.contains('\r') ||
            value.contains('\n') ||
            value.contains('\u0000')) {
          throw const FormatException(
            'headers contiene un nombre o valor inválido.',
          );
        }
        headers[key] = value.trim();
      }
    }

    String? logoUrl;
    Uint8List? logoBytes;
    final icon = raw['icono'];
    if (icon is String && icon.trim().isNotEmpty) {
      final value = icon.trim();
      if (value.toLowerCase().startsWith('data:image')) {
        try {
          if (value.length > maxIconBytes * 4 ~/ 3 + 256) {
            throw const FormatException();
          }
          final data = UriData.parse(value);
          if (!data.isBase64 || !data.mimeType.startsWith('image/')) {
            throw const FormatException();
          }
          final decoded = data.contentAsBytes();
          if (decoded.isEmpty || decoded.length > maxIconBytes) {
            throw const FormatException();
          }
          logoBytes = decoded;
        } on FormatException {
          warnings.add(
            '$path.icono: imagen base64 inválida o demasiado grande; se omitió el logo.',
          );
        }
      } else if (_isHttpUrl(value)) {
        logoUrl = value;
      } else {
        warnings.add('$path.icono: imagen no reconocida; se omitió el logo.');
      }
    } else if (icon != null && icon != '') {
      warnings.add('$path.icono: debe ser texto; se omitió el logo.');
    }

    final type = raw['type'];
    String? mime;
    if (type is String) {
      mime = switch (type.trim().toUpperCase()) {
        'HLS' || 'M3U8' => 'application/x-mpegURL',
        'DASH' || 'MPD' || 'CLEARKEY' => 'application/dash+xml',
        _ => null,
      };
      if (mime == null) {
        warnings.add('$path.type: formato a detectar al reproducir.');
      }
    } else if (type != null) {
      warnings.add(
        '$path.type: debe ser texto; formato a detectar al reproducir.',
      );
    }
    final uriPath = Uri.parse(originalUrl).path.toLowerCase();
    mime ??= uriPath.endsWith('.mpd')
        ? 'application/dash+xml'
        : uriPath.endsWith('.m3u8')
        ? 'application/x-mpegURL'
        : null;
    if (drm != null && mime == 'application/x-mpegURL') {
      warnings.add(
        '$path: ClearKey con HLS no está soportado por Media3; el proveedor debe entregar DASH/CENC compatible.',
      );
    }

    return Channel(
      name: name.trim(),
      url: url,
      group: group,
      logoUrl: logoUrl,
      logoBytes: logoBytes,
      httpHeaders: headers.isEmpty ? null : Map.unmodifiable(headers),
      dynamicStreamId: shouldResolve ? dynamicId : null,
      dynamicStreamPath: shouldResolve ? originalUrl : null,
      providerGlobalIndex: globalIndex,
      drmKeyId: drm?.keyId,
      drmKey: drm?.key,
      streamMimeType: mime,
    );
  }

  String? _firstText(Map raw, List<String> keys) {
    for (final key in keys) {
      final value = raw[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return null;
  }

  String _resolveStreamUrl(String value, Uri? baseUri) {
    if (_isHttpUrl(value)) return value;
    if (baseUri == null ||
        RegExp(r'[\x00-\x20]').hasMatch(value) ||
        value.startsWith('//')) {
      throw const FormatException(
        'original_url relativa requiere base_url del proveedor.',
      );
    }

    final relative = Uri.tryParse(value);
    if (relative == null || relative.hasScheme || relative.hasAuthority) {
      throw const FormatException('original_url relativa inválida.');
    }
    final resolved = baseUri.resolveUri(relative).toString();
    if (!_isHttpUrl(resolved)) {
      throw const FormatException(
        'original_url no pudo resolverse de forma segura.',
      );
    }
    return resolved;
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        !RegExp(r'[\x00-\x20]').hasMatch(value);
  }
}
