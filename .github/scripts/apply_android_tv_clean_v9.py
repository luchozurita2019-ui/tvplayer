from pathlib import Path
import re

ROOT = Path('.')
MAIN_DART = ROOT / 'lib/main.dart'
HOME = ROOT / 'lib/screens/home_screen.dart'
SOURCE = ROOT / 'lib/screens/source_content_screen.dart'
CHANNELS = ROOT / 'lib/screens/channel_list_screen.dart'
MOVIES = ROOT / 'lib/screens/xtream_movies_screen.dart'
SERIES_SCREEN = ROOT / 'lib/screens/xtream_series_screen.dart'
VOD_SERVICE = ROOT / 'lib/services/xtream_vod_service.dart'
SERIES_SERVICE = ROOT / 'lib/services/xtream_series_service.dart'
LIVE_PLAYER = ROOT / 'lib/screens/android_media3_texture_player_screen.dart'
VOD_PLAYER = ROOT / 'lib/screens/android_media3_vod_player_screen.dart'
GRADLE = ROOT / 'android/app/build.gradle.kts'
MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'
MAIN_KT = next((ROOT / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))

HOTPLAYER_UA = (
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/96.0.4664.18 Safari/537.36'
)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Marcador no encontrado: {label}')
    return text.replace(old, new, 1)


def patch_native_bridge():
    text = MAIN_KT.read_text()

    # Hot Player no impone un watchdog de 5/12 s en el bridge Media3.
    # Dejamos que Media3/HTTP emita el error real en lugar de matar streams sanos.
    timeout_pattern = re.compile(
        r'\n\s*val timeoutMs = if \(isLive\) STARTUP_TIMEOUT_MS else 12000L\n'
        r'\s*startupTimeout = Runnable \{.*?\n\s*\}\.also \{ handler\.postDelayed\(it, timeoutMs\) \}\n',
        re.S,
    )
    text, count = timeout_pattern.subn(
        '\n        // Sin timeout artificial: Media3 decide READY o error real.\n',
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit('No se pudo retirar timeout artificial V8')

    old_ua = (
        'Mozilla/5.0 (Linux; Android 10; Android TV) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    )
    text = text.replace(old_ua, HOTPLAYER_UA)
    MAIN_KT.write_text(text)


def patch_player_ua_and_live_overlay():
    live = LIVE_PLAYER.read_text()
    live = re.sub(
        r"const String _media3DefaultUserAgent =\n\s*'Mozilla/5\.0 \(Linux; Android 10; Android TV\) '\n\s*'AppleWebKit/537\.36 \(KHTML, like Gecko\) '\n\s*'Chrome/131\.0\.0\.0 Safari/537\.36';",
        "const String _media3DefaultUserAgent =\n    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '\n    'AppleWebKit/537.36 (KHTML, like Gecko) '\n    'Chrome/96.0.4664.18 Safari/537.36';",
        live,
        count=1,
    )

    live = replace_once(
        live,
        '  StreamSubscription<dynamic>? _eventSub;\n',
        '  StreamSubscription<dynamic>? _eventSub;\n  Timer? _overlayTimer;\n',
        'timer overlay live',
    )

    old_video = '''      case 'videoSize':
        final width = (event['width'] as num?)?.toDouble() ?? 0;
        final height = (event['height'] as num?)?.toDouble() ?? 0;
        if (width > 0 && height > 0) {
          setState(() => _aspectRatio = width / height);
        }
        break;
'''
    new_video = '''      case 'videoSize':
        final width = (event['width'] as num?)?.toDouble() ?? 0.0;
        final height = (event['height'] as num?)?.toDouble() ?? 0.0;
        final pixelRatio =
            (event['pixelWidthHeightRatio'] as num?)?.toDouble() ?? 1.0;
        if (width > 0 && height > 0) {
          final ratio = (width * (pixelRatio > 0 ? pixelRatio : 1.0)) / height;
          if (ratio > 0.5 && ratio < 3.0) {
            setState(() => _aspectRatio = ratio);
          }
        }
        break;
'''
    live = replace_once(live, old_video, new_video, 'aspect ratio live')

    marker = '  void _previous() {\n'
    overlay_method = '''  void _showOverlay() {
    _overlayTimer?.cancel();
    if (mounted && !_overlayVisible) {
      setState(() => _overlayVisible = true);
    }
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _error != null || _buffering) return;
      setState(() => _overlayVisible = false);
    });
  }

'''
    live = replace_once(live, marker, overlay_method + marker, 'metodo autohide live')

    live = live.replace(
        '      _overlayVisible = true;\n    });\n    unawaited(_prepareCurrent());',
        '      _overlayVisible = true;\n    });\n    _showOverlay();\n    unawaited(_prepareCurrent());',
    )

    live = replace_once(
        live,
        '    if (event is! KeyDownEvent) return KeyEventResult.ignored;\n    final key = event.logicalKey;\n',
        '    if (event is! KeyDownEvent) return KeyEventResult.ignored;\n    final key = event.logicalKey;\n    _showOverlay();\n',
        'mostrar overlay con control remoto',
    )

    live = replace_once(
        live,
        '    _eventSub?.cancel();\n    _focusNode.dispose();\n',
        '    _overlayTimer?.cancel();\n    _eventSub?.cancel();\n    _focusNode.dispose();\n',
        'dispose overlay live',
    )

    # Arranca visible y luego desaparece solo.
    live = replace_once(
        live,
        '      if (mounted) _focusNode.requestFocus();\n',
        '      if (mounted) {\n        _focusNode.requestFocus();\n        _showOverlay();\n      }\n',
        'autohide inicial live',
    )
    LIVE_PLAYER.write_text(live)

    vod = VOD_PLAYER.read_text()
    vod = re.sub(
        r"const String _vodUserAgent =\n\s*'Mozilla/5\.0 \(Linux; Android 10; Android TV\) '\n\s*'AppleWebKit/537\.36 \(KHTML, like Gecko\) '\n\s*'Chrome/131\.0\.0\.0 Safari/537\.36';",
        "const String _vodUserAgent =\n    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '\n    'AppleWebKit/537.36 (KHTML, like Gecko) '\n    'Chrome/96.0.4664.18 Safari/537.36';",
        vod,
        count=1,
    )
    VOD_PLAYER.write_text(vod)


def patch_xtream_vod_urls():
    text = VOD_SERVICE.read_text()

    text = re.sub(
        r'''    final url = _resolveDirect\(connection\.streamServer, directSource\) \?\?\n\s*_movieUrl\(connection, id, extension\);''',
        '    final url = _movieUrl(connection, id, extension);',
        text,
        count=1,
    )
    text = re.sub(
        r'''    final url = _resolveDirect\(connection\.streamServer, directSource\) \?\?\n\s*_resolveDirect\(connection\.streamServer, movie\.directSource\) \?\?\n\s*_movieUrl\(connection, movie\.id, extension\);''',
        '    final url = _movieUrl(connection, movie.id, extension);',
        text,
        count=1,
    )
    text = re.sub(
        r'''    final catalogPlayableUrl =\n\s*_resolveDirect\(activeConnection\.streamServer, summary\.directSource\) \?\?\n\s*_movieUrl\(activeConnection, summary\.id, summary\.extension\);''',
        '    final catalogPlayableUrl =\n        _movieUrl(activeConnection, summary.id, summary.extension);',
        text,
        count=1,
    )
    text = re.sub(
        r'''      final rawDirect = _firstText\(movieData, const \['direct_source'\]\) \?\?\n\s*_firstText\(info, const \['direct_source'\]\);\n      final playableUrl =\n\s*_resolveDirect\(activeConnection\.streamServer, rawDirect\) \?\?\n\s*_resolveDirect\(\n\s*activeConnection\.streamServer,\n\s*summary\.directSource,\n\s*\) \?\?\n\s*_movieUrl\(activeConnection, summary\.id, extension\);''',
        '      final playableUrl =\n          _movieUrl(activeConnection, summary.id, extension);',
        text,
        count=1,
    )

    VOD_SERVICE.write_text(text)


def patch_xtream_series_urls():
    text = SERIES_SERVICE.read_text()

    # Hot Player AOT expone /series/ y container_extension, pero no direct_source.
    direct_block = re.compile(
        r'''    // Algunos paneles Xtream entregan una URL exacta por episodio\..*?\n    final direct = _resolvedEpisodeDirectSource\(\n      connection\.streamServer,\n      directSource,\n    \);\n\n''',
        re.S,
    )
    text, _ = direct_block.subn('', text, count=1)
    text = text.replace('      url: direct ?? generated,', '      url: generated,', 1)

    playable = re.compile(
        r'''    final playableDirect = XtreamSeriesEpisode\._resolvedEpisodeDirectSource\(\n          activeConnection\.streamServer,\n          directSource,\n        \) \?\?\n        _seriesUrl\(activeConnection, id, extension\);''',
        re.S,
    )
    text, count = playable.subn(
        '    final playableDirect = _seriesUrl(activeConnection, id, extension);',
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit('No se pudo alinear URL de episodios')
    SERIES_SERVICE.write_text(text)


def patch_main_startup():
    text = MAIN_DART.read_text()
    text = replace_once(
        text,
        '  MediaKit.ensureInitialized();\n  runApp(const IptvPlayerApp());',
        '  if (!_androidTvBuild) {\n    MediaKit.ensureInitialized();\n  }\n  runApp(const IptvPlayerApp());',
        'no inicializar MPV en Android TV',
    )
    MAIN_DART.write_text(text)


def patch_tv_home():
    text = HOME.read_text()
    old = '''  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    return LayoutBuilder(
'''
    new = '''  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    if (_androidTvBuild) {
      if (provider.loading) {
        return const _TvHomeLoading();
      }
      if (provider.playlists.isEmpty) {
        return _TvHomeLoading(
          message: provider.error ?? 'Esperando la configuración del servicio…',
          showProgress: provider.error == null,
        );
      }
      // En TV no mostramos administración de listas, perfil, estadísticas ni
      // opciones de escritorio. El panel aprovisiona el servicio y entramos
      // directamente al contenido.
      return SourceContentScreen(playlist: provider.playlists.first);
    }

    return LayoutBuilder(
'''
    text = replace_once(text, old, new, 'home directo para TV')

    insert_before = 'class _PremiumSidebar extends StatelessWidget {'
    loading = '''class _TvHomeLoading extends StatelessWidget {
  final String? message;
  final bool showProgress;

  const _TvHomeLoading({this.message, this.showProgress = true});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05080D),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFF1677FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 58),
            ),
            const SizedBox(height: 22),
            const Text(
              'TV FULL',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            if (showProgress)
              const SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            if (showProgress) const SizedBox(height: 18),
            Text(
              message ?? 'Cargando tu servicio…',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

'''
    text = replace_once(text, insert_before, loading + insert_before, 'loading TV')
    HOME.write_text(text)


def patch_source_content_tv():
    text = SOURCE.read_text()
    marker = '''    final nativeXtream = playlist.sourceType == PlaylistSourceType.xtream;

    return Scaffold(
'''
    replacement = '''    final nativeXtream = playlist.sourceType == PlaylistSourceType.xtream;

    if (_androidTvBuild) {
      return Scaffold(
        backgroundColor: const Color(0xFF05080D),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              const Icon(Icons.live_tv_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TV FULL', style: TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(54, 44, 54, 54),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿Qué querés ver?',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _ContentCard(
                        autofocus: true,
                        icon: Icons.live_tv_rounded,
                        title: 'TV en vivo',
                        count: _buckets.count(IptvContentKind.live),
                        subtitleOverride: nativeXtream ? 'Canales' : null,
                        enabledOverride: nativeXtream ? true : null,
                        accent: const Color(0xFF1677FF),
                        onTap: () => _openKind(context, IptvContentKind.live),
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: _ContentCard(
                        icon: Icons.movie_creation_rounded,
                        title: 'Películas',
                        count: _buckets.count(IptvContentKind.movies),
                        subtitleOverride: nativeXtream ? 'Películas' : null,
                        enabledOverride: nativeXtream ? true : null,
                        accent: const Color(0xFF7B61FF),
                        onTap: () => _openKind(context, IptvContentKind.movies),
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: _ContentCard(
                        icon: Icons.video_library_rounded,
                        title: 'Series',
                        count: _buckets.count(IptvContentKind.series),
                        subtitleOverride: nativeXtream ? 'Temporadas y episodios' : null,
                        enabledOverride: nativeXtream ? true : null,
                        accent: const Color(0xFF00A7A0),
                        onTap: () => _openKind(context, IptvContentKind.series),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
'''
    text = replace_once(text, marker, replacement, 'source content TV')
    SOURCE.write_text(text)


def patch_live_catalog_tv():
    text = CHANNELS.read_text()
    old = '''          if (_androidTvBuild || constraints.maxWidth >= 900) {
            return _DesktopCatalogLayout(
'''
    new = '''          if (_androidTvBuild) {
            return _TvCatalogLayout(
              mode: mode,
              channels: channels,
              groups: visibleGroups,
              selectedGroup: _selectedGroup,
              onGroupSelected: (group) => unawaited(_selectGroup(group)),
              onPlay: (channel) =>
                  _openChannel(context, channels, channel, provider),
            );
          }

          if (constraints.maxWidth >= 900) {
            return _DesktopCatalogLayout(
'''
    text = replace_once(text, old, new, 'catalogo TV simple')

    marker = 'class _DesktopCatalogLayout extends StatelessWidget {'
    tv_layout = '''class _TvCatalogLayout extends StatelessWidget {
  final _CatalogMode mode;
  final List<Channel> channels;
  final List<String> groups;
  final String? selectedGroup;
  final ValueChanged<String?> onGroupSelected;
  final ValueChanged<Channel> onPlay;

  const _TvCatalogLayout({
    required this.mode,
    required this.channels,
    required this.groups,
    required this.selectedGroup,
    required this.onGroupSelected,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 300,
          decoration: const BoxDecoration(
            color: Color(0xFF08111D),
            border: Border(right: BorderSide(color: Colors.white12)),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 14),
            itemCount: groups.length + 1,
            itemBuilder: (context, index) {
              final group = index == 0 ? null : groups[index - 1];
              final selected = group == selectedGroup;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Material(
                  color: selected
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: .24)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    autofocus: index == 0,
                    onTap: () => onGroupSelected(group),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Text(
                        group ?? 'Todos los canales',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
                child: Text(
                  '${selectedGroup ?? mode.title} · ${channels.length}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(22, 4, 32, 28),
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Material(
                        color: const Color(0xFF0D1826),
                        borderRadius: BorderRadius.circular(13),
                        child: InkWell(
                          onTap: () => onPlay(channel),
                          borderRadius: BorderRadius.circular(13),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            child: Row(
                              children: [
                                _ChannelLogo(channel: channel),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    channel.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const Icon(Icons.play_arrow_rounded, size: 30),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

'''
    text = replace_once(text, marker, tv_layout + marker, 'widget catalogo TV')
    CHANNELS.write_text(text)


def patch_movies_tv():
    text = MOVIES.read_text()
    if 'const bool _androidTvBuild' not in text:
        text = replace_once(
            text,
            "import 'player_screen.dart';\n",
            "import 'player_screen.dart';\n\nconst bool _androidTvBuild = bool.fromEnvironment('TV_FULL_ANDROID_TV');\n",
            'const TV peliculas',
        )

    marker = '        if (width >= 760) {\n'
    tv = '''        if (_androidTvBuild) {
          return Row(
            children: [
              SizedBox(
                width: 300,
                child: _MovieCategorySidebar(
                  totalCount: visibleTotal,
                  categories: categories,
                  categoryCounts: categoryCounts,
                  selectedCategory: _category,
                  collapsed: false,
                  onToggleCollapsed: () {},
                  onCategorySelected: (value) =>
                      unawaited(_selectCategory(value)),
                ),
              ),
              Container(width: 1, color: Colors.white12),
              Expanded(child: grid()),
            ],
          );
        }

'''
    text = replace_once(text, marker, tv + marker, 'layout TV peliculas')
    MOVIES.write_text(text)


def patch_series_tv():
    text = SERIES_SCREEN.read_text()
    if 'const bool _androidTvBuild' not in text:
        text = replace_once(
            text,
            "import 'player_screen.dart';\n",
            "import 'player_screen.dart';\n\nconst bool _androidTvBuild = bool.fromEnvironment('TV_FULL_ANDROID_TV');\n",
            'const TV series',
        )

    marker = '        if (width >= 760) {\n'
    tv = '''        if (_androidTvBuild) {
          return Row(
            children: [
              SizedBox(
                width: 300,
                child: _SeriesCategorySidebar(
                  totalCount: visibleTotal,
                  categories: categories,
                  categoryCounts: categoryCounts,
                  selectedCategory: _category,
                  collapsed: false,
                  onToggleCollapsed: () {},
                  onCategorySelected: (value) =>
                      unawaited(_selectCategory(value)),
                ),
              ),
              Container(width: 1, color: Colors.white12),
              Expanded(child: grid()),
            ],
          );
        }

'''
    text = replace_once(text, marker, tv + marker, 'layout TV series')
    SERIES_SCREEN.write_text(text)


def patch_package_version():
    gradle = GRADLE.read_text()
    gradle = gradle.replace(
        'applicationId = "com.tvfull.pro.tv.v8media3"',
        'applicationId = "com.tvfull.pro.tv.v9clean"',
    )
    GRADLE.write_text(gradle)

    manifest = MANIFEST.read_text().replace(
        'TV FULL PRO V8 MEDIA3',
        'TV FULL',
    )
    MANIFEST.write_text(manifest)

    if REMOTE.exists():
        text = REMOTE.read_text()
        text = re.sub(
            r'1\.0\.0\+1-android-tv-[A-Za-z0-9._-]+',
            '1.0.0+1-android-tv-clean-v9',
            text,
        )
        REMOTE.write_text(text)


def validate():
    checks = {
        MAIN_KT: [
            'Sin timeout artificial',
            '"seekTo" ->',
            'pixelWidthHeightRatio',
        ],
        HOME: ['return SourceContentScreen(playlist: provider.playlists.first);'],
        SOURCE: ["title: 'TV en vivo'", "title: 'Películas'", "title: 'Series'"],
        CHANNELS: ['class _TvCatalogLayout extends StatelessWidget'],
        LIVE_PLAYER: ['Timer? _overlayTimer;', 'pixelWidthHeightRatio'],
        VOD_PLAYER: ['Chrome/96.0.4664.18'],
        GRADLE: ['com.tvfull.pro.tv.v9clean'],
    }
    for path, markers in checks.items():
        text = path.read_text()
        for marker in markers:
            if marker not in text:
                raise SystemExit(f'Validacion V9 fallo {path}: {marker}')


patch_native_bridge()
patch_player_ua_and_live_overlay()
patch_xtream_vod_urls()
patch_xtream_series_urls()
patch_main_startup()
patch_tv_home()
patch_source_content_tv()
patch_live_catalog_tv()
patch_movies_tv()
patch_series_tv()
patch_package_version()
validate()
print('V9 clean TV aplicado: playback alineado, sin timeouts artificiales y UI TV simplificada.')
