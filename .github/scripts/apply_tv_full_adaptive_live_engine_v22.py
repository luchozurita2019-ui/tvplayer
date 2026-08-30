from pathlib import Path

ROOT = Path('.')
main_path = ROOT / 'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt'
policy_path = ROOT / 'android/app/src/main/kotlin/com/example/iptv_player/TvFullLiveLoadErrorPolicy.kt'
profile_path = ROOT / 'android/app/src/main/kotlin/com/example/iptv_player/TvFullAdaptiveLiveProfileStore.kt'
dart_path = ROOT / 'lib/screens/android_media3_texture_player_screen.dart'
pubspec_path = ROOT / 'pubspec.yaml'

main = main_path.read_text()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing patch anchor: {label}')
    if text.count(old) != 1:
        raise SystemExit(f'non-unique patch anchor: {label} count={text.count(old)}')
    return text.replace(old, new, 1)

main = replace_once(
    main,
    '    private var liveStallRecoveries = 0\n    private val mainHandler = Handler(Looper.getMainLooper())',
    '''    private var liveStallRecoveries = 0
    private var currentAdaptiveLevel = 0
    private var liveSessionRebuffers = 0
    private var liveStableWindows = 0
    private var liveReadySinceMs = 0L
    private var lastBandwidthEstimate = 0L
    private val adaptiveProfiles by lazy { TvFullAdaptiveLiveProfileStore(this) }
    private val mainHandler = Handler(Looper.getMainLooper())''',
    'adaptive fields',
)

main = replace_once(
    main,
    '            when (call.method) {\n                "initialize" -> result.success(',
    '''            when (call.method) {
                "getLiveAdaptiveLevel" -> {
                    val url = call.argument<String>("url") ?: ""
                    result.success(if (url.isBlank()) 0 else adaptiveProfiles.loadLevel(url))
                }

                "initialize" -> result.success(''',
    'adaptive level method',
)

main = replace_once(
    main,
    '''        currentUrl = url
        currentHeaders = headers.toMap()
        currentUserAgent = userAgent
        endedRecoveries = 0
        liveStallRecoveries = 0
        liveEverReady = false
        liveBufferLastProgressAtMs = 0L
        liveBufferLastPositionMs = 0L
        dnsFallbackActive = false''',
    '''        currentUrl = url
        currentHeaders = headers.toMap()
        currentUserAgent = userAgent
        currentAdaptiveLevel = if (isLive) adaptiveProfiles.loadLevel(url) else 0
        liveLoadErrorPolicy.protectionLevel = currentAdaptiveLevel
        endedRecoveries = 0
        liveStallRecoveries = 0
        liveSessionRebuffers = 0
        liveStableWindows = 0
        liveReadySinceMs = 0L
        lastBandwidthEstimate = 0L
        liveEverReady = false
        liveBufferLastProgressAtMs = 0L
        liveBufferLastPositionMs = 0L
        dnsFallbackActive = false
        emitAdaptiveProfile("loaded")''',
    'prepare adaptive reset',
)

main = replace_once(
    main,
    '''        val factory = mediaSourceFactory(headers, userAgent, useFallbackDns)
        val source = factory.createMediaSource(
            MediaItem.Builder().setUri(Uri.parse(url)).build()
        )''',
    '''        val factory = mediaSourceFactory(headers, userAgent, useFallbackDns)
        val itemBuilder = MediaItem.Builder().setUri(Uri.parse(url))
        if (isLive) {
            val targetOffset = adaptiveTargetOffsetMs(currentAdaptiveLevel)
            itemBuilder.setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setTargetOffsetMs(targetOffset)
                    .setMinOffsetMs((targetOffset - 2500L).coerceAtLeast(2000L))
                    .setMaxOffsetMs(targetOffset + 5000L)
                    .build()
            )
        }
        val source = factory.createMediaSource(itemBuilder.build())''',
    'live configuration',
)

main = replace_once(
    main,
    '''            // Tras 30 s continuos de reproducción sana permitimos nuevamente
            // recuperaciones futuras. Evita loops rápidos, pero no penaliza una
            // señal que tiene un microcorte aislado mucho más tarde.
            endedRecoveries = 0
            liveStallRecoveries = 0''',
    '''            // Tras 30 s continuos de reproducción sana permitimos nuevamente
            // recuperaciones futuras. Además acumulamos ventanas sanas para que
            // un canal pueda volver gradualmente a un perfil menos conservador.
            endedRecoveries = 0
            liveStallRecoveries = 0
            liveStableWindows++
            if (liveStableWindows >= 6 && currentAdaptiveLevel > 0) {
                currentAdaptiveLevel--
                adaptiveProfiles.saveLevel(currentUrl.orEmpty(), currentAdaptiveLevel)
                liveLoadErrorPolicy.protectionLevel = currentAdaptiveLevel
                liveStableWindows = 0
                liveSessionRebuffers = 0
                emitAdaptiveProfile("stable_relax")
            }
            scheduleLiveStabilityReset(generation)''',
    'stable learning',
)

main = replace_once(
    main,
    '''                if (isLive && liveEverReady) {
                    if (liveBufferLastProgressAtMs == 0L) {''',
    '''                if (isLive && liveEverReady) {
                    liveStableWindows = 0
                    liveSessionRebuffers++
                    evaluateAdaptiveProfile("rebuffer")
                    if (liveBufferLastProgressAtMs == 0L) {''',
    'rebuffer learning',
)

main = replace_once(
    main,
    '''                cancelStartupDeadline()
                cancelLiveBufferHealthCheck()
                liveEverReady = liveEverReady || isLive
                liveBufferLastProgressAtMs = 0L''',
    '''                cancelStartupDeadline()
                cancelLiveBufferHealthCheck()
                liveEverReady = liveEverReady || isLive
                if (isLive && liveReadySinceMs == 0L) {
                    liveReadySinceMs = System.currentTimeMillis()
                }
                liveBufferLastProgressAtMs = 0L''',
    'ready timestamp',
)

adaptive_helpers = r'''
    private fun adaptiveTargetOffsetMs(level: Int): Long {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val lowRam = manager.isLowRamDevice
        return when (level.coerceIn(0, 3)) {
            0 -> 4500L
            1 -> 7000L
            2 -> 10000L
            else -> if (lowRam) 11000L else 14000L
        }
    }

    private fun selectedVideoBitrate(): Int {
        val tracks = player?.currentTracks ?: return 0
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSelected(trackIndex)) continue
                val bitrate = group.getTrackFormat(trackIndex).bitrate
                if (bitrate > 0) return bitrate
            }
        }
        return 0
    }

    private fun evaluateAdaptiveProfile(reason: String) {
        if (!isLive) return
        val url = currentUrl ?: return
        var desired = currentAdaptiveLevel

        desired = when {
            liveSessionRebuffers >= 6 -> maxOf(desired, 3)
            liveSessionRebuffers >= 4 -> maxOf(desired, 2)
            liveSessionRebuffers >= 2 -> maxOf(desired, 1)
            else -> desired
        }

        val videoBitrate = selectedVideoBitrate()
        val estimate = lastBandwidthEstimate
        val readyLongEnough = liveReadySinceMs > 0L &&
            System.currentTimeMillis() - liveReadySinceMs >= 12000L
        if (readyLongEnough && videoBitrate > 0 && estimate > 0L) {
            val headroom = estimate.toDouble() / videoBitrate.toDouble()
            desired = when {
                headroom < 1.10 -> maxOf(desired, 3)
                headroom < 1.30 -> maxOf(desired, 2)
                headroom < 1.60 -> maxOf(desired, 1)
                else -> desired
            }
        }

        desired = desired.coerceIn(0, 3)
        if (desired <= currentAdaptiveLevel) return
        currentAdaptiveLevel = desired
        adaptiveProfiles.saveLevel(url, desired)
        liveLoadErrorPolicy.protectionLevel = desired
        liveStableWindows = 0
        emitAdaptiveProfile(reason)
    }

    private fun emitAdaptiveProfile(reason: String) {
        if (!isLive || currentUrl.isNullOrBlank()) return
        eventSink?.success(
            mapOf(
                "eventType" to "adaptiveProfile",
                "level" to currentAdaptiveLevel,
                "reason" to reason,
                "rebufferCount" to liveSessionRebuffers,
                "bandwidthEstimate" to lastBandwidthEstimate,
                "videoBitrate" to selectedVideoBitrate(),
                "targetLiveOffsetMs" to adaptiveTargetOffsetMs(currentAdaptiveLevel),
            )
        )
    }

'''
main = replace_once(
    main,
    '    private fun selectTrack(\n',
    adaptive_helpers + '    private fun selectTrack(\n',
    'adaptive helper functions',
)

bandwidth_override = r'''
    override fun onBandwidthEstimate(
        eventTime: AnalyticsListener.EventTime,
        totalLoadTimeMs: Int,
        totalBytesLoaded: Long,
        bitrateEstimate: Long,
    ) {
        if (!isLive || bitrateEstimate <= 0L) return
        lastBandwidthEstimate = bitrateEstimate
        evaluateAdaptiveProfile("bandwidth")
    }

'''
main = replace_once(
    main,
    '    override fun onVideoCodecError(\n',
    bandwidth_override + '    override fun onVideoCodecError(\n',
    'bandwidth analytics',
)

main = replace_once(
    main,
    '''        endedRecoveries = 0
        liveStallRecoveries = 0
        liveEverReady = false
        liveBufferLastProgressAtMs = 0L
        liveBufferLastPositionMs = 0L
        dnsFallbackActive = false''',
    '''        endedRecoveries = 0
        liveStallRecoveries = 0
        currentAdaptiveLevel = 0
        liveSessionRebuffers = 0
        liveStableWindows = 0
        liveReadySinceMs = 0L
        lastBandwidthEstimate = 0L
        liveEverReady = false
        liveBufferLastProgressAtMs = 0L
        liveBufferLastPositionMs = 0L
        dnsFallbackActive = false''',
    'dispose adaptive reset',
)

main_path.write_text(main)

profile_path.write_text(r'''package com.example.iptv_player

import android.content.Context
import java.security.MessageDigest

/**
 * Tiny local memory for channels that proved unstable.
 *
 * Only non-zero protection levels are persisted, so large playlists do not
 * create a large database. URLs are hashed before becoming preference keys.
 */
class TvFullAdaptiveLiveProfileStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(
        "tvfull_live_adaptive_profiles_v1",
        Context.MODE_PRIVATE,
    )

    fun loadLevel(url: String): Int {
        if (url.isBlank()) return 0
        return prefs.getInt(key(url), 0).coerceIn(0, 3)
    }

    fun saveLevel(url: String, level: Int) {
        if (url.isBlank()) return
        val key = key(url)
        val safeLevel = level.coerceIn(0, 3)
        if (safeLevel == 0) {
            prefs.edit().remove(key).apply()
        } else {
            prefs.edit().putInt(key, safeLevel).apply()
        }
    }

    private fun key(url: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(url.toByteArray(Charsets.UTF_8))
        val shortHash = digest.take(12).joinToString("") { "%02x".format(it) }
        return "channel_$shortHash"
    }
}
''')

policy_path.write_text(r'''package com.example.iptv_player

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy

/** Segment/request recovery whose retry budget follows the learned channel profile. */
@UnstableApi
class TvFullLiveLoadErrorPolicy : DefaultLoadErrorHandlingPolicy() {
    @Volatile
    var protectionLevel: Int = 0

    override fun getMinimumLoadableRetryCount(dataType: Int): Int {
        val level = protectionLevel.coerceIn(0, 3)
        return when (dataType) {
            C.DATA_TYPE_MEDIA_PROGRESSIVE_LIVE -> 6 + level
            C.DATA_TYPE_MEDIA, C.DATA_TYPE_MANIFEST -> 4 + level
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
                429 -> return (1500L * loadErrorInfo.errorCount).coerceAtMost(6000L)
                in 500..599 -> return when (loadErrorInfo.errorCount) {
                    1 -> 250L
                    2 -> 600L
                    3 -> 1200L
                    else -> (1500L + protectionLevel * 250L).coerceAtMost(2500L)
                }
            }
        }

        val defaultDelay = super.getRetryDelayMsFor(loadErrorInfo)
        if (defaultDelay == C.TIME_UNSET) return C.TIME_UNSET
        return when (loadErrorInfo.errorCount) {
            1 -> 250L
            2 -> 600L
            3 -> 1200L
            else -> defaultDelay.coerceAtMost(2500L)
        }
    }
}
''')

dart = dart_path.read_text()
dart = replace_once(
    dart,
    '''      final lowRam = DevicePerformanceService.instance.lowRam;
      final id = await _player.invokeMethod<int>('initialize', {
        // Arranque rápido, pero con reserva suficiente para servidores que
        // entregan segmentos de forma irregular. LOW_RAM usa una ventana
        // ligeramente menor para no castigar TVs modestos.
        'minBuffer': lowRam ? 4000 : 5000,
        'maxBuffer': lowRam ? 12000 : 15000,
        'bufferForPlayback': 1000,
        'bufferForPlaybackAfterRebuffer': lowRam ? 2200 : 2500,
      });''',
    '''      final lowRam = DevicePerformanceService.instance.lowRam;
      var adaptiveLevel = 0;
      if (widget.playlist.isNotEmpty) {
        try {
          adaptiveLevel =
              await _player.invokeMethod<int>('getLiveAdaptiveLevel', {
                    'url': _channel.url,
                  }) ??
                  0;
        } on PlatformException {
          adaptiveLevel = 0;
        }
      }
      final level = adaptiveLevel.clamp(0, 3).toInt();
      final normalMin = <int>[5000, 6000, 7000, 8000][level];
      final normalMax = <int>[15000, 19000, 23000, 28000][level];
      final normalRebuffer = <int>[2500, 3000, 3500, 4000][level];
      final lowRamMin = <int>[4000, 4500, 5000, 5500][level];
      final lowRamMax = <int>[12000, 14000, 16000, 18000][level];
      final lowRamRebuffer = <int>[2200, 2500, 2800, 3000][level];
      final id = await _player.invokeMethod<int>('initialize', {
        // Perfil aprendido por canal: la primera imagen sigue arrancando con
        // 1 s, pero canales problemáticos reciben más reserva de forma local.
        // LOW_RAM mantiene límites estrictos para no castigar hardware modesto.
        'minBuffer': lowRam ? lowRamMin : normalMin,
        'maxBuffer': lowRam ? lowRamMax : normalMax,
        'bufferForPlayback': 1000,
        'bufferForPlaybackAfterRebuffer':
            lowRam ? lowRamRebuffer : normalRebuffer,
      });''',
    'dart learned startup profile',
)

dart = replace_once(
    dart,
    '''      case 'liveRecovery':
        debugPrint(
          'TV FULL PRO LIVE recovery: ${event['reason']} '
          'attempt=${event['attempt']}',
        );
        break;''',
    '''      case 'liveRecovery':
        debugPrint(
          'TV FULL PRO LIVE recovery: ${event['reason']} '
          'attempt=${event['attempt']}',
        );
        break;
      case 'adaptiveProfile':
        debugPrint(
          'TV FULL PRO LIVE adaptive level=${event['level']} '
          'reason=${event['reason']} rebuffers=${event['rebufferCount']} '
          'bandwidth=${event['bandwidthEstimate']} bitrate=${event['videoBitrate']}',
        );
        break;''',
    'dart adaptive event',
)

dart_path.write_text(dart)

pubspec = pubspec_path.read_text()
pubspec = replace_once(pubspec, 'version: 1.2.9+21', 'version: 1.3.0+22', 'version bump')
pubspec += '\n# TV FULL PRO 1.3.0+22 adaptive-live-engine-v22\n'
pubspec_path.write_text(pubspec)
