from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: {label}: expected exactly 1 match, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


player = Path('lib/screens/player_screen.dart')

# Constants: HotPlayer binary contains seg_max_retry=5. We use the same HLS
# segment retry count and debounce transient live errors before reopening Media.
replace_once(
    player,
    """  static const String _fastProbeSize = '131072';\n  static const String _normalProbeSize = '5000000';\n""",
    """  static const String _fastProbeSize = '131072';\n  static const String _normalProbeSize = '5000000';\n  static const int _hlsSegmentRetryCount = 5;\n  static const Duration _liveTransientErrorGrace = Duration(seconds: 6);\n""",
    'add HotPlayer-inspired live constants',
)

replace_once(
    player,
    """  Timer? _connectTimeoutTimer;\n  Timer? _retryTimer;\n  Duration _lastKnownPosition = Duration.zero;\n""",
    """  Timer? _connectTimeoutTimer;\n  Timer? _retryTimer;\n  Timer? _transientLiveFailureTimer;\n  Duration _lastKnownPosition = Duration.zero;\n""",
    'add transient live failure timer',
)

# A successful recovery cancels a pending app-level restart.
replace_once(
    player,
    """      if (!buffering) {\n        _connectTimeoutTimer?.cancel();\n        _retryTimer?.cancel();\n        _retryTimer = null;\n        _hasEverPlayed = true;\n""",
    """      if (!buffering) {\n        _connectTimeoutTimer?.cancel();\n        _retryTimer?.cancel();\n        _retryTimer = null;\n        _transientLiveFailureTimer?.cancel();\n        _transientLiveFailureTimer = null;\n        _hasEverPlayed = true;\n""",
    'cancel live failure timer after buffering recovers',
)

# Runtime errors on an already-playing live stream are often transient network
# events. Let FFmpeg retry first instead of immediately tearing down the Media.
replace_once(
    player,
    """    _errorSub = _player.stream.error.listen((error) {\n      if (_opening) return;\n      _handleFailure('Error de reproducción: $error');\n    });\n""",
    """    _errorSub = _player.stream.error.listen((error) {\n      if (_opening) return;\n      final message = 'Error de reproducción: $error';\n      if (widget.isLiveContent && _hasEverPlayed) {\n        _scheduleTransientLiveFailure(message);\n        return;\n      }\n      _handleFailure(message);\n    });\n""",
    'debounce transient live player errors',
)

replace_once(
    player,
    """    _positionSub = _player.stream.position.listen((position) {\n      if (position != _lastKnownPosition) {\n        _lastKnownPosition = position;\n        _lastProgressAt = DateTime.now();\n      }\n    });\n""",
    """    _positionSub = _player.stream.position.listen((position) {\n      if (position != _lastKnownPosition) {\n        _lastKnownPosition = position;\n        _lastProgressAt = DateTime.now();\n        _transientLiveFailureTimer?.cancel();\n        _transientLiveFailureTimer = null;\n      }\n    });\n""",
    'cancel pending restart when frames progress',
)

# Live cache should stay memory-only and never preserve played data backwards.
replace_once(
    player,
    """        if (widget.isLiveContent) {\n          await platform.setProperty('demuxer-max-back-bytes', '0');\n        }\n""",
    """        if (widget.isLiveContent) {\n          await platform.setProperty('demuxer-max-back-bytes', '0');\n          await platform.setProperty('cache-on-disk', 'no');\n        }\n""",
    'disable disk/back cache for live',
)

# Auto mode was becoming too aggressive after fast startups. Keep fast probing,
# but give live streams a small stability floor so normal jitter does not starve
# the demuxer and trigger an unnecessary Media reopen.
replace_once(
    player,
    """    _effectiveSettings = tuning.settings;\n    _tuningLabel = tuning.label;\n    _useFastProbe = tuning.useFastProbe;\n""",
    """    final tunedSettings = tuning.settings;\n    final applyLiveStabilityFloor =\n        widget.isLiveContent && widget.settings.profile == BufferProfile.auto;\n    _effectiveSettings = applyLiveStabilityFloor\n        ? tunedSettings.copyWith(\n            bufferMb: tunedSettings.bufferMb < 16 ? 16 : tunedSettings.bufferMb,\n            readaheadSeconds: tunedSettings.readaheadSeconds < 2.5\n                ? 2.5\n                : tunedSettings.readaheadSeconds,\n            recoveryBufferSeconds: tunedSettings.recoveryBufferSeconds < 1.5\n                ? 1.5\n                : tunedSettings.recoveryBufferSeconds,\n            connectTimeoutSeconds: tunedSettings.connectTimeoutSeconds < 8\n                ? 8\n                : tunedSettings.connectTimeoutSeconds,\n            stallThresholdSeconds: tunedSettings.stallThresholdSeconds < 12\n                ? 12\n                : tunedSettings.stallThresholdSeconds,\n          )\n        : tunedSettings;\n    _tuningLabel = applyLiveStabilityFloor\n        ? '${tuning.label} · Live estable'\n        : tuning.label;\n    _useFastProbe = tuning.useFastProbe;\n""",
    'add live stability floor in auto mode',
)

# HotPlayer contains network-timeout and uses media_kit/mpv. Tie mpv's timeout
# to our already-selected adaptive server timeout.
replace_once(
    player,
    """        await platform.setProperty(\n          'demuxer-max-bytes',\n          '${_effectiveSettings.bufferMb}MiB',\n        );\n        await platform.setProperty(\n          'demuxer-lavf-probesize',\n""",
    """        await platform.setProperty(\n          'demuxer-max-bytes',\n          '${_effectiveSettings.bufferMb}MiB',\n        );\n        await platform.setProperty(\n          'network-timeout',\n          _effectiveSettings.connectTimeoutSeconds.toString(),\n        );\n        await platform.setProperty(\n          'demuxer-lavf-probesize',\n""",
    'apply native network timeout',
)

# Replace the V3.7 recovery-only transport setup with a two-level strategy:
# 1) FFmpeg handles transient live failures from the first open.
# 2) App-level compatibility fallback remains available only if low-level
#    recovery cannot keep the stream moving.
old_transport = """        final recoveryMode =\n            _compatibilityMode == ServerCompatibilityMode.liveRecovery ||\n                _compatibilityMode == ServerCompatibilityMode.advanced;\n        if (recoveryMode) {\n          final isAdvanced =\n              _compatibilityMode == ServerCompatibilityMode.advanced;\n\n          // reconnect_at_eof es sólo para señales live/endless. En VOD puede\n          // convertir el final normal de una película en una reapertura.\n          final reconnectOptions = widget.isLiveContent\n              ? (isAdvanced\n                  ? 'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'\n                      'reconnect_on_network_error=1,'\n                      'reconnect_on_http_error=408,429,5xx,'\n                      'reconnect_delay_max=2'\n                  : 'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'\n                      'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'\n                      'reconnect_delay_max=1')\n              : (isAdvanced\n                  ? 'reconnect=1,reconnect_streamed=1,'\n                      'reconnect_on_network_error=1,'\n                      'reconnect_on_http_error=408,429,5xx,'\n                      'reconnect_delay_max=2'\n                  : 'reconnect=1,reconnect_streamed=1,'\n                      'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'\n                      'reconnect_delay_max=1');\n          await platform.setProperty('stream-lavf-o', reconnectOptions);\n\n          // Si sabemos que es HLS en vivo, al reabrir empezamos en el último\n          // segmento disponible en vez de varios segmentos atrás. Esto reduce\n          // la repetición de escenas después de un corte.\n          if (widget.isLiveContent && _looksLikeHls(channel.url)) {\n            await platform.setProperty(\n              'demuxer-lavf-o',\n              'live_start_index=-1',\n            );\n          }\n        }\n"""
new_transport = """        final recoveryMode =\n            _compatibilityMode == ServerCompatibilityMode.liveRecovery ||\n                _compatibilityMode == ServerCompatibilityMode.advanced;\n        final isAdvanced =\n            _compatibilityMode == ServerCompatibilityMode.advanced;\n        final isLiveHttp = widget.isLiveContent && _isHttpUrl(channel.url);\n        final isLiveHls = widget.isLiveContent && _looksLikeHls(channel.url);\n\n        // Hallazgo confirmado en HotPlayer Mac: seg_max_retry=5. Hacemos que\n        // FFmpeg reintente el segmento HLS antes de considerar caído el canal.\n        // live_start_index=-1 mantiene una reapertura pegada al borde en vivo.\n        if (isLiveHls) {\n          await platform.setProperty(\n            'demuxer-lavf-o',\n            'seg_max_retry=$_hlsSegmentRetryCount,live_start_index=-1',\n          );\n        }\n\n        // En live HTTP la recuperación de transporte trabaja desde la primera\n        // apertura, no sólo después de que Flutter reinicie el Media. Esto evita\n        // muchos cortes visibles y repeticiones de escenas.\n        if (isLiveHttp) {\n          final reconnectOptions = <String>[\n            'reconnect=1',\n            'reconnect_streamed=1',\n            'reconnect_on_network_error=1',\n            'reconnect_at_eof=1',\n            if (recoveryMode) 'reconnect_on_http_error=5xx',\n            'reconnect_delay_max=${isAdvanced ? 2 : 1}',\n          ].join(',');\n          await platform.setProperty('stream-lavf-o', reconnectOptions);\n        } else if (recoveryMode) {\n          // VOD puede reconectar errores de red, pero nunca reabrimos por EOF:\n          // el final de una película o episodio es un final real.\n          final reconnectOptions = <String>[\n            'reconnect=1',\n            'reconnect_streamed=1',\n            'reconnect_on_network_error=1',\n            'reconnect_on_http_error=5xx',\n            'reconnect_delay_max=${isAdvanced ? 2 : 1}',\n          ].join(',');\n          await platform.setProperty('stream-lavf-o', reconnectOptions);\n        }\n"""
replace_once(player, old_transport, new_transport, 'install low-level live recovery')

# Give the low-level engine time to retry segments/connections before Flutter
# performs a destructive reopen. Dead channels still fall back automatically.
old_stall = """    // Mientras mpv está oficialmente en buffering le damos un margen extra\n    // para que la reconexión nativa actúe antes de reiniciar el Media. Reiniciar\n    // demasiado pronto era una causa de volver a segmentos HLS ya vistos.\n    final bufferingGrace = Duration(\n      seconds: _stallThreshold.inSeconds < 8\n          ? 12\n          : _stallThreshold.inSeconds + 4,\n    );\n    final effectiveStallThreshold =\n        _isBuffering ? bufferingGrace : _stallThreshold;\n"""
new_stall = """    // HotPlayer deja que FFmpeg intente recuperar segmentos antes de\n    // reconstruir la reproducción. En live damos ese mismo margen: un microcorte\n    // no debe convertirse en stop/open del Media.\n    final liveGrace = widget.isLiveContent\n        ? Duration(\n            seconds: _stallThreshold.inSeconds < 15\n                ? 15\n                : _stallThreshold.inSeconds,\n          )\n        : _stallThreshold;\n    final bufferingGrace = widget.isLiveContent\n        ? Duration(\n            seconds: _stallThreshold.inSeconds + 8 < 20\n                ? 20\n                : _stallThreshold.inSeconds + 8,\n          )\n        : Duration(\n            seconds: _stallThreshold.inSeconds < 8\n                ? 12\n                : _stallThreshold.inSeconds + 4,\n          );\n    final effectiveStallThreshold =\n        _isBuffering ? bufferingGrace : liveGrace;\n"""
replace_once(player, old_stall, new_stall, 'extend live engine recovery grace')

# HTTP helper next to HLS detection.
replace_once(
    player,
    """  bool _looksLikeHls(String url) {\n""",
    """  bool _isHttpUrl(String url) {\n    final uri = Uri.tryParse(url);\n    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');\n  }\n\n  bool _looksLikeHls(String url) {\n""",
    'add HTTP live helper',
)

# Debounce method immediately before the normal failure path.
replace_once(
    player,
    """  void _handleFailure(String message, {bool silent = false}) {\n""",
    """  void _scheduleTransientLiveFailure(String message) {\n    _transientLiveFailureTimer?.cancel();\n    final session = _sessionId;\n    final progressAtError = _lastProgressAt;\n\n    if (mounted) {\n      setState(() {\n        _engineDiagnostic =\n            'Corte transitorio: FFmpeg está intentando recuperar la señal';\n      });\n    }\n\n    _transientLiveFailureTimer = Timer(_liveTransientErrorGrace, () {\n      _transientLiveFailureTimer = null;\n      if (!mounted ||\n          session != _sessionId ||\n          _opening ||\n          _reconnecting ||\n          _errorMessage != null) {\n        return;\n      }\n\n      // Si hubo progreso desde el error, la recuperación nativa funcionó.\n      if (_lastProgressAt.isAfter(progressAtError)) return;\n      _handleFailure(message, silent: true);\n    });\n  }\n\n  void _handleFailure(String message, {bool silent = false}) {\n""",
    'add transient live failure debounce',
)

replace_once(
    player,
    """    _connectTimeoutTimer?.cancel();\n    _retryTimer?.cancel();\n\n    final failedSession = _sessionId;\n""",
    """    _connectTimeoutTimer?.cancel();\n    _retryTimer?.cancel();\n    _transientLiveFailureTimer?.cancel();\n    _transientLiveFailureTimer = null;\n\n    final failedSession = _sessionId;\n""",
    'cancel transient timer on real failure',
)

replace_once(
    player,
    """    _connectTimeoutTimer?.cancel();\n    _retryTimer?.cancel();\n    _retryTimer = null;\n\n    if (!isRetry) {\n""",
    """    _connectTimeoutTimer?.cancel();\n    _retryTimer?.cancel();\n    _retryTimer = null;\n    _transientLiveFailureTimer?.cancel();\n    _transientLiveFailureTimer = null;\n\n    if (!isRetry) {\n""",
    'cancel transient timer before new open',
)

replace_once(
    player,
    """    _connectTimeoutTimer?.cancel();\n    _retryTimer?.cancel();\n    _bufferingSub?.cancel();\n""",
    """    _connectTimeoutTimer?.cancel();\n    _retryTimer?.cancel();\n    _transientLiveFailureTimer?.cancel();\n    _bufferingSub?.cancel();\n""",
    'dispose transient live timer',
)

print('V3.7.2 HotPlayer-inspired live recovery patch applied')
