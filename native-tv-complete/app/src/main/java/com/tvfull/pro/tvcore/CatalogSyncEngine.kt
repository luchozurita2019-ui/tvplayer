package com.tvfull.pro.tvcore

import com.tvfull.pro.ContentSection
import com.tvfull.pro.SourceMode
import org.json.JSONArray
import org.json.JSONObject

class CatalogSyncEngine(
    private val database: TvCatalogDatabase,
    private val xtream: XtreamClient = XtreamClient(),
    private val m3u: M3uImporter = M3uImporter()
) {
    fun sync(source: ProvisionedSource): SyncReport {
        return try {
            when (source.config.mode) {
                SourceMode.M3U -> syncM3u(source)
                SourceMode.XTREAM -> syncXtream(source)
            }
        } catch (e: Exception) {
            val report = SyncReport(source.serviceId, warnings = listOf(e.message ?: "Error de sincronización"))
            database.saveSyncReport(report, e.message ?: "Error de sincronización")
            throw e
        }
    }

    fun syncSeriesEpisodes(source: ProvisionedSource, series: CatalogItem): List<CatalogItem> {
        if (source.config.mode != SourceMode.XTREAM || series.seriesId.isBlank()) {
            return database.seriesEpisodes(source.serviceId, series.seriesId)
        }

        val session = xtream.authenticate(source.config)
        val info = xtream.objectResponse(session, "get_series_info", mapOf("series_id" to series.seriesId))
        val episodes = parseSeriesEpisodes(source, session, series, info)
        if (episodes.isNotEmpty()) {
            val current = database.items(source.serviceId, ContentSection.SERIES)
                .filterNot { it.seriesId == series.seriesId && it.seasonNumber != null }
            database.replaceSection(source.serviceId, ContentSection.SERIES, database.categories(source.serviceId, ContentSection.SERIES), current + episodes)
            return episodes
        }

        val fallbackUrl = source.config.fallbackM3uUrl
        if (fallbackUrl.isNotBlank()) {
            val fallback = m3u.downloadAndParse(source.serviceId, fallbackUrl)
            val key = series.name.lowercase().replace(Regex("[^a-z0-9áéíóúñ]+"), "-").trim('-')
            val fallbackEpisodes = fallback.items[ContentSection.SERIES].orEmpty().filter {
                it.seriesId == key || it.name.contains(series.name, ignoreCase = true)
            }
            if (fallbackEpisodes.isNotEmpty()) return fallbackEpisodes
        }
        return emptyList()
    }

    private fun syncM3u(source: ProvisionedSource): SyncReport {
        val url = source.config.m3uUrl.ifBlank { source.config.fallbackM3uUrl }
        val parsed = m3u.downloadAndParse(source.serviceId, url)
        database.upsertSource(source)
        ContentSection.entries.forEach { section ->
            database.replaceSection(
                source.serviceId,
                section,
                parsed.categories[section].orEmpty(),
                parsed.items[section].orEmpty()
            )
        }
        val report = SyncReport(
            sourceId = source.serviceId,
            liveCount = parsed.items[ContentSection.LIVE].orEmpty().size,
            movieCount = parsed.items[ContentSection.MOVIES].orEmpty().size,
            seriesCount = parsed.items[ContentSection.SERIES].orEmpty().map { it.seriesId.ifBlank { it.categoryId } }.distinct().size,
            episodeCount = parsed.items[ContentSection.SERIES].orEmpty().size
        )
        database.saveSyncReport(report)
        return report
    }

    private fun syncXtream(source: ProvisionedSource): SyncReport {
        val session = xtream.authenticate(source.config)
        database.upsertSource(source, session.server)

        val fallback = source.config.fallbackM3uUrl.takeIf { it.isNotBlank() }?.let {
            runCatching { m3u.downloadAndParse(source.serviceId, it) }.getOrNull()
        }
        val warnings = ArrayList<String>()
        if (source.config.fallbackM3uUrl.isNotBlank() && fallback == null) warnings += "No se pudo cargar M3U de compatibilidad"

        val liveCategories = categories(source.serviceId, ContentSection.LIVE, safeArray(session, "get_live_categories", warnings))
        val live = streamItems(
            source.serviceId,
            ContentSection.LIVE,
            safeArray(session, "get_live_streams", warnings),
            fallback,
            session
        )
        database.replaceSection(source.serviceId, ContentSection.LIVE, mergeCategories(liveCategories, fallback?.categories?.get(ContentSection.LIVE).orEmpty()), live)

        val movieCategories = categories(source.serviceId, ContentSection.MOVIES, safeArray(session, "get_vod_categories", warnings))
        val movies = streamItems(
            source.serviceId,
            ContentSection.MOVIES,
            safeArray(session, "get_vod_streams", warnings),
            fallback,
            session
        )
        database.replaceSection(source.serviceId, ContentSection.MOVIES, mergeCategories(movieCategories, fallback?.categories?.get(ContentSection.MOVIES).orEmpty()), movies)

        val seriesCategories = categories(source.serviceId, ContentSection.SERIES, safeArray(session, "get_series_categories", warnings))
        val series = seriesItems(source.serviceId, safeArray(session, "get_series", warnings))
        val fallbackSeries = fallback?.items?.get(ContentSection.SERIES).orEmpty()
        val mergedSeries = if (series.isNotEmpty()) series + fallbackSeries.filter { fallbackItem ->
            series.none { native -> native.name.equals(fallbackItem.name, ignoreCase = true) }
        } else fallbackSeries
        database.replaceSection(
            source.serviceId,
            ContentSection.SERIES,
            mergeCategories(seriesCategories, fallback?.categories?.get(ContentSection.SERIES).orEmpty()),
            mergedSeries
        )

        val radioCategories = categories(source.serviceId, ContentSection.RADIO, safeArray(session, "get_live_categories", warnings))
        val radioFallback = fallback?.items?.get(ContentSection.RADIO).orEmpty()
        if (radioFallback.isNotEmpty()) {
            database.replaceSection(source.serviceId, ContentSection.RADIO, mergeCategories(radioCategories, fallback?.categories?.get(ContentSection.RADIO).orEmpty()), radioFallback)
        }

        val report = SyncReport(
            sourceId = source.serviceId,
            liveCount = live.size,
            movieCount = movies.size,
            seriesCount = mergedSeries.count { it.seasonNumber == null },
            episodeCount = mergedSeries.count { it.seasonNumber != null },
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

    private fun categories(sourceId: String, section: ContentSection, array: JSONArray): List<CatalogCategory> {
        val out = ArrayList<CatalogCategory>()
        for (i in 0 until array.length()) {
            val o = array.optJSONObject(i) ?: continue
            val id = clean(o.opt("category_id")) ?: continue
            val name = clean(o.opt("category_name")) ?: "Otros"
            out += CatalogCategory(sourceId, section, id, name, i)
        }
        return out
    }

    private fun mergeCategories(primary: List<CatalogCategory>, fallback: List<CatalogCategory>): List<CatalogCategory> {
        if (fallback.isEmpty()) return primary
        val out = ArrayList<CatalogCategory>()
        out += primary
        fallback.forEach { f -> if (out.none { it.categoryId == f.categoryId || it.name.equals(f.name, true) }) out += f.copy(sortOrder = out.size) }
        return out
    }

    private fun streamItems(
        sourceId: String,
        section: ContentSection,
        array: JSONArray,
        fallback: M3uImporter.Result?,
        session: XtreamSession
    ): List<CatalogItem> {
        val out = ArrayList<CatalogItem>()
        for (i in 0 until array.length()) {
            val o = array.optJSONObject(i) ?: continue
            val id = clean(o.opt("stream_id")) ?: continue
            val name = clean(o.opt("name")) ?: "Sin nombre"
            val categoryId = clean(o.opt("category_id")).orEmpty()
            val direct = clean(o.opt("direct_source")).orEmpty()
            val ext = clean(o.opt("container_extension")).orEmpty().ifBlank { if (section == ContentSection.LIVE) "ts" else "mp4" }
            val fallbackUrl = fallback?.byStreamId?.get(id)?.playbackUrl.orEmpty()
            val url = when {
                direct.startsWith("http://", true) || direct.startsWith("https://", true) -> direct
                fallbackUrl.isNotBlank() -> fallbackUrl
                section == ContentSection.LIVE -> session.liveUrl(id, ext)
                else -> session.movieUrl(id, ext)
            }
            out += CatalogItem(
                sourceId = sourceId,
                section = section,
                itemId = id,
                categoryId = categoryId,
                name = name,
                playbackUrl = url,
                directSource = direct,
                logo = clean(o.opt("stream_icon")).orEmpty(),
                tvgId = clean(o.opt("epg_channel_id")).orEmpty(),
                extension = ext,
                metadataJson = o.toString(),
                sortOrder = i
            )
        }
        return out
    }

    private fun seriesItems(sourceId: String, array: JSONArray): List<CatalogItem> {
        val out = ArrayList<CatalogItem>()
        for (i in 0 until array.length()) {
            val o = array.optJSONObject(i) ?: continue
            val id = clean(o.opt("series_id")) ?: continue
            out += CatalogItem(
                sourceId = sourceId,
                section = ContentSection.SERIES,
                itemId = "series:$id",
                categoryId = clean(o.opt("category_id")).orEmpty(),
                name = clean(o.opt("name")) ?: "Serie $id",
                logo = clean(o.opt("cover")).orEmpty(),
                seriesId = id,
                metadataJson = o.toString(),
                sortOrder = i
            )
        }
        return out
    }

    private fun parseSeriesEpisodes(source: ProvisionedSource, session: XtreamSession, series: CatalogItem, info: JSONObject): List<CatalogItem> {
        val raw = info.opt("episodes")
        val out = ArrayList<CatalogItem>()
        var order = 0

        fun appendEpisode(o: JSONObject, seasonHint: Int?, episodeHint: Int?) {
            val epInfo = o.optJSONObject("info") ?: JSONObject()
            val id = clean(o.opt("id")) ?: clean(o.opt("stream_id")) ?: return
            val season = clean(o.opt("season"))?.toIntOrNull() ?: seasonHint
            val episode = clean(o.opt("episode_num"))?.toIntOrNull() ?: clean(epInfo.opt("episode_num"))?.toIntOrNull() ?: episodeHint
            val ext = clean(o.opt("container_extension")) ?: clean(epInfo.opt("container_extension")) ?: "mp4"
            val direct = clean(o.opt("direct_source")) ?: clean(epInfo.opt("direct_source")) ?: ""
            val title = clean(o.opt("title")) ?: clean(epInfo.opt("title")) ?: "Episodio ${episode ?: order + 1}"
            val url = if (direct.startsWith("http://", true) || direct.startsWith("https://", true)) direct else session.seriesUrl(id, ext)
            out += CatalogItem(
                sourceId = source.serviceId,
                section = ContentSection.SERIES,
                itemId = id,
                categoryId = series.categoryId,
                name = title,
                playbackUrl = url,
                directSource = direct,
                extension = ext,
                seriesId = series.seriesId,
                seasonNumber = season,
                episodeNumber = episode,
                metadataJson = o.toString(),
                sortOrder = order++
            )
        }

        when (raw) {
            is JSONObject -> {
                raw.keys().asSequence().toList().sortedBy { it.toIntOrNull() ?: Int.MAX_VALUE }.forEach { key ->
                    val season = key.toIntOrNull()
                    val arr = raw.optJSONArray(key) ?: return@forEach
                    for (i in 0 until arr.length()) arr.optJSONObject(i)?.let { appendEpisode(it, season, i + 1) }
                }
            }
            is JSONArray -> for (i in 0 until raw.length()) raw.optJSONObject(i)?.let { appendEpisode(it, null, i + 1) }
        }
        return out
    }

    private fun clean(value: Any?): String? {
        if (value == null || value === JSONObject.NULL) return null
        return value.toString().trim().takeIf { it.isNotBlank() && !it.equals("null", true) }
    }
}
