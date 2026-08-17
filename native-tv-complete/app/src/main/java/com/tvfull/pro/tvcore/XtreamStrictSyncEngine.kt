package com.tvfull.pro.tvcore

import com.tvfull.pro.ContentSection
import org.json.JSONArray
import org.json.JSONObject

/**
 * Strict Xtream catalog synchronization.
 *
 * The provider's player_api.php is the single authority for Live, VOD and
 * Series structure: category ids, names, stream ids and order are never merged
 * with an M3U playlist. This matches the behavior expected from a real Xtream
 * client and prevents a get.php playlist from flattening the provider catalog.
 */
class XtreamStrictSyncEngine(
    private val database: TvCatalogDatabase,
    private val xtream: XtreamClient = XtreamClient(),
    private val m3u: M3uImporter = M3uImporter()
) {
    fun sync(source: ProvisionedSource): SyncReport {
        val session = xtream.authenticate(source.config)
        database.upsertSource(source, session.streamServer)

        val warnings = ArrayList<String>()

        val liveCategories = categories(
            source.serviceId,
            ContentSection.LIVE,
            safeArray(session, "get_live_categories", warnings)
        )
        val live = streams(
            source.serviceId,
            ContentSection.LIVE,
            safeArray(session, "get_live_streams", warnings),
            session
        )
        database.replaceSection(source.serviceId, ContentSection.LIVE, liveCategories, live)

        val movieCategories = categories(
            source.serviceId,
            ContentSection.MOVIES,
            safeArray(session, "get_vod_categories", warnings)
        )
        val movies = streams(
            source.serviceId,
            ContentSection.MOVIES,
            safeArray(session, "get_vod_streams", warnings),
            session
        )
        database.replaceSection(source.serviceId, ContentSection.MOVIES, movieCategories, movies)

        val seriesCategories = categories(
            source.serviceId,
            ContentSection.SERIES,
            safeArray(session, "get_series_categories", warnings)
        )
        val series = seriesParents(
            source.serviceId,
            safeArray(session, "get_series", warnings)
        )
        database.replaceSection(source.serviceId, ContentSection.SERIES, seriesCategories, series)

        // Xtream panels do not expose a consistently supported Radio API.
        // Keep Radio completely isolated: an actual non-Xtream M3U fallback may
        // populate Radio, but it can never alter Live/VOD/Series above.
        val radioFallback = source.config.fallbackM3uUrl
            .takeIf { it.isNotBlank() && !M3uImporter.looksLikeXtreamGetPhp(it) }
            ?.let { url ->
                runCatching { m3u.downloadAndParse(source.serviceId, url) }
                    .onFailure { warnings += "Radio M3U: ${it.message ?: "error"}" }
                    .getOrNull()
            }

        database.replaceSection(
            source.serviceId,
            ContentSection.RADIO,
            radioFallback?.categories?.get(ContentSection.RADIO).orEmpty(),
            radioFallback?.items?.get(ContentSection.RADIO).orEmpty()
        )

        val report = SyncReport(
            sourceId = source.serviceId,
            liveCount = live.size,
            movieCount = movies.size,
            seriesCount = series.size,
            episodeCount = 0,
            warnings = warnings,
            finalServer = session.streamServer
        )
        database.saveSyncReport(report)
        return report
    }

    private fun safeArray(
        session: XtreamSession,
        action: String,
        warnings: MutableList<String>
    ): JSONArray {
        return runCatching { xtream.array(session, action) }.getOrElse {
            warnings += "$action: ${it.message ?: "error"}"
            JSONArray()
        }
    }

    private fun categories(
        sourceId: String,
        section: ContentSection,
        array: JSONArray
    ): List<CatalogCategory> {
        val out = ArrayList<CatalogCategory>()
        for (i in 0 until array.length()) {
            val o = array.optJSONObject(i) ?: continue
            val id = clean(o.opt("category_id")) ?: continue
            val name = clean(o.opt("category_name")) ?: "Otros"
            out += CatalogCategory(
                sourceId = sourceId,
                section = section,
                categoryId = id,
                name = name,
                sortOrder = i
            )
        }
        return out
    }

    private fun streams(
        sourceId: String,
        section: ContentSection,
        array: JSONArray,
        session: XtreamSession
    ): List<CatalogItem> {
        val out = ArrayList<CatalogItem>()
        for (i in 0 until array.length()) {
            val o = array.optJSONObject(i) ?: continue
            val streamId = clean(o.opt("stream_id")) ?: continue
            val name = clean(o.opt("name")) ?: "Sin nombre"
            val categoryId = clean(o.opt("category_id")).orEmpty()
            val direct = clean(o.opt("direct_source")).orEmpty()
            val extension = clean(o.opt("container_extension")).orEmpty().ifBlank {
                if (section == ContentSection.LIVE) "ts" else "mp4"
            }

            val playbackUrl = when {
                direct.startsWith("http://", true) || direct.startsWith("https://", true) -> direct
                section == ContentSection.LIVE -> session.liveUrl(streamId, extension)
                else -> session.movieUrl(streamId, extension)
            }

            out += CatalogItem(
                sourceId = sourceId,
                section = section,
                itemId = streamId,
                categoryId = categoryId,
                name = name,
                playbackUrl = playbackUrl,
                directSource = direct,
                logo = clean(o.opt("stream_icon")).orEmpty(),
                tvgId = clean(o.opt("epg_channel_id")).orEmpty(),
                extension = extension,
                metadataJson = o.toString(),
                sortOrder = i
            )
        }
        return out
    }

    private fun seriesParents(sourceId: String, array: JSONArray): List<CatalogItem> {
        val out = ArrayList<CatalogItem>()
        for (i in 0 until array.length()) {
            val o = array.optJSONObject(i) ?: continue
            val seriesId = clean(o.opt("series_id")) ?: continue
            out += CatalogItem(
                sourceId = sourceId,
                section = ContentSection.SERIES,
                itemId = "series:$seriesId",
                categoryId = clean(o.opt("category_id")).orEmpty(),
                name = clean(o.opt("name")) ?: "Serie $seriesId",
                logo = clean(o.opt("cover")).orEmpty(),
                seriesId = seriesId,
                metadataJson = o.toString(),
                sortOrder = i
            )
        }
        return out
    }

    private fun clean(value: Any?): String? {
        if (value == null || value === JSONObject.NULL) return null
        return value.toString().trim().takeIf {
            it.isNotBlank() && !it.equals("null", true)
        }
    }
}
