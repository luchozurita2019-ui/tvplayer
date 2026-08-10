import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import '../services/artwork_cache_service.dart';
import '../services/playback_metrics_service.dart';
import '../services/server_compatibility_service.dart';
import '../widgets/channel_tile.dart';
import '../widgets/live_video_view.dart';

const String _defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/96.0.4664.18 Safari/537.36';
const String _legacyVlcUserAgent =
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

class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final List<Channel> playlist;
  final int initialIndex;
  final PlaybackSettings settings;
  final bool isLiveContent;

  const PlayerScreen({
    super.key,
    required this.channel,
    required this.playlist,
    required this.initialIndex,
    required this.settings,
    this.isLiveContent = true,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const Duration _watchdogInterval = Duration(seconds: 2);
  static const String _fastProbeSize = '131072';
  static const String _normalProbeSize = '5000000';
  static const int _hlsSegmentRetryCount = 5;
  static const Duration _liveTransientErrorGrace = Duration(seconds: 15);

  final PlaybackMetricsService _metrics = PlaybackMetricsService.instance;
  final ServerCompatibilityService _compatibility =
      ServerCompatibilityService.instance;

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
  bool _runtimeStatsBusy = false;
  bool _runtimeFormatLoaded = false;
  bool _acceptPlaybackEvents = true;
  bool _providerIssueHint = false;

  String? _errorMessage;
  String _channelListQuery = '';
  String _tuningLabel = 'Equilibrado';
  int _retryCount = 0;
  int _sessionId = 0;
  int _startupSession = 0;
  int? _lastStartupMs;
  int? _lastZapMs;
  int? _zapSession;
  String? _startupUrl;
  String? _lastConnectionDetail;
  int _recentBufferingEvents = 0;
  DateTime _bufferingWindowStartedAt = DateTime.now();

  int? _videoWidth;
  int? _videoHeight;
  double? _videoFps;
  double? _videoBitrate;
  double? _audioBitrate;
  String? _videoCodec;
  String? _audioCodec;
  String? _pixelFormat;
  String? _containerFormat;
  String? _audioChannels;
  int? _audioSampleRate;
  double? _lastCacheSeconds;
  double? _networkReadBytesPerSecond;
  bool _coreIdle = false;
  bool _pausedForCache = false;
  bool _eofReached = false;
  int _seamlessEofRecoveries = 0;

  List<ServerCompatibilityMode> _compatibilityPlan = const [
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

  final ValueNotifier<_ConnectionHealthSnapshot> _connectionHealth =
      ValueNotifier<_ConnectionHealthSnapshot>(_ConnectionHealthSnapshot.stable);

  Timer? _watchdogTimer;
  Timer? _connectTimeoutTimer;
  Timer? _retryTimer;
  Timer? _transientLiveFailureTimer;
  Timer? _connectionProbeTimer;
  Timer? _connectionRecoveryTimer;
  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();
  Stopwatch? _startupStopwatch;
  Stopwatch? _zapStopwatch;

  StreamSubscription? _bufferingSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _videoParamsSub;
  StreamSubscription? _trackSub;
  StreamSubscription? _audioBitrateSub;
  StreamSubscription? _logSub;

  int get _maxAutoRetries => _effectiveSettings.maxRetries;
  Duration get _stallThreshold =>
      Duration(seconds: _effectiveSettings.stallThresholdSeconds);
  Duration get _connectTimeout =>
      Duration(seconds: _effectiveSettings.connectTimeoutSeconds);

  @override
  void initState() {
    super.initState();
    ArtworkCacheService.instance.pauseForPlayback();
    _currentIndex = widget.initialIndex;
    _effectiveSettings = widget.settings;

    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: widget.settings.bufferBytes,
      ),
    );
    _controller = VideoController(_player);

    _completedSub = _player.stream.completed.listen((completed) {
      if (!completed ||
          !mounted ||
          _opening ||
          _reconnecting ||
          _errorMessage != null) {
        return;
      }
      unawaited(_handleCompletedStream());
    });

    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!mounted || !_acceptPlaybackEvents) return;

      if (buffering && _hasEverPlayed && !_opening && !_reconnecting) {
        _onBufferingStarted();
      }

      if (!buffering) {
        _onBufferingRecovered();
        _connectTimeoutTimer?.cancel();
        _retryTimer?.cancel();
        _retryTimer = null;
        _transientLiveFailureTimer?.cancel();
        _transientLiveFailureTimer = null;
        _hasEverPlayed = true;
        _retryCount = 0;
        _lastProgressAt = DateTime.now();
        // Leemos el formato real una sola vez por canal. Esto conserva la
        // detección de HLS para URLs sin .m3u8 sin mantener un polling técnico.
        unawaited(_refreshContainerFormat());
      }

      setState(() {
        _isBuffering = buffering;
        if (!buffering) {
          _reconnecting = false;
        }
      });

      if (!buffering &&
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
    });

    _errorSub = _player.stream.error.listen((error) {
      if (_opening) return;
      final message = 'Error de reproducción: $error';
      if (widget.isLiveContent && _hasEverPlayed) {
        _scheduleTransientLiveFailure(message);
        return;
      }
      _handleFailure(message);
    });

    _playingSub = _player.stream.playing.listen((playing) {
      if (!_acceptPlaybackEvents) return;
      _isPlaying = playing;
      if (playing) _lastProgressAt = DateTime.now();
    });

    _positionSub = _player.stream.position.listen((position) {
      if (!_acceptPlaybackEvents) return;
      if (position != _lastKnownPosition) {
        _lastKnownPosition = position;
        _lastProgressAt = DateTime.now();
        _transientLiveFailureTimer?.cancel();
        _transientLiveFailureTimer = null;
      }
    });

    _videoParamsSub = _player.stream.videoParams.listen((params) {
      if (!mounted) return;
      final width = params.w ?? params.dw;
      final height = params.h ?? params.dh;
      final pixelFormat = params.pixelformat;
      if (width == _videoWidth &&
          height == _videoHeight &&
          pixelFormat == _pixelFormat) {
        return;
      }
      setState(() {
        _videoWidth = width;
        _videoHeight = height;
        _pixelFormat = pixelFormat;
      });
    });

    _trackSub = _player.stream.track.listen((track) {
      if (!mounted) return;
      final video = track.video;
      final audio = track.audio;
      setState(() {
        _videoCodec = video.codec;
        _videoFps = video.fps ?? _videoFps;
        if (video.bitrate != null && video.bitrate! > 0) {
          _videoBitrate = video.bitrate!.toDouble();
        }
        if (_videoWidth == null && video.w != null) _videoWidth = video.w;
        if (_videoHeight == null && video.h != null) _videoHeight = video.h;

        _audioCodec = audio.codec;
        _audioChannels = audio.channels;
        _audioSampleRate = audio.samplerate;
        if (audio.bitrate != null && audio.bitrate! > 0) {
          _audioBitrate = audio.bitrate!.toDouble();
        }
      });
    });

    _audioBitrateSub = _player.stream.audioBitrate.listen((bitrate) {
      if (!mounted || bitrate == null || bitrate <= 0) return;
      setState(() => _audioBitrate = bitrate);
    });

    _logSub = _player.stream.log.listen(_handlePlayerLog);

    // El watchdog conserva su frecuencia porque sólo observa estado de
    // reproducción. Las estadísticas técnicas ya no se consultan en segundo
    // plano: se leen únicamente cuando el usuario abre los paneles de info.
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
        // keep-open=yes convierte un EOF en una pausa del Player. En IPTV
        // algunos servidores terminan la conexión periódicamente aunque la
        // señal continúe. No queremos que mpv transforme ese EOF en Pause.
        await platform.setProperty('keep-open', 'no');

        // Dejamos activo el buffering nativo de mpv. Si la red se queda sin
        // datos, pausa internamente, rellena el cache y continúa sin destruir
        // la sesión HTTP/HLS; esto es mucho más tolerante a conexiones débiles.
        await platform.setProperty('cache-pause', 'yes');
        await platform.setProperty('cache-pause-initial', 'no');
        await platform.setProperty('demuxer-thread', 'yes');

        // En TV en vivo no necesitamos conservar paquetes ya reproducidos.
        // Un back-buffer grande puede volver a mostrar escenas viejas después
        // de un corte/reapertura. Películas y series mantienen su cache normal.
        if (widget.isLiveContent) {
          await platform.setProperty('demuxer-max-back-bytes', '0');
          await platform.setProperty('cache-on-disk', 'no');
        }
      }
    } catch (_) {
      // Optimización nativa opcional.
    }
  }

  Future<bool> _prepareChannelTuning(
    int session, {
    required bool forceNormalProbe,
  }) async {
    final channel = widget.playlist[_currentIndex];
    final tuning = await _metrics.tuningFor(channel.url, widget.settings);
    if (!mounted || session != _sessionId) return false;

    final tunedSettings = tuning.settings;
    final applyLiveStabilityFloor =
        widget.isLiveContent && widget.settings.profile == BufferProfile.auto;
    _effectiveSettings = applyLiveStabilityFloor
        ? tunedSettings.copyWith(
            bufferMb: tunedSettings.bufferMb < 16 ? 16 : tunedSettings.bufferMb,
            readaheadSeconds: tunedSettings.readaheadSeconds < 2.5
                ? 2.5
                : tunedSettings.readaheadSeconds,
            recoveryBufferSeconds: tunedSettings.recoveryBufferSeconds < 1.5
                ? 1.5
                : tunedSettings.recoveryBufferSeconds,
            connectTimeoutSeconds: tunedSettings.connectTimeoutSeconds < 8
                ? 8
                : tunedSettings.connectTimeoutSeconds,
            stallThresholdSeconds: tunedSettings.stallThresholdSeconds < 12
                ? 12
                : tunedSettings.stallThresholdSeconds,
          )
        : tunedSettings;
    _tuningLabel = applyLiveStabilityFloor
        ? '${tuning.label} · Live estable'
        : tuning.label;
    _useFastProbe = tuning.useFastProbe;
    final modeNeedsNormalProbe =
        _compatibilityMode == ServerCompatibilityMode.compatible ||
            _compatibilityMode == ServerCompatibilityMode.advanced;
    _currentOpenUsesFastProbe = !widget.isLiveContent &&
        _useFastProbe &&
        !forceNormalProbe &&
        !_compatibilityPrefersNormalProbe &&
        !modeNeedsNormalProbe;

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
        await platform.setProperty(
          'network-timeout',
          _effectiveSettings.connectTimeoutSeconds.toString(),
        );
        await platform.setProperty(
          'demuxer-lavf-probesize',
          _currentOpenUsesFastProbe ? _fastProbeSize : _normalProbeSize,
        );
        await platform.setProperty(
          'demuxer-lavf-probescore',
          _currentOpenUsesFastProbe ? '15' : '26',
        );


        // Compatibilidad por servidor. Limpiamos SIEMPRE las opciones de la
        // apertura anterior para que un proveedor no herede ajustes de otro.
        await platform.setProperty('demuxer-lavf-propagate-opts', 'yes');
        await platform.setProperty('demuxer-lavf-o', '');
        await platform.setProperty('stream-lavf-o', '');
        final disableMime =
            _compatibilityMode == ServerCompatibilityMode.compatible ||
                _compatibilityMode == ServerCompatibilityMode.advanced;
        await platform.setProperty(
          'demuxer-lavf-allow-mimetype',
          disableMime ? 'no' : 'yes',
        );

        final effectiveUrl = _playbackUrlForMode(channel.url);
        final isLiveHls = widget.isLiveContent && _looksLikeHls(effectiveUrl);

        // HotPlayer Mac contiene seg_max_retry=5: dejamos que FFmpeg
        // recupere un segmento HLS antes de reconstruir toda la reproducción.
        // En modos de compatibilidad también aceptamos extensiones HLS atípicas,
        // algo frecuente en paneles/proxies IPTV. Direct conserva el filtro
        // estándar de FFmpeg.
        if (isLiveHls) {
          final relaxedHlsExtensions =
              _compatibilityMode != ServerCompatibilityMode.direct;
          final hlsOptions = <String>[
            'seg_max_retry=$_hlsSegmentRetryCount',
            if (relaxedHlsExtensions) 'allowed_extensions=ALL',
          ].join(',');
          await platform.setProperty('demuxer-lavf-o', hlsOptions);
        }

        // V3.8 vuelve a una base más cercana a HotPlayer: no inyectamos una
        // batería global de reconnect_* en stream-lavf-o. Esos flags no aparecen
        // en el binario analizado y en ciertos servidores cambian el tratamiento
        // de EOF/HTTP de forma contraproducente. El fallback de TV FULL queda a
        // nivel de sesión sólo si mpv realmente no logra recuperar.
      }
    } catch (_) {
      // Estas propiedades son una optimización, no un requisito.
    }

    return mounted && session == _sessionId;
  }

  void _checkStall() {
    if (!mounted || _opening || _reconnecting || _errorMessage != null) {
      return;
    }
    if (!_isPlaying || !_hasEverPlayed) return;

    final silentFor = DateTime.now().difference(_lastProgressAt);

    // HotPlayer deja que FFmpeg intente recuperar segmentos antes de
    // reconstruir la reproducción. En live damos ese mismo margen: un microcorte
    // no debe convertirse en stop/open del Media.
    final liveGrace = widget.isLiveContent
        ? Duration(
            seconds: _stallThreshold.inSeconds < 30
                ? 30
                : _stallThreshold.inSeconds,
          )
        : _stallThreshold;
    final bufferingGrace = widget.isLiveContent
        ? Duration(
            seconds: _stallThreshold.inSeconds + 20 < 45
                ? 45
                : _stallThreshold.inSeconds + 20,
          )
        : Duration(
            seconds: _stallThreshold.inSeconds < 8
                ? 12
                : _stallThreshold.inSeconds + 4,
          );
    final effectiveStallThreshold =
        _isBuffering ? bufferingGrace : liveGrace;

    if (silentFor > effectiveStallThreshold) {
      _scheduleConnectionDiagnosis(severe: true);
      final url = widget.playlist[_currentIndex].url;
      unawaited(_metrics.recordStall(url));
      _handleFailure('El stream dejó de responder', silent: true);
    }
  }

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


  bool _looksLikeHls(String url) {
    final value = url.toLowerCase();
    final format = _containerFormat?.toLowerCase() ?? '';
    return value.contains('.m3u8') ||
        format.contains('hls') ||
        format.contains('applehttp');
  }

  bool _looksLikeXtreamLiveTs(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path.contains('/live/') && path.endsWith('.ts');
  }

  String _playbackUrlForMode(String originalUrl) {
    if (_compatibilityMode != ServerCompatibilityMode.xtreamHls ||
        !_looksLikeXtreamLiveTs(originalUrl)) {
      return originalUrl;
    }

    final uri = Uri.tryParse(originalUrl);
    if (uri == null) return originalUrl;
    final path = uri.path;
    final lower = path.toLowerCase();
    if (!lower.endsWith('.ts')) return originalUrl;
    final hlsPath = '${path.substring(0, path.length - 3)}.m3u8';
    return uri.replace(path: hlsPath).toString();
  }

  Future<void> _refreshContainerFormat() async {
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

  Future<void> _refreshRuntimeStats() async {
    if (_runtimeStatsBusy ||
        !mounted ||
        !_hasEverPlayed ||
        _opening ||
        _reconnecting) {
      return;
    }

    final platform = _player.platform;
    if (platform is! NativePlayer) return;

    _runtimeStatsBusy = true;
    try {
      final fps = await _readDoubleProperty(platform, 'estimated-vf-fps');
      final videoBitrate = await _readDoubleProperty(platform, 'video-bitrate');
      final audioBitrate = await _readDoubleProperty(platform, 'audio-bitrate');
      final cacheSeconds =
          await _readDoubleProperty(platform, 'demuxer-cache-duration');
      final cacheSpeed = await _readDoubleProperty(platform, 'cache-speed');
      final coreIdle = await _readStringProperty(platform, 'core-idle');
      final pausedForCache =
          await _readStringProperty(platform, 'paused-for-cache');
      final eofReached = await _readStringProperty(platform, 'eof-reached');
      final format = await _readStringProperty(platform, 'file-format');

      if (!mounted) return;

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
    } finally {
      _runtimeStatsBusy = false;
    }
  }

  Future<double?> _readDoubleProperty(
    NativePlayer platform,
    String property,
  ) async {
    try {
      final value = await platform.getProperty(property);
      return double.tryParse(value.trim());
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readStringProperty(
    NativePlayer platform,
    String property,
  ) async {
    try {
      return (await platform.getProperty(property)).trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleCompletedStream() async {
    // Películas y series tienen un final real. No debemos interpretarlo como
    // una caída de señal y volver a abrir el archivo desde el principio.
    if (!widget.isLiveContent) {
      _connectTimeoutTimer?.cancel();
      _retryTimer?.cancel();
      if (mounted) {
        setState(() {
          _isBuffering = false;
          _reconnecting = false;
          _engineDiagnostic = 'Reproducción finalizada correctamente';
        });
      }
      return;
    }

    final channel = widget.playlist[_currentIndex];
    final uri = Uri.tryParse(channel.url);
    final isHttpLive =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    if (_hasEverPlayed && isHttpLive) {
      _seamlessEofRecoveries++;
      _retryTimer?.cancel();

      // Si el servidor necesitó MIME relajado para abrir, conservamos ese
      // comportamiento durante la recuperación. Advanced = Compatible +
      // reconexión, evitando que un EOF haga volver a un modo incompatible.
      final recoveryMode =
          _compatibilityMode == ServerCompatibilityMode.nativeHttp ||
                  _compatibilityMode == ServerCompatibilityMode.xtreamHls
              ? _compatibilityMode
              : _compatibilityMode == ServerCompatibilityMode.compatible ||
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

      scheduleMicrotask(() {
        if (!mounted || _opening || _reconnecting) return;
        unawaited(
          _playCurrent(
            isRetry: true,
            forceNormalProbe: true,
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

  bool _promoteRuntimeRecoveryMode(String reason) {
    if (!_hasEverPlayed) return false;

    final previous = _compatibilityMode;
    final ServerCompatibilityMode? target = switch (previous) {
      ServerCompatibilityMode.direct => ServerCompatibilityMode.liveRecovery,
      ServerCompatibilityMode.nativeHttp => null,
      ServerCompatibilityMode.compatible => ServerCompatibilityMode.advanced,
      ServerCompatibilityMode.liveRecovery => ServerCompatibilityMode.advanced,
      ServerCompatibilityMode.advanced => null,
      ServerCompatibilityMode.xtreamHls => null,
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

    final resumePosition =
        widget.isLiveContent ? null : _lastKnownPosition;
    scheduleMicrotask(() {
      if (!mounted) return;
      unawaited(
        _playCurrent(
          isRetry: true,
          forceNormalProbe: true,
          resumePosition: resumePosition,
        ),
      );
    });
    return true;
  }

  void _handlePlayerLog(PlayerLog log) {
    if (!mounted) return;
    final text = log.text.toLowerCase();
    String? diagnostic;

    if (text.contains('429') || text.contains('too many requests')) {
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
    } else if (text.contains('certificate') ||
        text.contains('tls') ||
        text.contains('ssl')) {
      diagnostic = 'Problema TLS/SSL durante la conexión segura';
    } else if (text.contains('invalid data') ||
        text.contains('could not find codec parameters')) {
      diagnostic = 'El servidor respondió, pero el formato no pudo detectarse';
    } else if (text.contains('too many redirects') ||
        text.contains('redirect loop')) {
      diagnostic = 'El servidor entró en un bucle de redirecciones HTTP';
    } else if (RegExp(r'\b5\d\d\b').hasMatch(text) &&
        text.contains('http')) {
      diagnostic = 'El servidor respondió con un error HTTP 5xx temporal';
    } else if (text.contains('mime')) {
      diagnostic =
          'El MIME del servidor puede ser incompatible; disponible fallback Compatible';
    } else if (text.contains('eof')) {
      diagnostic = 'EOF detectado en la señal en vivo';
    } else if ((log.level == 'error' || log.level == 'fatal' || log.level == 'warn') &&
        (text.contains('http') || text.contains('network') || text.contains('failed'))) {
      diagnostic = 'mpv/FFmpeg reportó un fallo de red durante la apertura';
    }

    if (diagnostic != null && _hasEverPlayed && _looksLikeConnectionLog(text)) {
      _providerIssueHint = _looksProviderSpecific(text);
      _lastConnectionDetail = diagnostic;
      _scheduleConnectionDiagnosis(
        severe: log.level == 'error' || log.level == 'fatal',
      );
    }

    if (diagnostic != null && diagnostic != _engineDiagnostic) {
      setState(() => _engineDiagnostic = diagnostic!);
    }
  }

  void _scheduleTransientLiveFailure(String message) {
    _transientLiveFailureTimer?.cancel();
    final session = _sessionId;
    final progressAtError = _lastProgressAt;

    if (mounted) {
      setState(() {
        _engineDiagnostic =
            'Corte transitorio: FFmpeg está intentando recuperar la señal';
      });
    }

    _transientLiveFailureTimer = Timer(_liveTransientErrorGrace, () {
      _transientLiveFailureTimer = null;
      if (!mounted ||
          session != _sessionId ||
          _opening ||
          _reconnecting ||
          _isBuffering ||
          _errorMessage != null) {
        return;
      }

      // Si hubo progreso desde el error, la recuperación nativa funcionó.
      if (_lastProgressAt.isAfter(progressAtError)) return;
      _handleFailure(message, silent: true);
    });
  }

  void _handleFailure(String message, {bool silent = false}) {
    if (!mounted || _opening) return;

    _connectTimeoutTimer?.cancel();
    _retryTimer?.cancel();
    _transientLiveFailureTimer?.cancel();
    _transientLiveFailureTimer = null;

    final failedSession = _sessionId;
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

    unawaited(_metrics.recordFailure(url));

    if (_retryCount < _maxAutoRetries) {
      final seconds = 1 << _retryCount;
      _retryCount++;

      setState(() {
        _reconnecting = true;
        _errorMessage = null;
      });

      final resumePosition =
          widget.isLiveContent ? null : _lastKnownPosition;
      _retryTimer = Timer(Duration(seconds: seconds), () {
        if (!mounted || failedSession != _sessionId) return;
        unawaited(
          _playCurrent(
            isRetry: true,
            forceNormalProbe: true,
            resumePosition: resumePosition,
          ),
        );
      });
    } else {
      _zapStopwatch?.stop();
      _zapSession = null;
      setState(() {
        _reconnecting = false;
        _errorMessage = silent
            ? 'Este canal no responde tras varios intentos.\nProbá con otro canal o volvé a intentar más tarde.'
            : message;
      });
    }
  }

  void _startNormalProbeFallback(int session) {
    if (!mounted || session != _sessionId || _normalProbeFallbackUsed) return;

    _normalProbeFallbackUsed = true;
    final url = widget.playlist[_currentIndex].url;
    _compatibilityPrefersNormalProbe = true;
    unawaited(_metrics.recordFastProbeFallback(url));
    unawaited(_compatibility.recordNormalProbeFallback(url));

    setState(() {
      _reconnecting = true;
      _errorMessage = null;
    });

    scheduleMicrotask(() {
      if (!mounted || session != _sessionId) return;
      unawaited(_playCurrent(isRetry: true, forceNormalProbe: true));
    });
  }

  Future<void> _playCurrent({
    bool isRetry = false,
    bool forceNormalProbe = false,
    bool skipStop = false,
    bool isZap = false,
    Duration? resumePosition,
  }) async {
    final session = ++_sessionId;
    _opening = true;
    _acceptPlaybackEvents = false;
    _connectionProbeTimer?.cancel();
    _connectionRecoveryTimer?.cancel();

    if (isZap) {
      _zapStopwatch = Stopwatch()..start();
      _zapSession = session;
    } else if (isRetry && (_zapStopwatch?.isRunning ?? false)) {
      _zapSession = session;
    }
    _connectTimeoutTimer?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    _transientLiveFailureTimer?.cancel();
    _transientLiveFailureTimer = null;

    if (!isRetry) {
      _retryCount = 0;
      _normalProbeFallbackUsed = false;
      _providerIssueHint = false;
      _lastConnectionDetail = null;
      _recentBufferingEvents = 0;
      _bufferingWindowStartedAt = DateTime.now();
      _connectionHealth.value = _ConnectionHealthSnapshot.stable;
      _resetStreamInfo();

      final channelUrl = widget.playlist[_currentIndex].url;
      final profile = await _compatibility.profileForUrl(channelUrl);
      if (!mounted || session != _sessionId) return;
      final learnedPlan = _compatibility.planFor(profile.preferredMode);
      _compatibilityPlan = _looksLikeXtreamLiveTs(channelUrl)
          ? learnedPlan
          : learnedPlan
              .where((mode) => mode != ServerCompatibilityMode.xtreamHls)
              .toList(growable: false);
      _compatibilityIndex = 0;
      _compatibilityFallbacks = 0;
      _runtimeRecoveryPromotions = 0;
      _compatibilityPrefersNormalProbe = profile.preferNormalProbe;
      _compatibilityMode = _compatibilityPlan.first;
      _compatibilityUrl = channelUrl;
      _engineDiagnostic =
          'Apertura ${_compatibilityMode.label} para este servidor'
          '${_compatibilityPrefersNormalProbe ? ' · probe normal aprendido' : ''}';
    }

    _hasEverPlayed = false;
    _startupStopwatch = Stopwatch()..start();
    _startupSession = session;
    _startupUrl = widget.playlist[_currentIndex].url;

    if (mounted) {
      setState(() {
        _errorMessage = null;
        _isBuffering = isZap ? false : true;
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
      // En zapping live reemplazamos el Media directamente. El canal anterior
      // puede seguir visible mientras preparamos headers/perfil; evitamos el
      // hueco artificial de stop() -> open(). En retries/VOD conservamos stop().
      if (!skipStop && !isZap) {
        await _player.stop();
        if (!mounted || session != _sessionId) return;
      }

      final channel = widget.playlist[_currentIndex];
      final fallbackUserAgent =
          _compatibilityMode == ServerCompatibilityMode.compatible ||
                  _compatibilityMode == ServerCompatibilityMode.advanced
              ? _legacyVlcUserAgent
              : _defaultUserAgent;
      final nativeHttp =
          _compatibilityMode == ServerCompatibilityMode.nativeHttp ||
              _compatibilityMode == ServerCompatibilityMode.xtreamHls;
      final headers = channel.resolvedHttpHeaders(
        fallbackUserAgent,
        includeDefaultUserAgent: !nativeHttp,
      );
      final playbackUrl = _playbackUrlForMode(channel.url);
      final media = headers.isEmpty
          ? Media(playbackUrl)
          : Media(playbackUrl, httpHeaders: headers);

      final openFuture = _player.open(media);
      _acceptPlaybackEvents = true;
      await openFuture.timeout(_connectTimeout);
      if (!mounted || session != _sessionId) return;

      if (!widget.isLiveContent &&
          resumePosition != null &&
          resumePosition > Duration.zero) {
        try {
          await _player.seek(resumePosition);
        } catch (_) {
          // Si el servidor VOD no admite seek, seguimos desde donde permita.
        }
      }

      _opening = false;
      _connectTimeoutTimer = Timer(_connectTimeout, () {
        if (!mounted || session != _sessionId || _hasEverPlayed) return;
        if (_currentOpenUsesFastProbe && !_normalProbeFallbackUsed) {
          _startNormalProbeFallback(session);
          return;
        }
        _handleFailure('El canal tardó demasiado en responder', silent: true);
      });
    } on TimeoutException {
      if (!mounted || session != _sessionId) return;
      _opening = false;
      _acceptPlaybackEvents = true;
      unawaited(_player.stop());
      if (_currentOpenUsesFastProbe && !_normalProbeFallbackUsed) {
        _startNormalProbeFallback(session);
        return;
      }
      _handleFailure('El canal tardó demasiado en abrir', silent: true);
    } catch (e) {
      if (!mounted || session != _sessionId) return;
      _opening = false;
      _acceptPlaybackEvents = true;
      if (_currentOpenUsesFastProbe && !_normalProbeFallbackUsed) {
        _startNormalProbeFallback(session);
        return;
      }
      _handleFailure('No se pudo abrir el canal: $e');
    }
  }

  void _resetStreamInfo() {
    _videoWidth = null;
    _videoHeight = null;
    _videoFps = null;
    _videoBitrate = null;
    _audioBitrate = null;
    _videoCodec = null;
    _audioCodec = null;
    _pixelFormat = null;
    _containerFormat = null;
    _runtimeFormatLoaded = false;
    _audioChannels = null;
    _audioSampleRate = null;
    _lastCacheSeconds = null;
    _networkReadBytesPerSecond = null;
    _coreIdle = false;
    _pausedForCache = false;
    _eofReached = false;
    _seamlessEofRecoveries = 0;
    _runtimeRecoveryPromotions = 0;
  }

  void _switchToChannel(int index) {
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

  String get _resolutionText {
    if (_videoWidth == null || _videoHeight == null) return 'Detectando…';
    return '${_videoWidth}×$_videoHeight';
  }

  String get _qualityLabel {
    final w = _videoWidth ?? 0;
    final h = _videoHeight ?? 0;
    if (w >= 7680 || h >= 4320) return '8K';
    if (w >= 3840 || h >= 2160) return '4K / UHD';
    if (w >= 2560 || h >= 1440) return 'QHD';
    if (w >= 1920 || h >= 1080) return 'Full HD';
    if (w >= 1280 || h >= 720) return 'HD';
    if (w > 0 && h > 0) return 'SD';
    return 'Desconocida';
  }

  String get _compactResolutionLabel {
    if (_videoWidth == null || _videoHeight == null) return '';
    final fps = _videoFps;
    if (fps == null || fps <= 0) return _resolutionText;
    return '$_resolutionText · ${fps.toStringAsFixed(fps >= 10 ? 0 : 1)} fps';
  }

  String? _advertisedQuality(String name) {
    final value = name.toUpperCase();
    if (RegExp(r'\b(8K|4320P?)\b').hasMatch(value)) return '8K';
    if (RegExp(r'\b(4K|UHD|2160P?)\b').hasMatch(value)) return '4K / UHD';
    if (RegExp(r'\b(FHD|FULL[ -]?HD|1080P?)\b').hasMatch(value)) {
      return 'Full HD';
    }
    if (RegExp(r'\b(HD|720P?)\b').hasMatch(value)) return 'HD';
    if (RegExp(r'\bSD\b').hasMatch(value)) return 'SD';
    return null;
  }

  int _qualityRank(String quality) {
    return switch (quality) {
      '8K' => 5,
      '4K / UHD' => 4,
      'QHD' => 3,
      'Full HD' => 2,
      'HD' => 1,
      'SD' => 0,
      _ => -1,
    };
  }

  String _formatBitrate(double? bitsPerSecond) {
    if (bitsPerSecond == null || bitsPerSecond <= 0) return 'No disponible';
    if (bitsPerSecond >= 1000000) {
      return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbps';
    }
    return '${(bitsPerSecond / 1000).toStringAsFixed(0)} kbps';
  }

  String get _networkSpeedText {
    final bytes = _networkReadBytesPerSecond;
    if (bytes == null || bytes <= 0) return 'No disponible';
    final mbps = bytes * 8 / 1000000;
    return '${mbps.toStringAsFixed(2)} Mbps';
  }

  String get _networkHeadroomText {
    final bytes = _networkReadBytesPerSecond;
    final mediaBits = (_videoBitrate ?? 0) + (_audioBitrate ?? 0);
    if (bytes == null || bytes <= 0 || mediaBits <= 0) return 'No disponible';
    final ratio = (bytes * 8) / mediaBits;
    return '${ratio.toStringAsFixed(2)}× del bitrate';
  }

  String get _protocolText {
    final uri = Uri.tryParse(widget.playlist[_currentIndex].url);
    final scheme = uri?.scheme.toUpperCase();
    if (_containerFormat != null && _containerFormat!.isNotEmpty) {
      return '${scheme == null || scheme.isEmpty ? 'STREAM' : scheme} · $_containerFormat';
    }
    return scheme == null || scheme.isEmpty ? 'Desconocido' : scheme;
  }

  Future<void> _showStreamInfo() async {
    await _refreshRuntimeStats();
    if (!mounted) return;

    final channel = widget.playlist[_currentIndex];
    final advertised = _advertisedQuality(channel.name);
    final actual = _qualityLabel;
    final belowAdvertised = advertised != null &&
        _qualityRank(actual) >= 0 &&
        _qualityRank(actual) < _qualityRank(advertised);

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Información real del stream'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resolución real: $_resolutionText'),
              Text('Calidad detectada: $actual'),
              if (advertised != null) Text('Calidad anunciada: $advertised'),
              if (belowAdvertised)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '⚠ La señal recibida está por debajo de la calidad anunciada en el nombre del canal.',
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'FPS reales: ${_videoFps == null ? 'No disponible' : _videoFps!.toStringAsFixed(2)}',
              ),
              Text('Codec de video: ${_videoCodec ?? 'No disponible'}'),
              Text('Bitrate de video: ${_formatBitrate(_videoBitrate)}'),
              Text('Formato de píxel: ${_pixelFormat ?? 'No disponible'}'),
              const SizedBox(height: 10),
              Text('Codec de audio: ${_audioCodec ?? 'No disponible'}'),
              Text('Bitrate de audio: ${_formatBitrate(_audioBitrate)}'),
              Text('Canales de audio: ${_audioChannels ?? 'No disponible'}'),
              Text(
                'Muestreo de audio: ${_audioSampleRate == null ? 'No disponible' : '${_audioSampleRate} Hz'}',
              ),
              const SizedBox(height: 10),
              Text('Transporte / contenedor: $_protocolText'),
              Text(
                'Buffer en caché: ${_lastCacheSeconds == null ? 'No disponible' : '${_lastCacheSeconds!.toStringAsFixed(1)} s'}',
              ),
              Text('Buffer configurado: ${_effectiveSettings.bufferMb} MB'),
              Text(
                'Lectura anticipada configurada: ${_effectiveSettings.readaheadSeconds.toStringAsFixed(1)} s',
              ),
              Text('Velocidad de lectura de red: $_networkSpeedText'),
              Text('Margen de red: $_networkHeadroomText'),
              Text('Núcleo esperando datos: ${_coreIdle ? 'sí' : 'no'}'),
              Text('Pausado por caché (mpv): ${_pausedForCache ? 'sí' : 'no'}'),
              Text('EOF detectado por mpv: ${_eofReached ? 'sí' : 'no'}'),
              Text('Modo de compatibilidad: ${_compatibilityMode.label}'),
              Text('Fallbacks de compatibilidad: $_compatibilityFallbacks'),
              Text(
                'Probe aprendido: ${_compatibilityPrefersNormalProbe ? 'normal' : 'adaptativo'}',
              ),
              Text('Promociones de recuperación: $_runtimeRecoveryPromotions'),
              Text(
                'Headers enviados: ${channel.resolvedHttpHeaders(_defaultUserAgent).keys.join(', ')}',
              ),
              Text('Diagnóstico de red: $_engineDiagnostic'),
              Text('Recuperaciones transparentes de EOF: $_seamlessEofRecoveries'),
            ],
          ),
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

  Future<void> _showPerformanceInfo() async {
    await _refreshRuntimeStats();
    if (!mounted) return;

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
    final averageZap = stats.averageZapMs;

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
            Text('Buffer configurado: ${_effectiveSettings.bufferMb} MB'),
            Text('Lectura de red: $_networkSpeedText'),
            Text('Margen red/bitrate: $_networkHeadroomText'),
            Text(
              'Lectura anticipada: ${_effectiveSettings.readaheadSeconds.toStringAsFixed(1)} s',
            ),
            Text(
              'Margen de recuperación: ${_effectiveSettings.recoveryBufferSeconds.toStringAsFixed(1)} s',
            ),
            Text(
              'Arranque actual: ${_lastStartupMs == null ? 'midiendo…' : '$_lastStartupMs ms'}',
            ),
            Text(
              'Promedio servidor: ${average == null ? 'sin muestras' : '${average.round()} ms'}',
            ),
            Text(
              'Último zap: ${_lastZapMs == null ? 'sin medir' : '$_lastZapMs ms'}',
            ),
            Text(
              'Promedio de zap: ${averageZap == null ? 'sin muestras' : '${averageZap.round()} ms'}',
            ),
            Text('Muestras: ${stats.startupCount}'),
            Text('Fallos: ${stats.failures} · Cortes: ${stats.stalls}'),
            Text('Fast Probe: ${_currentOpenUsesFastProbe ? 'activo' : 'normal'}'),
            if (stats.fastProbeFallbacks > 0)
              Text('Fallbacks de detección: ${stats.fastProbeFallbacks}'),
            Text('Resolución actual: $_resolutionText'),
            Text('Modo servidor: ${_compatibilityMode.label}'),
            Text('Fallbacks compatibilidad: $_compatibilityFallbacks'),
            Text(
              'Probe aprendido: ${_compatibilityPrefersNormalProbe ? 'normal' : 'adaptativo'}',
            ),
            Text('Promociones de recuperación: $_runtimeRecoveryPromotions'),
            Text('Pausa de caché mpv: ${_pausedForCache ? 'sí' : 'no'}'),
            Text('EOF detectado: ${_eofReached ? 'sí' : 'no'}'),
            Text('Recuperaciones EOF: $_seamlessEofRecoveries'),
            Text('Diagnóstico: $_engineDiagnostic'),
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
    _retryTimer?.cancel();
    _transientLiveFailureTimer?.cancel();
    _connectionProbeTimer?.cancel();
    _connectionRecoveryTimer?.cancel();
    _connectionHealth.dispose();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _videoParamsSub?.cancel();
    _trackSub?.cancel();
    _audioBitrateSub?.cancel();
    _logSub?.cancel();
    unawaited(_player.dispose());
    ArtworkCacheService.instance.resumeBrowsing();
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
      body: Stack(
        children: [
          Positioned.fill(
            child: LiveVideoView(
              key: ValueKey(channel.uniqueKey),
              player: _player,
              controller: _controller,
              canPrevious: _currentIndex > 0,
              canNext: _currentIndex < widget.playlist.length - 1,
              onPrevious: _previous,
              onNext: _next,
              isLiveContent: widget.isLiveContent,
              title: channel.name,
              subtitle: channel.group,
              logoUrl: channel.logoUrl,
              channelNumber: _currentIndex + 1,
              resolution:
                  _videoWidth == null || _videoHeight == null ? '' : _resolutionText,
              performanceLabel: _lastZapMs != null
                  ? 'Zap $_lastZapMs ms'
                  : (_lastStartupMs == null ? null : '$_lastStartupMs ms'),
              onBack: () => Navigator.of(context).maybePop(),
              onShowChannelList: () =>
                  setState(() => _showChannelList = !_showChannelList),
              onShowStreamInfo: _showStreamInfo,
              onShowPerformance:
                  _lastStartupMs == null ? null : _showPerformanceInfo,
            ),
          ),
          Positioned(
            top: 18,
            right: 18,
            child: SafeArea(
              child: _buildConnectionHealthBadge(),
            ),
          ),
          if ((_isBuffering || _reconnecting) && _errorMessage == null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xC914202D),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _normalProbeFallbackUsed && _retryCount == 0
                              ? 'Probando modo compatible…'
                              : _reconnecting
                                  ? 'Reconectando (intento $_retryCount de $_maxAutoRetries)…'
                                  : _hasEverPlayed
                                      ? 'Recibiendo datos…'
                                      : 'Cargando…',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_errorMessage != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black87,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111B26),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 48,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: () => unawaited(_playCurrent()),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Reintentar'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => _showChannelList = true),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.view_list_rounded),
                              label: const Text('Ver otros canales'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: _showChannelList ? 0 : -370,
            width: 370,
            child: Material(
              elevation: 18,
              color: const Color(0xF2071728),
              child: SafeArea(
                left: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.live_tv_rounded,
                            color: Color(0xFF58A6FF),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Canales',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () =>
                                setState(() => _showChannelList = false),
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Buscar canal…',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Colors.white54,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF1677FF),
                            ),
                          ),
                          isDense: true,
                        ),
                        onChanged: (value) =>
                            setState(() => _channelListQuery = value),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filteredChannels.length,
                        itemBuilder: (context, index) {
                          final c = filteredChannels[index];
                          final realIndex = widget.playlist.indexOf(c);
                          final isCurrent = realIndex == _currentIndex;
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFF1677FF)
                                      .withValues(alpha: 0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: isCurrent
                                  ? Border.all(
                                      color: const Color(0xFF1677FF)
                                          .withValues(alpha: 0.35),
                                    )
                                  : null,
                            ),
                            child: ChannelTile(
                              channel: c,
                              isFavorite: false,
                              onFavoriteToggle: () {},
                              onTap: () => _switchToChannel(realIndex),
                              allowNetworkArtwork: false,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
