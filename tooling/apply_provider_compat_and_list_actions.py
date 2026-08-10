from pathlib import Path

FILES = {
    'channel': Path('lib/models/channel.dart'),
    'compat': Path('lib/services/server_compatibility_service.dart'),
    'player': Path('lib/screens/player_screen.dart'),
    'provider': Path('lib/providers/iptv_provider.dart'),
    'home': Path('lib/screens/home_screen.dart'),
}


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Pattern not found: {label}')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Channel: allow true native HTTP without injecting a default User-Agent.
# ---------------------------------------------------------------------------
path = FILES['channel']
text = path.read_text()
text = replace_once(
    text,
    '  Map<String, String> resolvedHttpHeaders(String defaultUserAgent) {\n',
    '  Map<String, String> resolvedHttpHeaders(\n'
    '    String defaultUserAgent, {\n'
    '    bool includeDefaultUserAgent = true,\n'
    '  }) {\n',
    'channel header signature',
)
text = replace_once(
    text,
    "    put('User-Agent', httpUserAgent ?? defaultUserAgent);\n",
    "    if (httpUserAgent != null) {\n"
    "      put('User-Agent', httpUserAgent!);\n"
    "    } else if (includeDefaultUserAgent) {\n"
    "      put('User-Agent', defaultUserAgent);\n"
    "    }\n",
    'channel default user agent',
)
path.write_text(text)

# ---------------------------------------------------------------------------
# Compatibility service: native HTTP + Xtream HLS fallback, persisted by host.
# ---------------------------------------------------------------------------
path = FILES['compat']
text = path.read_text()
text = replace_once(
    text,
    'enum ServerCompatibilityMode {\n  direct,\n  compatible,\n  liveRecovery,\n  advanced,\n}\n',
    'enum ServerCompatibilityMode {\n'
    '  direct,\n'
    '  nativeHttp,\n'
    '  compatible,\n'
    '  liveRecovery,\n'
    '  advanced,\n'
    '  xtreamHls,\n'
    '}\n',
    'compat enum',
)
text = replace_once(
    text,
    "        ServerCompatibilityMode.direct => 'Directo',\n        ServerCompatibilityMode.compatible => 'Compatible',\n        ServerCompatibilityMode.liveRecovery => 'Live Recovery',\n        ServerCompatibilityMode.advanced => 'Compatibilidad avanzada',\n",
    "        ServerCompatibilityMode.direct => 'Directo',\n"
    "        ServerCompatibilityMode.nativeHttp => 'HTTP nativo',\n"
    "        ServerCompatibilityMode.compatible => 'Compatible',\n"
    "        ServerCompatibilityMode.liveRecovery => 'Live Recovery',\n"
    "        ServerCompatibilityMode.advanced => 'Compatibilidad avanzada',\n"
    "        ServerCompatibilityMode.xtreamHls => 'Xtream HLS',\n",
    'compat labels',
)
text = replace_once(
    text,
    '  int directFailures;\n  int compatibleFailures;\n  int liveRecoveryFailures;\n  int advancedFailures;\n',
    '  int directFailures;\n'
    '  int nativeHttpFailures;\n'
    '  int compatibleFailures;\n'
    '  int liveRecoveryFailures;\n'
    '  int advancedFailures;\n'
    '  int xtreamHlsFailures;\n',
    'compat fields',
)
text = replace_once(
    text,
    '    this.directFailures = 0,\n    this.compatibleFailures = 0,\n    this.liveRecoveryFailures = 0,\n    this.advancedFailures = 0,\n',
    '    this.directFailures = 0,\n'
    '    this.nativeHttpFailures = 0,\n'
    '    this.compatibleFailures = 0,\n'
    '    this.liveRecoveryFailures = 0,\n'
    '    this.advancedFailures = 0,\n'
    '    this.xtreamHlsFailures = 0,\n',
    'compat constructor',
)
text = replace_once(
    text,
    "        'directFailures': directFailures,\n        'compatibleFailures': compatibleFailures,\n        'liveRecoveryFailures': liveRecoveryFailures,\n        'advancedFailures': advancedFailures,\n",
    "        'directFailures': directFailures,\n"
    "        'nativeHttpFailures': nativeHttpFailures,\n"
    "        'compatibleFailures': compatibleFailures,\n"
    "        'liveRecoveryFailures': liveRecoveryFailures,\n"
    "        'advancedFailures': advancedFailures,\n"
    "        'xtreamHlsFailures': xtreamHlsFailures,\n",
    'compat json',
)
text = replace_once(
    text,
    "      directFailures: (json['directFailures'] as num?)?.toInt() ?? 0,\n      compatibleFailures: (json['compatibleFailures'] as num?)?.toInt() ?? 0,\n      liveRecoveryFailures:\n          (json['liveRecoveryFailures'] as num?)?.toInt() ?? 0,\n      advancedFailures: (json['advancedFailures'] as num?)?.toInt() ?? 0,\n",
    "      directFailures: (json['directFailures'] as num?)?.toInt() ?? 0,\n"
    "      nativeHttpFailures:\n          (json['nativeHttpFailures'] as num?)?.toInt() ?? 0,\n"
    "      compatibleFailures: (json['compatibleFailures'] as num?)?.toInt() ?? 0,\n"
    "      liveRecoveryFailures:\n          (json['liveRecoveryFailures'] as num?)?.toInt() ?? 0,\n"
    "      advancedFailures: (json['advancedFailures'] as num?)?.toInt() ?? 0,\n"
    "      xtreamHlsFailures:\n          (json['xtreamHlsFailures'] as num?)?.toInt() ?? 0,\n",
    'compat from json',
)
old_plan = '''  List<ServerCompatibilityMode> planFor(ServerCompatibilityMode preferred) {
    return switch (preferred) {
      ServerCompatibilityMode.direct => const [
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.liveRecovery,
          ServerCompatibilityMode.advanced,
        ],
      ServerCompatibilityMode.compatible => const [
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.advanced,
          ServerCompatibilityMode.liveRecovery,
        ],
      ServerCompatibilityMode.liveRecovery => const [
          ServerCompatibilityMode.liveRecovery,
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.advanced,
          ServerCompatibilityMode.compatible,
        ],
      ServerCompatibilityMode.advanced => const [
          ServerCompatibilityMode.advanced,
          ServerCompatibilityMode.liveRecovery,
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.direct,
        ],
    };
  }
'''
new_plan = '''  List<ServerCompatibilityMode> planFor(ServerCompatibilityMode preferred) {
    return switch (preferred) {
      ServerCompatibilityMode.direct => const [
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.nativeHttp,
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.liveRecovery,
          ServerCompatibilityMode.advanced,
          ServerCompatibilityMode.xtreamHls,
        ],
      ServerCompatibilityMode.nativeHttp => const [
          ServerCompatibilityMode.nativeHttp,
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.liveRecovery,
          ServerCompatibilityMode.advanced,
          ServerCompatibilityMode.xtreamHls,
        ],
      ServerCompatibilityMode.compatible => const [
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.nativeHttp,
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.advanced,
          ServerCompatibilityMode.liveRecovery,
          ServerCompatibilityMode.xtreamHls,
        ],
      ServerCompatibilityMode.liveRecovery => const [
          ServerCompatibilityMode.liveRecovery,
          ServerCompatibilityMode.nativeHttp,
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.advanced,
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.xtreamHls,
        ],
      ServerCompatibilityMode.advanced => const [
          ServerCompatibilityMode.advanced,
          ServerCompatibilityMode.nativeHttp,
          ServerCompatibilityMode.liveRecovery,
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.xtreamHls,
        ],
      ServerCompatibilityMode.xtreamHls => const [
          ServerCompatibilityMode.xtreamHls,
          ServerCompatibilityMode.nativeHttp,
          ServerCompatibilityMode.direct,
          ServerCompatibilityMode.compatible,
          ServerCompatibilityMode.liveRecovery,
          ServerCompatibilityMode.advanced,
        ],
    };
  }
'''
text = replace_once(text, old_plan, new_plan, 'compat plan')
text = replace_once(
    text,
    '''      case ServerCompatibilityMode.direct:
        profile.directFailures++;
        break;
      case ServerCompatibilityMode.compatible:
        profile.compatibleFailures++;
        break;
      case ServerCompatibilityMode.liveRecovery:
        profile.liveRecoveryFailures++;
        break;
      case ServerCompatibilityMode.advanced:
        profile.advancedFailures++;
        break;
''',
    '''      case ServerCompatibilityMode.direct:
        profile.directFailures++;
        break;
      case ServerCompatibilityMode.nativeHttp:
        profile.nativeHttpFailures++;
        break;
      case ServerCompatibilityMode.compatible:
        profile.compatibleFailures++;
        break;
      case ServerCompatibilityMode.liveRecovery:
        profile.liveRecoveryFailures++;
        break;
      case ServerCompatibilityMode.advanced:
        profile.advancedFailures++;
        break;
      case ServerCompatibilityMode.xtreamHls:
        profile.xtreamHlsFailures++;
        break;
''',
    'compat failure switch',
)
path.write_text(text)

# ---------------------------------------------------------------------------
# Player: use native HTTP as fallback and HLS variant only for Xtream live TS.
# ---------------------------------------------------------------------------
path = FILES['player']
text = path.read_text()
text = replace_once(
    text,
    '      _compatibilityPlan = _compatibility.planFor(profile.preferredMode);\n',
    '''      final learnedPlan = _compatibility.planFor(profile.preferredMode);
      _compatibilityPlan = _looksLikeXtreamLiveTs(channelUrl)
          ? learnedPlan
          : learnedPlan
              .where((mode) => mode != ServerCompatibilityMode.xtreamHls)
              .toList(growable: false);
''',
    'player learned plan',
)
text = replace_once(
    text,
    '        final isLiveHls = widget.isLiveContent && _looksLikeHls(channel.url);\n',
    '''        final effectiveUrl = _playbackUrlForMode(channel.url);
        final isLiveHls = widget.isLiveContent && _looksLikeHls(effectiveUrl);
''',
    'player hls detection',
)
old_headers = '''      final channel = widget.playlist[_currentIndex];
      final fallbackUserAgent =
          _compatibilityMode == ServerCompatibilityMode.compatible ||
                  _compatibilityMode == ServerCompatibilityMode.advanced
              ? _legacyVlcUserAgent
              : _defaultUserAgent;
      final headers = channel.resolvedHttpHeaders(fallbackUserAgent);

      final openFuture = _player.open(Media(channel.url, httpHeaders: headers));
'''
new_headers = '''      final channel = widget.playlist[_currentIndex];
      final fallbackUserAgent =
          _compatibilityMode == ServerCompatibilityMode.compatible ||
                  _compatibilityMode == ServerCompatibilityMode.advanced
              ? _legacyVlcUserAgent
              : _defaultUserAgent;
      final nativeHttp =
          _compatibilityMode == ServerCompatibilityMode.nativeHttp ||
              _compatibilityMode == ServerCompatibilityMode.xtreamHls;
      final headers = channel.resolvedHttpHeaders(
        fallbackUserAgent,
        includeDefaultUserAgent: !nativeHttp,
      );
      final playbackUrl = _playbackUrlForMode(channel.url);
      final media = headers.isEmpty
          ? Media(playbackUrl)
          : Media(playbackUrl, httpHeaders: headers);

      final openFuture = _player.open(media);
'''
text = replace_once(text, old_headers, new_headers, 'player native headers')
marker = '''  bool _looksLikeHls(String url) {
    final value = url.toLowerCase();
    final format = _containerFormat?.toLowerCase() ?? '';
    return value.contains('.m3u8') ||
        format.contains('hls') ||
        format.contains('applehttp');
  }
'''
helpers = marker + '''
  bool _looksLikeXtreamLiveTs(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path.contains('/live/') && path.endsWith('.ts');
  }

  String _playbackUrlForMode(String originalUrl) {
    if (_compatibilityMode != ServerCompatibilityMode.xtreamHls ||
        !_looksLikeXtreamLiveTs(originalUrl)) {
      return originalUrl;
    }

    final uri = Uri.tryParse(originalUrl);
    if (uri == null) return originalUrl;
    final path = uri.path;
    final lower = path.toLowerCase();
    if (!lower.endsWith('.ts')) return originalUrl;
    final hlsPath = '${path.substring(0, path.length - 3)}.m3u8';
    return uri.replace(path: hlsPath).toString();
  }
'''
text = replace_once(text, marker, helpers, 'player xtream helpers')
text = replace_once(
    text,
    '''      final recoveryMode =
          _compatibilityMode == ServerCompatibilityMode.compatible ||
                  _compatibilityMode == ServerCompatibilityMode.advanced
              ? ServerCompatibilityMode.advanced
              : ServerCompatibilityMode.liveRecovery;
''',
    '''      final recoveryMode =
          _compatibilityMode == ServerCompatibilityMode.nativeHttp ||
                  _compatibilityMode == ServerCompatibilityMode.xtreamHls
              ? _compatibilityMode
              : _compatibilityMode == ServerCompatibilityMode.compatible ||
                      _compatibilityMode == ServerCompatibilityMode.advanced
                  ? ServerCompatibilityMode.advanced
                  : ServerCompatibilityMode.liveRecovery;
''',
    'player eof recovery',
)
text = replace_once(
    text,
    '''    final ServerCompatibilityMode? target = switch (previous) {
      ServerCompatibilityMode.direct => ServerCompatibilityMode.liveRecovery,
      ServerCompatibilityMode.compatible => ServerCompatibilityMode.advanced,
      ServerCompatibilityMode.liveRecovery => ServerCompatibilityMode.advanced,
      ServerCompatibilityMode.advanced => null,
    };
''',
    '''    final ServerCompatibilityMode? target = switch (previous) {
      ServerCompatibilityMode.direct => ServerCompatibilityMode.liveRecovery,
      ServerCompatibilityMode.nativeHttp => null,
      ServerCompatibilityMode.compatible => ServerCompatibilityMode.advanced,
      ServerCompatibilityMode.liveRecovery => ServerCompatibilityMode.advanced,
      ServerCompatibilityMode.advanced => null,
      ServerCompatibilityMode.xtreamHls => null,
    };
''',
    'player recovery switch',
)
path.write_text(text)

# ---------------------------------------------------------------------------
# Provider: edit remote sources in-place and rename local sources.
# ---------------------------------------------------------------------------
path = FILES['provider']
text = path.read_text()
insert_before = '''  Future<void> addPlaylistFromContent(
      String name, String path, String content) async {
'''
provider_methods = '''  Future<void> renamePlaylist(String playlistId, String name) async {
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
      final content = await M3uFetcher.fetch(url);
      final channels = await compute(parseM3uInBackground, content);
      if (channels.isEmpty) {
        throw Exception('La lista M3U no contiene canales reproducibles.');
      }
      final current = _playlists[index];
      final updated = current.copyWith(
        name: name.trim().isEmpty ? current.name : name.trim(),
        source: url,
        isRemote: true,
        channels: channels,
        lastUpdated: DateTime.now(),
        sourceType: PlaylistSourceType.m3u,
      );
      _playlists = [
        ..._playlists.take(index),
        updated,
        ..._playlists.skip(index + 1),
      ];
      await _storage.savePlaylists(_playlists);
      _error = null;
    } catch (e) {
      _error = e.toString();
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
      final content = await M3uFetcher.fetch(connection.playlistUrl);
      final channels = await compute(parseM3uInBackground, content);
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
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

'''
text = replace_once(text, insert_before, provider_methods + insert_before, 'provider edit methods')
path.write_text(text)

# ---------------------------------------------------------------------------
# Home: expose Edit + Update menu actions.
# ---------------------------------------------------------------------------
path = FILES['home']
text = path.read_text()
text = replace_once(
    text,
    "import 'add_source_screen.dart';\n",
    "import 'add_source_screen.dart';\nimport 'edit_source_screen.dart';\n",
    'home edit import',
)
card_marker = '''  @override
  Widget build(BuildContext context) {
    final provider = context.read<IptvProvider>();
'''
card_methods = '''  Future<void> _editPlaylist(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditSourceScreen(playlist: playlist),
      ),
    );
  }

  Future<void> _refreshPlaylist(BuildContext context) async {
    final provider = context.read<IptvProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await provider.refreshPlaylist(playlist.id);
    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            provider.error == null
                ? 'Lista actualizada correctamente.'
                : 'No se pudo actualizar: ${provider.error}',
          ),
        ),
      );
  }

'''
# Insert only inside _PlaylistCard: use the occurrence after _openPlaylist's closing block.
needle = '''    await navigator.push(
      MaterialPageRoute(
        builder: (_) => SourceContentScreen(playlist: playlist),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<IptvProvider>();
'''
replacement = '''    await navigator.push(
      MaterialPageRoute(
        builder: (_) => SourceContentScreen(playlist: playlist),
      ),
    );
  }

''' + card_methods + '''  @override
  Widget build(BuildContext context) {
    final provider = context.read<IptvProvider>();
'''
text = replace_once(text, needle, replacement, 'home card methods')
old_menu = '''              PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: (value) {
                  if (value == 'delete') {
                    provider.removePlaylist(playlist.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline),
                        SizedBox(width: 10),
                        Text('Eliminar lista'),
                      ],
                    ),
                  ),
                ],
              ),
'''
new_menu = '''              PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: (value) async {
                  switch (value) {
                    case 'edit':
                      await _editPlaylist(context);
                      break;
                    case 'refresh':
                      await _refreshPlaylist(context);
                      break;
                    case 'delete':
                      await provider.removePlaylist(playlist.id);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined),
                        SizedBox(width: 10),
                        Text('Editar lista'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'refresh',
                    enabled: playlist.isRemote,
                    child: const Row(
                      children: [
                        Icon(Icons.refresh_rounded),
                        SizedBox(width: 10),
                        Text('Actualizar lista'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline),
                        SizedBox(width: 10),
                        Text('Eliminar lista'),
                      ],
                    ),
                  ),
                ],
              ),
'''
text = replace_once(text, old_menu, new_menu, 'home menu')
path.write_text(text)

print('Patch applied successfully')
