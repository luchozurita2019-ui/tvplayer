from pathlib import Path
import re

ROOT = Path('.')
PROVIDER = ROOT / 'lib/providers/iptv_provider.dart'
HOME = ROOT / 'lib/screens/home_screen.dart'
LIVE = ROOT / 'lib/screens/xtream_live_screen.dart'
MOVIES = ROOT / 'lib/screens/xtream_movies_screen.dart'
SERIES = ROOT / 'lib/screens/xtream_series_screen.dart'
PLAYER = ROOT / 'lib/screens/player_screen.dart'
MAIN = ROOT / 'lib/main.dart'
CHANNELS = ROOT / 'lib/screens/channel_list_screen.dart'
LIVE_FAST = ROOT / 'lib/services/xtream_live_fast_service.dart'
MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Marcador no encontrado V13: {label}')
    return text.replace(old, new, 1)


def patch_remote_linking():
    text = PROVIDER.read_text()

    marker = '''  Future<Playlist> _buildRemotePlaylist(\n'''
    helpers = r'''  Playlist? _remoteXtreamStub(
    RemoteProvisionedService service,
    String localId,
  ) {
    String? source;

    if (service.type == 'xtream') {
      final server = service.server?.trim() ?? '';
      final username = service.username?.trim() ?? '';
      final password = service.password ?? '';
      if (server.isEmpty || username.isEmpty || password.isEmpty) return null;
      source = _buildXtreamPlaylistUrl(server, username, password);
    } else if (service.type == 'm3u') {
      final raw = service.url?.trim() ?? '';
      final uri = Uri.tryParse(raw);
      final username = uri?.queryParameters['username']?.trim() ?? '';
      final password = uri?.queryParameters['password'] ?? '';
      final path = uri?.path.toLowerCase() ?? '';
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          username.isNotEmpty &&
          password.isNotEmpty &&
          (path.endsWith('/get.php') || path.endsWith('get.php'))) {
        source = raw;
      }
    }

    if (source == null || source.isEmpty) return null;
    final existing = playlistById(localId);
    return Playlist(
      id: localId,
      name: service.name.trim().isEmpty ? 'TV FULL' : service.name.trim(),
      source: source,
      isRemote: true,
      // Hot Player expone primero la lista guardada/configurada y recupera el
      // catálogo después. Si ya existe una copia local la conservamos; si es
      // una vinculación nueva, el servicio aparece inmediatamente con 0 items.
      channels: existing?.channels ?? const <Channel>[],
      lastUpdated: DateTime.now(),
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
      throw Exception('Servidor Xtream inválido.');
    }

    var path = parsed.path;
    final lower = path.toLowerCase();
    if (lower.endsWith('/player_api.php')) {
      path = path.substring(0, path.length - '/player_api.php'.length);
    } else if (lower.endsWith('/get.php')) {
      path = path.substring(0, path.length - '/get.php'.length);
    }
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    path = '$path/get.php';

    return parsed.replace(
      path: path,
      queryParameters: <String, String>{
        'username': username,
        'password': password,
        'type': 'm3u_plus',
        'output': 'ts',
      },
      fragment: '',
    ).toString();
  }

'''
    if '_remoteXtreamStub(' not in text:
        text = replace_once(text, marker, helpers + marker, 'helpers remote Xtream local-first')

    old = '''  Future<Playlist> _buildRemotePlaylist(
    RemoteProvisionedService service,
    String localId,
  ) async {
    if (service.type == 'm3u') {
'''
    new = '''  Future<Playlist> _buildRemotePlaylist(
    RemoteProvisionedService service,
    String localId,
  ) async {
    // Vinculación rápida: si el panel ya entregó credenciales Xtream, guardar
    // el servicio no debe esperar get_live_streams, VOD, Series ni M3U.
    final localXtream = _remoteXtreamStub(service, localId);
    if (localXtream != null) return localXtream;

    if (service.type == 'm3u') {
'''
    text = replace_once(text, old, new, 'remote playlist stub before network')
    PROVIDER.write_text(text)


def patch_remote_polling():
    text = HOME.read_text()
    if 'Timer? _remotePollTimer;' not in text:
        text = replace_once(
            text,
            '  Set<String> _favoritePlaylistIds = <String>{};\n',
            '  Set<String> _favoritePlaylistIds = <String>{};\n  Timer? _remotePollTimer;\n  int _remotePollTick = 0;\n',
            'remote poll fields',
        )

    old = '''      context.read<IptvProvider>().init();
'''
    new = '''      final provider = context.read<IptvProvider>();
      unawaited(
        provider.init().whenComplete(() {
          if (mounted) _startRemotePolling();
        }),
      );
'''
    text = replace_once(text, old, new, 'provider init polling')

    marker = '''  Future<void> _loadFavoritePlaylists() async {
'''
    methods = r'''  void _startRemotePolling() {
    _remotePollTimer?.cancel();
    _remotePollTick = 0;
    _remotePollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final provider = context.read<IptvProvider>();
      if (provider.remoteSyncing) return;

      final hasProvisioned = provider.playlists.any(
        (playlist) => playlist.id.startsWith('tvf_remote_'),
      );
      _remotePollTick++;

      // Mientras todavía no llegó la primera lista, consultar cada 3 s.
      // Una vez vinculada, bajar a ~30 s para detectar cambios sin martillar API.
      if (!hasProvisioned || _remotePollTick % 10 == 0) {
        unawaited(provider.syncRemoteServices());
      }
    });
  }

  @override
  void dispose() {
    _remotePollTimer?.cancel();
    super.dispose();
  }

'''
    if '_startRemotePolling()' not in text:
        text = replace_once(text, marker, methods + marker, 'remote polling methods')
    HOME.write_text(text)


def patch_live_local_first():
    text = LIVE.read_text()
    if "import 'dart:async';" not in text:
        text = replace_once(text, "import 'package:flutter/material.dart';\n", "import 'dart:async';\n\nimport 'package:flutter/material.dart';\n", 'live async import')

    start = text.index('  Future<Playlist> _load({bool forceNetwork = false}) async {')
    end = text.index('  List<Channel> _originalLiveChannels()', start)
    new = r'''  Future<Playlist> _load({bool forceNetwork = false}) async {
    final service = XtreamLiveFastService.instance;

    if (!forceNetwork) {
      // Hot Player: almacenamiento local primero. La UI no espera la red.
      final cached = await service.loadCached(widget.playlist.source);
      if (cached != null && cached.channels.isNotEmpty) {
        final local = _playlistFromChannels(
          _mergePlaybackChannels(cached.channels),
        );
        unawaited(_refreshLiveInBackground());
        return local;
      }

      final original = _originalLiveChannels();
      if (original.isNotEmpty) {
        unawaited(_refreshLiveInBackground());
        return _playlistFromChannels(original);
      }
    }

    final fresh = await service.refresh(
      widget.playlist.source,
      forceSessionRefresh: forceNetwork,
      onProgress: _onProgress,
    );
    return _playlistFromChannels(_mergePlaybackChannels(fresh.channels));
  }

  Future<void> _refreshLiveInBackground() async {
    try {
      final fresh = await XtreamLiveFastService.instance.refresh(
        widget.playlist.source,
        onProgress: _onProgress,
      );
      if (!mounted) return;
      final updated = _playlistFromChannels(
        _mergePlaybackChannels(fresh.channels),
      );
      setState(() => _future = Future<Playlist>.value(updated));
    } catch (_) {
      // La copia local sigue usable. Un refresh nunca bloquea la sección.
    }
  }

'''
    text = text[:start] + new + text[end:]
    LIVE.write_text(text)


def patch_movies_local_first():
    text = MOVIES.read_text()
    start = text.index('  Future<_MovieCatalogData> _load({bool forceNetwork = false}) async {')
    end = text.index('  void _setCatalogCategories(', start)
    new = r'''  Future<_MovieCatalogData> _load({bool forceNetwork = false}) async {
    await _parental.init();
    final fast = XtreamFastCatalogService.instance;

    if (!forceNetwork) {
      final cached = await fast.loadCachedMovies(widget.playlist.source);
      if (cached != null && cached.movies.isNotEmpty) {
        _setCatalogCategories(cached.categories);
        unawaited(_refreshMoviesInBackground());
        return _MovieCatalogData(
          connection: cached.connection,
          movies: cached.movies,
        );
      }
    }

    final fresh = await fast.refreshMovies(
      widget.playlist.source,
      forceSessionRefresh: forceNetwork,
      onProgress: _onCatalogProgress,
    );
    _setCatalogCategories(fresh.categories);
    return _MovieCatalogData(
      connection: fresh.connection,
      movies: fresh.movies,
    );
  }

  Future<void> _refreshMoviesInBackground() async {
    try {
      final fresh = await XtreamFastCatalogService.instance.refreshMovies(
        widget.playlist.source,
        onProgress: _onCatalogProgress,
      );
      if (!mounted) return;
      _setCatalogCategories(fresh.categories);
      final updated = _MovieCatalogData(
        connection: fresh.connection,
        movies: fresh.movies,
      );
      setState(() => _future = Future<_MovieCatalogData>.value(updated));
    } catch (_) {
      // Mantener catálogo local si el proveedor está lento o sin conexión.
    }
  }

'''
    text = text[:start] + new + text[end:]
    MOVIES.write_text(text)


def patch_series_local_first():
    text = SERIES.read_text()
    start = text.index('  Future<_SeriesCatalogData> _load({bool forceNetwork = false}) async {')
    end = text.index('  void _setCatalogCategories(', start)
    new = r'''  Future<_SeriesCatalogData> _load({bool forceNetwork = false}) async {
    await _parental.init();
    final fast = XtreamFastCatalogService.instance;

    if (!forceNetwork) {
      final cached = await fast.loadCachedSeries(widget.playlist.source);
      if (cached != null && cached.series.isNotEmpty) {
        _setCatalogCategories(cached.categories);
        unawaited(_refreshSeriesInBackground());
        return _SeriesCatalogData(
          connection: cached.connection,
          series: cached.series,
        );
      }
    }

    final fresh = await fast.refreshSeries(
      widget.playlist.source,
      forceSessionRefresh: forceNetwork,
      onProgress: _onCatalogProgress,
    );
    _setCatalogCategories(fresh.categories);
    return _SeriesCatalogData(
      connection: fresh.connection,
      series: fresh.series,
    );
  }

  Future<void> _refreshSeriesInBackground() async {
    try {
      final fresh = await XtreamFastCatalogService.instance.refreshSeries(
        widget.playlist.source,
        onProgress: _onCatalogProgress,
      );
      if (!mounted) return;
      _setCatalogCategories(fresh.categories);
      final updated = _SeriesCatalogData(
        connection: fresh.connection,
        series: fresh.series,
      );
      setState(() => _future = Future<_SeriesCatalogData>.value(updated));
    } catch (_) {
      // Mantener catálogo local si el proveedor está lento o sin conexión.
    }
  }

'''
    text = text[:start] + new + text[end:]
    SERIES.write_text(text)


def patch_logos_and_cleartext():
    text = MANIFEST.read_text()
    if 'android:usesCleartextTraffic=' not in text:
        text = replace_once(
            text,
            '<application\n',
            '<application\n        android:usesCleartextTraffic="true"\n',
            'cleartext traffic Hot Player compatible',
        )
    MANIFEST.write_text(text)

    text = LIVE_FAST.read_text()
    old = "      'logoUrl': _firstText(item, const ['stream_icon', 'logo', 'icon']),"
    if old in text:
        new = "      'logoUrl': _resolveArtworkUrl(\n        streamServer,\n        _firstText(item, const ['stream_icon', 'logo', 'icon']),\n      ),"
        text = text.replace(old, new, 1)

        marker = '''String? _resolveDirect(Uri base, String? raw) {\n'''
        helper = '''String? _resolveArtworkUrl(Uri base, String? raw) {\n  final value = raw?.trim() ?? '';\n  if (value.isEmpty || value.toLowerCase() == 'null' || value == '0') {\n    return null;\n  }\n  if (value.startsWith('//')) {\n    return '${base.scheme == 'https' ? 'https' : 'http'}:$value';\n  }\n  final parsed = Uri.tryParse(value);\n  if (parsed != null &&\n      (parsed.scheme == 'http' || parsed.scheme == 'https') &&\n      parsed.host.isNotEmpty) {\n    return parsed.toString();\n  }\n  return base.resolve(value).toString();\n}\n\n'''
        text = replace_once(text, marker, helper + marker, 'logo URL resolver')
    LIVE_FAST.write_text(text)

    text = CHANNELS.read_text()
    pattern = re.compile(
        r'''\s*Container\(\n\s*width: 46,\n\s*height: 46,\n\s*decoration: BoxDecoration\(.*?\n\s*child: const Icon\(Icons\.live_tv_rounded, size: 24\),\n\s*\),''',
        re.S,
    )
    replacement = '''\n                                SizedBox(\n                                  width: 46,\n                                  height: 46,\n                                  child: ClipRRect(\n                                    borderRadius: BorderRadius.circular(10),\n                                    child: CachedArtworkImage(\n                                      url: channel.logoUrl,\n                                      fit: BoxFit.contain,\n                                      cacheWidth: 92,\n                                      cacheHeight: 92,\n                                      prefetchExtent: 0,\n                                      fallback: ColoredBox(\n                                        color: Theme.of(context)\n                                            .colorScheme\n                                            .primary\n                                            .withValues(alpha: .14),\n                                        child: const Icon(\n                                          Icons.live_tv_rounded,\n                                          size: 24,\n                                        ),\n                                      ),\n                                    ),\n                                  ),\n                                ),'''
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit('No se pudo restaurar logo de canal después del fix V10')
    CHANNELS.write_text(text)


def patch_vod_safe_software():
    text = MAIN.read_text()
    text = text.replace(
        '''  if (!_androidTvBuild) {\n    MediaKit.ensureInitialized();\n  }\n''',
        '''  MediaKit.ensureInitialized();\n''',
        1,
    )
    MAIN.write_text(text)

    text = PLAYER.read_text()
    if "import 'dart:io';" not in text:
        text = replace_once(text, "import 'dart:async';\n", "import 'dart:async';\nimport 'dart:io';\n", 'dart io for VOD preflight')

    text, count = re.subn(
        r'''    final useNativeMedia3Vod =\n        _androidTvBuild &&\n        !kIsWeb &&\n        defaultTargetPlatform == TargetPlatform\.android &&\n        !isLiveContent;''',
        '''    // LIVE sigue en Media3 estable. VOD usa media_kit/libmpv con\n    // decodificación software para no tocar el decoder Realtek problemático.\n    final useNativeMedia3Vod = false;''',
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit('No se pudo enrutar VOD V13 a media_kit')

    old_comment = '''        // Android TV: no forzamos opciones de decodificación/sincronización\n        // desde la app. media_kit_video administra su Surface nativa y la ruta\n        // MediaCodec de Android para evitar copias innecesarias por CPU.\n'''
    if old_comment in text:
        text = text.replace(
            old_comment,
            '''        // V13: este player sólo recibe VOD en Android TV. Forzamos\n        // software decode para evitar MediaCodec/Realtek; LIVE no pasa por acá.\n        if (!widget.isLiveContent) {\n          await platform.setProperty('hwdec', 'no');\n        }\n''',
            1,
        )

    advance = '''  bool _advanceCompatibilityMode(\n    String reason, {\n    ServerCompatibilityMode? preferredTarget,\n  }) {\n    if (_hasEverPlayed || _compatibilityPlan.isEmpty) {\n'''
    if advance in text:
        text = text.replace(
            advance,
            '''  bool _advanceCompatibilityMode(\n    String reason, {\n    ServerCompatibilityMode? preferredTarget,\n  }) {\n    if (!widget.isLiveContent) return false;\n    if (_hasEverPlayed || _compatibilityPlan.isEmpty) {\n''',
            1,
        )

    marker = '''  Future<void> _playCurrent({\n'''
    if '_preflightVod(' not in text:
        helper = r'''  Future<String?> _preflightVod(Channel channel) async {
    if (widget.isLiveContent) return null;
    final uri = Uri.tryParse(channel.url.trim());
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'La URL de esta película o episodio no es válida.';
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-65535');
      final headers = channel.resolvedHttpHeaders(_defaultUserAgent);
      for (final entry in headers.entries) {
        try {
          request.headers.set(entry.key, entry.value);
        } catch (_) {}
      }
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'El servidor rechazó el contenido (HTTP ${response.statusCode}).';
      }
      try {
        final firstChunk = await response.first.timeout(const Duration(seconds: 5));
        if (firstChunk.isEmpty) {
          return 'El servidor respondió pero no entregó datos de video.';
        }
      } on StateError {
        return 'El servidor respondió pero no entregó datos de video.';
      } on TimeoutException {
        return 'El servidor tardó demasiado en entregar los primeros datos.';
      }
      return null;
    } on TimeoutException {
      return 'El servidor tardó demasiado en responder.';
    } on SocketException {
      return 'No se pudo abrir la conexión de esta película o episodio.';
    } on HttpException catch (error) {
      return 'Error HTTP antes de reproducir: ${error.message}';
    } catch (_) {
      return 'No se pudo validar el contenido antes de reproducir.';
    } finally {
      client.close(force: true);
    }
  }

'''
        text = replace_once(text, marker, helper + marker, 'VOD preflight helper')

    old_prepare = '''    _lastKnownPosition = Duration.zero;\n    _lastProgressAt = DateTime.now();\n\n    final prepared = await _prepareChannelTuning(\n'''
    new_prepare = '''    _lastKnownPosition = Duration.zero;\n    _lastProgressAt = DateTime.now();\n\n    if (!widget.isLiveContent && !isRetry) {\n      final preflightError = await _preflightVod(widget.playlist[_currentIndex]);\n      if (!mounted || session != _sessionId) return;\n      if (preflightError != null) {\n        _opening = false;\n        _acceptPlaybackEvents = true;\n        _startupStopwatch?.stop();\n        setState(() {\n          _isBuffering = false;\n          _reconnecting = false;\n          _errorTitle = 'NO SE PUDO ABRIR EL CONTENIDO';\n          _errorMessage = preflightError;\n          _engineDiagnostic = 'V13 bloqueó una URL VOD inválida antes del decoder';\n        });\n        return;\n      }\n    }\n\n    final prepared = await _prepareChannelTuning(\n'''
    text = replace_once(text, old_prepare, new_prepare, 'VOD preflight before decoder')

    old_retry = '''    if (_retryCount < _maxAutoRetries) {\n      final seconds = 1 << _retryCount;\n'''
    if old_retry in text:
        text = text.replace(
            old_retry,
            '''    final retryLimit = widget.isLiveContent ? _maxAutoRetries : 0;\n    if (_retryCount < retryLimit) {\n      final seconds = 1 << _retryCount;\n''',
            1,
        )

    PLAYER.write_text(text)


def patch_version_without_package_change():
    text = REMOTE.read_text()
    text = re.sub(
        r"1\.0\.0\+1-android-tv-[A-Za-z0-9._-]+",
        '1.0.0+1-android-tv-v13-hotplayer-flow',
        text,
        count=1,
    )
    REMOTE.write_text(text)


def verify():
    checks = {
        PROVIDER: ['_remoteXtreamStub(', '_buildXtreamPlaylistUrl(', 'channels: existing?.channels'],
        HOME: ['Timer? _remotePollTimer;', '_startRemotePolling()', 'Duration(seconds: 3)'],
        LIVE: ['_refreshLiveInBackground()', 'loadCached(widget.playlist.source)'],
        MOVIES: ['_refreshMoviesInBackground()', 'loadCachedMovies(widget.playlist.source)'],
        SERIES: ['_refreshSeriesInBackground()', 'loadCachedSeries(widget.playlist.source)'],
        PLAYER: ["setProperty('hwdec', 'no')", '_preflightVod(', 'useNativeMedia3Vod = false'],
        MANIFEST: ['android:usesCleartextTraffic="true"'],
        LIVE_FAST: ['_resolveArtworkUrl('],
        CHANNELS: ['url: channel.logoUrl', 'prefetchExtent: 0'],
    }
    for path, markers in checks.items():
        content = path.read_text()
        for marker in markers:
            if marker not in content:
                raise SystemExit(f'Verificación V13 falló: {path} -> {marker}')


patch_remote_linking()
patch_remote_polling()
patch_live_local_first()
patch_movies_local_first()
patch_series_local_first()
patch_logos_and_cleartext()
patch_vod_safe_software()
patch_version_without_package_change()
verify()
print('V13 aplicado: panel instantáneo + local-first + logos visibles + VOD software seguro.')
