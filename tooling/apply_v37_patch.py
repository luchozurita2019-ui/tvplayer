from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    text = text.replace(old, new, 1)


replace_once(
    '''  List<ServerCompatibilityMode> _compatibilityPlan = const [
    ServerCompatibilityMode.direct,
    ServerCompatibilityMode.compatible,
    ServerCompatibilityMode.liveRecovery,
  ];
  int _compatibilityIndex = 0;
  int _compatibilityFallbacks = 0;
  ServerCompatibilityMode _compatibilityMode =
      ServerCompatibilityMode.direct;
  String? _compatibilityUrl;
  String _engineDiagnostic = 'Sin errores de red detectados';
''',
    '''  List<ServerCompatibilityMode> _compatibilityPlan = const [
    ServerCompatibilityMode.direct,
    ServerCompatibilityMode.compatible,
    ServerCompatibilityMode.liveRecovery,
    ServerCompatibilityMode.advanced,
  ];
  int _compatibilityIndex = 0;
  int _compatibilityFallbacks = 0;
  int _runtimeRecoveryPromotions = 0;
  bool _compatibilityPrefersNormalProbe = false;
  ServerCompatibilityMode _compatibilityMode =
      ServerCompatibilityMode.direct;
  String? _compatibilityUrl;
  String _engineDiagnostic = 'Sin errores de red detectados';
''',
    'compatibility fields',
)

replace_once(
    '''    _useFastProbe = tuning.useFastProbe;
    _currentOpenUsesFastProbe = _useFastProbe &&
        !forceNormalProbe &&
        _compatibilityMode != ServerCompatibilityMode.compatible;
''',
    '''    _useFastProbe = tuning.useFastProbe;
    final modeNeedsNormalProbe =
        _compatibilityMode == ServerCompatibilityMode.compatible ||
            _compatibilityMode == ServerCompatibilityMode.advanced;
    _currentOpenUsesFastProbe = _useFastProbe &&
        !forceNormalProbe &&
        !_compatibilityPrefersNormalProbe &&
        !modeNeedsNormalProbe;
''',
    'probe selection',
)

replace_once(
    '''        await platform.setProperty(
          'demuxer-lavf-allow-mimetype',
          _compatibilityMode == ServerCompatibilityMode.compatible
              ? 'no'
              : 'yes',
        );

        if (_compatibilityMode == ServerCompatibilityMode.liveRecovery) {
          await platform.setProperty(
            'stream-lavf-o',
            'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'
                'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'
                'reconnect_delay_max=1',
          );
        }
''',
    '''        final disableMime =
            _compatibilityMode == ServerCompatibilityMode.compatible ||
                _compatibilityMode == ServerCompatibilityMode.advanced;
        await platform.setProperty(
          'demuxer-lavf-allow-mimetype',
          disableMime ? 'no' : 'yes',
        );

        final recoveryMode =
            _compatibilityMode == ServerCompatibilityMode.liveRecovery ||
                _compatibilityMode == ServerCompatibilityMode.advanced;
        if (recoveryMode) {
          final reconnectOptions =
              _compatibilityMode == ServerCompatibilityMode.advanced
                  ? 'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'
                      'reconnect_on_network_error=1,'
                      'reconnect_on_http_error=408,429,5xx,'
                      'reconnect_delay_max=2'
                  : 'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'
                      'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'
                      'reconnect_delay_max=1';
          await platform.setProperty('stream-lavf-o', reconnectOptions);
        }
''',
    'compatibility native options',
)

replace_once(
    '''      _seamlessEofRecoveries++;
      _retryTimer?.cancel();
      await _compatibility.recordLiveEof(channel.url);
      if (!mounted) return;

      final liveIndex =
          _compatibilityPlan.indexOf(ServerCompatibilityMode.liveRecovery);
      if (liveIndex >= 0) _compatibilityIndex = liveIndex;
      _compatibilityMode = ServerCompatibilityMode.liveRecovery;
      setState(() {
        _engineDiagnostic =
            'EOF de señal en vivo: activado Live Recovery para este servidor';
      });
''',
    '''      _seamlessEofRecoveries++;
      _retryTimer?.cancel();

      // Si el servidor necesitó MIME relajado para abrir, conservamos ese
      // comportamiento durante la recuperación. Advanced = Compatible +
      // reconexión, evitando que un EOF haga volver a un modo incompatible.
      final recoveryMode =
          _compatibilityMode == ServerCompatibilityMode.compatible ||
                  _compatibilityMode == ServerCompatibilityMode.advanced
              ? ServerCompatibilityMode.advanced
              : ServerCompatibilityMode.liveRecovery;
      await _compatibility.recordLiveEof(channel.url, recoveryMode);
      if (!mounted) return;

      final recoveryIndex = _compatibilityPlan.indexOf(recoveryMode);
      if (recoveryIndex >= 0) _compatibilityIndex = recoveryIndex;
      _compatibilityMode = recoveryMode;
      setState(() {
        _engineDiagnostic =
            'EOF de señal en vivo: activado ${recoveryMode.label} para este servidor';
      });
''',
    'EOF recovery mode',
)

marker = '''  void _handlePlayerLog(PlayerLog log) {
'''
insert = '''  bool _promoteRuntimeRecoveryMode(String reason) {
    if (!_hasEverPlayed) return false;

    final previous = _compatibilityMode;
    final ServerCompatibilityMode? target = switch (previous) {
      ServerCompatibilityMode.direct => ServerCompatibilityMode.liveRecovery,
      ServerCompatibilityMode.compatible => ServerCompatibilityMode.advanced,
      ServerCompatibilityMode.liveRecovery => ServerCompatibilityMode.advanced,
      ServerCompatibilityMode.advanced => null,
    };
    if (target == null) return false;

    final targetIndex = _compatibilityPlan.indexOf(target);
    if (targetIndex < 0) return false;

    final url = widget.playlist[_currentIndex].url;
    unawaited(_compatibility.recordFailure(url, previous));
    unawaited(_compatibility.recordRuntimeRecovery(url));

    _compatibilityIndex = targetIndex;
    _compatibilityFallbacks++;
    _runtimeRecoveryPromotions++;
    _compatibilityMode = target;
    _normalProbeFallbackUsed = true;
    _retryCount = 0;

    setState(() {
      _reconnecting = true;
      _errorMessage = null;
      _engineDiagnostic =
          '$reason · señal inestable en ${previous.label}; probando ${target.label}';
    });

    scheduleMicrotask(() {
      if (!mounted) return;
      unawaited(_playCurrent(isRetry: true, forceNormalProbe: true));
    });
    return true;
  }

'''
if text.count(marker) != 1:
    raise SystemExit(f'runtime promotion marker: expected 1, found {text.count(marker)}')
text = text.replace(marker, insert + marker, 1)

replace_once(
    '''    if (text.contains('403') || text.contains('forbidden')) {
      diagnostic = 'HTTP 403: el servidor rechazó la solicitud o sus headers';
    } else if (text.contains('401') || text.contains('unauthorized')) {
      diagnostic = 'HTTP 401: el servidor exige autorización válida';
    } else if (text.contains('404') || text.contains('not found')) {
      diagnostic = 'HTTP 404: la URL o un segmento del stream no existe';
    } else if (text.contains('timed out') || text.contains('timeout')) {
      diagnostic = 'Timeout de red: el servidor tardó demasiado en responder';
    } else if (text.contains('connection refused')) {
      diagnostic = 'Conexión rechazada por el servidor';
''',
    '''    if (text.contains('429') || text.contains('too many requests')) {
      diagnostic = 'HTTP 429: el servidor limitó temporalmente las solicitudes';
    } else if (text.contains('408') || text.contains('request timeout')) {
      diagnostic = 'HTTP 408: el servidor agotó el tiempo de la solicitud';
    } else if (text.contains('403') || text.contains('forbidden')) {
      diagnostic = 'HTTP 403: el servidor rechazó la solicitud o sus headers';
    } else if (text.contains('401') || text.contains('unauthorized')) {
      diagnostic = 'HTTP 401: el servidor exige autorización válida';
    } else if (text.contains('404') || text.contains('not found')) {
      diagnostic = 'HTTP 404: la URL o un segmento del stream no existe';
    } else if (text.contains('timed out') || text.contains('timeout')) {
      diagnostic = 'Timeout de red: el servidor tardó demasiado en responder';
    } else if (text.contains('connection reset') ||
        text.contains('broken pipe')) {
      diagnostic = 'La conexión fue cerrada durante la reproducción';
    } else if (text.contains('connection refused')) {
      diagnostic = 'Conexión rechazada por el servidor';
''',
    'log diagnostics part 1',
)

replace_once(
    '''    } else if (text.contains('mime')) {
      diagnostic = 'El MIME del servidor puede ser incompatible; disponible fallback Compatible';
    } else if (text.contains('eof')) {
      diagnostic = 'EOF detectado en la señal en vivo';
    } else if ((log.level == 'error' || log.level == 'fatal' || log.level == 'warn') &&
''',
    '''    } else if (text.contains('too many redirects') ||
        text.contains('redirect loop')) {
      diagnostic = 'El servidor entró en un bucle de redirecciones HTTP';
    } else if (RegExp(r'\\b5\\d\\d\\b').hasMatch(text) &&
        text.contains('http')) {
      diagnostic = 'El servidor respondió con un error HTTP 5xx temporal';
    } else if (text.contains('mime')) {
      diagnostic =
          'El MIME del servidor puede ser incompatible; disponible fallback Compatible';
    } else if (text.contains('eof')) {
      diagnostic = 'EOF detectado en la señal en vivo';
    } else if ((log.level == 'error' || log.level == 'fatal' || log.level == 'warn') &&
''',
    'log diagnostics part 2',
)

replace_once(
    '''    final failedSession = _sessionId;
    final url = widget.playlist[_currentIndex].url;

    if (!_hasEverPlayed && _advanceCompatibilityMode(message)) {
      return;
    }
''',
    '''    final failedSession = _sessionId;
    final url = widget.playlist[_currentIndex].url;

    // Si el canal ya llegó a reproducir y luego se corta, no repetimos el
    // mismo modo a ciegas: promovemos sólo ese servidor a una estrategia con
    // reconexión. Esto no afecta a proveedores que funcionan bien en Directo.
    if (_hasEverPlayed && _promoteRuntimeRecoveryMode(message)) {
      return;
    }

    if (!_hasEverPlayed && _advanceCompatibilityMode(message)) {
      return;
    }
''',
    'runtime failure promotion',
)

replace_once(
    '''    _normalProbeFallbackUsed = true;
    final url = widget.playlist[_currentIndex].url;
    unawaited(_metrics.recordFastProbeFallback(url));

    setState(() {
''',
    '''    _normalProbeFallbackUsed = true;
    final url = widget.playlist[_currentIndex].url;
    _compatibilityPrefersNormalProbe = true;
    unawaited(_metrics.recordFastProbeFallback(url));
    unawaited(_compatibility.recordNormalProbeFallback(url));

    setState(() {
''',
    'learn normal probe',
)

replace_once(
    '''      final channelUrl = widget.playlist[_currentIndex].url;
      final preferred = await _compatibility.preferredModeForUrl(channelUrl);
      if (!mounted || session != _sessionId) return;
      _compatibilityPlan = _compatibility.planFor(preferred);
      _compatibilityIndex = 0;
      _compatibilityFallbacks = 0;
      _compatibilityMode = _compatibilityPlan.first;
      _compatibilityUrl = channelUrl;
      _engineDiagnostic =
          'Apertura ${_compatibilityMode.label} para este servidor';
''',
    '''      final channelUrl = widget.playlist[_currentIndex].url;
      final profile = await _compatibility.profileForUrl(channelUrl);
      if (!mounted || session != _sessionId) return;
      _compatibilityPlan = _compatibility.planFor(profile.preferredMode);
      _compatibilityIndex = 0;
      _compatibilityFallbacks = 0;
      _runtimeRecoveryPromotions = 0;
      _compatibilityPrefersNormalProbe = profile.preferNormalProbe;
      _compatibilityMode = _compatibilityPlan.first;
      _compatibilityUrl = channelUrl;
      _engineDiagnostic =
          'Apertura ${_compatibilityMode.label} para este servidor'
          '${_compatibilityPrefersNormalProbe ? ' · probe normal aprendido' : ''}';
''',
    'load learned profile',
)

replace_once(
    '''    _eofReached = false;
    _seamlessEofRecoveries = 0;
  }
''',
    '''    _eofReached = false;
    _seamlessEofRecoveries = 0;
    _runtimeRecoveryPromotions = 0;
  }
''',
    'reset runtime recoveries',
)

replace_once(
    '''              Text('Modo de compatibilidad: ${_compatibilityMode.label}'),
              Text('Fallbacks de compatibilidad: $_compatibilityFallbacks'),
              Text(
                'Headers enviados: ${channel.resolvedHttpHeaders(_defaultUserAgent).keys.join(', ')}',
              ),
''',
    '''              Text('Modo de compatibilidad: ${_compatibilityMode.label}'),
              Text('Fallbacks de compatibilidad: $_compatibilityFallbacks'),
              Text(
                'Probe aprendido: ${_compatibilityPrefersNormalProbe ? 'normal' : 'adaptativo'}',
              ),
              Text('Promociones de recuperación: $_runtimeRecoveryPromotions'),
              Text(
                'Headers enviados: ${channel.resolvedHttpHeaders(_defaultUserAgent).keys.join(', ')}',
              ),
''',
    'stream diagnostics',
)

replace_once(
    '''            Text('Modo servidor: ${_compatibilityMode.label}'),
            Text('Fallbacks compatibilidad: $_compatibilityFallbacks'),
            Text('Pausa de caché mpv: ${_pausedForCache ? 'sí' : 'no'}'),
''',
    '''            Text('Modo servidor: ${_compatibilityMode.label}'),
            Text('Fallbacks compatibilidad: $_compatibilityFallbacks'),
            Text(
              'Probe aprendido: ${_compatibilityPrefersNormalProbe ? 'normal' : 'adaptativo'}',
            ),
            Text('Promociones de recuperación: $_runtimeRecoveryPromotions'),
            Text('Pausa de caché mpv: ${_pausedForCache ? 'sí' : 'no'}'),
''',
    'performance diagnostics',
)

path.write_text(text, encoding='utf-8')
print('V3.7 player patch applied successfully')
