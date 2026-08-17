package com.tvfull.pro

import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Locale

/**
 * Uses the provider's own get.php playlist as a compatibility source.
 *
 * Xtream metadata remains useful for categories/details, but when a provider
 * serializes a stream URL differently in get.php we prefer that exact URL.
 * Series can also fall back to the M3U entries when get_series_info is partial.
 */
class FallbackPlaylistResolver(private val config: SourceConfig) {
    private var loaded = false
    private var cached: List<ContentItem> = emptyList()

    fun streamUrl(section: ContentSection, id: String): String? {
        if (id.isBlank()) return null
        return items().firstOrNull { item ->
            sectionFromUrl(item.url) == section && streamId(item.url) == id
        }?.url
    }

    fun seriesItems(): List<ContentItem> = items().filter {
        sectionFromUrl(it.url) == ContentSection.SERIES || it.section == ContentSection.SERIES
    }

    fun seriesEpisodes(seriesName: String): List<ContentItem> {
        val target = normalizeSeriesName(seriesName)
        if (target.isBlank()) return emptyList()
        return seriesItems().filter { item ->
            val n = normalizeSeriesName(item.name)
            val g = normalizeSeriesName(item.categoryName)
            n.contains(target) || target.contains(n) || g.contains(target)
        }.sortedBy { episodeOrder(it.name) }
    }

    fun seriesCategories(): List<TvCategory> {
        val data = seriesItems()
        if (data.isEmpty()) return emptyList()
        val grouped = data.groupBy { it.categoryId.ifBlank { it.categoryName.ifBlank { "Series" } } }
            .map { (id, values) ->
                TvCategory(id, values.firstOrNull()?.categoryName?.ifBlank { id } ?: id, values.size)
            }
            .sortedBy { it.name.lowercase(Locale.getDefault()) }
        return listOf(TvCategory("__all__", "Todos", data.size)) + grouped
    }

    fun seriesByCategory(categoryId: String): List<ContentItem> {
        val data = seriesItems()
        if (categoryId == "__all__") return data
        val filtered = data.filter { it.categoryId == categoryId || it.categoryName == categoryId }
        return if (filtered.isNotEmpty()) filtered else data
    }

    private fun items(): List<ContentItem> {
        if (loaded) return cached
        loaded = true
        val url = playlistUrl()
        if (url.isBlank()) return emptyList()
        cached = runCatching { parse(url) }.getOrDefault(emptyList())
        return cached
    }

    private fun playlistUrl(): String {
        if (config.fallbackM3uUrl.isNotBlank()) return config.fallbackM3uUrl.trim()
        if (config.mode != SourceMode.XTREAM || config.server.isBlank() || config.username.isBlank()) return ""
        val base = config.server.trim().trimEnd('/')
        return "$base/get.php?username=${enc(config.username)}&password=${enc(config.password)}&type=m3u_plus&output=ts"
    }

    private fun parse(url: String): List<ContentItem> {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000
            readTimeout = 35_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 Chrome/120 Safari/537.36")
            setRequestProperty("Accept", "application/x-mpegURL,text/plain,*/*")
            setRequestProperty("Connection", "keep-alive")
        }
        try {
            val status = conn.responseCode
            if (status !in 200..299) return emptyList()
            val out = ArrayList<ContentItem>()
            var pending: Map<String, String>? = null
            BufferedReader(InputStreamReader(conn.inputStream, StandardCharsets.UTF_8), 32 * 1024).useLines { lines ->
                lines.forEach { raw ->
                    val line = raw.trim()
                    if (line.startsWith("#EXTINF", true)) {
                        pending = parseExtInf(line)
                    } else if (line.isNotBlank() && !line.startsWith("#")) {
                        val meta = pending ?: emptyMap()
                        val name = meta["name"].orEmpty().ifBlank { "Contenido" }
                        val group = meta["group-title"].orEmpty().ifBlank { "Sin categoría" }
                        val section = classify(line, group, name)
                        out += ContentItem(
                            id = streamId(line).orEmpty().ifBlank { (out.size + 1).toString() },
                            name = name,
                            url = line,
                            logo = meta["tvg-logo"].orEmpty(),
                            categoryId = group,
                            categoryName = group,
                            section = section,
                            tvgId = meta["tvg-id"].orEmpty(),
                        )
                        pending = null
                    }
                }
            }
            return out
        } finally {
            conn.disconnect()
        }
    }

    private fun parseExtInf(line: String): Map<String, String> {
        val result = mutableMapOf<String, String>()
        val comma = line.indexOf(',')
        if (comma >= 0 && comma + 1 < line.length) result["name"] = line.substring(comma + 1).trim()
        Regex("([A-Za-z0-9_-]+)=\\\"([^\\\"]*)\\\"")
            .findAll(line)
            .forEach { result[it.groupValues[1].lowercase(Locale.ROOT)] = it.groupValues[2] }
        return result
    }

    private fun classify(url: String, group: String, name: String): ContentSection {
        sectionFromUrl(url)?.let { return it }
        val text = "$group $name".lowercase(Locale.ROOT)
        return when {
            text.contains("radio") || text.contains("emisora") -> ContentSection.RADIO
            listOf("movie", "pelicula", "película", "cine", "vod").any(text::contains) -> ContentSection.MOVIES
            listOf("series", "serie", "temporada").any(text::contains) -> ContentSection.SERIES
            else -> ContentSection.LIVE
        }
    }

    private fun sectionFromUrl(raw: String): ContentSection? {
        val path = runCatching { URI(raw).path.lowercase(Locale.ROOT) }.getOrNull() ?: return null
        return when {
            path.contains("/live/") -> ContentSection.LIVE
            path.contains("/movie/") -> ContentSection.MOVIES
            path.contains("/series/") -> ContentSection.SERIES
            else -> null
        }
    }

    private fun streamId(raw: String): String? {
        val path = runCatching { URI(raw).path }.getOrNull() ?: return null
        val last = path.substringAfterLast('/').substringBefore('?')
        val id = last.substringBeforeLast('.', last).trim()
        return id.takeIf { it.isNotBlank() }
    }

    private fun normalizeSeriesName(raw: String): String {
        return raw.lowercase(Locale.ROOT)
            .replace(Regex("\\b[sStT]?\\d{1,2}\\s*[-_. ]?[eE]\\d{1,3}\\b"), " ")
            .replace(Regex("\\b\\d{1,2}x\\d{1,3}\\b"), " ")
            .replace(Regex("\\btemporada\\s*\\d+\\b"), " ")
            .replace(Regex("\\bepisodio\\s*\\d+\\b"), " ")
            .replace(Regex("[^a-z0-9áéíóúñü]+"), " ")
            .trim()
    }

    private fun episodeOrder(raw: String): Int {
        val sxe = Regex("(?i)[sStT]?(\\d{1,2})\\s*[-_. ]?[eE](\\d{1,3})").find(raw)
        if (sxe != null) return (sxe.groupValues[1].toIntOrNull() ?: 0) * 10_000 + (sxe.groupValues[2].toIntOrNull() ?: 0)
        val x = Regex("(?i)(\\d{1,2})x(\\d{1,3})").find(raw)
        if (x != null) return (x.groupValues[1].toIntOrNull() ?: 0) * 10_000 + (x.groupValues[2].toIntOrNull() ?: 0)
        return Int.MAX_VALUE
    }

    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8")
}
