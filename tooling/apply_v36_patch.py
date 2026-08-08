from pathlib import Path

path = Path('lib/screens/player_screen.dart')
s = path.read_text()

def replace_once(old: str, new: str, label: str):
    global s
    if old not in s:
        raise SystemExit(f'No se encontró bloque para {label}')
    s = s.replace(old, new, 1)

replace_once(
    "import '../services/playback_metrics_service.dart';\n",
    "import '../services/playback_metrics_service.dart';\nimport '../services/server_compatibility_service.dart';\n",
    'import compatibility',
)

replace_once(
    "  final PlaybackMetricsService _metrics = PlaybackMetricsService.instance;\n",
    "  final PlaybackMetricsService _metrics = PlaybackMetricsService.instance;\n"
    "  final ServerCompatibilityService _compatibility =\n"
    "      ServerCompatibilityService.instance;\n",
    'compatibility service field',
)

replace_once(
    "  bool _coreIdle = false;\n  bool _pausedForCache = false;\n  bool _eofReached = false;\n  int _seamlessEofRecoveries = 0;\n",
    "  bool _coreIdle = false;\n"
    "  bool _pausedForCache = false;\n"
    "  bool _eofReached = false;\n"
    "  int _seamlessEofRecoveries = 0;\n"
    "\n"
    "  List<ServerCompatibilityMode> _compatibilityPlan = const [\n"
    "    ServerCompatibilityMode.direct,\n"
    "    ServerCompatibilityMode.compatible,\n"
    "    ServerCompatibilityMode.liveRecovery,\n"
    "  ];\n"
    "  int _compatibilityIndex = 0;\n"
    "  int _compatibilityFallbacks = 0;\n"
    "  ServerCompatibilityMode _compatibilityMode =\n"
    "      ServerCompatibilityMode.direct;\n"
    "  String? _compatibilityUrl;\n"
    "  String _engineDiagnostic = 'Sin errores de red detectados';\n",
    'compatibility state',
)

replace_once(
    "  StreamSubscription? _audioBitrateSub;\n",
    "  StreamSubscription? _audioBitrateSub;\n  StreamSubscription? _logSub;\n",
    'log subscription field',
)

old_completed = """    _completedSub = _player.stream.completed.listen((completed) {
      if (!completed ||
          !mounted ||
          _opening ||
          _reconnecting ||
          _errorMessage != null) {
        return;
      }

      final channel = widget.playlist[_currentIndex];
      final uri = Uri.tryParse(channel.url);
      final isHttpLive = uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https');

      // Algunos proveedores cierran deliberadamente el socket/segmento cada
      // pocos segundos (en las pruebas reales, cerca de 30 s). Para un canal
      // HTTP en vivo, un EOF no significa que el programa terminó. FFmpeg
      // intenta reconectar primero; si aun así mpv publica completed, hacemos
      // un reemplazo inmediato del Media sin esperar el backoff normal.
      if (_hasEverPlayed && isHttpLive) {
        _seamlessEofRecoveries++;
        _retryTimer?.cancel();
        scheduleMicrotask(() {
          if (!mounted || _opening || _reconnecting) return;
          unawaited(
            _playCurrent(
              isRetry: true,
              forceNormalProbe: true,
              skipStop: true,
            ),
          );
        });
        return;
      }

      _handleFailure('El stream terminó inesperadamente', silent: true);
    });
"""
new_completed = """    _completedSub = _player.stream.completed.listen((completed) {
      if (!completed ||
          !mounted ||
          _opening ||
          _reconnecting ||
          _errorMessage != null) {
        return;
      }
      unawaited(_handleCompletedStream());
    });
"""
replace_once(old_completed, new_completed, 'completed listener')

replace_once(
    """    _audioBitrateSub = _player.stream.audioBitrate.listen((bitrate) {
      if (!mounted || bitrate == null || bitrate <= 0) return;
      setState(() => _audioBitrate = bitrate);
    });

    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) => _checkStall());
""",
    """    _audioBitrateSub = _player.stream.audioBitrate.listen((bitrate) {
      if (!mounted || bitrate == null || bitrate <= 0) return;
      setState(() => _audioBitrate = bitrate);
    });

    _logSub = _player.stream.log.listen(_handlePlayerLog);

    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) => _checkStall());
""",
    'log listener',
)

# V3.6 no propaga opciones del demuxer a todos los substreams. Cada servidor
# empieza limpio y sólo Live Recovery recibe AVOptions HTTP en stream-lavf-o.
old_http = """

        final uri = Uri.tryParse(channel.url);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          // FFmpeg documenta reconnect_at_eof específicamente para streams
          // live/endless. Lo usamos sin rw_timeout ni cambios agresivos de
          // cache: el objetivo es que un cierre del socket no llegue a mpv
          // como una pausa visible cada ~30 segundos.
          await platform.setProperty('demuxer-lavf-propagate-opts', 'yes');
          await platform.setProperty(
            'demuxer-lavf-o',
            'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'
                'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'
                'reconnect_delay_max=1',
          );
        } else {
          await platform.setProperty('demuxer-lavf-o', '');
        }
"""
new_http = """

        // Compatibilidad por servidor. Limpiamos SIEMPRE las opciones de la
        // apertura anterior para que un proveedor no herede ajustes de otro.
        await platform.setProperty('demuxer-lavf-propagate-opts', 'no');
        await platform.setProperty('demuxer-lavf-o', '');
        await platform.setProperty('stream-lavf-o', '');
        await platform.setProperty(
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
"""
replace_once(old_http, new_http, 'lavf compatibility block')

replace_once(
    """    _useFastProbe = tuning.useFastProbe;
    _currentOpenUsesFastProbe = _useFastProbe && !forceNormalProbe;
""",
    """    _useFastProbe = tuning.useFastProbe;
    _currentOpenUsesFastProbe = _useFastProbe &&
        !forceNormalProbe &&
        _compatibilityMode != ServerCompatibilityMode.compatible;
""",
    'compatible probe mode',
)

# Antes de contar un fallo general, intentamos el siguiente modo de
# compatibilidad si el canal todavía nunca llegó a reproducir.
replace_once(
    """    final failedSession = _sessionId;
    final url = widget.playlist[_currentIndex].url;
    unawaited(_metrics.recordFailure(url));

    if (_retryCount < _maxAutoRetries) {
""",
    """    final failedSession = _sessionId;
    final url = widget.playlist[_currentIndex].url;

    if (!_hasEverPlayed && _advanceCompatibilityMode(message)) {
      return;
    }

    unawaited(_metrics.recordFailure(url));

    if (_retryCount < _maxAutoRetries) {
""",
    'failure compatibility fallback',
)

# Inicialización del plan por host en cada canal nuevo.
replace_once(
    """    if (!isRetry) {
      _retryCount = 0;
      _normalProbeFallbackUsed = false;
      _resetStreamInfo();
    }

    _hasEverPlayed = false;
""",
    """    if (!isRetry) {
      _retryCount = 0;
      _normalProbeFallbackUsed = false;
      _resetStreamInfo();

      final channelUrl = widget.playlist[_currentIndex].url;
      final preferred = await _compatibility.preferredModeForUrl(channelUrl);
      if (!mounted || session != _sessionId) return;
      _compatibilityPlan = _compatibility.planFor(preferred);
      _compatibilityIndex = 0;
      _compatibilityFallbacks = 0;
      _compatibilityMode = _compatibilityPlan.first;
      _compatibilityUrl = channelUrl;
      _engineDiagnostic =
          'Apertura ${_compatibilityMode.label} para este servidor';
    }

    _hasEverPlayed = false;
""",
    'initialize compatibility plan',
)

# Todos los headers declarados por la lista se envían al Media.
replace_once(
    """      final channel = widget.playlist[_currentIndex];
      final headers = <String, String>{
        'User-Agent': channel.httpUserAgent ?? _defaultUserAgent,
        if (channel.httpReferrer != null) 'Referer': channel.httpReferrer!,
      };

      await _player
""",
    """      final channel = widget.playlist[_currentIndex];
      final headers = channel.resolvedHttpHeaders(_defaultUserAgent);

      await _player
""",
    'resolved HTTP headers',
)

# Persistimos el modo que realmente consiguió iniciar video.
replace_once(
    """        if (url != null) {
          unawaited(_metrics.recordStartup(url, elapsed));
        }
""",
    """        if (url != null) {
          unawaited(_metrics.recordStartup(url, elapsed));
          unawaited(_compatibility.recordSuccess(url, _compatibilityMode));
        }
""",
    'record compatibility success',
)

# Diagnóstico visible en Información real del stream.
replace_once(
    """              Text('Velocidad de lectura de red: $_networkSpeedText'),
              Text('Margen de red: $_networkHeadroomText'),
              Text('Núcleo esperando datos: ${_coreIdle ? 'sí' : 'no'}'),
              Text('Pausado por caché (mpv): ${_pausedForCache ? 'sí' : 'no'}'),
              Text('EOF detectado por mpv: ${_eofReached ? 'sí' : 'no'}'),
              Text('Recuperaciones transparentes de EOF: $_seamlessEofRecoveries'),
              const Text(
                'Motor de red: reconexión HTTP/EOF transparente para señal en vivo',
              ),
""",
    """              Text('Velocidad de lectura de red: $_networkSpeedText'),
              Text('Margen de red: $_networkHeadroomText'),
              Text('Núcleo esperando datos: ${_coreIdle ? 'sí' : 'no'}'),
              Text('Pausado por caché (mpv): ${_pausedForCache ? 'sí' : 'no'}'),
              Text('EOF detectado por mpv: ${_eofReached ? 'sí' : 'no'}'),
              Text('Modo de compatibilidad: ${_compatibilityMode.label}'),
              Text('Fallbacks de compatibilidad: $_compatibilityFallbacks'),
              Text(
                'Headers enviados: ${channel.resolvedHttpHeaders(_defaultUserAgent).keys.join(', ')}',
              ),
              Text('Diagnóstico de red: $_engineDiagnostic'),
              Text('Recuperaciones transparentes de EOF: $_seamlessEofRecoveries'),
""",
    'stream diagnostics compatibility',
)

replace_once(
    """            Text('Resolución actual: $_resolutionText'),
            Text('Pausa de caché mpv: ${_pausedForCache ? 'sí' : 'no'}'),
            Text('EOF detectado: ${_eofReached ? 'sí' : 'no'}'),
            Text('Recuperaciones EOF: $_seamlessEofRecoveries'),
""",
    """            Text('Resolución actual: $_resolutionText'),
            Text('Modo servidor: ${_compatibilityMode.label}'),
            Text('Fallbacks compatibilidad: $_compatibilityFallbacks'),
            Text('Pausa de caché mpv: ${_pausedForCache ? 'sí' : 'no'}'),
            Text('EOF detectado: ${_eofReached ? 'sí' : 'no'}'),
            Text('Recuperaciones EOF: $_seamlessEofRecoveries'),
            Text('Diagnóstico: $_engineDiagnostic'),
""",
    'performance diagnostics compatibility',
)

replace_once(
    """    _audioBitrateSub?.cancel();
    unawaited(_player.dispose());
""",
    """    _audioBitrateSub?.cancel();
    _logSub?.cancel();
    unawaited(_player.dispose());
""",
    'dispose log subscription',
)

# Métodos auxiliares antes de _handleFailure.
marker = "  void _handleFailure(String message, {bool silent = false}) {\n"
if marker not in s:
    raise SystemExit('No se encontró marcador para helpers V3.6')
helpers = r'''  Future<void> _handleCompletedStream() async {
    final channel = widget.playlist[_currentIndex];
    final uri = Uri.tryParse(channel.url);
    final isHttpLive =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    if (_hasEverPlayed && isHttpLive) {
      _seamlessEofRecoveries++;
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

      scheduleMicrotask(() {
        if (!mounted || _opening || _reconnecting) return;
        unawaited(
          _playCurrent(
            isRetry: true,
            forceNormalProbe: true,
            skipStop: true,
          ),
        );
      });
      return;
    }

    _handleFailure('El stream terminó inesperadamente', silent: true);
  }

  bool _advanceCompatibilityMode(String reason) {
    if (_hasEverPlayed ||
        _compatibilityIndex >= _compatibilityPlan.length - 1) {
      return false;
    }

    final url = widget.playlist[_currentIndex].url;
    final previous = _compatibilityMode;
    unawaited(_compatibility.recordFailure(url, previous));

    _compatibilityIndex++;
    _compatibilityFallbacks++;
    _compatibilityMode = _compatibilityPlan[_compatibilityIndex];
    _normalProbeFallbackUsed = true;
    _retryCount = 0;

    setState(() {
      _reconnecting = true;
      _errorMessage = null;
      _engineDiagnostic =
          '$reason · ${previous.label} no abrió; probando ${_compatibilityMode.label}';
    });

    scheduleMicrotask(() {
      if (!mounted) return;
      unawaited(_playCurrent(isRetry: true, forceNormalProbe: true));
    });
    return true;
  }

  void _handlePlayerLog(PlayerLog log) {
    if (!mounted) return;
    final text = log.text.toLowerCase();
    String? diagnostic;

    if (text.contains('403') || text.contains('forbidden')) {
      diagnostic = 'HTTP 403: el servidor rechazó la solicitud o sus headers';
    } else if (text.contains('401') || text.contains('unauthorized')) {
      diagnostic = 'HTTP 401: el servidor exige autorización válida';
    } else if (text.contains('404') || text.contains('not found')) {
      diagnostic = 'HTTP 404: la URL o un segmento del stream no existe';
    } else if (text.contains('timed out') || text.contains('timeout')) {
      diagnostic = 'Timeout de red: el servidor tardó demasiado en responder';
    } else if (text.contains('connection refused')) {
      diagnostic = 'Conexión rechazada por el servidor';
    } else if (text.contains('certificate') ||
        text.contains('tls') ||
        text.contains('ssl')) {
      diagnostic = 'Problema TLS/SSL durante la conexión segura';
    } else if (text.contains('invalid data') ||
        text.contains('could not find codec parameters')) {
      diagnostic = 'El servidor respondió, pero el formato no pudo detectarse';
    } else if (text.contains('mime')) {
      diagnostic = 'El MIME del servidor puede ser incompatible; disponible fallback Compatible';
    } else if (text.contains('eof')) {
      diagnostic = 'EOF detectado en la señal en vivo';
    } else if ((log.level == 'error' || log.level == 'fatal' || log.level == 'warn') &&
        (text.contains('http') || text.contains('network') || text.contains('failed'))) {
      diagnostic = 'mpv/FFmpeg reportó un fallo de red durante la apertura';
    }

    if (diagnostic != null && diagnostic != _engineDiagnostic) {
      setState(() => _engineDiagnostic = diagnostic!);
    }
  }

'''
s = s.replace(marker, helpers + marker, 1)

path.write_text(s)
