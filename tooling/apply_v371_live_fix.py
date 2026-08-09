from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: {label}: expected exactly 1 match, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


# 1) Live controls: no elapsed/duration numbers for live/radio; keep them for VOD.
live_view = Path('lib/widgets/live_video_view.dart')
replace_once(
    live_view,
    '''  final bool canPrevious;\n  final bool canNext;\n\n  const LiveVideoView({\n''',
    '''  final bool canPrevious;\n  final bool canNext;\n  final bool isLiveContent;\n\n  const LiveVideoView({\n''',
    'add live-content field',
)
replace_once(
    live_view,
    '''    required this.canPrevious,\n    required this.canNext,\n  });\n''',
    '''    required this.canPrevious,\n    required this.canNext,\n    this.isLiveContent = true,\n  });\n''',
    'add live-content constructor arg',
)
replace_once(
    live_view,
    '''      const MaterialDesktopVolumeButton(),\n      const MaterialDesktopPositionIndicator(),\n      _LiveControlIndicator(\n        active: _isLive,\n        label: _statusLabel,\n      ),\n      const Spacer(),\n''',
    '''      const MaterialDesktopVolumeButton(),\n      if (!widget.isLiveContent) const MaterialDesktopPositionIndicator(),\n      if (widget.isLiveContent)\n        _LiveControlIndicator(\n          active: _isLive,\n          label: _statusLabel,\n        ),\n      const Spacer(),\n''',
    'conditional timeline/live indicator',
)


# 2) Catalog tells the player whether this section is live or VOD.
channel_list = Path('lib/screens/channel_list_screen.dart')
replace_once(
    channel_list,
    '''          initialIndex: index,\n          settings: provider.playbackSettings,\n        ),\n''',
    '''          initialIndex: index,\n          settings: provider.playbackSettings,\n          isLiveContent:\n              _mode == _CatalogMode.live || _mode == _CatalogMode.radios,\n        ),\n''',
    'pass content mode to player',
)


# 3) Player: separate live semantics from VOD and reduce replay after stalls.
player = Path('lib/screens/player_screen.dart')
replace_once(
    player,
    '''  final int initialIndex;\n  final PlaybackSettings settings;\n\n  const PlayerScreen({\n''',
    '''  final int initialIndex;\n  final PlaybackSettings settings;\n  final bool isLiveContent;\n\n  const PlayerScreen({\n''',
    'player live-content field',
)
replace_once(
    player,
    '''    required this.initialIndex,\n    required this.settings,\n  });\n''',
    '''    required this.initialIndex,\n    required this.settings,\n    this.isLiveContent = true,\n  });\n''',
    'player live-content constructor arg',
)
replace_once(
    player,
    '''        await platform.setProperty('cache-pause', 'no');\n        await platform.setProperty('cache-pause-initial', 'no');\n        await platform.setProperty('demuxer-thread', 'yes');\n''',
    '''        await platform.setProperty('cache-pause', 'no');\n        await platform.setProperty('cache-pause-initial', 'no');\n        await platform.setProperty('demuxer-thread', 'yes');\n\n        // En TV en vivo no necesitamos conservar paquetes ya reproducidos.\n        // Un back-buffer grande puede volver a mostrar escenas viejas después\n        // de un corte/reapertura. Películas y series mantienen su cache normal.\n        if (widget.isLiveContent) {\n          await platform.setProperty('demuxer-max-back-bytes', '0');\n        }\n''',
    'disable live back buffer',
)
replace_once(
    player,
    '''        final recoveryMode =\n            _compatibilityMode == ServerCompatibilityMode.liveRecovery ||\n                _compatibilityMode == ServerCompatibilityMode.advanced;\n        if (recoveryMode) {\n          final reconnectOptions =\n              _compatibilityMode == ServerCompatibilityMode.advanced\n                  ? 'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'\n                      'reconnect_on_network_error=1,'\n                      'reconnect_on_http_error=408,429,5xx,'\n                      'reconnect_delay_max=2'\n                  : 'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'\n                      'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'\n                      'reconnect_delay_max=1';\n          await platform.setProperty('stream-lavf-o', reconnectOptions);\n        }\n''',
    '''        final recoveryMode =\n            _compatibilityMode == ServerCompatibilityMode.liveRecovery ||\n                _compatibilityMode == ServerCompatibilityMode.advanced;\n        if (recoveryMode) {\n          final isAdvanced =\n              _compatibilityMode == ServerCompatibilityMode.advanced;\n\n          // reconnect_at_eof es sólo para señales live/endless. En VOD puede\n          // convertir el final normal de una película en una reapertura.\n          final reconnectOptions = widget.isLiveContent\n              ? (isAdvanced\n                  ? 'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'\n                      'reconnect_on_network_error=1,'\n                      'reconnect_on_http_error=408,429,5xx,'\n                      'reconnect_delay_max=2'\n                  : 'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'\n                      'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'\n                      'reconnect_delay_max=1')\n              : (isAdvanced\n                  ? 'reconnect=1,reconnect_streamed=1,'\n                      'reconnect_on_network_error=1,'\n                      'reconnect_on_http_error=408,429,5xx,'\n                      'reconnect_delay_max=2'\n                  : 'reconnect=1,reconnect_streamed=1,'\n                      'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'\n                      'reconnect_delay_max=1');\n          await platform.setProperty('stream-lavf-o', reconnectOptions);\n\n          // Si sabemos que es HLS en vivo, al reabrir empezamos en el último\n          // segmento disponible en vez de varios segmentos atrás. Esto reduce\n          // la repetición de escenas después de un corte.\n          if (widget.isLiveContent && _looksLikeHls(channel.url)) {\n            await platform.setProperty(\n              'demuxer-lavf-o',\n              'live_start_index=-1',\n            );\n          }\n        }\n''',
    'content-aware reconnect options',
)
replace_once(
    player,
    '''  void _checkStall() {\n    if (!mounted || _opening || _reconnecting || _errorMessage != null) {\n      return;\n    }\n    if (!_isPlaying || !_hasEverPlayed) return;\n\n    final silentFor = DateTime.now().difference(_lastProgressAt);\n    if (silentFor > _stallThreshold) {\n      final url = widget.playlist[_currentIndex].url;\n      unawaited(_metrics.recordStall(url));\n      _handleFailure('El stream dejó de responder', silent: true);\n    }\n  }\n''',
    '''  void _checkStall() {\n    if (!mounted || _opening || _reconnecting || _errorMessage != null) {\n      return;\n    }\n    if (!_isPlaying || !_hasEverPlayed) return;\n\n    final silentFor = DateTime.now().difference(_lastProgressAt);\n\n    // Mientras mpv está oficialmente en buffering le damos un margen extra\n    // para que la reconexión nativa actúe antes de reiniciar el Media. Reiniciar\n    // demasiado pronto era una causa de volver a segmentos HLS ya vistos.\n    final bufferingGrace = Duration(\n      seconds: _stallThreshold.inSeconds < 8\n          ? 12\n          : _stallThreshold.inSeconds + 4,\n    );\n    final effectiveStallThreshold =\n        _isBuffering ? bufferingGrace : _stallThreshold;\n\n    if (silentFor > effectiveStallThreshold) {\n      final url = widget.playlist[_currentIndex].url;\n      unawaited(_metrics.recordStall(url));\n      _handleFailure('El stream dejó de responder', silent: true);\n    }\n  }\n\n  bool _looksLikeHls(String url) {\n    final value = url.toLowerCase();\n    final format = _containerFormat?.toLowerCase() ?? '';\n    return value.contains('.m3u8') ||\n        format.contains('hls') ||\n        format.contains('applehttp');\n  }\n''',
    'buffering grace and HLS detection',
)
replace_once(
    player,
    '''  Future<void> _handleCompletedStream() async {\n    final channel = widget.playlist[_currentIndex];\n    final uri = Uri.tryParse(channel.url);\n''',
    '''  Future<void> _handleCompletedStream() async {\n    // Películas y series tienen un final real. No debemos interpretarlo como\n    // una caída de señal y volver a abrir el archivo desde el principio.\n    if (!widget.isLiveContent) {\n      _connectTimeoutTimer?.cancel();\n      _retryTimer?.cancel();\n      if (mounted) {\n        setState(() {\n          _isBuffering = false;\n          _reconnecting = false;\n          _engineDiagnostic = 'Reproducción finalizada correctamente';\n        });\n      }\n      return;\n    }\n\n    final channel = widget.playlist[_currentIndex];\n    final uri = Uri.tryParse(channel.url);\n''',
    'do not reopen completed VOD',
)
replace_once(
    player,
    '''          _playCurrent(\n            isRetry: true,\n            forceNormalProbe: true,\n            skipStop: true,\n          ),\n''',
    '''          _playCurrent(\n            isRetry: true,\n            forceNormalProbe: true,\n          ),\n''',
    'clear old live cache on EOF reopen',
)
replace_once(
    player,
    '''    scheduleMicrotask(() {\n      if (!mounted) return;\n      unawaited(_playCurrent(isRetry: true, forceNormalProbe: true));\n    });\n    return true;\n  }\n\n  void _handlePlayerLog(PlayerLog log) {\n''',
    '''    final resumePosition =\n        widget.isLiveContent ? null : _lastKnownPosition;\n    scheduleMicrotask(() {\n      if (!mounted) return;\n      unawaited(\n        _playCurrent(\n          isRetry: true,\n          forceNormalProbe: true,\n          resumePosition: resumePosition,\n        ),\n      );\n    });\n    return true;\n  }\n\n  void _handlePlayerLog(PlayerLog log) {\n''',
    'resume VOD after runtime promotion',
)
replace_once(
    player,
    '''      _retryTimer = Timer(Duration(seconds: seconds), () {\n        if (!mounted || failedSession != _sessionId) return;\n        unawaited(_playCurrent(isRetry: true, forceNormalProbe: true));\n      });\n''',
    '''      final resumePosition =\n          widget.isLiveContent ? null : _lastKnownPosition;\n      _retryTimer = Timer(Duration(seconds: seconds), () {\n        if (!mounted || failedSession != _sessionId) return;\n        unawaited(\n          _playCurrent(\n            isRetry: true,\n            forceNormalProbe: true,\n            resumePosition: resumePosition,\n          ),\n        );\n      });\n''',
    'resume VOD on automatic retry',
)
replace_once(
    player,
    '''  Future<void> _playCurrent({\n    bool isRetry = false,\n    bool forceNormalProbe = false,\n    bool skipStop = false,\n  }) async {\n''',
    '''  Future<void> _playCurrent({\n    bool isRetry = false,\n    bool forceNormalProbe = false,\n    bool skipStop = false,\n    Duration? resumePosition,\n  }) async {\n''',
    'add VOD resume position',
)
replace_once(
    player,
    '''      await _player\n          .open(Media(channel.url, httpHeaders: headers))\n          .timeout(_connectTimeout);\n      if (!mounted || session != _sessionId) return;\n\n      _opening = false;\n''',
    '''      await _player\n          .open(Media(channel.url, httpHeaders: headers))\n          .timeout(_connectTimeout);\n      if (!mounted || session != _sessionId) return;\n\n      if (!widget.isLiveContent &&\n          resumePosition != null &&\n          resumePosition > Duration.zero) {\n        try {\n          await _player.seek(resumePosition);\n        } catch (_) {\n          // Si el servidor VOD no admite seek, seguimos desde donde permita.\n        }\n      }\n\n      _opening = false;\n''',
    'seek VOD after recovery',
)
replace_once(
    player,
    '''                  onPrevious: _previous,\n                  onNext: _next,\n                ),\n''',
    '''                  onPrevious: _previous,\n                  onNext: _next,\n                  isLiveContent: widget.isLiveContent,\n                ),\n''',
    'pass live mode to controls',
)

print('V3.7.1 live/VOD controls and recovery fixes applied')
