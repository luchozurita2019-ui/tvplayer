import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/channel.dart';
import '../widgets/channel_tile.dart';

/// User-Agent por defecto cuando el canal no trae uno propio en el M3U.
/// Muchos servidores IPTV bloquean o cuelgan la conexión ante clientes
/// "desconocidos"; imitar un reproductor ampliamente aceptado (VLC)
/// evita ese bloqueo silencioso en la mayoría de los proveedores.
const String _defaultUserAgent =
    'VLC/3.0.20 LibVLC/3.0.20 (iptv_player; +https://github.com)';

/// Pantalla de reproducción, estilo TiviMate:
/// - Motor nativo media_kit (libmpv/FFmpeg) para arranque rápido.
/// - Timeout de CONEXIÓN real: si un canal no empieza a entregar datos
///   en un tiempo razonable, se corta y reintenta — nunca se queda
///   "cargando" indefinidamente (antes podía quedar así minutos).
/// - Watchdog de reproducción: detecta cuelgues silenciosos ya en curso.
/// - Reconexión automática con backoff exponencial.
/// - Panel de canales deslizable sin salir del video, para cambiar de
///   canal sin perder el stream actual de vista.
class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final List<Channel> playlist;
  final int initialIndex;

  const PlayerScreen({
    super.key,
    required this.channel,
    required this.playlist,
    required this.initialIndex,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const int _maxAutoRetries = 5;
  static const Duration _watchdogInterval = Duration(seconds: 6);
  static const Duration _stallThreshold = Duration(seconds: 10);
  // Si al abrir un canal no hay señal de vida (ni buffering-false, ni
  // datos) en este tiempo, lo tratamos como fallo y reintentamos.
  // Esto es lo que evita el cuelgue de "23 minutos cargando".
  static const Duration _connectTimeout = Duration(seconds: 15);

  late final Player _player;
  late final VideoController _controller;
  late int _currentIndex;

  bool _isBuffering = true;
  String? _errorMessage;
  int _retryCount = 0;
  bool _reconnecting = false;
  bool _showChannelList = false;
  String _channelListQuery = '';

  Timer? _watchdogTimer;
  Timer? _connectTimeoutTimer;
  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();
  bool _isPlaying = false;
  bool _hasEverPlayed = false;

  StreamSubscription? _bufferingSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 8 * 1024 * 1024, // 8MB: prioriza arranque rápido
      ),
    );
    _controller = VideoController(_player);
    _configureNativeLiveStreamOptions();

    _completedSub = _player.stream.completed.listen((completed) {
      // BUG COMÚN EN STREAMS EN VIVO: el motor a veces calcula mal la
      // duración de un flujo IPTV (que en realidad es infinito) y, al
      // llegar a esa duración falsa, se PAUSA SOLO pensando que el
      // archivo terminó (se ve como "00:40 / 00:39" en la barra: la
      // posición ya pasó la duración detectada). demuxer-lavf-o=live=1
      // debería evitarlo, pero por si igual ocurre, reconectamos en
      // vez de dejar al usuario con la pantalla pausada.
      if (completed && mounted && !_reconnecting && _errorMessage == null) {
        _handleFailure('El canal se pausó solo (duración mal detectada)',
            silent: true);
      }
    });

    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!mounted) return;
      setState(() => _isBuffering = buffering);
      if (!buffering) {
        // Llegaron datos reales: cancelamos el timeout de conexión
        // y reseteamos el contador de reintentos.
        _connectTimeoutTimer?.cancel();
        _hasEverPlayed = true;
        _retryCount = 0;
      }
    });

    _errorSub = _player.stream.error.listen((error) {
      _handleFailure('Error de reproducción: $error');
    });

    _playingSub = _player.stream.playing.listen((playing) {
      _isPlaying = playing;
    });

    _positionSub = _player.stream.position.listen((position) {
      if (position != _lastKnownPosition) {
        _lastKnownPosition = position;
        _lastProgressAt = DateTime.now();
      }
    });

    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) => _checkStall());

    _playCurrent();
  }

  /// Le indica al motor nativo (mpv/FFmpeg) que esto es un flujo EN VIVO,
  /// no un archivo con duración fija. Sin esto, algunos streams IPTV
  /// (sobre todo MPEG-TS crudo por HTTP) hacen que mpv calcule una
  /// duración incorrecta a partir de los primeros segundos, y al llegar
  /// ahí se pausa solo pensando que el archivo terminó — exactamente el
  /// síntoma de "el canal se pausa cada tantos minutos y hay que darle
  /// Play de nuevo".
  Future<void> _configureNativeLiveStreamOptions() async {
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('demuxer-lavf-o', 'live=1');
        // Red de seguridad extra: si igual llega a "fin de archivo",
        // que mantenga el último frame en vez de cerrar el stream,
        // dándole tiempo a nuestro listener de completed a reconectar.
        await platform.setProperty('keep-open', 'yes');
      }
    } catch (_) {
      // Plataformas sin backend nativo (ej. web) no soportan esto;
      // no es crítico, el resto de las protecciones siguen activas.
    }
  }

  void _checkStall() {
    if (!mounted || _reconnecting || _errorMessage != null) return;
    if (!_isPlaying) return; // ya cubierto por el connectTimeout

    final silentFor = DateTime.now().difference(_lastProgressAt);
    if (silentFor > _stallThreshold) {
      _handleFailure('El stream dejó de responder', silent: true);
    }
  }

  void _handleFailure(String message, {bool silent = false}) {
    if (!mounted) return;
    _connectTimeoutTimer?.cancel();

    if (_retryCount < _maxAutoRetries) {
      setState(() {
        _reconnecting = true;
        _errorMessage = null;
      });
      final seconds = 1 << _retryCount; // 1s, 2s, 4s, 8s, 16s
      _retryCount++;
      Future.delayed(Duration(seconds: seconds), () {
        if (mounted) _playCurrent(isRetry: true);
      });
    } else {
      setState(() {
        _reconnecting = false;
        _errorMessage = silent
            ? 'Este canal no responde tras varios intentos.\nProbá con otro canal o volvé a intentar más tarde.'
            : message;
      });
    }
  }

  void _playCurrent({bool isRetry = false}) {
    if (!isRetry) _retryCount = 0;
    _hasEverPlayed = false;
    setState(() {
      _errorMessage = null;
      _isBuffering = true;
      _reconnecting = false;
    });
    _lastKnownPosition = Duration.zero;
    _lastProgressAt = DateTime.now();

    final channel = widget.playlist[_currentIndex];
    final headers = <String, String>{
      'User-Agent': channel.httpUserAgent ?? _defaultUserAgent,
      if (channel.httpReferrer != null) 'Referer': channel.httpReferrer!,
    };

    _player.open(Media(channel.url, httpHeaders: headers));

    // Arranca el reloj de conexión: si no hay datos en _connectTimeout,
    // se trata como fallo (esto es lo que antes faltaba y permitía
    // que un canal quedara "cargando" indefinidamente).
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(_connectTimeout, () {
      if (!mounted || _hasEverPlayed) return;
      _handleFailure('El canal tardó demasiado en responder', silent: true);
    });
  }

  void _switchToChannel(int index) {
    if (index == _currentIndex) {
      setState(() => _showChannelList = false);
      return;
    }
    setState(() {
      _currentIndex = index;
      _showChannelList = false;
    });
    _playCurrent();
  }

  void _next() {
    if (_currentIndex < widget.playlist.length - 1) {
      setState(() => _currentIndex++);
      _playCurrent();
    }
  }

  void _previous() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _playCurrent();
    }
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.playlist[_currentIndex];

    final filteredChannels = _channelListQuery.trim().isEmpty
        ? widget.playlist
        : widget.playlist
            .where((c) =>
                c.name.toLowerCase().contains(_channelListQuery.toLowerCase()))
            .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(channel.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(_showChannelList ? Icons.close : Icons.list),
            tooltip: 'Lista de canales',
            onPressed: () =>
                setState(() => _showChannelList = !_showChannelList),
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Video(controller: _controller),
                if ((_isBuffering || _reconnecting) && _errorMessage == null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      if (_reconnecting) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Reconectando (intento $_retryCount de $_maxAutoRetries)...',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ],
                  ),
                if (_errorMessage != null)
                  Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: () => _playCurrent(),
                              child: const Text('Reintentar'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  setState(() => _showChannelList = true),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white),
                              child: const Text('Ver otros canales'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Panel deslizable de canales, estilo TiviMate: se abre sobre
          // el video sin cortar la reproducción de fondo.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            top: 0,
            bottom: 0,
            right: _showChannelList ? 0 : -340,
            width: 340,
            child: Material(
              color: Colors.black.withOpacity(0.92),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Buscar canal...',
                        hintStyle: TextStyle(color: Colors.white54),
                        prefixIcon: Icon(Icons.search, color: Colors.white54),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white54),
                        ),
                        isDense: true,
                      ),
                      onChanged: (value) =>
                          setState(() => _channelListQuery = value),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredChannels.length,
                      itemBuilder: (context, index) {
                        final c = filteredChannels[index];
                        final realIndex = widget.playlist.indexOf(c);
                        final isCurrent = realIndex == _currentIndex;
                        return Container(
                          color: isCurrent
                              ? Colors.white.withOpacity(0.08)
                              : Colors.transparent,
                          child: ChannelTile(
                            channel: c,
                            isFavorite: false,
                            onFavoriteToggle: () {},
                            onTap: () => _switchToChannel(realIndex),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.black,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous, color: Colors.white),
              onPressed: _currentIndex > 0 ? _previous : null,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.white),
              onPressed:
                  _currentIndex < widget.playlist.length - 1 ? _next : null,
            ),
          ],
        ),
      ),
    );
  }
}
