import 'channel.dart';
import 'playlist_source_type.dart';

/// Representa una fuente IPTV cargada en TV FULL.
///
/// Históricamente este modelo sólo representaba M3U. Mantiene el mismo formato
/// de almacenamiento para no romper las listas existentes, pero ahora también
/// identifica si la fuente nació desde M3U, Xtream Codes o Portal Stalker.
class Playlist {
  final String id; // uuid simple (timestamp)
  final String name;
  final String source; // URL/path de origen o endpoint reproducible
  final bool isRemote;
  final List<Channel> channels;
  final DateTime lastUpdated;
  final PlaylistSourceType sourceType;

  const Playlist({
    required this.id,
    required this.name,
    required this.source,
    required this.isRemote,
    required this.channels,
    required this.lastUpdated,
    this.sourceType = PlaylistSourceType.m3u,
  });

  /// Todas las categorías presentes en la lista, ordenadas.
  List<String> get groups {
    final set = <String>{};
    for (final c in channels) {
      if (c.group != null && c.group!.trim().isNotEmpty) {
        set.add(c.group!.trim());
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'source': source,
        'isRemote': isRemote,
        'channels': channels.map((c) => c.toJson()).toList(),
        'lastUpdated': lastUpdated.toIso8601String(),
        'sourceType': sourceType.name,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawSourceType = json['sourceType'] as String?;
    final sourceType = PlaylistSourceType.values.firstWhere(
      (value) => value.name == rawSourceType,
      orElse: () => PlaylistSourceType.m3u,
    );

    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      source: json['source'] as String,
      isRemote: json['isRemote'] as bool,
      channels: (json['channels'] as List)
          .map((c) => Channel.fromJson(c as Map<String, dynamic>))
          .toList(),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      sourceType: sourceType,
    );
  }

  Playlist copyWith({
    String? name,
    String? source,
    bool? isRemote,
    List<Channel>? channels,
    DateTime? lastUpdated,
    PlaylistSourceType? sourceType,
  }) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        source: source ?? this.source,
        isRemote: isRemote ?? this.isRemote,
        channels: channels ?? this.channels,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        sourceType: sourceType ?? this.sourceType,
      );
}
