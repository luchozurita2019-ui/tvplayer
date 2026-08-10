from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f'Pattern not found: {label}')
    text = text.replace(old, new, 1)


replace_once(
    "  static const Duration _watchdogInterval = Duration(seconds: 2);\n  static const Duration _runtimeStatsInterval = Duration(seconds: 1);\n",
    "  static const Duration _watchdogInterval = Duration(seconds: 2);\n",
    'runtime stats interval constant',
)

replace_once(
    "  bool _normalProbeFallbackUsed = false;\n  bool _runtimeStatsBusy = false;\n",
    "  bool _normalProbeFallbackUsed = false;\n  bool _runtimeStatsBusy = false;\n  bool _runtimeFormatLoaded = false;\n",
    'runtime format state',
)

replace_once(
    "  Timer? _watchdogTimer;\n  Timer? _runtimeStatsTimer;\n  Timer? _connectTimeoutTimer;\n",
    "  Timer? _watchdogTimer;\n  Timer? _connectTimeoutTimer;\n",
    'runtime stats timer field',
)

replace_once(
    "        _hasEverPlayed = true;\n        _retryCount = 0;\n        _lastProgressAt = DateTime.now();\n",
    "        _hasEverPlayed = true;\n        _retryCount = 0;\n        _lastProgressAt = DateTime.now();\n        // Leemos el formato real una sola vez por canal. Esto conserva la\n        // detección de HLS para URLs sin .m3u8 sin mantener un polling técnico.\n        unawaited(_refreshContainerFormat());\n",
    'one-shot format refresh',
)

replace_once(
    "    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) => _checkStall());\n    _runtimeStatsTimer = Timer.periodic(\n      _runtimeStatsInterval,\n      (_) => unawaited(_refreshRuntimeStats()),\n    );\n\n    unawaited(_initializeAndPlay());\n",
    "    // El watchdog conserva su frecuencia porque sólo observa estado de\n    // reproducción. Las estadísticas técnicas ya no se consultan en segundo\n    // plano: se leen únicamente cuando el usuario abre los paneles de info.\n    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) => _checkStall());\n\n    unawaited(_initializeAndPlay());\n",
    'remove periodic runtime stats polling',
)

marker = "  Future<void> _refreshRuntimeStats() async {\n"
if marker not in text:
    raise SystemExit('Pattern not found: refreshRuntimeStats marker')
helper = '''  Future<void> _refreshContainerFormat() async {
    if (_runtimeFormatLoaded ||
        !mounted ||
        !_hasEverPlayed ||
        _opening ||
        _reconnecting) {
      return;
    }

    final platform = _player.platform;
    if (platform is! NativePlayer) return;

    final format = await _readStringProperty(platform, 'file-format');
    if (!mounted || format == null || format.isEmpty || format == 'N/A') return;

    // No hacemos setState: este dato alimenta compatibilidad/diagnóstico y será
    // leído por la UI sólo cuando corresponda.
    _containerFormat = format;
    _runtimeFormatLoaded = true;
  }

'''
text = text.replace(marker, helper + marker, 1)

old_stats = '''      if (!mounted) return;
      setState(() {
        if (fps != null && fps > 0) _videoFps = fps;
        if (videoBitrate != null && videoBitrate > 0) {
          _videoBitrate = videoBitrate;
        }
        if (audioBitrate != null && audioBitrate > 0) {
          _audioBitrate = audioBitrate;
        }
        if (cacheSeconds != null && cacheSeconds >= 0) {
          _lastCacheSeconds = cacheSeconds;
        }
        if (cacheSpeed != null && cacheSpeed >= 0) {
          _networkReadBytesPerSecond = cacheSpeed;
        }
        if (coreIdle != null) {
          _coreIdle = coreIdle == 'yes' || coreIdle == 'true';
        }
        if (pausedForCache != null) {
          _pausedForCache =
              pausedForCache == 'yes' || pausedForCache == 'true';
        }
        if (eofReached != null) {
          _eofReached = eofReached == 'yes' || eofReached == 'true';
        }
        if (format != null && format.isNotEmpty && format != 'N/A') {
          _containerFormat = format;
        }
      });
'''
new_stats = '''      if (!mounted) return;

      // Snapshot técnico bajo demanda. No usamos setState porque estos valores
      // no forman parte del camino crítico del video; los diálogos que los
      // muestran se construyen después de que esta lectura termina.
      if (fps != null && fps > 0) _videoFps = fps;
      if (videoBitrate != null && videoBitrate > 0) {
        _videoBitrate = videoBitrate;
      }
      if (audioBitrate != null && audioBitrate > 0) {
        _audioBitrate = audioBitrate;
      }
      if (cacheSeconds != null && cacheSeconds >= 0) {
        _lastCacheSeconds = cacheSeconds;
      }
      if (cacheSpeed != null && cacheSpeed >= 0) {
        _networkReadBytesPerSecond = cacheSpeed;
      }
      if (coreIdle != null) {
        _coreIdle = coreIdle == 'yes' || coreIdle == 'true';
      }
      if (pausedForCache != null) {
        _pausedForCache = pausedForCache == 'yes' || pausedForCache == 'true';
      }
      if (eofReached != null) {
        _eofReached = eofReached == 'yes' || eofReached == 'true';
      }
      if (format != null && format.isNotEmpty && format != 'N/A') {
        _containerFormat = format;
        _runtimeFormatLoaded = true;
      }
'''
replace_once(old_stats, new_stats, 'remove global stats setState')

replace_once(
    "  Future<void> _showPerformanceInfo() async {\n    final channel = widget.playlist[_currentIndex];\n",
    "  Future<void> _showPerformanceInfo() async {\n    await _refreshRuntimeStats();\n    if (!mounted) return;\n\n    final channel = widget.playlist[_currentIndex];\n",
    'refresh performance info on demand',
)

replace_once(
    "    _containerFormat = null;\n    _audioChannels = null;\n",
    "    _containerFormat = null;\n    _runtimeFormatLoaded = false;\n    _audioChannels = null;\n",
    'reset runtime format state',
)

replace_once(
    "    _watchdogTimer?.cancel();\n    _runtimeStatsTimer?.cancel();\n    _connectTimeoutTimer?.cancel();\n",
    "    _watchdogTimer?.cancel();\n    _connectTimeoutTimer?.cancel();\n",
    'dispose runtime stats timer',
)

path.write_text(text)
