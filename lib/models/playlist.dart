import 'channel.dart';

/// Representa una lista M3U completa: puede venir de una URL remota
/// o de un archivo local. El usuario puede tener varias.
class Playlist {
  final String id; // uuid simple (timestamp)
  final String name;
  final String source; // URL o path local
  final bool isRemote;
  final List<Channel> channels;
  final DateTime lastUpdated;

  const Playlist({
    required this.id,
    required this.name,
    required this.source,
    required this.isRemote,
    required this.channels,
    required this.lastUpdated,
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
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        source: json['source'] as String,
        isRemote: json['isRemote'] as bool,
        channels: (json['channels'] as List)
            .map((c) => Channel.fromJson(c as Map<String, dynamic>))
            .toList(),
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      );

  Playlist copyWith({
    String? name,
    List<Channel>? channels,
    DateTime? lastUpdated,
  }) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        source: source,
        isRemote: isRemote,
        channels: channels ?? this.channels,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
}
