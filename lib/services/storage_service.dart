import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/playlist.dart';

/// Persiste listas y favoritos en disco (SharedPreferences, JSON).
/// Suficiente para el volumen de datos de una app IPTV personal;
/// si en el futuro se necesita más escala, migrar a Hive/SQLite
/// reusando la misma interfaz.
class StorageService {
  static const _playlistsKey = 'playlists_v1';
  static const _favoritesKey = 'favorites_v1';

  Future<List<Playlist>> loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((p) => Playlist.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(playlists.map((p) => p.toJson()).toList());
    await prefs.setString(_playlistsKey, raw);
  }

  Future<List<Channel>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoritesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((c) => Channel.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveFavorites(List<Channel> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(favorites.map((c) => c.toJson()).toList());
    await prefs.setString(_favoritesKey, raw);
  }
}
