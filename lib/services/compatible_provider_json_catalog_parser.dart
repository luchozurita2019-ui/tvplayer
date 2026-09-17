import 'dart:convert';
import 'dart:io';

import '../models/channel.dart';
import 'provider_json_catalog_parser.dart';

/// Adaptador de importación local.
///
/// Mantiene intacto el formato provider.json de TV FULL y, únicamente para
/// archivos locales importados por el usuario, acepta también el catálogo LIVE
/// con raíz `data.channelList`. Las credenciales/licencias del documento no se
/// copian al modelo Channel; la copia privada del JSON sigue bajo el almacenamiento
/// interno que ya utiliza V50 para catálogos locales.
class CompatibleProviderJsonCatalogParser {
  static const String _compiledListaTv3Resolver = String.fromEnvironment(
    'TV_FULL_LISTA3_RESOLVER_URL',
    defaultValue: '',
  );

  final String? _resolverOverride;

  const CompatibleProviderJsonCatalogParser({String? resolverUrl})
    : _resolverOverride = resolverUrl;

  String get _resolverBase => (_resolverOverride ?? _compiledListaTv3Resolver).trim();

  Future<ProviderJsonCatalog> parseFile(File file) async {
    try {
      if (await file.length() > ProviderJsonCatalogParser.maxCatalogBytes) {
        throw const FormatException('El catálogo supera el límite de 16 MB.');
      }
      return parse(await file.readAsString());
    } on FileSystemException {
      throw const FormatException('No se pudo leer el archivo JSON local.');
    }
  }

  ProviderJsonCatalog parse(String content) {
    if (content.length > ProviderJsonCatalogParser.maxCatalogBytes ||
        utf8.encode(content).length > ProviderJsonCatalogParser.maxCatalogBytes) {
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

    if (root is Map && root['categories'] is List) {
      return const ProviderJsonCatalogParser().parse(content);
    }

    if (root is Map) {
      final data = root['data'];
      if (data is Map && data['channelList'] is List) {
        return _parseLiveChannelList(data);
      }
    }

    throw const FormatException(
      'El JSON no contiene categories ni data.channelList.',
    );
  }

  ProviderJsonCatalog _parseLiveChannelList(Map data) {
    final rawChannels = data['channelList'];
    if (rawChannels is! List) {
      throw const FormatException('data.channelList debe ser una lista.');
    }

    final channels = <Channel>[];
    final warnings = <String>[];
    final seen = <String>{};
    final resolver = _parseResolverBase(_resolverBase);

    for (var i = 0; i < rawChannels.length; i++) {
      final raw = rawChannels[i];
      if (raw is! Map) {
        warnings.add('data.channelList[$i]: canal inválido; omitido.');
        continue;
      }

      final channelCode = _text(raw['channelCode']);
      if (channelCode == null || !seen.add(channelCode)) {
        warnings.add(
          'data.channelList[$i]: channelCode ausente o repetido; omitido.',
        );
        continue;
      }

      final name = _text(raw['name']) ?? _text(raw['alias']) ?? channelCode;
      final poster = _httpUrl(_text(raw['posterUrl']));
      final channelNumber = _text(raw['channelNumber']);

      String? playCode;
      String? avFormat;
      final addresses = raw['liveAddressList'];
      if (addresses is List) {
        for (final item in addresses) {
          if (item is! Map) continue;
          playCode ??= _text(item['playCode']);
          avFormat ??= _text(item['AVFormat']);
          if (playCode != null && avFormat != null) break;
        }
      }
      playCode ??= channelCode;

      final directResolverUrl = resolver == null
          ? null
          : _resolverUrl(
              resolver,
              channelCode: channelCode,
              playCode: playCode,
              name: name,
              channelNumber: channelNumber,
            );

      channels.add(
        Channel(
          name: name,
          url: directResolverUrl ??
              '${ProviderJsonCatalogParser.dynamicStreamPrefix}${Uri.encodeComponent(channelCode)}',
          logoUrl: poster,
          group: 'Lista TV 3',
          tvgId: channelCode,
          // Si existe un resolver HTTP propio, Media3 abre ese endpoint y sigue
          // su redirección al stream final. Sin resolver compilado conservamos
          // el camino dinámico de V50 para diagnóstico/configuración posterior.
          dynamicStreamId: directResolverUrl == null ? channelCode : null,
          dynamicStreamPath: playCode,
          providerGlobalIndex: channelNumber,
          streamMimeType: _mimeFor(avFormat),
        ),
      );
    }

    if (channels.isEmpty) {
      throw const FormatException(
        'data.channelList no contiene canales válidos.',
      );
    }

    if (resolver == null && _resolverBase.isNotEmpty) {
      warnings.add(
        'TV_FULL_LISTA3_RESOLVER_URL no es una URL HTTP/HTTPS válida; '
        'Lista TV 3 quedó en modo dinámico.',
      );
    }

    return ProviderJsonCatalog(channels, warnings);
  }

  Uri? _parseResolverBase(String value) {
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  String _resolverUrl(
    Uri base, {
    required String channelCode,
    required String playCode,
    required String name,
    String? channelNumber,
  }) {
    return base
        .replace(
          queryParameters: <String, String>{
            ...base.queryParameters,
            'channelCode': channelCode,
            'playCode': playCode,
            'name': name,
            if (channelNumber != null) 'channelNumber': channelNumber,
          },
        )
        .toString();
  }

  String? _text(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  String? _httpUrl(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return value;
  }

  String? _mimeFor(String? format) {
    return switch (format?.trim().toLowerCase()) {
      'm3u8' || 'hls' => 'application/x-mpegURL',
      'mpd' || 'dash' => 'application/dash+xml',
      'ts' || 'mpegts' || 'mpeg-ts' => 'video/mp2t',
      _ => null,
    };
  }
}
