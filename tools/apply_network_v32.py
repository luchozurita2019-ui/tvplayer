from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 occurrence, found {count}')
    text = text.replace(old, new, 1)


replace_once(
    "static const Duration _runtimeStatsInterval = Duration(seconds: 2);",
    "static const Duration _runtimeStatsInterval = Duration(seconds: 1);",
    'runtime stats interval',
)

replace_once(
    "  double? _lastCacheSeconds;\n  int _softRecoveryCount = 0;",
    "  double? _lastCacheSeconds;\n  double? _networkReadBytesPerSecond;\n  bool _coreIdle = false;\n  int _softRecoveryCount = 0;\n  int _networkRecoveryCount = 0;",
    'network state fields',
)

replace_once(
    """  Duration get _underrunGrace {\n    final seconds = math.max(\n      3.0,\n      _effectiveSettings.recoveryBufferSeconds + 1.5,\n    );\n    return Duration(milliseconds: (seconds * 1000).round());\n  }\n\n  double get _targetCacheSeconds => math.max(\n        1.0,\n        math.max(\n          _effectiveSettings.readaheadSeconds,\n          _effectiveSettings.recoveryBufferSeconds + 1.0,\n        ),\n      );\n""",
    """  Duration get _underrunGrace {\n    // Un corte pequeño debe tener margen para recuperarse sin reconstruir\n    // el canal, pero no esperamos varios segundos con la imagen congelada.\n    final seconds = math.min(\n      2.5,\n      math.max(1.25, _effectiveSettings.recoveryBufferSeconds + 0.5),\n    );\n    return Duration(milliseconds: (seconds * 1000).round());\n  }\n\n  int get _forwardBufferMb {\n    // El modo automático puede conservar el zapping rápido sin limitar la\n    // reserva de red a solo 8 MB. El tamaño máximo no obliga a esperar antes\n    // de mostrar imagen: únicamente permite acumular más colchón en segundo\n    // plano cuando el servidor puede entregar datos por delante del vivo.\n    if (_effectiveSettings.profile == BufferProfile.auto) {\n      return math.max(16, _effectiveSettings.bufferMb);\n    }\n    return _effectiveSettings.bufferMb;\n  }\n\n  double get _targetCacheSeconds {\n    final floor = switch (_effectiveSettings.profile) {\n      BufferProfile.ultraFast => 5.0,\n      BufferProfile.balanced => 8.0,\n      BufferProfile.stable => 15.0,\n      BufferProfile.auto => _effectiveSettings.bufferMb >= 32 ? 12.0 : 8.0,\n      BufferProfile.custom => math.max(4.0, _effectiveSettings.readaheadSeconds),\n    };\n\n    return math.max(\n      floor,\n      math.max(\n        _effectiveSettings.readaheadSeconds * 2.0,\n        _effectiveSettings.recoveryBufferSeconds + 3.0,\n      ),\n    );\n  }\n""",
    'buffer getters',
)

replace_once(
    """        await platform.setProperty('cache-pause', 'no');\n        await platform.setProperty('cache-pause-initial', 'no');\n        await platform.setProperty('demuxer-thread', 'yes');\n""",
    """        await platform.setProperty('cache-pause', 'no');\n        await platform.setProperty('cache-pause-initial', 'no');\n        await platform.setProperty('demuxer-thread', 'yes');\n\n        // Mantener la lectura hacia delante de forma continua. Con la\n        // histéresis en 0 mpv no llena por bloques y luego deja de leer hasta\n        // que la caché cae: intenta aprovechar constantemente el ancho de\n        // banda disponible del servidor.\n        await platform.setProperty('demuxer-hysteresis-secs', '0');\n        await platform.setProperty('demuxer-hysteresis-bytes', '0');\n\n        // IPTV no necesita un back-buffer grande. Reservamos la memoria para\n        // datos futuros y aumentamos moderadamente el buffer de I/O entre la\n        // red y el demuxer (128 KiB es el valor habitual de mpv).\n        await platform.setProperty('demuxer-max-back-bytes', '1MiB');\n        await platform.setProperty('demuxer-donate-buffer', 'no');\n        await platform.setProperty('stream-buffer-size', '512KiB');\n""",
    'native cache options',
)

replace_once(
    """        await platform.setProperty(\n          'demuxer-max-bytes',\n          '${_effectiveSettings.bufferMb}MiB',\n        );\n""",
    """        await platform.setProperty(\n          'demuxer-max-bytes',\n          '${_forwardBufferMb}MiB',\n        );\n""",
    'forward buffer memory',
)

replace_once(
    """          await platform.setProperty(\n            'demuxer-lavf-o',\n            'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'\n                'reconnect_delay_max=2,rw_timeout=8000000',\n          );\n""",
    """          await platform.setProperty(\n            'demuxer-lavf-o',\n            'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'\n                'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'\n                'multiple_requests=1,reconnect_delay_max=1,'\n                'rw_timeout=3000000',\n          );\n""",
    'ffmpeg http reconnect options',
)

replace_once(
    """    // Etapa 1: no descartamos datos. Simplemente reafirmamos Play y damos\n    // oportunidad a FFmpeg/mpv de continuar con la conexión existente.\n    try {\n      await _player.play();\n    } catch (_) {}\n\n    await Future<void>.delayed(const Duration(milliseconds: 1200));\n    if (!mounted || recoverySession != _sessionId) {\n      _softRecovering = false;\n      return;\n    }\n\n    if (_streamLooksRecovered()) {\n      _softRecoveryCount++;\n      _bufferingStartedAt = null;\n      _lastProgressAt = DateTime.now();\n      _softRecovering = false;\n      if (mounted) setState(() {});\n      return;\n    }\n\n    // Etapa 2: recién si sigue trabado descartamos paquetes viejos. Esto\n    // evita que drop-buffers provoque por sí mismo cortes en un canal sano.\n    try {\n      final platform = _player.platform;\n      if (platform is NativePlayer) {\n        await platform.command(const ['drop-buffers']);\n      }\n      await _player.play();\n    } catch (_) {}\n\n    await Future<void>.delayed(const Duration(milliseconds: 1200));\n    if (!mounted || recoverySession != _sessionId) {\n      _softRecovering = false;\n      return;\n    }\n\n    if (_streamLooksRecovered()) {\n      _softRecoveryCount++;\n      _bufferingStartedAt = null;\n      _lastProgressAt = DateTime.now();\n      _softRecovering = false;\n      if (mounted) setState(() {});\n      return;\n    }\n\n    _softRecovering = false;\n    if (mounted) setState(() {});\n    _handleFailure('El stream dejó de entregar datos', silent: true);\n""",
    """    // Etapa 1: FFmpeg ya dispone de reconexión HTTP interna. Damos un\n    // margen corto para que la misma conexión vuelva sin vaciar paquetes.\n    try {\n      await _player.play();\n    } catch (_) {}\n\n    await Future<void>.delayed(const Duration(milliseconds: 700));\n    if (!mounted || recoverySession != _sessionId) {\n      _softRecovering = false;\n      return;\n    }\n\n    if (_streamLooksRecovered()) {\n      _softRecoveryCount++;\n      _bufferingStartedAt = null;\n      _lastProgressAt = DateTime.now();\n      _softRecovering = false;\n      if (mounted) setState(() {});\n      return;\n    }\n\n    // Si la caché está vacía no hay nada útil que descartar: hacerlo solo\n    // alarga el corte. En ese caso pasamos pronto a una nueva conexión.\n    final cacheEmpty = _lastCacheSeconds == null || _lastCacheSeconds! <= 0.15;\n    if (_isBuffering || cacheEmpty) {\n      _networkRecoveryCount++;\n      _softRecovering = false;\n      if (mounted) setState(() {});\n      _handleFailure('La red dejó de entregar datos', silent: true);\n      return;\n    }\n\n    // Solo para un bloqueo extraño con paquetes todavía en caché usamos\n    // drop-buffers como último intento antes de reconstruir la conexión.\n    try {\n      final platform = _player.platform;\n      if (platform is NativePlayer) {\n        await platform.command(const ['drop-buffers']);\n      }\n      await _player.play();\n    } catch (_) {}\n\n    await Future<void>.delayed(const Duration(milliseconds: 500));\n    if (!mounted || recoverySession != _sessionId) {\n      _softRecovering = false;\n      return;\n    }\n\n    if (_streamLooksRecovered()) {\n      _softRecoveryCount++;\n      _bufferingStartedAt = null;\n      _lastProgressAt = DateTime.now();\n      _softRecovering = false;\n      if (mounted) setState(() {});\n      return;\n    }\n\n    _networkRecoveryCount++;\n    _softRecovering = false;\n    if (mounted) setState(() {});\n    _handleFailure('El stream dejó de entregar datos', silent: true);\n""",
    'soft recovery sequence',
)

replace_once(
    """      final cacheSeconds =\n          await _readDoubleProperty(platform, 'demuxer-cache-duration');\n      final format = await _readStringProperty(platform, 'file-format');\n""",
    """      final cacheSeconds =\n          await _readDoubleProperty(platform, 'demuxer-cache-duration');\n      final cacheSpeed = await _readDoubleProperty(platform, 'cache-speed');\n      final coreIdle = await _readStringProperty(platform, 'core-idle');\n      final format = await _readStringProperty(platform, 'file-format');\n""",
    'runtime network properties',
)

replace_once(
    """        if (cacheSeconds != null && cacheSeconds >= 0) {\n          _lastCacheSeconds = cacheSeconds;\n        }\n        if (format != null && format.isNotEmpty && format != 'N/A') {\n""",
    """        if (cacheSeconds != null && cacheSeconds >= 0) {\n          _lastCacheSeconds = cacheSeconds;\n        }\n        if (cacheSpeed != null && cacheSpeed >= 0) {\n          _networkReadBytesPerSecond = cacheSpeed;\n        }\n        if (coreIdle != null) {\n          _coreIdle = coreIdle == 'yes' || coreIdle == 'true';\n        }\n        if (format != null && format.isNotEmpty && format != 'N/A') {\n""",
    'runtime network state assignment',
)

replace_once(
    """  String _formatBitrate(double? bitsPerSecond) {\n    if (bitsPerSecond == null || bitsPerSecond <= 0) return 'No disponible';\n    if (bitsPerSecond >= 1000000) {\n      return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbps';\n    }\n    return '${(bitsPerSecond / 1000).toStringAsFixed(0)} kbps';\n  }\n""",
    """  String _formatBitrate(double? bitsPerSecond) {\n    if (bitsPerSecond == null || bitsPerSecond <= 0) return 'No disponible';\n    if (bitsPerSecond >= 1000000) {\n      return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbps';\n    }\n    return '${(bitsPerSecond / 1000).toStringAsFixed(0)} kbps';\n  }\n\n  String get _networkSpeedText {\n    final bytes = _networkReadBytesPerSecond;\n    if (bytes == null || bytes <= 0) return 'No disponible';\n    final mbps = bytes * 8 / 1000000;\n    return '${mbps.toStringAsFixed(2)} Mbps';\n  }\n\n  String get _networkHeadroomText {\n    final bytes = _networkReadBytesPerSecond;\n    final mediaBits = (_videoBitrate ?? 0) + (_audioBitrate ?? 0);\n    if (bytes == null || bytes <= 0 || mediaBits <= 0) return 'No disponible';\n    final ratio = (bytes * 8) / mediaBits;\n    return '${ratio.toStringAsFixed(2)}× del bitrate';\n  }\n""",
    'network diagnostics helpers',
)

replace_once(
    """              Text('Objetivo de caché: ${_targetCacheSeconds.toStringAsFixed(1)} s'),\n              const Text('Pausa automática por buffer: desactivada'),\n              Text('Recuperaciones suaves: $_softRecoveryCount'),\n""",
    """              Text('Objetivo de caché: ${_targetCacheSeconds.toStringAsFixed(1)} s'),\n              Text('Memoria de caché hacia delante: $_forwardBufferMb MB'),\n              Text('Velocidad de lectura de red: $_networkSpeedText'),\n              Text('Margen de red: $_networkHeadroomText'),\n              Text('Núcleo esperando datos: ${_coreIdle ? 'sí' : 'no'}'),\n              const Text('Pausa automática por buffer: desactivada'),\n              Text('Recuperaciones suaves: $_softRecoveryCount'),\n              Text('Reconexiones por falta de datos: $_networkRecoveryCount'),\n""",
    'stream diagnostics panel',
)

replace_once(
    """            Text('Buffer efectivo: ${_effectiveSettings.bufferMb} MB'),\n            Text('Caché objetivo: ${_targetCacheSeconds.toStringAsFixed(1)} s'),\n""",
    """            Text('Buffer configurado: ${_effectiveSettings.bufferMb} MB'),\n            Text('Buffer efectivo de red: $_forwardBufferMb MB'),\n            Text('Caché objetivo: ${_targetCacheSeconds.toStringAsFixed(1)} s'),\n            Text('Lectura de red: $_networkSpeedText'),\n            Text('Margen red/bitrate: $_networkHeadroomText'),\n""",
    'performance diagnostics panel',
)

replace_once(
    """    _lastCacheSeconds = null;\n    _softRecoveryCount = 0;\n    _bufferingStartedAt = null;\n""",
    """    _lastCacheSeconds = null;\n    _networkReadBytesPerSecond = null;\n    _coreIdle = false;\n    _softRecoveryCount = 0;\n    _networkRecoveryCount = 0;\n    _bufferingStartedAt = null;\n""",
    'reset network diagnostics',
)

replace_once(
    """                Video(controller: _controller),\n                if ((_isBuffering || _reconnecting || _softRecovering) &&\n""",
    """                Video(controller: _controller),\n                if (_hasEverPlayed && _errorMessage == null)\n                  Positioned(\n                    left: 18,\n                    bottom: 18,\n                    child: IgnorePointer(\n                      child: Container(\n                        padding: const EdgeInsets.symmetric(\n                          horizontal: 9,\n                          vertical: 5,\n                        ),\n                        decoration: BoxDecoration(\n                          color: Colors.black.withValues(alpha: 0.58),\n                          borderRadius: BorderRadius.circular(14),\n                        ),\n                        child: Row(\n                          mainAxisSize: MainAxisSize.min,\n                          children: [\n                            Container(\n                              width: 9,\n                              height: 9,\n                              decoration: const BoxDecoration(\n                                color: Colors.redAccent,\n                                shape: BoxShape.circle,\n                              ),\n                            ),\n                            const SizedBox(width: 6),\n                            const Text(\n                              'EN VIVO',\n                              style: TextStyle(\n                                color: Colors.white,\n                                fontWeight: FontWeight.w700,\n                                fontSize: 12,\n                                letterSpacing: 0.4,\n                              ),\n                            ),\n                          ],\n                        ),\n                      ),\n                    ),\n                  ),\n                if ((_isBuffering || _reconnecting || _softRecovering) &&\n""",
    'live badge overlay',
)

path.write_text(text, encoding='utf-8')
print('network v3.2 patch applied successfully')
