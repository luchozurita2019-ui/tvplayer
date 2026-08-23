from pathlib import Path
import re

ROOT = Path('.')
MAIN = ROOT / 'lib/main.dart'
HOME = ROOT / 'lib/screens/home_screen.dart'
PLAYER = ROOT / 'lib/screens/player_screen.dart'
CHANNELS = ROOT / 'lib/screens/channel_list_screen.dart'
MOVIES = ROOT / 'lib/screens/xtream_movies_screen.dart'
SERIES = ROOT / 'lib/screens/xtream_series_screen.dart'
PROVIDER = ROOT / 'lib/providers/iptv_provider.dart'
XTREAM = ROOT / 'lib/services/xtream_service.dart'
VOD_SERVICE = ROOT / 'lib/services/xtream_vod_service.dart'
SERIES_SERVICE = ROOT / 'lib/services/xtream_series_service.dart'
GRADLE = ROOT / 'android/app/build.gradle.kts'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Marcador no encontrado V11: {label}')
    return text.replace(old, new, 1)


def patch_lazy_remote_catalog():
    text = XTREAM.read_text()
    marker = '''  static Future<XtreamNativeCatalog> fetchNativeCatalog(\n'''
    helper = '''  /// Carga mínima para el aprovisionamiento remoto de Android TV.\n  /// No consulta VOD ni descarga get.php: el servicio queda visible apenas\n  /// llegan categorías y streams LIVE. Películas/Series se cargan al entrar.\n  static Future<List<Channel>> fetchLiveCatalog(\n    XtreamConnectionResult connection, {\n    Duration timeout = const Duration(seconds: 12),\n  }) async {\n    final results = await Future.wait<List<dynamic>>([\n      _safeActionList(connection, 'get_live_categories', timeout),\n      _safeActionList(connection, 'get_live_streams', timeout),\n    ]);\n    final categories = _categoryMap(results[0]);\n    return List<Channel>.unmodifiable(\n      _liveChannels(\n        connection,\n        categories: categories,\n        rawStreams: results[1],\n      ),\n    );\n  }\n\n'''
    if 'static Future<List<Channel>> fetchLiveCatalog(' not in text:
        text = replace_once(text, marker, helper + marker, 'helper live-only Xtream')
    XTREAM.write_text(text)

    text = PROVIDER.read_text()
    helper_marker = '''  Future<Playlist> _buildRemotePlaylist(\n'''
    helper = '''  Future<List<Channel>> _loadXtreamLiveOnly(\n    XtreamConnectionResult connection,\n  ) async {\n    final live = await XtreamService.fetchLiveCatalog(connection);\n    if (live.isEmpty) {\n      throw Exception('Xtream autenticó, pero no devolvió canales LIVE.');\n    }\n    return live;\n  }\n\n'''
    if '_loadXtreamLiveOnly(' not in text:
        text = replace_once(text, helper_marker, helper + helper_marker, 'helper provider live-only')

    start = text.index('  Future<Playlist> _buildRemotePlaylist(')
    end = text.index('  Future<void> renamePlaylist(', start)
    block = text[start:end]
    block = block.replace('channels = await _loadXtreamChannels(xtream);', 'channels = await _loadXtreamLiveOnly(xtream);')
    block = block.replace('final channels = await _loadXtreamChannels(connection);', 'final channels = await _loadXtreamLiveOnly(connection);')
    text = text[:start] + block + text[end:]
    PROVIDER.write_text(text)


def patch_panel_polling():
    text = HOME.read_text()
    text = replace_once(
        text,
        '  Set<String> _favoritePlaylistIds = <String>{};\n',
        '  Set<String> _favoritePlaylistIds = <String>{};\n  Timer? _remotePollTimer;\n',
        'timer polling panel',
    )

    text = replace_once(
        text,
        '''      context.read<IptvProvider>().init();\n''',
        '''      final provider = context.read<IptvProvider>();\n      unawaited(\n        provider.init().whenComplete(() {\n          if (mounted) _startRemotePolling();\n        }),\n      );\n''',
        'inicio provider con polling',
    )

    marker = '''  Future<void> _loadFavoritePlaylists() async {\n'''
    polling = '''  void _startRemotePolling() {\n    _remotePollTimer?.cancel();\n    _remotePollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {\n      if (!mounted) {\n        timer.cancel();\n        return;\n      }\n      final provider = context.read<IptvProvider>();\n      if (provider.playlists.isNotEmpty) {\n        timer.cancel();\n        return;\n      }\n      if (!provider.remoteSyncing) {\n        unawaited(provider.syncRemoteServices());\n      }\n    });\n  }\n\n  @override\n  void dispose() {\n    _remotePollTimer?.cancel();\n    super.dispose();\n  }\n\n'''
    text = replace_once(text, marker, polling + marker, 'metodo polling panel')
    HOME.write_text(text)


def patch_real_lazy_logos():
    text = CHANNELS.read_text()
    pattern = re.compile(
        r'''\s*Container\(\n\s*width: 46,\n\s*height: 46,\n\s*decoration: BoxDecoration\(.*?\n\s*child: const Icon\(Icons\.live_tv_rounded, size: 24\),\n\s*\),''',
        re.S,
    )
    replacement = '''\n                                SizedBox(\n                                  width: 46,\n                                  height: 46,\n                                  child: ClipRRect(\n                                    borderRadius: BorderRadius.circular(10),\n                                    child: CachedArtworkImage(\n                                      url: channel.logoUrl,\n                                      fit: BoxFit.contain,\n                                      cacheWidth: 92,\n                                      cacheHeight: 92,\n                                      prefetchExtent: 48,\n                                      fallback: ColoredBox(\n                                        color: Theme.of(context)\n                                            .colorScheme\n                                            .primary\n                                            .withValues(alpha: .14),\n                                        child: const Icon(\n                                          Icons.live_tv_rounded,\n                                          size: 24,\n                                        ),\n                                      ),\n                                    ),\n                                  ),\n                                ),'''
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit('No se pudo restaurar logo real V11')
    CHANNELS.write_text(text)

    text = MOVIES.read_text()
    text = text.replace(
        '''                  CachedArtworkImage(\n                    url: movie.cover,\n                    fit: BoxFit.cover,\n''',
        '''                  CachedArtworkImage(\n                    url: movie.cover,\n                    fit: BoxFit.cover,\n                    cacheWidth: 300,\n                    prefetchExtent: 48,\n''',
        1,
    )
    MOVIES.write_text(text)

    text = SERIES.read_text()
    text = text.replace('cacheWidth: 420,', 'cacheWidth: 300,\n                prefetchExtent: 48,', 1)
    SERIES.write_text(text)


def patch_direct_sources():
    text = VOD_SERVICE.read_text()
    text = replace_once(
        text,
        '    final url = _movieUrl(connection, id, extension);',
        '    final url = _resolveDirect(connection.streamServer, directSource) ??\n        _movieUrl(connection, id, extension);',
        'direct source summary VOD',
    )
    text = replace_once(
        text,
        '    final url = _movieUrl(connection, movie.id, extension);',
        '    final url = _resolveDirect(connection.streamServer, directSource) ??\n        _resolveDirect(connection.streamServer, movie.directSource) ??\n        _movieUrl(connection, movie.id, extension);',
        'direct source details VOD',
    )
    text = replace_once(
        text,
        '''    final catalogPlayableUrl =\n        _movieUrl(activeConnection, summary.id, summary.extension);''',
        '''    final catalogPlayableUrl =\n        _resolveDirect(activeConnection.streamServer, summary.directSource) ??\n            _movieUrl(activeConnection, summary.id, summary.extension);''',
        'direct source catalog VOD',
    )
    text = replace_once(
        text,
        '''      final playableUrl =\n          _movieUrl(activeConnection, summary.id, extension);''',
        '''      final rawDirect = _firstText(movieData, const ['direct_source']) ??\n          _firstText(info, const ['direct_source']);\n      final playableUrl =\n          _resolveDirect(activeConnection.streamServer, rawDirect) ??\n              _resolveDirect(\n                activeConnection.streamServer,\n                summary.directSource,\n              ) ??\n              _movieUrl(activeConnection, summary.id, extension);''',
        'direct source playback VOD',
    )
    VOD_SERVICE.write_text(text)

    text = SERIES_SERVICE.read_text()
    insert = '''    final direct = _resolvedEpisodeDirectSource(\n      connection.streamServer,\n      directSource,\n    );\n\n'''
    marker = '''    final prefix = connection.streamServer.pathSegments\n'''
    if insert not in text:
        text = replace_once(text, marker, insert + marker, 'direct source episode')
    text = replace_once(text, '      url: generated,', '      url: direct ?? generated,', 'episode channel direct source')
    text = replace_once(
        text,
        '    final playableDirect = _seriesUrl(activeConnection, id, extension);',
        '''    final playableDirect = XtreamSeriesEpisode._resolvedEpisodeDirectSource(\n          activeConnection.streamServer,\n          directSource,\n        ) ??\n        _seriesUrl(activeConnection, id, extension);''',
        'episode resolved direct source',
    )
    SERIES_SERVICE.write_text(text)


def patch_vod_engine_to_mpv():
    text = MAIN.read_text()
    text = replace_once(
        text,
        '''  if (!_androidTvBuild) {\n    MediaKit.ensureInitialized();\n  }\n''',
        '''  MediaKit.ensureInitialized();\n''',
        'inicializar MediaKit Android TV V11',
    )
    MAIN.write_text(text)

    text = PLAYER.read_text()
    pattern = re.compile(
        r'''    final useNativeMedia3Vod =\n        _androidTvBuild &&\n        !kIsWeb &&\n        defaultTargetPlatform == TargetPlatform\.android &&\n        !isLiveContent;'''
    )
    text, count = pattern.subn(
        '''    // V11: LIVE permanece en Media3. VOD vuelve al motor MPV/media_kit\n    // ya incluido en TV FULL, evitando el cierre nativo observado al cargar\n    // películas/episodios en determinados decoders Android TV.\n    final useNativeMedia3Vod = false;''',
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit('No se pudo enrutar VOD a MPV')
    PLAYER.write_text(text)


def patch_movie_tv_detail():
    text = MOVIES.read_text()
    old = '''                return LayoutBuilder(\n                  builder: (context, constraints) => constraints.maxWidth >= 980\n                      ? _buildWide(details)\n                      : _buildCompact(details),\n                );'''
    new = '''                return LayoutBuilder(\n                  builder: (context, constraints) {\n                    if (_androidTvBuild) return _buildTv(details);\n                    return constraints.maxWidth >= 980\n                        ? _buildWide(details)\n                        : _buildCompact(details);\n                  },\n                );'''
    text = replace_once(text, old, new, 'forzar ficha TV peliculas')

    marker = '''  Widget _buildWide(XtreamVodDetails details) {\n'''
    tv = '''  Widget _buildTv(XtreamVodDetails details) {\n    final description = details.plot?.trim() ?? '';\n    return Padding(\n      padding: const EdgeInsets.fromLTRB(26, 20, 30, 24),\n      child: Row(\n        crossAxisAlignment: CrossAxisAlignment.stretch,\n        children: [\n          SizedBox(\n            width: 190,\n            child: Align(\n              alignment: Alignment.topCenter,\n              child: AspectRatio(\n                aspectRatio: 0.67,\n                child: ClipRRect(\n                  borderRadius: BorderRadius.circular(16),\n                  child: CachedArtworkImage(\n                    url: details.movie.cover,\n                    fit: BoxFit.cover,\n                    cacheWidth: 380,\n                    cacheHeight: 560,\n                    prefetchExtent: 0,\n                    fallback: const ColoredBox(\n                      color: Color(0xFF111C2C),\n                      child: Center(\n                        child: Icon(Icons.movie_rounded, size: 54),\n                      ),\n                    ),\n                  ),\n                ),\n              ),\n            ),\n          ),\n          const SizedBox(width: 26),\n          Expanded(\n            child: Column(\n              crossAxisAlignment: CrossAxisAlignment.start,\n              children: [\n                Text(\n                  details.movie.name,\n                  maxLines: 2,\n                  overflow: TextOverflow.ellipsis,\n                  style: const TextStyle(\n                    fontSize: 28,\n                    fontWeight: FontWeight.w900,\n                  ),\n                ),\n                const SizedBox(height: 10),\n                Wrap(\n                  spacing: 14,\n                  runSpacing: 6,\n                  children: [\n                    if (details.releaseDate?.trim().isNotEmpty ?? false)\n                      Text(details.releaseDate!),\n                    if (details.genre?.trim().isNotEmpty ?? false)\n                      Text(details.genre!),\n                    if (details.duration?.trim().isNotEmpty ?? false)\n                      Text(details.duration!),\n                    if (details.rating?.trim().isNotEmpty ?? false)\n                      Text('★ ${details.rating}'),\n                  ],\n                ),\n                if (description.isNotEmpty) ...[\n                  const SizedBox(height: 16),\n                  Text(\n                    description,\n                    maxLines: 4,\n                    overflow: TextOverflow.ellipsis,\n                    style: const TextStyle(\n                      fontSize: 16,\n                      height: 1.35,\n                      color: Colors.white70,\n                    ),\n                  ),\n                ],\n                const Spacer(),\n                Wrap(\n                  spacing: 12,\n                  runSpacing: 10,\n                  children: [\n                    FilledButton.icon(\n                      autofocus: true,\n                      onPressed: () => _play(details),\n                      icon: const Icon(Icons.play_arrow_rounded),\n                      label: const Text('PLAY'),\n                    ),\n                    if (details.trailerChannel() != null)\n                      OutlinedButton.icon(\n                        onPressed: () => _playTrailer(details),\n                        icon: const Icon(Icons.movie_filter_rounded),\n                        label: const Text('Tráiler'),\n                      ),\n                  ],\n                ),\n              ],\n            ),\n          ),\n        ],\n      ),\n    );\n  }\n\n'''
    text = replace_once(text, marker, tv + marker, 'ficha TV compacta peliculas')
    MOVIES.write_text(text)


def patch_series_tv_detail():
    text = SERIES.read_text()
    old = '''                    if (constraints.maxWidth >= 980) {\n                      return _buildWide(details, season, episodes);\n                    }\n                    return _buildCompact(details, season, episodes);'''
    new = '''                    if (_androidTvBuild || constraints.maxWidth >= 980) {\n                      return _buildWide(details, season, episodes);\n                    }\n                    return _buildCompact(details, season, episodes);'''
    text = replace_once(text, old, new, 'forzar layout TV series')
    SERIES.write_text(text)


def patch_version():
    gradle = GRADLE.read_text().replace(
        'applicationId = "com.tvfull.pro.tv.v10safe"',
        'applicationId = "com.tvfull.pro.tv.v11lazy"',
    )
    GRADLE.write_text(gradle)

    if REMOTE.exists():
        text = REMOTE.read_text()
        text = re.sub(
            r'1\.0\.0\+1-android-tv-[A-Za-z0-9._-]+',
            '1.0.0+1-android-tv-v11-lazy-vod',
            text,
        )
        REMOTE.write_text(text)


def validate():
    checks = {
        XTREAM: ['fetchLiveCatalog(', "'get_live_streams'"],
        PROVIDER: ['_loadXtreamLiveOnly(', 'XtreamService.fetchLiveCatalog'],
        HOME: ['Timer? _remotePollTimer;', 'Duration(seconds: 3)', 'syncRemoteServices()'],
        CHANNELS: ['url: channel.logoUrl', 'prefetchExtent: 48'],
        VOD_SERVICE: ['summary.directSource', 'rawDirect'],
        SERIES_SERVICE: ['url: direct ?? generated', '_resolvedEpisodeDirectSource'],
        MAIN: ['MediaKit.ensureInitialized();'],
        PLAYER: ['final useNativeMedia3Vod = false;'],
        MOVIES: ['Widget _buildTv(', 'maxLines: 4', "label: const Text('PLAY')"],
        SERIES: ['_androidTvBuild || constraints.maxWidth >= 980'],
        GRADLE: ['com.tvfull.pro.tv.v11lazy'],
    }
    for path, markers in checks.items():
        value = path.read_text()
        for marker in markers:
            if marker not in value:
                raise SystemExit(f'Validacion V11 fallo {path}: {marker}')


patch_lazy_remote_catalog()
patch_panel_polling()
patch_real_lazy_logos()
patch_direct_sources()
patch_vod_engine_to_mpv()
patch_movie_tv_detail()
patch_series_tv_detail()
patch_version()
validate()
print('V11 aplicada: panel LIVE-first, imágenes lazy, VOD MPV/direct_source y fichas TV compactas.')
