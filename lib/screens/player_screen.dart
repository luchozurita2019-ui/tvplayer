import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/channel.dart';
import '../models/playback_settings.dart';
import '../services/playback_metrics_service.dart';
import '../widgets/channel_tile.dart';

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
  static const Duration _watchdogInterval = Duration(seconds: 2);
  static const Duration _runtimeStatsInterval = Duration(seconds: 1);
  static const String _fastProbeSize = '131072';
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
  bool _softRecovering = false;
  bool _runtimeStatsBusy = false;

  String? _errorMessage;
  String _channelListQuery = '';
  String _tuningLabel = 'Equilibrado';
  int _retryCount = 0;
  int _sessionId = 0;
  int _startupSession = 0;
  int? _lastStartupMs;
  String? _startupUrl;

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
  int _softRecoveryCount = 0;
  int _networkRecoveryCount = 0;

  Timer? _watchdogTimer;
  Timer? _runtimeStatsTimer;
  Timer? _connectTimeoutTimer;
  Timer? _retryTimer;
  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();
  DateTime? _bufferingStartedAt;
  Stopwatch? _startupStopwatch;

  StreamSubscription? _bufferingSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _videoParamsSub;
  StreamSubscription? _trackSub;
  StreamSubscription? _audioBitrateSub;

  int get _maxAutoRetries => _effectiveSettings.maxRetries;
  Duration get _stallThreshold =>
      Duration(seconds: _effectiveSettings.stallThresholdSeconds);
  Duration get _connectTimeout =>
      Duration(seconds: _effectiveSettings.connectTimeoutSeconds);

  Duration get _underrunGrace {
    // Un corte pequeño debe tener margen para recuperarse sin reconstruir
    // el canal, pero no esperamos varios segundos con la imagen congelada.
    final seconds = math.min(
      2.5,
      math.max(1.25, _effectiveSettings.recoveryBufferSeconds + 0.5),
    );
    return Duration(milliseconds: (seconds * 1000).round());
  }

  int get _forwardBufferMb {
    // El modo automático puede conservar el zapping rápido sin limitar la
    // reserva de red a solo 8 MB. El tamaño máximo no obliga a esperar antes
    // de mostrar imagen: únicamente permite acumular más colchón en segundo
    // plano cuando el servidor puede entregar datos por delante del vivo.
    if (_effectiveSettings.profile == BufferProfile.auto) {
      return math.max(16, _effectiveSettings.bufferMb);
    }
    return _effectiveSettings.bufferMb;
  }

  double get _targetCacheSeconds {
    final floor = switch (_effectiveSettings.profile) {
      BufferProfile.ultraFast => 5.0,
      BufferProfile.balanced => 8.0,
      BufferProfile.stable => 15.0,
      BufferProfile.auto => _effectiveSettings.bufferMb >= 32 ? 12.0 : 8.0,
      BufferProfile.custom => math.max(4.0, _effectiveSettings.readaheadSeconds),
    };

    return math.max(
      floor,
      math.max(
        _effectiveSettings.readaheadSeconds * 2.0,
        _effectiveSettings.recoveryBufferSeconds + 3.0,
      ),
    );
  }

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
          !_softRecovering &&
          _errorMessage == null) {
        _handleFailure('El stream terminó inesperadamente', silent: true);
      }
    });

    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!mounted) return;

      final now = DateTime.now();
      if (buffering) {
        if (_hasEverPlayed) {
          _bufferingStartedAt ??= now;
        }
      } else {
        _bufferingStartedAt = null;
        _connectTimeoutTimer?.cancel();
        _retryTimer?.cancel();
        _retryTimer = null;
        _hasEverPlayed = true;
        _retryCount = 0;
        _lastProgressAt = now;
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
        if (mounted) setState(() => _lastStartupMs = elapsed);
        if (url != null) {
          unawaited(_metrics.recordStartup(url, elapsed));
        }
      }
    });

    _errorSub = _player.stream.error.listen((error) {
      if (_opening || _softRecovering) return;
      _handleFailure('Error de reproducción: $error');
    });

    _playingSub = _player.stream.playing.listen((playing) {
      _isPlaying = playing;
      if (playing) _lastProgressAt = DateTime.now();
    });

    _positionSub = _player.stream.position.listen((position) {
      if (position != _lastKnownPosition) {
        _lastKnownPosition = position;
        _lastProgressAt = DateTime.now();
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

    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) => _checkStall());
    _runtimeStatsTimer = Timer.periodic(
      _runtimeStatsInterval,
      (_) => unawaited(_refreshRuntimeStats()),
    );

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
        await platform.setProperty('cache', 'yes');

        // IMPORTANTE PARA IPTV EN VIVO:
        // cache-pause=yes hace que mpv PAUSE automáticamente cuando el
        // buffer llega a cero y vuelva a dar Play al rellenarse. En canales
        // irregulares eso se percibía como pausas periódicas. Dejamos que el
        // stream continúe en estado live y nuestra capa de recuperación solo
        // interviene si el underrun dura de verdad.
        await platform.setProperty('cache-pause', 'no');
        await platform.setProperty('cache-pause-initial', 'no');
        await platform.setProperty('demuxer-thread', 'yes');

        // Mantener la lectura hacia delante de forma continua. Con la
        // histéresis en 0 mpv no llena por bloques y luego deja de leer hasta
        // que la caché cae: intenta aprovechar constantemente el ancho de
        // banda disponible del servidor.
        await platform.setProperty('demuxer-hysteresis-secs', '0');
        await platform.setProperty('demuxer-hysteresis-bytes', '0');

        // IPTV no necesita un back-buffer grande. Reservamos la memoria para
        // datos futuros y aumentamos moderadamente el buffer de I/O entre la
        // red y el demuxer (128 KiB es el valor habitual de mpv).
        await platform.setProperty('demuxer-max-back-bytes', '1MiB');
        await platform.setProperty('demuxer-donate-buffer', 'no');
        await platform.setProperty('stream-buffer-size', '512KiB');
      }
    } catch (_) {
      // Una plataforma sin libmpv puede ignorar estas optimizaciones.
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
        // En streams de red mpv usa cache-secs por encima de
        // demuxer-readahead-secs. Configuramos ambos para que el perfil de
        // buffer realmente se aplique a IPTV y no quede solo como un valor UI.
        await platform.setProperty(
          'cache-secs',
          _targetCacheSeconds.toStringAsFixed(2),
        );
        await platform.setProperty(
          'demuxer-readahead-secs',
          _effectiveSettings.readaheadSeconds.toStringAsFixed(2),
        );
        await platform.setProperty(
          'demuxer-max-bytes',
          '${_forwardBufferMb}MiB',
        );
        await platform.setProperty(
          'demuxer-lavf-probesize',
          _currentOpenUsesFastProbe ? _fastProbeSize : _normalProbeSize,
        );
        await platform.setProperty(
          'demuxer-lavf-probescore',
          _currentOpenUsesFastProbe ? '15' : '26',
        );

        final uri = Uri.tryParse(channel.url);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          // Dejamos que FFmpeg intente mantener/reabrir la conexión HTTP
          // antes de reconstruir por completo el Player. reconnect_at_eof
          // es especialmente útil para streams IPTV/endless cuyos servidores
          // cierran el socket periódicamente.
          await platform.setProperty(
            'demuxer-lavf-o',
            'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,'
                'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'
                'multiple_requests=1,reconnect_delay_max=1,'
                'rw_timeout=3000000',
          );
        } else {
          await platform.setProperty('demuxer-lavf-o', '');
        }
      }
    } catch (_) {
      // Estas propiedades son una optimización, no un requisito.
    }

    return mounted && session == _sessionId;
  }

  void _checkStall() {
    if (!mounted ||
        _opening ||
        _reconnecting ||
        _softRecovering ||
        _errorMessage != null ||
        !_hasEverPlayed) {
      return;
    }

    final now = DateTime.now();

    // Caso 1: underrun real. No reaccionamos al primer evento de buffering;
    // damos unos segundos para que la propia conexión recupere paquetes.
    if (_isBuffering && _bufferingStartedAt != null) {
      final bufferingFor = now.difference(_bufferingStartedAt!);
      if (bufferingFor >= _underrunGrace) {
        final url = widget.playlist[_currentIndex].url;
        unawaited(_metrics.recordStall(url));
        unawaited(_trySoftRecovery());
      }
      return;
    }

    // Caso 2: algunos MPEG-TS no informan buffering correctamente. Solo
    // intervenimos si no hubo progreso durante bastante tiempo Y la caché
    // está efectivamente vacía.
    final silentFor = now.difference(_lastProgressAt);
    final cacheDepleted =
        _lastCacheSeconds != null && _lastCacheSeconds! <= 0.10;

    if (silentFor > _stallThreshold && cacheDepleted) {
      final url = widget.playlist[_currentIndex].url;
      unawaited(_metrics.recordStall(url));
      unawaited(_trySoftRecovery());
    }
  }

  bool _streamLooksRecovered() {
    final recentProgress = DateTime.now().difference(_lastProgressAt) <
        const Duration(milliseconds: 2200);
    return !_isBuffering && (_isPlaying || recentProgress);
  }

  Future<void> _trySoftRecovery() async {
    if (!mounted || _softRecovering || _opening || _reconnecting) return;

    final recoverySession = _sessionId;
    _softRecovering = true;
    if (mounted) setState(() => _errorMessage = null);

    // Etapa 1: FFmpeg ya dispone de reconexión HTTP interna. Damos un
    // margen corto para que la misma conexión vuelva sin vaciar paquetes.
    try {
      await _player.play();
    } catch (_) {}

    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || recoverySession != _sessionId) {
      _softRecovering = false;
      return;
    }

    if (_streamLooksRecovered()) {
      _softRecoveryCount++;
      _bufferingStartedAt = null;
      _lastProgressAt = DateTime.now();
      _softRecovering = false;
      if (mounted) setState(() {});
      return;
    }

    // Si la caché está vacía no hay nada útil que descartar: hacerlo solo
    // alarga el corte. En ese caso pasamos pronto a una nueva conexión.
    final cacheEmpty = _lastCacheSeconds == null || _lastCacheSeconds! <= 0.15;
    if (_isBuffering || cacheEmpty) {
      _networkRecoveryCount++;
      _softRecovering = false;
      if (mounted) setState(() {});
      _handleFailure('La red dejó de entregar datos', silent: true);
      return;
    }

    // Solo para un bloqueo extraño con paquetes todavía en caché usamos
    // drop-buffers como último intento antes de reconstruir la conexión.
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.command(const ['drop-buffers']);
      }
      await _player.play();
    } catch (_) {}

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted || recoverySession != _sessionId) {
      _softRecovering = false;
      return;
    }

    if (_streamLooksRecovered()) {
      _softRecoveryCount++;
      _bufferingStartedAt = null;
      _lastProgressAt = DateTime.now();
      _softRecovering = false;
      if (mounted) setState(() {});
      return;
    }

    _networkRecoveryCount++;
    _softRecovering = false;
    if (mounted) setState(() {});
    _handleFailure('El stream dejó de entregar datos', silent: true);
  }

  Future<void> _refreshRuntimeStats() async {
    if (_runtimeStatsBusy ||
        !mounted ||
        !_hasEverPlayed ||
        _opening ||
        _reconnecting ||
        _softRecovering) {
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
      final format = await _readStringProperty(platform, 'file-format');

      if (!mounted) return;
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
        if (format != null && format.isNotEmpty && format != 'N/A') {
          _containerFormat = format;
        }
      });
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

  void _handleFailure(String message, {bool silent = false}) {
    if (!mounted || _opening || _softRecovering) return;

    _connectTimeoutTimer?.cancel();
    _retryTimer?.cancel();

    final failedSession = _sessionId;
    final url = widget.playlist[_currentIndex].url;
    unawaited(_metrics.recordFailure(url));

    if (_retryCount < _maxAutoRetries) {
      // El primer reintento es casi inmediato. Los siguientes sí usan
      // backoff para no martillar un servidor realmente caído.
      final delay = _retryCount == 0
          ? const Duration(milliseconds: 250)
          : Duration(seconds: 1 << (_retryCount - 1));
      _retryCount++;

      setState(() {
        _reconnecting = true;
        _errorMessage = null;
      });

      _retryTimer = Timer(delay, () {
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

  void _startNormalProbeFallback(int session) {
    if (!mounted || session != _sessionId || _normalProbeFallbackUsed) return;

    _normalProbeFallbackUsed = true;
    final url = widget.playlist[_currentIndex].url;
    unawaited(_metrics.recordFastProbeFallback(url));

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
  }) async {
    final session = ++_sessionId;
    _opening = true;
    _connectTimeoutTimer?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    _bufferingStartedAt = null;

    if (!isRetry) {
      _retryCount = 0;
      _normalProbeFallbackUsed = false;
      _resetStreamInfo();
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
        _softRecovering = false;
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
          _startNormalProbeFallback(session);
          return;
        }
        _handleFailure('El canal tardó demasiado en responder', silent: true);
      });
    } on TimeoutException {
      if (!mounted || session != _sessionId) return;
      _opening = false;
      unawaited(_player.stop());
      if (_currentOpenUsesFastProbe && !_normalProbeFallbackUsed) {
        _startNormalProbeFallback(session);
        return;
      }
      _handleFailure('El canal tardó demasiado en abrir', silent: true);
    } catch (e) {
      if (!mounted || session != _sessionId) return;
      _opening = false;
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
    _audioChannels = null;
    _audioSampleRate = null;
    _lastCacheSeconds = null;
    _networkReadBytesPerSecond = null;
    _coreIdle = false;
    _softRecoveryCount = 0;
    _networkRecoveryCount = 0;
    _bufferingStartedAt = null;
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
              Text('Objetivo de caché: ${_targetCacheSeconds.toStringAsFixed(1)} s'),
              Text('Memoria de caché hacia delante: $_forwardBufferMb MB'),
              Text('Velocidad de lectura de red: $_networkSpeedText'),
              Text('Margen de red: $_networkHeadroomText'),
              Text('Núcleo esperando datos: ${_coreIdle ? 'sí' : 'no'}'),
              const Text('Pausa automática por buffer: desactivada'),
              Text('Recuperaciones suaves: $_softRecoveryCount'),
              Text('Reconexiones por falta de datos: $_networkRecoveryCount'),
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
            Text('Buffer configurado: ${_effectiveSettings.bufferMb} MB'),
            Text('Buffer efectivo de red: $_forwardBufferMb MB'),
            Text('Caché objetivo: ${_targetCacheSeconds.toStringAsFixed(1)} s'),
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
            Text('Muestras: ${stats.startupCount}'),
            Text('Fallos: ${stats.failures} · Cortes: ${stats.stalls}'),
            Text('Fast Probe: ${_currentOpenUsesFastProbe ? 'activo' : 'normal'}'),
            if (stats.fastProbeFallbacks > 0)
              Text('Fallbacks de detección: ${stats.fastProbeFallbacks}'),
            Text('Resolución actual: $_resolutionText'),
            Text('Recuperaciones suaves: $_softRecoveryCount'),
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
    _runtimeStatsTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _retryTimer?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _videoParamsSub?.cancel();
    _trackSub?.cancel();
    _audioBitrateSub?.cancel();
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
          if (_videoWidth != null && _videoHeight != null)
            TextButton.icon(
              onPressed: _showStreamInfo,
              icon: const Icon(Icons.high_quality, color: Colors.white70),
              label: Text(
                _compactResolutionLabel,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          if (_lastStartupMs != null)
            TextButton.icon(
              onPressed: _showPerformanceInfo,
              icon: const Icon(Icons.speed, color: Colors.white70),
              label: Text(
                '$_lastStartupMs ms',
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
                Video(controller: _controller),
                if (_hasEverPlayed && _errorMessage == null)
                  Positioned(
                    left: 18,
                    bottom: 18,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'EN VIVO',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if ((_isBuffering || _reconnecting || _softRecovering) &&
                    _errorMessage == null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 12),
                      Text(
                        _softRecovering
                            ? 'Recuperando la señal…'
                            : _normalProbeFallbackUsed && _retryCount == 0
                                ? 'Probando modo compatible…'
                                : _reconnecting
                                    ? 'Reconectando (intento $_retryCount de $_maxAutoRetries)…'
                                    : _hasEverPlayed
                                        ? 'Recibiendo datos…'
                                        : 'Cargando…',
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
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
