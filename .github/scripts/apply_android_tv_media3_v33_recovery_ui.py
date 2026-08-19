from pathlib import Path

PLAYER = Path('lib/screens/player_screen.dart')
LIVE = Path('lib/widgets/live_video_view.dart')

player = PLAYER.read_text()
live = LIVE.read_text()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        if new in text:
            return text
        raise SystemExit(f'{label} marker not found')
    return text.replace(old, new, 1)


# V3.3 keeps the successful Media3 + SurfaceView + Hybrid Composition renderer.
# Only the visible recovery/buffering state is debounced so very short LIVE EOS
# recoveries do not flash an animated Flutter overlay over the native SurfaceView.
player = replace_once(
    player,
    """  Timer? _nativeLiveReconnectTimer;\n  double _nativeLiveVolume = 100;\n""",
    """  Timer? _nativeLiveReconnectTimer;\n  Timer? _nativeLiveRecoveryUiTimer;\n  bool _nativeLiveStartedOnce = false;\n  bool _nativeLiveBufferingSignal = false;\n  bool _showNativeRecoveryUi = false;\n  double _nativeLiveVolume = 100;\n""",
    'v33 native recovery fields',
)

player = replace_once(
    player,
    """      case 'buffering':\n        setState(() {\n          _isBuffering = true;\n          _engineDiagnostic = 'Media3 · recibiendo buffer';\n        });\n        return;\n""",
    """      case 'buffering':\n        _nativeLiveBufferingSignal = true;\n        if (!_nativeLiveStartedOnce) {\n          setState(() {\n            _isBuffering = true;\n            _engineDiagnostic = 'Media3 · recibiendo buffer';\n          });\n        } else if (!(_nativeLiveRecoveryUiTimer?.isActive ?? false) &&\n            !_showNativeRecoveryUi) {\n          _nativeLiveRecoveryUiTimer =\n              Timer(const Duration(milliseconds: 1200), () {\n            _nativeLiveRecoveryUiTimer = null;\n            if (!mounted ||\n                !_nativeLiveBufferingSignal ||\n                !_nativeLiveStartedOnce ||\n                _errorMessage != null) {\n              return;\n            }\n            setState(() {\n              _isBuffering = true;\n              _showNativeRecoveryUi = true;\n              _engineDiagnostic = 'Media3 · buffer sostenido';\n            });\n          });\n        }\n        return;\n""",
    'v33 buffering debounce',
)

player = replace_once(
    player,
    """      case 'ready':\n        setState(() {\n          _isBuffering = false;\n          _reconnecting = false;\n        });\n        return;\n""",
    """      case 'ready':\n        _nativeLiveBufferingSignal = false;\n        _nativeLiveRecoveryUiTimer?.cancel();\n        _nativeLiveRecoveryUiTimer = null;\n        setState(() {\n          _isBuffering = false;\n          _reconnecting = false;\n          _showNativeRecoveryUi = false;\n        });\n        return;\n""",
    'v33 ready clears recovery ui',
)

player = replace_once(
    player,
    """      case 'isPlaying':\n        final value = event['value'] == true;\n        setState(() {\n          _isPlaying = value;\n          if (value) _isBuffering = false;\n        });\n        return;\n""",
    """      case 'isPlaying':\n        final value = event['value'] == true;\n        if (value) {\n          _nativeLiveBufferingSignal = false;\n          _nativeLiveRecoveryUiTimer?.cancel();\n          _nativeLiveRecoveryUiTimer = null;\n        }\n        setState(() {\n          _isPlaying = value;\n          if (value) {\n            _isBuffering = false;\n            _showNativeRecoveryUi = false;\n          }\n        });\n        return;\n""",
    'v33 playing clears transient recovery ui',
)

player = replace_once(
    player,
    """    _connectTimeoutTimer?.cancel();\n    _nativeLiveReconnectTimer?.cancel();\n    _hasEverPlayed = true;\n    _isPlaying = true;\n    _isBuffering = false;\n    _reconnecting = false;\n""",
    """    _connectTimeoutTimer?.cancel();\n    _nativeLiveReconnectTimer?.cancel();\n    _nativeLiveRecoveryUiTimer?.cancel();\n    _nativeLiveRecoveryUiTimer = null;\n    _nativeLiveStartedOnce = true;\n    _nativeLiveBufferingSignal = false;\n    _showNativeRecoveryUi = false;\n    _hasEverPlayed = true;\n    _isPlaying = true;\n    _isBuffering = false;\n    _reconnecting = false;\n""",
    'v33 first frame marks persistent native start',
)

player = replace_once(
    player,
    """    final controller = _nativeLiveController;\n    if (controller == null || !mounted) return;\n\n    final session = ++_sessionId;\n""",
    """    final controller = _nativeLiveController;\n    if (controller == null || !mounted) return;\n\n    if (isZap) {\n      _nativeLiveRecoveryUiTimer?.cancel();\n      _nativeLiveRecoveryUiTimer = null;\n      _nativeLiveStartedOnce = false;\n      _nativeLiveBufferingSignal = false;\n      _showNativeRecoveryUi = false;\n    }\n\n    final session = ++_sessionId;\n""",
    'v33 reset persistent start only on zap',
)

player = replace_once(
    player,
    """    _isPlaying = false;\n    _isBuffering = true;\n    _reconnecting = isRetry;\n""",
    """    _isPlaying = false;\n    _isBuffering = isRetry && _nativeLiveStartedOnce ? false : true;\n    _reconnecting = isRetry;\n""",
    'v33 retry stays visually quiet',
)

player = replace_once(
    player,
    """    final hadPlayback = _hasEverPlayed;\n""",
    """    final hadPlayback = _nativeLiveStartedOnce || _hasEverPlayed;\n""",
    'v33 persistent playback history',
)

player = replace_once(
    player,
    """      setState(() {\n        _isBuffering = true;\n        _reconnecting = true;\n        _engineDiagnostic = '$message · reintento Media3 $_retryCount/$maxRetries';\n      });\n      _nativeLiveReconnectTimer?.cancel();\n""",
    """      setState(() {\n        _isBuffering = hadPlayback ? false : true;\n        _reconnecting = true;\n        if (!hadPlayback) _showNativeRecoveryUi = true;\n        _engineDiagnostic = '$message · reintento Media3 $_retryCount/$maxRetries';\n      });\n      if (hadPlayback &&\n          !(_nativeLiveRecoveryUiTimer?.isActive ?? false) &&\n          !_showNativeRecoveryUi) {\n        _nativeLiveRecoveryUiTimer =\n            Timer(const Duration(milliseconds: 1200), () {\n          _nativeLiveRecoveryUiTimer = null;\n          if (!mounted ||\n              !_reconnecting ||\n              !_nativeLiveStartedOnce ||\n              _errorMessage != null) {\n            return;\n          }\n          setState(() {\n            _showNativeRecoveryUi = true;\n            _isBuffering = true;\n          });\n        });\n      }\n      _nativeLiveReconnectTimer?.cancel();\n""",
    'v33 delayed reconnect indicator',
)

player = replace_once(
    player,
    """    _startupStopwatch?.stop();\n    _zapStopwatch?.stop();\n    _zapSession = null;\n    setState(() {\n""",
    """    _startupStopwatch?.stop();\n    _zapStopwatch?.stop();\n    _zapSession = null;\n    _nativeLiveRecoveryUiTimer?.cancel();\n    _nativeLiveRecoveryUiTimer = null;\n    _showNativeRecoveryUi = false;\n    setState(() {\n""",
    'v33 clear recovery ui on terminal failure',
)

# Only show the blocking center overlay immediately during initial startup.
# After the first native frame it appears only if recovery lasts > 1.2 seconds.
player = replace_once(
    player,
    """          if ((_isBuffering || _reconnecting) && _errorMessage == null)\n""",
    """          if ((_useMedia3Live\n                  ? (!_nativeLiveStartedOnce || _showNativeRecoveryUi)\n                  : (_isBuffering || _reconnecting)) &&\n              _errorMessage == null)\n""",
    'v33 blocking overlay condition',
)

# Hybrid Composition can make continuously animated Flutter indicators look
# choppy over a SurfaceView on older TV hardware. For post-start recovery use
# a static sync glyph; the video itself stays native and untouched.
player = replace_once(
    player,
    """                        const SizedBox(\n                          width: 30,\n                          height: 30,\n                          child: CircularProgressIndicator(\n                            color: Colors.white,\n                            strokeWidth: 2.5,\n                          ),\n                        ),\n""",
    """                        if (_useMedia3Live && _nativeLiveStartedOnce)\n                          const Icon(\n                            Icons.sync_rounded,\n                            color: Colors.white,\n                            size: 30,\n                          )\n                        else\n                          const SizedBox(\n                            width: 30,\n                            height: 30,\n                            child: CircularProgressIndicator(\n                              color: Colors.white,\n                              strokeWidth: 2.5,\n                            ),\n                          ),\n""",
    'v33 static native recovery icon',
)

player = replace_once(
    player,
    """    _nativeLiveReconnectTimer?.cancel();\n    _nativeLiveEventsSub?.cancel();\n""",
    """    _nativeLiveReconnectTimer?.cancel();\n    _nativeLiveRecoveryUiTimer?.cancel();\n    _nativeLiveEventsSub?.cancel();\n""",
    'v33 dispose recovery timer',
)

# Keep the LIVE progress bar static after the first native frame. This avoids
# the indeterminate LinearProgressIndicator animation fighting Hybrid Composition.
live = replace_once(
    live,
    """              value: _isActuallyLive ? 1 : null,\n""",
    """              value: _usesNativeLive && _hasStarted\n                  ? 1\n                  : (_isActuallyLive ? 1 : null),\n""",
    'v33 static native live bar',
)

PLAYER.write_text(player)
LIVE.write_text(live)
print('Android TV V3.3 quiet Media3 recovery UI applied; native playback unchanged')
