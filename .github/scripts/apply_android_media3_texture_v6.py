from pathlib import Path
import re

ROOT = Path('.')
PLAYER = ROOT / 'lib/screens/player_screen.dart'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'
ANDROID_SCREEN = ROOT / 'lib/screens/android_media3_texture_player_screen.dart'

DEFAULT_UA = (
    'Mozilla/5.0 (Linux; Android 10; Android TV) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
)


def patch_player_wrapper():
    text = PLAYER.read_text()
    import_line = "import 'android_media3_texture_player_screen.dart';"
    if import_line not in text:
        marker = "import '../widgets/live_video_view.dart';"
        if marker not in text:
            raise SystemExit('No se encontro import de live_video_view.dart')
        text = text.replace(marker, marker + "\n" + import_line, 1)

    if 'class _MpvPlayerScreen extends StatefulWidget' not in text:
        old = 'class PlayerScreen extends StatefulWidget {'
        if old not in text:
            raise SystemExit('No se encontro clase PlayerScreen original')
        text = text.replace(old, 'class _MpvPlayerScreen extends StatefulWidget {', 1)
        text = text.replace('  const PlayerScreen({', '  const _MpvPlayerScreen({', 1)
        text = text.replace(
            '  State<PlayerScreen> createState() => _PlayerScreenState();',
            '  State<_MpvPlayerScreen> createState() => _PlayerScreenState();',
            1,
        )
        text = text.replace(
            'class _PlayerScreenState extends State<PlayerScreen> {',
            'class _PlayerScreenState extends State<_MpvPlayerScreen> {',
            1,
        )

    if 'class PlayerScreen extends StatelessWidget' not in text:
        marker = 'class _MpvPlayerScreen extends StatefulWidget {'
        wrapper = r'''class PlayerScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final useNativeMedia3Texture =
        _androidTvBuild &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        isLiveContent;

    if (useNativeMedia3Texture) {
      return AndroidMedia3TexturePlayerScreen(
        playlist: playlist,
        initialIndex: initialIndex,
      );
    }

    return _MpvPlayerScreen(
      channel: channel,
      playlist: playlist,
      initialIndex: initialIndex,
      settings: settings,
      isLiveContent: isLiveContent,
    );
  }
}

'''
        text = text.replace(marker, wrapper + marker, 1)

    PLAYER.write_text(text)


def write_android_screen():
    ANDROID_SCREEN.write_text(r'''import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

const String _media3DefaultUserAgent =
    'Mozilla/5.0 (Linux; Android 10; Android TV) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/131.0.0.0 Safari/537.36';

/// Android TV live player using Media3 + Flutter Texture.
///
/// Unlike the previous V5 experiment, ExoPlayer is NOT embedded in an
/// AndroidView. The native player renders into a SurfaceTexture owned by the
/// FlutterEngine and Flutter composes it with Texture, which is much closer to
/// the architecture used by the analyzed Hot Player build.
class AndroidMedia3TexturePlayerScreen extends StatefulWidget {
  final List<Channel> playlist;
  final int initialIndex;

  const AndroidMedia3TexturePlayerScreen({
    super.key,
    required this.playlist,
    required this.initialIndex,
  });

  @override
  State<AndroidMedia3TexturePlayerScreen> createState() =>
      _AndroidMedia3TexturePlayerScreenState();
}

class _AndroidMedia3TexturePlayerScreenState
    extends State<AndroidMedia3TexturePlayerScreen> {
  static const MethodChannel _player = MethodChannel('tvfull/media3_texture');
  static const EventChannel _events = EventChannel(
    'tvfull/media3_texture_events',
  );

  late int _index;
  final FocusNode _focusNode = FocusNode(debugLabel: 'media3-texture-tv-player');
  StreamSubscription<dynamic>? _eventSub;

  int? _textureId;
  double _aspectRatio = 16 / 9;
  bool _overlayVisible = true;
  bool _buffering = true;
  bool _ready = false;
  String? _error;
  int _openGeneration = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.playlist.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.playlist.length - 1);
    _eventSub = _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _buffering = false;
          _ready = false;
          _error = 'Error del reproductor: $error';
        });
      },
    );
    unawaited(_initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Channel get _channel => widget.playlist[_index];

  Map<String, String> get _headers =>
      _channel.resolvedHttpHeaders(_media3DefaultUserAgent);

  Future<void> _initialize() async {
    try {
      final id = await _player.invokeMethod<int>('initialize', <String, Object?>{
        'minBuffer': 5000,
        'maxBuffer': 15000,
        'bufferForPlayback': 2500,
        'bufferForPlaybackAfterRebuffer': 1000,
      });
      if (!mounted) return;
      setState(() => _textureId = id);
      if (widget.playlist.isNotEmpty) {
        await _prepareCurrent();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _buffering = false;
        _error = e.message ?? e.code;
      });
    }
  }

  Future<void> _prepareCurrent() async {
    if (widget.playlist.isEmpty || _textureId == null) return;
    final generation = ++_openGeneration;
    if (mounted) {
      setState(() {
        _buffering = true;
        _ready = false;
        _error = null;
      });
    }

    final headers = Map<String, String>.from(_headers);
    String? userAgent;
    for (final key in headers.keys.toList()) {
      if (key.toLowerCase() == 'user-agent') {
        userAgent = headers.remove(key);
        break;
      }
    }

    try {
      await _player.invokeMethod<void>('prepare', <String, Object?>{
        'url': _channel.url,
        'headers': headers,
        'userAgent': userAgent ?? _media3DefaultUserAgent,
        'isLive': true,
      });
    } on PlatformException catch (e) {
      if (!mounted || generation != _openGeneration) return;
      setState(() {
        _buffering = false;
        _ready = false;
        _error = e.message ?? e.code;
      });
    }
  }

  void _onNativeEvent(dynamic raw) {
    if (!mounted || raw is! Map) return;
    final event = raw.cast<Object?, Object?>();
    final type = event['eventType']?.toString();
    switch (type) {
      case 'bufferingStart':
        setState(() => _buffering = true);
        break;
      case 'prepared':
      case 'bufferingEnd':
        setState(() {
          _buffering = false;
          _ready = true;
          _error = null;
        });
        break;
      case 'videoSize':
        final width = (event['width'] as num?)?.toDouble() ?? 0;
        final height = (event['height'] as num?)?.toDouble() ?? 0;
        if (width > 0 && height > 0) {
          setState(() => _aspectRatio = width / height);
        }
        break;
      case 'videoError':
        setState(() {
          _buffering = false;
          _ready = false;
          _error = event['error']?.toString() ?? 'Canal no disponible';
        });
        break;
      case 'completed':
        setState(() {
          _buffering = false;
          _ready = false;
          _error = 'La señal terminó inesperadamente.';
        });
        break;
    }
  }

  void _previous() {
    if (widget.playlist.isEmpty) return;
    setState(() {
      _index = (_index - 1 + widget.playlist.length) % widget.playlist.length;
      _overlayVisible = true;
    });
    unawaited(_prepareCurrent());
  }

  void _next() {
    if (widget.playlist.isEmpty) return;
    setState(() {
      _index = (_index + 1) % widget.playlist.length;
      _overlayVisible = true;
    });
    unawaited(_prepareCurrent());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
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
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      setState(() => _overlayVisible = !_overlayVisible);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _openGeneration++;
    _eventSub?.cancel();
    _focusNode.dispose();
    unawaited(_player.invokeMethod<void>('dispose'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.playlist.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No hay canales para reproducir.')),
      );
    }

    final channel = _channel;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
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
              ),
              if (_buffering && _error == null)
                const IgnorePointer(
                  child: Center(
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ),
              if (_error != null)
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 540),
                    margin: const EdgeInsets.all(28),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xE814202D),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: .4),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.tv_off_rounded,
                          size: 46,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'CANAL TEMPORALMENTE NO DISPONIBLE',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => unawaited(_prepareCurrent()),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_overlayVisible)
                IgnorePointer(
                  ignoring: false,
                  child: SafeArea(
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.all(18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xD9101722),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Volver',
                                onPressed: () => Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      channel.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      _ready
                                          ? 'MEDIA3 · FLUTTER TEXTURE · EN VIVO'
                                          : 'MEDIA3 · CONECTANDO…',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white60,
                                        letterSpacing: .7,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${_index + 1}/${widget.playlist.length}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Container(
                          margin: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xD9101722),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Canal anterior',
                                onPressed: _previous,
                                icon: const Icon(Icons.skip_previous_rounded),
                              ),
                              const SizedBox(width: 14),
                              const Text(
                                'EN VIVO',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(width: 14),
                              IconButton(
                                tooltip: 'Canal siguiente',
                                onPressed: _next,
                                icon: const Icon(Icons.skip_next_rounded),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
''')


def patch_remote_version():
    if not REMOTE.exists():
        return
    text = REMOTE.read_text()
    text = re.sub(
        r"1\.0\.0\+1-android-tv-[A-Za-z0-9._-]+",
        "1.0.0+1-android-tv-media3-texture-v6",
        text,
    )
    REMOTE.write_text(text)


def patch_android_project():
    gradle = ROOT / 'android/app/build.gradle.kts'
    manifest = ROOT / 'android/app/src/main/AndroidManifest.xml'
    if not gradle.exists() or not manifest.exists():
        raise SystemExit('Primero debe ejecutarse flutter create --platforms=android .')

    g = gradle.read_text()
    g = g.replace(
        'applicationId = "com.example.iptv_player"',
        'applicationId = "com.tvfull.pro.tv.v6texture"',
    )
    deps = '''\n\ndependencies {\n    implementation("androidx.media3:media3-exoplayer:1.8.0")\n    implementation("androidx.media3:media3-exoplayer-hls:1.8.0")\n    implementation("io.github.anilbeesetti:nextlib-media3ext:1.8.0-0.9.0")\n}\n'''
    if 'nextlib-media3ext' not in g:
        g += deps
    gradle.write_text(g)

    m = manifest.read_text()
    if 'android.permission.INTERNET' not in m:
        m = m.replace(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <uses-permission android:name="android.permission.INTERNET" />\n'
            '    <uses-feature android:name="android.software.leanback" android:required="true" />\n'
            '    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />\n'
            '    <uses-feature android:name="android.hardware.faketouch" android:required="false" />',
            1,
        )
    m = m.replace('android:label="iptv_player"', 'android:label="TV FULL PRO V6 TEXTURE"')
    if 'android:usesCleartextTraffic=' not in m:
        m = m.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
    if 'android:banner=' not in m:
        m = m.replace(
            'android:label="TV FULL PRO V6 TEXTURE"',
            'android:label="TV FULL PRO V6 TEXTURE"\n        android:banner="@mipmap/ic_launcher"',
            1,
        )
    if 'android:screenOrientation=' not in m:
        m = m.replace(
            'android:name=".MainActivity"',
            'android:name=".MainActivity"\n            android:screenOrientation="landscape"',
            1,
        )
    if 'android.intent.category.LEANBACK_LAUNCHER' not in m:
        m = m.replace(
            '<category android:name="android.intent.category.LAUNCHER"/>',
            '<category android:name="android.intent.category.LAUNCHER"/>\n'
            '                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
            1,
        )
    manifest.write_text(m)

    candidates = list((ROOT / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))
    if not candidates:
        raise SystemExit('No se encontro MainActivity.kt generado por Flutter')
    main = candidates[0]
    original = main.read_text()
    package_line = next(
        (line for line in original.splitlines() if line.startswith('package ')),
        'package com.example.iptv_player',
    )

    native = f'''{package_line}\n\nimport android.net.Uri\nimport android.os.Handler\nimport android.os.Looper\nimport android.view.Surface\nimport androidx.media3.common.AudioAttributes\nimport androidx.media3.common.C\nimport androidx.media3.common.MediaItem\nimport androidx.media3.common.PlaybackException\nimport androidx.media3.common.Player\nimport androidx.media3.common.VideoSize\nimport androidx.media3.common.util.UnstableApi\nimport androidx.media3.datasource.DefaultHttpDataSource\nimport androidx.media3.exoplayer.DefaultLoadControl\nimport androidx.media3.exoplayer.DefaultRenderersFactory\nimport androidx.media3.exoplayer.ExoPlayer\nimport androidx.media3.exoplayer.source.DefaultMediaSourceFactory\nimport io.flutter.embedding.android.FlutterActivity\nimport io.flutter.embedding.engine.FlutterEngine\nimport io.flutter.plugin.common.EventChannel\nimport io.flutter.plugin.common.MethodCall\nimport io.flutter.plugin.common.MethodChannel\nimport io.flutter.view.TextureRegistry\nimport io.github.anilbeesetti.nextlib.media3ext.ffdecoder.NextRenderersFactory\n\n@UnstableApi\nclass MainActivity : FlutterActivity(), Player.Listener {{\n    companion object {{\n        private const val METHOD_CHANNEL = "tvfull/media3_texture"\n        private const val EVENT_CHANNEL = "tvfull/media3_texture_events"\n        private const val STARTUP_TIMEOUT_MS = 5000L\n    }}\n\n    private var player: ExoPlayer? = null\n    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null\n    private var surface: Surface? = null\n    private var eventSink: EventChannel.EventSink? = null\n    private val handler = Handler(Looper.getMainLooper())\n    private var startupTimeout: Runnable? = null\n    private var playbackGeneration = 0L\n    private var currentUrl: String? = null\n    private var isLive = false\n    private var endedRecoveries = 0\n\n    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{\n        super.configureFlutterEngine(flutterEngine)\n\n        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)\n            .setStreamHandler(object : EventChannel.StreamHandler {{\n                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {{\n                    eventSink = events\n                }}\n                override fun onCancel(arguments: Any?) {{\n                    eventSink = null\n                }}\n            }})\n\n        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)\n            .setMethodCallHandler {{ call, result ->\n                handlePlayerCall(flutterEngine, call, result)\n            }}\n    }}\n\n    private fun handlePlayerCall(\n        flutterEngine: FlutterEngine,\n        call: MethodCall,\n        result: MethodChannel.Result,\n    ) {{\n        when (call.method) {{\n            "initialize" -> {{\n                val minBuffer = call.argument<Int>("minBuffer") ?: 5000\n                val maxBuffer = call.argument<Int>("maxBuffer") ?: 15000\n                val playBuffer = call.argument<Int>("bufferForPlayback") ?: 2500\n                val rebuffer = call.argument<Int>("bufferForPlaybackAfterRebuffer") ?: 1000\n                result.success(\n                    initializePlayer(\n                        flutterEngine,\n                        minBuffer,\n                        maxBuffer,\n                        playBuffer,\n                        rebuffer,\n                    )\n                )\n            }}\n            "prepare" -> {{\n                val url = call.argument<String>("url")\n                if (url.isNullOrBlank()) {{\n                    result.error("INVALID_URL", "URL vacia", null)\n                    return\n                }}\n                @Suppress("UNCHECKED_CAST")\n                val headers = (\n                    call.argument<Map<String, String>>("headers") ?: emptyMap()\n                ).toMutableMap()\n                val userAgent = call.argument<String>("userAgent") ?: "{DEFAULT_UA}"\n                isLive = call.argument<Boolean>("isLive") ?: true\n                prepare(url, headers, userAgent)\n                result.success(null)\n            }}\n            "play" -> {{\n                player?.play()\n                result.success(null)\n            }}\n            "pause" -> {{\n                player?.pause()\n                result.success(null)\n            }}\n            "dispose" -> {{\n                disposePlayer()\n                result.success(null)\n            }}\n            else -> result.notImplemented()\n        }}\n    }}\n\n    private fun initializePlayer(\n        flutterEngine: FlutterEngine,\n        minBuffer: Int,\n        maxBuffer: Int,\n        playBuffer: Int,\n        rebuffer: Int,\n    ): Long {{\n        disposePlayer()\n\n        val loadControl = DefaultLoadControl.Builder()\n            .setBufferDurationsMs(minBuffer, maxBuffer, playBuffer, rebuffer)\n            .build()\n\n        val renderersFactory = NextRenderersFactory(this)\n            .setEnableDecoderFallback(true)\n            .setExtensionRendererMode(\n                DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON\n            )\n\n        player = ExoPlayer.Builder(this)\n            .setLoadControl(loadControl)\n            .setRenderersFactory(renderersFactory)\n            .build()\n            .also {{ exo ->\n                exo.setAudioAttributes(\n                    AudioAttributes.Builder()\n                        .setUsage(C.USAGE_MEDIA)\n                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)\n                        .build(),\n                    true,\n                )\n                exo.addListener(this)\n            }}\n\n        textureEntry = flutterEngine.renderer.createSurfaceTexture()\n        surface = Surface(textureEntry!!.surfaceTexture())\n        player!!.setVideoSurface(surface)\n        return textureEntry!!.id()\n    }}\n\n    private fun prepare(\n        url: String,\n        headers: MutableMap<String, String>,\n        userAgent: String,\n    ) {{\n        val exo = player ?: return\n        currentUrl = url\n        endedRecoveries = 0\n        playbackGeneration++\n        val generation = playbackGeneration\n        cancelStartupTimeout()\n\n        val httpFactory = DefaultHttpDataSource.Factory()\n            .setUserAgent(userAgent)\n            .setAllowCrossProtocolRedirects(true)\n        if (headers.isNotEmpty()) {{\n            httpFactory.setDefaultRequestProperties(headers)\n        }}\n\n        val item = MediaItem.Builder().setUri(Uri.parse(url)).build()\n        val source = DefaultMediaSourceFactory(httpFactory).createMediaSource(item)\n        exo.setMediaSource(source)\n        exo.prepare()\n        exo.playWhenReady = true\n\n        startupTimeout = Runnable {{\n            if (generation != playbackGeneration) return@Runnable\n            val current = player ?: return@Runnable\n            if (current.playbackState != Player.STATE_READY) {{\n                current.stop()\n                eventSink?.success(\n                    mapOf(\n                        "eventType" to "videoError",\n                        "error" to "El canal no entregó señal en 5 segundos",\n                    )\n                )\n            }}\n        }}.also {{ handler.postDelayed(it, STARTUP_TIMEOUT_MS) }}\n    }}\n\n    private fun cancelStartupTimeout() {{\n        startupTimeout?.let(handler::removeCallbacks)\n        startupTimeout = null\n    }}\n\n    override fun onPlaybackStateChanged(playbackState: Int) {{\n        when (playbackState) {{\n            Player.STATE_BUFFERING ->\n                eventSink?.success(mapOf("eventType" to "bufferingStart"))\n            Player.STATE_READY -> {{\n                cancelStartupTimeout()\n                endedRecoveries = 0\n                eventSink?.success(mapOf("eventType" to "prepared"))\n                eventSink?.success(mapOf("eventType" to "bufferingEnd"))\n            }}\n            Player.STATE_ENDED -> {{\n                val exo = player\n                if (\n                    isLive &&\n                    currentUrl != null &&\n                    exo != null &&\n                    endedRecoveries < 5\n                ) {{\n                    endedRecoveries++\n                    exo.seekToDefaultPosition()\n                    exo.prepare()\n                    exo.play()\n                }} else {{\n                    eventSink?.success(mapOf("eventType" to "completed"))\n                }}\n            }}\n        }}\n    }}\n\n    override fun onVideoSizeChanged(videoSize: VideoSize) {{\n        if (videoSize.width > 0 && videoSize.height > 0) {{\n            textureEntry?.surfaceTexture()?.setDefaultBufferSize(\n                videoSize.width,\n                videoSize.height,\n            )\n            eventSink?.success(\n                mapOf(\n                    "eventType" to "videoSize",\n                    "width" to videoSize.width,\n                    "height" to videoSize.height,\n                )\n            )\n        }}\n    }}\n\n    override fun onPlayerError(error: PlaybackException) {{\n        cancelStartupTimeout()\n        eventSink?.success(\n            mapOf(\n                "eventType" to "videoError",\n                "error" to (\n                    error.errorCodeName +\n                    " · " +\n                    (error.message ?: "error de reproducción")\n                ),\n            )\n        )\n    }}\n\n    private fun disposePlayer() {{\n        playbackGeneration++\n        cancelStartupTimeout()\n        player?.removeListener(this)\n        player?.stop()\n        player?.clearMediaItems()\n        player?.release()\n        player = null\n        surface?.release()\n        surface = null\n        textureEntry?.release()\n        textureEntry = null\n        currentUrl = null\n        endedRecoveries = 0\n    }}\n\n    override fun onDestroy() {{\n        disposePlayer()\n        super.onDestroy()\n    }}\n}}\n'''
    main.write_text(native)


def validate():
    p = PLAYER.read_text()
    for check in [
        'class PlayerScreen extends StatelessWidget',
        'class _MpvPlayerScreen extends StatefulWidget',
        'AndroidMedia3TexturePlayerScreen(',
    ]:
        if check not in p:
            raise SystemExit(f'Falta marcador Dart: {check}')

    d = ANDROID_SCREEN.read_text()
    for check in ['Texture(', "MethodChannel('tvfull/media3_texture')"]:
        if check not in d:
            raise SystemExit(f'Falta marcador Texture: {check}')

    g = (ROOT / 'android/app/build.gradle.kts').read_text()
    for check in [
        'media3-exoplayer:1.8.0',
        'nextlib-media3ext:1.8.0-0.9.0',
        'com.tvfull.pro.tv.v6texture',
    ]:
        if check not in g:
            raise SystemExit(f'Falta marcador Android: {check}')

    mains = list((ROOT / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))
    if not mains:
        raise SystemExit('MainActivity faltante')
    native = mains[0].read_text()
    for check in [
        'createSurfaceTexture()',
        'setVideoSurface(surface)',
        'STARTUP_TIMEOUT_MS = 5000L',
    ]:
        if check not in native:
            raise SystemExit(f'Falta marcador nativo: {check}')


patch_player_wrapper()
write_android_screen()
patch_remote_version()
patch_android_project()
validate()
print('Android Media3 Texture V6 aplicado correctamente.')
