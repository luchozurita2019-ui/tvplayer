import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../services/m3u_parser.dart';
import '../services/playback_settings_service.dart';
import '../services/remote_provisioning_service.dart';
import '../services/storage_service.dart';
import '../services/tv_local_store.dart';

class IptvProvider extends ChangeNotifier {
  final StorageService _legacyStorage = StorageService();
  final TvLocalStore _localStore = TvLocalStore.instance;
  final PlaybackSettingsService _playbackSettingsService =
      PlaybackSettingsService();
  final RemoteProvisioningService _remoteProvisioning =
      RemoteProvisioningService();

  static const _remotePlaylistPrefix = 'tvf_remote_';

  List<Playlist> _playlists = const [];
  List<Channel> _favorites = const [];
  PlaybackSettings _playbackSettings = PlaybackSettings.balanced;
  String _searchQuery = '';
  bool _loading = false;
  bool _initialized = false;
  String? _error;
  String? _selectedPlaylistId;
  String? _remoteDeviceCode;
  bool _remoteSyncing = false;
  String? _remoteSyncError;
  DateTime? _remoteLastSyncedAt;

  List<Playlist> get playlists => _playlists;
  List<Channel> get favorites => _favorites;
  PlaybackSettings get playbackSettings => _playbackSettings;
  String get searchQuery => _searchQuery;
  bool get loading => _loading;
  bool get initialized => _initialized;
  String? get error => _error;
  bool get remoteProvisioningSupported => _remoteProvisioning.isSupported;
  String? get remoteDeviceCode => _remoteDeviceCode;
  bool get remoteSyncing => _remoteSyncing;
  String? get remoteSyncError => _remoteSyncError;
  DateTime? get remoteLastSyncedAt => _remoteLastSyncedAt;
  String? get selectedPlaylistId => _selectedPlaylistId;
  bool get hasMultiplePlaylists => _playlists.length > 1;

  Playlist? get selectedPlaylist {
    if (_playlists.isEmpty) return null;
    final id = _selectedPlaylistId;
    if (id != null) {
      for (final item in _playlists) {
        if (item.id == id) return item;
      }
    }
    return _playlists.first;
  }

  Future<void> init() async {
    if (_initialized) return;
    final results = await Future.wait([
      _localStore.loadServices(),
      _legacyStorage.loadFavorites(),
      _playbackSettingsService.load(),
      _localStore.loadSelectedServiceId(),
    ]);
    _playlists = results[0] as List<Playlist>;
    _favorites = results[1] as List<Channel>;
    _playbackSettings = results[2] as PlaybackSettings;
    _selectedPlaylistId = results[3] as String?;

    // Migración única desde la persistencia histórica. Sólo se copian las
    // definiciones de servicios; los catálogos grandes dejan SharedPreferences.
    if (_playlists.isEmpty) {
      try {
        final legacy = await _legacyStorage.loadPlaylists();
        if (legacy.isNotEmpty) {
          _playlists = legacy
              .map((item) => item.copyWith(channels: const <Channel>[]))
              .toList(growable: false);
          await _localStore.saveServices(_playlists);
        }
      } catch (_) {}
    }

    _normalizeSelection();
    _initialized = true;
    notifyListeners();

    if (_remoteProvisioning.isSupported) {
      unawaited(syncRemoteServices());
    }
  }

  Playlist? playlistById(String playlistId) {
    for (final item in _playlists) {
      if (item.id == playlistId) return item;
    }
    return null;
  }

  Future<void> selectPlaylist(String playlistId) async {
    if (!_playlists.any((item) => item.id == playlistId)) return;
    if (_selectedPlaylistId == playlistId) return;
    _selectedPlaylistId = playlistId;
    await _localStore.saveSelectedServiceId(playlistId);
    notifyListeners();
  }

  Future<void> updatePlaybackSettings(PlaybackSettings settings) async {
    _playbackSettings = settings;
    await _playbackSettingsService.save(settings);
    notifyListeners();
  }

  Future<void> syncRemoteServices() async {
    if (!_remoteProvisioning.isSupported || _remoteSyncing) return;
    _remoteSyncing = true;
    _remoteSyncError = null;
    notifyListeners();

    try {
      var credentials = await _remoteProvisioning.ensureRegistered();
      _remoteDeviceCode = credentials.code;
      RemoteProvisioningConfiguration configuration;
      try {
        configuration = await _remoteProvisioning.fetchConfiguration(
          credentials,
        );
      } on RemoteDeviceCredentialsInvalidException {
        await _remoteProvisioning.clearCredentials();
        credentials = await _remoteProvisioning.ensureRegistered();
        _remoteDeviceCode = credentials.code;
        configuration = await _remoteProvisioning.fetchConfiguration(
          credentials,
        );
      }

      _remoteDeviceCode = configuration.deviceCode;
      final previous = {for (final item in _playlists) item.id: item};
      final nextRemote = <Playlist>[];

      // El orden del backend es el display_order del proveedor/panel. No se
      // ordena alfabéticamente ni se reconstruye el catálogo durante el vínculo.
      for (final service in configuration.services) {
        final id = '$_remotePlaylistPrefix${service.id}';
        final old = previous[id];
        final next = _playlistFromRemote(service, id, old);
        if (old != null &&
            (old.source != next.source || old.sourceType != next.sourceType)) {
          await _localStore.clearServiceCatalogs(id);
        }
        nextRemote.add(next);
      }

      final localOnly = _playlists
          .where((item) => !item.id.startsWith(_remotePlaylistPrefix))
          .toList(growable: false);
      _playlists = [...nextRemote, ...localOnly];
      _normalizeSelection();
      await _localStore.saveServices(_playlists);
      await _localStore.saveSelectedServiceId(_selectedPlaylistId);
      _remoteLastSyncedAt = configuration.syncedAt ?? DateTime.now();
      _error = null;
    } catch (error) {
      _remoteSyncError = _friendlyConnectionError(error);
    } finally {
      _remoteSyncing = false;
      notifyListeners();
    }
  }

  Playlist _playlistFromRemote(
    RemoteProvisionedService service,
    String id,
    Playlist? previous,
  ) {
    final name =
        service.name.trim().isEmpty ? 'TV FULL PRO' : service.name.trim();
    if (service.type == 'm3u') {
      final url = service.url?.trim() ?? '';
      if (url.isEmpty) throw Exception('$name no tiene URL M3U.');
      return Playlist(
        id: id,
        name: name,
        source: url,
        isRemote: true,
        channels: const [],
        lastUpdated: previous?.lastUpdated ?? DateTime.now(),
        sourceType: PlaylistSourceType.m3u,
      );
    }

    final server = service.server?.trim() ?? '';
    final username = service.username?.trim() ?? '';
    final password = service.password ?? '';
    if (server.isEmpty || username.isEmpty || password.isEmpty) {
      throw Exception('$name tiene credenciales Xtream incompletas.');
    }
    return Playlist(
      id: id,
      name: name,
      source: _buildXtreamPlaylistUrl(server, username, password),
      isRemote: true,
      channels: const [],
      lastUpdated: previous?.lastUpdated ?? DateTime.now(),
      sourceType: PlaylistSourceType.xtream,
    );
  }

  String _buildXtreamPlaylistUrl(
    String rawServer,
    String username,
    String password,
  ) {
    var value = rawServer.trim();
    if (!value.contains('://')) value = 'http://$value';
    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.host.isEmpty) {
      throw const FormatException('Servidor Xtream inválido.');
    }
    var path = parsed.path;
    final lower = path.toLowerCase();
    for (final suffix in ['/player_api.php', '/get.php']) {
      if (lower.endsWith(suffix)) {
        path = path.substring(0, path.length - suffix.length);
        break;
      }
    }
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    return parsed
        .replace(
          path: '$path/get.php',
          queryParameters: {
            'username': username,
            'password': password,
            'type': 'm3u_plus',
            'output': 'ts',
          },
          fragment: '',
        )
        .toString();
  }

  void _normalizeSelection() {
    if (_playlists.isEmpty) {
      _selectedPlaylistId = null;
      return;
    }
    if (_selectedPlaylistId == null ||
        !_playlists.any((item) => item.id == _selectedPlaylistId)) {
      _selectedPlaylistId = _playlists.first.id;
    }
  }

  Future<void> addPlaylistFromUrl(String name, String url) async {
    final clean = url.trim();
    if (clean.isEmpty) return;
    final playlist = Playlist(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Lista M3U' : name.trim(),
      source: clean,
      isRemote: true,
      channels: const [],
      lastUpdated: DateTime.now(),
      sourceType: PlaylistSourceType.m3u,
    );
    _playlists = [..._playlists, playlist];
    _selectedPlaylistId ??= playlist.id;
    await _localStore.saveServices(_playlists);
    await _localStore.saveSelectedServiceId(_selectedPlaylistId);
    notifyListeners();
  }

  Future<void> addXtreamSource({
    required String name,
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final playlist = Playlist(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Xtream Codes' : name.trim(),
      source: _buildXtreamPlaylistUrl(serverUrl, username, password),
      isRemote: true,
      channels: const [],
      lastUpdated: DateTime.now(),
      sourceType: PlaylistSourceType.xtream,
    );
    _playlists = [..._playlists, playlist];
    _selectedPlaylistId ??= playlist.id;
    await _localStore.saveServices(_playlists);
    await _localStore.saveSelectedServiceId(_selectedPlaylistId);
    notifyListeners();
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
        id: 'file-${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim().isEmpty ? 'Lista local' : name.trim(),
        source: path,
        isRemote: false,
        channels: channels,
        lastUpdated: DateTime.now(),
        sourceType: PlaylistSourceType.m3u,
      );
      _playlists = [..._playlists, playlist];
      _selectedPlaylistId ??= playlist.id;
      await _localStore.saveServices(_playlists);
      await _localStore.saveSelectedServiceId(_selectedPlaylistId);
      _error = null;
    } catch (error) {
      _error = 'No se pudo leer el archivo: $error';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    final index = _playlists.indexWhere((item) => item.id == playlistId);
    if (index < 0) return;
    final current = _playlists[index];
    final updated = current.copyWith(
      name: name.trim().isEmpty ? current.name : name.trim(),
    );
    final next = List<Playlist>.from(_playlists)..[index] = updated;
    _playlists = next;
    await _localStore.saveServices(_playlists);
    notifyListeners();
  }

  Future<void> updatePlaylistFromUrl({
    required String playlistId,
    required String name,
    required String url,
  }) async {
    final index = _playlists.indexWhere((item) => item.id == playlistId);
    if (index < 0) return;
    final current = _playlists[index];
    final updated = current.copyWith(
      name: name.trim().isEmpty ? current.name : name.trim(),
      source: url.trim(),
      sourceType: PlaylistSourceType.m3u,
      channels: const [],
      lastUpdated: DateTime.now(),
    );
    final next = List<Playlist>.from(_playlists)..[index] = updated;
    _playlists = next;
    await _localStore.clearServiceCatalogs(playlistId);
    await _localStore.saveServices(_playlists);
    notifyListeners();
  }

  Future<void> updateXtreamSource({
    required String playlistId,
    required String name,
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final index = _playlists.indexWhere((item) => item.id == playlistId);
    if (index < 0) return;
    final current = _playlists[index];
    final updated = current.copyWith(
      name: name.trim().isEmpty ? current.name : name.trim(),
      source: _buildXtreamPlaylistUrl(serverUrl, username, password),
      sourceType: PlaylistSourceType.xtream,
      channels: const [],
      lastUpdated: DateTime.now(),
    );
    final next = List<Playlist>.from(_playlists)..[index] = updated;
    _playlists = next;
    await _localStore.clearServiceCatalogs(playlistId);
    await _localStore.saveServices(_playlists);
    notifyListeners();
  }

  Future<void> refreshPlaylist(String playlistId) async {
    await _localStore.clearServiceCatalogs(playlistId);
    final index = _playlists.indexWhere((item) => item.id == playlistId);
    if (index >= 0) {
      final next = List<Playlist>.from(_playlists);
      next[index] = next[index].copyWith(lastUpdated: DateTime.now());
      _playlists = next;
      await _localStore.saveServices(_playlists);
      notifyListeners();
    }
  }

  Future<void> removePlaylist(String playlistId) async {
    _playlists = _playlists.where((item) => item.id != playlistId).toList();
    await _localStore.clearServiceCatalogs(playlistId);
    _normalizeSelection();
    await _localStore.saveServices(_playlists);
    await _localStore.saveSelectedServiceId(_selectedPlaylistId);
    notifyListeners();
  }

  Future<void> toggleFavorite(Channel channel) async {
    if (_favorites.contains(channel)) {
      _favorites = _favorites.where((item) => item != channel).toList();
    } else {
      _favorites = [..._favorites, channel];
    }
    await _legacyStorage.saveFavorites(_favorites);
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
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return channels;
    return channels
        .where(
          (item) =>
              item.name.toLowerCase().contains(query) ||
              (item.group?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
  }

  String _friendlyConnectionError(Object error) {
    var message = error.toString().replaceFirst('Exception: ', '');
    message = message.replaceAllMapped(
      RegExp(r'([?&](?:username|password)=)([^&#\s]+)', caseSensitive: false),
      (match) => '${match.group(1)}••••',
    );
    return message;
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}
