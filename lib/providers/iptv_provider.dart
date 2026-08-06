import 'package:flutter/foundation.dart';
import '../models/channel.dart';
import '../models/playlist.dart';
import '../services/m3u_fetcher.dart';
import '../services/m3u_parser.dart';
import '../services/storage_service.dart';

// compute() necesita una función top-level: parseM3uInBackground,
// expuesta en m3u_parser.dart, corre en un isolate separado.

class IptvProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();

  List<Playlist> _playlists = [];
  List<Channel> _favorites = [];
  String _searchQuery = '';
  bool _loading = false;
  String? _error;

  List<Playlist> get playlists => _playlists;
  List<Channel> get favorites => _favorites;
  String get searchQuery => _searchQuery;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> init() async {
    _playlists = await _storage.loadPlaylists();
    _favorites = await _storage.loadFavorites();
    notifyListeners();
  }

  /// Agrega una lista desde una URL remota.
  Future<void> addPlaylistFromUrl(String name, String url) async {
    _setLoading(true);
    try {
      final content = await M3uFetcher.fetch(url);
      final channels = await compute(parseM3uInBackground, content);
      final playlist = Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.trim().isEmpty ? 'Lista sin nombre' : name.trim(),
        source: url,
        isRemote: true,
        channels: channels,
        lastUpdated: DateTime.now(),
      );
      _playlists = [..._playlists, playlist];
      await _storage.savePlaylists(_playlists);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  /// Agrega una lista a partir de contenido M3U ya leído (archivo local).
  Future<void> addPlaylistFromContent(
      String name, String path, String content) async {
    _setLoading(true);
    try {
      final channels = await compute(parseM3uInBackground, content);
      final playlist = Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.trim().isEmpty ? 'Lista sin nombre' : name.trim(),
        source: path,
        isRemote: false,
        channels: channels,
        lastUpdated: DateTime.now(),
      );
      _playlists = [..._playlists, playlist];
      await _storage.savePlaylists(_playlists);
      _error = null;
    } catch (e) {
      _error = 'No se pudo leer el archivo: $e';
    } finally {
      _setLoading(false);
    }
  }

  /// Refresca una lista remota (vuelve a descargar y parsear).
  Future<void> refreshPlaylist(String playlistId) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    final playlist = _playlists[index];
    if (!playlist.isRemote) return;

    _setLoading(true);
    try {
      final content = await M3uFetcher.fetch(playlist.source);
      final channels = await compute(parseM3uInBackground, content);
      _playlists[index] = playlist.copyWith(
        channels: channels,
        lastUpdated: DateTime.now(),
      );
      await _storage.savePlaylists(_playlists);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> removePlaylist(String playlistId) async {
    _playlists = _playlists.where((p) => p.id != playlistId).toList();
    await _storage.savePlaylists(_playlists);
    notifyListeners();
  }

  Future<void> toggleFavorite(Channel channel) async {
    final exists = _favorites.contains(channel);
    if (exists) {
      _favorites = _favorites.where((c) => c != channel).toList();
    } else {
      _favorites = [..._favorites, channel];
    }
    await _storage.saveFavorites(_favorites);
    notifyListeners();
  }

  bool isFavorite(Channel channel) => _favorites.contains(channel);

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Filtra canales de una lista según la búsqueda actual.
  /// Búsqueda case-insensitive por nombre y por grupo.
  List<Channel> filterChannels(List<Channel> channels) {
    if (_searchQuery.trim().isEmpty) return channels;
    final q = _searchQuery.toLowerCase();
    return channels
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            (c.group?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}
