from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text()

old_buffer = '''    _bufferingSub = _player.stream.buffering.listen((buffering) {
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
'''
new_buffer = '''    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!mounted || !_acceptPlaybackEvents) return;

      if (buffering && _hasEverPlayed && !_opening && !_reconnecting) {
        _onBufferingStarted();
      }

      // IMPORTANTE: buffering=false sólo significa que mpv dejó el estado de
      // buffering. Algunos servidores TS emiten este evento antes del primer
      // frame real. No cancelamos el timeout ni aprendemos compatibilidad hasta
      // confirmar progreso/salida real de audio o video.
      if (!buffering && _hasEverPlayed) {
        _onBufferingRecovered();
        _lastProgressAt = DateTime.now();
      }

      setState(() {
        _isBuffering = buffering;
        if (!buffering && _hasEverPlayed) {
          _reconnecting = false;
        }
      });

      if (!buffering) {
        _tryConfirmPlaybackFromDecodedOutput();
      }
    });
'''
if old_buffer not in text:
    raise SystemExit('buffering block not found')
text = text.replace(old_buffer, new_buffer, 1)

old_playing = '''    _playingSub = _player.stream.playing.listen((playing) {
      if (!_acceptPlaybackEvents) return;
      _isPlaying = playing;
      if (playing) _lastProgressAt = DateTime.now();
    });
'''
new_playing = '''    _playingSub = _player.stream.playing.listen((playing) {
      if (!_acceptPlaybackEvents) return;
      _isPlaying = playing;
      if (playing) {
        _lastProgressAt = DateTime.now();
        _tryConfirmPlaybackFromDecodedOutput();
      }
    });
'''
if old_playing not in text:
    raise SystemExit('playing block not found')
text = text.replace(old_playing, new_playing, 1)

old_position = '''    _positionSub = _player.stream.position.listen((position) {
      if (!_acceptPlaybackEvents) return;
      if (position != _lastKnownPosition) {
        _lastKnownPosition = position;
        _lastProgressAt = DateTime.now();
        _transientLiveFailureTimer?.cancel();
        _transientLiveFailureTimer = null;
      }
    });
'''
new_position = '''    _positionSub = _player.stream.position.listen((position) {
      if (!_acceptPlaybackEvents) return;
      if (position != _lastKnownPosition) {
        _lastKnownPosition = position;
        _lastProgressAt = DateTime.now();
        _transientLiveFailureTimer?.cancel();
        _transientLiveFailureTimer = null;
        // El avance del reloj es la evidencia más fuerte de que el stream
        // realmente empezó a reproducir, no sólo de que terminó "buffering".
        _confirmPlaybackStarted();
      }
    });
'''
if old_position not in text:
    raise SystemExit('position block not found')
text = text.replace(old_position, new_position, 1)

old_video_tail = '''      setState(() {
        _videoWidth = width;
        _videoHeight = height;
        _pixelFormat = pixelFormat;
      });
    });
'''
new_video_tail = '''      setState(() {
        _videoWidth = width;
        _videoHeight = height;
        _pixelFormat = pixelFormat;
      });
      _tryConfirmPlaybackFromDecodedOutput();
    });
'''
if old_video_tail not in text:
    raise SystemExit('video params tail not found')
text = text.replace(old_video_tail, new_video_tail, 1)

anchor = '''  Future<void> _initializeAndPlay() async {
'''
helper = '''  void _tryConfirmPlaybackFromDecodedOutput() {
    if (_hasEverPlayed ||
        !_acceptPlaybackEvents ||
        _opening ||
        !_isPlaying ||
        _isBuffering) {
      return;
    }

    final hasVideoOutput = (_videoWidth ?? 0) > 0 && (_videoHeight ?? 0) > 0;
    final hasAudioOutput = (_audioCodec?.trim().isNotEmpty ?? false);
    if (hasVideoOutput || hasAudioOutput) {
      _confirmPlaybackStarted();
    }
  }

  void _confirmPlaybackStarted() {
    if (!mounted ||
        _hasEverPlayed ||
        !_acceptPlaybackEvents ||
        _opening ||
        _startupSession != _sessionId) {
      return;
    }

    _hasEverPlayed = true;
    _retryCount = 0;
    _lastProgressAt = DateTime.now();
    _connectTimeoutTimer?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    _transientLiveFailureTimer?.cancel();
    _transientLiveFailureTimer = null;

    // Leemos el formato real una sola vez cuando YA existe reproducción.
    unawaited(_refreshContainerFormat());

    int? elapsed;
    if (_startupStopwatch?.isRunning ?? false) {
      _startupStopwatch!.stop();
      elapsed = _startupStopwatch!.elapsedMilliseconds;
    }

    int? zapElapsed;
    if ((_zapStopwatch?.isRunning ?? false) && _zapSession == _sessionId) {
      _zapStopwatch!.stop();
      zapElapsed = _zapStopwatch!.elapsedMilliseconds;
      _zapSession = null;
    }

    final url = _startupUrl;
    setState(() {
      _reconnecting = false;
      if (elapsed != null) _lastStartupMs = elapsed;
      if (zapElapsed != null) _lastZapMs = zapElapsed;
      _engineDiagnostic =
          'Reproducción confirmada · ${_compatibilityMode.label}';
    });

    if (url != null && elapsed != null) {
      unawaited(_metrics.recordStartup(url, elapsed));
      if (zapElapsed != null) {
        unawaited(_metrics.recordZap(url, zapElapsed));
      }
      // Recién ahora aprendemos que este modo funciona para el host.
      unawaited(_compatibility.recordSuccess(url, _compatibilityMode));
    }
  }

'''
if anchor not in text:
    raise SystemExit('initialize anchor not found')
text = text.replace(anchor, helper + anchor, 1)

old_track_tail = '''        if (audio.bitrate != null && audio.bitrate! > 0) {
          _audioBitrate = audio.bitrate!.toDouble();
        }
      });
    });
'''
new_track_tail = '''        if (audio.bitrate != null && audio.bitrate! > 0) {
          _audioBitrate = audio.bitrate!.toDouble();
        }
      });
      _tryConfirmPlaybackFromDecodedOutput();
    });
'''
if old_track_tail not in text:
    raise SystemExit('track tail not found')
text = text.replace(old_track_tail, new_track_tail, 1)

old_timeout = "        _handleFailure('El canal tardó demasiado en responder', silent: true);"
new_timeout = "        _handleFailure('El servidor respondió, pero no llegó el primer frame', silent: true);"
if old_timeout not in text:
    raise SystemExit('timeout message not found')
text = text.replace(old_timeout, new_timeout, 1)

path.write_text(text)
