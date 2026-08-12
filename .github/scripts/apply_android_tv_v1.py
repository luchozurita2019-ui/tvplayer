from pathlib import Path

TV_DEFINE = "const bool _androidTvBuild = bool.fromEnvironment('TV_FULL_ANDROID_TV');"


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'No se encontró bloque para {label} en {path}')
    p.write_text(text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# 1) Tema general: foco visible y navegación consistente con control remoto.
# ---------------------------------------------------------------------------
replace_once(
    'lib/main.dart',
    "import 'screens/home_screen.dart';\n",
    "import 'screens/home_screen.dart';\n\n" + TV_DEFINE + "\n",
    'define Android TV main',
)
replace_once(
    'lib/main.dart',
    "          scaffoldBackgroundColor: darkNavy,\n",
    "          scaffoldBackgroundColor: darkNavy,\n"
    "          focusColor: const Color(0x6634A8FF),\n"
    "          hoverColor: const Color(0x332A9CFF),\n"
    "          splashColor: const Color(0x4434A8FF),\n"
    "          highlightColor: const Color(0x2234A8FF),\n"
    "          visualDensity: _androidTvBuild\n"
    "              ? const VisualDensity(horizontal: 0.5, vertical: 0.5)\n"
    "              : VisualDensity.standard,\n",
    'tema de foco TV',
)
replace_once(
    'lib/main.dart',
    "          filledButtonTheme: FilledButtonThemeData(\n"
    "            style: FilledButton.styleFrom(\n"
    "              backgroundColor: brandBlue,\n"
    "              foregroundColor: Colors.white,\n"
    "            ),\n"
    "          ),\n",
    "          filledButtonTheme: FilledButtonThemeData(\n"
    "            style: FilledButton.styleFrom(\n"
    "              backgroundColor: brandBlue,\n"
    "              foregroundColor: Colors.white,\n"
    "              minimumSize: _androidTvBuild ? const Size(56, 48) : null,\n"
    "            ),\n"
    "          ),\n"
    "          iconButtonTheme: IconButtonThemeData(\n"
    "            style: ButtonStyle(\n"
    "              minimumSize: _androidTvBuild\n"
    "                  ? const WidgetStatePropertyAll(Size(48, 48))\n"
    "                  : null,\n"
    "              backgroundColor: _androidTvBuild\n"
    "                  ? WidgetStateProperty.resolveWith((states) {\n"
    "                      if (states.contains(WidgetState.focused)) {\n"
    "                        return const Color(0x5534A8FF);\n"
    "                      }\n"
    "                      return null;\n"
    "                    })\n"
    "                  : null,\n"
    "            ),\n"
    "          ),\n",
    'botones TV',
)

# ---------------------------------------------------------------------------
# 2) Home: siempre usar composición horizontal de TV y dimensiones seguras.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/home_screen.dart',
    "const _proMuted = Color(0xFF8D9AAD);\n",
    "const _proMuted = Color(0xFF8D9AAD);\n" + TV_DEFINE + "\n",
    'define Android TV home',
)
replace_once(
    'lib/screens/home_screen.dart',
    "        final desktop = constraints.maxWidth >= 860;\n",
    "        final desktop = _androidTvBuild || constraints.maxWidth >= 860;\n",
    'forzar layout desktop TV',
)
replace_once(
    'lib/screens/home_screen.dart',
    "      width: compact ? double.infinity : 270,\n",
    "      width: compact ? double.infinity : (_androidTvBuild ? 238 : 270),\n",
    'sidebar TV',
)
replace_once(
    'lib/screens/home_screen.dart',
    "        final columns = constraints.maxWidth >= 1250\n"
    "            ? 3\n"
    "            : constraints.maxWidth >= 760\n"
    "            ? 2\n"
    "            : 1;\n",
    "        final columns = _androidTvBuild\n"
    "            ? (constraints.maxWidth >= 1180 ? 3 : 2)\n"
    "            : constraints.maxWidth >= 1250\n"
    "            ? 3\n"
    "            : constraints.maxWidth >= 760\n"
    "            ? 2\n"
    "            : 1;\n",
    'grid servicios TV',
)

# ---------------------------------------------------------------------------
# 3) Selector TV/Películas/Series/Radio: 2 columnas estables en TV 720/1080p.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/source_content_screen.dart',
    "import 'xtream_series_screen.dart';\n",
    "import 'xtream_series_screen.dart';\n\n" + TV_DEFINE + "\n",
    'define Android TV content',
)
replace_once(
    'lib/screens/source_content_screen.dart',
    "          final wide = constraints.maxWidth >= 900;\n"
    "          final columns = constraints.maxWidth >= 1250\n"
    "              ? 4\n"
    "              : constraints.maxWidth >= 760\n"
    "              ? 2\n"
    "              : 1;\n",
    "          final wide = _androidTvBuild || constraints.maxWidth >= 900;\n"
    "          final columns = _androidTvBuild\n"
    "              ? (constraints.maxWidth >= 1500 ? 4 : 2)\n"
    "              : constraints.maxWidth >= 1250\n"
    "              ? 4\n"
    "              : constraints.maxWidth >= 760\n"
    "              ? 2\n"
    "              : 1;\n",
    'columnas selector TV',
)
replace_once(
    'lib/screens/source_content_screen.dart',
    "              final compact = constraints.maxWidth < 620;\n",
    "              final compact = !_androidTvBuild && constraints.maxWidth < 620;\n",
    'tarjetas verticales TV',
)

# ---------------------------------------------------------------------------
# 4) Catálogo: layout desktop forzado, sidebar menos invasivo y foco visible.
# ---------------------------------------------------------------------------
replace_once(
    'lib/screens/channel_list_screen.dart',
    "enum _CatalogMode { live, movies, series, radios }\n",
    TV_DEFINE + "\n\nenum _CatalogMode { live, movies, series, radios }\n",
    'define Android TV catalog',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "  double _sidebarWidth = 320;\n",
    "  double _sidebarWidth = _androidTvBuild ? 260 : 320;\n",
    'ancho sidebar TV',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "    final width = prefs.getDouble(_sidebarWidthKey) ?? 320;\n",
    "    final width = prefs.getDouble(_sidebarWidthKey) ?? (_androidTvBuild ? 260 : 320);\n",
    'preferencia sidebar TV',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "          if (constraints.maxWidth >= 900) {\n",
    "          if (_androidTvBuild || constraints.maxWidth >= 900) {\n",
    'layout desktop catálogo TV',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "        final columns = mode.usesPoster\n"
    "            ? (width >= 1500\n"
    "                  ? 7\n"
    "                  : width >= 1250\n"
    "                  ? 6\n"
    "                  : width >= 1000\n"
    "                  ? 5\n"
    "                  : 4)\n"
    "            : (width >= 1500\n"
    "                  ? 6\n"
    "                  : width >= 1250\n"
    "                  ? 5\n"
    "                  : width >= 1000\n"
    "                  ? 4\n"
    "                  : 3);\n",
    "        final columns = _androidTvBuild\n"
    "            ? (width >= 1450\n"
    "                  ? 6\n"
    "                  : width >= 1120\n"
    "                  ? 5\n"
    "                  : width >= 880\n"
    "                  ? 4\n"
    "                  : 3)\n"
    "            : mode.usesPoster\n"
    "            ? (width >= 1500\n"
    "                  ? 7\n"
    "                  : width >= 1250\n"
    "                  ? 6\n"
    "                  : width >= 1000\n"
    "                  ? 5\n"
    "                  : 4)\n"
    "            : (width >= 1500\n"
    "                  ? 6\n"
    "                  : width >= 1250\n"
    "                  ? 5\n"
    "                  : width >= 1000\n"
    "                  ? 4\n"
    "                  : 3);\n",
    'columnas catálogo TV',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "class _CatalogCardState extends State<_CatalogCard> {\n  bool _hovered = false;\n",
    "class _CatalogCardState extends State<_CatalogCard> {\n"
    "  bool _hovered = false;\n"
    "  bool _focused = false;\n",
    'estado foco cards',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "    final primary = Theme.of(context).colorScheme.primary;\n"
    "    return MouseRegion(\n",
    "    final primary = Theme.of(context).colorScheme.primary;\n"
    "    final highlighted = _hovered || _focused;\n"
    "    return MouseRegion(\n",
    'highlight cards',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "        scale: _hovered ? 1.025 : 1,\n",
    "        scale: highlighted ? (_androidTvBuild ? 1.045 : 1.025) : 1,\n",
    'escala foco TV',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "          elevation: _hovered ? 7 : 1,\n",
    "          elevation: highlighted ? 9 : 1,\n",
    'elevación foco TV',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "              color: _hovered\n"
    "                  ? primary.withValues(alpha: 0.75)\n"
    "                  : Colors.white.withValues(alpha: 0.08),\n"
    "              width: _hovered ? 1.4 : 1,\n",
    "              color: highlighted\n"
    "                  ? primary.withValues(alpha: 0.92)\n"
    "                  : Colors.white.withValues(alpha: 0.08),\n"
    "              width: highlighted ? (_androidTvBuild ? 2.3 : 1.4) : 1,\n",
    'borde foco TV',
)
replace_once(
    'lib/screens/channel_list_screen.dart',
    "          child: InkWell(\n"
    "            onTap: widget.onTap,\n",
    "          child: InkWell(\n"
    "            onFocusChange: (value) {\n"
    "              if (mounted) setState(() => _focused = value);\n"
    "            },\n"
    "            focusColor: primary.withValues(alpha: 0.18),\n"
    "            onTap: widget.onTap,\n",
    'foco InkWell cards',
)

# ---------------------------------------------------------------------------
# 5) Reproductor: remoto revela controles, TV usa layout no compacto y panel
# de canales proporcional. No se toca Player/media_kit ni la lógica de red.
# ---------------------------------------------------------------------------
replace_once(
    'lib/widgets/live_video_view.dart',
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
    'keyboard import TV player UI',
)
replace_once(
    'lib/widgets/live_video_view.dart',
    "import 'cached_artwork_image.dart';\n",
    "import 'cached_artwork_image.dart';\n\n" + TV_DEFINE + "\n",
    'define Android TV video UI',
)
replace_once(
    'lib/widgets/live_video_view.dart',
    "  void _toggleFit(VideoState videoState) {\n",
    "  KeyEventResult _handleTvKeyEvent(FocusNode node, KeyEvent event) {\n"
    "    if (!_androidTvBuild || event is! KeyDownEvent) {\n"
    "      return KeyEventResult.ignored;\n"
    "    }\n"
    "    _showOverlay();\n"
    "    return KeyEventResult.ignored;\n"
    "  }\n\n"
    "  void _toggleFit(VideoState videoState) {\n",
    'evento remoto TV',
)
replace_once(
    'lib/widgets/live_video_view.dart',
    "  Widget build(BuildContext context) {\n"
    "    return MouseRegion(\n"
    "      onHover: (_) => _showOverlay(),\n"
    "      child: Listener(\n"
    "        behavior: HitTestBehavior.translucent,\n"
    "        onPointerDown: (_) => _toggleOverlayFromPointer(),\n"
    "        child: Video(\n"
    "          controller: widget.controller,\n"
    "          fit: _videoFit,\n"
    "          controls: (videoState) => _buildControls(videoState),\n"
    "        ),\n"
    "      ),\n"
    "    );\n"
    "  }\n",
    "  Widget build(BuildContext context) {\n"
    "    final video = MouseRegion(\n"
    "      onHover: (_) => _showOverlay(),\n"
    "      child: Listener(\n"
    "        behavior: HitTestBehavior.translucent,\n"
    "        onPointerDown: (_) => _toggleOverlayFromPointer(),\n"
    "        child: Video(\n"
    "          controller: widget.controller,\n"
    "          fit: _videoFit,\n"
    "          controls: (videoState) => _buildControls(videoState),\n"
    "        ),\n"
    "      ),\n"
    "    );\n"
    "    if (!_androidTvBuild) return video;\n"
    "    return Focus(\n"
    "      autofocus: true,\n"
    "      onKeyEvent: _handleTvKeyEvent,\n"
    "      child: video,\n"
    "    );\n"
    "  }\n",
    'wrapper foco remoto',
)
replace_once(
    'lib/widgets/live_video_view.dart',
    "  Widget _buildControls(VideoState videoState) {\n"
    "    return IgnorePointer(\n"
    "      ignoring: !_overlayVisible,\n"
    "      child: AnimatedOpacity(\n",
    "  Widget _buildControls(VideoState videoState) {\n"
    "    return ExcludeFocus(\n"
    "      excluding: !_overlayVisible,\n"
    "      child: IgnorePointer(\n"
    "        ignoring: !_overlayVisible,\n"
    "        child: AnimatedOpacity(\n",
    'exclude focus controles ocultos',
)
# Cierra un nivel extra agregado por ExcludeFocus.
replace_once(
    'lib/widgets/live_video_view.dart',
    "        ),\n      ),\n    );\n  }\n\n  Widget _buildTopBar(VideoState videoState) {\n",
    "        ),\n      ),\n    ),\n    );\n  }\n\n  Widget _buildTopBar(VideoState videoState) {\n",
    'cierre ExcludeFocus',
)
replace_once(
    'lib/widgets/live_video_view.dart',
    "        final compact =\n"
    "            constraints.maxWidth < 980 ||\n"
    "            MediaQuery.sizeOf(context).height < 520;\n",
    "        final compact = _androidTvBuild\n"
    "            ? constraints.maxWidth < 720\n"
    "            : constraints.maxWidth < 980 ||\n"
    "                  MediaQuery.sizeOf(context).height < 520;\n"
    "        final compactControls =\n"
    "            compact || (_androidTvBuild && constraints.maxWidth < 1180);\n",
    'layout TV reproductor',
)
replace_once(
    'lib/widgets/live_video_view.dart',
    "            _buildControlRow(videoState, compact),\n",
    "            _buildControlRow(videoState, compactControls),\n",
    'controles compactos TV 720/1080',
)

replace_once(
    'lib/screens/player_screen.dart',
    "const String _legacyVlcUserAgent =\n"
    "    'VLC/3.0.20 LibVLC/3.0.20 (iptv_player; +https://github.com)';\n",
    "const String _legacyVlcUserAgent =\n"
    "    'VLC/3.0.20 LibVLC/3.0.20 (iptv_player; +https://github.com)';\n"
    + TV_DEFINE + "\n",
    'define Android TV player',
)
replace_once(
    'lib/screens/player_screen.dart',
    "    final errorAccent = isChannelMaintenance\n"
    "        ? Colors.amberAccent\n"
    "        : Colors.redAccent;\n\n"
    "    return Scaffold(\n",
    "    final errorAccent = isChannelMaintenance\n"
    "        ? Colors.amberAccent\n"
    "        : Colors.redAccent;\n"
    "    final screenWidth = MediaQuery.sizeOf(context).width;\n"
    "    final channelPanelWidth = _androidTvBuild\n"
    "        ? (screenWidth * 0.34).clamp(330.0, 460.0).toDouble()\n"
    "        : 370.0;\n\n"
    "    return Scaffold(\n",
    'panel canales TV',
)
replace_once(
    'lib/screens/player_screen.dart',
    "            right: _showChannelList ? 0 : -370,\n"
    "            width: 370,\n",
    "            right: _showChannelList ? 0 : -channelPanelWidth,\n"
    "            width: channelPanelWidth,\n",
    'ancho dinámico panel canales',
)

print('Android TV V1 patches applied successfully')
