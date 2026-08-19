from pathlib import Path

LIVE = Path('lib/widgets/live_video_view.dart')
PLAYER = Path('lib/screens/player_screen.dart')
text = LIVE.read_text()
player = PLAYER.read_text()

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
    handler = r'''  void _seekTvRelative(int seconds) {
    if (widget.isLiveContent || _duration <= Duration.zero) return;
    final maxMs = _duration.inMilliseconds;
    final targetMs = (_position.inMilliseconds + (seconds * 1000))
        .clamp(0, maxMs)
        .toInt();
    _showOverlay();
    unawaited(widget.player.seek(Duration(milliseconds: targetMs)));
  }

  KeyEventResult _handleTvRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.channelUp) {
      if (widget.canNext) widget.onNext();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious ||
        key == LogicalKeyboardKey.channelDown) {
      if (widget.canPrevious) widget.onPrevious();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekTvRelative(10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      _seekTvRelative(-10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.info) {
      widget.onShowStreamInfo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.guide) {
      _showOverlay(scheduleHide: false);
      widget.onShowChannelList();
      return KeyEventResult.handled;
    }
    if (!widget.isLiveContent && key == LogicalKeyboardKey.mediaAudioTrack) {
      unawaited(_showAudioTrackPicker());
      return KeyEventResult.handled;
    }
    if (!widget.isLiveContent && key == LogicalKeyboardKey.subtitle) {
      unawaited(_showSubtitleTrackPicker());
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

# While the channel drawer is closed, do not build/filter its channel catalog at
# all. On low-RAM TVs this keeps the video surface from competing with an
# invisible ListView and its widgets.
old_filter = """    final query = _channelListQuery.toLowerCase();\n    final filteredChannels = query.trim().isEmpty\n        ? widget.playlist\n        : widget.playlist\n              .where((c) => c.name.toLowerCase().contains(query))\n              .toList();\n"""
new_filter = """    final query = _channelListQuery.toLowerCase();\n    final filteredChannels = !_showChannelList\n        ? const <Channel>[]\n        : query.trim().isEmpty\n            ? widget.playlist\n            : widget.playlist\n                .where((c) => c.name.toLowerCase().contains(query))\n                .toList();\n"""
if old_filter in player:
    player = player.replace(old_filter, new_filter, 1)
elif "final filteredChannels = !_showChannelList" not in player:
    raise SystemExit('player channel filter marker not found')

old_drawer = """          AnimatedPositioned(\n            duration: const Duration(milliseconds: 200),\n            curve: Curves.easeOutCubic,\n            top: 0,\n            bottom: 0,\n            right: _showChannelList ? 0 : -370,\n            width: 370,\n"""
new_drawer = """          if (_showChannelList)\n            Positioned(\n              top: 0,\n              bottom: 0,\n              right: 0,\n              width: 370,\n"""
if old_drawer in player:
    player = player.replace(old_drawer, new_drawer, 1)
elif "if (_showChannelList)\n            Positioned(" not in player:
    raise SystemExit('player drawer marker not found')

LIVE.write_text(text)
PLAYER.write_text(player)
print('Android TV runtime optimization applied')
