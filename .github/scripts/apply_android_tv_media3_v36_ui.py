from pathlib import Path
import re

LIVE = Path('lib/widgets/live_video_view.dart')
CATALOG = Path('lib/screens/channel_list_screen.dart')
CHANNEL = Path('lib/widgets/channel_tile.dart')

live = LIVE.read_text()
catalog = CATALOG.read_text()
channel = CHANNEL.read_text()


def rep(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label} marker not found')

# 1) Android TV catalog: remove every favorite heart from channel cards/rows.
# Provider/model favorite state remains untouched for compatibility; only the TV
# interaction is removed so DPAD/OK cannot accidentally toggle favorites.
channel = re.sub(
    r"\s*trailing:\s*IconButton\(\s*icon:\s*Icon\(\s*isFavorite\s*\?\s*Icons\.favorite\s*:\s*Icons\.favorite_border,\s*color:\s*isFavorite\s*\?\s*Colors\.redAccent\s*:\s*null,\s*\),\s*onPressed:\s*onFavoriteToggle,\s*\),",
    '\n      trailing: null,',
    channel,
    flags=re.S,
)

# The main catalog uses four independent favorite IconButtons (desktop/compact,
# live/poster cards). Remove those blocks robustly by matching their tooltip + icon.
favorite_button = re.compile(
    r"\s*IconButton\(\s*tooltip:\s*isFavorite\s*\?\s*'Quitar de favoritos'\s*:\s*'Agregar a favoritos',\s*onPressed:\s*onFavoriteToggle,\s*icon:\s*Icon\(\s*isFavorite\s*\?\s*Icons\.favorite\s*:\s*Icons\.favorite_border,\s*size:\s*20,\s*\),\s*\),",
    re.S,
)
catalog, removed = favorite_button.subn('', catalog)
if removed < 1:
    raise SystemExit('V3.6 catalog favorite buttons not found')
if 'Icons.favorite' in catalog or 'Icons.favorite_border' in catalog:
    raise SystemExit('V3.6 favorite icon still present in channel_list_screen.dart')

# 2) Controls must reliably disappear during LIVE playback after no remote input.
# Native Media3 can briefly report buffering/recovery; that must not pin the UI.
live = rep(
    live,
    '  static const _overlayTimeout = Duration(seconds: 4);\n',
    '  static const _overlayTimeout = Duration(seconds: 3);\n',
    'v36 overlay timeout',
)
old_hide = '''  void _scheduleOverlayHide() {\n    _overlayTimer?.cancel();\n    if (!_playing || _buffering) return;\n    _overlayTimer = Timer(_overlayTimeout, () {\n      if (!mounted || !_playing || _buffering) return;\n      setState(() => _overlayVisible = false);\n    });\n  }\n'''
new_hide = '''  void _scheduleOverlayHide() {\n    _overlayTimer?.cancel();\n    if (_usesNativeLive) {\n      if (!_hasStarted || !_playing) return;\n    } else if (!_playing || _buffering) {\n      return;\n    }\n    _overlayTimer = Timer(_overlayTimeout, () {\n      if (!mounted) return;\n      if (_usesNativeLive) {\n        if (!_hasStarted || !_playing) return;\n      } else if (!_playing || _buffering) {\n        return;\n      }\n      if (_overlayVisible) setState(() => _overlayVisible = false);\n    });\n  }\n'''
live = rep(live, old_hide, new_hide, 'v36 reliable native overlay hide')

# Native LIVE controls from V3.4: visually scale the whole top/bottom UI instead
# of rewriting each button. This keeps focus targets/semantics intact while making
# the player noticeably smaller and the progress/buffer bar less intrusive.
old_controls = '''        Positioned(\n          left: 0,\n          right: 0,\n          top: 0,\n          child: _buildTopBar(videoState),\n        ),\n        Positioned(\n          left: 20,\n          right: 20,\n          bottom: 18,\n          child: SafeArea(\n            top: false,\n            child: Center(\n              child: ConstrainedBox(\n                constraints: const BoxConstraints(maxWidth: 1320),\n                child: _buildBottomArea(videoState),\n              ),\n            ),\n          ),\n        ),\n'''
new_controls = '''        Positioned(\n          left: 0,\n          right: 0,\n          top: 0,\n          child: Transform.scale(\n            scale: _usesNativeLive ? 0.82 : 1.0,\n            alignment: Alignment.topCenter,\n            child: _buildTopBar(videoState),\n          ),\n        ),\n        Positioned(\n          left: 28,\n          right: 28,\n          bottom: 10,\n          child: SafeArea(\n            top: false,\n            child: Center(\n              child: ConstrainedBox(\n                constraints: const BoxConstraints(maxWidth: 1120),\n                child: Transform.scale(\n                  scale: _usesNativeLive ? 0.82 : 1.0,\n                  alignment: Alignment.bottomCenter,\n                  child: _buildBottomArea(videoState),\n                ),\n              ),\n            ),\n          ),\n        ),\n'''
live = rep(live, old_controls, new_controls, 'v36 compact controls')

LIVE.write_text(live)
CATALOG.write_text(catalog)
CHANNEL.write_text(channel)
print(f'Android TV V3.6 UI applied: removed {removed} catalog favorite buttons, compact controls, reliable 3s auto-hide')
