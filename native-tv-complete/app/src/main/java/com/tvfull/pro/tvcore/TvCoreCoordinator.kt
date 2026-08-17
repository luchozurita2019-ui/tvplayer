package com.tvfull.pro.tvcore

import android.content.Context
import com.tvfull.pro.RemoteConfigResult
import com.tvfull.pro.RemoteConfigState

class TvCoreCoordinator(context: Context) {
    private val appContext = context.applicationContext
    private val provisioning = ProvisioningBridge(appContext)
    val database = TvCatalogDatabase(appContext)
    val playbackResolver = PlaybackSourceResolver()
    val playbackEngine = IjkPlaybackEngine()
    private val syncEngine = CatalogSyncEngine(database)

    data class RefreshResult(
        val remote: RemoteConfigResult,
        val sources: List<ProvisionedSource>,
        val reports: List<SyncReport>
    )

    fun refreshFromPanel(): RefreshResult {
        val (remote, sources) = provisioning.fetch()
        if (remote.state != RemoteConfigState.READY) {
            return RefreshResult(remote, sources, emptyList())
        }

        val reports = sources.mapNotNull { source ->
            runCatching { syncEngine.sync(source) }.getOrNull()
        }
        return RefreshResult(remote, sources, reports)
    }

    fun loadSeriesEpisodes(source: ProvisionedSource, series: CatalogItem): List<CatalogItem> {
        val cached = database.seriesEpisodes(source.serviceId, series.seriesId)
        if (cached.isNotEmpty()) return cached
        return syncEngine.syncSeriesEpisodes(source, series)
    }

    fun close() {
        playbackEngine.release()
        database.close()
    }
}
