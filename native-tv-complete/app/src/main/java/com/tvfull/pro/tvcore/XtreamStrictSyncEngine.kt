package com.tvfull.pro.tvcore

import com.tvfull.pro.ContentSection
import org.json.JSONArray
import org.json.JSONObject

/**
 * Xtream is authoritative for catalog structure.
 * M3U compatibility may supply an exact playback URL for a matching stream id,
 * but it must never add/reorder/rename Xtream categories or catalog rows.
 */
class XtreamStrictSyncEngine(
    private val database: TvCatalogDatabase,
    private val xtream: XtreamClient = XtreamClient(),
    private val m3u: M3uImporter = M3uImporter()
) {
    fun sync(source: ProvisionedSource): SyncReport {
        val session = xtream.authenticate(source.config)
        database.upsertSource(source, session.server)

        val warnings = ArrayList<String>()
        val fallback = source.config.fallbackM3uUrl.takeIf { it.isNotBlank() }?.let { url ->
            runCatching { m3u.downloadAndParse(source.serviceId, url) }
                .onFailure { warnings += "M3U de compatibilidad: ${it.message ?: "error"}" }
                .getOrNull()
        }
        val fallbackIndex: Map<ContentSection, Map<String, CatalogItem>> = fallback?.items
            ?.mapValues { (_, rows) -> rows.associateBy { it.itemId } }
            .orEmpty()

        val liveCategories = categories(
            source.serviceId,
            ContentSection.LIVE,
            safeArray(session, "get_live_categories", warnings)
        )
        val live = streams(
            source.serviceId,
            ContentSection.LIVE,
            safeArray(session, "get_live_streams", warnings),
            session,
            fallbackIndex[ContentSection.LIVE].orEmpty()
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
            session,
            fallbackIndex[ContentSection.MOVIES].orEmpty()
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

        // Xtream has no universal radio API. Keep Radio isolated from Live/Movies/Series.
        // A fallback M3U can populate Radio only; it cannot alter any Xtream section above.
        val radioItems = fallback?.items?.get(ContentSection.RADIO).orEmpty()
        val radioCategories = fallback?.categories?.get(ContentSection.RADIO).orEmpty()
        database.replaceSection(source.serviceId, ContentSection.RADIO, radioCategories, radioItems)

        val report = SyncReport(
            sourceId = source.serviceId,
            liveCount = live.size,
            movieCount = movies.size,
            seriesCount = series.size,
            episodeCount = 0,
            warnings = warnings,
            finalServer = session.server
        )
        database.saveSyncReport(report)
        return report
    }

    private fun safeArray(session: XtreamSession, action: String, warnings: MutableList<String>): JSONArray {
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
        session: XtreamSession,
        fallbackById: Map<String, CatalogItem>
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

            // M3U can replace only the URL of the SAME section + stream id.
            // Xtream metadata/category/name/order remain authoritative.
            val exactM3uUrl = fallbackById[streamId]?.playbackUrl.orEmpty()
            val playbackUrl = when {
                direct.startsWith("http://", true) || direct.startsWith("https://", true) -> direct
                exactM3uUrl.isNotBlank() -> exactM3uUrl
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
        return value.toString().trim().takeIf { it.isNotBlank() && !it.equals("null", true) }
    }
}
