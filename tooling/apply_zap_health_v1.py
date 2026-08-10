from pathlib import Path

PLAYER = Path('lib/screens/player_screen.dart')
METRICS = Path('lib/services/playback_metrics_service.dart')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Pattern not found: {label}')
    return text.replace(old, new, 1)


player = PLAYER.read_text()
metrics = METRICS.read_text()

# ---------------------------------------------------------------------------
# Player: connection health model.
# ---------------------------------------------------------------------------
marker = "const String _legacyVlcUserAgent =\n    'VLC/3.0.20 LibVLC/3.0.20 (iptv_player; +https://github.com)';\n\n"
health_model = r'''const String _legacyVlcUserAgent =
    'VLC/3.0.20 LibVLC/3.0.20 (iptv_player; +https://github.com)';

enum _ConnectionHealthLevel { stable, unstable, poor }

enum _ConnectionIssueSource { none, internet, provider, unknown }

class _ConnectionHealthSnapshot {
  final _ConnectionHealthLevel level;
  final _ConnectionIssueSource source;
  final String title;
  final String detail;
  final String confidence;

  const _ConnectionHealthSnapshot({
    required this.level,
    required this.source,
    required this.title,
    required this.detail,
    required this.confidence,
  });

  static const stable = _ConnectionHealthSnapshot(
    level: _ConnectionHealthLevel.stable,
    source: _ConnectionIssueSource.none,
    title: 'Conexión estable',
    detail: 'La reproducción está recibiendo datos con normalidad.',
    confidence: 'alta',
  );
}

'''
player = replace_once(player, marker, health_model, 'connection health model')

# State fields.
player = replace_once(
    player,
    "  bool _runtimeStatsBusy = false;\n  bool _runtimeFormatLoaded = false;\n",
    "  bool _runtimeStatsBusy = false;\n  bool _runtimeFormatLoaded = false;\n  bool _acceptPlaybackEvents = true;\n  bool _providerIssueHint = false;\n",
    'player health flags',
)
player = replace_once(
    player,
    "  int? _lastStartupMs;\n  String? _startupUrl;\n",
    "  int? _lastStartupMs;\n  int? _lastZapMs;\n  int? _zapSession;\n  String? _startupUrl;\n  String? _lastConnectionDetail;\n  int _recentBufferingEvents = 0;\n  DateTime _bufferingWindowStartedAt = DateTime.now();\n",
    'zap and health state',
)
player = replace_once(
    player,
    "  Timer? _watchdogTimer;\n  Timer? _connectTimeoutTimer;\n  Timer? _retryTimer;\n  Timer? _transientLiveFailureTimer;\n",
    "  final ValueNotifier<_ConnectionHealthSnapshot> _connectionHealth =\n      ValueNotifier<_ConnectionHealthSnapshot>(_ConnectionHealthSnapshot.stable);\n\n  Timer? _watchdogTimer;\n  Timer? _connectTimeoutTimer;\n  Timer? _retryTimer;\n  Timer? _transientLiveFailureTimer;\n  Timer? _connectionProbeTimer;\n  Timer? _connectionRecoveryTimer;\n",
    'health notifier and timers',
)
player = replace_once(
    player,
    "  Stopwatch? _startupStopwatch;\n",
    "  Stopwatch? _startupStopwatch;\n  Stopwatch? _zapStopwatch;\n",
    'zap stopwatch',
)

# Ignore stale events while preparing a replacement stream, and diagnose buffering.
player = replace_once(
    player,
    "    _bufferingSub = _player.stream.buffering.listen((buffering) {\n      if (!mounted) return;\n\n      if (!buffering) {\n",
    "    _bufferingSub = _player.stream.buffering.listen((buffering) {\n      if (!mounted || !_acceptPlaybackEvents) return;\n\n      if (buffering && _hasEverPlayed && !_opening && !_reconnecting) {\n        _onBufferingStarted();\n      }\n\n      if (!buffering) {\n        _onBufferingRecovered();\n",
    'buffering health hooks',
)

# Record startup and zapping completion together.
old_startup = r'''      if (!buffering &&
          (_startupStopwatch?.isRunning ?? false) &&
          _startupSession == _sessionId) {
        _startupStopwatch!.stop();
        final elapsed = _startupStopwatch!.elapsedMilliseconds;
        final url = _startupUrl;
        if (mounted) setState(() => _lastStartupMs = elapsed);
        if (url != null) {
          unawaited(_metrics.recordStartup(url, elapsed));
          unawaited(_compatibility.recordSuccess(url, _compatibilityMode));
        }
      }
'''
new_startup = r'''      if (!buffering &&
          (_startupStopwatch?.isRunning ?? false) &&
          _startupSession == _sessionId) {
        _startupStopwatch!.stop();
        final elapsed = _startupStopwatch!.elapsedMilliseconds;
        final url = _startupUrl;

        int? zapElapsed;
        if ((_zapStopwatch?.isRunning ?? false) && _zapSession == _sessionId) {
          _zapStopwatch!.stop();
          zapElapsed = _zapStopwatch!.elapsedMilliseconds;
          _zapSession = null;
        }

        if (mounted) {
          setState(() {
            _lastStartupMs = elapsed;
            if (zapElapsed != null) _lastZapMs = zapElapsed;
          });
        }
        if (url != null) {
          unawaited(_metrics.recordStartup(url, elapsed));
          if (zapElapsed != null) {
            unawaited(_metrics.recordZap(url, zapElapsed));
          }
          unawaited(_compatibility.recordSuccess(url, _compatibilityMode));
        }
      }
'''
player = replace_once(player, old_startup, new_startup, 'record zap completion')

player = replace_once(
    player,
    "    _playingSub = _player.stream.playing.listen((playing) {\n      _isPlaying = playing;\n",
    "    _playingSub = _player.stream.playing.listen((playing) {\n      if (!_acceptPlaybackEvents) return;\n      _isPlaying = playing;\n",
    'ignore stale playing events',
)
player = replace_once(
    player,
    "    _positionSub = _player.stream.position.listen((position) {\n      if (position != _lastKnownPosition) {\n",
    "    _positionSub = _player.stream.position.listen((position) {\n      if (!_acceptPlaybackEvents) return;\n      if (position != _lastKnownPosition) {\n",
    'ignore stale position events',
)

# Health engine, inserted before HLS detection.
health_methods = r'''
  void _onBufferingStarted() {
    final now = DateTime.now();
    if (now.difference(_bufferingWindowStartedAt) > const Duration(seconds: 60)) {
      _bufferingWindowStartedAt = now;
      _recentBufferingEvents = 0;
    }
    _recentBufferingEvents++;
    _connectionRecoveryTimer?.cancel();

    if (_connectionHealth.value.level == _ConnectionHealthLevel.stable) {
      _connectionHealth.value = const _ConnectionHealthSnapshot(
        level: _ConnectionHealthLevel.unstable,
        source: _ConnectionIssueSource.unknown,
        title: 'Señal inestable',
        detail: 'TV FULL está esperando datos. Estamos verificando si el origen es la conexión o el servidor.',
        confidence: 'baja',
      );
    }

    _scheduleConnectionDiagnosis(
      severe: _recentBufferingEvents >= 3,
      delay: const Duration(seconds: 2),
    );
  }

  void _onBufferingRecovered() {
    _connectionProbeTimer?.cancel();
    _connectionRecoveryTimer?.cancel();
    _connectionRecoveryTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted || _isBuffering || _reconnecting || _errorMessage != null) {
        return;
      }
      _providerIssueHint = false;
      _lastConnectionDetail = null;
      _connectionHealth.value = _ConnectionHealthSnapshot.stable;
    });
  }

  void _scheduleConnectionDiagnosis({
    bool severe = false,
    Duration delay = const Duration(milliseconds: 700),
  }) {
    if (!mounted || !_hasEverPlayed) return;
    final session = _sessionId;
    _connectionProbeTimer?.cancel();
    _connectionProbeTimer = Timer(delay, () {
      if (!mounted || session != _sessionId) return;
      unawaited(_diagnoseConnectionHealth(severe: severe));
    });
  }

  Future<void> _diagnoseConnectionHealth({bool severe = false}) async {
    if (!mounted || !_hasEverPlayed || _opening || _reconnecting) return;

    await _refreshRuntimeStats();
    if (!mounted) return;

    final channel = widget.playlist[_currentIndex];
    final current = await _metrics.statsForUrl(channel.url);
    final all = await _metrics.allStats();
    if (!mounted) return;

    final mediaBits = (_videoBitrate ?? 0) + (_audioBitrate ?? 0);
    final networkBits = (_networkReadBytesPerSecond ?? 0) * 8;
    final ratio = mediaBits > 0 && networkBits > 0 ? networkBits / mediaBits : null;

    final currentHostLooksBad = current.startupCount >= 3 &&
        ((current.averageStartupMs ?? 0) >= 1800 ||
            current.failureRatio >= 0.20 ||
            current.stallRatio >= 0.15);
    final otherHostsLookHealthy = all.any((stats) {
      if (stats.host == current.host || stats.startupCount < 2) return false;
      final avg = stats.averageStartupMs;
      return (avg == null || avg < 1400) &&
          stats.failureRatio < 0.12 &&
          stats.stallRatio < 0.10;
    });

    _ConnectionIssueSource source;
    String title;
    String detail;
    String confidence;

    if (_providerIssueHint || (currentHostLooksBad && otherHostsLookHealthy)) {
      source = _ConnectionIssueSource.provider;
      title = 'Servidor del canal inestable';
      detail = _lastConnectionDetail ??
          'Este servidor acumula más demoras o cortes que otros servidores usados en TV FULL.';
      confidence = _providerIssueHint ? 'alta' : 'media';
    } else if (ratio != null && ratio < 0.95 && !currentHostLooksBad) {
      source = _ConnectionIssueSource.internet;
      title = 'Posible conexión lenta';
      detail = ratio < 0.65
          ? 'Los datos están llegando bastante más lento de lo que necesita este canal. Probá Wi‑Fi más cerca del router o cable Ethernet.'
          : 'La velocidad recibida está por debajo del bitrate necesario para sostener este canal de forma continua.';
      confidence = ratio < 0.65 ? 'alta' : 'media';
    } else {
      source = _ConnectionIssueSource.unknown;
      title = 'Recepción inestable';
      detail = _lastConnectionDetail ??
          'La señal está llegando de forma irregular. Puede ser la conexión del usuario o el servidor del canal.';
      confidence = 'baja';
    }

    final poorByThroughput = ratio != null && ratio < 0.65;
    final level = severe || _recentBufferingEvents >= 3 || poorByThroughput
        ? _ConnectionHealthLevel.poor
        : _ConnectionHealthLevel.unstable;

    _connectionHealth.value = _ConnectionHealthSnapshot(
      level: level,
      source: source,
      title: title,
      detail: detail,
      confidence: confidence,
    );
  }

  bool _looksLikeConnectionLog(String text) {
    return text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('connection reset') ||
        text.contains('broken pipe') ||
        text.contains('connection refused') ||
        text.contains('too many requests') ||
        text.contains('network') ||
        text.contains('http 5') ||
        RegExp(r'\b5\d\d\b').hasMatch(text);
  }

  bool _looksProviderSpecific(String text) {
    return text.contains('401') ||
        text.contains('403') ||
        text.contains('404') ||
        text.contains('429') ||
        text.contains('connection refused') ||
        (RegExp(r'\b5\d\d\b').hasMatch(text) && text.contains('http'));
  }

  Future<void> _showConnectionHealthInfo(
    _ConnectionHealthSnapshot snapshot,
  ) async {
    await _refreshRuntimeStats();
    if (!mounted) return;

    final sourceLabel = switch (snapshot.source) {
      _ConnectionIssueSource.internet => 'Conexión / Wi‑Fi',
      _ConnectionIssueSource.provider => 'Servidor del canal',
      _ConnectionIssueSource.unknown => 'No determinado',
      _ConnectionIssueSource.none => 'Sin problemas',
    };

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estado de reproducción'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(snapshot.title),
            const SizedBox(height: 8),
            Text(snapshot.detail),
            const SizedBox(height: 14),
            Text('Causa probable: $sourceLabel'),
            Text('Confianza del diagnóstico: ${snapshot.confidence}'),
            Text('Velocidad recibida: $_networkSpeedText'),
            Text('Bitrate de video: ${_formatBitrate(_videoBitrate)}'),
            Text('Bitrate de audio: ${_formatBitrate(_audioBitrate)}'),
            Text('Buffer disponible: ${_lastCacheSeconds == null ? 'No disponible' : '${_lastCacheSeconds!.toStringAsFixed(1)} s'}'),
            if (_lastZapMs != null) Text('Último cambio de canal: $_lastZapMs ms'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionHealthBadge() {
    return ValueListenableBuilder<_ConnectionHealthSnapshot>(
      valueListenable: _connectionHealth,
      builder: (context, snapshot, _) {
        if (snapshot.level == _ConnectionHealthLevel.stable) {
          return const SizedBox.shrink();
        }

        final isPoor = snapshot.level == _ConnectionHealthLevel.poor;
        final color = isPoor ? Colors.redAccent : Colors.amberAccent;
        final icon = snapshot.source == _ConnectionIssueSource.provider
            ? Icons.dns_rounded
            : snapshot.source == _ConnectionIssueSource.internet
                ? Icons.wifi_off_rounded
                : Icons.network_check_rounded;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => unawaited(_showConnectionHealthInfo(snapshot)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xDC101820),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text(
                    snapshot.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

'''
player = replace_once(
    player,
    "\n\n  bool _looksLikeHls(String url) {\n",
    health_methods + "\n  bool _looksLikeHls(String url) {\n",
    'connection health methods',
)

# Mark stalls as severe connection-health events.
player = replace_once(
    player,
    "    if (silentFor > effectiveStallThreshold) {\n      final url = widget.playlist[_currentIndex].url;\n",
    "    if (silentFor > effectiveStallThreshold) {\n      _scheduleConnectionDiagnosis(severe: true);\n      final url = widget.playlist[_currentIndex].url;\n",
    'stall health diagnosis',
)

# Fold player logs into health classifier.
player = replace_once(
    player,
    "    if (diagnostic != null && diagnostic != _engineDiagnostic) {\n      setState(() => _engineDiagnostic = diagnostic!);\n    }\n",
    "    if (diagnostic != null && _hasEverPlayed && _looksLikeConnectionLog(text)) {\n      _providerIssueHint = _looksProviderSpecific(text);\n      _lastConnectionDetail = diagnostic;\n      _scheduleConnectionDiagnosis(\n        severe: log.level == 'error' || log.level == 'fatal',\n      );\n    }\n\n    if (diagnostic != null && diagnostic != _engineDiagnostic) {\n      setState(() => _engineDiagnostic = diagnostic!);\n    }\n",
    'log health classifier',
)

# Zapping: direct replacement for live/radio and stale-event isolation.
player = replace_once(
    player,
    "  Future<void> _playCurrent({\n    bool isRetry = false,\n    bool forceNormalProbe = false,\n    bool skipStop = false,\n    Duration? resumePosition,\n",
    "  Future<void> _playCurrent({\n    bool isRetry = false,\n    bool forceNormalProbe = false,\n    bool skipStop = false,\n    bool isZap = false,\n    Duration? resumePosition,\n",
    'playCurrent isZap argument',
)
player = replace_once(
    player,
    "    final session = ++_sessionId;\n    _opening = true;\n",
    "    final session = ++_sessionId;\n    _opening = true;\n    _acceptPlaybackEvents = false;\n    _connectionProbeTimer?.cancel();\n    _connectionRecoveryTimer?.cancel();\n\n    if (isZap) {\n      _zapStopwatch = Stopwatch()..start();\n      _zapSession = session;\n    }\n",
    'start zap and suppress stale events',
)
player = replace_once(
    player,
    "      _retryCount = 0;\n      _normalProbeFallbackUsed = false;\n      _resetStreamInfo();\n",
    "      _retryCount = 0;\n      _normalProbeFallbackUsed = false;\n      _providerIssueHint = false;\n      _lastConnectionDetail = null;\n      _resetStreamInfo();\n",
    'reset health hints per channel',
)
old_stop = r'''    try {
      // En recuperación de EOF reemplazamos el Media directamente. Evitar un
      // stop explícito reduce el hueco visible entre una conexión y la siguiente.
      if (!skipStop) {
        await _player.stop();
        if (!mounted || session != _sessionId) return;
      }

      final channel = widget.playlist[_currentIndex];
'''
new_stop = r'''    try {
      // En zapping live reemplazamos el Media directamente. El canal anterior
      // puede seguir visible mientras preparamos headers/perfil; evitamos el
      // hueco artificial de stop() -> open(). En retries/VOD conservamos stop().
      if (!skipStop && !isZap) {
        await _player.stop();
        if (!mounted || session != _sessionId) return;
      }

      _acceptPlaybackEvents = true;
      final channel = widget.playlist[_currentIndex];
'''
player = replace_once(player, old_stop, new_stop, 'remove stop from live zapping')

# Ensure events are accepted during error recovery.
player = replace_once(
    player,
    "    } on TimeoutException {\n      if (!mounted || session != _sessionId) return;\n      _opening = false;\n",
    "    } on TimeoutException {\n      if (!mounted || session != _sessionId) return;\n      _opening = false;\n      _acceptPlaybackEvents = true;\n",
    'timeout event recovery',
)
player = replace_once(
    player,
    "    } catch (e) {\n      if (!mounted || session != _sessionId) return;\n      _opening = false;\n",
    "    } catch (e) {\n      if (!mounted || session != _sessionId) return;\n      _opening = false;\n      _acceptPlaybackEvents = true;\n",
    'catch event recovery',
)

# Route channel changes through one zapping path.
old_switches = r'''  void _switchToChannel(int index) {
    if (index == _currentIndex) {
      setState(() => _showChannelList = false);
      return;
    }
    setState(() {
      _currentIndex = index;
      _showChannelList = false;
    });
    unawaited(_playCurrent());
  }

  void _next() {
    if (_currentIndex < widget.playlist.length - 1) {
      setState(() => _currentIndex++);
      unawaited(_playCurrent());
    }
  }

  void _previous() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      unawaited(_playCurrent());
    }
  }
'''
new_switches = r'''  void _switchToChannel(int index) {
    if (index == _currentIndex) {
      setState(() => _showChannelList = false);
      return;
    }
    _zapTo(index);
  }

  void _zapTo(int index) {
    if (index < 0 || index >= widget.playlist.length || index == _currentIndex) {
      return;
    }
    setState(() {
      _currentIndex = index;
      _showChannelList = false;
    });
    // El reemplazo directo se reserva para TV/radio. En VOD mantenemos el
    // cierre explícito para no alterar seek/resume ni semántica de archivos.
    unawaited(_playCurrent(isZap: widget.isLiveContent));
  }

  void _next() {
    if (_currentIndex < widget.playlist.length - 1) {
      _zapTo(_currentIndex + 1);
    }
  }

  void _previous() {
    if (_currentIndex > 0) {
      _zapTo(_currentIndex - 1);
    }
  }
'''
player = replace_once(player, old_switches, new_switches, 'unified zap path')

# Performance dialog shows zap metrics.
player = replace_once(
    player,
    "    final average = stats.averageStartupMs;\n",
    "    final average = stats.averageStartupMs;\n    final averageZap = stats.averageZapMs;\n",
    'average zap metric',
)
player = replace_once(
    player,
    "            Text(\n              'Promedio servidor: ${average == null ? 'sin muestras' : '${average.round()} ms'}',\n            ),\n",
    "            Text(\n              'Promedio servidor: ${average == null ? 'sin muestras' : '${average.round()} ms'}',\n            ),\n            Text(\n              'Último zap: ${_lastZapMs == null ? 'sin medir' : '$_lastZapMs ms'}',\n            ),\n            Text(\n              'Promedio de zap: ${averageZap == null ? 'sin muestras' : '${averageZap.round()} ms'}',\n            ),\n",
    'performance zap rows',
)

# UI label and connection-health badge.
player = replace_once(
    player,
    "              performanceLabel:\n                  _lastStartupMs == null ? null : '$_lastStartupMs ms',\n",
    "              performanceLabel: _lastZapMs != null\n                  ? 'Zap $_lastZapMs ms'\n                  : (_lastStartupMs == null ? null : '$_lastStartupMs ms'),\n",
    'zap label in overlay',
)
player = replace_once(
    player,
    "          if ((_isBuffering || _reconnecting) && _errorMessage == null)\n",
    "          Positioned(\n            top: 18,\n            right: 18,\n            child: SafeArea(\n              child: _buildConnectionHealthBadge(),\n            ),\n          ),\n          if ((_isBuffering || _reconnecting) && _errorMessage == null)\n",
    'connection badge placement',
)

# Dispose health resources.
player = replace_once(
    player,
    "    _transientLiveFailureTimer?.cancel();\n    _bufferingSub?.cancel();\n",
    "    _transientLiveFailureTimer?.cancel();\n    _connectionProbeTimer?.cancel();\n    _connectionRecoveryTimer?.cancel();\n    _connectionHealth.dispose();\n    _bufferingSub?.cancel();\n",
    'dispose connection health',
)

# ---------------------------------------------------------------------------
# Metrics: persistent zap timing per host.
# ---------------------------------------------------------------------------
metrics = replace_once(
    metrics,
    "  int fastProbeFallbacks;\n  int lastUpdatedEpochMs;\n",
    "  int fastProbeFallbacks;\n  int zapCount;\n  int zapTotalMs;\n  int fastestZapMs;\n  int slowestZapMs;\n  int lastUpdatedEpochMs;\n",
    'zap metric fields',
)
metrics = replace_once(
    metrics,
    "    this.fastProbeFallbacks = 0,\n    this.lastUpdatedEpochMs = 0,\n",
    "    this.fastProbeFallbacks = 0,\n    this.zapCount = 0,\n    this.zapTotalMs = 0,\n    this.fastestZapMs = 0,\n    this.slowestZapMs = 0,\n    this.lastUpdatedEpochMs = 0,\n",
    'zap constructor fields',
)
metrics = replace_once(
    metrics,
    "  double? get averageStartupMs =>\n      startupCount == 0 ? null : startupTotalMs / startupCount;\n",
    "  double? get averageStartupMs =>\n      startupCount == 0 ? null : startupTotalMs / startupCount;\n\n  double? get averageZapMs => zapCount == 0 ? null : zapTotalMs / zapCount;\n",
    'average zap getter',
)
metrics = replace_once(
    metrics,
    "  int get sampleScore => startupCount + failures + stalls;\n",
    "  int get sampleScore => startupCount + failures + stalls + zapCount;\n",
    'zap sample score',
)
metrics = replace_once(
    metrics,
    "  void recordFastProbeFallback() {\n    fastProbeFallbacks++;\n    lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;\n  }\n",
    "  void recordFastProbeFallback() {\n    fastProbeFallbacks++;\n    lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;\n  }\n\n  void recordZap(int milliseconds) {\n    zapCount++;\n    zapTotalMs += milliseconds;\n    if (fastestZapMs == 0 || milliseconds < fastestZapMs) {\n      fastestZapMs = milliseconds;\n    }\n    if (milliseconds > slowestZapMs) slowestZapMs = milliseconds;\n    lastUpdatedEpochMs = DateTime.now().millisecondsSinceEpoch;\n  }\n",
    'record zap stats',
)
metrics = replace_once(
    metrics,
    "        'fastProbeFallbacks': fastProbeFallbacks,\n        'lastUpdatedEpochMs': lastUpdatedEpochMs,\n",
    "        'fastProbeFallbacks': fastProbeFallbacks,\n        'zapCount': zapCount,\n        'zapTotalMs': zapTotalMs,\n        'fastestZapMs': fastestZapMs,\n        'slowestZapMs': slowestZapMs,\n        'lastUpdatedEpochMs': lastUpdatedEpochMs,\n",
    'zap json fields',
)
metrics = replace_once(
    metrics,
    "      fastProbeFallbacks:\n          (json['fastProbeFallbacks'] as num?)?.toInt() ?? 0,\n      lastUpdatedEpochMs:\n",
    "      fastProbeFallbacks:\n          (json['fastProbeFallbacks'] as num?)?.toInt() ?? 0,\n      zapCount: (json['zapCount'] as num?)?.toInt() ?? 0,\n      zapTotalMs: (json['zapTotalMs'] as num?)?.toInt() ?? 0,\n      fastestZapMs: (json['fastestZapMs'] as num?)?.toInt() ?? 0,\n      slowestZapMs: (json['slowestZapMs'] as num?)?.toInt() ?? 0,\n      lastUpdatedEpochMs:\n",
    'zap json decoding',
)
metrics = replace_once(
    metrics,
    "  Future<void> recordFastProbeFallback(String url) async {\n    final stats = await statsForUrl(url);\n    stats.recordFastProbeFallback();\n    await _save();\n  }\n",
    "  Future<void> recordFastProbeFallback(String url) async {\n    final stats = await statsForUrl(url);\n    stats.recordFastProbeFallback();\n    await _save();\n  }\n\n  Future<void> recordZap(String url, int milliseconds) async {\n    final stats = await statsForUrl(url);\n    stats.recordZap(milliseconds);\n    await _save();\n  }\n",
    'recordZap service',
)

PLAYER.write_text(player)
METRICS.write_text(metrics)
