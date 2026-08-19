from pathlib import Path

PLAYER = Path('lib/screens/player_screen.dart')
LIVE = Path('lib/widgets/live_video_view.dart')
CHANNEL_TILE = Path('lib/widgets/channel_tile.dart')

player = PLAYER.read_text()
live = LIVE.read_text()
channel_tile = CHANNEL_TILE.read_text()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        if new in text:
            return text
        raise SystemExit(f'{label} marker not found')
    return text.replace(old, new, 1)


# 1) Android TV: remove the favorite heart from each channel row. We keep the
# existing callback fields/API so no panel/provider semantics are changed.
favorite_block = """      trailing: IconButton(\n        icon: Icon(\n          isFavorite ? Icons.favorite : Icons.favorite_border,\n          color: isFavorite ? Colors.redAccent : null,\n        ),\n        onPressed: onFavoriteToggle,\n      ),\n"""
channel_tile = replace_once(
    channel_tile,
    favorite_block,
    "      trailing: null,\n",
    'channel favorite button',
)

# 2) Full DPAD access: explicitly expose the top bar to focus traversal and add
# a deterministic UP/DOWN bridge between the bottom controls and the top row.
focus_marker = "  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: 'tv-play-pause');\n"
focus_fields = focus_marker + """  final FocusNode _topBackFocusNode = FocusNode(debugLabel: 'tv-top-back');\n  final FocusNode _topInfoFocusNode = FocusNode(debugLabel: 'tv-top-info');\n  final FocusNode _topListFocusNode = FocusNode(debugLabel: 'tv-top-list');\n"""
live = replace_once(live, focus_marker, focus_fields, 'v34 top focus nodes')

# Explicit row switching before normal directional traversal runs.
nav_marker = """    final navigationKey = key == LogicalKeyboardKey.arrowUp ||\n"""
nav_bridge = """    if (_overlayVisible && key == LogicalKeyboardKey.arrowUp) {\n      _topListFocusNode.requestFocus();\n      return KeyEventResult.handled;\n    }\n    if (_overlayVisible &&\n        key == LogicalKeyboardKey.arrowDown &&\n        (_topBackFocusNode.hasFocus ||\n            _topInfoFocusNode.hasFocus ||\n            _topListFocusNode.hasFocus)) {\n      _playPauseFocusNode.requestFocus();\n      return KeyEventResult.handled;\n    }\n\n""" + nav_marker
live = replace_once(live, nav_marker, nav_bridge, 'v34 DPAD row bridge')

# Give top buttons real focus nodes + visible focus feedback.
round_sig = """  Widget _roundButton({\n    required IconData icon,\n    required String tooltip,\n    required VoidCallback onTap,\n  }) {\n"""
round_sig_new = """  Widget _roundButton({\n    required IconData icon,\n    required String tooltip,\n    FocusNode? focusNode,\n    required VoidCallback onTap,\n  }) {\n"""
live = replace_once(live, round_sig, round_sig_new, 'v34 round button focus signature')

round_start = live.find("  Widget _roundButton({")
round_end = live.find("\n  Widget _smallInfoChip({", round_start)
if round_start == -1 or round_end == -1:
    raise SystemExit('v34 round button bounds not found')
round_block = live[round_start:round_end]
round_block_new = round_block.replace(
    """        child: InkWell(\n          customBorder: const CircleBorder(),\n""",
    """        child: InkWell(\n          focusNode: focusNode,\n          canRequestFocus: true,\n          focusColor: const Color(0xFF1677FF),\n          customBorder: const CircleBorder(),\n""",
    1,
)
if round_block_new == round_block:
    raise SystemExit('v34 round InkWell marker not found')
live = live[:round_start] + round_block_new + live[round_end:]

live = replace_once(
    live,
    """            _roundButton(\n              icon: Icons.arrow_back_ios_new_rounded,\n              tooltip: 'Volver',\n""",
    """            _roundButton(\n              icon: Icons.arrow_back_ios_new_rounded,\n              tooltip: 'Volver',\n              focusNode: _topBackFocusNode,\n""",
    'v34 top back focus',
)
live = replace_once(
    live,
    """            _roundButton(\n              icon: Icons.info_outline_rounded,\n              tooltip: 'Información del stream',\n""",
    """            _roundButton(\n              icon: Icons.info_outline_rounded,\n              tooltip: 'Información del stream',\n              focusNode: _topInfoFocusNode,\n""",
    'v34 top info focus',
)
live = replace_once(
    live,
    """            _roundButton(\n              icon: Icons.view_list_rounded,\n              tooltip: 'Lista de canales',\n""",
    """            _roundButton(\n              icon: Icons.view_list_rounded,\n              tooltip: 'Lista de canales',\n              focusNode: _topListFocusNode,\n""",
    'v34 top list focus',
)

live = replace_once(
    live,
    """    _playPauseFocusNode.dispose();\n""",
    """    _playPauseFocusNode.dispose();\n    _topBackFocusNode.dispose();\n    _topInfoFocusNode.dispose();\n    _topListFocusNode.dispose();\n""",
    'v34 dispose top focus nodes',
)

# 3) Hybrid Composition: no animated opacity for native LIVE controls. The
# video remains SurfaceView; controls simply appear/disappear, reducing jank on
# low-power TVs. VOD keeps the original AnimatedOpacity behavior.
controls_start = live.find("  Widget _buildControls(VideoState? videoState) {")
controls_end = live.find("\n  Widget _buildTopBar(VideoState? videoState)", controls_start)
if controls_start == -1 or controls_end == -1:
    raise SystemExit('v34 controls bounds not found')
controls_new = r'''  Widget _buildControls(VideoState? videoState) {
    final controls = Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _buildTopBar(videoState),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 18,
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: _buildBottomArea(videoState),
              ),
            ),
          ),
        ),
      ],
    );

    if (_usesNativeLive) {
      if (!_overlayVisible) return const SizedBox.shrink();
      return controls;
    }

    return IgnorePointer(
      ignoring: !_overlayVisible,
      child: AnimatedOpacity(
        opacity: _overlayVisible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: controls,
      ),
    );
  }
'''
live = live[:controls_start] + controls_new + live[controls_end:]

# 4) After the first Media3 frame, never cover the native SurfaceView with the
# blocking reconnect/buffering panel. Recovery still runs and terminal errors
# are still shown; only the transient full-screen Flutter overlay is removed.
old_overlay_condition = """          if ((_useMedia3Live\n                  ? (!_nativeLiveStartedOnce || _showNativeRecoveryUi)\n                  : (_isBuffering || _reconnecting)) &&\n              _errorMessage == null)\n"""
new_overlay_condition = """          if ((_useMedia3Live\n                  ? !_nativeLiveStartedOnce\n                  : (_isBuffering || _reconnecting)) &&\n              _errorMessage == null)\n"""
player = replace_once(
    player,
    old_overlay_condition,
    new_overlay_condition,
    'v34 post-start blocking overlay removal',
)

PLAYER.write_text(player)
LIVE.write_text(live)
CHANNEL_TILE.write_text(channel_tile)
print('Android TV V3.4 UI patch applied: favorites hidden, full DPAD focus, native LIVE overlays simplified')
