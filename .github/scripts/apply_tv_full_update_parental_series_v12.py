from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'marker not found: {label}')
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'regex marker not found: {label} ({count})')
    return updated


# ---------------------------------------------------------------------------
# 1) Lightweight update service: one GET per app process, no polling/download.
# ---------------------------------------------------------------------------
update_service = Path('lib/services/app_update_service.dart')
update_service.write_text(r'''import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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

  static const int currentVersionCode = 12;
  static const String currentVersionName = '1.2.0';
  static final Uri _endpoint = Uri.parse(
    'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-update',
  );

  bool _checked = false;
  bool _checking = false;
  AppUpdateInfo? _availableUpdate;

  bool get checked => _checked;
  bool get checking => _checking;
  AppUpdateInfo? get availableUpdate => _availableUpdate;
  bool get hasUpdate => _availableUpdate != null;

  Future<void> checkOnce() async {
    if (_checked || _checking) return;

    // Se marca antes de salir a red: incluso si falla Internet, no repetimos la
    // petición durante esta apertura de TV FULL PRO.
    _checked = true;
    _checking = true;
    try {
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

      if (enabled &&
          versionCode > currentVersionCode &&
          versionName.isNotEmpty &&
          validUrl) {
        _availableUpdate = AppUpdateInfo(
          versionCode: versionCode,
          versionName: versionName,
          downloaderUrl: downloaderUrl,
        );
      }
    } catch (_) {
      // La comprobación de actualización nunca debe molestar ni bloquear la TV.
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
''', encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) pubspec: release +12 and tiny external-link launcher only.
# ---------------------------------------------------------------------------
pubspec = Path('pubspec.yaml')
text = pubspec.read_text(encoding='utf-8')
text = replace_once(text, 'version: 1.1.9+11', 'version: 1.2.0+12', 'pubspec version')
text = replace_once(
    text,
    '  path_provider: ^2.1.4\n  cupertino_icons: ^1.0.8',
    '  path_provider: ^2.1.4\n  url_launcher: ^6.3.2\n  cupertino_icons: ^1.0.8',
    'url_launcher dependency',
)
pubspec.write_text(text, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Initialize parental rules before first catalog can render.
# ---------------------------------------------------------------------------
main = Path('lib/main.dart')
text = main.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import 'services/remote_access_guard.dart';",
    "import 'services/parental_control_service.dart';\nimport 'services/remote_access_guard.dart';",
    'main parental import',
)
text = replace_once(
    text,
    "void main() {\n  WidgetsFlutterBinding.ensureInitialized();\n  MediaKit.ensureInitialized();\n  runApp(const TvFullProApp());\n}",
    "Future<void> main() async {\n  WidgetsFlutterBinding.ensureInitialized();\n  MediaKit.ensureInitialized();\n  await ParentalControlService.instance.init();\n  runApp(const TvFullProApp());\n}",
    'main parental init',
)
main.write_text(text, encoding='utf-8')


# ---------------------------------------------------------------------------
# 4) Home: exactly one silent update check each app opening.
# ---------------------------------------------------------------------------
home = Path('lib/screens/home_screen.dart')
text = home.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import '../providers/iptv_provider.dart';\nimport '../services/remote_access_guard.dart';",
    "import '../providers/iptv_provider.dart';\nimport '../services/app_update_service.dart';\nimport '../services/remote_access_guard.dart';",
    'home update import',
)
text = replace_once(
    text,
    "      final provider = context.read<IptvProvider>();\n      unawaited(provider.init());",
    "      final provider = context.read<IptvProvider>();\n      unawaited(provider.init());\n      unawaited(AppUpdateService.instance.checkOnce());",
    'one startup update request',
)
home.write_text(text, encoding='utf-8')


# ---------------------------------------------------------------------------
# 5) Home content: parental lock + red update banner above the three sections.
# ---------------------------------------------------------------------------
source = Path('lib/screens/source_content_screen.dart')
text = source.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import '../providers/iptv_provider.dart';\nimport 'xtream_live_screen.dart';",
    "import '../providers/iptv_provider.dart';\nimport '../services/app_update_service.dart';\nimport '../services/parental_control_service.dart';\nimport '../widgets/parental_lock_button.dart';\nimport '../widgets/parental_unlock_dialog.dart';\nimport 'parental_control_screen.dart';\nimport 'xtream_live_screen.dart';",
    'source imports',
)

new_source_head = r'''class SourceContentScreen extends StatefulWidget {
  final Playlist playlist;

  const SourceContentScreen({super.key, required this.playlist});

  @override
  State<SourceContentScreen> createState() => _SourceContentScreenState();
}

class _SourceContentScreenState extends State<SourceContentScreen> {
  final ParentalControlService _parental = ParentalControlService.instance;
  final AppUpdateService _updates = AppUpdateService.instance;

  @override
  void initState() {
    super.initState();
    _parental.addListener(_refresh);
    _updates.addListener(_refresh);
    unawaited(_parental.init());
    unawaited(_updates.checkOnce());
  }

  @override
  void dispose() {
    _parental.removeListener(_refresh);
    _updates.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final active = provider.selectedPlaylist ?? widget.playlist;
    final update = _updates.availableUpdate;

    return Scaffold(
      backgroundColor: const Color(0xFF05090F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(42, 26, 42, 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TV FULL PRO',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  ParentalLockButton(
                    unlocked: !_parental.enabled || _parental.isUnlocked,
                    hiddenCategoryCount: 0,
                    onPressed: () => unawaited(_handleParentalLock()),
                  ),
                  const SizedBox(width: 8),
                  if (provider.hasMultiplePlaylists)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_choosePlaylist(context)),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                      label: const Text('Cambiar lista'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                active.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (update != null) ...[
                const SizedBox(height: 14),
                _UpdateBanner(
                  versionName: update.versionName,
                  onUpdate: () => unawaited(_openUpdate()),
                ),
              ],
              const Spacer(flex: 2),
              const Text(
                '¿Qué querés ver?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 22),
              Expanded(
                flex: 9,
                child: Row(
                  children: [
                    Expanded(
                      child: _SectionButton(
                        autofocus: true,
                        eyebrow: 'EN DIRECTO',
                        title: 'TV EN VIVO',
                        icon: Icons.live_tv_rounded,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => XtreamLiveScreen(playlist: active),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _SectionButton(
                        eyebrow: 'CATÁLOGO',
                        title: 'PELÍCULAS',
                        icon: Icons.movie_outlined,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                XtreamMoviesScreen(playlist: active),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _SectionButton(
                        eyebrow: 'TEMPORADAS',
                        title: 'SERIES',
                        icon: Icons.video_library_outlined,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                XtreamSeriesScreen(playlist: active),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleParentalLock() async {
    await _parental.init();
    if (!mounted) return;

    if (!_parental.pinConfigured || !_parental.enabled) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ParentalControlScreen()),
      );
      return;
    }

    if (_parental.isUnlocked) {
      _parental.lockNow();
      return;
    }

    await requestParentalUnlock(
      context,
      title: 'Desbloquear contenido para adultos',
    );
  }

  Future<void> _openUpdate() async {
    final opened = await _updates.openUpdate();
    if (!mounted || opened) return;
    final code = _updates.availableUpdate?.downloaderCode ?? '';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            code.isEmpty
                ? 'No se pudo abrir el enlace de actualización.'
                : 'No se pudo abrir Downloader. Código: $code',
          ),
        ),
      );
  }

'''
text = regex_once(
    text,
    r'class SourceContentScreen extends StatelessWidget \{.*?(?=  Future<void> _choosePlaylist)',
    new_source_head,
    'source screen stateful body',
)

# Add a compact alert widget before the existing section button class.
update_banner = r'''
class _UpdateBanner extends StatelessWidget {
  final String versionName;
  final VoidCallback onUpdate;

  const _UpdateBanner({required this.versionName, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF626B);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: red.withValues(alpha: .075),
        border: Border.all(color: red.withValues(alpha: .38)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt_rounded, color: red, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ACTUALIZACIÓN DISPONIBLE',
                  style: TextStyle(
                    color: red,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .45,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Mejor rendimiento · versión $versionName',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onUpdate,
            style: OutlinedButton.styleFrom(
              foregroundColor: red,
              side: const BorderSide(color: red),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'ACTUALIZAR',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

'''
text = replace_once(
    text,
    'class _SectionButton extends StatefulWidget {',
    update_banner + 'class _SectionButton extends StatefulWidget {',
    'update banner widget',
)
source.write_text(text, encoding='utf-8')


# ---------------------------------------------------------------------------
# 6) Parental filtering in LIVE / Movies / Series. Provider data is untouched;
#    only the visible UI list is filtered, and it rebuilds when lock timer fires.
# ---------------------------------------------------------------------------
def patch_parental(path: str, item_kind: str):
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    text = replace_once(
        text,
        "import '../services/artwork_cache_service.dart';",
        "import '../services/artwork_cache_service.dart';\nimport '../services/parental_control_service.dart';",
        f'{item_kind} parental import',
    )

    state_marker = {
        'live': '  late Future<_LiveData> _future;\n',
        'movies': '  late Future<_MovieData> _future;\n',
        'series': '  late Future<_SeriesData> _future;\n',
    }[item_kind]
    text = replace_once(
        text,
        state_marker,
        state_marker + '  final ParentalControlService _parental = ParentalControlService.instance;\n',
        f'{item_kind} parental state',
    )
    text = replace_once(
        text,
        '    super.initState();\n    unawaited(ArtworkCacheService.instance.switchProvider(widget.playlist.id));',
        '    super.initState();\n    _parental.addListener(_onParentalChanged);\n    unawaited(_parental.init());\n    unawaited(ArtworkCacheService.instance.switchProvider(widget.playlist.id));',
        f'{item_kind} parental listener init',
    )
    text = replace_once(
        text,
        '  @override\n  void dispose() {\n    _searchController.dispose();',
        '  @override\n  void dispose() {\n    _parental.removeListener(_onParentalChanged);\n    _searchController.dispose();',
        f'{item_kind} parental listener dispose',
    )
    hook = r'''  void _onParentalChanged() {
    if (!mounted) return;
    if (_parental.isLocked &&
        _category != null &&
        _parental.isProtectedGroup(_category)) {
      _category = null;
    }
    setState(() {});
  }

'''
    text = replace_once(
        text,
        '  void _openSearch() {',
        hook + '  void _openSearch() {',
        f'{item_kind} parental rebuild hook',
    )

    if item_kind == 'live':
        text = replace_once(
            text,
            '    final categories = data.categories;\n    final normalizedQuery = _query.trim().toLowerCase();\n    final List<Channel> visible;\n    if (_searchOpen) {\n      visible = normalizedQuery.isEmpty\n          ? data.channels\n          : data.channels.where((item) {',
            "    final categories = _parental.visibleGroups(data.categories);\n    final allowed = data.channels\n        .where(_parental.canShowChannel)\n        .toList(growable: false);\n    final normalizedQuery = _query.trim().toLowerCase();\n    final List<Channel> visible;\n    if (_searchOpen) {\n      visible = normalizedQuery.isEmpty\n          ? allowed\n          : allowed.where((item) {",
            'live allowed search base',
        )
        text = replace_once(
            text,
            '      visible = _category == null\n          ? data.channels\n          : data.channels\n              .where((item) => item.group == _category)',
            '      visible = _category == null\n          ? allowed\n          : allowed\n              .where((item) => item.group == _category)',
            'live allowed category base',
        )
    else:
        data_type = '_MovieItem' if item_kind == 'movies' else '_SeriesItem'
        text = replace_once(
            text,
            f'    final categories = data.categories;\n    final normalizedQuery = _query.trim().toLowerCase();\n    final List<{data_type}> visible;\n    if (_searchOpen) {{\n      visible = normalizedQuery.isEmpty\n          ? data.items\n          : data.items.where((item) {{',
            f"    final categories = _parental.visibleGroups(data.categories);\n    final allowed = data.items\n        .where(\n          (item) => _parental.canShowItem(\n            name: item.name,\n            group: item.category,\n          ),\n        )\n        .toList(growable: false);\n    final normalizedQuery = _query.trim().toLowerCase();\n    final List<{data_type}> visible;\n    if (_searchOpen) {{\n      visible = normalizedQuery.isEmpty\n          ? allowed\n          : allowed.where((item) {{",
            f'{item_kind} allowed search base',
        )
        text = replace_once(
            text,
            '      visible = _category == null\n          ? data.items\n          : data.items\n              .where((item) => item.category == _category)',
            '      visible = _category == null\n          ? allowed\n          : allowed\n              .where((item) => item.category == _category)',
            f'{item_kind} allowed category base',
        )

    file.write_text(text, encoding='utf-8')


patch_parental('lib/screens/xtream_live_screen.dart', 'live')
patch_parental('lib/screens/xtream_movies_screen.dart', 'movies')
patch_parental('lib/screens/xtream_series_screen.dart', 'series')


# ---------------------------------------------------------------------------
# 7) Series catalog: same poster-first dimensions/grid as Movies.
# ---------------------------------------------------------------------------
series = Path('lib/screens/xtream_series_screen.dart')
text = series.read_text(encoding='utf-8')
old_grid = '''                          final columns = constraints.maxWidth >= 1000 ? 4 : 3;
                          return GridView.builder(
                            controller: _searchOpen
                                ? _searchScrollController
                                : _catalogScrollController,
                            padding: const EdgeInsets.fromLTRB(18, 0, 22, 24),
                            scrollCacheExtent:
                                const ScrollCacheExtent.pixels(90),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 2.65,
                            ),'''
new_grid = '''                          final columns = constraints.maxWidth >= 850
                              ? 5
                              : constraints.maxWidth >= 620
                                  ? 4
                                  : 3;
                          return GridView.builder(
                            controller: _searchOpen
                                ? _searchScrollController
                                : _catalogScrollController,
                            padding: const EdgeInsets.fromLTRB(20, 4, 24, 30),
                            scrollCacheExtent:
                                const ScrollCacheExtent.pixels(120),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 18,
                              mainAxisSpacing: 20,
                              childAspectRatio: 0.62,
                            ),'''
text = replace_once(text, old_grid, new_grid, 'series movie-sized grid')

series_card = r'''class _SeriesCard extends StatefulWidget {
  final _SeriesItem item;
  final bool autofocus;
  final VoidCallback onTap;

  const _SeriesCard({
    required this.item,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<_SeriesCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _focused ? 1.035 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: const Color(0xFF0B151F),
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: widget.autofocus,
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _focused ? const Color(0xFF58B9FF) : Colors.white10,
                width: _focused ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CachedArtworkImage(
                    url: widget.item.cover,
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                    cacheHeight: 480,
                    prefetchExtent: 0,
                    fallback: const ColoredBox(
                      color: Color(0xFF111E29),
                      child: Center(
                        child: Icon(
                          Icons.video_library_outlined,
                          size: 42,
                          color: Colors.white30,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Text(
                    widget.item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.15,
                      fontWeight: _focused ? FontWeight.w900 : FontWeight.w750,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

'''
text = regex_once(
    text,
    r'class _SeriesCard extends StatefulWidget \{.*?(?=class _SeriesData \{)',
    series_card,
    'series vertical card',
)
series.write_text(text, encoding='utf-8')

print('TV FULL PRO +12 improvements applied: series posters, parental lock/filter, one-shot update alert')
