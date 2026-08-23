from pathlib import Path
import re

ROOT = Path('.')
SCREEN = ROOT / 'lib/screens/android_media3_texture_player_screen.dart'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'
MAIN = next((ROOT / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))


def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f'Marcador no encontrado: {label}')
    return text.replace(old, new, 1)


def patch_dart():
    text = SCREEN.read_text()

    text = replace_once(
        text,
        "  StreamSubscription<dynamic>? _eventSub;\n\n  int? _textureId;",
        "  StreamSubscription<dynamic>? _eventSub;\n  Timer? _overlayTimer;\n\n  int? _textureId;",
        'overlay timer field',
    )
    text = replace_once(
        text,
        "  int _openGeneration = 0;",
        "  int _openGeneration = 0;\n  int? _startupMs;\n  int? _firstFrameMs;",
        'metric fields',
    )
    text = replace_once(
        text,
        "  Map<String, String> get _headers =>\n      _channel.resolvedHttpHeaders(_media3DefaultUserAgent);\n\n  Future<void> _initialize() async {",
        "  Map<String, String> get _headers =>\n      _channel.resolvedHttpHeaders(_media3DefaultUserAgent);\n\n  void _showOverlayTemporarily({Duration duration = const Duration(seconds: 4)}) {\n    _overlayTimer?.cancel();\n    if (mounted && !_overlayVisible) {\n      setState(() => _overlayVisible = true);\n    }\n    _overlayTimer = Timer(duration, () {\n      if (!mounted || _error != null) return;\n      setState(() => _overlayVisible = false);\n    });\n  }\n\n  Future<void> _initialize() async {",
        'overlay helper',
    )
    text = replace_once(
        text,
        "    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (mounted) _focusNode.requestFocus();\n    });",
        "    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (!mounted) return;\n      _focusNode.requestFocus();\n      _showOverlayTemporarily();\n    });",
        'initial overlay',
    )
    text = replace_once(
        text,
        "        _error = null;\n      });\n    }\n\n    final headers",
        "        _error = null;\n        _startupMs = null;\n        _firstFrameMs = null;\n      });\n    }\n\n    final headers",
        'reset metrics',
    )
    text = replace_once(
        text,
        "      case 'prepared':\n      case 'bufferingEnd':\n        setState(() {\n          _buffering = false;\n          _ready = true;\n          _error = null;\n        });\n        break;",
        "      case 'prepared':\n      case 'bufferingEnd':\n        setState(() {\n          _buffering = false;\n          _ready = true;\n          _error = null;\n          final value = event['startupMs'];\n          if (value is num) _startupMs = value.toInt();\n        });\n        _showOverlayTemporarily();\n        break;\n      case 'firstFrame':\n        final value = event['firstFrameMs'];\n        if (value is num) {\n          setState(() => _firstFrameMs = value.toInt());\n        }\n        break;",
        'ready metrics',
    )
    text = replace_once(
        text,
        "      case 'videoSize':\n        final width = (event['width'] as num?)?.toDouble() ?? 0;\n        final height = (event['height'] as num?)?.toDouble() ?? 0;\n        if (width > 0 && height > 0) {\n          setState(() => _aspectRatio = width / height);\n        }\n        break;",
        "      case 'videoSize':\n        final width = (event['width'] as num?)?.toDouble() ?? 0;\n        final height = (event['height'] as num?)?.toDouble() ?? 0;\n        final pixelRatio =\n            (event['pixelWidthHeightRatio'] as num?)?.toDouble() ?? 1;\n        final displayAspect =\n            (event['displayAspectRatio'] as num?)?.toDouble() ?? 0;\n        final calculated = displayAspect > 0\n            ? displayAspect\n            : (width > 0 && height > 0\n                  ? (width * (pixelRatio > 0 ? pixelRatio : 1)) / height\n                  : 0);\n        if (calculated > 0.5 && calculated < 3.0) {\n          setState(() => _aspectRatio = calculated);\n        }\n        break;",
        'display aspect ratio',
    )

    text = text.replace(
        "      _overlayVisible = true;\n    });\n    unawaited(_prepareCurrent());",
        "      _overlayVisible = true;\n    });\n    _showOverlayTemporarily();\n    unawaited(_prepareCurrent());",
        2,
    )

    text = replace_once(
        text,
        "    if (key == LogicalKeyboardKey.select ||\n        key == LogicalKeyboardKey.enter ||\n        key == LogicalKeyboardKey.numpadEnter) {\n      setState(() => _overlayVisible = !_overlayVisible);\n      return KeyEventResult.handled;\n    }",
        "    if (key == LogicalKeyboardKey.select ||\n        key == LogicalKeyboardKey.enter ||\n        key == LogicalKeyboardKey.numpadEnter) {\n      if (_overlayVisible) {\n        _overlayTimer?.cancel();\n        setState(() => _overlayVisible = false);\n      } else {\n        _showOverlayTemporarily();\n      }\n      return KeyEventResult.handled;\n    }\n    _showOverlayTemporarily();",
        'remote overlay behavior',
    )

    text = replace_once(
        text,
        "    _openGeneration++;\n    _eventSub?.cancel();",
        "    _openGeneration++;\n    _overlayTimer?.cancel();\n    _eventSub?.cancel();",
        'dispose overlay timer',
    )

    text = replace_once(
        text,
        "                                      _ready\n                                          ? 'MEDIA3 · FLUTTER TEXTURE · EN VIVO'\n                                          : 'MEDIA3 · CONECTANDO…',",
        "                                      _ready\n                                          ? 'MEDIA3 · TEXTURE · ${_firstFrameMs != null ? 'FRAME ${_firstFrameMs}ms' : _startupMs != null ? 'READY ${_startupMs}ms' : 'EN VIVO'}'\n                                          : 'MEDIA3 · CONECTANDO…',",
        'metric label',
    )

    SCREEN.write_text(text)


def patch_native():
    text = MAIN.read_text()

    text = replace_once(
        text,
        "        private const val STARTUP_TIMEOUT_MS = 5000L",
        "        private const val TS_STARTUP_TIMEOUT_MS = 4000L\n        private const val HLS_STARTUP_TIMEOUT_MS = 5000L\n        private const val CONNECT_TIMEOUT_MS = 3500\n        private const val READ_TIMEOUT_MS = 5000",
        'timeouts',
    )
    text = replace_once(
        text,
        "    private var endedRecoveries = 0",
        "    private var endedRecoveries = 0\n    private var startupStartedAtMs = 0L\n    private var readyElapsedMs: Long? = null\n    private var firstFrameReported = false\n    private var reachedReady = false",
        'native metrics fields',
    )
    text = replace_once(
        text,
        "        currentUrl = url\n        endedRecoveries = 0\n        playbackGeneration++",
        "        currentUrl = url\n        endedRecoveries = 0\n        reachedReady = false\n        firstFrameReported = false\n        readyElapsedMs = null\n        startupStartedAtMs = android.os.SystemClock.elapsedRealtime()\n        playbackGeneration++",
        'metric reset',
    )
    text = replace_once(
        text,
        "        val httpFactory = DefaultHttpDataSource.Factory()\n            .setUserAgent(userAgent)\n            .setAllowCrossProtocolRedirects(true)",
        "        val httpFactory = DefaultHttpDataSource.Factory()\n            .setUserAgent(userAgent)\n            .setAllowCrossProtocolRedirects(true)\n            .setConnectTimeoutMs(CONNECT_TIMEOUT_MS)\n            .setReadTimeoutMs(READ_TIMEOUT_MS)",
        'http timeouts',
    )
    text = replace_once(
        text,
        "        val item = MediaItem.Builder().setUri(Uri.parse(url)).build()\n        val source = DefaultMediaSourceFactory(httpFactory).createMediaSource(item)",
        "        val lowerUrl = url.lowercase()\n        val isHls = lowerUrl.contains(\".m3u8\") || lowerUrl.contains(\"format=m3u8\")\n        val itemBuilder = MediaItem.Builder().setUri(Uri.parse(url))\n        if (isHls) {\n            itemBuilder.setLiveConfiguration(\n                MediaItem.LiveConfiguration.Builder()\n                    .setTargetOffsetMs(3000L)\n                    .setMinPlaybackSpeed(0.97f)\n                    .setMaxPlaybackSpeed(1.03f)\n                    .build()\n            )\n        }\n        val item = itemBuilder.build()\n        val source = DefaultMediaSourceFactory(httpFactory).createMediaSource(item)",
        'TS HLS policy',
    )
    text = replace_once(
        text,
        "        startupTimeout = Runnable {",
        "        val startupTimeoutMs = if (isHls) HLS_STARTUP_TIMEOUT_MS else TS_STARTUP_TIMEOUT_MS\n        startupTimeout = Runnable {",
        'per format timeout',
    )
    text = replace_once(
        text,
        "                        \"error\" to \"El canal no entregó señal en 5 segundos\",",
        "                        \"error\" to \"El canal no entregó señal en ${startupTimeoutMs / 1000} segundos\",",
        'timeout message',
    )
    text = replace_once(
        text,
        "        }.also { handler.postDelayed(it, STARTUP_TIMEOUT_MS) }",
        "        }.also { handler.postDelayed(it, startupTimeoutMs) }",
        'timeout schedule',
    )
    text = replace_once(
        text,
        "            Player.STATE_BUFFERING ->\n                eventSink?.success(mapOf(\"eventType\" to \"bufferingStart\"))",
        "            Player.STATE_BUFFERING -> {\n                // Startup y rebuffer se reportan por separado: no reiniciamos\n                // el timeout de apertura una vez que el canal llegó a READY.\n                eventSink?.success(\n                    mapOf(\n                        \"eventType\" to if (reachedReady) \"rebufferStart\" else \"bufferingStart\"\n                    )\n                )\n            }",
        'startup vs rebuffer',
    )
    text = replace_once(
        text,
        "            Player.STATE_READY -> {\n                cancelStartupTimeout()\n                endedRecoveries = 0\n                eventSink?.success(mapOf(\"eventType\" to \"prepared\"))\n                eventSink?.success(mapOf(\"eventType\" to \"bufferingEnd\"))",
        "            Player.STATE_READY -> {\n                cancelStartupTimeout()\n                endedRecoveries = 0\n                val elapsed = (android.os.SystemClock.elapsedRealtime() - startupStartedAtMs).coerceAtLeast(0L)\n                if (!reachedReady) readyElapsedMs = elapsed\n                reachedReady = true\n                eventSink?.success(mapOf(\"eventType\" to \"prepared\", \"startupMs\" to (readyElapsedMs ?: elapsed)))\n                eventSink?.success(mapOf(\"eventType\" to \"bufferingEnd\", \"startupMs\" to (readyElapsedMs ?: elapsed)))",
        'ready metrics',
    )
    text = text.replace("endedRecoveries < 5", "endedRecoveries < 1", 1)

    text = replace_once(
        text,
        "    override fun onVideoSizeChanged(videoSize: VideoSize) {\n        if (videoSize.width > 0 && videoSize.height > 0) {",
        "    override fun onRenderedFirstFrame() {\n        if (!firstFrameReported) {\n            firstFrameReported = true\n            val elapsed = (android.os.SystemClock.elapsedRealtime() - startupStartedAtMs).coerceAtLeast(0L)\n            eventSink?.success(mapOf(\"eventType\" to \"firstFrame\", \"firstFrameMs\" to elapsed))\n        }\n    }\n\n    override fun onVideoSizeChanged(videoSize: VideoSize) {\n        if (videoSize.width > 0 && videoSize.height > 0) {",
        'first frame callback',
    )
    text = replace_once(
        text,
        "                    \"width\" to videoSize.width,\n                    \"height\" to videoSize.height,",
        "                    \"width\" to videoSize.width,\n                    \"height\" to videoSize.height,\n                    \"pixelWidthHeightRatio\" to videoSize.pixelWidthHeightRatio,\n                    \"displayAspectRatio\" to ((videoSize.width.toDouble() * videoSize.pixelWidthHeightRatio) / videoSize.height.toDouble()),",
        'pixel ratio event',
    )

    MAIN.write_text(text)


def patch_version():
    if not REMOTE.exists():
        return
    text = REMOTE.read_text()
    text = re.sub(
        r"1\.0\.0\+1-android-tv-[A-Za-z0-9._-]+",
        "1.0.0+1-android-tv-media3-integrated-v7",
        text,
    )
    REMOTE.write_text(text)


patch_dart()
patch_native()
patch_version()
print('V7 integrada aplicada: overlay, aspect ratio, HTTP, TS/HLS, métricas y recuperación.')
