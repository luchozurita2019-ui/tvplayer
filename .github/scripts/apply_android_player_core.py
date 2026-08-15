from pathlib import Path

ROOT = Path('.')
PLAYER = ROOT / 'lib/screens/player_screen.dart'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'
LAUNCHER = ROOT / 'lib/screens/android_player_core_launcher.dart'
APP_GRADLE = ROOT / 'android/app/build.gradle.kts'
MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'
KOTLIN_DIR = ROOT / 'android/app/src/main/kotlin/com/example/iptv_player'
MAIN_ACTIVITY = KOTLIN_DIR / 'MainActivity.kt'
CONTRACT = KOTLIN_DIR / 'PlayerCoreContract.kt'
MEDIA3_ENGINE = KOTLIN_DIR / 'Media3PlaybackEngine.kt'
NATIVE_ENGINE = KOTLIN_DIR / 'AndroidMediaPlaybackEngine.kt'
DIAGNOSTICS = KOTLIN_DIR / 'PlaybackDiagnostics.kt'
NATIVE_ACTIVITY = KOTLIN_DIR / 'TvFullPlayerCoreActivity.kt'


def patch_player_router():
    text = PLAYER.read_text()
    marker_import = "import '../widgets/live_video_view.dart';"
    if "import 'android_player_core_launcher.dart';" not in text:
        if marker_import not in text:
            raise SystemExit('No se encontro import de live_video_view.dart')
        text = text.replace(marker_import, marker_import + "\nimport 'android_player_core_launcher.dart';", 1)

    if 'class _MpvPlayerScreen extends StatefulWidget' not in text:
        text = text.replace('class PlayerScreen extends StatefulWidget {', 'class _MpvPlayerScreen extends StatefulWidget {', 1)
        text = text.replace('  const PlayerScreen({', '  const _MpvPlayerScreen({', 1)
        text = text.replace('  State<PlayerScreen> createState() => _PlayerScreenState();', '  State<_MpvPlayerScreen> createState() => _MpvPlayerScreenState();', 1)
        text = text.replace('class _PlayerScreenState extends State<PlayerScreen> {', 'class _MpvPlayerScreenState extends State<_MpvPlayerScreen> {', 1)

    if 'class PlayerScreen extends StatefulWidget' not in text:
        marker = 'class _MpvPlayerScreen extends StatefulWidget {'
        wrapper = r'''class PlayerScreen extends StatefulWidget {
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
  State<PlayerScreen> createState() => _PlayerScreenRouterState();
}

class _PlayerScreenRouterState extends State<PlayerScreen> {
  late int _index;
  bool _forceMpv = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.playlist.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final useNativeCore =
        !_forceMpv &&
        _androidTvBuild &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        widget.isLiveContent &&
        widget.playlist.isNotEmpty;

    if (useNativeCore) {
      return AndroidPlayerCoreLauncher(
        playlist: widget.playlist,
        initialIndex: _index,
        onFallbackToMpv: (index) {
          if (!mounted) return;
          setState(() {
            _index = index.clamp(0, widget.playlist.length - 1);
            _forceMpv = true;
          });
        },
      );
    }

    final channel = widget.playlist.isEmpty ? widget.channel : widget.playlist[_index];
    return _MpvPlayerScreen(
      channel: channel,
      playlist: widget.playlist,
      initialIndex: _index,
      settings: widget.settings,
      isLiveContent: widget.isLiveContent,
    );
  }
}

'''
        if marker not in text:
            raise SystemExit('No se encontro _MpvPlayerScreen')
        text = text.replace(marker, wrapper + marker, 1)

    PLAYER.write_text(text)


def write_launcher():
    LAUNCHER.write_text(r'''import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';

const String _playerCoreDefaultUserAgent =
    'Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class AndroidPlayerCoreLauncher extends StatefulWidget {
  final List<Channel> playlist;
  final int initialIndex;
  final ValueChanged<int> onFallbackToMpv;

  const AndroidPlayerCoreLauncher({
    super.key,
    required this.playlist,
    required this.initialIndex,
    required this.onFallbackToMpv,
  });

  @override
  State<AndroidPlayerCoreLauncher> createState() => _AndroidPlayerCoreLauncherState();
}

class _AndroidPlayerCoreLauncherState extends State<AndroidPlayerCoreLauncher> {
  static const MethodChannel _channel = MethodChannel('tvfull/player_core');
  bool _launched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  Future<void> _launch() async {
    if (_launched || widget.playlist.isEmpty) return;
    _launched = true;
    try {
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/tvfull_player_core_playlist.json');
      final payload = <String, Object?>{
        'channels': widget.playlist
            .map(
              (item) => <String, Object?>{
                'name': item.name,
                'url': item.url,
                'headers': item.resolvedHttpHeaders(_playerCoreDefaultUserAgent),
              },
            )
            .toList(growable: false),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);

      final result = await _channel.invokeMapMethod<String, Object?>('open', <String, Object?>{
        'playlistPath': file.path,
        'initialIndex': widget.initialIndex,
      });
      if (!mounted) return;
      final action = result?['action']?.toString() ?? 'closed';
      final index = (result?['index'] as num?)?.toInt() ?? widget.initialIndex;
      if (action == 'fallback_mpv') {
        widget.onFallbackToMpv(index);
      } else {
        Navigator.of(context).maybePop();
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? 'No se pudo abrir Player Core.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo abrir Player Core: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _error == null
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Iniciando Player Core...', style: TextStyle(color: Colors.white70)),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 14),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => widget.onFallbackToMpv(widget.initialIndex),
                      child: const Text('Usar motor MPV'),
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
    text = REMOTE.read_text()
    candidates = [
        '1.0.0+1-android-tv-panel-v3-native-hw',
        '1.0.0+1-android-tv-native-multiplayer-v6',
    ]
    for old in candidates:
        if old in text:
            text = text.replace(old, '1.0.0+1-android-tv-player-core', 1)
            break
    REMOTE.write_text(text)


def patch_android_project():
    gradle = APP_GRADLE.read_text()
    if 'dependencies {' not in gradle:
        gradle += '\n\ndependencies {\n}\n'
    dependencies = (
        '    implementation("androidx.media3:media3-exoplayer:1.10.1")\n'
        '    implementation("androidx.media3:media3-exoplayer-hls:1.10.1")\n'
        '    implementation("io.github.anilbeesetti:nextlib-media3ext:1.10.1-0.13.0")\n'
    )
    if 'androidx.media3:media3-exoplayer:1.10.1' not in gradle:
        gradle = gradle.replace('dependencies {\n', 'dependencies {\n' + dependencies, 1)
    gradle = gradle.replace('applicationId = "com.example.iptv_player"', 'applicationId = "com.tvfull.pro.tv.playercore"')
    APP_GRADLE.write_text(gradle)

    manifest = MANIFEST.read_text()
    if 'android.permission.INTERNET' not in manifest:
        end = manifest.find('>')
        manifest = manifest[:end + 1] + (
            '\n    <uses-permission android:name="android.permission.INTERNET" />'
            '\n    <uses-feature android:name="android.software.leanback" android:required="true" />'
            '\n    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />'
            '\n    <uses-feature android:name="android.hardware.faketouch" android:required="false" />'
        ) + manifest[end + 1:]
    manifest = manifest.replace('android:label="iptv_player"', 'android:label="TV FULL PRO PLAYER CORE"')
    if 'android:usesCleartextTraffic' not in manifest:
        manifest = manifest.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
    if 'android:banner=' not in manifest:
        manifest = manifest.replace(
            'android:label="TV FULL PRO PLAYER CORE"',
            'android:label="TV FULL PRO PLAYER CORE"\n        android:banner="@mipmap/ic_launcher"',
            1,
        )
    if 'android:screenOrientation=' not in manifest:
        manifest = manifest.replace('android:name=".MainActivity"', 'android:name=".MainActivity"\n            android:screenOrientation="landscape"', 1)
    if 'android.intent.category.LEANBACK_LAUNCHER' not in manifest:
        manifest = manifest.replace(
            '<category android:name="android.intent.category.LAUNCHER"/>',
            '<category android:name="android.intent.category.LAUNCHER"/>\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
            1,
        )
    if 'TvFullPlayerCoreActivity' not in manifest:
        activity = '''\n        <activity\n            android:name="com.example.iptv_player.TvFullPlayerCoreActivity"\n            android:exported="false"\n            android:screenOrientation="landscape"\n            android:configChanges="keyboard|keyboardHidden|orientation|screenSize|smallestScreenSize|uiMode"\n            android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen" />\n'''
        manifest = manifest.replace('</application>', activity + '    </application>', 1)
    MANIFEST.write_text(manifest)


def write_main_activity():
    KOTLIN_DIR.mkdir(parents=True, exist_ok=True)
    MAIN_ACTIVITY.write_text(r'''package com.example.iptv_player

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "tvfull/player_core"
        private const val REQUEST_PLAYER = 4711
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> openPlayer(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openPlayer(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("player_busy", "Player Core ya esta abierto", null)
            return
        }
        val args = call.arguments as? Map<*, *>
        val path = args?.get("playlistPath")?.toString()?.trim().orEmpty()
        val index = (args?.get("initialIndex") as? Number)?.toInt() ?: 0
        if (path.isEmpty()) {
            result.error("missing_playlist", "No se recibio playlistPath", null)
            return
        }
        pendingResult = result
        val intent = Intent(this, TvFullPlayerCoreActivity::class.java)
            .putExtra("playlistPath", path)
            .putExtra("initialIndex", index)
        startActivityForResult(intent, REQUEST_PLAYER)
    }

    @Deprecated("Deprecated in Android API; kept for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PLAYER) return
        val result = pendingResult ?: return
        pendingResult = null
        result.success(
            mapOf(
                "action" to (data?.getStringExtra("action") ?: "closed"),
                "index" to data?.getIntExtra("index", 0),
                "reason" to data?.getStringExtra("reason"),
            )
        )
    }
}
''')


def write_contract():
    CONTRACT.write_text(r'''package com.example.iptv_player

import android.view.Surface

data class CoreChannel(
    val name: String,
    val url: String,
    val headers: Map<String, String>,
)

enum class CoreEngineId(val label: String) {
    MEDIA3("MEDIA3 / MEDIACODEC"),
    NATIVE("ANDROID MEDIAPLAYER"),
}

data class CoreEngineSnapshot(
    val engine: CoreEngineId,
    val decoder: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val droppedFrames: Int = 0,
    val bufferedMs: Long? = null,
    val isPlaying: Boolean = false,
)

interface CoreEngineObserver {
    fun onFirstFrame(engine: CoreEngineId)
    fun onFatalError(engine: CoreEngineId, reason: String)
    fun onDroppedFrames(engine: CoreEngineId, count: Int, elapsedMs: Long)
    fun onSnapshot(snapshot: CoreEngineSnapshot)
}

interface CorePlaybackEngine {
    val id: CoreEngineId
    fun start(channel: CoreChannel, surface: Surface, observer: CoreEngineObserver)
    fun stop()
    fun snapshot(): CoreEngineSnapshot
}
''')


def write_diagnostics():
    DIAGNOSTICS.write_text(r'''package com.example.iptv_player

import android.content.Context
import android.os.Build
import android.util.Log
import org.json.JSONObject
import java.io.File

class PlaybackDiagnostics(private val context: Context) {
    private val file: File by lazy { File(context.filesDir, "tvfull-player-diagnostics.jsonl") }

    @Synchronized
    fun event(name: String, fields: Map<String, Any?> = emptyMap()) {
        try {
            val json = JSONObject()
            json.put("ts", System.currentTimeMillis())
            json.put("event", name)
            json.put("sdk", Build.VERSION.SDK_INT)
            json.put("device", Build.DEVICE)
            json.put("model", Build.MODEL)
            json.put("abi", Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")
            fields.forEach { (key, value) -> json.put(key, value) }
            file.appendText(json.toString() + "\n")
            Log.i("TVFULL-PLAYER", json.toString())
        } catch (error: Throwable) {
            Log.w("TVFULL-PLAYER", "diagnostic write failed", error)
        }
    }
}
''')


def write_media3_engine():
    MEDIA3_ENGINE.write_text(r'''package com.example.iptv_player

import android.content.Context
import android.view.Surface
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.NextRenderersFactory

@OptIn(UnstableApi::class)
class Media3PlaybackEngine(private val context: Context) : CorePlaybackEngine {
    override val id = CoreEngineId.MEDIA3
    private var player: ExoPlayer? = null
    private var observer: CoreEngineObserver? = null
    private var decoder: String? = null
    private var width: Int? = null
    private var height: Int? = null
    private var dropped = 0

    override fun start(channel: CoreChannel, surface: Surface, observer: CoreEngineObserver) {
        stop()
        this.observer = observer
        decoder = null
        width = null
        height = null
        dropped = 0

        val renderersFactory = NextRenderersFactory(context)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(3000, 12000, 800, 1200)
            .build()

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(8000)
            .setReadTimeoutMs(15000)
            .setDefaultRequestProperties(channel.headers)
        val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

        val exo = ExoPlayer.Builder(context, renderersFactory)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
        player = exo
        exo.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            true,
        )
        exo.setVideoSurface(surface)
        exo.addListener(object : Player.Listener {
            override fun onRenderedFirstFrame() {
                observer.onFirstFrame(id)
                publishSnapshot()
            }

            override fun onPlayerError(error: PlaybackException) {
                observer.onFatalError(id, "${error.errorCodeName}: ${error.message ?: "player error"}")
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                width = videoSize.width.takeIf { it > 0 }
                height = videoSize.height.takeIf { it > 0 }
                publishSnapshot()
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                publishSnapshot()
            }
        })
        exo.addAnalyticsListener(object : AnalyticsListener {
            override fun onDroppedVideoFrames(eventTime: AnalyticsListener.EventTime, droppedFrames: Int, elapsedMs: Long) {
                dropped += droppedFrames
                observer.onDroppedFrames(id, droppedFrames, elapsedMs)
                publishSnapshot()
            }

            override fun onVideoDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long,
            ) {
                decoder = decoderName
                publishSnapshot()
            }

            override fun onVideoCodecError(eventTime: AnalyticsListener.EventTime, videoCodecError: Exception) {
                observer.onFatalError(id, "codec: ${videoCodecError.message ?: videoCodecError.javaClass.simpleName}")
            }
        })
        exo.setMediaItem(MediaItem.fromUri(channel.url))
        exo.prepare()
        exo.playWhenReady = true
    }

    private fun publishSnapshot() {
        observer?.onSnapshot(snapshot())
    }

    override fun snapshot(): CoreEngineSnapshot {
        val exo = player
        val buffered = if (exo == null) null else (exo.bufferedPosition - exo.currentPosition).coerceAtLeast(0L)
        return CoreEngineSnapshot(
            engine = id,
            decoder = decoder,
            width = width,
            height = height,
            droppedFrames = dropped,
            bufferedMs = buffered,
            isPlaying = exo?.isPlaying == true,
        )
    }

    override fun stop() {
        player?.release()
        player = null
        observer = null
    }
}
''')


def write_native_engine():
    NATIVE_ENGINE.write_text(r'''package com.example.iptv_player

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.view.Surface

class AndroidMediaPlaybackEngine(private val context: Context) : CorePlaybackEngine {
    override val id = CoreEngineId.NATIVE
    private var player: MediaPlayer? = null
    private var observer: CoreEngineObserver? = null
    private var width: Int? = null
    private var height: Int? = null
    private var firstFrame = false

    override fun start(channel: CoreChannel, surface: Surface, observer: CoreEngineObserver) {
        stop()
        this.observer = observer
        firstFrame = false
        val mediaPlayer = MediaPlayer()
        player = mediaPlayer
        mediaPlayer.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()
        )
        mediaPlayer.setSurface(surface)
        mediaPlayer.setScreenOnWhilePlaying(true)
        mediaPlayer.setOnPreparedListener {
            width = it.videoWidth.takeIf { value -> value > 0 }
            height = it.videoHeight.takeIf { value -> value > 0 }
            it.start()
            publishSnapshot()
        }
        mediaPlayer.setOnVideoSizeChangedListener { _, w, h ->
            width = w.takeIf { it > 0 }
            height = h.takeIf { it > 0 }
            publishSnapshot()
        }
        mediaPlayer.setOnInfoListener { _, what, _ ->
            if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START && !firstFrame) {
                firstFrame = true
                observer.onFirstFrame(id)
                publishSnapshot()
            }
            false
        }
        mediaPlayer.setOnErrorListener { _, what, extra ->
            observer.onFatalError(id, "MediaPlayer error what=$what extra=$extra")
            true
        }
        try {
            mediaPlayer.setDataSource(context, Uri.parse(channel.url), channel.headers)
            mediaPlayer.prepareAsync()
        } catch (error: Throwable) {
            observer.onFatalError(id, error.message ?: error.javaClass.simpleName)
        }
    }

    private fun publishSnapshot() {
        observer?.onSnapshot(snapshot())
    }

    override fun snapshot() = CoreEngineSnapshot(
        engine = id,
        decoder = "Android MediaPlayer",
        width = width,
        height = height,
        droppedFrames = 0,
        bufferedMs = null,
        isPlaying = player?.isPlaying == true,
    )

    override fun stop() {
        try { player?.reset() } catch (_: Throwable) {}
        try { player?.release() } catch (_: Throwable) {}
        player = null
        observer = null
    }
}
''')


def write_native_activity():
    NATIVE_ACTIVITY.write_text(r'''package com.example.iptv_player

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import org.json.JSONObject
import java.io.File

class TvFullPlayerCoreActivity : Activity(), SurfaceHolder.Callback, CoreEngineObserver {
    private val handler = Handler(Looper.getMainLooper())
    private val diagnostics by lazy { PlaybackDiagnostics(this) }
    private lateinit var surfaceView: SurfaceView
    private lateinit var titleView: TextView
    private lateinit var engineView: TextView
    private lateinit var statsView: TextView
    private lateinit var errorView: TextView
    private lateinit var spinner: ProgressBar
    private lateinit var overlay: LinearLayout

    private var channels: List<CoreChannel> = emptyList()
    private var currentIndex = 0
    private var currentEngine: CorePlaybackEngine? = null
    private var currentEngineId = CoreEngineId.MEDIA3
    private var currentSurface: Surface? = null
    private var generation = 0
    private var firstFrameSeen = false
    private var badDropWindows = 0
    private var media3Failed = false
    private var nativeFailed = false
    private var overlayVisible = true
    private var lastFallbackReason: String? = null
    private var latestSnapshot = CoreEngineSnapshot(CoreEngineId.MEDIA3)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        hideSystemUi()
        buildUi()
        surfaceView.holder.addCallback(this)
        loadPlaylistAsync()
    }

    override fun onResume() {
        super.onResume()
        hideSystemUi()
    }

    private fun loadPlaylistAsync() {
        spinner.visibility = View.VISIBLE
        val path = intent.getStringExtra("playlistPath").orEmpty()
        val requested = intent.getIntExtra("initialIndex", 0)
        Thread {
            try {
                val root = JSONObject(File(path).readText())
                val array = root.getJSONArray("channels")
                val parsed = ArrayList<CoreChannel>(array.length())
                for (i in 0 until array.length()) {
                    val item = array.getJSONObject(i)
                    val url = item.optString("url").trim()
                    if (url.isEmpty()) continue
                    val headersJson = item.optJSONObject("headers")
                    val headers = linkedMapOf<String, String>()
                    if (headersJson != null) {
                        val keys = headersJson.keys()
                        while (keys.hasNext()) {
                            val key = keys.next()
                            val value = headersJson.optString(key).trim()
                            if (key.isNotBlank() && value.isNotBlank()) headers[key] = value
                        }
                    }
                    parsed.add(CoreChannel(item.optString("name", "Canal"), url, headers))
                }
                runOnUiThread {
                    channels = parsed
                    if (channels.isEmpty()) {
                        failToMpv("playlist vacia")
                        return@runOnUiThread
                    }
                    currentIndex = requested.coerceIn(0, channels.lastIndex)
                    spinner.visibility = View.GONE
                    updateOverlay()
                    if (currentSurface != null) playCurrent(CoreEngineId.MEDIA3, "startup")
                }
            } catch (error: Throwable) {
                runOnUiThread { failToMpv("playlist: ${error.message ?: error.javaClass.simpleName}") }
            }
        }.start()
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        currentSurface = holder.surface
        if (channels.isNotEmpty()) playCurrent(CoreEngineId.MEDIA3, "surface_created")
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        currentSurface = holder.surface
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        currentSurface = null
        releaseEngine()
    }

    private fun playCurrent(engineId: CoreEngineId, reason: String) {
        val surface = currentSurface ?: return
        if (channels.isEmpty()) return
        generation += 1
        val myGeneration = generation
        firstFrameSeen = false
        badDropWindows = 0
        errorView.text = ""
        spinner.visibility = View.VISIBLE
        releaseEngine()
        currentEngineId = engineId
        val channel = channels[currentIndex]
        currentEngine = when (engineId) {
            CoreEngineId.MEDIA3 -> Media3PlaybackEngine(this)
            CoreEngineId.NATIVE -> AndroidMediaPlaybackEngine(this)
        }
        diagnostics.event("engine_start", mapOf("engine" to engineId.name, "channel" to channel.name, "reason" to reason))
        updateOverlay()
        try {
            currentEngine?.start(channel, surface, this)
        } catch (error: Throwable) {
            onFatalError(engineId, error.message ?: error.javaClass.simpleName)
            return
        }
        handler.postDelayed({
            if (myGeneration != generation || firstFrameSeen) return@postDelayed
            diagnostics.event("first_frame_timeout", mapOf("engine" to engineId.name, "channel" to channel.name))
            handleEngineFailure(engineId, "sin primer frame en 8 s")
        }, 8000)
    }

    override fun onFirstFrame(engine: CoreEngineId) {
        if (engine != currentEngineId) return
        firstFrameSeen = true
        spinner.visibility = View.GONE
        diagnostics.event("first_frame", mapOf("engine" to engine.name, "channel" to channels[currentIndex].name))
        updateOverlay()
    }

    override fun onFatalError(engine: CoreEngineId, reason: String) {
        if (engine != currentEngineId) return
        diagnostics.event("engine_error", mapOf("engine" to engine.name, "reason" to reason, "channel" to channels[currentIndex].name))
        handleEngineFailure(engine, reason)
    }

    override fun onDroppedFrames(engine: CoreEngineId, count: Int, elapsedMs: Long) {
        if (engine != CoreEngineId.MEDIA3 || currentEngineId != engine) return
        if (elapsedMs <= 5000 && count >= 10) badDropWindows++ else badDropWindows = 0
        if (badDropWindows >= 2 && !nativeFailed) {
            diagnostics.event("severe_dropped_frames", mapOf("count" to count, "elapsedMs" to elapsedMs))
            handleEngineFailure(engine, "caida severa de frames")
        }
    }

    override fun onSnapshot(snapshot: CoreEngineSnapshot) {
        if (snapshot.engine != currentEngineId) return
        latestSnapshot = snapshot
        updateOverlay()
    }

    private fun handleEngineFailure(engine: CoreEngineId, reason: String) {
        lastFallbackReason = reason
        when (engine) {
            CoreEngineId.MEDIA3 -> {
                media3Failed = true
                if (!nativeFailed) playCurrent(CoreEngineId.NATIVE, reason) else failToMpv(reason)
            }
            CoreEngineId.NATIVE -> {
                nativeFailed = true
                if (!media3Failed) playCurrent(CoreEngineId.MEDIA3, reason) else failToMpv(reason)
            }
        }
    }

    private fun failToMpv(reason: String) {
        diagnostics.event("fallback_mpv", mapOf("reason" to reason, "index" to currentIndex))
        setResult(RESULT_OK, Intent().putExtra("action", "fallback_mpv").putExtra("index", currentIndex).putExtra("reason", reason))
        finish()
    }

    private fun previousChannel() {
        if (channels.isEmpty()) return
        currentIndex = (currentIndex - 1 + channels.size) % channels.size
        resetChannelHealth()
        playCurrent(CoreEngineId.MEDIA3, "channel_previous")
    }

    private fun nextChannel() {
        if (channels.isEmpty()) return
        currentIndex = (currentIndex + 1) % channels.size
        resetChannelHealth()
        playCurrent(CoreEngineId.MEDIA3, "channel_next")
    }

    private fun resetChannelHealth() {
        media3Failed = false
        nativeFailed = false
        badDropWindows = 0
        lastFallbackReason = null
    }

    private fun toggleEngine() {
        if (channels.isEmpty()) return
        val next = if (currentEngineId == CoreEngineId.MEDIA3) CoreEngineId.NATIVE else CoreEngineId.MEDIA3
        playCurrent(next, "manual_switch")
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_CHANNEL_UP -> { previousChannel(); return true }
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_CHANNEL_DOWN -> { nextChannel(); return true }
            KeyEvent.KEYCODE_DPAD_UP -> { toggleEngine(); return true }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                overlayVisible = !overlayVisible
                overlay.visibility = if (overlayVisible) View.VISIBLE else View.GONE
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    @Deprecated("Deprecated in Android API; used for TV remote compatibility")
    override fun onBackPressed() {
        setResult(RESULT_OK, Intent().putExtra("action", "closed").putExtra("index", currentIndex))
        finish()
    }

    private fun releaseEngine() {
        try { currentEngine?.stop() } catch (_: Throwable) {}
        currentEngine = null
    }

    override fun onDestroy() {
        generation += 1
        handler.removeCallbacksAndMessages(null)
        releaseEngine()
        super.onDestroy()
    }

    private fun buildUi() {
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        surfaceView = SurfaceView(this)
        root.addView(surfaceView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        spinner = ProgressBar(this)
        root.addView(spinner, FrameLayout.LayoutParams(72, 72, Gravity.CENTER))

        overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 18, 24, 18)
            setBackgroundColor(0xCC101722.toInt())
        }
        titleView = TextView(this).apply { setTextColor(Color.WHITE); textSize = 20f }
        engineView = TextView(this).apply { setTextColor(0xFF81D4FA.toInt()); textSize = 13f }
        statsView = TextView(this).apply { setTextColor(0xFFCCCCCC.toInt()); textSize = 12f }
        errorView = TextView(this).apply { setTextColor(0xFFFF8A80.toInt()); textSize = 12f }
        overlay.addView(titleView)
        overlay.addView(engineView)
        overlay.addView(statsView)
        overlay.addView(errorView)
        val params = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP)
        params.setMargins(20, 20, 20, 0)
        root.addView(overlay, params)
        setContentView(root)
    }

    private fun updateOverlay() {
        if (!::titleView.isInitialized) return
        val channel = channels.getOrNull(currentIndex)
        titleView.text = channel?.let { "${currentIndex + 1}/${channels.size}  ${it.name}" } ?: "Player Core"
        engineView.text = "${currentEngineId.label}${latestSnapshot.decoder?.let { " · $it" } ?: ""}"
        val resolution = if (latestSnapshot.width != null && latestSnapshot.height != null) "${latestSnapshot.width}x${latestSnapshot.height}" else "resolucion ?"
        val buffer = latestSnapshot.bufferedMs?.let { "buffer ${it}ms" } ?: "buffer ?"
        statsView.text = "$resolution · $buffer · dropped ${latestSnapshot.droppedFrames} · ↑ cambia motor · ←/→ canal · OK info"
        errorView.text = lastFallbackReason?.let { "Ultimo fallback: $it" } ?: ""
    }

    private fun hideSystemUi() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
    }
}
''')


def main():
    patch_player_router()
    write_launcher()
    patch_remote_version()
    patch_android_project()
    write_main_activity()
    write_contract()
    write_diagnostics()
    write_media3_engine()
    write_native_engine()
    write_native_activity()
    print('Android TV Player Core aplicado correctamente.')


if __name__ == '__main__':
    main()
