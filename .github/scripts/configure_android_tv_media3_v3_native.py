from pathlib import Path

# This script runs after `flutter create --platforms=android .`.
# It changes only the generated Android shell for the isolated V3 test build.

gradle = Path('android/app/build.gradle.kts')
text = gradle.read_text()
old_app_id = 'applicationId = "com.example.iptv_player"'
new_app_id = 'applicationId = "com.tvfull.pro.tvv3test"'
if old_app_id in text:
    text = text.replace(old_app_id, new_app_id, 1)
elif new_app_id not in text:
    raise SystemExit('Generated applicationId marker not found')

media3_deps = '''

dependencies {
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-exoplayer-hls:1.8.0")
    implementation("androidx.media3:media3-ui:1.8.0")
}
'''
if 'androidx.media3:media3-exoplayer:1.8.0' not in text:
    text += media3_deps
gradle.write_text(text)

manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text()
text = text.replace(
    'android:label="iptv_player"',
    'android:label="TV FULL V3 TEST"',
    1,
)
if 'android.permission.INTERNET' not in text:
    text = text.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <uses-permission android:name="android.permission.INTERNET" />',
        1,
    )
features = (
    '    <uses-feature android:name="android.software.leanback" android:required="false" />\n'
    '    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />\n'
)
if 'android.software.leanback' not in text:
    text = text.replace('<application', features + '    <application', 1)
if 'android:screenOrientation="landscape"' not in text:
    text = text.replace(
        'android:name=".MainActivity"',
        'android:name=".MainActivity"\n'
        '            android:screenOrientation="landscape"\n'
        '            android:resizeableActivity="false"',
        1,
    )
if 'android.intent.category.LEANBACK_LAUNCHER' not in text:
    text = text.replace(
        '<category android:name="android.intent.category.LAUNCHER"/>',
        '<category android:name="android.intent.category.LAUNCHER"/>\n'
        '                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
        1,
    )
impeller = (
    '        <meta-data\n'
    '            android:name="io.flutter.embedding.android.EnableImpeller"\n'
    '            android:value="false" />\n'
)
if 'io.flutter.embedding.android.EnableImpeller' not in text:
    marker = '        <activity\n'
    if marker not in text:
        raise SystemExit('Android activity marker not found')
    text = text.replace(marker, impeller + marker, 1)
manifest.write_text(text)

kotlin_dir = Path('android/app/src/main/kotlin/com/example/iptv_player')
kotlin_dir.mkdir(parents=True, exist_ok=True)

(kotlin_dir / 'MainActivity.kt').write_text('''package com.example.iptv_player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "tvfull/media3_live_surface",
                Media3LivePlayerFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
    }
}
''')

(kotlin_dir / 'Media3LivePlayerView.kt').write_text(r'''package com.example.iptv_player

import android.content.Context
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

@UnstableApi
class Media3LivePlayerFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return Media3LivePlayerView(context, viewId, messenger)
    }
}

@UnstableApi
private class Media3LivePlayerView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
) : PlatformView, MethodChannel.MethodCallHandler, Player.Listener {
    private val root = FrameLayout(context)
    private val playerView = PlayerView(context)
    private val player = ExoPlayer.Builder(context).build()
    private val channel = MethodChannel(messenger, "tvfull/media3_live_$viewId")
    private var openSession = 0
    private var released = false

    init {
        playerView.useController = false
        playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        playerView.player = player
        root.addView(
            playerView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        val surface = playerView.videoSurfaceView
        if (surface is SurfaceView) {
            surface.setZOrderOnTop(false)
            surface.setZOrderMediaOverlay(false)
            sendEvent(mapOf("type" to "surface", "value" to "SurfaceView", "session" to openSession))
        } else {
            sendEvent(
                mapOf(
                    "type" to "surface",
                    "value" to (surface?.javaClass?.simpleName ?: "unknown"),
                    "session" to openSession,
                ),
            )
        }

        player.addListener(this)
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = root

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (released) {
            result.error("released", "Media3 player already released", null)
            return
        }

        when (call.method) {
            "open" -> open(call, result)
            "playPause" -> {
                if (player.isPlaying) player.pause() else player.play()
                result.success(null)
            }
            "setVolume" -> {
                val value = call.argument<Number>("value")?.toFloat() ?: 100f
                player.volume = (value / 100f).coerceIn(0f, 1f)
                result.success(null)
            }
            "setResizeMode" -> {
                when (call.argument<Number>("mode")?.toInt() ?: 0) {
                    1 -> playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    2 -> playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
                    else -> playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                }
                result.success(null)
            }
            "stop" -> {
                player.stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        if (url.isEmpty()) {
            result.error("invalid_url", "Empty live URL", null)
            return
        }

        val headers = mutableMapOf<String, String>()
        val rawHeaders = call.argument<Map<*, *>>("headers")
        rawHeaders?.forEach { (key, value) ->
            val k = key?.toString()?.trim().orEmpty()
            val v = value?.toString()?.trim().orEmpty()
            if (k.isNotEmpty() && v.isNotEmpty()) headers[k] = v
        }

        openSession += 1
        try {
            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(10_000)
                .setReadTimeoutMs(15_000)
                .setDefaultRequestProperties(headers)
            headers.entries.firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }
                ?.value
                ?.takeIf { it.isNotBlank() }
                ?.let { httpFactory.setUserAgent(it) }

            val dataSourceFactory = DefaultDataSource.Factory(root.context, httpFactory)
            val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
            val mediaItem = MediaItem.Builder().setUri(url).build()
            val mediaSource = mediaSourceFactory.createMediaSource(mediaItem)

            player.stop()
            player.clearMediaItems()
            player.setMediaSource(mediaSource)
            player.prepare()
            player.playWhenReady = true
            sendEvent(mapOf("type" to "opening", "session" to openSession))
            result.success(null)
        } catch (error: Throwable) {
            sendEvent(
                mapOf(
                    "type" to "error",
                    "message" to (error.message ?: error.javaClass.simpleName),
                    "session" to openSession,
                ),
            )
            result.error("open_failed", error.message, null)
        }
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_BUFFERING -> sendEvent(mapOf("type" to "buffering", "session" to openSession))
            Player.STATE_READY -> sendEvent(mapOf("type" to "ready", "session" to openSession))
            Player.STATE_ENDED -> sendEvent(mapOf("type" to "ended", "session" to openSession))
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        sendEvent(mapOf("type" to "isPlaying", "value" to isPlaying, "session" to openSession))
    }

    override fun onRenderedFirstFrame() {
        sendEvent(mapOf("type" to "firstFrame", "session" to openSession))
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        sendEvent(
            mapOf(
                "type" to "videoSize",
                "width" to videoSize.width,
                "height" to videoSize.height,
                "session" to openSession,
            ),
        )
    }

    override fun onPlayerError(error: PlaybackException) {
        sendEvent(
            mapOf(
                "type" to "error",
                "message" to "${error.errorCodeName}: ${error.message ?: "playback error"}",
                "session" to openSession,
            ),
        )
    }

    private fun sendEvent(event: Map<String, Any?>) {
        if (!released) channel.invokeMethod("event", event)
    }

    override fun dispose() {
        if (released) return
        released = true
        channel.setMethodCallHandler(null)
        player.removeListener(this)
        playerView.player = null
        player.release()
    }
}
''')

print('Generated Android TV V3 package + Media3 PlayerView/SurfaceView configuration')
