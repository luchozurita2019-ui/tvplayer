from pathlib import Path
import re

ROOT = Path('.')
PLAYER = ROOT / 'lib/screens/player_screen.dart'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'
ANDROID_SCREEN = ROOT / 'lib/screens/android_media3_player_screen.dart'

DEFAULT_UA = (
    'Mozilla/5.0 (Linux; Android 10; Android TV) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
)


def patch_player_wrapper():
    text = PLAYER.read_text()
    if "import 'android_media3_player_screen.dart';" not in text:
        marker = "import '../widgets/live_video_view.dart';"
        if marker not in text:
            raise SystemExit('No se encontro import de live_video_view.dart')
        text = text.replace(marker, marker + "\nimport 'android_media3_player_screen.dart';", 1)

    if 'class _MpvPlayerScreen extends StatefulWidget' not in text:
        old = 'class PlayerScreen extends StatefulWidget {'
        if old not in text:
            raise SystemExit('No se encontro clase PlayerScreen original')
        text = text.replace(old, 'class _MpvPlayerScreen extends StatefulWidget {', 1)
        text = text.replace('  const PlayerScreen({', '  const _MpvPlayerScreen({', 1)
        text = text.replace('  State<PlayerScreen> createState() => _PlayerScreenState();',
                            '  State<_MpvPlayerScreen> createState() => _PlayerScreenState();', 1)
        text = text.replace('class _PlayerScreenState extends State<PlayerScreen> {',
                            'class _PlayerScreenState extends State<_MpvPlayerScreen> {', 1)

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
    final useNativeMedia3 =
        _androidTvBuild &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        isLiveContent;

    if (useNativeMedia3) {
      return AndroidMedia3PlayerScreen(
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
    ANDROID_SCREEN.write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

const String _media3DefaultUserAgent =
    'Mozilla/5.0 (Linux; Android 10; Android TV) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/131.0.0.0 Safari/537.36';

/// Reproductor Android TV nativo basado en AndroidX Media3/ExoPlayer.
///
/// Esta pantalla se usa exclusivamente para TV en vivo en la build Android TV.
/// macOS, VOD y el resto de plataformas conservan el motor MediaKit/MPV.
class AndroidMedia3PlayerScreen extends StatefulWidget {
  final List<Channel> playlist;
  final int initialIndex;

  const AndroidMedia3PlayerScreen({
    super.key,
    required this.playlist,
    required this.initialIndex,
  });

  @override
  State<AndroidMedia3PlayerScreen> createState() =>
      _AndroidMedia3PlayerScreenState();
}

class _AndroidMedia3PlayerScreenState extends State<AndroidMedia3PlayerScreen> {
  late int _index;
  final FocusNode _focusNode = FocusNode(debugLabel: 'media3-tv-player');
  bool _overlayVisible = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.playlist.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Channel get _channel => widget.playlist[_index];

  Map<String, String> get _headers =>
      _channel.resolvedHttpHeaders(_media3DefaultUserAgent);

  void _previous() {
    if (widget.playlist.isEmpty) return;
    setState(() {
      _index = (_index - 1 + widget.playlist.length) % widget.playlist.length;
      _overlayVisible = true;
    });
  }

  void _next() {
    if (widget.playlist.isEmpty) return;
    setState(() {
      _index = (_index + 1) % widget.playlist.length;
      _overlayVisible = true;
    });
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
    _focusNode.dispose();
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
              AndroidView(
                key: ValueKey('media3-${_index}-${channel.url}'),
                viewType: 'tvfull/media3_player',
                creationParams: <String, Object?>{
                  'url': channel.url,
                  'headers': _headers,
                  'title': channel.name,
                  'isLive': true,
                },
                creationParamsCodec: const StandardMessageCodec(),
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
                                    const Text(
                                      'MEDIA3 · MEDIACODEC + FFMPEG FALLBACK',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white60,
                                        letterSpacing: 0.7,
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
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xFFB71C1C),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(20),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  child: Text(
                                    'EN VIVO',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
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
        "1.0.0+1-android-tv-media3-hotplayer-v5",
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
        'applicationId = "com.tvfull.pro.tv.v5media3"',
    )
    deps = '''\n\ndependencies {\n    implementation("androidx.media3:media3-exoplayer:1.8.0")\n    implementation("androidx.media3:media3-exoplayer-hls:1.8.0")\n    implementation("androidx.media3:media3-ui:1.8.0")\n    implementation("io.github.anilbeesetti:nextlib-media3ext:1.8.0-0.9.0")\n}\n'''
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
    m = m.replace('android:label="iptv_player"', 'android:label="TV FULL PRO V5 MEDIA3"')
    if 'android:usesCleartextTraffic=' not in m:
        m = m.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
    if 'android:banner=' not in m:
        m = m.replace(
            'android:label="TV FULL PRO V5 MEDIA3"',
            'android:label="TV FULL PRO V5 MEDIA3"\n        android:banner="@mipmap/ic_launcher"',
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

    native = f'''{package_line}\n\nimport android.content.Context\nimport android.util.Log\nimport android.view.View\nimport androidx.media3.common.AudioAttributes\nimport androidx.media3.common.C\nimport androidx.media3.common.MediaItem\nimport androidx.media3.common.PlaybackException\nimport androidx.media3.common.Player\nimport androidx.media3.common.VideoSize\nimport androidx.media3.common.util.UnstableApi\nimport androidx.media3.datasource.DefaultHttpDataSource\nimport androidx.media3.exoplayer.DefaultLoadControl\nimport androidx.media3.exoplayer.DefaultRenderersFactory\nimport androidx.media3.exoplayer.ExoPlayer\nimport androidx.media3.exoplayer.source.DefaultMediaSourceFactory\nimport androidx.media3.ui.AspectRatioFrameLayout\nimport androidx.media3.ui.PlayerView\nimport io.flutter.embedding.android.FlutterActivity\nimport io.flutter.embedding.engine.FlutterEngine\nimport io.flutter.plugin.common.MessageCodec\nimport io.flutter.plugin.common.StandardMessageCodec\nimport io.flutter.plugin.platform.PlatformView\nimport io.flutter.plugin.platform.PlatformViewFactory\nimport io.github.anilbeesetti.nextlib.media3ext.ffdecoder.NextRenderersFactory\n\nclass MainActivity : FlutterActivity() {{\n    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{\n        super.configureFlutterEngine(flutterEngine)\n        flutterEngine.platformViewsController.registry.registerViewFactory(\n            "tvfull/media3_player",\n            TvFullMedia3Factory()\n        )\n    }}\n}}\n\nprivate class TvFullMedia3Factory :\n    PlatformViewFactory(StandardMessageCodec.INSTANCE as MessageCodec<Any>) {{\n    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {{\n        @Suppress("UNCHECKED_CAST")\n        val params = args as? Map<String, Any?> ?: emptyMap()\n        return TvFullMedia3View(context, params)\n    }}\n}}\n\n@UnstableApi\nprivate class TvFullMedia3View(\n    context: Context,\n    params: Map<String, Any?>,\n) : PlatformView, Player.Listener {{\n    companion object {{\n        private const val TAG = "TVFULL-MEDIA3"\n        private const val DEFAULT_UA = "{DEFAULT_UA}"\n    }}\n\n    private val playerView = PlayerView(context)\n    private val player: ExoPlayer\n    private var endedRecoveries = 0\n\n    init {{\n        val url = params["url"]?.toString()?.trim().orEmpty()\n        @Suppress("UNCHECKED_CAST")\n        val rawHeaders = params["headers"] as? Map<Any?, Any?> ?: emptyMap()\n        val headers = LinkedHashMap<String, String>()\n        rawHeaders.forEach {{ (k, v) ->\n            val key = k?.toString()?.trim().orEmpty()\n            val value = v?.toString()?.trim().orEmpty()\n            if (key.isNotEmpty() && value.isNotEmpty()) headers[key] = value\n        }}\n        val userAgent = headers.entries\n            .firstOrNull {{ it.key.equals("User-Agent", ignoreCase = true) }}\n            ?.value ?: DEFAULT_UA\n        headers.keys.firstOrNull {{ it.equals("User-Agent", ignoreCase = true) }}?.let {{\n            headers.remove(it)\n        }}\n\n        val httpFactory = DefaultHttpDataSource.Factory()\n            .setUserAgent(userAgent)\n            .setAllowCrossProtocolRedirects(true)\n        if (headers.isNotEmpty()) {{\n            httpFactory.setDefaultRequestProperties(headers)\n        }}\n\n        // Igual que el motor Media3 encontrado en Hot Player:\n        // MediaCodec primero, fallback de decoder habilitado y FFmpeg/NextLib\n        // como renderer de extension despues de los renderers nativos.\n        val renderersFactory = NextRenderersFactory(context)\n            .setEnableDecoderFallback(true)\n            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)\n\n        // Valores observados en Hot Player 2.2.5: 5s / 15s / 2.5s / 1s.\n        val loadControl = DefaultLoadControl.Builder()\n            .setBufferDurationsMs(5000, 15000, 2500, 1000)\n            .build()\n\n        val mediaSourceFactory = DefaultMediaSourceFactory(httpFactory)\n        player = ExoPlayer.Builder(context, renderersFactory)\n            .setLoadControl(loadControl)\n            .setMediaSourceFactory(mediaSourceFactory)\n            .build()\n\n        player.setAudioAttributes(\n            AudioAttributes.Builder()\n                .setUsage(C.USAGE_MEDIA)\n                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)\n                .build(),\n            true,\n        )\n        player.addListener(this)\n\n        playerView.player = player\n        playerView.useController = false\n        playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT\n        playerView.keepScreenOn = true\n        playerView.setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)\n\n        if (url.isNotEmpty()) {{\n            Log.i(TAG, "open host=" + runCatching {{ java.net.URI(url).host }}.getOrNull())\n            player.setMediaItem(MediaItem.fromUri(url))\n            player.prepare()\n            player.playWhenReady = true\n        }} else {{\n            Log.e(TAG, "URL vacia")\n        }}\n    }}\n\n    override fun getView(): View = playerView\n\n    override fun dispose() {{\n        player.removeListener(this)\n        playerView.player = null\n        player.release()\n    }}\n\n    override fun onVideoSizeChanged(videoSize: VideoSize) {{\n        Log.i(TAG, "video=" + videoSize.width + "x" + videoSize.height)\n    }}\n\n    override fun onPlayerError(error: PlaybackException) {{\n        Log.e(TAG, "playerError=" + error.errorCodeName + " " + error.message)\n    }}\n\n    override fun onPlaybackStateChanged(playbackState: Int) {{\n        when (playbackState) {{\n            Player.STATE_READY -> {{\n                endedRecoveries = 0\n                Log.i(TAG, "STATE_READY")\n            }}\n            Player.STATE_BUFFERING -> Log.i(TAG, "STATE_BUFFERING")\n            Player.STATE_ENDED -> {{\n                Log.w(TAG, "STATE_ENDED")\n                if (endedRecoveries < 1) {{\n                    endedRecoveries++\n                    player.seekToDefaultPosition()\n                    player.prepare()\n                    player.playWhenReady = true\n                }}\n            }}\n        }}\n    }}\n}}\n'''
    main.write_text(native)


def validate():
    p = PLAYER.read_text()
    checks = [
        'class PlayerScreen extends StatelessWidget',
        'class _MpvPlayerScreen extends StatefulWidget',
        'AndroidMedia3PlayerScreen(',
    ]
    for check in checks:
        if check not in p:
            raise SystemExit(f'Falta marcador Dart: {check}')
    g = (ROOT / 'android/app/build.gradle.kts').read_text()
    for check in [
        'media3-exoplayer:1.8.0',
        'media3-exoplayer-hls:1.8.0',
        'nextlib-media3ext:1.8.0-0.9.0',
        'com.tvfull.pro.tv.v5media3',
    ]:
        if check not in g:
            raise SystemExit(f'Falta marcador Android: {check}')


patch_player_wrapper()
write_android_screen()
patch_remote_version()
patch_android_project()
validate()
print('Android Media3 HotPlayer-style V5 aplicado correctamente.')
