package com.tvfull.pro.tvcore

import android.content.Context
import com.tvfull.pro.RemoteConfigResult
import com.tvfull.pro.RemoteConfigState
import com.tvfull.pro.SourceMode
import com.tvfull.pro.SourceResolver

class TvCoreCoordinator(context: Context) {
    private val appContext = context.applicationContext
    private val provisioning = ProvisioningBridge(appContext)
    val database = TvCatalogDatabase(appContext)
    val playbackResolver = PlaybackSourceResolver()
    val playbackEngine = IjkPlaybackEngine()
    private val m3uSyncEngine = CatalogSyncEngine(database)
    private val xtreamSyncEngine = XtreamStrictSyncEngine(database)

    data class RefreshResult(
        val remote: RemoteConfigResult,
        val sources: List<ProvisionedSource>,
        val reports: List<SyncReport>
    )

    fun refreshFromPanel(): RefreshResult {
        val (remote, provisioned) = provisioning.fetch()
        if (remote.state != RemoteConfigState.READY) {
            return RefreshResult(remote, provisioned, emptyList())
        }

        val resolvedSources = provisioned.map { source ->
            val resolved = SourceResolver.resolve(source.config)
            source.copy(config = resolved)
        }

        val reports = resolvedSources.mapNotNull { source ->
            runCatching {
                if (source.config.mode == SourceMode.XTREAM) {
                    xtreamSyncEngine.sync(source)
                } else {
                    m3uSyncEngine.sync(source)
                }
            }.getOrNull()
        }
        return RefreshResult(remote, resolvedSources, reports)
    }

    fun loadSeriesEpisodes(source: ProvisionedSource, series: CatalogItem): List<CatalogItem> {
        val cached = database.seriesEpisodes(source.serviceId, series.seriesId)
        if (cached.isNotEmpty()) return cached
        val resolved = source.copy(config = SourceResolver.resolve(source.config))
        return m3uSyncEngine.syncSeriesEpisodes(resolved, series)
    }

    fun close() {
        playbackEngine.release()
        database.close()
    }
}
