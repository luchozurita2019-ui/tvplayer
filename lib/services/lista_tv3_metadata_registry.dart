class ListaTv3StreamVariant {
  final String playCode;
  final String? license;
  final String? mediaCode;
  final String? cdnType;
  final String? tag;
  final String? quality;
  final String? avFormat;
  final String? supportVideoType;

  const ListaTv3StreamVariant({
    required this.playCode,
    this.license,
    this.mediaCode,
    this.cdnType,
    this.tag,
    this.quality,
    this.avFormat,
    this.supportVideoType,
  });
}

class ListaTv3ChannelMetadata {
  final String channelCode;
  final String name;
  final List<ListaTv3StreamVariant> variants;

  const ListaTv3ChannelMetadata({
    required this.channelCode,
    required this.name,
    required this.variants,
  });
}

/// Registro efímero de la metadata sensible del catálogo de investigación.
///
/// Nunca se serializa dentro de Channel ni se escribe por separado. Se vuelve a
/// construir cada vez que TV FULL lee la copia privada del JSON local. Así el
/// resolvedor temporal puede usar los mismos datos de entrada que recibe el
/// motor original (playCode/license/cdnType/tag/calidad/formato) sin propagar
/// tokens a favoritos, snapshots o al repositorio.
class ListaTv3MetadataRegistry {
  ListaTv3MetadataRegistry._();

  static final ListaTv3MetadataRegistry instance = ListaTv3MetadataRegistry._();

  final Map<String, ListaTv3ChannelMetadata> _channels =
      <String, ListaTv3ChannelMetadata>{};

  ListaTv3ChannelMetadata? channel(String channelCode) =>
      _channels[channelCode.trim()];

  void replaceFromRawChannels(List rawChannels) {
    final next = <String, ListaTv3ChannelMetadata>{};
    for (final raw in rawChannels) {
      if (raw is! Map) continue;
      final channelCode = _text(raw['channelCode']);
      if (channelCode == null) continue;
      final name = _text(raw['name']) ?? _text(raw['alias']) ?? channelCode;
      final variants = <ListaTv3StreamVariant>[];
      final rawAddresses = raw['liveAddressList'];
      if (rawAddresses is List) {
        for (final item in rawAddresses) {
          if (item is! Map) continue;
          final playCode = _text(item['playCode']);
          if (playCode == null) continue;
          final license = _text(item['license']);
          variants.add(
            ListaTv3StreamVariant(
              playCode: playCode,
              license: license,
              mediaCode: _licenseValue(license, 'media_code'),
              cdnType: _text(item['cdnType']),
              tag: _text(item['tag']),
              quality: _text(item['quality']),
              avFormat: _text(item['AVFormat']),
              supportVideoType: _text(item['supportVideoType']),
            ),
          );
        }
      }
      next[channelCode] = ListaTv3ChannelMetadata(
        channelCode: channelCode,
        name: name,
        variants: List<ListaTv3StreamVariant>.unmodifiable(variants),
      );
    }
    _channels
      ..clear()
      ..addAll(next);
  }

  void clear() => _channels.clear();

  static String? _licenseValue(String? license, String key) {
    if (license == null || license.isEmpty) return null;
    try {
      final parsed = Uri.splitQueryString(license);
      return _text(parsed[key]);
    } catch (_) {
      return null;
    }
  }

  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }
}
