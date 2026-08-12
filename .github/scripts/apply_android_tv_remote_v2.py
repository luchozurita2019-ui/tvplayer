from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"Pattern not found in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))


# Global Android TV remote OK/Enter -> ActivateIntent bridge.
replace_once(
    'lib/main.dart',
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
)
replace_once(
    'lib/main.dart',
    "        debugShowCheckedModeBanner: false,\n        theme: ThemeData(\n",
    "        debugShowCheckedModeBanner: false,\n        builder: (context, child) {\n          if (!_androidTvBuild || child == null) {\n            return child ?? const SizedBox.shrink();\n          }\n          return Shortcuts(\n            shortcuts: const <ShortcutActivator, Intent>{\n              SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),\n              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),\n              SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),\n              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),\n            },\n            child: FocusTraversalGroup(\n              policy: ReadingOrderTraversalPolicy(),\n              child: child,\n            ),\n          );\n        },\n        theme: ThemeData(\n",
)

# Home: first playlist is the initial D-pad target.
replace_once(
    'lib/screens/home_screen.dart',
    "            return _PlaylistCard(\n              playlist: playlist,\n              isFavorite: favoriteIds.contains(playlist.id),\n              onToggleFavorite: () => onToggleFavorite(playlist),\n            );\n",
    "            return _PlaylistCard(\n              playlist: playlist,\n              isFavorite: favoriteIds.contains(playlist.id),\n              autofocus: _androidTvBuild && index == 0,\n              onToggleFavorite: () => onToggleFavorite(playlist),\n            );\n",
)
replace_once(
    'lib/screens/home_screen.dart',
    "class _PlaylistCard extends StatelessWidget {\n  final Playlist playlist;\n  final bool isFavorite;\n  final VoidCallback onToggleFavorite;\n\n  const _PlaylistCard({\n    required this.playlist,\n    required this.isFavorite,\n    required this.onToggleFavorite,\n  });\n",
    "class _PlaylistCard extends StatelessWidget {\n  final Playlist playlist;\n  final bool isFavorite;\n  final bool autofocus;\n  final VoidCallback onToggleFavorite;\n\n  const _PlaylistCard({\n    required this.playlist,\n    required this.isFavorite,\n    required this.autofocus,\n    required this.onToggleFavorite,\n  });\n",
)
replace_once(
    'lib/screens/home_screen.dart',
    "      child: InkWell(\n        onTap: () => _openPlaylist(context),\n        borderRadius: BorderRadius.circular(18),\n",
    "      child: InkWell(\n        autofocus: autofocus,\n        focusColor: _proBlue.withValues(alpha: 0.24),\n        onFocusChange: (focused) {\n          if (focused && _androidTvBuild) {\n            WidgetsBinding.instance.addPostFrameCallback((_) {\n              if (context.mounted) {\n                Scrollable.ensureVisible(\n                  context,\n                  duration: const Duration(milliseconds: 180),\n                  alignment: 0.35,\n                );\n              }\n            });\n          }\n        },\n        onTap: () => _openPlaylist(context),\n        borderRadius: BorderRadius.circular(18),\n",
)

# Content selector: TV en vivo starts focused and accepts the remote center button.
replace_once(
    'lib/screens/source_content_screen.dart',
    "                  _ContentCard(\n                    icon: Icons.live_tv_rounded,\n",
    "                  _ContentCard(\n                    autofocus: _androidTvBuild,\n                    icon: Icons.live_tv_rounded,\n",
)
replace_once(
    'lib/screens/source_content_screen.dart',
    "class _ContentCard extends StatelessWidget {\n  final IconData icon;\n",
    "class _ContentCard extends StatelessWidget {\n  final bool autofocus;\n  final IconData icon;\n",
)
replace_once(
    'lib/screens/source_content_screen.dart',
    "  const _ContentCard({\n    required this.icon,\n",
    "  const _ContentCard({\n    this.autofocus = false,\n    required this.icon,\n",
)
replace_once(
    'lib/screens/source_content_screen.dart',
    "      child: InkWell(\n        onTap: enabled ? onTap : null,\n        child: Container(\n",
    "      child: InkWell(\n        autofocus: enabled && autofocus,\n        focusColor: accent.withValues(alpha: 0.30),\n        onFocusChange: (focused) {\n          if (focused && _androidTvBuild) {\n            WidgetsBinding.instance.addPostFrameCallback((_) {\n              if (context.mounted) {\n                Scrollable.ensureVisible(\n                  context,\n                  duration: const Duration(milliseconds: 160),\n                  alignment: 0.4,\n                );\n              }\n            });\n          }\n        },\n        onTap: enabled ? onTap : null,\n        child: Container(\n",
)

# Channel grids: first channel becomes the D-pad target after the catalog loads.
replace_once(
    'lib/screens/channel_list_screen.dart',
    "              isFavorite: isFavorite(channel),\n              onFavoriteToggle: () => onFavoriteToggle(channel),\n",
    "              isFavorite: isFavorite(channel),\n              autofocus: _androidTvBuild && index == 0,\n              onFavoriteToggle: () => onFavoriteToggle(channel),\n",
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "                          isFavorite: isFavorite(channel),\n                          onFavoriteToggle: () => onFavoriteToggle(channel),\n",
    "                          isFavorite: isFavorite(channel),\n                          autofocus: _androidTvBuild && index == 0,\n                          onFavoriteToggle: () => onFavoriteToggle(channel),\n",
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "class _CatalogCard extends StatefulWidget {\n  final _CatalogMode mode;\n  final Channel channel;\n  final bool isFavorite;\n",
    "class _CatalogCard extends StatefulWidget {\n  final _CatalogMode mode;\n  final Channel channel;\n  final bool isFavorite;\n  final bool autofocus;\n",
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "    required this.channel,\n    required this.isFavorite,\n    required this.onFavoriteToggle,\n",
    "    required this.channel,\n    required this.isFavorite,\n    required this.autofocus,\n    required this.onFavoriteToggle,\n",
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "          child: InkWell(\n            onFocusChange: (value) {\n              if (mounted) setState(() => _focused = value);\n            },\n            focusColor: primary.withValues(alpha: 0.18),\n            onTap: widget.onTap,\n",
    "          child: InkWell(\n            autofocus: widget.autofocus,\n            onFocusChange: (value) {\n              if (mounted) setState(() => _focused = value);\n              if (value && _androidTvBuild) {\n                WidgetsBinding.instance.addPostFrameCallback((_) {\n                  if (mounted) {\n                    Scrollable.ensureVisible(\n                      context,\n                      duration: const Duration(milliseconds: 150),\n                      alignment: 0.35,\n                    );\n                  }\n                });\n              }\n            },\n            focusColor: primary.withValues(alpha: 0.24),\n            onTap: widget.onTap,\n",
)

# Player: center/OK reveals controls when they are hidden. Visible controls still
# receive the normal ActivateIntent from the global shortcut bridge.
replace_once(
    'lib/widgets/live_video_view.dart',
    "  KeyEventResult _handleTvKeyEvent(FocusNode node, KeyEvent event) {\n    if (!_androidTvBuild || event is! KeyDownEvent) {\n      return KeyEventResult.ignored;\n    }\n    _showOverlay();\n    return KeyEventResult.ignored;\n  }\n",
    "  KeyEventResult _handleTvKeyEvent(FocusNode node, KeyEvent event) {\n    if (!_androidTvBuild || event is! KeyDownEvent) {\n      return KeyEventResult.ignored;\n    }\n    final key = event.logicalKey;\n    final isCenter = key == LogicalKeyboardKey.select ||\n        key == LogicalKeyboardKey.enter ||\n        key == LogicalKeyboardKey.numpadEnter;\n    if (isCenter && !_overlayVisible) {\n      _showOverlay();\n      return KeyEventResult.handled;\n    }\n    _showOverlay();\n    return KeyEventResult.ignored;\n  }\n",
)

print('Android TV remote V2 patches applied successfully')
