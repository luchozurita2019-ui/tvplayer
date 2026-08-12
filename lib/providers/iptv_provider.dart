import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../services/content_classifier.dart';
import '../services/m3u_fetcher.dart';
import '../services/m3u_parser.dart';
import '../services/playback_settings_service.dart';
import '../services/storage_service.dart';
import '../services/xtream_service.dart';

class IptvProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final PlaybackSettingsService _playbackSettingsService =
      PlaybackSettingsService();

  List<Playlist> _playlists = [];
  List<Channel> _favorites = [];
  PlaybackSettings _playbackSettings = PlaybackSettings.balanced;
  String _searchQuery = '';
  bool _loading = false;
  String? _error;

  List<Playlist> get playlists => _playlists;
  List<Channel> get favorites => _favorites;
  PlaybackSettings get playbackSettings => _playbackSettings;
  String get searchQuery => _searchQuery;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> init() async {
    final results = await Future.wait([
      _storage.loadPlaylists(),
      _storage.loadFavorites(),
      _playbackSettingsService.load(),
    ]);
    _playlists = results[0] as List<Playlist>;
    _favorites = results[1] as List<Channel>;
    _playbackSettings = results[2] as PlaybackSettings;
    notifyListeners();
  }

  Playlist? playlistById(String playlistId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    return index == -1 ? null : _playlists[index];
  }

  Future<void> updatePlaybackSettings(PlaybackSettings settings) async {
    _playbackSettings = settings;
    await _playbackSettingsService.save(settings);
    notifyListeners();
  }

  Future<void> addPlaylistFromUrl(String name, String url) async {
    _setLoading(true);
    try {
      final xtream = await XtreamService.tryConnectFromPlaylistUrl(url);
      final List<Channel> channels;
      final PlaylistSourceType detectedType;

      if (xtream != null) {
        // Muchos proveedores entregan una URL get.php aunque detrás exista una
        // cuenta Xtream completa. Si player_api.php valida, usamos la API nativa
        // porque conserva stream_id/server_info y es más compatible que tratar
        // el enlace únicamente como texto M3U.
        channels = await _loadXtreamChannels(xtream);
        detectedType = PlaylistSourceType.xtream;
      } else {
        final content = await M3uFetcher.fetch(url);
        channels = await compute(parseM3uInBackground, content);
        detectedType = PlaylistSourceType.m3u;
      }

      if (channels.isEmpty) {
        throw Exception('El proveedor no devolvió canales reproducibles.');
      }
      final playlist = Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.trim().isEmpty ? 'Lista sin nombre' : name.trim(),
        // Conservamos exactamente el enlace entregado por el proveedor. El tipo
        // detectado se guarda aparte y controla cómo se actualiza después.
        source: url,
        isRemote: true,
        channels: channels,
        lastUpdated: DateTime.now(),
        sourceType: detectedType,
      );
      _playlists = [..._playlists, playlist];
      await _storage.savePlaylists(_playlists);
      _error = null;
    } catch (e) {
      _error = _friendlyConnectionError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addXtreamSource({
    required String name,
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    _setLoading(true);
    try {
      final connection = await XtreamService.connect(
        serverUrl: serverUrl,
        username: username,
        password: password,
      );
      final channels = await _loadXtreamChannels(connection);
      if (channels.isEmpty) {
        throw Exception(
          'Xtream autenticó correctamente, pero no devolvió contenido reproducible.',
        );
      }

      final playlist = Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.trim().isEmpty ? 'Xtream Codes' : name.trim(),
        // Conservamos get.php como referencia persistente para que listas ya
        // guardadas, Editar y Actualizar sigan siendo compatibles.
        source: connection.playlistUrl,
        isRemote: true,
        channels: channels,
        lastUpdated: DateTime.now(),
        sourceType: PlaylistSourceType.xtream,
      );

      _playlists = [..._playlists, playlist];
      await _storage.savePlaylists(_playlists);
      _error = null;
    } catch (e) {
      _error = _friendlyConnectionError(e);
    } finally {
      _setLoading(false);
    }
  }

  /// TV en vivo y VOD se obtienen directamente de player_api.php para no
  /// depender de la URL serializada por get.php. Series y radios continúan
  /// viniendo de M3U como complemento hasta que tengan carga Xtream perezosa.
  Future<List<Channel>> _loadXtreamChannels(
    XtreamConnectionResult connection,
  ) async {
    XtreamNativeCatalog nativeCatalog;
    try {
      nativeCatalog = await XtreamService.fetchNativeCatalog(connection);
    } catch (_) {
      nativeCatalog = const XtreamNativeCatalog(live: [], vod: []);
    }

    List<Channel> m3uChannels = const [];
    try {
      final content = await M3uFetcher.fetch(connection.playlistUrl);
      m3uChannels = await compute(parseM3uInBackground, content);
    } catch (_) {
      // Si el panel permite API nativa pero bloquea get.php, todavía podemos
      // ofrecer TV/VOD. Sólo fallamos si tampoco llegó catálogo nativo.
    }

    final nativeBuckets = ContentClassifier.partition([
      ...nativeCatalog.live,
      ...nativeCatalog.vod,
    ]);
    final m3uBuckets = ContentClassifier.partition(m3uChannels);

    final merged = <Channel>[
      ...(nativeBuckets.live.isNotEmpty ? nativeBuckets.live : m3uBuckets.live),
      ...(nativeBuckets.movies.isNotEmpty
          ? nativeBuckets.movies
          : m3uBuckets.movies),
      ...m3uBuckets.series,
      ...(nativeBuckets.radios.isNotEmpty
          ? nativeBuckets.radios
          : m3uBuckets.radios),
    ];

    // Evita duplicados en paneles que publican una misma entrada en más de una
    // sección. uniqueKey incluye URL, por lo que variantes reales se conservan.
    final unique = <String, Channel>{};
    for (final channel in merged) {
      unique.putIfAbsent(channel.uniqueKey, () => channel);
    }
    return unique.values.toList(growable: false);
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    final playlist = _playlists[index];
    final cleanName = name.trim().isEmpty ? playlist.name : name.trim();
    final updated = playlist.copyWith(name: cleanName);
    _playlists = [
      ..._playlists.take(index),
      updated,
      ..._playlists.skip(index + 1),
    ];
    await _storage.savePlaylists(_playlists);
    _error = null;
    notifyListeners();
  }

  Future<void> updatePlaylistFromUrl({
    required String playlistId,
    required String name,
    required String url,
  }) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    _error = null;
    _setLoading(true);
    try {
      final xtream = await XtreamService.tryConnectFromPlaylistUrl(url);
      final List<Channel> channels;
      final PlaylistSourceType detectedType;
      if (xtream != null) {
        channels = await _loadXtreamChannels(xtream);
        detectedType = PlaylistSourceType.xtream;
      } else {
        final content = await M3uFetcher.fetch(url);
        channels = await compute(parseM3uInBackground, content);
        detectedType = PlaylistSourceType.m3u;
      }
      if (channels.isEmpty) {
        throw Exception('El proveedor no devolvió contenido reproducible.');
      }
      final current = _playlists[index];
      final updated = current.copyWith(
        name: name.trim().isEmpty ? current.name : name.trim(),
        source: url,
        isRemote: true,
        channels: channels,
        lastUpdated: DateTime.now(),
        sourceType: detectedType,
      );
      _playlists = [
        ..._playlists.take(index),
        updated,
        ..._playlists.skip(index + 1),
      ];
      await _storage.savePlaylists(_playlists);
      _error = null;
    } catch (e) {
      _error = _friendlyConnectionError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateXtreamSource({
    required String playlistId,
    required String name,
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    _error = null;
    _setLoading(true);
    try {
      final connection = await XtreamService.connect(
        serverUrl: serverUrl,
        username: username,
        password: password,
      );
      final channels = await _loadXtreamChannels(connection);
      if (channels.isEmpty) {
        throw Exception(
          'Xtream autenticó correctamente, pero no devolvió contenido reproducible.',
        );
      }
      final current = _playlists[index];
      final updated = current.copyWith(
        name: name.trim().isEmpty ? current.name : name.trim(),
        source: connection.playlistUrl,
        isRemote: true,
        channels: channels,
        lastUpdated: DateTime.now(),
        sourceType: PlaylistSourceType.xtream,
      );
      _playlists = [
        ..._playlists.take(index),
        updated,
        ..._playlists.skip(index + 1),
      ];
      await _storage.savePlaylists(_playlists);
      _error = null;
    } catch (e) {
      _error = _friendlyConnectionError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addPlaylistFromContent(
    String name,
    String path,
    String content,
  ) async {
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
        sourceType: PlaylistSourceType.m3u,
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

  Future<void> refreshPlaylist(String playlistId) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    final playlist = _playlists[index];
    if (!playlist.isRemote) return;

    _setLoading(true);
    try {
      final List<Channel> channels;
      var detectedType = playlist.sourceType;
      if (playlist.sourceType == PlaylistSourceType.xtream) {
        final connection = await XtreamService.reconnectFromPlaylistUrl(
          playlist.source,
        );
        channels = await _loadXtreamChannels(connection);
      } else {
        // Las listas guardadas antes de la autodetección pueden seguir marcadas
        // como M3U aunque sean un get.php Xtream. Actualizar las migra sin borrar.
        final xtream = await XtreamService.tryConnectFromPlaylistUrl(
          playlist.source,
        );
        if (xtream != null) {
          channels = await _loadXtreamChannels(xtream);
          detectedType = PlaylistSourceType.xtream;
        } else {
          final content = await M3uFetcher.fetch(playlist.source);
          channels = await compute(parseM3uInBackground, content);
          detectedType = PlaylistSourceType.m3u;
        }
      }

      if (channels.isEmpty) {
        throw Exception('El proveedor no devolvió contenido reproducible.');
      }
      final updated = playlist.copyWith(
        channels: channels,
        lastUpdated: DateTime.now(),
        sourceType: detectedType,
      );
      _playlists = [
        ..._playlists.take(index),
        updated,
        ..._playlists.skip(index + 1),
      ];
      await _storage.savePlaylists(_playlists);
      _error = null;
    } catch (e) {
      _error = _friendlyConnectionError(e);
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

  void clearSearchQuery() {
    if (_searchQuery.isEmpty) return;
    _searchQuery = '';
    notifyListeners();
  }

  List<Channel> filterChannels(List<Channel> channels) {
    if (_searchQuery.trim().isEmpty) return channels;
    final q = _searchQuery.toLowerCase();
    return channels
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              (c.group?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  String _friendlyConnectionError(Object error) {
    var message = error.toString();
    message = message.replaceAllMapped(
      RegExp(r'([?&](?:username|password)=)([^&#\s]+)', caseSensitive: false),
      (match) => '${match.group(1)}••••',
    );

    final lower = message.toLowerCase();
    if (lower.contains('wrong_version_number')) {
      return 'El servidor rechazó la conexión segura. Revisá si este proveedor usa http:// en lugar de https://.';
    }
    if (lower.contains('connection refused')) {
      return 'No se pudo conectar con el servidor. Verificá que el host y el puerto estén disponibles.';
    }
    return message;
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}
