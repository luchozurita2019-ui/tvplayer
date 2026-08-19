from pathlib import Path

PLAYER = Path('lib/screens/player_screen.dart')
LIVE = Path('lib/widgets/live_video_view.dart')

player = PLAYER.read_text()
live = LIVE.read_text()


def rep(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label} marker not found')

# Distinguish a real user pause from Media3 temporarily reporting isPlaying=false
# while buffering/recovering. Media3 docs define playWhenReady as user intent;
# isPlaying also becomes false during BUFFERING, so it must not drive the PAUSA UI.
player = rep(
    player,
    """  bool _nativeLiveBufferingSignal = false;\n  bool _showNativeRecoveryUi = false;\n  double _nativeLiveVolume = 100;\n""",
    """  bool _nativeLiveBufferingSignal = false;\n  bool _showNativeRecoveryUi = false;\n  bool _nativeLiveUserPaused = false;\n  String _nativeVideoDecoderName = 'desconocido';\n  double _nativeLiveVolume = 100;\n""",
    'v35 native pause fields',
)

old_is_playing = """      case 'isPlaying':\n        final value = event['value'] == true;\n        if (value) {\n          _nativeLiveBufferingSignal = false;\n          _nativeLiveRecoveryUiTimer?.cancel();\n          _nativeLiveRecoveryUiTimer = null;\n        }\n        setState(() {\n          _isPlaying = value;\n          if (value) {\n            _isBuffering = false;\n            _showNativeRecoveryUi = false;\n          }\n        });\n        return;\n"""
new_is_playing = """      case 'isPlaying':\n        final value = event['value'] == true;\n        if (value) {\n          _nativeLiveBufferingSignal = false;\n          _nativeLiveRecoveryUiTimer?.cancel();\n          _nativeLiveRecoveryUiTimer = null;\n        }\n        setState(() {\n          if (value) {\n            _isPlaying = true;\n            _isBuffering = false;\n            _showNativeRecoveryUi = false;\n          } else if (_nativeLiveUserPaused) {\n            _isPlaying = false;\n          }\n          // Si isPlaying=false por BUFFERING pero playWhenReady sigue true,\n          // mantenemos el estado visual de reproducción. No es una pausa real.\n        });\n        return;\n      case 'playWhenReady':\n        final wantsPlay = event['value'] == true;\n        _nativeLiveUserPaused = !wantsPlay;\n        setState(() {\n          if (!wantsPlay) {\n            _isPlaying = false;\n            _isBuffering = false;\n            _reconnecting = false;\n            _showNativeRecoveryUi = false;\n          } else if (_nativeLiveStartedOnce) {\n            _isPlaying = true;\n          }\n        });\n        return;\n      case 'decoder':\n        _nativeVideoDecoderName =\n            event['value']?.toString().trim().isNotEmpty == true\n                ? event['value'].toString().trim()\n                : 'desconocido';\n        setState(() {\n          _engineDiagnostic = 'Media3 decoder: $_nativeVideoDecoderName';\n        });\n        return;\n      case 'videoFormat':\n        final mime = event['mime']?.toString();\n        final codecs = event['codecs']?.toString();\n        final width = event['width'];\n        final height = event['height'];\n        final fps = event['fps'];\n        setState(() {\n          if (width is int && width > 0) _videoWidth = width;\n          if (height is int && height > 0) _videoHeight = height;\n          if (fps is num && fps > 0) _videoFps = fps.toDouble();\n          final codecText = (codecs != null && codecs.trim().isNotEmpty)\n              ? codecs.trim()\n              : (mime ?? '').replaceFirst('video/', '');\n          if (codecText.isNotEmpty) _videoCodec = codecText;\n          _engineDiagnostic =\n              'Media3 · $_nativeVideoDecoderName · ${_videoWidth ?? '?'}x${_videoHeight ?? '?'}';\n        });\n        return;\n      case 'droppedFrames':\n        final count = event['count'];\n        if (count is int && count > 0) {\n          setState(() {\n            _engineDiagnostic =\n                'Media3 · $_nativeVideoDecoderName · $count frames perdidos';\n          });\n        }\n        return;\n"""
player = rep(player, old_is_playing, new_is_playing, 'v35 Media3 state semantics')

# A zap starts a fresh user-intent session. Internal retry keeps the existing
# intent, so transient recovery never fabricates a PAUSA state.
player = rep(
    player,
    """    if (isZap) {\n      _nativeLiveRecoveryUiTimer?.cancel();\n      _nativeLiveRecoveryUiTimer = null;\n      _nativeLiveStartedOnce = false;\n      _nativeLiveBufferingSignal = false;\n      _showNativeRecoveryUi = false;\n    }\n""",
    """    if (isZap) {\n      _nativeLiveRecoveryUiTimer?.cancel();\n      _nativeLiveRecoveryUiTimer = null;\n      _nativeLiveStartedOnce = false;\n      _nativeLiveBufferingSignal = false;\n      _showNativeRecoveryUi = false;\n      _nativeLiveUserPaused = false;\n      _nativeVideoDecoderName = 'desconocido';\n    }\n""",
    'v35 zap pause reset',
)

player = rep(
    player,
    """    _hasEverPlayed = false;\n    _isPlaying = false;\n    _isBuffering = isRetry && _nativeLiveStartedOnce ? false : true;\n    _reconnecting = isRetry;\n""",
    """    _hasEverPlayed = false;\n    _isPlaying = isRetry && _nativeLiveStartedOnce && !_nativeLiveUserPaused;\n    _isBuffering = isRetry && _nativeLiveStartedOnce ? false : true;\n    _reconnecting = isRetry;\n""",
    'v35 retry visual play state',
)

# Preserve PLAY icon only for an actual user pause. During recovery the player
# controls remain in the LIVE intent state even if Media3 is momentarily buffering.
player = rep(
    player,
    """              nativeLivePlaying: _isPlaying,\n              nativeLiveBuffering: _isBuffering,\n""",
    """              nativeLivePlaying: _nativeLiveUserPaused\n                  ? false\n                  : (_nativeLiveStartedOnce ? true : _isPlaying),\n              nativeLiveBuffering: _nativeLiveUserPaused\n                  ? false\n                  : (_nativeLiveStartedOnce\n                      ? _showNativeRecoveryUi\n                      : _isBuffering),\n""",
    'v35 stable native live visual state',
)

# Native LIVE status labels: PAUSA only means an explicit pause. A sustained
# network/stream interruption is shown as RECUPERANDO, never as PAUSA->BUFFER.
old_status = """  String get _statusLabel {\n    if (!_hasStarted) return 'CARGANDO';\n    if (_buffering) return 'BUFFER';\n    if (!_playing) return 'PAUSA';\n    return _isActuallyLive ? 'EN VIVO' : 'RECUPERANDO';\n  }\n"""
new_status = """  String get _statusLabel {\n    if (!_hasStarted) return 'CARGANDO';\n    if (_usesNativeLive) {\n      if (!_playing) return 'PAUSA';\n      if (_buffering) return 'RECUPERANDO';\n      return 'EN VIVO';\n    }\n    if (_buffering) return 'BUFFER';\n    if (!_playing) return 'PAUSA';\n    return _isActuallyLive ? 'EN VIVO' : 'RECUPERANDO';\n  }\n"""
live = rep(live, old_status, new_status, 'v35 native status label')

PLAYER.write_text(player)
LIVE.write_text(live)
print('Android TV V3.5 stability UI applied: real pause semantics, quiet recovery, decoder diagnostics')
