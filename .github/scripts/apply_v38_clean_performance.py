from pathlib import Path

ROOT = Path('.')


def replace_once(path: str, old: str, new: str, label: str) -> None:
    file = ROOT / path
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    file.write_text(text.replace(old, new, 1))


def write_file(path: str, content: str) -> None:
    file = ROOT / path
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(content)


# Version only. Installer manifest is intentionally out of scope.
replace_once(
    'pubspec.yaml',
    'version: 1.4.5+37',
    'version: 1.4.6+38',
    'pubspec version',
)

# Native LIVE retry policy: terminal auth/not-found vs transient server/network.
write_file(
    'android/app/src/main/kotlin/com/example/iptv_player/TvFullLiveLoadErrorPolicy.kt',
    '''package com.example.iptv_player

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy

/** LIVE request recovery with a small bounded budget and explicit terminal HTTPs. */
@UnstableApi
class TvFullLiveLoadErrorPolicy : DefaultLoadErrorHandlingPolicy() {
    @Volatile
    var protectionLevel: Int = 0

    override fun getMinimumLoadableRetryCount(dataType: Int): Int {
        val level = protectionLevel.coerceIn(0, 3)
        return when (dataType) {
            C.DATA_TYPE_MEDIA_PROGRESSIVE_LIVE -> 5 + level
            C.DATA_TYPE_MEDIA, C.DATA_TYPE_MANIFEST -> 3 + level
            else -> super.getMinimumLoadableRetryCount(dataType)
        }
    }

    override fun getRetryDelayMsFor(
        loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo,
    ): Long {
        val exception = loadErrorInfo.exception
        if (exception is HttpDataSource.InvalidResponseCodeException) {
            when (exception.responseCode) {
                401, 403, 404, 410 -> return C.TIME_UNSET
                408 -> return boundedBackoff(loadErrorInfo.errorCount)
                429 -> return (1200L * loadErrorInfo.errorCount).coerceAtMost(5000L)
                in 500..599 -> return boundedBackoff(loadErrorInfo.errorCount)
            }
        }

        val defaultDelay = super.getRetryDelayMsFor(loadErrorInfo)
        if (defaultDelay == C.TIME_UNSET) return C.TIME_UNSET
        return when (loadErrorInfo.errorCount) {
            1 -> 240L
            2 -> 600L
            3 -> 1200L
            else -> defaultDelay.coerceAtMost(2200L)
        }
    }

    private fun boundedBackoff(errorCount: Int): Long = when (errorCount) {
        1 -> 240L
        2 -> 600L
        3 -> 1200L
        else -> (1500L + protectionLevel * 200L).coerceAtMost(2200L)
    }
}
''',
)

# MainActivity: structured errors, first-frame health, HLS hint/recovery, player reuse.
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    'import androidx.media3.common.MediaItem\nimport androidx.media3.common.PlaybackException',
    'import androidx.media3.common.MediaItem\nimport androidx.media3.common.MimeTypes\nimport androidx.media3.common.PlaybackException',
    'MainActivity MimeTypes import',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    'import java.net.InetAddress\nimport java.net.UnknownHostException',
    'import java.net.InetAddress\nimport java.net.SocketTimeoutException\nimport java.net.UnknownHostException',
    'MainActivity SocketTimeout import',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '    private var liveEverReady = false\n    private var liveBufferLastProgressAtMs = 0L',
    '    private var liveEverReady = false\n    private var liveFirstFrameGeneration = -1L\n    private var currentSourceForcedHls = false\n    private var opaqueHlsRecoveryAttempted = false\n    private var liveBufferLastProgressAtMs = 0L',
    'MainActivity first-frame state',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '''        lastBandwidthEstimate = 0L
        liveEverReady = false
        liveBufferLastProgressAtMs = 0L
        liveBufferLastPositionMs = 0L
        resetStartupProgress()
        dnsFallbackActive = false''',
    '''        lastBandwidthEstimate = 0L
        liveEverReady = false
        liveFirstFrameGeneration = -1L
        currentSourceForcedHls = false
        opaqueHlsRecoveryAttempted = false
        liveBufferLastProgressAtMs = 0L
        liveBufferLastPositionMs = 0L
        resetStartupProgress()
        dnsFallbackActive = false''',
    'MainActivity prepare reset',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '''        positionMs: Long,
        useFallbackDns: Boolean,
    ) {''',
    '''        positionMs: Long,
        useFallbackDns: Boolean,
        forceHls: Boolean = false,
    ) {''',
    'MainActivity prepareSource forceHls signature',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '''        val factory = mediaSourceFactory(headers, userAgent, useFallbackDns)
        val itemBuilder = MediaItem.Builder()
            .setUri(Uri.parse(url))
            .setMediaId(clientGeneration.toString())
        if (isLive) {''',
    '''        val factory = mediaSourceFactory(headers, userAgent, useFallbackDns)
        val useHlsMime = isLive && (currentSourceForcedHls || forceHls || looksLikeHls(url))
        currentSourceForcedHls = useHlsMime
        val itemBuilder = MediaItem.Builder()
            .setUri(Uri.parse(url))
            .setMediaId(clientGeneration.toString())
        if (useHlsMime) itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
        if (isLive) {''',
    'MainActivity explicit HLS MIME',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '''        exo.prepare()
        exo.playWhenReady = true
    }

    private fun mediaSourceFactory(''',
    '''        exo.prepare()
        exo.playWhenReady = true
    }

    private fun looksLikeHls(url: String): Boolean {
        val lower = url.lowercase(Locale.US)
        if (lower.contains(".m3u8")) return true
        val parsed = try { Uri.parse(url) } catch (_: Throwable) { return false }
        val path = (parsed.path ?: "").lowercase(Locale.US)
        val query = (parsed.query ?: "").lowercase(Locale.US)
        return path.contains("/hls/") ||
            query.contains("m3u8") ||
            query.contains("format=hls") ||
            query.contains("type=hls")
    }

    private fun mediaSourceFactory(''',
    'MainActivity HLS detector',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '            if (exo.playbackState == Player.STATE_READY) return@Runnable',
    '            if (liveFirstFrameGeneration == clientGeneration) return@Runnable',
    'MainActivity startup waits for first frame',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '''                    "errorCodeName" to "TVFULL_NO_PROGRESS",
                    "error" to "La señal no envió datos",''',
    '''                    "errorCodeName" to "TVFULL_NO_PROGRESS",
                    "errorCategory" to "no_progress",
                    "retryable" to false,
                    "error" to "La señal no envió datos",''',
    'MainActivity no-progress structure',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '''    private fun handleRenderedFirstFrame(generation: Long) {
        if (!isActiveClientGeneration(generation)) return
        liveNetworkProgressAtMs = System.currentTimeMillis()
        eventSink?.success(
            mapOf(
                "eventType" to "playing",
                "generation" to generation,
                "bufferedPosition" to (player?.bufferedPosition ?: 0L).coerceAtLeast(0L),
            )
        )
    }''',
    '''    private fun handleRenderedFirstFrame(generation: Long) {
        if (!isActiveClientGeneration(generation)) return
        val firstFrameForGeneration = liveFirstFrameGeneration != generation
        val now = System.currentTimeMillis()
        liveFirstFrameGeneration = generation
        liveNetworkProgressAtMs = now
        if (isLive && firstFrameForGeneration) {
            cancelStartupDeadline()
            liveEverReady = true
            liveReadySinceMs = now
            liveBufferLastProgressAtMs = 0L
            liveBufferLastPositionMs = 0L
            scheduleLiveStabilityReset(playbackGeneration)
        }
        eventSink?.success(
            mapOf(
                "eventType" to "playing",
                "generation" to generation,
                "firstFrame" to true,
                "bufferedPosition" to (player?.bufferedPosition ?: 0L).coerceAtLeast(0L),
            )
        )
    }''',
    'MainActivity first frame confirmation',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '''            Player.STATE_READY -> {
                cancelStartupDeadline()
                cancelLiveBufferHealthCheck()
                liveEverReady = liveEverReady || isLive
                if (isLive && liveReadySinceMs == 0L) {
                    liveReadySinceMs = System.currentTimeMillis()
                }
                liveBufferLastProgressAtMs = 0L
                liveBufferLastPositionMs = 0L
                if (isLive) scheduleLiveStabilityReset(playbackGeneration)
                if (player?.playWhenReady == true) {''',
    '''            Player.STATE_READY -> {
                if (!isLive) cancelStartupDeadline()
                cancelLiveBufferHealthCheck()
                // READY confirma preparación, no imagen. En LIVE el guardián
                // sigue activo hasta onRenderedFirstFrame de esta generación.
                liveBufferLastProgressAtMs = 0L
                liveBufferLastPositionMs = 0L
                if (player?.playWhenReady == true) {''',
    'MainActivity READY is not healthy',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '''        if (!dnsFallbackActive && hasUnknownHost(error)) {''',
    '''        if (isLive &&
            !currentSourceForcedHls &&
            !opaqueHlsRecoveryAttempted &&
            isLikelyOpaqueHlsParserError(error)
        ) {
            val url = currentUrl
            if (url != null) {
                try {
                    opaqueHlsRecoveryAttempted = true
                    prepareSource(
                        url,
                        currentHeaders,
                        currentUserAgent,
                        0L,
                        useFallbackDns = dnsFallbackActive,
                        forceHls = true,
                    )
                    resetStartupProgress()
                    scheduleStartupDeadline(playbackGeneration, LIVE_RECOVERY_MAX_WAIT_MS)
                    eventSink?.success(
                        mapOf(
                            "eventType" to "liveRecovery",
                            "generation" to generation,
                            "reason" to "opaque_hls_mime",
                            "attempt" to 1,
                        )
                    )
                    return
                } catch (_: Throwable) {
                    // Si no era HLS, continuamos con la clasificación original.
                }
            }
        }

        if (!dnsFallbackActive && hasUnknownHost(error)) {''',
    'MainActivity opaque HLS recovery',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '''    private fun isFastIoError(error: PlaybackException): Boolean {
        val name = error.errorCodeName.lowercase(Locale.US)
        return name.contains("_io_") ||
            name.contains("network") ||
            name.contains("timeout") ||
            name.contains("bad_http_status")
    }

    private fun findHttpStatus(error: Throwable): Int? {
        var cause: Throwable? = error
        repeat(12) {
            val current = cause ?: return null
            if (current is HttpDataSource.InvalidResponseCodeException) {
                return current.responseCode
            }
            cause = current.cause
        }
        return null
    }

    private fun playbackErrorCategory(error: PlaybackException, httpStatus: Int?): String = when {
        httpStatus != null -> "http"
        hasUnknownHost(error) -> "dns"
        error.errorCodeName.contains("TIMEOUT", ignoreCase = true) -> "timeout"
        isFastIoError(error) -> "network"
        error.errorCodeName.contains("DECOD", ignoreCase = true) -> "decoder"
        error.errorCodeName.contains("PARS", ignoreCase = true) -> "parser"
        else -> "playback"
    }

    private fun isRetryablePlaybackError(error: PlaybackException, httpStatus: Int?): Boolean {
        if (httpStatus != null) {
            return httpStatus == 404 || httpStatus == 408 || httpStatus == 429 ||
                httpStatus in 500..599
        }
        return hasUnknownHost(error) || isFastIoError(error)
    }

    private fun hasUnknownHost(error: Throwable): Boolean {
        var cause: Throwable? = error
        repeat(12) {
            if (cause == null) return false
            if (cause is UnknownHostException) return true
            cause = cause?.cause
        }
        return false
    }''',
    '''    private fun isFastIoError(error: PlaybackException): Boolean {
        val name = error.errorCodeName.lowercase(Locale.US)
        return name.contains("_io_") ||
            name.contains("network") ||
            name.contains("timeout") ||
            name.contains("bad_http_status")
    }

    private fun findHttpStatus(error: Throwable): Int? {
        var cause: Throwable? = error
        repeat(12) {
            val current = cause ?: return null
            if (current is HttpDataSource.InvalidResponseCodeException) {
                return current.responseCode
            }
            cause = current.cause
        }
        return null
    }

    private fun playbackErrorCategory(error: PlaybackException, httpStatus: Int?): String {
        val name = error.errorCodeName.uppercase(Locale.US)
        return when {
            httpStatus != null && httpStatus in setOf(401, 403, 404, 410) -> "http_terminal"
            httpStatus != null && (httpStatus == 408 || httpStatus == 429 || httpStatus in 500..599) -> "http_transient"
            httpStatus != null -> "http"
            hasUnknownHost(error) -> "dns"
            hasSocketTimeout(error) || name.contains("TIMEOUT") -> "timeout"
            name.contains("DECOD") -> "decoder"
            name.contains("PARSING_MANIFEST") -> "manifest"
            name.contains("PARSING_CONTAINER") -> "segment"
            name.contains("BEHIND_LIVE_WINDOW") -> "microcut"
            isFastIoError(error) -> "network"
            name.contains("PARS") -> "parser"
            else -> "playback"
        }
    }

    private fun isRetryablePlaybackError(error: PlaybackException, httpStatus: Int?): Boolean {
        if (httpStatus != null) {
            if (httpStatus in setOf(401, 403, 404, 410)) return false
            return httpStatus == 408 || httpStatus == 429 || httpStatus in 500..599
        }
        val category = playbackErrorCategory(error, null)
        if (category == "decoder" || category == "parser" || category == "manifest") return false
        return category == "dns" ||
            category == "timeout" ||
            category == "network" ||
            category == "segment" ||
            category == "microcut"
    }

    private fun hasUnknownHost(error: Throwable): Boolean {
        var cause: Throwable? = error
        repeat(12) {
            if (cause == null) return false
            if (cause is UnknownHostException) return true
            cause = cause?.cause
        }
        return false
    }

    private fun hasSocketTimeout(error: Throwable): Boolean {
        var cause: Throwable? = error
        repeat(12) {
            if (cause == null) return false
            if (cause is SocketTimeoutException) return true
            cause = cause?.cause
        }
        return false
    }

    private fun isLikelyOpaqueHlsParserError(error: PlaybackException): Boolean {
        val url = currentUrl ?: return false
        if (looksLikeHls(url)) return false
        val name = error.errorCodeName.uppercase(Locale.US)
        return name.contains("PARSING_MANIFEST") ||
            name.contains("PARSING_CONTAINER_UNSUPPORTED")
    }''',
    'MainActivity error taxonomy',
)
replace_once(
    'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt',
    '''        liveEverReady = false
        liveBufferLastProgressAtMs = 0L
        liveBufferLastPositionMs = 0L
        startupStartedAtMs = 0L''',
    '''        liveEverReady = false
        liveFirstFrameGeneration = -1L
        currentSourceForcedHls = false
        opaqueHlsRecoveryAttempted = false
        liveBufferLastProgressAtMs = 0L
        liveBufferLastPositionMs = 0L
        startupStartedAtMs = 0L''',
    'MainActivity dispose reset',
)

# Centralized Dart-side retry/cooldown taxonomy. No widget/layout changes.
write_file(
    'lib/services/live_playback_error_policy.dart',
    '''class LivePlaybackDecision {
  final bool shouldRetry;
  final bool markDead;
  final Duration retryDelay;
  final String friendlyMessage;
  final String category;

  const LivePlaybackDecision({
    required this.shouldRetry,
    required this.markDead,
    required this.retryDelay,
    required this.friendlyMessage,
    required this.category,
  });
}

class LivePlaybackErrorPolicy {
  LivePlaybackErrorPolicy._();

  static const List<Duration> _retryBackoff = <Duration>[
    Duration(milliseconds: 240),
    Duration(milliseconds: 600),
    Duration(milliseconds: 1200),
  ];

  static LivePlaybackDecision decide({
    required String code,
    required String detail,
    required int retryCount,
    int? httpStatus,
    bool? nativeRetryable,
    String? category,
  }) {
    final normalizedCode = code.toLowerCase();
    final normalizedCategory = (category ?? '').toLowerCase();
    final combined = '$code $detail ${category ?? ''}'.toLowerCase();

    final terminalHttp = _isTerminalHttp(httpStatus, combined);
    final transientHttp = !terminalHttp &&
        (httpStatus == 408 ||
            httpStatus == 429 ||
            (httpStatus != null && httpStatus >= 500 && httpStatus <= 599));
    final exhaustedSignal = normalizedCode.contains('tvfull_no_progress') ||
        normalizedCode.contains('tvfull_stall_exhausted') ||
        normalizedCode.contains('stream_ended');
    final transientCategory = <String>{
      'dns',
      'timeout',
      'network',
      'segment',
      'microcut',
      'http_transient',
    }.contains(normalizedCategory);
    final transientText = combined.contains('tvfull_fast_io') ||
        combined.contains('network') ||
        combined.contains('timeout') ||
        combined.contains('connection reset') ||
        combined.contains('connection refused');

    final retryableSignal = !terminalHttp &&
        !exhaustedSignal &&
        (transientHttp ||
            nativeRetryable == true ||
            transientCategory ||
            transientText);
    final shouldRetry = retryableSignal && retryCount < _retryBackoff.length;
    final markDead = terminalHttp || exhaustedSignal;

    return LivePlaybackDecision(
      shouldRetry: shouldRetry,
      markDead: markDead,
      retryDelay: shouldRetry ? _retryBackoff[retryCount] : Duration.zero,
      friendlyMessage: _friendlyMessage(
        combined,
        httpStatus: httpStatus,
        category: normalizedCategory,
      ),
      category: normalizedCategory.isEmpty ? 'playback' : normalizedCategory,
    );
  }

  static bool _isTerminalHttp(int? status, String text) {
    if (status != null) {
      return status == 401 || status == 403 || status == 404 || status == 410;
    }
    return text.contains('401') ||
        text.contains('403') ||
        text.contains('404') ||
        text.contains('410');
  }

  static String _friendlyMessage(
    String value, {
    required int? httpStatus,
    required String category,
  }) {
    if (category == 'decoder' ||
        value.contains('decoder') ||
        value.contains('codec')) {
      return 'Formato de video no compatible';
    }
    if (category == 'manifest' ||
        category == 'parser' ||
        value.contains('parsing_manifest') ||
        value.contains('parsing_container') ||
        value.contains('malformed')) {
      return 'Formato de señal no compatible';
    }
    if (category == 'dns' ||
        category == 'timeout' ||
        category == 'network' ||
        value.contains('timeout') ||
        value.contains('network') ||
        value.contains('connection')) {
      return 'Problema de conexión';
    }
    if (httpStatus != null ||
        category.startsWith('http') ||
        value.contains('response_code')) {
      return 'Canal no disponible';
    }
    return 'Canal temporalmente no disponible';
  }
}
''',
)

replace_once(
    'lib/screens/android_media3_texture_player_screen.dart',
    "import '../services/live_channel_usage_service.dart';\n",
    "import '../services/live_channel_usage_service.dart';\nimport '../services/live_playback_error_policy.dart';\n",
    'player screen policy import',
)
replace_once(
    'lib/screens/android_media3_texture_player_screen.dart',
    '''      case 'prepared':
        _autoRetryCount = 0;
        // READY significa que Media3 preparó la fuente, no que el usuario ya''',
    '''      case 'prepared':
        // READY significa que Media3 preparó la fuente, no que el usuario ya''',
    'player screen do not reset retry on READY',
)
replace_once(
    'lib/screens/android_media3_texture_player_screen.dart',
    '''      case 'bufferingEnd':
        _autoRetryCount = 0;
        if (_firstFrameGeneration == _openGeneration) {''',
    '''      case 'bufferingEnd':
        if (_firstFrameGeneration == _openGeneration) {''',
    'player screen do not reset retry on buffering end',
)
replace_once(
    'lib/screens/android_media3_texture_player_screen.dart',
    '''  void _handleTechnicalError(
    String code,
    String detail, {
    int? httpStatus,
    bool? retryable,
    String? category,
  }) {
    debugPrint(
      'TV FULL PRO LIVE [$code] $detail '
      'http=$httpStatus retryable=$retryable category=$category',
    );
    final combined = '$code $detail ${category ?? ''}'.toLowerCase();
    final status = httpStatus;
    final permanentHttp = status == 401 ||
        status == 403 ||
        status == 410 ||
        (status == null &&
            (combined.contains('401') ||
                combined.contains('403') ||
                combined.contains('410')));
    final transient = !permanentHttp &&
        (retryable == true ||
            status == 404 ||
            status == 408 ||
            status == 429 ||
            (status != null && status >= 500 && status <= 599) ||
            combined.contains('network') ||
            combined.contains('timeout') ||
            combined.contains('connection') ||
            combined.contains('io_bad_http_status') ||
            combined.contains('response_code_5'));

    if (transient && _autoRetryCount < 1) {
      _autoRetryCount++;
      if (mounted) {
        setState(() {
          _buffering = true;
          _friendlyError = null;
        });
      }
      _retryTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) {
          unawaited(
            _prepareCurrent(
              preserveRetry: true,
              keepChannelListOpen: _channelListVisible,
            ),
          );
        }
      });
      return;
    }

    final shouldCooldown = permanentHttp ||
        combined.contains('tvfull_no_progress') ||
        combined.contains('tvfull_stall_exhausted') ||
        combined.contains('io_bad_http_status') ||
        combined.contains('response_code_5') ||
        combined.contains('network') ||
        combined.contains('timeout') ||
        combined.contains('connection') ||
        status == 404 ||
        status == 408 ||
        status == 429 ||
        (status != null && status >= 500 && status <= 599);
    if (shouldCooldown) {
      _health.markDead(_channel, reason: code);
    }
    _finishWithError(_friendlyMessage(combined), '$code · $detail');
  }

  String _friendlyMessage(String value) {
    if (value.contains('parsing_container') ||
        value.contains('parser') ||
        value.contains('malformed')) {
      return 'Formato de señal no compatible';
    }
    if (value.contains('decoder') || value.contains('codec')) {
      return 'Formato de video no compatible';
    }
    if (value.contains('timeout') ||
        value.contains('network') ||
        value.contains('connection')) {
      return 'Problema de conexión';
    }
    if (value.contains('http') || value.contains('response_code')) {
      return 'Canal no disponible';
    }
    return 'Canal temporalmente no disponible';
  }''',
    '''  void _handleTechnicalError(
    String code,
    String detail, {
    int? httpStatus,
    bool? retryable,
    String? category,
  }) {
    debugPrint(
      'TV FULL PRO LIVE [$code] $detail '
      'http=$httpStatus retryable=$retryable category=$category',
    );
    final decision = LivePlaybackErrorPolicy.decide(
      code: code,
      detail: detail,
      retryCount: _autoRetryCount,
      httpStatus: httpStatus,
      nativeRetryable: retryable,
      category: category,
    );

    if (decision.shouldRetry) {
      _autoRetryCount++;
      if (mounted) {
        setState(() {
          _buffering = true;
          _friendlyError = null;
        });
      }
      _retryTimer = Timer(decision.retryDelay, () {
        if (mounted) {
          unawaited(
            _prepareCurrent(
              preserveRetry: true,
              keepChannelListOpen: _channelListVisible,
            ),
          );
        }
      });
      return;
    }

    if (decision.markDead) {
      _health.markDead(_channel, reason: code);
    }
    _finishWithError(decision.friendlyMessage, '$code · $detail');
  }''',
    'player screen structured retry policy',
)

# Xtream shared transport with explicit cancellation generation.
write_file(
    'lib/services/xtream_http_client.dart',
    '''import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class XtreamRequestCancelled implements Exception {
  const XtreamRequestCancelled();

  @override
  String toString() => 'La operación Xtream fue reemplazada por una más nueva.';
}

/// Cliente HTTP compartido para Xtream con pool nativo y cancelación por generación.
class XtreamHttpClient {
  XtreamHttpClient._();

  static final _RestartableXtreamClient instance = _RestartableXtreamClient();

  static int get generation => instance.generation;

  /// Comienza una navegación nueva y corta transferencias de navegación viejas.
  static int beginBrowsingOperation() => instance.cancelBrowsing();

  static void ensureGeneration(int expected) => instance.ensureGeneration(expected);

  /// Se conserva para los sitios que priorizan reproducción sobre navegación.
  static void cancelBrowsingRequests() => instance.cancelBrowsing();

  /// Reinicia solamente sockets/pool para un retry interno de la misma operación.
  static void restartTransport() => instance.restartTransport();

  static const String browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/96.0.4664.18 Safari/537.36';

  static const Map<String, String> jsonHeaders = <String, String>{
    'User-Agent': browserUserAgent,
    'Accept': 'application/json,text/plain,*/*',
    'Connection': 'keep-alive',
  };
}

http.Client _newNativeClient() {
  final io = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 4
    ..autoUncompress = true;
  return IOClient(io);
}

class _RestartableXtreamClient extends http.BaseClient {
  http.Client _inner = _newNativeClient();
  bool _closed = false;
  int _generation = 0;

  int get generation => _generation;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) {
      return Future<http.StreamedResponse>.error(
        StateError('El cliente Xtream ya fue cerrado.'),
      );
    }
    final client = _inner;
    return client.send(request);
  }

  int cancelBrowsing() {
    if (_closed) throw StateError('El cliente Xtream ya fue cerrado.');
    _generation++;
    restartTransport();
    return _generation;
  }

  void ensureGeneration(int expected) {
    if (_closed || expected != _generation) {
      throw const XtreamRequestCancelled();
    }
  }

  void restartTransport() {
    if (_closed) return;
    final previous = _inner;
    _inner = _newNativeClient();
    previous.close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _generation++;
    _inner.close();
  }
}
''',
)

# Xtream catalog generations: latest navigation wins and stale results cannot cache/overwrite.
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''  Directory? _cacheDirectory;
  Directory? _transferDirectory;

  Future<XtreamConnectionResult> connectionForPlaylist(''',
    '''  Directory? _cacheDirectory;
  Directory? _transferDirectory;
  int _movieRefreshGeneration = 0;
  int _seriesRefreshGeneration = 0;
  final Map<String, int> _sessionGenerations = <String, int>{};

  Future<XtreamConnectionResult> connectionForPlaylist(''',
    'fast catalog generation fields',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''  Future<XtreamConnectionResult> connectionForPlaylist(
    String playlistUrl, {
    bool forceRefresh = false,
  }) async {
    final key = playlistUrl.trim();
    if (!forceRefresh) {
      final cached = _sessions[key];
      if (cached != null) return cached;
      final pending = _pendingSessions[key];
      if (pending != null) return pending;
    }

    final future = XtreamService.reconnectFromPlaylistUrl(key);
    _pendingSessions[key] = future;
    try {
      final connection = await future;
      _sessions[key] = connection;
      _sessions[connection.playlistUrl] = connection;
      return connection;
    } finally {
      if (identical(_pendingSessions[key], future)) {
        _pendingSessions.remove(key);
      }
    }
  }''',
    '''  Future<XtreamConnectionResult> connectionForPlaylist(
    String playlistUrl, {
    bool forceRefresh = false,
  }) async {
    final key = playlistUrl.trim();
    if (!forceRefresh) {
      final cached = _sessions[key];
      if (cached != null) return cached;
      final pending = _pendingSessions[key];
      if (pending != null) return pending;
    }

    final transportGeneration = XtreamHttpClient.generation;
    final sessionGeneration = (_sessionGenerations[key] ?? 0) + 1;
    _sessionGenerations[key] = sessionGeneration;
    final future = XtreamService.reconnectFromPlaylistUrl(key);
    _pendingSessions[key] = future;
    try {
      final connection = await future;
      XtreamHttpClient.ensureGeneration(transportGeneration);
      if (_sessionGenerations[key] != sessionGeneration) {
        throw const XtreamRequestCancelled();
      }
      _sessions[key] = connection;
      _sessions[connection.playlistUrl] = connection;
      return connection;
    } finally {
      if (identical(_pendingSessions[key], future)) {
        _pendingSessions.remove(key);
      }
    }
  }''',
    'fast catalog session generation',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''  void invalidateSession(String playlistUrl) {
    _sessions.remove(playlistUrl.trim());
  }''',
    '''  void invalidateSession(String playlistUrl) {
    final key = playlistUrl.trim();
    _sessions.remove(key);
    _sessionGenerations[key] = (_sessionGenerations[key] ?? 0) + 1;
  }''',
    'fast catalog invalidate generation',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''  Future<XtreamMovieCatalogSnapshot> refreshMovies(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    final key = playlistUrl.trim();
    var connection = await _connectionForCatalog(
      playlistUrl,
      forceRefresh: forceSessionRefresh,
    );

    try {
      final snapshot = await _fetchMovies(connection, playlistUrl, onProgress);
      _rememberMovieSnapshot(key, snapshot);
      return snapshot;
    } on _XtreamHttpException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 403) rethrow;
      invalidateSession(playlistUrl);
      connection = await connectionForPlaylist(playlistUrl, forceRefresh: true);
      final snapshot = await _fetchMovies(connection, playlistUrl, onProgress);
      _rememberMovieSnapshot(key, snapshot);
      return snapshot;
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (error) {
      try {
        final movies = await XtreamVodService.fetchCatalog(connection);
        final categories = _categoriesFromMovies(movies);
        final snapshot = XtreamMovieCatalogSnapshot(
          connection: connection,
          movies: movies,
          categories: categories,
          savedAt: DateTime.now(),
          fromCache: false,
        );
        await _writeMovieCache(playlistUrl, snapshot);
        _rememberMovieSnapshot(key, snapshot);
        return snapshot;
      } catch (_) {
        throw error;
      }
    }
  }''',
    '''  Future<XtreamMovieCatalogSnapshot> refreshMovies(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    final key = playlistUrl.trim();
    final operationGeneration = ++_movieRefreshGeneration;
    final browsingGeneration = XtreamHttpClient.beginBrowsingOperation();
    void checkpoint() {
      if (operationGeneration != _movieRefreshGeneration) {
        throw const XtreamRequestCancelled();
      }
      XtreamHttpClient.ensureGeneration(browsingGeneration);
    }
    void progress(XtreamCatalogProgress value) {
      checkpoint();
      onProgress?.call(value);
    }

    var connection = await _connectionForCatalog(
      playlistUrl,
      forceRefresh: forceSessionRefresh,
    );
    checkpoint();

    try {
      final snapshot = await _fetchMovies(
        connection,
        playlistUrl,
        progress,
        checkpoint: checkpoint,
      );
      checkpoint();
      _rememberMovieSnapshot(key, snapshot);
      return snapshot;
    } on _XtreamHttpException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 403) rethrow;
      invalidateSession(playlistUrl);
      connection = await connectionForPlaylist(playlistUrl, forceRefresh: true);
      checkpoint();
      final snapshot = await _fetchMovies(
        connection,
        playlistUrl,
        progress,
        checkpoint: checkpoint,
      );
      checkpoint();
      _rememberMovieSnapshot(key, snapshot);
      return snapshot;
    } on XtreamRequestCancelled {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (error) {
      try {
        final movies = await XtreamVodService.fetchCatalog(connection);
        checkpoint();
        final categories = _categoriesFromMovies(movies);
        final snapshot = XtreamMovieCatalogSnapshot(
          connection: connection,
          movies: movies,
          categories: categories,
          savedAt: DateTime.now(),
          fromCache: false,
        );
        await _writeMovieCache(playlistUrl, snapshot, checkpoint: checkpoint);
        checkpoint();
        _rememberMovieSnapshot(key, snapshot);
        return snapshot;
      } on XtreamRequestCancelled {
        rethrow;
      } catch (_) {
        throw error;
      }
    }
  }''',
    'fast catalog movies generation',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''  Future<XtreamSeriesCatalogSnapshot> refreshSeries(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    final key = playlistUrl.trim();
    final totalWatch = Stopwatch()..start();
    final connectionWatch = Stopwatch()..start();
    var connection = await _connectionForCatalog(
      playlistUrl,
      forceRefresh: forceSessionRefresh,
    );
    connectionWatch.stop();
    var connectionElapsed = connectionWatch.elapsed;

    try {
      final snapshot = await _fetchSeries(
        connection,
        playlistUrl,
        onProgress,
        totalWatch: totalWatch,
        connectionElapsed: connectionElapsed,
      );
      _rememberSeriesSnapshot(key, snapshot);
      return snapshot;
    } on _XtreamHttpException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 403) rethrow;
      invalidateSession(playlistUrl);
      final authWatch = Stopwatch()..start();
      connection = await connectionForPlaylist(playlistUrl, forceRefresh: true);
      authWatch.stop();
      connectionElapsed += authWatch.elapsed;
      final snapshot = await _fetchSeries(
        connection,
        playlistUrl,
        onProgress,
        totalWatch: totalWatch,
        connectionElapsed: connectionElapsed,
      );
      _rememberSeriesSnapshot(key, snapshot);
      return snapshot;
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (error) {
      try {
        final fallbackWatch = Stopwatch()..start();
        final series = await XtreamSeriesService.fetchCatalog(connection);
        fallbackWatch.stop();
        final categories = _categoriesFromSeries(series);''',
    '''  Future<XtreamSeriesCatalogSnapshot> refreshSeries(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    final key = playlistUrl.trim();
    final operationGeneration = ++_seriesRefreshGeneration;
    final browsingGeneration = XtreamHttpClient.beginBrowsingOperation();
    void checkpoint() {
      if (operationGeneration != _seriesRefreshGeneration) {
        throw const XtreamRequestCancelled();
      }
      XtreamHttpClient.ensureGeneration(browsingGeneration);
    }
    void progress(XtreamCatalogProgress value) {
      checkpoint();
      onProgress?.call(value);
    }

    final totalWatch = Stopwatch()..start();
    final connectionWatch = Stopwatch()..start();
    var connection = await _connectionForCatalog(
      playlistUrl,
      forceRefresh: forceSessionRefresh,
    );
    checkpoint();
    connectionWatch.stop();
    var connectionElapsed = connectionWatch.elapsed;

    try {
      final snapshot = await _fetchSeries(
        connection,
        playlistUrl,
        progress,
        totalWatch: totalWatch,
        connectionElapsed: connectionElapsed,
        checkpoint: checkpoint,
      );
      checkpoint();
      _rememberSeriesSnapshot(key, snapshot);
      return snapshot;
    } on _XtreamHttpException catch (error) {
      if (error.statusCode != 401 && error.statusCode != 403) rethrow;
      invalidateSession(playlistUrl);
      final authWatch = Stopwatch()..start();
      connection = await connectionForPlaylist(playlistUrl, forceRefresh: true);
      checkpoint();
      authWatch.stop();
      connectionElapsed += authWatch.elapsed;
      final snapshot = await _fetchSeries(
        connection,
        playlistUrl,
        progress,
        totalWatch: totalWatch,
        connectionElapsed: connectionElapsed,
        checkpoint: checkpoint,
      );
      checkpoint();
      _rememberSeriesSnapshot(key, snapshot);
      return snapshot;
    } on XtreamRequestCancelled {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (error) {
      try {
        final fallbackWatch = Stopwatch()..start();
        final series = await XtreamSeriesService.fetchCatalog(connection);
        checkpoint();
        fallbackWatch.stop();
        final categories = _categoriesFromSeries(series);''',
    'fast catalog series generation prefix',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''        await _writeSeriesCache(playlistUrl, snapshot);
        _rememberSeriesSnapshot(key, snapshot);
        return snapshot;
      } catch (_) {
        throw error;
      }
    }
  }

  Future<XtreamMovieCatalogSnapshot> _fetchMovies(
    XtreamConnectionResult connection,
    String playlistUrl,
    XtreamCatalogProgressCallback? onProgress,
  ) async {''',
    '''        await _writeSeriesCache(playlistUrl, snapshot, checkpoint: checkpoint);
        checkpoint();
        _rememberSeriesSnapshot(key, snapshot);
        return snapshot;
      } on XtreamRequestCancelled {
        rethrow;
      } catch (_) {
        throw error;
      }
    }
  }

  Future<XtreamMovieCatalogSnapshot> _fetchMovies(
    XtreamConnectionResult connection,
    String playlistUrl,
    XtreamCatalogProgressCallback? onProgress, {
    required void Function() checkpoint,
  }) async {
    checkpoint();''',
    'fast catalog movies fetch signature',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''      categoriesBody = await _downloadActionBody(
        connection,
        'get_vod_categories',
        _categoryTimeout,
      );
    } catch (_) {''',
    '''      categoriesBody = await _downloadActionBody(
        connection,
        'get_vod_categories',
        _categoryTimeout,
      );
      checkpoint();
    } on XtreamRequestCancelled {
      rethrow;
    } catch (_) {''',
    'fast catalog movies category checkpoint',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''    final transfer = await _downloadActionFile(
      connection,
      'get_vod_streams',
      _movieTimeout,
      onBytes: (bytes) => onProgress?.call(''',
    '''    final transfer = await _downloadActionFile(
      connection,
      'get_vod_streams',
      _movieTimeout,
      onBytes: (bytes) => onProgress?.call(''',
    'fast catalog movie transfer anchor',
)
# Insert checkpoint after the MOVIE transfer block by a unique following marker.
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''      ),
    );

    onProgress?.call(
      const XtreamCatalogProgress(
        section: 'MOVIE',
        phase: 'Preparando catálogo',''',
    '''      ),
    );
    checkpoint();

    onProgress?.call(
      const XtreamCatalogProgress(
        section: 'MOVIE',
        phase: 'Preparando catálogo',''',
    'fast catalog movie transfer checkpoint',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''    } finally {
      unawaited(_deleteFileQuietly(transfer.file));
    }

    final movies = _movieListFromPrepared(prepared['items']);''',
    '''    } finally {
      unawaited(_deleteFileQuietly(transfer.file));
    }
    checkpoint();

    final movies = _movieListFromPrepared(prepared['items']);''',
    'fast catalog movie compute checkpoint',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''    if (connection.serverName != null ||
        connection.status != null ||
        connection.expiration != null) {
      rememberConnection(connection);
    }
    await _writePreparedCache(
      playlistUrl,
      'movies',
      prepared,
      snapshot.savedAt,
    );
    return snapshot;
  }

  Future<XtreamSeriesCatalogSnapshot> _fetchSeries(''',
    '''    checkpoint();
    if (connection.serverName != null ||
        connection.status != null ||
        connection.expiration != null) {
      rememberConnection(connection);
    }
    await _writePreparedCache(
      playlistUrl,
      'movies',
      prepared,
      snapshot.savedAt,
      checkpoint: checkpoint,
    );
    checkpoint();
    return snapshot;
  }

  Future<XtreamSeriesCatalogSnapshot> _fetchSeries(''',
    'fast catalog movie cache checkpoint',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''    XtreamCatalogProgressCallback? onProgress, {
    required Stopwatch totalWatch,
    required Duration connectionElapsed,
  }) async {
    onProgress?.call(''',
    '''    XtreamCatalogProgressCallback? onProgress, {
    required Stopwatch totalWatch,
    required Duration connectionElapsed,
    required void Function() checkpoint,
  }) async {
    checkpoint();
    onProgress?.call(''',
    'fast catalog series fetch signature',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''      categoriesBody = await _downloadActionBody(
        connection,
        'get_series_categories',
        _categoryTimeout,
        onBytes: (value) => categoryBytes = value,
      );
    } catch (_) {''',
    '''      categoriesBody = await _downloadActionBody(
        connection,
        'get_series_categories',
        _categoryTimeout,
        onBytes: (value) => categoryBytes = value,
      );
      checkpoint();
    } on XtreamRequestCancelled {
      rethrow;
    } catch (_) {''',
    'fast catalog series category checkpoint',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''      ),
    );

    onProgress?.call(
      const XtreamCatalogProgress(
        section: 'SERIES',
        phase: 'Preparando catálogo',''',
    '''      ),
    );
    checkpoint();

    onProgress?.call(
      const XtreamCatalogProgress(
        section: 'SERIES',
        phase: 'Preparando catálogo',''',
    'fast catalog series transfer checkpoint',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''    } finally {
      unawaited(_deleteFileQuietly(transfer.file));
    }
    prepareWatch.stop();''',
    '''    } finally {
      unawaited(_deleteFileQuietly(transfer.file));
    }
    checkpoint();
    prepareWatch.stop();''',
    'fast catalog series compute checkpoint',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''    await _writePreparedCache(
      playlistUrl,
      'series',
      prepared,
      snapshot.savedAt,
    );
    return snapshot;''',
    '''    await _writePreparedCache(
      playlistUrl,
      'series',
      prepared,
      snapshot.savedAt,
      checkpoint: checkpoint,
    );
    checkpoint();
    return snapshot;''',
    'fast catalog series cache checkpoint',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''  Future<void> _writePreparedCache(
    String playlistUrl,
    String kind,
    Map<String, dynamic> prepared,
    DateTime savedAt,
  ) async {''',
    '''  Future<void> _writePreparedCache(
    String playlistUrl,
    String kind,
    Map<String, dynamic> prepared,
    DateTime savedAt, {
    void Function()? checkpoint,
  }) async {''',
    'fast catalog prepared cache signature',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''    await _writeCache(playlistUrl, kind, payload);
  }

  Future<void> _writeMovieCache(
    String playlistUrl,
    XtreamMovieCatalogSnapshot snapshot,
  ) async {''',
    '''    await _writeCache(playlistUrl, kind, payload, checkpoint: checkpoint);
  }

  Future<void> _writeMovieCache(
    String playlistUrl,
    XtreamMovieCatalogSnapshot snapshot, {
    void Function()? checkpoint,
  }) async {''',
    'fast catalog movie cache signature',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''    await _writeCache(playlistUrl, 'movies', payload);
  }

  Future<void> _writeSeriesCache(
    String playlistUrl,
    XtreamSeriesCatalogSnapshot snapshot,
  ) async {''',
    '''    await _writeCache(
      playlistUrl,
      'movies',
      payload,
      checkpoint: checkpoint,
    );
  }

  Future<void> _writeSeriesCache(
    String playlistUrl,
    XtreamSeriesCatalogSnapshot snapshot, {
    void Function()? checkpoint,
  }) async {''',
    'fast catalog series cache signature',
)
replace_once(
    'lib/services/xtream_fast_catalog_service.dart',
    '''    await _writeCache(playlistUrl, 'series', payload);
  }

  Future<void> _writeCache(
    String playlistUrl,
    String kind,
    Map<String, dynamic> payload,
  ) async {
    final encoded = await compute(_encodeCachePayload, payload);
    final file = await _cacheFile(playlistUrl, kind);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(encoded, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }''',
    '''    await _writeCache(
      playlistUrl,
      'series',
      payload,
      checkpoint: checkpoint,
    );
  }

  Future<void> _writeCache(
    String playlistUrl,
    String kind,
    Map<String, dynamic> payload, {
    void Function()? checkpoint,
  }) async {
    final encoded = await compute(_encodeCachePayload, payload);
    checkpoint?.call();
    final file = await _cacheFile(playlistUrl, kind);
    final temp = File(
      '${file.path}.tmp_${DateTime.now().microsecondsSinceEpoch}',
    );
    await temp.writeAsString(encoded, flush: true);
    checkpoint?.call();
    if (await file.exists()) {
      checkpoint?.call();
      await file.delete();
    }
    checkpoint?.call();
    await temp.rename(file.path);
  }''',
    'fast catalog atomic cache generation',
)

# LIVE Xtream generation checkpoints and same-operation transport retry.
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '''  final Map<String, Future<XtreamLiveCatalogSnapshot?>> _pendingCacheReads =
      <String, Future<XtreamLiveCatalogSnapshot?>>{};

  String? get lastDiagnostics => _lastDiagnostics;''',
    '''  final Map<String, Future<XtreamLiveCatalogSnapshot?>> _pendingCacheReads =
      <String, Future<XtreamLiveCatalogSnapshot?>>{};
  int _refreshGeneration = 0;

  String? get lastDiagnostics => _lastDiagnostics;''',
    'live catalog generation field',
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '''  Future<XtreamLiveCatalogSnapshot> refresh(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    final totalWatch = Stopwatch()..start();
    try {
      // Siempre resolvemos la sesión real al refrescar LIVE. Esto evita depender
      // de una conexión provisional y respeta host/protocolo/puerto server_info.
      var connection = await XtreamFastCatalogService.instance
          .connectionForPlaylist(playlistUrl, forceRefresh: true);

      try {
        return await _fetch(
          connection,
          playlistUrl,
          onProgress,
          totalWatch: totalWatch,
        );
      } on _XtreamLiveHttpException catch (error) {
        if (error.statusCode != 401 && error.statusCode != 403) rethrow;
        XtreamFastCatalogService.instance.invalidateSession(playlistUrl);
        connection = await XtreamFastCatalogService.instance
            .connectionForPlaylist(playlistUrl, forceRefresh: true);
        return await _fetch(
          connection,
          playlistUrl,
          onProgress,
          totalWatch: totalWatch,
        );
      }
    } catch (error) {''',
    '''  Future<XtreamLiveCatalogSnapshot> refresh(
    String playlistUrl, {
    XtreamCatalogProgressCallback? onProgress,
    bool forceSessionRefresh = false,
  }) async {
    final operationGeneration = ++_refreshGeneration;
    final browsingGeneration = XtreamHttpClient.beginBrowsingOperation();
    void checkpoint() {
      if (operationGeneration != _refreshGeneration) {
        throw const XtreamRequestCancelled();
      }
      XtreamHttpClient.ensureGeneration(browsingGeneration);
    }
    void progress(XtreamCatalogProgress value) {
      checkpoint();
      onProgress?.call(value);
    }

    final totalWatch = Stopwatch()..start();
    try {
      // Siempre resolvemos la sesión real al refrescar LIVE. Esto evita depender
      // de una conexión provisional y respeta host/protocolo/puerto server_info.
      var connection = await XtreamFastCatalogService.instance
          .connectionForPlaylist(playlistUrl, forceRefresh: true);
      checkpoint();

      try {
        return await _fetch(
          connection,
          playlistUrl,
          progress,
          totalWatch: totalWatch,
          checkpoint: checkpoint,
        );
      } on _XtreamLiveHttpException catch (error) {
        if (error.statusCode != 401 && error.statusCode != 403) rethrow;
        XtreamFastCatalogService.instance.invalidateSession(playlistUrl);
        connection = await XtreamFastCatalogService.instance
            .connectionForPlaylist(playlistUrl, forceRefresh: true);
        checkpoint();
        return await _fetch(
          connection,
          playlistUrl,
          progress,
          totalWatch: totalWatch,
          checkpoint: checkpoint,
        );
      }
    } on XtreamRequestCancelled {
      rethrow;
    } catch (error) {''',
    'live catalog refresh generation',
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '''    XtreamCatalogProgressCallback? onProgress, {
    required Stopwatch totalWatch,
  }) async {
    onProgress?.call(''',
    '''    XtreamCatalogProgressCallback? onProgress, {
    required Stopwatch totalWatch,
    required void Function() checkpoint,
  }) async {
    checkpoint();
    onProgress?.call(''',
    'live catalog fetch signature',
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '''      categoriesBody = categoryResult.body;
    } catch (_) {''',
    '''      categoriesBody = categoryResult.body;
      checkpoint();
    } on XtreamRequestCancelled {
      rethrow;
    } catch (_) {''',
    'live category checkpoint',
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '''    final transfer = await _downloadActionFile(
      connection,
      'get_live_streams',
      _liveTimeout,
      onBytes: (bytes) => onProgress?.call(
        XtreamCatalogProgress(
          section: 'LIVE',
          phase: 'Cargando lista',
          step: 2,
          totalSteps: 3,
          receivedBytes: bytes,
        ),
      ),
    );

    onProgress?.call(''',
    '''    final transfer = await _downloadActionFile(
      connection,
      'get_live_streams',
      _liveTimeout,
      onBytes: (bytes) => onProgress?.call(
        XtreamCatalogProgress(
          section: 'LIVE',
          phase: 'Cargando lista',
          step: 2,
          totalSteps: 3,
          receivedBytes: bytes,
        ),
      ),
    );
    checkpoint();

    onProgress?.call(''',
    'live transfer checkpoint',
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '''    } finally {
      unawaited(_deleteFileQuietly(transfer.file));
    }
    prepareWatch.stop();''',
    '''    } finally {
      unawaited(_deleteFileQuietly(transfer.file));
    }
    checkpoint();
    prepareWatch.stop();''',
    'live prepare checkpoint',
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '''    await metaTemp.writeAsString(
      jsonEncode(<String, dynamic>{
        'version': _cacheVersion,
        'kind': 'live',
        'savedAt': savedAt.millisecondsSinceEpoch,
        'count': count,
        'categories': categories,
      }),
      flush: true,
    );

    await _replaceFile(itemsTemp, files.items);
    await _replaceFile(metaTemp, files.meta);''',
    '''    await metaTemp.writeAsString(
      jsonEncode(<String, dynamic>{
        'version': _cacheVersion,
        'kind': 'live',
        'savedAt': savedAt.millisecondsSinceEpoch,
        'count': count,
        'categories': categories,
      }),
      flush: true,
    );
    checkpoint();

    await _replaceFile(itemsTemp, files.items);
    checkpoint();
    await _replaceFile(metaTemp, files.meta);
    checkpoint();''',
    'live cache replace checkpoint',
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '''    final cached = await _loadCachedFromDisk(playlistUrl);
    if (cached == null || cached.channels.isEmpty) {''',
    '''    final cached = await _loadCachedFromDisk(playlistUrl);
    checkpoint();
    if (cached == null || cached.channels.isEmpty) {''',
    'live cache read checkpoint',
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '        XtreamHttpClient.cancelBrowsingRequests();\n        await Future<void>.delayed(const Duration(milliseconds: 650));',
    '        XtreamHttpClient.restartTransport();\n        await Future<void>.delayed(const Duration(milliseconds: 650));',
    'live transfer retry keeps generation',
)
replace_once(
    'lib/services/xtream_live_fast_service.dart',
    '        XtreamHttpClient.cancelBrowsingRequests();\n        await Future<void>.delayed(const Duration(milliseconds: 650));',
    '        XtreamHttpClient.restartTransport();\n        await Future<void>.delayed(const Duration(milliseconds: 650));',
    'live body retry keeps generation',
)

# Tests for the behavior that caused the original V38 problem.
write_file(
    'test/live_playback_error_policy_test.dart',
    '''import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/live_playback_error_policy.dart';

void main() {
  test('401 403 404 410 are terminal and mark channel dead', () {
    for (final status in <int>[401, 403, 404, 410]) {
      final decision = LivePlaybackErrorPolicy.decide(
        code: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
        detail: 'HTTP $status',
        retryCount: 0,
        httpStatus: status,
        nativeRetryable: true,
        category: 'http_terminal',
      );
      expect(decision.shouldRetry, isFalse, reason: '$status must be terminal');
      expect(decision.markDead, isTrue, reason: '$status must cooldown fast');
    }
  });

  test('network failures use bounded 240 600 1200 ms retries', () {
    final delays = <int>[];
    for (var retryCount = 0; retryCount < 3; retryCount++) {
      final decision = LivePlaybackErrorPolicy.decide(
        code: 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
        detail: 'connection reset',
        retryCount: retryCount,
        nativeRetryable: true,
        category: 'network',
      );
      expect(decision.shouldRetry, isTrue);
      expect(decision.markDead, isFalse);
      delays.add(decision.retryDelay.inMilliseconds);
    }
    expect(delays, <int>[240, 600, 1200]);

    final exhausted = LivePlaybackErrorPolicy.decide(
      code: 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
      detail: 'connection reset',
      retryCount: 3,
      nativeRetryable: true,
      category: 'network',
    );
    expect(exhausted.shouldRetry, isFalse);
    expect(exhausted.markDead, isFalse);
  });

  test('5xx is transient and never becomes permanent cooldown by itself', () {
    final decision = LivePlaybackErrorPolicy.decide(
      code: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
      detail: 'HTTP 503',
      retryCount: 3,
      httpStatus: 503,
      nativeRetryable: true,
      category: 'http_transient',
    );
    expect(decision.shouldRetry, isFalse);
    expect(decision.markDead, isFalse);
  });

  test('no progress and exhausted stall are terminal for channel health', () {
    for (final code in <String>[
      'TVFULL_NO_PROGRESS',
      'TVFULL_STALL_EXHAUSTED',
    ]) {
      final decision = LivePlaybackErrorPolicy.decide(
        code: code,
        detail: 'signal stopped',
        retryCount: 0,
        category: 'no_progress',
      );
      expect(decision.shouldRetry, isFalse);
      expect(decision.markDead, isTrue);
    }
  });

  test('decoder errors are not mistaken for network failures', () {
    final decision = LivePlaybackErrorPolicy.decide(
      code: 'ERROR_CODE_DECODING_FAILED',
      detail: 'decoder failed',
      retryCount: 0,
      nativeRetryable: false,
      category: 'decoder',
    );
    expect(decision.shouldRetry, isFalse);
    expect(decision.markDead, isFalse);
    expect(decision.friendlyMessage, 'Formato de video no compatible');
  });
}
''',
)
write_file(
    'test/xtream_http_client_generation_test.dart',
    '''import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/xtream_http_client.dart';

void main() {
  test('new browsing operation invalidates the previous generation', () {
    final first = XtreamHttpClient.beginBrowsingOperation();
    XtreamHttpClient.ensureGeneration(first);

    final second = XtreamHttpClient.beginBrowsingOperation();
    expect(second, greaterThan(first));
    XtreamHttpClient.ensureGeneration(second);
    expect(
      () => XtreamHttpClient.ensureGeneration(first),
      throwsA(isA<XtreamRequestCancelled>()),
    );
  });

  test('transport restart keeps the same browsing generation', () {
    final generation = XtreamHttpClient.beginBrowsingOperation();
    XtreamHttpClient.restartTransport();
    expect(XtreamHttpClient.generation, generation);
    XtreamHttpClient.ensureGeneration(generation);
  });
}
''',
)

print('V38 clean performance patch applied successfully.')
