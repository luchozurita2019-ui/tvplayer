from pathlib import Path

LIVE = Path('lib/widgets/live_video_view.dart')
text = LIVE.read_text()

# TV remote keys are handled only in the visual layer. Playback/network logic is
# intentionally untouched.
if "package:flutter/services.dart" not in text:
    text = text.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';",
        1,
    )

if "final FocusNode _remoteFocusNode" not in text:
    marker = "  Timer? _overlayTimer;\n"
    if marker not in text:
        raise SystemExit('overlay timer marker not found')
    text = text.replace(
        marker,
        marker + "  final FocusNode _remoteFocusNode = FocusNode(debugLabel: 'tv-live-remote');\n",
        1,
    )

old_position = """    _positionSub = widget.player.stream.position.listen((value) {\n      if (!mounted) return;\n      if (value != _position) {\n        _position = value;\n        _lastProgressAt = DateTime.now();\n      }\n      setState(() {});\n    });\n"""
new_position = """    _positionSub = widget.player.stream.position.listen((value) {\n      if (!mounted) return;\n      final changed = value != _position;\n      if (changed) {\n        _position = value;\n        _lastProgressAt = DateTime.now();\n      }\n      // En LIVE no reconstruimos el árbol del Video por cada tick de posición.\n      // En VOD sólo refrescamos el progreso mientras los controles están visibles.\n      if (!widget.isLiveContent && changed && _overlayVisible) {\n        setState(() {});\n      }\n    });\n"""
if old_position in text:
    text = text.replace(old_position, new_position, 1)
elif "En LIVE no reconstruimos el árbol del Video" not in text:
    raise SystemExit('position listener marker not found')

old_volume = """    _volumeSub = widget.player.stream.volume.listen((value) {\n      if (!mounted) return;\n      setState(() => _volume = value.clamp(0, 100).toDouble());\n    });\n"""
new_volume = """    _volumeSub = widget.player.stream.volume.listen((value) {\n      if (!mounted) return;\n      _volume = value.clamp(0, 100).toDouble();\n      if (_overlayVisible) setState(() {});\n    });\n"""
if old_volume in text:
    text = text.replace(old_volume, new_volume, 1)
elif "if (_overlayVisible) setState(() {});" not in text:
    raise SystemExit('volume listener marker not found')

old_timer = """    _statusTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {\n      if (mounted && widget.isLiveContent) setState(() {});\n    });\n"""
new_timer = """    _statusTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {\n      if (mounted && widget.isLiveContent && _overlayVisible) setState(() {});\n    });\n"""
if old_timer in text:
    text = text.replace(old_timer, new_timer, 1)
elif "Duration(milliseconds: 1500)" not in text:
    raise SystemExit('status timer marker not found')

if "KeyEventResult _handleTvRemoteKey" not in text:
    marker = "  @override\n  void dispose() {\n"
    handler = r'''  KeyEventResult _handleTvRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      if (widget.canNext) widget.onNext();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (widget.canPrevious) widget.onPrevious();
      return KeyEventResult.handled;
    }

    final navigationKey = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select;
    if (navigationKey && !_overlayVisible) {
      _showOverlay(scheduleHide: false);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

'''
    if marker not in text:
        raise SystemExit('dispose marker not found')
    text = text.replace(marker, handler + marker, 1)

if "_remoteFocusNode.dispose();" not in text:
    marker = "    _overlayTimer?.cancel();\n"
    if marker not in text:
        raise SystemExit('dispose overlay marker not found')
    text = text.replace(
        marker,
        marker + "    _remoteFocusNode.dispose();\n",
        1,
    )

old_build = """  @override\n  Widget build(BuildContext context) {\n    return MouseRegion(\n      onHover: (_) => _showOverlay(),\n      child: Listener(\n        behavior: HitTestBehavior.translucent,\n        onPointerDown: (_) => _showOverlay(),\n        child: Video(\n          controller: widget.controller,\n          fit: _videoFit,\n          controls: (videoState) => _buildControls(videoState),\n        ),\n      ),\n    );\n  }\n"""
new_build = """  @override\n  Widget build(BuildContext context) {\n    return Focus(\n      focusNode: _remoteFocusNode,\n      autofocus: true,\n      onKeyEvent: _handleTvRemoteKey,\n      child: RepaintBoundary(\n        child: MouseRegion(\n          onHover: (_) => _showOverlay(),\n          child: Listener(\n            behavior: HitTestBehavior.translucent,\n            onPointerDown: (_) => _showOverlay(),\n            child: Video(\n              controller: widget.controller,\n              fit: _videoFit,\n              controls: (videoState) => _buildControls(videoState),\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n"""
if old_build in text:
    text = text.replace(old_build, new_build, 1)
elif "onKeyEvent: _handleTvRemoteKey" not in text:
    raise SystemExit('build marker not found')

LIVE.write_text(text)
print('Android TV runtime optimization applied')
