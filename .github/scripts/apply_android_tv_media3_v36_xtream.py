from pathlib import Path

KOTLIN = Path('android/app/src/main/kotlin/com/example/iptv_player/Media3LivePlayerView.kt')
text = KOTLIN.read_text()


def rep(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label} marker not found')

# Keep the successful decoder/SurfaceView path. V3.6 only adds source-level
# compatibility for LIVE URLs, especially Xtream /live/user/pass/id.* streams.
field_marker = '''    private var hasRenderedVideoFrame = false\n'''
field_new = '''    private var hasRenderedVideoFrame = false\n    private var compatibilityCandidates: List<String> = emptyList()\n    private var compatibilityIndex = 0\n    private var compatibilityHeaders: Map<String, String> = emptyMap()\n'''
text = rep(text, field_marker, field_new, 'v36 compatibility fields')

start = text.find('    private fun open(call: MethodCall, result: MethodChannel.Result) {')
end = text.find('    override fun onPlayWhenReadyChanged(', start)
if start < 0 or end < 0:
    raise SystemExit('V3.6 native open method bounds not found')

open_block = r'''    private fun open(call: MethodCall, result: MethodChannel.Result) {
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
        if (headers.keys.none { it.equals("Accept", ignoreCase = true) }) {
            headers["Accept"] = "*/*"
        }

        openSession += 1
        hasRenderedVideoFrame = false
        compatibilityCandidates = buildCompatibilityCandidates(url)
        compatibilityIndex = 0
        compatibilityHeaders = headers.toMap()
        try {
            prepareCompatibilityCandidate()
            sendEvent(
                mapOf(
                    "type" to "opening",
                    "candidate" to compatibilityIndex,
                    "session" to openSession,
                ),
            )
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

    private fun prepareCompatibilityCandidate() {
        val url = compatibilityCandidates.getOrNull(compatibilityIndex)
            ?: throw IllegalStateException("No LIVE compatibility candidate")
        val headers = compatibilityHeaders

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
        val mediaItemBuilder = MediaItem.Builder().setUri(url)
        mimeTypeForLiveUrl(url)?.let { mediaItemBuilder.setMimeType(it) }
        val mediaSource = mediaSourceFactory.createMediaSource(mediaItemBuilder.build())

        player.stop()
        player.clearMediaItems()
        player.setMediaSource(mediaSource)
        player.prepare()
        player.playWhenReady = true
    }

    private fun mimeTypeForLiveUrl(url: String): String? {
        val path = url.substringBefore('?').substringBefore('#').lowercase()
        return when {
            path.endsWith(".m3u8") -> "application/x-mpegURL"
            path.endsWith(".ts") || path.endsWith(".mpegts") -> "video/mp2t"
            path.endsWith(".mpd") -> "application/dash+xml"
            else -> null
        }
    }

    private fun buildCompatibilityCandidates(url: String): List<String> {
        val candidates = mutableListOf(url)
        val queryPos = url.indexOf('?')
        val base = if (queryPos >= 0) url.substring(0, queryPos) else url
        val suffix = if (queryPos >= 0) url.substring(queryPos) else ""
        val lower = base.lowercase()

        // Xtream clones are not consistent: some serve the same stream as
        // id.ts, id (no extension), or id.m3u8. Only generate alternatives for
        // the canonical /live/ path so arbitrary M3U URLs are never rewritten.
        if (lower.contains("/live/")) {
            when {
                lower.endsWith(".ts") -> {
                    val stem = base.dropLast(3)
                    candidates.add(stem + suffix)
                    candidates.add(stem + ".m3u8" + suffix)
                }
                lower.endsWith(".m3u8") -> {
                    val stem = base.dropLast(5)
                    candidates.add(stem + ".ts" + suffix)
                    candidates.add(stem + suffix)
                }
                base.substringAfterLast('/').contains('.').not() -> {
                    candidates.add(base + ".ts" + suffix)
                    candidates.add(base + ".m3u8" + suffix)
                }
            }
        }
        return candidates.distinct()
    }

    private fun tryNextCompatibilityCandidate(errorMessage: String): Boolean {
        if (hasRenderedVideoFrame || compatibilityIndex + 1 >= compatibilityCandidates.size) {
            return false
        }
        compatibilityIndex += 1
        hasRenderedVideoFrame = false
        return try {
            sendEvent(
                mapOf(
                    "type" to "nativeCompatibility",
                    "value" to "candidate_${compatibilityIndex + 1}",
                    "reason" to errorMessage,
                    "session" to openSession,
                ),
            )
            prepareCompatibilityCandidate()
            true
        } catch (error: Throwable) {
            tryNextCompatibilityCandidate(error.message ?: error.javaClass.simpleName)
        }
    }

'''
text = text[:start] + open_block + text[end:]

old_error = '''    override fun onPlayerError(error: PlaybackException) {\n        sendEvent(\n            mapOf(\n                "type" to "error",\n                "message" to "${error.errorCodeName}: ${error.message ?: "playback error"}",\n                "session" to openSession,\n            ),\n        )\n    }\n'''
new_error = '''    override fun onPlayerError(error: PlaybackException) {\n        val message = "${error.errorCodeName}: ${error.message ?: "playback error"}"\n        if (tryNextCompatibilityCandidate(message)) return\n        sendEvent(\n            mapOf(\n                "type" to "error",\n                "message" to message,\n                "session" to openSession,\n            ),\n        )\n    }\n'''
text = rep(text, old_error, new_error, 'v36 player error Xtream fallback')

KOTLIN.write_text(text)
print('Android TV V3.6 Xtream compatibility applied: TS/HLS MIME hints + /live/ URL fallbacks')
