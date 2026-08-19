from pathlib import Path

KOTLIN = Path('android/app/src/main/kotlin/com/example/iptv_player/Media3LivePlayerView.kt')
text = KOTLIN.read_text()


def rep(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label} marker not found')

# V3.4 forced asynchronous MediaCodec queueing. It did not solve 1080p on the
# target Realtek TV and the user observed more BUFFER/recovery cycles, so V3.5
# returns to the codec's normal queueing mode. Decoder fallback stays enabled.
text = text.replace('        .forceEnableMediaCodecAsynchronousQueueing()\n', '', 1)
if 'forceEnableMediaCodecAsynchronousQueueing()' in text:
    raise SystemExit('v35 async MediaCodec queueing removal failed')

if 'import androidx.media3.common.Format' not in text:
    text = text.replace(
        'import androidx.media3.common.MediaItem\n',
        'import androidx.media3.common.Format\nimport androidx.media3.common.MediaItem\n',
        1,
    )
if 'import androidx.media3.exoplayer.DecoderReuseEvaluation' not in text:
    text = text.replace(
        'import androidx.media3.exoplayer.DefaultRenderersFactory\n',
        'import androidx.media3.exoplayer.DecoderReuseEvaluation\n'
        'import androidx.media3.exoplayer.DefaultLoadControl\n'
        'import androidx.media3.exoplayer.DefaultRenderersFactory\n',
        1,
    )

# Media3 1.8.0 exposes the generic setBufferDurationsMs /
# setPrioritizeTimeOverSizeThresholds APIs. The newer streaming-specific
# variants are not available in the pinned 1.8.0 artifact. Since this player is
# LIVE-only, applying the generic values is equivalent for this controlled test.
old_player = '    private val player = ExoPlayer.Builder(context, renderersFactory).build()\n'
new_player = '''    private val liveLoadControl = DefaultLoadControl.Builder()\n        .setBufferDurationsMs(\n            8_000,  // min buffer\n            20_000, // max buffer\n            750,    // initial playback\n            1_000,  // resume after rebuffer\n        )\n        .setTargetBufferBytes(32 * 1024 * 1024)\n        .setPrioritizeTimeOverSizeThresholds(true)\n        .build()\n    private val player = ExoPlayer.Builder(context, renderersFactory)\n        .setLoadControl(liveLoadControl)\n        .build()\n'''
text = rep(text, old_player, new_player, 'v35 bounded LIVE load control')

# Report actual play intent. isPlaying becomes false during BUFFERING, which is
# not the same as the user pressing Pause.
state_marker = '''    override fun onPlaybackStateChanged(playbackState: Int) {\n'''
state_new = '''    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {\n        sendEvent(\n            mapOf(\n                "type" to "playWhenReady",\n                "value" to playWhenReady,\n                "reason" to reason,\n                "session" to openSession,\n            ),\n        )\n    }\n\n    override fun onPlaybackStateChanged(playbackState: Int) {\n'''
text = rep(text, state_marker, state_new, 'v35 playWhenReady event')

# Extend the existing V3.4 analytics listener with the real input format and
# dropped-frame diagnostics. This lets 1080p failures be classified by codec,
# decoder, profile/resolution behavior instead of guessing from resolution only.
listener_old = '''            override fun onVideoDecoderInitialized(\n                eventTime: AnalyticsListener.EventTime,\n                decoderName: String,\n                initializedTimestampMs: Long,\n                initializationDurationMs: Long,\n            ) {\n                sendEvent(\n                    mapOf(\n                        "type" to "decoder",\n                        "value" to decoderName,\n                        "session" to openSession,\n                    ),\n                )\n            }\n'''
listener_new = '''            override fun onVideoDecoderInitialized(\n                eventTime: AnalyticsListener.EventTime,\n                decoderName: String,\n                initializedTimestampMs: Long,\n                initializationDurationMs: Long,\n            ) {\n                sendEvent(\n                    mapOf(\n                        "type" to "decoder",\n                        "value" to decoderName,\n                        "session" to openSession,\n                    ),\n                )\n            }\n\n            override fun onVideoInputFormatChanged(\n                eventTime: AnalyticsListener.EventTime,\n                format: Format,\n                decoderReuseEvaluation: DecoderReuseEvaluation?,\n            ) {\n                sendEvent(\n                    mapOf(\n                        "type" to "videoFormat",\n                        "mime" to format.sampleMimeType,\n                        "codecs" to format.codecs,\n                        "width" to format.width,\n                        "height" to format.height,\n                        "fps" to format.frameRate,\n                        "bitrate" to format.bitrate,\n                        "session" to openSession,\n                    ),\n                )\n            }\n\n            override fun onDroppedVideoFrames(\n                eventTime: AnalyticsListener.EventTime,\n                droppedFrames: Int,\n                elapsedMs: Long,\n            ) {\n                if (droppedFrames <= 0) return\n                sendEvent(\n                    mapOf(\n                        "type" to "droppedFrames",\n                        "count" to droppedFrames,\n                        "elapsedMs" to elapsedMs,\n                        "session" to openSession,\n                    ),\n                )\n            }\n'''
text = rep(text, listener_old, listener_new, 'v35 video diagnostics')

KOTLIN.write_text(text)
print('Android TV V3.5 native stability applied: sync MediaCodec, bounded LIVE buffers, real pause intent, video diagnostics')
