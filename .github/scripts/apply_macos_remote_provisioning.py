from pathlib import Path

path = Path('lib/providers/iptv_provider.dart')
text = path.read_text(encoding='utf-8')

import_marker = "import '../services/playback_settings_service.dart';\n"
remote_import = "import '../services/remote_provisioning_service.dart';\n"
if remote_import not in text:
    if import_marker not in text:
        raise SystemExit('playback settings import marker not found')
    text = text.replace(import_marker, import_marker + remote_import, 1)

service_marker = "  final PlaybackSettingsService _playbackSettingsService =\n      PlaybackSettingsService();\n"
service_replacement = service_marker + "  final RemoteProvisioningService _remoteProvisioning =\n      RemoteProvisioningService();\n\n  static const _remotePlaylistPrefix = 'tvf_remote_';\n"
if "final RemoteProvisioningService _remoteProvisioning" not in text:
    if service_marker not in text:
        raise SystemExit('provider service marker not found')
    text = text.replace(service_marker, service_replacement, 1)

field_marker = "  bool _loading = false;\n  String? _error;\n"
field_replacement = "  bool _loading = false;\n  String? _error;\n  String? _remoteDeviceCode;\n  bool _remoteSyncing = false;\n  String? _remoteSyncError;\n  DateTime? _remoteLastSyncedAt;\n"
if "String? _remoteDeviceCode;" not in text:
    if field_marker not in text:
        raise SystemExit('provider field marker not found')
    text = text.replace(field_marker, field_replacement, 1)

getter_marker = "  bool get loading => _loading;\n  String? get error => _error;\n"
getter_replacement = "  bool get loading => _loading;\n  String? get error => _error;\n  bool get remoteProvisioningSupported => _remoteProvisioning.isSupported;\n  String? get remoteDeviceCode => _remoteDeviceCode;\n  bool get remoteSyncing => _remoteSyncing;\n  String? get remoteSyncError => _remoteSyncError;\n  DateTime? get remoteLastSyncedAt => _remoteLastSyncedAt;\n"
if "bool get remoteProvisioningSupported" not in text:
    if getter_marker not in text:
        raise SystemExit('provider getter marker not found')
    text = text.replace(getter_marker, getter_replacement, 1)

old_init = """  Future<void> init() async {
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
"""
new_init = """  Future<void> init() async {
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
"""
if "Primera prueba de aprovisionamiento remoto" not in text:
    if old_init not in text:
        raise SystemExit('provider init marker not found')
    text = text.replace(old_init, new_init, 1)

insert_marker = "  Future<void> renamePlaylist(String playlistId, String name) async {\n"
remote_methods = r'''  Future<void> syncRemoteServices() async {
    if (!_remoteProvisioning.isSupported || _remoteSyncing) return;

    _remoteSyncing = true;
    _remoteSyncError = null;
    notifyListeners();

    try {
      final credentials = await _remoteProvisioning.ensureRegistered();
      _remoteDeviceCode = credentials.code;
      notifyListeners();

      final configuration =
          await _remoteProvisioning.fetchConfiguration(credentials);
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
        throw Exception('El servicio remoto no devolvió contenido reproducible.');
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
        throw Exception('El servicio remoto no devolvió contenido reproducible.');
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

'''
if "Future<void> syncRemoteServices() async" not in text:
    if insert_marker not in text:
        raise SystemExit('renamePlaylist marker not found')
    text = text.replace(insert_marker, remote_methods + insert_marker, 1)

path.write_text(text, encoding='utf-8')
print('macOS remote provisioning provider patch applied')
