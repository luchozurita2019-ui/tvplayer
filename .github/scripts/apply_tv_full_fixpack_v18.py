from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f"No se encontró el bloque esperado: {label}")
    return text.replace(old, new, 1)


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
pubspec_path = ROOT / "pubspec.yaml"
pubspec = pubspec_path.read_text(encoding="utf-8")
pubspec = replace_once(pubspec, "version: 1.2.5+17", "version: 1.2.6+18", "version")
pubspec = pubspec.replace(
    "# TV FULL PRO 1.2.5+17 premium-neon-ui marker.",
    "# TV FULL PRO 1.2.6+18 remote-focus-scroll-update-fixes marker.",
)
pubspec_path.write_text(pubspec, encoding="utf-8")


# ---------------------------------------------------------------------------
# Reliable update polling: retry failures and recheck every five minutes.
# ---------------------------------------------------------------------------
write(
    "lib/services/app_update_service.dart",
    r'''import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'app_version_service.dart';

class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final String downloaderUrl;

  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloaderUrl,
  });

  String get downloaderCode {
    final uri = Uri.tryParse(downloaderUrl);
    if (uri == null || uri.pathSegments.isEmpty) return '';
    final last = uri.pathSegments.last.trim();
    return RegExp(r'^\d+$').hasMatch(last) ? last : '';
  }
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static final Uri _endpoint = Uri.parse(
    'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-update',
  );

  bool _checked = false;
  bool _checking = false;
  DateTime? _nextAllowedCheckAt;
  AppUpdateInfo? _availableUpdate;

  bool get checked => _checked;
  bool get checking => _checking;
  AppUpdateInfo? get availableUpdate => _availableUpdate;
  bool get hasUpdate => _availableUpdate != null;

  Future<void> checkOnce({bool force = false}) async {
    if (_checking) return;
    final now = DateTime.now();
    final next = _nextAllowedCheckAt;
    if (!force && next != null && now.isBefore(next)) return;

    // Si la red falla, se permite otro intento a los 30 s. Una respuesta válida
    // se vuelve a consultar a los 5 min para detectar updates sin reiniciar la TV.
    _checking = true;
    _nextAllowedCheckAt = now.add(const Duration(seconds: 30));
    try {
      final installed = await AppVersionService.instance.current;
      final response = await http.get(_endpoint).timeout(
            const Duration(seconds: 4),
          );
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) return;

      final enabled = decoded['update_available'] == true;
      final versionCode = _toInt(decoded['version_code']);
      final versionName = '${decoded['version_name'] ?? ''}'.trim();
      final downloaderUrl = '${decoded['downloader_url'] ?? ''}'.trim();
      final uri = Uri.tryParse(downloaderUrl);
      final validUrl = uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          (uri.host == 'aftv.news' || uri.host == 'www.aftv.news');

      _checked = true;
      _nextAllowedCheckAt = DateTime.now().add(const Duration(minutes: 5));
      if (enabled &&
          versionCode > installed.versionCode &&
          versionName.isNotEmpty &&
          validUrl) {
        _availableUpdate = AppUpdateInfo(
          versionCode: versionCode,
          versionName: versionName,
          downloaderUrl: downloaderUrl,
        );
      } else {
        _availableUpdate = null;
      }
    } catch (_) {
      // Nunca bloquea la TV; el próximo intento queda habilitado rápidamente.
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<bool> openUpdate() async {
    final update = _availableUpdate;
    if (update == null) return false;
    final uri = Uri.tryParse(update.downloaderUrl);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
''',
)


# ---------------------------------------------------------------------------
# Home: recheck update every 5 minutes while open and on resume.
# ---------------------------------------------------------------------------
home_path = ROOT / "lib/screens/home_screen.dart"
home = home_path.read_text(encoding="utf-8")
home = replace_once(
    home,
    """        if (current.playlists.isEmpty || _tick % 10 == 0) {\n          unawaited(current.syncRemoteServices());\n        }\n""",
    """        if (current.playlists.isEmpty || _tick % 10 == 0) {\n          unawaited(current.syncRemoteServices());\n        }\n        if (_tick % 100 == 0) {\n          unawaited(AppUpdateService.instance.checkOnce());\n        }\n""",
    "periodic update check",
)
home = replace_once(
    home,
    """    final provider = context.read<IptvProvider>();\n    if (!provider.remoteSyncing) unawaited(provider.syncRemoteServices());\n""",
    """    final provider = context.read<IptvProvider>();\n    if (!provider.remoteSyncing) unawaited(provider.syncRemoteServices());\n    unawaited(AppUpdateService.instance.checkOnce());\n""",
    "resume update check",
)
home_path.write_text(home, encoding="utf-8")


# ---------------------------------------------------------------------------
# Catalog scroll/focus reset helpers.
# ---------------------------------------------------------------------------
def patch_catalog(path: str, kind: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    helper = """  void _resetScroll(ScrollController controller) {\n    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (!mounted || !controller.hasClients) return;\n      controller.jumpTo(0);\n    });\n  }\n\n  void _resetCatalogScroll() => _resetScroll(_catalogScrollController);\n  void _resetSearchScroll() => _resetScroll(_searchScrollController);\n\n"""
    text = replace_once(text, "  void _openSearch() {\n", helper + "  void _openSearch() {\n", f"{kind} scroll helpers")
    text = replace_once(
        text,
        """    setState(() => _searchOpen = true);\n    WidgetsBinding.instance.addPostFrameCallback((_) {\n""",
        """    setState(() => _searchOpen = true);\n    _resetSearchScroll();\n    WidgetsBinding.instance.addPostFrameCallback((_) {\n""",
        f"{kind} open search reset",
    )
    text = replace_once(
        text,
        """    setState(() {\n      _query = '';\n      _searchOpen = false;\n    });\n""",
        """    setState(() {\n      _query = '';\n      _searchOpen = false;\n    });\n    _resetCatalogScroll();\n""",
        f"{kind} close search reset",
    )
    text = replace_once(
        text,
        """    _searchDebounce = Timer(const Duration(milliseconds: 120), () {\n      if (mounted && value != _query) setState(() => _query = value);\n    });\n""",
        """    _searchDebounce = Timer(const Duration(milliseconds: 120), () {\n      if (mounted && value != _query) {\n        setState(() => _query = value);\n        _resetSearchScroll();\n      }\n    });\n""",
        f"{kind} search query reset",
    )
    if kind == "live":
        text = replace_once(
            text,
            """                  onTap: () {\n                    if (_searchOpen) _closeSearch();\n                    setState(() => _category = category);\n                  },\n""",
            """                  onTap: () {\n                    if (_searchOpen) _closeSearch();\n                    setState(() => _category = category);\n                    _resetCatalogScroll();\n                  },\n""",
            "live category reset",
        )
        text = replace_once(
            text,
            """                    : ListView.builder(\n                        controller: _searchOpen\n""",
            """                    : ListView.builder(\n                        key: ValueKey<String>(\n                          _searchOpen\n                              ? 'live-search:$_query'\n                              : 'live-category:${_category ?? 'all'}',\n                        ),\n                        controller: _searchOpen\n""",
            "live list key",
        )
    else:
        label = "movies" if kind == "movies" else "series"
        text = replace_once(
            text,
            """                  onTap: () {\n                    if (_searchOpen) _closeSearch();\n                    setState(() => _category = value);\n                  },\n""",
            """                  onTap: () {\n                    if (_searchOpen) _closeSearch();\n                    setState(() => _category = value);\n                    _resetCatalogScroll();\n                  },\n""",
            f"{kind} category reset",
        )
        text = replace_once(
            text,
            """                          return GridView.builder(\n                            controller: _searchOpen\n""",
            f"""                          return GridView.builder(\n                            key: ValueKey<String>(\n                              _searchOpen\n                                  ? '{label}-search:$_query'\n                                  : '{label}-category:${{_category ?? 'all'}}',\n                            ),\n                            controller: _searchOpen\n""",
            f"{kind} grid key",
        )
    p.write_text(text, encoding="utf-8")


patch_catalog("lib/screens/xtream_live_screen.dart", "live")
patch_catalog("lib/screens/xtream_movies_screen.dart", "movies")
patch_catalog("lib/screens/xtream_series_screen.dart", "series")


# ---------------------------------------------------------------------------
# Series: visible focus/zoom on episodes and reset episode list per season.
# ---------------------------------------------------------------------------
series_path = ROOT / "lib/screens/xtream_series_screen.dart"
series = series_path.read_text(encoding="utf-8")
series = replace_once(
    series,
    """                                return TvCatalogCategoryRow(\n                                  label: 'Temporada $season',\n                                  selected: selected,\n                                  onTap: () => setState(() => _season = season),\n                                );\n""",
    """                                return TvCatalogCategoryRow(\n                                  label: 'Temporada $season',\n                                  selected: selected,\n                                  onTap: () => setState(() => _season = season),\n                                );\n""",
    "series season row",
)
series = replace_once(
    series,
    """                            child: ListView.builder(\n                              itemCount: episodes.length,\n""",
    """                            child: ListView.builder(\n                              key: ValueKey<int>(_season),\n                              itemCount: episodes.length,\n""",
    "episode list season key",
)
old_episode = """                                  child: ListTile(\n                                    autofocus: index == 0,\n                                    focusColor: const Color(0xFF12324A),\n                                    minTileHeight: 58,\n                                    shape: RoundedRectangleBorder(\n                                      borderRadius: BorderRadius.circular(10),\n                                    ),\n                                    tileColor: const Color(0xFF0B151F),\n                                    leading: SizedBox(\n                                      width: 42,\n                                      child: Text(\n                                        episode.number > 0\n                                            ? 'E${episode.number.toString().padLeft(2, '0')}'\n                                            : '▶',\n                                        style: const TextStyle(\n                                          color: Color(0xFF58B9FF),\n                                          fontWeight: FontWeight.w900,\n                                        ),\n                                      ),\n                                    ),\n                                    title: Text(\n                                      episode.title,\n                                      maxLines: 1,\n                                      overflow: TextOverflow.ellipsis,\n                                      style: const TextStyle(\n                                        fontWeight: FontWeight.w700,\n                                      ),\n                                    ),\n                                    subtitle: (episode.duration ?? '').isEmpty\n                                        ? null\n                                        : Text(\n                                            episode.duration!,\n                                            style: const TextStyle(\n                                              color: Colors.white38,\n                                            ),\n                                          ),\n                                    trailing: const Icon(\n                                      Icons.play_arrow_rounded,\n                                    ),\n                                    onTap: () =>\n                                        _play(context, episode.channel),\n                                  ),\n"""
new_episode = """                                  child: _EpisodeFocusTile(\n                                    episode: episode,\n                                    autofocus: index == 0,\n                                    onTap: () =>\n                                        _play(context, episode.channel),\n                                  ),\n"""
series = replace_once(series, old_episode, new_episode, "episode focus tile usage")
insert_at = series.find("class _SeriesCard extends StatefulWidget {")
if insert_at < 0:
    raise RuntimeError("No se encontró inserción de EpisodeFocusTile")
episode_widget = r'''class _EpisodeFocusTile extends StatefulWidget {
  final _EpisodeItem episode;
  final bool autofocus;
  final VoidCallback onTap;

  const _EpisodeFocusTile({
    required this.episode,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_EpisodeFocusTile> createState() => _EpisodeFocusTileState();
}

class _EpisodeFocusTileState extends State<_EpisodeFocusTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return AnimatedScale(
      scale: _focused ? (lowRam ? 1.018 : 1.035) : 1,
      duration: Duration(milliseconds: lowRam ? 80 : 130),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: Duration(milliseconds: lowRam ? 80 : 130),
        decoration: tvFullGlassDecoration(
          focused: _focused,
          radius: 12,
          accent: tvFullCyan,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            child: SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(
                        widget.episode.number > 0
                            ? 'E${widget.episode.number.toString().padLeft(2, '0')}'
                            : '▶',
                        style: TextStyle(
                          color: _focused ? tvFullCyan : const Color(0xFF58B9FF),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.episode.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  _focused ? FontWeight.w900 : FontWeight.w700,
                            ),
                          ),
                          if ((widget.episode.duration ?? '').isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              widget.episode.duration!,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.play_arrow_rounded,
                      color: _focused ? tvFullCyan : Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

'''
series = series[:insert_at] + episode_widget + series[insert_at:]
series_path.write_text(series, encoding="utf-8")


# ---------------------------------------------------------------------------
# LIVE error card: focus Retry automatically and make ENTER/OK deterministic.
# ---------------------------------------------------------------------------
live_player_path = ROOT / "lib/screens/android_media3_texture_player_screen.dart"
live_player = live_player_path.read_text(encoding="utf-8")
live_player = replace_once(
    live_player,
    """  final FocusNode _channelListFocus = FocusNode(\n    debugLabel: 'tvfull-pro-live-selected-channel',\n  );\n""",
    """  final FocusNode _channelListFocus = FocusNode(\n    debugLabel: 'tvfull-pro-live-selected-channel',\n  );\n  final FocusNode _retryFocus = FocusNode(debugLabel: 'tvfull-pro-live-retry');\n  final FocusNode _errorChannelListFocus =\n      FocusNode(debugLabel: 'tvfull-pro-live-error-channel-list');\n""",
    "live error focus nodes",
)
live_player = replace_once(
    live_player,
    """    setState(() {\n      _buffering = false;\n      _friendlyError = friendly;\n      _overlayVisible = false;\n      _channelListVisible = false;\n      _audioTracks = const <_LiveAudioTrack>[];\n    });\n  }\n""",
    """    setState(() {\n      _buffering = false;\n      _friendlyError = friendly;\n      _overlayVisible = false;\n      _channelListVisible = false;\n      _audioTracks = const <_LiveAudioTrack>[];\n    });\n    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (mounted && _retryFocus.canRequestFocus) _retryFocus.requestFocus();\n    });\n  }\n""",
    "focus retry after error",
)
key_anchor = """    final isBack =\n        key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape;\n\n"""
error_keys = """    if (_friendlyError != null) {\n      if (isBack) return KeyEventResult.ignored;\n      if (key == LogicalKeyboardKey.arrowLeft ||\n          key == LogicalKeyboardKey.arrowUp) {\n        _retryFocus.requestFocus();\n        return KeyEventResult.handled;\n      }\n      if (key == LogicalKeyboardKey.arrowRight ||\n          key == LogicalKeyboardKey.arrowDown) {\n        _errorChannelListFocus.requestFocus();\n        return KeyEventResult.handled;\n      }\n      if (key == LogicalKeyboardKey.select ||\n          key == LogicalKeyboardKey.enter ||\n          key == LogicalKeyboardKey.numpadEnter) {\n        if (_errorChannelListFocus.hasFocus) {\n          _openChannelList();\n        } else {\n          unawaited(_prepareCurrent());\n        }\n        return KeyEventResult.handled;\n      }\n    }\n\n"""
live_player = replace_once(live_player, key_anchor, key_anchor + error_keys, "error key handling")
live_player = replace_once(
    live_player,
    """    _channelScrollController.dispose();\n    _channelListFocus.dispose();\n    _rootFocus.dispose();\n""",
    """    _channelScrollController.dispose();\n    _channelListFocus.dispose();\n    _retryFocus.dispose();\n    _errorChannelListFocus.dispose();\n    _rootFocus.dispose();\n""",
    "dispose error focus nodes",
)
old_buttons = """                  FilledButton(\n                    autofocus: true,\n                    onPressed: () => unawaited(_prepareCurrent()),\n                    child: const Text('Reintentar'),\n                  ),\n                  const SizedBox(width: 12),\n                  OutlinedButton(\n                    onPressed: _openChannelList,\n                    child: const Text('Lista de canales'),\n                  ),\n"""
new_buttons = """                  _LiveErrorButton(\n                    focusNode: _retryFocus,\n                    autofocus: true,\n                    filled: true,\n                    label: 'Reintentar',\n                    icon: Icons.refresh_rounded,\n                    onTap: () => unawaited(_prepareCurrent()),\n                  ),\n                  const SizedBox(width: 12),\n                  _LiveErrorButton(\n                    focusNode: _errorChannelListFocus,\n                    label: 'Lista de canales',\n                    icon: Icons.list_rounded,\n                    onTap: _openChannelList,\n                  ),\n"""
live_player = replace_once(live_player, old_buttons, new_buttons, "error action buttons")
insert_live = live_player.find("class _LiveAudioTrack {")
if insert_live < 0:
    raise RuntimeError("No se encontró inserción LiveErrorButton")
error_button_widget = r'''class _LiveErrorButton extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;
  final bool filled;

  const _LiveErrorButton({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.onTap,
    this.autofocus = false,
    this.filled = false,
  });

  @override
  State<_LiveErrorButton> createState() => _LiveErrorButtonState();
}

class _LiveErrorButtonState extends State<_LiveErrorButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF58B9FF);
    return AnimatedScale(
      scale: _focused ? 1.07 : 1,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        decoration: BoxDecoration(
          color: widget.filled
              ? const Color(0xFF1677FF).withValues(alpha: _focused ? .42 : .28)
              : const Color(0xFF101A26),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: _focused ? accent : Colors.white24,
            width: _focused ? 2 : 1,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: .28),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 19, color: _focused ? accent : Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontWeight: _focused ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

'''
live_player = live_player[:insert_live] + error_button_widget + live_player[insert_live:]
live_player_path.write_text(live_player, encoding="utf-8")

print("TV FULL PRO 1.2.6+18 fixpack aplicado")
