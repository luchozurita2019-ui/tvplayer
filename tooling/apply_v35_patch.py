from pathlib import Path

player_path = Path('lib/screens/player_screen.dart')
home_path = Path('lib/screens/home_screen.dart')

s = player_path.read_text()

old = """    _completedSub = _player.stream.completed.listen((completed) {
      if (completed &&
          mounted &&
          !_opening &&
          !_reconnecting &&
          _errorMessage == null) {
        _handleFailure('El stream terminó inesperadamente', silent: true);
      }
    });
"""
new = """    _completedSub = _player.stream.completed.listen((completed) {
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
if old not in s:
    raise SystemExit('No se encontró completed listener esperado')
s = s.replace(old, new, 1)

s = s.replace(
    "  bool _coreIdle = false;\n",
    "  bool _coreIdle = false;\n  bool _pausedForCache = false;\n  bool _eofReached = false;\n  int _seamlessEofRecoveries = 0;\n",
    1,
)

old = """        await platform.setProperty('keep-open', 'yes');
        await platform.setProperty('cache-pause', 'yes');
        await platform.setProperty('cache-pause-initial', 'no');
        await platform.setProperty('demuxer-thread', 'yes');
"""
new = """        // keep-open=yes convierte un EOF en una pausa del Player. En IPTV
        // algunos servidores terminan la conexión periódicamente aunque la
        // señal continúe. No queremos que mpv transforme ese EOF en Pause.
        await platform.setProperty('keep-open', 'no');

        // No dejamos que mpv cambie el estado global a Pause cuando el cache
        // se vacía. El frame puede quedar quieto mientras llegan paquetes,
        // pero el motor sigue en reproducción y FFmpeg puede reconectar abajo.
        await platform.setProperty('cache-pause', 'no');
        await platform.setProperty('cache-pause-initial', 'no');
        await platform.setProperty('demuxer-thread', 'yes');
"""
if old not in s:
    raise SystemExit('No se encontró configuración base esperada')
s = s.replace(old, new, 1)

needle = """        await platform.setProperty(
          'demuxer-lavf-probescore',
          _currentOpenUsesFastProbe ? '15' : '26',
        );
"""
insert = needle + """

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
if needle not in s:
    raise SystemExit('No se encontró probescore esperado')
s = s.replace(needle, insert, 1)

old = """      final coreIdle = await _readStringProperty(platform, 'core-idle');
      final format = await _readStringProperty(platform, 'file-format');
"""
new = """      final coreIdle = await _readStringProperty(platform, 'core-idle');
      final pausedForCache =
          await _readStringProperty(platform, 'paused-for-cache');
      final eofReached = await _readStringProperty(platform, 'eof-reached');
      final format = await _readStringProperty(platform, 'file-format');
"""
if old not in s:
    raise SystemExit('No se encontró runtime properties esperado')
s = s.replace(old, new, 1)

old = """        if (coreIdle != null) {
          _coreIdle = coreIdle == 'yes' || coreIdle == 'true';
        }
        if (format != null && format.isNotEmpty && format != 'N/A') {
"""
new = """        if (coreIdle != null) {
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
"""
if old not in s:
    raise SystemExit('No se encontró setState runtime esperado')
s = s.replace(old, new, 1)

old = """  Future<void> _playCurrent({
    bool isRetry = false,
    bool forceNormalProbe = false,
  }) async {
"""
new = """  Future<void> _playCurrent({
    bool isRetry = false,
    bool forceNormalProbe = false,
    bool skipStop = false,
  }) async {
"""
if old not in s:
    raise SystemExit('No se encontró firma _playCurrent')
s = s.replace(old, new, 1)

old = """    try {
      await _player.stop();
      if (!mounted || session != _sessionId) return;

      final channel = widget.playlist[_currentIndex];
"""
new = """    try {
      // En recuperación de EOF reemplazamos el Media directamente. Evitar un
      // stop explícito reduce el hueco visible entre una conexión y la siguiente.
      if (!skipStop) {
        await _player.stop();
        if (!mounted || session != _sessionId) return;
      }

      final channel = widget.playlist[_currentIndex];
"""
if old not in s:
    raise SystemExit('No se encontró stop previo a open')
s = s.replace(old, new, 1)

old = """    _networkReadBytesPerSecond = null;
    _coreIdle = false;
  }
"""
new = """    _networkReadBytesPerSecond = null;
    _coreIdle = false;
    _pausedForCache = false;
    _eofReached = false;
    _seamlessEofRecoveries = 0;
  }
"""
if old not in s:
    raise SystemExit('No se encontró reset stream info')
s = s.replace(old, new, 1)

old = """              Text('Núcleo esperando datos: ${_coreIdle ? 'sí' : 'no'}'),
              const Text(
                'Motor de red: modo estable, sin reconexiones forzadas adicionales',
              ),
"""
new = """              Text('Núcleo esperando datos: ${_coreIdle ? 'sí' : 'no'}'),
              Text('Pausado por caché (mpv): ${_pausedForCache ? 'sí' : 'no'}'),
              Text('EOF detectado por mpv: ${_eofReached ? 'sí' : 'no'}'),
              Text('Recuperaciones transparentes de EOF: $_seamlessEofRecoveries'),
              const Text(
                'Motor de red: reconexión HTTP/EOF transparente para señal en vivo',
              ),
"""
if old not in s:
    raise SystemExit('No se encontró bloque de diagnóstico de red')
s = s.replace(old, new, 1)

old = """            Text('Resolución actual: $_resolutionText'),
"""
new = """            Text('Resolución actual: $_resolutionText'),
            Text('Pausa de caché mpv: ${_pausedForCache ? 'sí' : 'no'}'),
            Text('EOF detectado: ${_eofReached ? 'sí' : 'no'}'),
            Text('Recuperaciones EOF: $_seamlessEofRecoveries'),
"""
if old not in s:
    raise SystemExit('No se encontró resolución en rendimiento')
s = s.replace(old, new, 1)

# Dar identidad TV FULL azul también dentro del reproductor sin teñir el video.
s = s.replace(
    "        backgroundColor: Colors.black,\n        foregroundColor: Colors.white,\n        title: Text(channel.name, overflow: TextOverflow.ellipsis),\n",
    "        backgroundColor: const Color(0xFF071D38),\n        foregroundColor: Colors.white,\n        title: Row(\n          children: [\n            const Text(\n              'TV FULL',\n              style: TextStyle(\n                color: Color(0xFF58A6FF),\n                fontWeight: FontWeight.w800,\n                letterSpacing: 0.6,\n              ),\n            ),\n            const SizedBox(width: 12),\n            Expanded(\n              child: Text(channel.name, overflow: TextOverflow.ellipsis),\n            ),\n          ],\n        ),\n",
    1,
)
s = s.replace(
    "              color: Colors.black.withValues(alpha: 0.92),\n",
    "              color: const Color(0xFF071D38).withValues(alpha: 0.96),\n",
    1,
)
s = s.replace(
    "                              ? Colors.white.withValues(alpha: 0.08)\n",
    "                              ? const Color(0xFF1677FF).withValues(alpha: 0.18)\n",
    1,
)

player_path.write_text(s)

h = home_path.read_text()
old = """                Text(
                  _sectionTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
"""
new = """                Text(
                  'TV FULL · $_sectionTitle',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
"""
if old not in h:
    raise SystemExit('No se encontró título del home')
h = h.replace(old, new, 1)
home_path.write_text(h)
