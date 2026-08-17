package com.tvfull.pro.tvcore

import com.tvfull.pro.ContentSection
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

class M3uImporter {
    data class Result(
        val categories: Map<ContentSection, List<CatalogCategory>>,
        val items: Map<ContentSection, List<CatalogItem>>,
        val byStreamId: Map<String, CatalogItem>
    )

    fun downloadAndParse(sourceId: String, url: String): Result {
        require(url.isNotBlank()) { "M3U URL vacía" }
        val text = download(url)
        return parse(sourceId, text)
    }

    fun parse(sourceId: String, text: String): Result {
        val categoryNames = linkedMapOf<ContentSection, LinkedHashSet<String>>()
        val items = linkedMapOf<ContentSection, MutableList<CatalogItem>>()
        val byStreamId = LinkedHashMap<String, CatalogItem>()

        var pendingInfo: String? = null
        var order = 0
        text.lineSequence().forEach { raw ->
            val line = raw.trim()
            when {
                line.startsWith("#EXTINF", true) -> pendingInfo = line
                line.isBlank() || line.startsWith("#") -> Unit
                pendingInfo != null -> {
                    val info = pendingInfo.orEmpty()
                    pendingInfo = null
                    val attrs = parseAttributes(info)
                    val displayName = info.substringAfter(',', attrs["tvg-name"].orEmpty()).trim().ifBlank { "Sin nombre" }
                    val group = attrs["group-title"].orEmpty().trim().ifBlank { "Otros" }
                    val section = classify(line, group, displayName)
                    val categoryId = stableKey(group)
                    val streamId = streamIdFromUrl(line).ifBlank { stableKey(line) }
                    val seriesInfo = if (section == ContentSection.SERIES) inferSeries(displayName, group) else null
                    val item = CatalogItem(
                        sourceId = sourceId,
                        section = section,
                        itemId = streamId,
                        categoryId = categoryId,
                        name = displayName,
                        playbackUrl = line,
                        logo = attrs["tvg-logo"].orEmpty(),
                        tvgId = attrs["tvg-id"].orEmpty(),
                        extension = line.substringBefore('?').substringAfterLast('.', "").lowercase(Locale.ROOT),
                        seriesId = seriesInfo?.first.orEmpty(),
                        seasonNumber = seriesInfo?.second,
                        episodeNumber = seriesInfo?.third,
                        metadataJson = "{}",
                        sortOrder = order++
                    )
                    categoryNames.getOrPut(section) { LinkedHashSet() }.add(group)
                    items.getOrPut(section) { ArrayList() }.add(item)
                    byStreamId.putIfAbsent(streamId, item)
                }
            }
        }

        val categories = categoryNames.mapValues { (section, names) ->
            names.mapIndexed { index, name ->
                CatalogCategory(sourceId, section, stableKey(name), name, index)
            }
        }
        return Result(categories, items, byStreamId)
    }

    private fun download(url: String, redirectsLeft: Int = 5): String {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = false
            connectTimeout = 10_000
            readTimeout = 45_000
            setRequestProperty("User-Agent", "TV FULL PRO")
            setRequestProperty("Accept", "audio/x-mpegurl,application/vnd.apple.mpegurl,text/plain,*/*")
        }
        val status = conn.responseCode
        if (status in setOf(301, 302, 303, 307, 308)) {
            val next = conn.getHeaderField("Location")
            conn.disconnect()
            if (next.isNullOrBlank() || redirectsLeft <= 0) error("Redirección M3U inválida")
            return download(URL(URL(url), next).toString(), redirectsLeft - 1)
        }
        val stream = if (status in 200..299) conn.inputStream else conn.errorStream
        val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
        conn.disconnect()
        if (status !in 200..299) error("M3U HTTP $status")
        return body
    }

    private fun parseAttributes(extinf: String): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        ATTR.findAll(extinf.substringBefore(',')).forEach { m -> out[m.groupValues[1].lowercase(Locale.ROOT)] = m.groupValues[2] }
        return out
    }

    private fun classify(url: String, group: String, name: String): ContentSection {
        val path = url.lowercase(Locale.ROOT)
        val hint = "$group $name".lowercase(Locale.ROOT)
        return when {
            "/movie/" in path || listOf("pelicula", "película", "movie", "cine", "film").any { it in hint } -> ContentSection.MOVIES
            "/series/" in path || listOf("serie", "series", "temporada", "season").any { it in hint } -> ContentSection.SERIES
            listOf("radio", "fm ", " am ").any { it in hint } -> ContentSection.RADIO
            else -> ContentSection.LIVE
        }
    }

    private fun streamIdFromUrl(url: String): String {
        val clean = url.substringBefore('?').trimEnd('/')
        return clean.substringAfterLast('/').substringBeforeLast('.').trim()
    }

    private fun inferSeries(name: String, group: String): Triple<String, Int?, Int?> {
        val match = EPISODE.find(name)
        val season = match?.groupValues?.getOrNull(1)?.toIntOrNull()
        val episode = match?.groupValues?.getOrNull(2)?.toIntOrNull()
        val base = if (match == null) name else name.removeRange(match.range).trim(' ', '-', '.', ':')
        val seriesName = base.ifBlank { group }
        return Triple(stableKey(seriesName), season, episode)
    }

    companion object {
        private val ATTR = Regex("([A-Za-z0-9_-]+)=\\\"([^\\\"]*)\\\"")
        private val EPISODE = Regex("(?i)(?:S|T)(\\d{1,2})\\s*[ ._-]?(?:E|x)(\\d{1,3})")
        private fun stableKey(value: String): String = value.trim().lowercase(Locale.ROOT)
            .replace(Regex("[^a-z0-9áéíóúñ]+"), "-")
            .trim('-')
            .ifBlank { Integer.toHexString(value.hashCode()) }
    }
}
