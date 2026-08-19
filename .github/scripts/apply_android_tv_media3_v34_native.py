from pathlib import Path

KOTLIN = Path('android/app/src/main/kotlin/com/example/iptv_player/Media3LivePlayerView.kt')
text = KOTLIN.read_text()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        if new in text:
            return text
        raise SystemExit(f'{label} marker not found')
    return text.replace(old, new, 1)

# Media3 high-resolution experiment for older Android TV SoCs:
# - enable decoder fallback if the primary codec fails to initialize
# - force asynchronous MediaCodec queueing (API 23+) to reduce blocking work
# - keep the already successful PlayerView + SurfaceView path unchanged
# - report the decoder name to Flutter for diagnostics
if 'import androidx.media3.exoplayer.DefaultRenderersFactory' not in text:
    text = text.replace(
        'import androidx.media3.exoplayer.ExoPlayer\n',
        'import androidx.media3.exoplayer.DefaultRenderersFactory\n'
        'import androidx.media3.exoplayer.ExoPlayer\n'
        'import androidx.media3.exoplayer.analytics.AnalyticsListener\n',
        1,
    )

old_player = '    private val player = ExoPlayer.Builder(context).build()\n'
new_player = '''    private val renderersFactory = DefaultRenderersFactory(context)\n        .setEnableDecoderFallback(true)\n        .forceEnableMediaCodecAsynchronousQueueing()\n    private val player = ExoPlayer.Builder(context, renderersFactory).build()\n'''
text = replace_once(text, old_player, new_player, 'v34 renderer factory')

listener_marker = '''        player.addListener(this)\n        channel.setMethodCallHandler(this)\n'''
listener_new = '''        player.addListener(this)\n        player.addAnalyticsListener(object : AnalyticsListener {\n            override fun onVideoDecoderInitialized(\n                eventTime: AnalyticsListener.EventTime,\n                decoderName: String,\n                initializedTimestampMs: Long,\n                initializationDurationMs: Long,\n            ) {\n                sendEvent(\n                    mapOf(\n                        "type" to "decoder",\n                        "value" to decoderName,\n                        "session" to openSession,\n                    ),\n                )\n            }\n        })\n        channel.setMethodCallHandler(this)\n'''
text = replace_once(text, listener_marker, listener_new, 'v34 decoder analytics listener')

# Keep short live EOS recoveries inside the native player after playback has
# already produced video. This avoids rebuilding the Flutter/native bridge for
# every server-side LIVE connection rollover. Initial EOS still goes to Flutter
# so dead channels retain the existing retry/error behavior.
field_marker = '''    private var openSession = 0\n    private var released = false\n'''
field_new = '''    private var openSession = 0\n    private var released = false\n    private var hasRenderedVideoFrame = false\n'''
text = replace_once(text, field_marker, field_new, 'v34 native frame history')

open_marker = '''        openSession += 1\n        try {\n'''
open_new = '''        openSession += 1\n        hasRenderedVideoFrame = false\n        try {\n'''
text = replace_once(text, open_marker, open_new, 'v34 reset frame history')

ended_old = '''            Player.STATE_ENDED -> sendEvent(mapOf("type" to "ended", "session" to openSession))\n'''
ended_new = '''            Player.STATE_ENDED -> {\n                if (hasRenderedVideoFrame) {\n                    sendEvent(\n                        mapOf(\n                            "type" to "nativeRecovery",\n                            "value" to "eos",\n                            "session" to openSession,\n                        ),\n                    )\n                    player.seekToDefaultPosition()\n                    player.prepare()\n                    player.playWhenReady = true\n                } else {\n                    sendEvent(mapOf("type" to "ended", "session" to openSession))\n                }\n            }\n'''
text = replace_once(text, ended_old, ended_new, 'v34 native EOS recovery')

first_frame_old = '''    override fun onRenderedFirstFrame() {\n        sendEvent(mapOf("type" to "firstFrame", "session" to openSession))\n    }\n'''
first_frame_new = '''    override fun onRenderedFirstFrame() {\n        hasRenderedVideoFrame = true\n        sendEvent(mapOf("type" to "firstFrame", "session" to openSession))\n    }\n'''
text = replace_once(text, first_frame_old, first_frame_new, 'v34 first frame marker')

KOTLIN.write_text(text)
print('Android TV V3.4 native Media3 tuning applied: async MediaCodec, decoder fallback, decoder diagnostics, native EOS recovery')
