from pathlib import Path
import re

ROOT = Path('.')
DART = ROOT / 'lib/screens/android_media3_texture_player_screen.dart'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'
GRADLE = ROOT / 'android/app/build.gradle.kts'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'No se encontro marcador: {label}')
    return text.replace(old, new, 1)


def patch_dart():
    text = DART.read_text()

    text = replace_once(
        text,
        "  StreamSubscription<dynamic>? _eventSub;\n\n  int? _textureId;",
        "  StreamSubscription<dynamic>? _eventSub;\n  Timer? _overlayTimer;\n\n  int? _textureId;",
        'overlay timer field',
    )
    text = replace_once(
        text,
        "  int _openGeneration = 0;\n",
        "  int _openGeneration = 0;\n  int? _lastStartupMs;\n  int? _lastFirstFrameMs;\n",
        'metrics fields',
    )
    text = replace_once(
        text,
        "    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (mounted) _focusNode.requestFocus();\n    });",
        "    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (!mounted) return;\n      _focusNode.requestFocus();\n      _showOverlayTemporarily();\n    });",
        'initial overlay scheduling',
    )

    text = replace_once(
        text,
        "      case 'prepared':\n      case 'bufferingEnd':\n        setState(() {\n          _buffering = false;\n          _ready = true;\n          _error = null;\n        });\n        break;",
        "      case 'prepared':\n        final startupMs = (event['startupMs'] as num?)?.toInt();\n        setState(() {\n          _buffering = false;\n          _ready = true;\n          _error = null;\n          if (startupMs != null) _lastStartupMs = startupMs;\n        });\n        _scheduleOverlayHide();\n        break;\n      case 'bufferingEnd':\n        setState(() {\n          _buffering = false;\n          _ready = true;\n          _error = null;\n        });\n        _scheduleOverlayHide();\n        break;\n      case 'firstFrame':\n        final firstFrameMs = (event['firstFrameMs'] as num?)?.toInt();\n        if (firstFrameMs != null) {\n          setState(() => _lastFirstFrameMs = firstFrameMs);\n        }\n        break;",
        'prepared metrics',
    )

    text = replace_once(
        text,
        "        final width = (event['width'] as num?)?.toDouble() ?? 0;\n        final height = (event['height'] as num?)?.toDouble() ?? 0;\n        if (width > 0 && height > 0) {\n          setState(() => _aspectRatio = width / height);\n        }",
        "        final width = (event['width'] as num?)?.toDouble() ?? 0;\n        final height = (event['height'] as num?)?.toDouble() ?? 0;\n        final displayAspect =\n            (event['displayAspectRatio'] as num?)?.toDouble();\n        if (displayAspect != null && displayAspect > 0.2) {\n          setState(() => _aspectRatio = displayAspect);\n        } else if (width > 0 && height > 0) {\n          setState(() => _aspectRatio = width / height);\n        }",
        'display aspect ratio',
    )

    text = replace_once(
        text,
        "      case 'videoError':\n        setState(() {\n          _buffering = false;\n          _ready = false;\n          _error = event['error']?.toString() ?? 'Canal no disponible';\n        });",
        "      case 'videoError':\n        _overlayTimer?.cancel();\n        setState(() {\n          _buffering = false;\n          _ready = false;\n          _overlayVisible = true;\n          _error = event['error']?.toString() ?? 'Canal no disponible';\n        });",
        'error overlay',
    )

    text = replace_once(
        text,
        "  void _previous() {\n    if (widget.playlist.isEmpty) return;\n    setState(() {\n      _index = (_index - 1 + widget.playlist.length) % widget.playlist.length;\n      _overlayVisible = true;\n    });\n    unawaited(_prepareCurrent());\n  }\n\n  void _next() {\n    if (widget.playlist.isEmpty) return;\n    setState(() {\n      _index = (_index + 1) % widget.playlist.length;\n      _overlayVisible = true;\n    });\n    unawaited(_prepareCurrent());\n  }",
        "  void _previous() {\n    if (widget.playlist.isEmpty) return;\n    setState(() {\n      _index = (_index - 1 + widget.playlist.length) % widget.playlist.length;\n    });\n    _showOverlayTemporarily();\n    unawaited(_prepareCurrent());\n  }\n\n  void _next() {\n    if (widget.playlist.isEmpty) return;\n    setState(() {\n      _index = (_index + 1) % widget.playlist.length;\n    });\n    _showOverlayTemporarily();\n    unawaited(_prepareCurrent());\n  }",
        'channel navigation overlay',
    )

    key_start = text.index('  KeyEventResult _onKey(')
    dispose_start = text.index('  @override\n  void dispose()', key_start)
    replacement = r'''  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    if (!_ready || _error != null) return;
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_ready || _error != null) return;
      setState(() => _overlayVisible = false);
    });
  }

  void _showOverlayTemporarily() {
    _overlayTimer?.cancel();
    if (mounted && !_overlayVisible) {
      setState(() => _overlayVisible = true);
    }
    _scheduleOverlayHide();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_overlayVisible) {
        _overlayTimer?.cancel();
        setState(() => _overlayVisible = false);
      } else {
        _showOverlayTemporarily();
      }
      return KeyEventResult.handled;
    }

    _showOverlayTemporarily();
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _previous();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
      _next();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

'''
    text = text[:key_start] + replacement + text[dispose_start:]

    text = replace_once(
        text,
        "    _eventSub?.cancel();\n    _focusNode.dispose();",
        "    _eventSub?.cancel();\n    _overlayTimer?.cancel();\n    _focusNode.dispose();",
        'dispose overlay timer',
    )

    old_video = '''              ColoredBox(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _aspectRatio,
                    child: _textureId == null
                        ? const SizedBox.shrink()
                        : Texture(
                            textureId: _textureId!,
                            filterQuality: FilterQuality.none,
                          ),
                  ),
                ),
              ),'''
    new_video = '''              ColoredBox(
                color: Colors.black,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_textureId == null ||
                        constraints.maxWidth <= 0 ||
                        constraints.maxHeight <= 0) {
                      return const SizedBox.shrink();
                    }
                    final screenAspect =
                        constraints.maxWidth / constraints.maxHeight;
                    final videoAspect = _aspectRatio > 0
                        ? _aspectRatio
                        : screenAspect;
                    final ratioError =
                        (videoAspect - screenAspect).abs() / screenAspect;
                    final looksLikeWideScreen =
                        videoAspect >= 1.60 && videoAspect <= 1.95;
                    final fillScreen = ratioError < 0.10 || looksLikeWideScreen;
                    final texture = Texture(
                      textureId: _textureId!,
                      filterQuality: FilterQuality.none,
                    );
                    if (fillScreen) {
                      return SizedBox.expand(child: texture);
                    }
                    return Center(
                      child: AspectRatio(
                        aspectRatio: videoAspect,
                        child: texture,
                      ),
                    );
                  },
                ),
              ),'''
    text = replace_once(text, old_video, new_video, 'smart screen fit')

    text = replace_once(
        text,
        "                                      _ready\n                                          ? 'MEDIA3 · FLUTTER TEXTURE · EN VIVO'\n                                          : 'MEDIA3 · CONECTANDO…',",
        "                                      _ready\n                                          ? 'MEDIA3 · EN VIVO'\n                                              '${_lastFirstFrameMs == null ? '' : ' · ${_lastFirstFrameMs} ms'}'\n                                          : 'MEDIA3 · CONECTANDO…',",
        'compact live status',
    )

    DART.write_text(text)


def patch_native():
    candidates = list((ROOT / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))
    if not candidates:
        raise SystemExit('No se encontro MainActivity.kt')
    main = candidates[0]
    text = main.read_text()

    text = replace_once(
        text,
        'import android.os.Looper\nimport android.view.Surface',
        'import android.os.Looper\nimport android.os.SystemClock\nimport android.view.Surface',
        'SystemClock import',
    )
    text = replace_once(
        text,
        'import androidx.media3.common.MediaItem\nimport androidx.media3.common.PlaybackException',
        'import androidx.media3.common.MediaItem\nimport androidx.media3.common.MimeTypes\nimport androidx.media3.common.PlaybackException',
        'MimeTypes import',
    )
    text = replace_once(
        text,
        '        private const val STARTUP_TIMEOUT_MS = 5000L\n',
        '        private const val STARTUP_TIMEOUT_MS = 5000L\n        private const val REBUFFER_TIMEOUT_MS = 15000L\n',
        'rebuffer constant',
    )
    text = replace_once(
        text,
        '    private var startupTimeout: Runnable? = null\n    private var playbackGeneration = 0L',
        '    private var startupTimeout: Runnable? = null\n    private var rebufferTimeout: Runnable? = null\n    private var playbackGeneration = 0L',
        'rebuffer field',
    )
    text = replace_once(
        text,
        '    private var endedRecoveries = 0\n',
        '    private var endedRecoveries = 0\n    private var hasReachedReady = false\n    private var openStartedAtMs = 0L\n    private var firstFrameReported = false\n',
        'playback state fields',
    )
    text = replace_once(
        text,
        '        val loadControl = DefaultLoadControl.Builder()\n            .setBufferDurationsMs(minBuffer, maxBuffer, playBuffer, rebuffer)\n            .build()',
        '        val loadControl = DefaultLoadControl.Builder()\n            .setBufferDurationsMs(minBuffer, maxBuffer, playBuffer, rebuffer)\n            .setPrioritizeTimeOverSizeThresholds(true)\n            .build()',
        'time prioritized buffering',
    )

    text = replace_once(
        text,
        '        endedRecoveries = 0\n        playbackGeneration++\n        val generation = playbackGeneration\n        cancelStartupTimeout()\n\n        val httpFactory = DefaultHttpDataSource.Factory()\n            .setUserAgent(userAgent)\n            .setAllowCrossProtocolRedirects(true)',
        '        endedRecoveries = 0\n        hasReachedReady = false\n        firstFrameReported = false\n        openStartedAtMs = SystemClock.elapsedRealtime()\n        playbackGeneration++\n        val generation = playbackGeneration\n        cancelStartupTimeout()\n        cancelRebufferTimeout()\n\n        val httpFactory = DefaultHttpDataSource.Factory()\n            .setUserAgent(userAgent)\n            .setConnectTimeoutMs(5000)\n            .setReadTimeoutMs(8000)\n            .setAllowCrossProtocolRedirects(true)',
        'http timeouts and session state',
    )

    text = replace_once(
        text,
        '        val item = MediaItem.Builder().setUri(Uri.parse(url)).build()\n        val source = DefaultMediaSourceFactory(httpFactory).createMediaSource(item)',
        '''        val parsed = Uri.parse(url)
        val path = parsed.path?.lowercase() ?: ""
        val itemBuilder = MediaItem.Builder().setUri(parsed)
        when {
            path.endsWith(".m3u8") -> itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
            path.endsWith(".ts") -> itemBuilder.setMimeType(MimeTypes.VIDEO_MP2T)
        }
        val item = itemBuilder.build()
        val source = DefaultMediaSourceFactory(httpFactory).createMediaSource(item)''',
        'TS/HLS media type',
    )

    text = replace_once(
        text,
        '    private fun cancelStartupTimeout() {\n        startupTimeout?.let(handler::removeCallbacks)\n        startupTimeout = null\n    }\n\n',
        '''    private fun cancelStartupTimeout() {
        startupTimeout?.let(handler::removeCallbacks)
        startupTimeout = null
    }

    private fun cancelRebufferTimeout() {
        rebufferTimeout?.let(handler::removeCallbacks)
        rebufferTimeout = null
    }

    private fun scheduleRebufferTimeout() {
        cancelRebufferTimeout()
        val generation = playbackGeneration
        rebufferTimeout = Runnable {
            if (generation != playbackGeneration) return@Runnable
            val current = player ?: return@Runnable
            if (hasReachedReady && current.playbackState == Player.STATE_BUFFERING) {
                current.stop()
                eventSink?.success(
                    mapOf(
                        "eventType" to "videoError",
                        "error" to "La señal dejó de entregar datos durante 15 segundos",
                    )
                )
            }
        }.also { handler.postDelayed(it, REBUFFER_TIMEOUT_MS) }
    }

''',
        'rebuffer timeout helpers',
    )

    start = text.index('    override fun onPlaybackStateChanged(playbackState: Int) {')
    end = text.index('    override fun onVideoSizeChanged(videoSize: VideoSize) {', start)
    playback = r'''    override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_BUFFERING -> {
                eventSink?.success(mapOf("eventType" to "bufferingStart"))
                if (hasReachedReady) scheduleRebufferTimeout()
            }
            Player.STATE_READY -> {
                cancelStartupTimeout()
                cancelRebufferTimeout()
                endedRecoveries = 0
                val firstReady = !hasReachedReady
                hasReachedReady = true
                if (firstReady) {
                    val startupMs = (SystemClock.elapsedRealtime() - openStartedAtMs)
                        .coerceAtLeast(0L)
                    eventSink?.success(
                        mapOf(
                            "eventType" to "prepared",
                            "startupMs" to startupMs,
                        )
                    )
                }
                eventSink?.success(mapOf("eventType" to "bufferingEnd"))
            }
            Player.STATE_ENDED -> {
                val exo = player
                if (
                    isLive &&
                    currentUrl != null &&
                    exo != null &&
                    endedRecoveries < 1
                ) {
                    endedRecoveries++
                    exo.seekToDefaultPosition()
                    exo.prepare()
                    exo.play()
                } else {
                    eventSink?.success(mapOf("eventType" to "completed"))
                }
            }
        }
    }

'''
    text = text[:start] + playback + text[end:]

    old_size = '''    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (videoSize.width > 0 && videoSize.height > 0) {
            textureEntry?.surfaceTexture()?.setDefaultBufferSize(
                videoSize.width,
                videoSize.height,
            )
            eventSink?.success(
                mapOf(
                    "eventType" to "videoSize",
                    "width" to videoSize.width,
                    "height" to videoSize.height,
                )
            )
        }
    }

'''
    new_size = '''    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (videoSize.width > 0 && videoSize.height > 0) {
            textureEntry?.surfaceTexture()?.setDefaultBufferSize(
                videoSize.width,
                videoSize.height,
            )
            val pixelRatio = videoSize.pixelWidthHeightRatio
                .takeIf { it > 0f } ?: 1f
            val displayAspect =
                (videoSize.width.toFloat() * pixelRatio) / videoSize.height.toFloat()
            eventSink?.success(
                mapOf(
                    "eventType" to "videoSize",
                    "width" to videoSize.width,
                    "height" to videoSize.height,
                    "pixelRatio" to pixelRatio.toDouble(),
                    "displayAspectRatio" to displayAspect.toDouble(),
                )
            )
        }
    }

    override fun onRenderedFirstFrame() {
        if (firstFrameReported || openStartedAtMs <= 0L) return
        firstFrameReported = true
        val firstFrameMs = (SystemClock.elapsedRealtime() - openStartedAtMs)
            .coerceAtLeast(0L)
        eventSink?.success(
            mapOf(
                "eventType" to "firstFrame",
                "firstFrameMs" to firstFrameMs,
            )
        )
    }

'''
    text = replace_once(text, old_size, new_size, 'pixel aspect and first frame')

    text = replace_once(
        text,
        '        cancelStartupTimeout()\n        eventSink?.success(',
        '        cancelStartupTimeout()\n        cancelRebufferTimeout()\n        eventSink?.success(',
        'cancel rebuffer on player error',
    )
    text = replace_once(
        text,
        '        cancelStartupTimeout()\n        player?.removeListener(this)',
        '        cancelStartupTimeout()\n        cancelRebufferTimeout()\n        player?.removeListener(this)',
        'cancel rebuffer on dispose',
    )
    text = replace_once(
        text,
        '        endedRecoveries = 0\n    }',
        '        endedRecoveries = 0\n        hasReachedReady = false\n        firstFrameReported = false\n        openStartedAtMs = 0L\n    }',
        'reset native state',
    )

    main.write_text(text)


def patch_build():
    text = GRADLE.read_text()
    marker = 'applicationId = "com.tvfull.pro.tv.v6texture"'
    if marker not in text:
        raise SystemExit('No se encontro applicationId V6')
    if 'abiFilters += listOf("arm64-v8a")' not in text:
        text = text.replace(
            marker,
            marker + '\n        ndk { abiFilters += listOf("arm64-v8a") }',
            1,
        )
    GRADLE.write_text(text)

    if REMOTE.exists():
        remote = REMOTE.read_text().replace(
            '1.0.0+1-android-tv-media3-texture-v6',
            '1.0.0+1-android-tv-media3-v7-integrated',
        )
        REMOTE.write_text(remote)


def validate():
    d = DART.read_text()
    for marker in [
        '_scheduleOverlayHide()',
        'displayAspectRatio',
        'looksLikeWideScreen',
        '_lastFirstFrameMs',
    ]:
        if marker not in d:
            raise SystemExit(f'Falta ajuste Dart: {marker}')

    candidates = list((ROOT / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))
    native = candidates[0].read_text()
    for marker in [
        'REBUFFER_TIMEOUT_MS = 15000L',
        'setConnectTimeoutMs(5000)',
        'MimeTypes.APPLICATION_M3U8',
        'MimeTypes.VIDEO_MP2T',
        'onRenderedFirstFrame()',
        'pixelWidthHeightRatio',
        'endedRecoveries < 1',
    ]:
        if marker not in native:
            raise SystemExit(f'Falta ajuste nativo: {marker}')

    gradle = GRADLE.read_text()
    if 'abiFilters += listOf("arm64-v8a")' not in gradle:
        raise SystemExit('Falta filtro ARM64')


patch_dart()
patch_native()
patch_build()
validate()
print('Media3 V7 integrada aplicada: overlay, aspect, HTTP, TS/HLS, rebuffer, metrics, ARM64.')
