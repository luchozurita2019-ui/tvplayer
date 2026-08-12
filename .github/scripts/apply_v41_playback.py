from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    text = text.replace(old, new, 1)


replace_once(
    """  static const Duration _watchdogInterval = Duration(seconds: 2);\n  static const String _fastProbeSize = '131072';\n  static const String _normalProbeSize = '5000000';\n  static const int _hlsSegmentRetryCount = 5;\n  static const Duration _liveTransientErrorGrace = Duration(seconds: 15);\n""",
    """  static const Duration _watchdogInterval = Duration(seconds: 2);\n  static const String _fastProbeSize = '131072';\n  static const String _liveProbeSize = '524288';\n  static const String _normalProbeSize = '5000000';\n  static const int _hlsSegmentRetryCount = 5;\n  static const Duration _liveTransientErrorGrace = Duration(seconds: 15);\n  static const Duration _liveStartupAttemptTimeout = Duration(seconds: 5);\n  static const int _maxLiveStartupCompatibilityFallbacks = 1;\n  static const String _channelMaintenanceMessage =\n      'Este canal no se encuentra disponible en este momento.\\n'\n      'Por favor, intentá nuevamente más tarde.';\n""",
    'constants',
)

replace_once(
    """  bool _runtimeFormatLoaded = false;\n  bool _acceptPlaybackEvents = true;\n  bool _providerIssueHint = false;\n""",
    """  bool _runtimeFormatLoaded = false;\n  bool _acceptPlaybackEvents = true;\n  bool _providerIssueHint = false;\n  bool _startupCompatibilityHint = false;\n""",
    'startup hint flag',
)

replace_once(
    """  String? _errorMessage;\n  String _channelListQuery = '';\n""",
    """  String? _errorTitle;\n  String? _errorMessage;\n  String _channelListQuery = '';\n""",
    'error title',
)

replace_once(
    """  ServerCompatibilityMode _compatibilityMode =\n      ServerCompatibilityMode.direct;\n  String? _compatibilityUrl;\n  String _engineDiagnostic = 'Sin errores de red detectados';\n""",
    """  ServerCompatibilityMode _compatibilityMode =\n      ServerCompatibilityMode.direct;\n  ServerCompatibilityMode? _startupCompatibilityTarget;\n  int? _terminalStartupSession;\n  String? _compatibilityUrl;\n  String _engineDiagnostic = 'Sin errores de red detectados';\n""",
    'startup compatibility state',
)

replace_once(
    """  Duration get _connectTimeout =>\n      Duration(seconds: _effectiveSettings.connectTimeoutSeconds);\n\n  @override\n""",
    """  Duration get _connectTimeout =>\n      Duration(seconds: _effectiveSettings.connectTimeoutSeconds);\n\n  Duration get _startupAttemptTimeout {\n    final configured = _connectTimeout;\n    if (!widget.isLiveContent ||\n        _hasEverPlayed ||\n        widget.settings.profile == BufferProfile.slowConnection) {\n      return configured;\n    }\n    return configured.inMilliseconds <=\n            _liveStartupAttemptTimeout.inMilliseconds\n        ? configured\n        : _liveStartupAttemptTimeout;\n  }\n\n  @override\n""",
    'startup attempt timeout getter',
)

replace_once(
    """    _errorSub = _player.stream.error.listen((error) {\n      if (_opening) return;\n      final message = 'Error de reproducción: $error';\n      if (widget.isLiveContent && _hasEverPlayed) {\n        _scheduleTransientLiveFailure(message);\n        return;\n      }\n      _handleFailure(message);\n    });\n""",
    """    _errorSub = _player.stream.error.listen((error) {\n      final rawError = error.toString();\n      if (_opening && widget.isLiveContent && !_hasEverPlayed) {\n        final text = rawError.toLowerCase();\n        _rememberStartupCompatibilityHint(text);\n        if (_isDefinitiveStartupFailureLog(text)) {\n          scheduleMicrotask(() {\n            if (!mounted) return;\n            _showChannelMaintenance('Fallo definitivo durante la apertura: $rawError');\n          });\n        }\n        return;\n      }\n      if (_opening) return;\n      final message = 'Error de reproducción: $rawError';\n      if (widget.isLiveContent && _hasEverPlayed) {\n        _scheduleTransientLiveFailure(message);\n        return;\n      }\n      _handleFailure(message);\n    });\n""",
    'startup error listener',
)

replace_once(
    """        await platform.setProperty(\n          'demuxer-lavf-probesize',\n          _currentOpenUsesFastProbe ? _fastProbeSize : _normalProbeSize,\n        );\n        await platform.setProperty(\n          'demuxer-lavf-probescore',\n          _currentOpenUsesFastProbe ? '15' : '26',\n        );\n""",
    """        final useLiveStartupProbe = widget.isLiveContent &&\n            !forceNormalProbe &&\n            _compatibilityMode != ServerCompatibilityMode.compatible &&\n            _compatibilityMode != ServerCompatibilityMode.advanced;\n        final probeSize = useLiveStartupProbe\n            ? _liveProbeSize\n            : (_currentOpenUsesFastProbe ? _fastProbeSize : _normalProbeSize);\n        final probeScore = useLiveStartupProbe\n            ? '20'\n            : (_currentOpenUsesFastProbe ? '15' : '26');\n        await platform.setProperty('demuxer-lavf-probesize', probeSize);\n        await platform.setProperty('demuxer-lavf-probescore', probeScore);\n""",
    'live probe tuning',
)

helper_anchor = """  void _handlePlayerLog(PlayerLog log) {\n"""
helpers = """  ServerCompatibilityMode? _compatibilityTargetForStartupLog(String text) {\n    final lower = text.toLowerCase();\n    final channelUrl = widget.playlist[_currentIndex].url;\n\n    if ((lower.contains('404') || lower.contains('not found')) &&\n        _looksLikeXtreamLiveTs(channelUrl) &&\n        _compatibilityMode != ServerCompatibilityMode.xtreamHls) {\n      return ServerCompatibilityMode.xtreamHls;\n    }\n    if (lower.contains('403') || lower.contains('forbidden')) {\n      return ServerCompatibilityMode.mpvHttp;\n    }\n    if (lower.contains('certificate') ||\n        lower.contains('tls') ||\n        lower.contains('ssl')) {\n      return ServerCompatibilityMode.tlsLegacy;\n    }\n    if (lower.contains('mime') ||\n        lower.contains('invalid data') ||\n        lower.contains('could not find codec parameters')) {\n      return ServerCompatibilityMode.compatible;\n    }\n    return null;\n  }\n\n  void _rememberStartupCompatibilityHint(String text) {\n    if (!widget.isLiveContent || _hasEverPlayed) return;\n    final target = _compatibilityTargetForStartupLog(text);\n    if (target == null || target == _compatibilityMode) return;\n    _startupCompatibilityHint = true;\n    _startupCompatibilityTarget = target;\n  }\n\n  bool _isDefinitiveStartupFailureLog(String text) {\n    if (!widget.isLiveContent || _hasEverPlayed) return false;\n    final lower = text.toLowerCase();\n\n    // Un 404 en un endpoint Xtream .ts merece un único intento HLS porque\n    // algunos paneles publican el mismo stream sólo como .m3u8. El resto de\n    // 404/410/401 y errores de servidor no mejoran repitiendo ocho modos.\n    if ((lower.contains('404') || lower.contains('not found')) &&\n        _compatibilityTargetForStartupLog(lower) ==\n            ServerCompatibilityMode.xtreamHls) {\n      return false;\n    }\n\n    return lower.contains('401') ||\n        lower.contains('unauthorized') ||\n        lower.contains('404') ||\n        lower.contains('not found') ||\n        lower.contains('410') ||\n        lower.contains(' gone') ||\n        lower.contains('429') ||\n        lower.contains('too many requests') ||\n        lower.contains('connection refused') ||\n        lower.contains('service unavailable') ||\n        lower.contains('bad gateway') ||\n        lower.contains('gateway timeout') ||\n        (RegExp(r'\\b5\\d\\d\\b').hasMatch(lower) && lower.contains('http'));\n  }\n\n  void _showChannelMaintenance(String diagnostic) {\n    if (!mounted || !widget.isLiveContent || _hasEverPlayed) return;\n    final session = _sessionId;\n    if (_terminalStartupSession == session) return;\n    _terminalStartupSession = session;\n\n    _connectTimeoutTimer?.cancel();\n    _retryTimer?.cancel();\n    _transientLiveFailureTimer?.cancel();\n    _transientLiveFailureTimer = null;\n    _startupStopwatch?.stop();\n    _zapStopwatch?.stop();\n    _zapSession = null;\n    _opening = false;\n    _acceptPlaybackEvents = false;\n\n    final url = widget.playlist[_currentIndex].url;\n    unawaited(_metrics.recordFailure(url));\n    unawaited(_compatibility.recordFailure(url, _compatibilityMode));\n    unawaited(_player.stop());\n\n    setState(() {\n      _isBuffering = false;\n      _reconnecting = false;\n      _errorTitle = 'CANAL EN MANTENIMIENTO';\n      _errorMessage = _channelMaintenanceMessage;\n      _engineDiagnostic = diagnostic;\n    });\n  }\n\n"""
replace_once(helper_anchor, helpers + helper_anchor, 'startup failure helpers')

replace_once(
    """  bool _advanceCompatibilityMode(String reason) {\n    if (_hasEverPlayed ||\n        _compatibilityIndex >= _compatibilityPlan.length - 1) {\n      return false;\n    }\n\n    final url = widget.playlist[_currentIndex].url;\n    final previous = _compatibilityMode;\n    unawaited(_compatibility.recordFailure(url, previous));\n\n    _compatibilityIndex++;\n    _compatibilityFallbacks++;\n    _compatibilityMode = _compatibilityPlan[_compatibilityIndex];\n    _normalProbeFallbackUsed = true;\n    _retryCount = 0;\n""",
    """  bool _advanceCompatibilityMode(\n    String reason, {\n    ServerCompatibilityMode? preferredTarget,\n  }) {\n    if (_hasEverPlayed || _compatibilityPlan.isEmpty) {\n      return false;\n    }\n    if (widget.isLiveContent &&\n        _compatibilityFallbacks >= _maxLiveStartupCompatibilityFallbacks) {\n      return false;\n    }\n\n    var nextIndex = _compatibilityIndex + 1;\n    if (preferredTarget != null) {\n      final targetedIndex = _compatibilityPlan.indexOf(preferredTarget);\n      if (targetedIndex >= 0 && targetedIndex != _compatibilityIndex) {\n        nextIndex = targetedIndex;\n      }\n    }\n    if (nextIndex < 0 || nextIndex >= _compatibilityPlan.length) {\n      return false;\n    }\n\n    final url = widget.playlist[_currentIndex].url;\n    final previous = _compatibilityMode;\n    unawaited(_compatibility.recordFailure(url, previous));\n\n    _compatibilityIndex = nextIndex;\n    _compatibilityFallbacks++;\n    _compatibilityMode = _compatibilityPlan[_compatibilityIndex];\n    _normalProbeFallbackUsed = true;\n    _retryCount = 0;\n""",
    'bounded targeted compatibility fallback',
)

replace_once(
    """    if (!_hasEverPlayed && _advanceCompatibilityMode(message)) {\n      return;\n    }\n\n    unawaited(_metrics.recordFailure(url));\n""",
    """    if (!_hasEverPlayed && widget.isLiveContent) {\n      final elapsedMs = _startupStopwatch?.elapsedMilliseconds ?? 999999;\n      final failedQuickly = elapsedMs < 2500;\n      final shouldTryCompatibility =\n          _startupCompatibilityHint || failedQuickly;\n      if (shouldTryCompatibility &&\n          _advanceCompatibilityMode(\n            message,\n            preferredTarget: _startupCompatibilityTarget,\n          )) {\n        return;\n      }\n\n      _showChannelMaintenance(message);\n      return;\n    }\n\n    if (!_hasEverPlayed && _advanceCompatibilityMode(message)) {\n      return;\n    }\n\n    unawaited(_metrics.recordFailure(url));\n""",
    'live startup failure policy',
)

replace_once(
    """  }) async {\n    final session = ++_sessionId;\n    _opening = true;\n    _acceptPlaybackEvents = false;\n""",
    """  }) async {\n    final session = ++_sessionId;\n    _terminalStartupSession = null;\n    _startupCompatibilityHint = false;\n    _startupCompatibilityTarget = null;\n    _opening = true;\n    _acceptPlaybackEvents = false;\n""",
    'play attempt reset',
)

replace_once(
    """      setState(() {\n        _errorMessage = null;\n        _isBuffering = isZap ? false : true;\n""",
    """      setState(() {\n        _errorTitle = null;\n        _errorMessage = null;\n        _isBuffering = isZap ? false : true;\n""",
    'clear error title',
)

replace_once(
    """      if (!skipStop && !isZap) {\n        await _player.stop();\n        if (!mounted || session != _sessionId) return;\n      }\n""",
    """      final shouldStopBeforeOpen =\n          !skipStop && !isZap && (isRetry || !widget.isLiveContent);\n      if (shouldStopBeforeOpen) {\n        await _player.stop();\n        if (!mounted || session != _sessionId) return;\n      }\n""",
    'skip redundant first live stop',
)

replace_once(
    """      final openFuture = _player.open(media);\n      _acceptPlaybackEvents = true;\n      await openFuture.timeout(_connectTimeout);\n      if (!mounted || session != _sessionId) return;\n""",
    """      final attemptTimeout = _startupAttemptTimeout;\n      final openFuture = _player.open(media);\n      _acceptPlaybackEvents = true;\n      await openFuture.timeout(attemptTimeout);\n      if (!mounted ||\n          session != _sessionId ||\n          _terminalStartupSession == session) {\n        return;\n      }\n""",
    'bounded live open timeout',
)

replace_once(
    """      _opening = false;\n      _connectTimeoutTimer = Timer(_connectTimeout, () {\n""",
    """      _opening = false;\n      _connectTimeoutTimer = Timer(attemptTimeout, () {\n""",
    'bounded first-frame timeout',
)

replace_once(
    """    } on TimeoutException {\n      if (!mounted || session != _sessionId) return;\n      _opening = false;\n""",
    """    } on TimeoutException {\n      if (!mounted ||\n          session != _sessionId ||\n          _terminalStartupSession == session) {\n        return;\n      }\n      _opening = false;\n""",
    'timeout terminal guard',
)

replace_once(
    """    } catch (e) {\n      if (!mounted || session != _sessionId) return;\n      _opening = false;\n""",
    """    } catch (e) {\n      if (!mounted ||\n          session != _sessionId ||\n          _terminalStartupSession == session) {\n        return;\n      }\n      _opening = false;\n""",
    'exception terminal guard',
)

replace_once(
    """    final filteredChannels = query.trim().isEmpty\n        ? widget.playlist\n        : widget.playlist\n            .where((c) => c.name.toLowerCase().contains(query))\n            .toList();\n\n    return Scaffold(\n""",
    """    final filteredChannels = query.trim().isEmpty\n        ? widget.playlist\n        : widget.playlist\n            .where((c) => c.name.toLowerCase().contains(query))\n            .toList();\n    final isChannelMaintenance =\n        widget.isLiveContent && _errorTitle == 'CANAL EN MANTENIMIENTO';\n    final errorAccent =\n        isChannelMaintenance ? Colors.amberAccent : Colors.redAccent;\n\n    return Scaffold(\n""",
    'maintenance UI state',
)

replace_once(
    """                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),\n                    ),\n                    child: Column(\n                      mainAxisSize: MainAxisSize.min,\n                      children: [\n                        const Icon(\n                          Icons.error_outline_rounded,\n                          color: Colors.redAccent,\n                          size: 48,\n                        ),\n                        const SizedBox(height: 14),\n                        Text(\n                          _errorMessage!,\n""",
    """                      border: Border.all(\n                        color: errorAccent.withValues(alpha: 0.35),\n                      ),\n                    ),\n                    child: Column(\n                      mainAxisSize: MainAxisSize.min,\n                      children: [\n                        Icon(\n                          isChannelMaintenance\n                              ? Icons.settings_suggest_rounded\n                              : Icons.error_outline_rounded,\n                          color: errorAccent,\n                          size: 48,\n                        ),\n                        if (_errorTitle != null) ...[\n                          const SizedBox(height: 14),\n                          Text(\n                            _errorTitle!,\n                            style: const TextStyle(\n                              color: Colors.white,\n                              fontSize: 20,\n                              fontWeight: FontWeight.w900,\n                              letterSpacing: 0.8,\n                            ),\n                            textAlign: TextAlign.center,\n                          ),\n                        ],\n                        const SizedBox(height: 12),\n                        Text(\n                          _errorMessage!,\n""",
    'maintenance error card',
)

replace_once(
    """                            OutlinedButton.icon(\n                              onPressed: () =>\n                                  setState(() => _showChannelList = true),\n                              style: OutlinedButton.styleFrom(\n                                foregroundColor: Colors.white,\n                              ),\n                              icon: const Icon(Icons.view_list_rounded),\n                              label: const Text('Ver otros canales'),\n                            ),\n""",
    """                            OutlinedButton.icon(\n                              onPressed: () => Navigator.of(context).maybePop(),\n                              style: OutlinedButton.styleFrom(\n                                foregroundColor: Colors.white,\n                              ),\n                              icon: const Icon(Icons.arrow_back_rounded),\n                              label: Text(\n                                widget.isLiveContent\n                                    ? 'Volver a canales'\n                                    : 'Volver al catálogo',\n                              ),\n                            ),\n""",
    'back to channels button',
)

path.write_text(text)
print('v41 playback patch applied successfully')
