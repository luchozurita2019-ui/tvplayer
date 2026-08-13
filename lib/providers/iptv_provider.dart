import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../services/content_classifier.dart';
import '../services/m3u_fetcher.dart';
import '../services/m3u_parser.dart';
import '../services/playback_settings_service.dart';
import '../services/remote_provisioning_service.dart';
import '../services/storage_service.dart';
import '../services/xtream_service.dart';

class IptvProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final PlaybackSettingsService _playbackSettingsService =
      PlaybackSettingsService();
  final RemoteProvisioningService _remoteProvisioning =
      RemoteProvisioningService();

  static const _remotePlaylistPrefix = 'tvf_remote_';

  List<Playlist> _playlists = [];
  List<Channel> _favorites = [];
  PlaybackSettings _playbackSettings = PlaybackSettings.balanced;
  String _searchQuery = '';
  bool _loading = false;
  String? _error;
  String? _remoteDeviceCode;
  bool _remoteSyncing = false;
  String? _remoteSyncError;
  DateTime? _remoteLastSyncedAt;

  List<Playlist> get playlists => _playlists;
  List<Channel> get favorites => _favorites;
  PlaybackSettings get playbackSettings => _playbackSettings;
  String get searchQuery => _searchQuery;
  bool get loading => _loading;
  String? get error => _error;
  bool get remoteProvisioningSupported => _remoteProvisioning.isSupported;
  String? get remoteDeviceCode => _remoteDeviceCode;
  bool get remoteSyncing => _remoteSyncing;
  String? get remoteSyncError => _remoteSyncError;
  DateTime? get remoteLastSyncedAt => _remoteLastSyncedAt;

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

    // Primera prueba de aprovisionamiento remoto: sólo macOS. Android y
    // Android TV conservan exactamente su comportamiento actual.
    if (_remoteProvisioning.isSupported) {
      await syncRemoteServices();
    }
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

  Future<void> syncRemoteServices() async {
    if (!_remoteProvisioning.isSupported || _remoteSyncing) return;

    _remoteSyncing = true;
    _remoteSyncError = null;
    notifyListeners();

    try {
      var credentials = await _remoteProvisioning.ensureRegistered();
      _remoteDeviceCode = credentials.code;
      notifyListeners();

      RemoteProvisioningConfiguration configuration;
      try {
        configuration = await _remoteProvisioning.fetchConfiguration(
          credentials,
        );
      } on RemoteDeviceCredentialsInvalidException {
        // Si el administrador borró este dispositivo del panel, olvidamos
        // únicamente la identidad remota local y pedimos un código nuevo.
        // Un dispositivo marcado como INACTIVO devuelve 403 y NO entra acá,
        // por lo que sigue bloqueado hasta que el administrador lo reactive.
        await _remoteProvisioning.clearCredentials();
        credentials = await _remoteProvisioning.ensureRegistered();
        _remoteDeviceCode = credentials.code;
        notifyListeners();
        configuration = await _remoteProvisioning.fetchConfiguration(
          credentials,
        );
      }
      _remoteDeviceCode = configuration.deviceCode;

      final fingerprints = await _remoteProvisioning.loadFingerprints();
      final activeServiceIds = configuration.services.map((s) => s.id).toSet();
      final nextPlaylists = List<Playlist>.from(_playlists);
      var storageChanged = false;

      nextPlaylists.removeWhere((playlist) {
        if (!playlist.id.startsWith(_remotePlaylistPrefix)) return false;
        final serviceId = playlist.id.substring(_remotePlaylistPrefix.length);
        if (activeServiceIds.contains(serviceId)) return false;
        fingerprints.remove(serviceId);
        storageChanged = true;
        return true;
      });

      for (final service in configuration.services) {
        final localId = '$_remotePlaylistPrefix${service.id}';
        final index = nextPlaylists.indexWhere((p) => p.id == localId);
        final fingerprint = service.fingerprint;

        if (index != -1 && fingerprints[service.id] == fingerprint) {
          final current = nextPlaylists[index];
          if (current.name != service.name) {
            nextPlaylists[index] = current.copyWith(name: service.name);
            storageChanged = true;
          }
          continue;
        }

        try {
          final playlist = await _buildRemotePlaylist(service, localId);
          if (index == -1) {
            nextPlaylists.add(playlist);
          } else {
            nextPlaylists[index] = playlist;
          }
          fingerprints[service.id] = fingerprint;
          storageChanged = true;
        } catch (error) {
          _remoteSyncError ??=
              'No se pudo actualizar ${service.name}: ${_friendlyConnectionError(error)}';
        }
      }

      fingerprints.removeWhere((id, _) => !activeServiceIds.contains(id));
      if (storageChanged) {
        _playlists = nextPlaylists;
        await _storage.savePlaylists(_playlists);
      }
      await _remoteProvisioning.saveFingerprints(fingerprints);
      _remoteLastSyncedAt = configuration.syncedAt ?? DateTime.now();
    } catch (error) {
      _remoteSyncError = _friendlyConnectionError(error);
    } finally {
      _remoteSyncing = false;
      notifyListeners();
    }
  }

  Future<Playlist> _buildRemotePlaylist(
    RemoteProvisionedService service,
    String localId,
  ) async {
    if (service.type == 'm3u') {
      final url = service.url?.trim() ?? '';
      if (url.isEmpty) {
        throw Exception('El servicio remoto M3U no tiene URL.');
      }

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
        throw Exception(
          'El servicio remoto no devolvió contenido reproducible.',
        );
      }

      return Playlist(
        id: localId,
        name: service.name.trim().isEmpty ? 'TV FULL' : service.name.trim(),
        source: url,
        isRemote: true,
        channels: channels,
        lastUpdated: DateTime.now(),
        sourceType: detectedType,
      );
    }

    if (service.type == 'xtream') {
      final server = service.server?.trim() ?? '';
      final username = service.username?.trim() ?? '';
      final password = service.password ?? '';
      if (server.isEmpty || username.isEmpty || password.isEmpty) {
        throw Exception('El servicio remoto Xtream está incompleto.');
      }

      final connection = await XtreamService.connect(
        serverUrl: server,
        username: username,
        password: password,
      );
      final channels = await _loadXtreamChannels(connection);
      if (channels.isEmpty) {
        throw Exception(
          'El servicio remoto no devolvió contenido reproducible.',
        );
      }

      return Playlist(
        id: localId,
        name: service.name.trim().isEmpty ? 'TV FULL' : service.name.trim(),
        source: connection.playlistUrl,
        isRemote: true,
        channels: channels,
        lastUpdated: DateTime.now(),
        sourceType: PlaylistSourceType.xtream,
      );
    }

    throw Exception('Tipo de servicio remoto no compatible.');
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
