from pathlib import Path

PLAYER = Path('lib/screens/player_screen.dart')
LIVE = Path('lib/widgets/live_video_view.dart')
CHANNEL = Path('lib/widgets/channel_tile.dart')
player = PLAYER.read_text()
live = LIVE.read_text()
channel = CHANNEL.read_text()


def rep(text, old, new, label):
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label} marker not found')

# Hide the per-channel favorite heart without changing provider/model APIs.
fav = """      trailing: IconButton(\n        icon: Icon(\n          isFavorite ? Icons.favorite : Icons.favorite_border,\n          color: isFavorite ? Colors.redAccent : null,\n        ),\n        onPressed: onFavoriteToggle,\n      ),\n"""
channel = rep(channel, fav, "      trailing: null,\n", 'favorite button')

# Explicit focus nodes for the top player row.
play_node = "  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: 'tv-play-pause');\n"
top_nodes = play_node + """  final FocusNode _topBackFocusNode = FocusNode(debugLabel: 'tv-top-back');\n  final FocusNode _topInfoFocusNode = FocusNode(debugLabel: 'tv-top-info');\n  final FocusNode _topListFocusNode = FocusNode(debugLabel: 'tv-top-list');\n"""
live = rep(live, play_node, top_nodes, 'top focus nodes')

# UP enters the top row; DOWN returns to the main bottom row.
nav = "    final navigationKey = key == LogicalKeyboardKey.arrowUp ||\n"
bridge = """    if (_overlayVisible && key == LogicalKeyboardKey.arrowUp) {\n      _topListFocusNode.requestFocus();\n      return KeyEventResult.handled;\n    }\n    if (_overlayVisible &&\n        key == LogicalKeyboardKey.arrowDown &&\n        (_topBackFocusNode.hasFocus ||\n            _topInfoFocusNode.hasFocus ||\n            _topListFocusNode.hasFocus)) {\n      _playPauseFocusNode.requestFocus();\n      return KeyEventResult.handled;\n    }\n\n""" + nav
live = rep(live, nav, bridge, 'DPAD row bridge')

# Top round buttons get focus feedback and optional explicit focus nodes.
sig = """  Widget _roundButton({\n    required IconData icon,\n    required String tooltip,\n    required VoidCallback onTap,\n  }) {\n"""
sig2 = """  Widget _roundButton({\n    required IconData icon,\n    required String tooltip,\n    FocusNode? focusNode,\n    required VoidCallback onTap,\n  }) {\n"""
live = rep(live, sig, sig2, 'round button signature')

start = live.find("  Widget _roundButton({")
end = live.find("\n  Widget _smallInfoChip({", start)
if start < 0 or end < 0:
    raise SystemExit('round button bounds not found')
block = live[start:end]
old_ink = """        child: InkWell(\n          customBorder: const CircleBorder(),\n"""
new_ink = """        child: InkWell(\n          focusNode: focusNode,\n          canRequestFocus: true,\n          focusColor: const Color(0xFF1677FF),\n          customBorder: const CircleBorder(),\n"""
if old_ink in block:
    block = block.replace(old_ink, new_ink, 1)
elif 'focusNode: focusNode' not in block:
    raise SystemExit('round button InkWell marker not found')
live = live[:start] + block + live[end:]

for old, new, label in [
    ("""            _roundButton(\n              icon: Icons.arrow_back_ios_new_rounded,\n              tooltip: 'Volver',\n""", """            _roundButton(\n              icon: Icons.arrow_back_ios_new_rounded,\n              tooltip: 'Volver',\n              focusNode: _topBackFocusNode,\n""", 'top back focus'),
    ("""            _roundButton(\n              icon: Icons.info_outline_rounded,\n              tooltip: 'Información del stream',\n""", """            _roundButton(\n              icon: Icons.info_outline_rounded,\n              tooltip: 'Información del stream',\n              focusNode: _topInfoFocusNode,\n""", 'top info focus'),
    ("""            _roundButton(\n              icon: Icons.view_list_rounded,\n              tooltip: 'Lista de canales',\n""", """            _roundButton(\n              icon: Icons.view_list_rounded,\n              tooltip: 'Lista de canales',\n              focusNode: _topListFocusNode,\n""", 'top list focus'),
]:
    live = rep(live, old, new, label)

# Dispose only the new nodes; locate the actual dispose method instead of
# depending on V2/V3 formatting around _playPauseFocusNode.
dstart = live.find("  @override\n  void dispose() {")
dend = live.find("\n  }", dstart)
if dstart < 0 or dend < 0:
    raise SystemExit('dispose method not found')
dispose_block = live[dstart:dend]
if '_topBackFocusNode.dispose();' not in dispose_block:
    if '    super.dispose();' not in dispose_block:
        raise SystemExit('super.dispose marker not found')
    dispose_block = dispose_block.replace(
        '    super.dispose();',
        """    _topBackFocusNode.dispose();\n    _topInfoFocusNode.dispose();\n    _topListFocusNode.dispose();\n    super.dispose();""",
        1,
    )
live = live[:dstart] + dispose_block + live[dend:]

# Native LIVE overlay: no opacity animation over Hybrid Composition.
cstart = live.find("  Widget _buildControls(VideoState? videoState) {")
cend = live.find("\n  Widget _buildTopBar(VideoState? videoState)", cstart)
if cstart < 0 or cend < 0:
    raise SystemExit('controls bounds not found')
controls = r'''  Widget _buildControls(VideoState? videoState) {
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
      return _overlayVisible ? controls : const SizedBox.shrink();
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
live = live[:cstart] + controls + live[cend:]

# After the first native frame, recovery remains active but no full-screen
# reconnect/buffering overlay covers the SurfaceView.
old_cond = """          if ((_useMedia3Live\n                  ? (!_nativeLiveStartedOnce || _showNativeRecoveryUi)\n                  : (_isBuffering || _reconnecting)) &&\n              _errorMessage == null)\n"""
new_cond = """          if ((_useMedia3Live\n                  ? !_nativeLiveStartedOnce\n                  : (_isBuffering || _reconnecting)) &&\n              _errorMessage == null)\n"""
player = rep(player, old_cond, new_cond, 'post-start reconnect overlay')

PLAYER.write_text(player)
LIVE.write_text(live)
CHANNEL.write_text(channel)
print('Android TV V3.4 UI patch applied')
