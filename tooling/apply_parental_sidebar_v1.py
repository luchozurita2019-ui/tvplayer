from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Patch marker not found: {label}')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# channel_list_screen.dart
# ---------------------------------------------------------------------------
path = Path('lib/screens/channel_list_screen.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import 'package:flutter/material.dart';\nimport 'package:provider/provider.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:provider/provider.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n",
    'channel imports shared prefs',
)
text = replace_once(
    text,
    "import '../services/artwork_cache_service.dart';\nimport '../widgets/cached_artwork_image.dart';\n",
    "import '../services/artwork_cache_service.dart';\nimport '../services/parental_control_service.dart';\nimport '../widgets/cached_artwork_image.dart';\n",
    'channel parental import',
)
text = replace_once(
    text,
    "  late Map<String, int> _groupCounts;\n  bool _initialArtworkReady = false;\n",
    "  late Map<String, int> _groupCounts;\n  bool _initialArtworkReady = false;\n\n  final ParentalControlService _parental = ParentalControlService.instance;\n  double _sidebarWidth = 320;\n  bool _sidebarCollapsed = false;\n\n  static const double _sidebarMinWidth = 230;\n  static const double _sidebarMaxWidth = 480;\n  static const String _sidebarWidthKey = 'catalog_sidebar_width_v1';\n  static const String _sidebarCollapsedKey = 'catalog_sidebar_collapsed_v1';\n",
    'channel state fields',
)
text = replace_once(
    text,
    "  void initState() {\n    super.initState();\n    _rebuildCategoryCache(widget.playlist);\n    unawaited(_prepareInitialArtwork());\n  }\n\n  @override\n  void didUpdateWidget",
    "  void initState() {\n    super.initState();\n    _parental.addListener(_onParentalChanged);\n    _rebuildCategoryCache(widget.playlist);\n    unawaited(_initializeCatalogPreferences());\n    unawaited(_prepareInitialArtwork());\n  }\n\n  @override\n  void dispose() {\n    _parental.removeListener(_onParentalChanged);\n    super.dispose();\n  }\n\n  Future<void> _initializeCatalogPreferences() async {\n    await _parental.init();\n    final prefs = await SharedPreferences.getInstance();\n    if (!mounted) return;\n    final width = prefs.getDouble(_sidebarWidthKey) ?? 320;\n    setState(() {\n      _sidebarWidth = width.clamp(_sidebarMinWidth, _sidebarMaxWidth).toDouble();\n      _sidebarCollapsed = prefs.getBool(_sidebarCollapsedKey) ?? false;\n    });\n  }\n\n  void _onParentalChanged() {\n    if (!mounted) return;\n    if (_selectedGroup != null &&\n        _parental.isLocked &&\n        _parental.isProtectedGroup(_selectedGroup)) {\n      _selectedGroup = null;\n    }\n    setState(() {});\n  }\n\n  Future<void> _persistSidebar() async {\n    final prefs = await SharedPreferences.getInstance();\n    await prefs.setDouble(_sidebarWidthKey, _sidebarWidth);\n    await prefs.setBool(_sidebarCollapsedKey, _sidebarCollapsed);\n  }\n\n  void _resizeSidebar(double delta) {\n    if (_sidebarCollapsed) return;\n    setState(() {\n      _sidebarWidth = (_sidebarWidth + delta)\n          .clamp(_sidebarMinWidth, _sidebarMaxWidth)\n          .toDouble();\n    });\n  }\n\n  void _toggleSidebar() {\n    setState(() => _sidebarCollapsed = !_sidebarCollapsed);\n    unawaited(_persistSidebar());\n  }\n\n  @override\n  void didUpdateWidget",
    'channel init and preferences',
)
text = replace_once(
    text,
    "    final channels = _filteredChannels(playlist);\n    final mode = _mode;\n",
    "    final channels = _filteredChannels(playlist);\n    final mode = _mode;\n    final visibleGroups = _parental.visibleGroups(_groups);\n    final visibleTotal = playlist.channels\n        .where(_parental.canShowChannel)\n        .length;\n",
    'channel visible parental vars',
)
text = replace_once(
    text,
    "        actions: [\n          if (playlist.isRemote)\n",
    "        actions: [\n          if (_parental.enabled)\n            IconButton(\n              icon: Icon(\n                _parental.isUnlocked\n                    ? Icons.lock_open_rounded\n                    : Icons.lock_rounded,\n              ),\n              tooltip: _parental.isUnlocked\n                  ? 'Bloquear contenido protegido'\n                  : 'Desbloquear contenido protegido',\n              onPressed: () => unawaited(_toggleParentalLock()),\n            ),\n          if (playlist.isRemote)\n",
    'channel parental appbar action',
)
text = replace_once(
    text,
    "              groups: _groups,\n              groupCounts: _groupCounts,\n              selectedGroup: _selectedGroup,\n              query: _query,\n              onGroupSelected: (group) {\n                setState(() => _selectedGroup = group);\n              },\n",
    "              groups: visibleGroups,\n              groupCounts: _groupCounts,\n              selectedGroup: _selectedGroup,\n              query: _query,\n              sidebarWidth: _sidebarWidth,\n              sidebarCollapsed: _sidebarCollapsed,\n              totalVisibleCount: visibleTotal,\n              parentalLocked: _parental.isLocked,\n              isProtectedGroup: _parental.isProtectedGroup,\n              onSidebarResize: _resizeSidebar,\n              onSidebarResizeEnd: () => unawaited(_persistSidebar()),\n              onSidebarToggle: _toggleSidebar,\n              onGroupSelected: (group) => unawaited(_selectGroup(group)),\n",
    'desktop layout params',
)
text = replace_once(
    text,
    "            groups: _groups,\n            selectedGroup: _selectedGroup,\n            query: _query,\n            onGroupSelected: (group) {\n              setState(() => _selectedGroup = group);\n            },\n",
    "            groups: visibleGroups,\n            selectedGroup: _selectedGroup,\n            query: _query,\n            onGroupSelected: (group) => unawaited(_selectGroup(group)),\n",
    'compact layout params',
)
old_filter = """  List<Channel> _filteredChannels(Playlist playlist) {
    final normalized = _query.trim().toLowerCase();
    if (_selectedGroup == null && normalized.isEmpty) {
      return playlist.channels;
    }

    return playlist.channels.where((channel) {
      if (_selectedGroup != null && channel.group?.trim() != _selectedGroup) {
        return false;
      }
      if (normalized.isEmpty) return true;

      final name = channel.name.toLowerCase();
      final group = channel.group?.toLowerCase() ?? '';
      return name.contains(normalized) || group.contains(normalized);
    }).toList(growable: false);
  }

"""
new_filter = """  Future<void> _selectGroup(String? group) async {
    if (group != null &&
        _parental.isLocked &&
        _parental.isProtectedGroup(group)) {
      final unlocked = await _requestParentalUnlock();
      if (!unlocked || !mounted) return;
    }
    setState(() => _selectedGroup = group);
  }

  Future<void> _toggleParentalLock() async {
    if (_parental.isUnlocked) {
      _parental.lockNow();
      return;
    }
    await _requestParentalUnlock();
  }

  Future<bool> _requestParentalUnlock() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contenido protegido'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(
            labelText: 'PIN parental',
            counterText: '',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Desbloquear'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || pin == null) return false;
    final ok = await _parental.unlock(pin);
    if (!mounted) return ok;
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('PIN incorrecto.')));
    }
    return ok;
  }

  List<Channel> _filteredChannels(Playlist playlist) {
    final normalized = _query.trim().toLowerCase();
    final parentalFiltering = _parental.enabled && _parental.isLocked;
    if (_selectedGroup == null && normalized.isEmpty && !parentalFiltering) {
      return playlist.channels;
    }

    return playlist.channels.where((channel) {
      if (!_parental.canShowChannel(channel)) return false;
      if (_selectedGroup != null && channel.group?.trim() != _selectedGroup) {
        return false;
      }
      if (normalized.isEmpty) return true;

      final name = channel.name.toLowerCase();
      final group = channel.group?.toLowerCase() ?? '';
      return name.contains(normalized) || group.contains(normalized);
    }).toList(growable: false);
  }

"""
text = replace_once(text, old_filter, new_filter, 'parental filter and unlock')

# Desktop layout fields & constructor.
text = replace_once(
    text,
    "  final String query;\n  final ValueChanged<String?> onGroupSelected;\n",
    "  final String query;\n  final double sidebarWidth;\n  final bool sidebarCollapsed;\n  final int totalVisibleCount;\n  final bool parentalLocked;\n  final bool Function(String?) isProtectedGroup;\n  final ValueChanged<double> onSidebarResize;\n  final VoidCallback onSidebarResizeEnd;\n  final VoidCallback onSidebarToggle;\n  final ValueChanged<String?> onGroupSelected;\n",
    'desktop fields',
)
text = replace_once(
    text,
    "    required this.query,\n    required this.onGroupSelected,\n",
    "    required this.query,\n    required this.sidebarWidth,\n    required this.sidebarCollapsed,\n    required this.totalVisibleCount,\n    required this.parentalLocked,\n    required this.isProtectedGroup,\n    required this.onSidebarResize,\n    required this.onSidebarResizeEnd,\n    required this.onSidebarToggle,\n    required this.onGroupSelected,\n",
    'desktop constructor',
)
old_sidebar_build = """        SizedBox(
          width: 268,
          child: _CategorySidebar(
            mode: mode,
            totalCount: playlist.channels.length,
            groups: groups,
            groupCounts: groupCounts,
            selectedGroup: selectedGroup,
            onGroupSelected: onGroupSelected,
          ),
        ),
        const VerticalDivider(width: 1),
"""
new_sidebar_build = """        SizedBox(
          width: sidebarCollapsed ? 72 : sidebarWidth,
          child: _CategorySidebar(
            mode: mode,
            totalCount: totalVisibleCount,
            groups: groups,
            groupCounts: groupCounts,
            selectedGroup: selectedGroup,
            collapsed: sidebarCollapsed,
            parentalLocked: parentalLocked,
            isProtectedGroup: isProtectedGroup,
            onToggleCollapsed: onSidebarToggle,
            onGroupSelected: onGroupSelected,
          ),
        ),
        MouseRegion(
          cursor: sidebarCollapsed
              ? SystemMouseCursors.basic
              : SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: sidebarCollapsed
                ? null
                : (details) => onSidebarResize(details.delta.dx),
            onHorizontalDragEnd:
                sidebarCollapsed ? null : (_) => onSidebarResizeEnd(),
            child: Container(
              width: 9,
              alignment: Alignment.center,
              child: Container(width: 1, color: Colors.white12),
            ),
          ),
        ),
"""
text = replace_once(text, old_sidebar_build, new_sidebar_build, 'desktop resizable sidebar')

# Replace whole CategorySidebar implementation.
start = text.index('class _CategorySidebar extends StatelessWidget {')
end = text.index('class _CatalogGrid extends StatelessWidget {', start)
new_sidebar_class = r'''class _CategorySidebar extends StatelessWidget {
  final _CatalogMode mode;
  final int totalCount;
  final List<String> groups;
  final Map<String, int> groupCounts;
  final String? selectedGroup;
  final bool collapsed;
  final bool parentalLocked;
  final bool Function(String?) isProtectedGroup;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<String?> onGroupSelected;

  const _CategorySidebar({
    required this.mode,
    required this.totalCount,
    required this.groups,
    required this.groupCounts,
    required this.selectedGroup,
    required this.collapsed,
    required this.parentalLocked,
    required this.isProtectedGroup,
    required this.onToggleCollapsed,
    required this.onGroupSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF081728),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment:
              collapsed ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                collapsed ? 8 : 20,
                18,
                collapsed ? 8 : 10,
                8,
              ),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(
                    mode.icon,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        mode.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ],
                  if (!collapsed)
                    IconButton(
                      tooltip: 'Achicar categorías',
                      onPressed: onToggleCollapsed,
                      icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                    ),
                ],
              ),
            ),
            if (collapsed)
              IconButton(
                tooltip: 'Agrandar categorías',
                onPressed: onToggleCollapsed,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'CATEGORÍAS',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Colors.white54,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                      ),
                    ),
                    const Tooltip(
                      message: 'Arrastrá el borde derecho para cambiar el ancho',
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: Colors.white30,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(collapsed ? 8 : 10, 0, collapsed ? 8 : 10, 20),
                itemCount: groups.length + 1,
                itemBuilder: (context, index) {
                  final group = index == 0 ? null : groups[index - 1];
                  final label = group ?? 'Todos';
                  final selected = group == selectedGroup;
                  final count = group == null ? totalCount : (groupCounts[group] ?? 0);
                  final locked = group != null && parentalLocked && isProtectedGroup(group);

                  if (collapsed) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Tooltip(
                        message: locked ? '$label · Bloqueada con PIN' : '$label · $count',
                        child: Material(
                          color: selected
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.20)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onGroupSelected(group),
                            child: SizedBox(
                              height: 52,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    group == null
                                        ? Icons.grid_view_rounded
                                        : Icons.folder_rounded,
                                    size: 25,
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white70,
                                  ),
                                  if (locked)
                                    const Positioned(
                                      right: 7,
                                      bottom: 7,
                                      child: Icon(
                                        Icons.lock_rounded,
                                        size: 13,
                                        color: Colors.amberAccent,
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

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Tooltip(
                      message: label,
                      waitDuration: const Duration(milliseconds: 450),
                      child: ListTile(
                        minTileHeight: 54,
                        selected: selected,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.20),
                        leading: Icon(
                          group == null
                              ? Icons.grid_view_rounded
                              : Icons.folder_rounded,
                          size: 24,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white70,
                        ),
                        title: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (locked) ...[
                              const Icon(
                                Icons.lock_rounded,
                                size: 17,
                                color: Colors.amberAccent,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ],
                        ),
                        onTap: () => onGroupSelected(group),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

'''
text = text[:start] + new_sidebar_class + text[end:]
path.write_text(text, encoding='utf-8')


# ---------------------------------------------------------------------------
# home_screen.dart
# ---------------------------------------------------------------------------
path = Path('lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import 'package:flutter/material.dart';\n",
    "import 'dart:async';\n\nimport 'package:flutter/material.dart';\n",
    'home dart async import',
)
text = replace_once(
    text,
    "import '../services/artwork_cache_service.dart';\n",
    "import '../services/artwork_cache_service.dart';\nimport '../services/parental_control_service.dart';\n",
    'home parental service import',
)
text = replace_once(
    text,
    "import 'playback_settings_screen.dart';\nimport 'player_screen.dart';\n",
    "import 'playback_settings_screen.dart';\nimport 'parental_control_screen.dart';\nimport 'player_screen.dart';\n",
    'home parental screen import',
)
text = replace_once(
    text,
    "    WidgetsBinding.instance.addPostFrameCallback((_) {\n      context.read<IptvProvider>().init();\n    });\n",
    "    WidgetsBinding.instance.addPostFrameCallback((_) {\n      unawaited(ParentalControlService.instance.init());\n      context.read<IptvProvider>().init();\n    });\n",
    'home parental init',
)
text = replace_once(
    text,
    "            actions: [\n              if (_section != 2)\n",
    "            actions: [\n              IconButton(\n                tooltip: 'Control parental',\n                icon: const Icon(Icons.shield_outlined),\n                onPressed: () => unawaited(_openParentalSettings(context)),\n              ),\n              if (_section != 2)\n",
    'home parental action',
)
insert_marker = """  void _openPlaybackSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlaybackSettingsScreen()),
    );
  }


}
"""
insert_replacement = """  void _openPlaybackSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlaybackSettingsScreen()),
    );
  }

  Future<void> _openParentalSettings(BuildContext context) async {
    final parental = ParentalControlService.instance;
    await parental.init();
    if (!mounted) return;

    if (parental.pinConfigured) {
      final controller = TextEditingController();
      final pin = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Control parental'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: 'Ingresá tu PIN',
              counterText: '',
            ),
            onSubmitted: (value) =>
                Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (!mounted || pin == null) return;
      if (!parental.verifyPin(pin)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('PIN incorrecto.')));
        return;
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ParentalControlScreen()),
    );
  }

}
"""
text = replace_once(text, insert_marker, insert_replacement, 'home parental settings helper')

# Ensure provider artwork warm waits for parental preferences to load.
text = replace_once(
    text,
    "  Future<void> _openPlaylist(BuildContext context) async {\n    final navigator = Navigator.of(context);\n    final cache = ArtworkCacheService.instance;\n",
    "  Future<void> _openPlaylist(BuildContext context) async {\n    final navigator = Navigator.of(context);\n    final cache = ArtworkCacheService.instance;\n    await ParentalControlService.instance.init();\n    if (!context.mounted) return;\n",
    'home playlist parental init',
)

# Favorites never expose protected content while the parental lock is active.
text = replace_once(
    text,
    "    final provider = context.watch<IptvProvider>();\n    final favorites = provider.favorites;\n\n    if (favorites.isEmpty) {\n",
    "    final provider = context.watch<IptvProvider>();\n    final parental = ParentalControlService.instance;\n    final favorites = parental.enabled && parental.isLocked\n        ? provider.favorites.where(parental.canShowChannel).toList(growable: false)\n        : provider.favorites;\n\n    if (favorites.isEmpty) {\n",
    'home favorites parental filter',
)
path.write_text(text, encoding='utf-8')


# ---------------------------------------------------------------------------
# artwork_cache_service.dart
# ---------------------------------------------------------------------------
path = Path('lib/services/artwork_cache_service.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import 'content_classifier.dart';\n",
    "import 'content_classifier.dart';\nimport 'parental_control_service.dart';\n",
    'artwork parental import',
)
text = replace_once(
    text,
    "  Future<void> warmProvider(Playlist playlist) async {\n    await switchProvider(playlist.id);\n\n    final buckets = ContentClassifier.partition(playlist.channels);\n",
    "  Future<void> warmProvider(Playlist playlist) async {\n    await switchProvider(playlist.id);\n    final parental = ParentalControlService.instance;\n    await parental.init();\n\n    final buckets = ContentClassifier.partition(playlist.channels);\n",
    'artwork provider parental init',
)
text = replace_once(
    text,
    "      for (final channel in channels) {\n        final url = _validArtworkUrl(channel.logoUrl);\n",
    "      for (final channel in channels) {\n        if (!parental.canShowChannel(channel)) continue;\n        final url = _validArtworkUrl(channel.logoUrl);\n",
    'artwork provider skip protected',
)
text = replace_once(
    text,
    "  }) async {\n    final urls = <String>[];\n    final seen = <String>{};\n    for (final channel in channels) {\n      final url = _validArtworkUrl(channel.logoUrl);\n",
    "  }) async {\n    final parental = ParentalControlService.instance;\n    await parental.init();\n    final urls = <String>[];\n    final seen = <String>{};\n    for (final channel in channels) {\n      if (!parental.canShowChannel(channel)) continue;\n      final url = _validArtworkUrl(channel.logoUrl);\n",
    'artwork section skip protected',
)
path.write_text(text, encoding='utf-8')


# ---------------------------------------------------------------------------
# pubspec.yaml
# ---------------------------------------------------------------------------
path = Path('pubspec.yaml')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "  # --- Utilidades ---\n  path_provider: ^2.1.4\n",
    "  # --- Utilidades ---\n  crypto: ^3.0.6\n  path_provider: ^2.1.4\n",
    'pubspec crypto',
)
path.write_text(text, encoding='utf-8')

print('Parental control + resizable category sidebar applied')
