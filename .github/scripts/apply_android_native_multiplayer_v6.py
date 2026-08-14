from pathlib import Path

ROOT = Path('.')
PLAYER = ROOT / 'lib/screens/player_screen.dart'
REMOTE = ROOT / 'lib/services/remote_provisioning_service.dart'
LAUNCHER = ROOT / 'lib/screens/android_native_player_launcher.dart'
APP_GRADLE = ROOT / 'android/app/build.gradle.kts'
MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'
KOTLIN_DIR = ROOT / 'android/app/src/main/kotlin/com/example/iptv_player'
MAIN_ACTIVITY = KOTLIN_DIR / 'MainActivity.kt'
NATIVE_ACTIVITY = KOTLIN_DIR / 'TvFullNativePlayerActivity.kt'


def patch_player_wrapper():
    text = PLAYER.read_text()
    if "import 'android_native_player_launcher.dart';" not in text:
        marker = "import '../widgets/live_video_view.dart';"
        if marker not in text:
            raise SystemExit('No se encontro import de live_video_view.dart')
        text = text.replace(marker, marker + "\nimport 'android_native_player_launcher.dart';", 1)

    if 'class _MpvPlayerScreen extends StatefulWidget' not in text:
        if 'class PlayerScreen extends StatefulWidget {' not in text:
            raise SystemExit('No se encontro PlayerScreen original')
        text = text.replace(
            'class PlayerScreen extends StatefulWidget {',
            'class _MpvPlayerScreen extends StatefulWidget {',
            1,
        )
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
    final useNativeAndroidPlayer =
        _androidTvBuild &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        isLiveContent;

    if (useNativeAndroidPlayer) {
      return AndroidNativePlayerLauncher(
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


def write_launcher():
    LAUNCHER.write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

const String _nativePlayerDefaultUserAgent =
    'Mozilla/5.0 (Linux; Android 10; Android TV) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/131.0.0.0 Safari/537.36';

class AndroidNativePlayerLauncher extends StatefulWidget {
  final List<Channel> playlist;
  final int initialIndex;

  const AndroidNativePlayerLauncher({
    super.key,
    required this.playlist,
    required this.initialIndex,
  });

  @override
  State<AndroidNativePlayerLauncher> createState() =>
      _AndroidNativePlayerLauncherState();
}

class _AndroidNativePlayerLauncherState
    extends State<AndroidNativePlayerLauncher> {
  static const MethodChannel _channel = MethodChannel('tvfull/native_player');
  String? _error;
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  Future<void> _launch() async {
    if (_launched || widget.playlist.isEmpty) return;
    _launched = true;
    try {
      final channels = widget.playlist
          .map(
            (item) => <String, Object?>{
              'name': item.name,
              'url': item.url,
              'headers': item.resolvedHttpHeaders(
                _nativePlayerDefaultUserAgent,
              ),
            },
          )
          .toList(growable: false);

      await _channel.invokeMethod<bool>('open', <String, Object?>{
        'initialIndex': widget.initialIndex,
        'channels': channels,
      });

      if (mounted) Navigator.of(context).maybePop();
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message ?? 'No se pudo abrir el reproductor nativo.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo abrir el reproductor nativo: $error';
      });
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
                  Text(
                    'Abriendo reproductor nativo...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Volver'),
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
    old = '1.0.0+1-android-tv-panel-v3-native-hw'
    if old in text:
        text = text.replace(old, '1.0.0+1-android-tv-native-multiplayer-v6', 1)
    elif 'android-tv-native-multiplayer-v6' not in text:
        raise SystemExit('No se encontro app_version esperado')
    REMOTE.write_text(text)


def patch_android_project():
    gradle = APP_GRADLE.read_text()
    if 'androidx.media3:media3-exoplayer:1.8.0' not in gradle:
        if 'dependencies {' not in gradle:
            gradle += '\n\ndependencies {\n}\n'
        gradle = gradle.replace(
            'dependencies {\n',
            'dependencies {\n'
            '    implementation("androidx.media3:media3-exoplayer:1.8.0")\n'
            '    implementation("androidx.media3:media3-exoplayer-hls:1.8.0")\n'
            '    implementation("io.github.anilbeesetti:nextlib-media3ext:1.8.0-0.9.0")\n',
            1,
        )
    gradle = gradle.replace(
        'applicationId = "com.example.iptv_player"',
        'applicationId = "com.tvfull.pro.tv.v6native"',
    )
    APP_GRADLE.write_text(gradle)

    manifest = MANIFEST.read_text()
    if 'android.permission.INTERNET' not in manifest:
        end = manifest.find('>')
        features = (
            '\n    <uses-permission android:name="android.permission.INTERNET" />'
            '\n    <uses-feature android:name="android.software.leanback" android:required="true" />'
            '\n    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />'
            '\n    <uses-feature android:name="android.hardware.faketouch" android:required="false" />'
        )
        manifest = manifest[:end + 1] + features + manifest[end + 1:]
    manifest = manifest.replace(
        'android:label="iptv_player"',
        'android:label="TV FULL PRO V6 NATIVE"',
    )
    if 'android:usesCleartextTraffic' not in manifest:
        manifest = manifest.replace(
            '<application',
            '<application android:usesCleartextTraffic="true"',
            1,
        )
    if 'android:banner=' not in manifest:
        manifest = manifest.replace(
            'android:label="TV FULL PRO V6 NATIVE"',
            'android:label="TV FULL PRO V6 NATIVE"\n        android:banner="@mipmap/ic_launcher"',
            1,
        )
    if 'android:screenOrientation=' not in manifest:
        manifest = manifest.replace(
            'android:name=".MainActivity"',
            'android:name=".MainActivity"\n            android:screenOrientation="landscape"',
            1,
        )
    if 'android.intent.category.LEANBACK_LAUNCHER' not in manifest:
        manifest = manifest.replace(
            '<category android:name="android.intent.category.LAUNCHER"/>',
            '<category android:name="android.intent.category.LAUNCHER"/>\n'
            '                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
            1,
        )
    if 'TvFullNativePlayerActivity' not in manifest:
        activity = r'''
        <activity
            android:name="com.example.iptv_player.TvFullNativePlayerActivity"
            android:exported="false"
            android:screenOrientation="landscape"
            android:configChanges="keyboard|keyboardHidden|orientation|screenSize|smallestScreenSize|uiMode"
            android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen" />
'''
        manifest = manifest.replace('</application>', activity + '    </application>', 1)
    MANIFEST.write_text(manifest)


def write_main_activity():
    KOTLIN_DIR.mkdir(parents=True, exist_ok=True)
    MAIN_ACTIVITY.write_text(r'''package com.example.iptv_player

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "tvfull/native_player"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> openNativePlayer(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openNativePlayer(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *>
                ?: throw IllegalArgumentException("Argumentos invalidos")
            val rawChannels = args["channels"] as? List<*>
                ?: throw IllegalArgumentException("No se recibio la lista")
            val channels = rawChannels.mapNotNull { raw ->
                val map = raw as? Map<*, *> ?: return@mapNotNull null
                val name = map["name"]?.toString()?.trim().orEmpty()
                val url = map["url"]?.toString()?.trim().orEmpty()
                if (url.isEmpty()) return@mapNotNull null
                val headers = linkedMapOf<String, String>()
                val rawHeaders = map["headers"] as? Map<*, *>
                rawHeaders?.forEach { (key, value) ->
                    val k = key?.toString()?.trim().orEmpty()
                    val v = value?.toString()?.trim().orEmpty()
                    if (k.isNotEmpty() && v.isNotEmpty()) headers[k] = v
                }
                NativeChannel(name.ifEmpty { "Canal" }, url, headers)
            }
            if (channels.isEmpty()) {
                throw IllegalArgumentException("No hay canales reproducibles")
            }
            val requested = (args["initialIndex"] as? Number)?.toInt() ?: 0
            NativePlaybackPayloadStore.channels = channels
            NativePlaybackPayloadStore.initialIndex =
                requested.coerceIn(0, channels.lastIndex)
            startActivity(Intent(this, TvFullNativePlayerActivity::class.java))
            result.success(true)
        } catch (error: Throwable) {
            result.error("native_player_open_failed", error.message, null)
        }
    }
}
''')


def write_native_activity():
    NATIVE_ACTIVITY.write_text(r'''package com.example.iptv_player

import android.app.Activity
import android.graphics.Color
import android.media.AudioAttributes as AndroidAudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.media3.common.AudioAttributes as Media3AudioAttributes
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.NextRenderersFactory

data class NativeChannel(
    val name: String,
    val url: String,
    val headers: Map<String, String>,
)

object NativePlaybackPayloadStore {
    @Volatile var channels: List<NativeChannel> = emptyList()
    @Volatile var initialIndex: Int = 0
}

class TvFullNativePlayerActivity : Activity(), SurfaceHolder.Callback {
    private enum class Backend(val label: String) {
        NATIVE("ANDROID NATIVE"),
        MEDIA3("MEDIA3 + MEDIACODEC / FFMPEG FALLBACK"),
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var surfaceView: SurfaceView
    private lateinit var titleView: TextView
    private lateinit var backendView: TextView
    private lateinit var overlay: LinearLayout
    private lateinit var spinner: ProgressBar
    private lateinit var errorView: TextView

    private var channels: List<NativeChannel> = emptyList()
    private var currentIndex = 0
    private var backend = Backend.NATIVE
    private var nativePlayer: MediaPlayer? = null
    private var exoPlayer: ExoPlayer? = null
    private var generation = 0
    private var prepared = false
    private var overlayVisible = true
    private var fallbackReason: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        hideSystemUi()
        channels = NativePlaybackPayloadStore.channels
        if (channels.isEmpty()) {
            finish()
            return
        }
        currentIndex = NativePlaybackPayloadStore.initialIndex.coerceIn(0, channels.lastIndex)
        buildUi()
        surfaceView.holder.addCallback(this)
        updateOverlay()
    }

    override fun onResume() {
        super.onResume()
        hideSystemUi()
    }

    override fun onDestroy() {
        releasePlayers()
        handler.removeCallbacksAndMessages(null)
        if (isFinishing) NativePlaybackPayloadStore.channels = emptyList()
        super.onDestroy()
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        playCurrent(Backend.NATIVE, null)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        releasePlayers()
    }

    private fun buildUi() {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            isFocusable = true
            isFocusableInTouchMode = true
        }
        surfaceView = SurfaceView(this).apply { holder.setKeepScreenOn(true) }
        root.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        spinner = ProgressBar(this)
        root.addView(spinner, FrameLayout.LayoutParams(72, 72, Gravity.CENTER))

        overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(28, 20, 28, 20)
            setBackgroundColor(Color.argb(205, 10, 17, 28))
        }
        titleView = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 21f
        }
        backendView = TextView(this).apply {
            setTextColor(Color.rgb(100, 190, 255))
            textSize = 13f
        }
        val hint = TextView(this).apply {
            setTextColor(Color.LTGRAY)
            textSize = 12f
            text = "←/→ canal  •  ↑ cambiar motor  •  OK ocultar info"
        }
        overlay.addView(titleView)
        overlay.addView(backendView)
        overlay.addView(hint)
        root.addView(
            overlay,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP,
            ),
        )

        errorView = TextView(this).apply {
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.argb(220, 125, 0, 0))
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(28, 18, 28, 18)
            visibility = View.GONE
        }
        root.addView(
            errorView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ),
        )
        setContentView(root)
        root.requestFocus()
    }

    private fun hideSystemUi() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }

    private fun currentChannel(): NativeChannel = channels[currentIndex]

    private fun playCurrent(target: Backend, reason: String?) {
        if (!surfaceView.holder.surface.isValid) return
        generation += 1
        val localGeneration = generation
        prepared = false
        backend = target
        fallbackReason = reason
        releasePlayers()
        spinner.visibility = View.VISIBLE
        errorView.visibility = View.GONE
        updateOverlay()
        when (target) {
            Backend.NATIVE -> startNative(localGeneration)
            Backend.MEDIA3 -> startMedia3(localGeneration)
        }
    }

    private fun startNative(localGeneration: Int) {
        val channel = currentChannel()
        try {
            val player = MediaPlayer()
            nativePlayer = player
            player.setAudioAttributes(
                AndroidAudioAttributes.Builder()
                    .setUsage(AndroidAudioAttributes.USAGE_MEDIA)
                    .setContentType(AndroidAudioAttributes.CONTENT_TYPE_MOVIE)
                    .build(),
            )
            player.setScreenOnWhilePlaying(true)
            player.setDisplay(surfaceView.holder)
            player.setDataSource(this, Uri.parse(channel.url), channel.headers)
            player.setOnPreparedListener {
                if (localGeneration != generation) return@setOnPreparedListener
                prepared = true
                spinner.visibility = View.GONE
                it.start()
                updateOverlay()
            }
            player.setOnErrorListener { _, what, extra ->
                if (localGeneration == generation) {
                    fallbackToMedia3("AndroidMediaPlayer error $what/$extra")
                }
                true
            }
            player.setOnInfoListener { _, what, _ ->
                if (localGeneration == generation && what == MediaPlayer.MEDIA_INFO_VIDEO_TRACK_LAGGING) {
                    fallbackToMedia3("Android detecto video atrasado")
                    true
                } else {
                    false
                }
            }
            player.prepareAsync()
            armTimeout(localGeneration, Backend.NATIVE)
        } catch (error: Throwable) {
            fallbackToMedia3("AndroidMediaPlayer: ${error.javaClass.simpleName}")
        }
    }

    private fun startMedia3(localGeneration: Int) {
        val channel = currentChannel()
        try {
            val renderers = NextRenderersFactory(this)
            renderers.setEnableDecoderFallback(true)
            renderers.setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)

            val loadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(2_000, 4_000, 1_000, 1_000)
                .build()

            val http = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(8_000)
                .setReadTimeoutMs(12_000)
                .setDefaultRequestProperties(channel.headers)
            val userAgent = channel.headers.entries
                .firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }
                ?.value
            if (!userAgent.isNullOrBlank()) http.setUserAgent(userAgent)

            val dataSource = DefaultDataSource.Factory(this, http)
            val mediaSources = DefaultMediaSourceFactory(dataSource)
            val player = ExoPlayer.Builder(this, renderers)
                .setLoadControl(loadControl)
                .setMediaSourceFactory(mediaSources)
                .build()
            exoPlayer = player
            player.setAudioAttributes(Media3AudioAttributes.DEFAULT, true)
            player.setVideoSurfaceHolder(surfaceView.holder)
            player.addListener(
                object : Player.Listener {
                    override fun onPlaybackStateChanged(playbackState: Int) {
                        if (localGeneration != generation) return
                        if (playbackState == Player.STATE_READY) {
                            prepared = true
                            spinner.visibility = View.GONE
                            updateOverlay()
                        }
                    }

                    override fun onPlayerError(error: PlaybackException) {
                        if (localGeneration == generation) {
                            showError("Media3: ${error.errorCodeName}")
                        }
                    }
                },
            )
            val item = MediaItem.Builder().setUri(channel.url)
            val lower = channel.url.lowercase()
            if (lower.contains(".m3u8") || lower.contains("type=m3u8")) {
                item.setMimeType(MimeTypes.APPLICATION_M3U8)
            }
            player.setMediaItem(item.build())
            player.prepare()
            player.playWhenReady = true
            armTimeout(localGeneration, Backend.MEDIA3)
        } catch (error: Throwable) {
            showError("Media3 no pudo abrir: ${error.javaClass.simpleName}")
        }
    }

    private fun armTimeout(localGeneration: Int, target: Backend) {
        handler.postDelayed({
            if (localGeneration != generation || prepared || isFinishing) return@postDelayed
            when (target) {
                Backend.NATIVE -> fallbackToMedia3("timeout AndroidMediaPlayer")
                Backend.MEDIA3 -> showError("El canal no respondio a tiempo")
            }
        }, 8_000)
    }

    private fun fallbackToMedia3(reason: String) {
        if (backend == Backend.MEDIA3 || isFinishing) return
        handler.post {
            if (!isFinishing) playCurrent(Backend.MEDIA3, reason)
        }
    }

    private fun showError(message: String) {
        releasePlayers()
        spinner.visibility = View.GONE
        errorView.text = "$message\nUsa ←/→ para probar otro canal."
        errorView.visibility = View.VISIBLE
        updateOverlay()
    }

    private fun releasePlayers() {
        try {
            nativePlayer?.setOnPreparedListener(null)
            nativePlayer?.setOnErrorListener(null)
            nativePlayer?.setOnInfoListener(null)
            nativePlayer?.reset()
            nativePlayer?.release()
        } catch (_: Throwable) {
        }
        nativePlayer = null
        try {
            exoPlayer?.clearVideoSurface()
            exoPlayer?.release()
        } catch (_: Throwable) {
        }
        exoPlayer = null
    }

    private fun updateOverlay() {
        if (!::titleView.isInitialized) return
        val channel = currentChannel()
        titleView.text = "${currentIndex + 1}/${channels.size}  ${channel.name}"
        backendView.text = buildString {
            append("Motor: ")
            append(backend.label)
            fallbackReason?.let {
                append("  · ")
                append(it)
            }
        }
        overlay.visibility = if (overlayVisible) View.VISIBLE else View.GONE
    }

    private fun previousChannel() {
        currentIndex = (currentIndex - 1 + channels.size) % channels.size
        playCurrent(Backend.NATIVE, null)
    }

    private fun nextChannel() {
        currentIndex = (currentIndex + 1) % channels.size
        playCurrent(Backend.NATIVE, null)
    }

    private fun toggleBackend() {
        val next = if (backend == Backend.NATIVE) Backend.MEDIA3 else Backend.NATIVE
        playCurrent(next, "cambio manual")
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_CHANNEL_UP -> {
                previousChannel()
                true
            }
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_CHANNEL_DOWN -> {
                nextChannel()
                true
            }
            KeyEvent.KEYCODE_DPAD_UP -> {
                toggleBackend()
                true
            }
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                overlayVisible = !overlayVisible
                updateOverlay()
                true
            }
            else -> super.onKeyDown(keyCode, event)
        }
    }
}
''')


def main():
    patch_player_wrapper()
    write_launcher()
    patch_remote_version()
    patch_android_project()
    write_main_activity()
    write_native_activity()
    print('Android Native MultiPlayer V6 aplicado correctamente.')


if __name__ == '__main__':
    main()
