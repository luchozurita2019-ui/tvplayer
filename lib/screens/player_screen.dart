import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import '../services/playback_metrics_service.dart';
import '../widgets/channel_tile.dart';
import '../widgets/stable_video_view.dart';

const String _defaultUserAgent =
    'VLC/3.0.20 LibVLC/3.0.20 (iptv_player; +https://github.com)';

class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final List<Channel> playlist;
  final int initialIndex;
  final PlaybackSettings settings;

  const PlayerScreen({
    super.key,
    required this.channel,
    required this.playlist,
    required this.initialIndex,
    required this.settings,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const Duration _watchdogInterval = Duration(seconds: 3);
  static const String _fastProbeSize = '131072'; // 128 KiB
  static const String _normalProbeSize = '5000000';

  final PlaybackMetricsService _metrics = PlaybackMetricsService.instance;

  late final Player _player;
  late final VideoController _controller;
  late int _currentIndex;
  late PlaybackSettings _effectiveSettings;

  bool _isBuffering = true;
  bool _isPlaying = false;
  bool _hasEverPlayed = false;
  bool _reconnecting = false;
  bool _showChannelList = false;
  bool _opening = false;
  bool _useFastProbe = false;
  bool _currentOpenUsesFastProbe = false;
  bool _normalProbeFallbackUsed = false;
  String? _errorMessage;
  String _channelListQuery = '';
  String _tuningLabel = 'Equilibrado';
  int _retryCount = 0;
  int _sessionId = 0;
  int _startupSession = 0;
  int? _lastStartupMs;
  String? _startupUrl;

  Timer? _watchdogTimer;
  Timer? _connectTimeoutTimer;
  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();
  Stopwatch? _startupStopwatch;

  StreamSubscription? _bufferingSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;

  int get _maxAutoRetries => _effectiveSettings.maxRetries;
  Duration get _stallThreshold =>
      Duration(seconds: _effectiveSettings.stallThresholdSeconds);
  Duration get _connectTimeout =>
      Duration(seconds: _effectiveSettings.connectTimeoutSeconds);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _effectiveSettings = widget.settings;

    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: widget.settings.bufferBytes,
      ),
    );
    _controller = VideoController(_player);

    _completedSub = _player.stream.completed.listen((completed) {
      if (completed &&
          mounted &&
          !_opening &&
          !_reconnecting &&
          _errorMessage == null) {
        _handleFailure(
          'El canal se pausó solo o el stream terminó inesperadamente',
          silent: true,
        );
      }
    });

    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!mounted) return;
      setState(() => _isBuffering = buffering);
      if (!buffering) {
        _connectTimeoutTimer?.cancel();
        _hasEverPlayed = true;
        _retryCount = 0;

        if ((_startupStopwatch?.isRunning ?? false) &&
            _startupSession == _sessionId) {
          _startupStopwatch!.stop();
          final elapsed = _startupStopwatch!.elapsedMilliseconds;
          final url = _startupUrl;
          setState(() => _lastStartupMs = elapsed);
          if (url != null) {
            unawaited(_metrics.recordStartup(url, elapsed));
          }
        }
      }
    });

    _errorSub = _player.stream.error.listen((error) {
      if (_opening) return;
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
    unawaited(_initializeAndPlay());
  }

  Future<void> _initializeAndPlay() async {
    await _configureNativeBaseOptions();
    if (!mounted) return;
    await _playCurrent();
  }

  Future<void> _configureNativeBaseOptions() async {
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('keep-open', 'yes');
        await platform.setProperty('cache-pause', 'yes');
        await platform.setProperty('cache-pause-initial', 'no');
        await platform.setProperty('demuxer-thread', 'yes');
      }
    } catch (_) {
      // El backend web no expone propiedades nativas de mpv.
    }
  }

  Future<bool> _prepareChannelTuning(
    int session, {
    required bool forceNormalProbe,
  }) async {
    final channel = widget.playlist[_currentIndex];
    final tuning = await _metrics.tuningFor(channel.url, widget.settings);
    if (!mounted || session != _sessionId) return false;

    _effectiveSettings = tuning.settings;
    _tuningLabel = tuning.label;
    _useFastProbe = tuning.useFastProbe;
    _currentOpenUsesFastProbe = _useFastProbe && !forceNormalProbe;

    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty(
          'cache-pause-wait',
          _effectiveSettings.recoveryBufferSeconds.toStringAsFixed(2),
        );
        await platform.setProperty(
          'demuxer-readahead-secs',
          _effectiveSettings.readaheadSeconds.toStringAsFixed(2),
        );
        await platform.setProperty(
          'demuxer-max-bytes',
          '${_effectiveSettings.bufferMb}MiB',
        );

        // Fast Probe: menos datos para identificar el stream. Si un canal
        // raro no abre con estos valores, se hace un segundo intento
        // automático con valores conservadores sin gastar un reintento.
        await platform.setProperty(
          'demuxer-lavf-probesize',
          _currentOpenUsesFastProbe ? _fastProbeSize : _normalProbeSize,
        );
        await platform.setProperty(
          'demuxer-lavf-probescore',
          _currentOpenUsesFastProbe ? '15' : '26',
        );
      }
    } catch (_) {
      // No es crítico si una plataforma no soporta estas propiedades.
    }

    return mounted && session == _sessionId;
  }

  void _checkStall() {
    if (!mounted || _opening || _reconnecting || _errorMessage != null) {
      return;
    }
    if (!_isPlaying) return;

    final silentFor = DateTime.now().difference(_lastProgressAt);
    if (silentFor > _stallThreshold) {
      final url = widget.playlist[_currentIndex].url;
      unawaited(_metrics.recordStall(url));
      _handleFailure('El stream dejó de responder', silent: true);
    }
  }

  void _handleFailure(String message, {bool silent = false}) {
    if (!mounted || _opening) return;
    _connectTimeoutTimer?.cancel();
    final failedSession = _sessionId;
    final url = widget.playlist[_currentIndex].url;
    unawaited(_metrics.recordFailure(url));

    if (_retryCount < _maxAutoRetries) {
      setState(() {
        _reconnecting = true;
        _errorMessage = null;
      });

      final seconds = 1 << _retryCount;
      _retryCount++;
      Future.delayed(Duration(seconds: seconds), () {
        if (!mounted || failedSession != _sessionId) return;
        unawaited(_playCurrent(isRetry: true, forceNormalProbe: true));
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

  void _startNormalProbeFallback(int session, String reason) {
    if (!mounted || session != _sessionId || _normalProbeFallbackUsed) return;
    _normalProbeFallbackUsed = true;
    final url = widget.playlist[_currentIndex].url;
    unawaited(_metrics.recordFastProbeFallback(url));

    setState(() {
      _reconnecting = true;
      _errorMessage = null;
    });

    // El fallback es inmediato: no consume un reintento ni espera backoff.
    scheduleMicrotask(() {
      if (!mounted || session != _sessionId) return;
      unawaited(_playCurrent(isRetry: true, forceNormalProbe: true));
    });
  }

  Future<void> _playCurrent({
    bool isRetry = false,
    bool forceNormalProbe = false,
  }) async {
    final session = ++_sessionId;
    _opening = true;
    _connectTimeoutTimer?.cancel();

    if (!isRetry) {
      _retryCount = 0;
      _normalProbeFallbackUsed = false;
    }

    _hasEverPlayed = false;
    _startupStopwatch = Stopwatch()..start();
    _startupSession = session;
    _startupUrl = widget.playlist[_currentIndex].url;

    if (mounted) {
      setState(() {
        _errorMessage = null;
        _isBuffering = true;
        _reconnecting = isRetry;
        _lastStartupMs = null;
      });
    }

    _lastKnownPosition = Duration.zero;
    _lastProgressAt = DateTime.now();

    final prepared = await _prepareChannelTuning(
      session,
      forceNormalProbe: forceNormalProbe,
    );
    if (!prepared) return;

    try {
      await _player.stop();
      if (!mounted || session != _sessionId) return;

      final channel = widget.playlist[_currentIndex];
      final headers = <String, String>{
        'User-Agent': channel.httpUserAgent ?? _defaultUserAgent,
        if (channel.httpReferrer != null) 'Referer': channel.httpReferrer!,
      };

      await _player
          .open(Media(channel.url, httpHeaders: headers))
          .timeout(_connectTimeout);
      if (!mounted || session != _sessionId) return;

      _opening = false;
      _connectTimeoutTimer = Timer(_connectTimeout, () {
        if (!mounted || session != _sessionId || _hasEverPlayed) return;
        if (_currentOpenUsesFastProbe && !_normalProbeFallbackUsed) {
          _startNormalProbeFallback(session, 'sin datos');
          return;
        }
        _handleFailure('El canal tardó demasiado en responder', silent: true);
      });
    } on TimeoutException {
      if (!mounted || session != _sessionId) return;
      _opening = false;
      unawaited(_player.stop());
      if (_currentOpenUsesFastProbe && !_normalProbeFallbackUsed) {
        _startNormalProbeFallback(session, 'timeout de apertura');
        return;
      }
      _handleFailure('El canal tardó demasiado en abrir', silent: true);
    } catch (e) {
      if (!mounted || session != _sessionId) return;
      _opening = false;
      if (_currentOpenUsesFastProbe && !_normalProbeFallbackUsed) {
        _startNormalProbeFallback(session, 'error de detección');
        return;
      }
      _handleFailure('No se pudo abrir el canal: $e');
    }
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

  Future<void> _showPerformanceInfo() async {
    final channel = widget.playlist[_currentIndex];
    final stats = await _metrics.statsForUrl(channel.url);
    if (!mounted) return;

    final requestedProfile = switch (widget.settings.profile) {
      BufferProfile.auto => 'Automático',
      BufferProfile.ultraFast => 'Ultra rápido',
      BufferProfile.balanced => 'Equilibrado',
      BufferProfile.stable => 'Estable',
      BufferProfile.custom => 'Personalizado',
    };
    final average = stats.averageStartupMs;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rendimiento del canal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Servidor: ${stats.host}'),
            Text('Perfil elegido: $requestedProfile'),
            Text('Ajuste actual: $_tuningLabel'),
            Text('Buffer efectivo: ${_effectiveSettings.bufferMb} MB'),
            Text(
              'Lectura anticipada: ${_effectiveSettings.readaheadSeconds.toStringAsFixed(1)} s',
            ),
            Text(
              'Buffer de recuperación: ${_effectiveSettings.recoveryBufferSeconds.toStringAsFixed(1)} s',
            ),
            Text(
              'Arranque actual: ${_lastStartupMs == null ? 'midiendo…' : '$_lastStartupMs ms'}',
            ),
            Text(
              'Promedio servidor: ${average == null ? 'sin muestras' : '${average.round()} ms'}',
            ),
            Text('Muestras: ${stats.startupCount}'),
            Text('Fallos: ${stats.failures} · Cortes: ${stats.stalls}'),
            Text('Fast Probe: ${_currentOpenUsesFastProbe ? 'activo' : 'normal'}'),
            if (stats.fastProbeFallbacks > 0)
              Text('Fallbacks de detección: ${stats.fastProbeFallbacks}'),
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

  @override
  void dispose() {
    _sessionId++;
    _watchdogTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.playlist[_currentIndex];
    final query = _channelListQuery.toLowerCase();
    final filteredChannels = query.trim().isEmpty
        ? widget.playlist
        : widget.playlist
            .where((c) => c.name.toLowerCase().contains(query))
            .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(channel.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (_lastStartupMs != null)
            TextButton.icon(
              onPressed: _showPerformanceInfo,
              icon: const Icon(Icons.speed, color: Colors.white70),
              label: Text(
                '${_lastStartupMs} ms',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
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
                StableVideoView(player: _player, controller: _controller),
                if ((_isBuffering || _reconnecting) && _errorMessage == null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      if (_reconnecting) ...[
                        const SizedBox(height: 12),
                        Text(
                          _normalProbeFallbackUsed && _retryCount == 0
                              ? 'Probando modo compatible…'
                              : 'Reconectando (intento $_retryCount de $_maxAutoRetries)…',
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
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 48,
                        ),
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
                              onPressed: () => unawaited(_playCurrent()),
                              child: const Text('Reintentar'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  setState(() => _showChannelList = true),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
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
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            top: 0,
            bottom: 0,
            right: _showChannelList ? 0 : -340,
            width: 340,
            child: Material(
              color: Colors.black.withValues(alpha: 0.92),
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
                              ? Colors.white.withValues(alpha: 0.08)
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
