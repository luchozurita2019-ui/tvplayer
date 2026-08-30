package com.example.iptv_player

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
