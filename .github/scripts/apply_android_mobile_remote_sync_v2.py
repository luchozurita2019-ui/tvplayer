from pathlib import Path

REMOTE = Path('lib/services/remote_provisioning_service.dart')
PROVIDER = Path('lib/providers/iptv_provider.dart')

remote = REMOTE.read_text()
provider = PROVIDER.read_text()

# --- remote_provisioning_service.dart ---------------------------------------
if "package:crypto/crypto.dart" not in remote:
    remote = remote.replace(
        "import 'package:flutter/foundation.dart';",
        "import 'package:crypto/crypto.dart';\nimport 'package:flutter/foundation.dart';",
        1,
    )

if 'class RemoteProvisionedService' not in remote:
    marker = 'class RemoteProvisioningService {'
    insert = r'''class RemoteProvisionedService {
  final String id;
  final String name;
  final String type;
  final String? url;
  final String? server;
  final String? username;
  final String? password;
  final DateTime? expiresAt;

  const RemoteProvisionedService({
    required this.id,
    required this.name,
    required this.type,
    this.url,
    this.server,
    this.username,
    this.password,
    this.expiresAt,
  });

  factory RemoteProvisionedService.fromJson(Map<String, dynamic> json) {
    final rawExpires = json['expires_at']?.toString();
    return RemoteProvisionedService(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'TV FULL',
      type: json['type']?.toString().toLowerCase() ?? '',
      url: json['url']?.toString(),
      server: json['server']?.toString(),
      username: json['username']?.toString(),
      password: json['password']?.toString(),
      expiresAt: rawExpires == null || rawExpires.isEmpty
          ? null
          : DateTime.tryParse(rawExpires),
    );
  }

  String get fingerprint {
    final payload = jsonEncode(<String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'url': url,
      'server': server,
      'username': username,
      'password': password,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }
}

class RemoteProvisioningConfiguration {
  final String deviceCode;
  final List<RemoteProvisionedService> services;
  final DateTime? syncedAt;

  const RemoteProvisioningConfiguration({
    required this.deviceCode,
    required this.services,
    this.syncedAt,
  });
}

'''
    if marker not in remote:
        raise SystemExit('RemoteProvisioningService marker not found')
    remote = remote.replace(marker, insert + marker, 1)

if '_fingerprintsKey' not in remote:
    remote = remote.replace(
        "  static const _deviceSecretKey = 'tv_full_mobile_device_secret_v1';",
        "  static const _deviceSecretKey = 'tv_full_mobile_device_secret_v1';\n"
        "  static const _fingerprintsKey = 'tv_full_mobile_service_fingerprints_v1';",
        1,
    )

remote = remote.replace(
    "'app_version': '1.0.0+1-android-mobile-payment-status-v1'",
    "'app_version': '1.0.0+2-android-mobile-panel-sync-v2'",
)

start = remote.find('  Future<void> verifyAccess(')
if start == -1:
    raise SystemExit('verifyAccess method not found')
class_end = remote.rfind('\n}')
if class_end == -1 or class_end <= start:
    raise SystemExit('RemoteProvisioningService class end not found')

remote_methods = r'''  Future<RemoteProvisioningConfiguration> fetchConfiguration(
    RemoteDeviceCredentials credentials,
  ) async {
    final response = await http
        .get(
          Uri.parse('$_functionsBase/tvf-device-config'),
          headers: {
            'Accept': 'application/json',
            'x-tvfull-device-code': credentials.code,
            'x-tvfull-device-secret': credentials.secret,
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 403) {
      String reason = 'device_disabled';
      String title = 'Acceso suspendido';
      String message =
          'Este dispositivo fue desactivado desde el panel TV FULL.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final data = Map<String, dynamic>.from(decoded);
          final serverReason = data['error']?.toString().trim() ?? '';
          final serverTitle = data['title']?.toString().trim() ?? '';
          final serverMessage = data['message']?.toString().trim() ?? '';
          if (serverReason.isNotEmpty) reason = serverReason;
          if (serverTitle.isNotEmpty) title = serverTitle;
          if (serverMessage.isNotEmpty) message = serverMessage;
        }
      } catch (_) {
        // Conserva el mensaje genérico si el servidor no devolvió JSON válido.
      }
      throw RemoteDeviceAccessBlockedException(
        reason: reason,
        title: title,
        message: message,
      );
    }

    if (response.statusCode == 401) {
      throw const RemoteDeviceCredentialsInvalidException();
    }

    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo sincronizar con TV FULL (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception(
        'El servidor de TV FULL devolvió una configuración inválida.',
      );
    }

    final data = Map<String, dynamic>.from(decoded);
    final rawDevice = data['device'];
    final device = rawDevice is Map
        ? Map<String, dynamic>.from(rawDevice)
        : const <String, dynamic>{};

    final rawServices = data['services'];
    final services = <RemoteProvisionedService>[];
    if (rawServices is List) {
      for (final item in rawServices) {
        if (item is! Map) continue;
        final service = RemoteProvisionedService.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (service.id.isEmpty) continue;
        if (service.type != 'm3u' && service.type != 'xtream') continue;
        services.add(service);
      }
    }

    return RemoteProvisioningConfiguration(
      deviceCode: device['code']?.toString() ?? credentials.code,
      services: services,
      syncedAt: DateTime.tryParse(data['synced_at']?.toString() ?? ''),
    );
  }

  Future<void> verifyAccess(RemoteDeviceCredentials credentials) async {
    await fetchConfiguration(credentials);
  }

  Future<Map<String, String>> loadFingerprints() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_fingerprintsKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> saveFingerprints(Map<String, String> fingerprints) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fingerprintsKey, jsonEncode(fingerprints));
  }
'''
remote = remote[:start] + remote_methods + remote[class_end:]
REMOTE.write_text(remote)

# --- iptv_provider.dart ------------------------------------------------------
if "../services/remote_provisioning_service.dart" not in provider:
    provider = provider.replace(
        "import '../services/playback_settings_service.dart';",
        "import '../services/playback_settings_service.dart';\n"
        "import '../services/remote_provisioning_service.dart';",
        1,
    )

if '_remoteProvisioning = RemoteProvisioningService()' not in provider:
    provider = provider.replace(
        "  final PlaybackSettingsService _playbackSettingsService =\n"
        "      PlaybackSettingsService();",
        "  final PlaybackSettingsService _playbackSettingsService =\n"
        "      PlaybackSettingsService();\n"
        "  final RemoteProvisioningService _remoteProvisioning =\n"
        "      RemoteProvisioningService();\n\n"
        "  static const _remotePlaylistPrefix = 'tvf_remote_';",
        1,
    )

if 'String? _remoteDeviceCode;' not in provider:
    provider = provider.replace(
        "  String? _error;",
        "  String? _error;\n"
        "  String? _remoteDeviceCode;\n"
        "  bool _remoteSyncing = false;\n"
        "  String? _remoteSyncError;\n"
        "  DateTime? _remoteLastSyncedAt;",
        1,
    )

if 'bool get remoteProvisioningSupported' not in provider:
    provider = provider.replace(
        "  String? get error => _error;",
        "  String? get error => _error;\n"
        "  bool get remoteProvisioningSupported => _remoteProvisioning.isSupported;\n"
        "  String? get remoteDeviceCode => _remoteDeviceCode;\n"
        "  bool get remoteSyncing => _remoteSyncing;\n"
        "  String? get remoteSyncError => _remoteSyncError;\n"
        "  DateTime? get remoteLastSyncedAt => _remoteLastSyncedAt;",
        1,
    )

init_old = """    _playbackSettings = results[2] as PlaybackSettings;\n    notifyListeners();\n  }\n\n  Playlist? playlistById"""
init_new = """    _playbackSettings = results[2] as PlaybackSettings;\n    notifyListeners();\n\n    // Igual que en macOS: al abrir la app se descargan los servicios\n    // asignados a este dispositivo desde el panel TV FULL.\n    if (_remoteProvisioning.isSupported) {\n      await syncRemoteServices();\n    }\n  }\n\n  Playlist? playlistById"""
if 'await syncRemoteServices();' not in provider:
    if init_old not in provider:
        raise SystemExit('IptvProvider init marker not found')
    provider = provider.replace(init_old, init_new, 1)

if 'Future<void> syncRemoteServices()' not in provider:
    marker = '  Future<void> renamePlaylist('
    sync_block = r'''  Future<void> syncRemoteServices() async {
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

      // Si desde el panel se desasigna una lista, también se elimina la copia
      // remota local. Las listas agregadas manualmente por el usuario no se tocan.
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
          _remoteSyncError ??= 'No se pudo actualizar ${service.name}: $error';
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
      _remoteSyncError = error.toString();
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

      // Misma detección que la app de macOS: aunque el panel lo entregue como
      // M3U, primero probamos player_api.php. Si valida, es Xtream real.
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

'''
    if marker not in provider:
        raise SystemExit('renamePlaylist marker not found')
    provider = provider.replace(marker, sync_block + marker, 1)

PROVIDER.write_text(provider)

print('Android mobile remote sync v2 applied successfully')
