/// Representa un único canal/entrada dentro de una lista M3U.
class Channel {
  final String name;
  final String url;
  final String? logoUrl;
  final String? group; // categoría (ej: "Deportes", "Noticias")
  final String? tvgId; // id para cruzar con EPG en el futuro

  // Headers opcionales para el stream. Muchos proveedores IPTV
  // bloquean o cuelgan la conexión si no reciben un User-Agent
  // reconocido, o exigen un Referer específico. Estos vienen de
  // líneas #EXTVLCOPT en el M3U si el proveedor las incluye; si no,
  // la app aplica un User-Agent por defecto razonable (ver player).
  final String? httpUserAgent;
  final String? httpReferrer;

  const Channel({
    required this.name,
    required this.url,
    this.logoUrl,
    this.group,
    this.tvgId,
    this.httpUserAgent,
    this.httpReferrer,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'logoUrl': logoUrl,
        'group': group,
        'tvgId': tvgId,
        'httpUserAgent': httpUserAgent,
        'httpReferrer': httpReferrer,
      };

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        name: json['name'] as String,
        url: json['url'] as String,
        logoUrl: json['logoUrl'] as String?,
        group: json['group'] as String?,
        tvgId: json['tvgId'] as String?,
        httpUserAgent: json['httpUserAgent'] as String?,
        httpReferrer: json['httpReferrer'] as String?,
      );

  /// Clave estable para identificar el canal (usada en favoritos).
  String get uniqueKey => '$name|$url';

  @override
  bool operator ==(Object other) =>
      other is Channel && other.uniqueKey == uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;
}
