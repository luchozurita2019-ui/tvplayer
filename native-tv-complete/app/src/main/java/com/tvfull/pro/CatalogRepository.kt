package com.tvfull.pro

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Locale

enum class SourceMode { M3U, XTREAM }
enum class ContentSection { LIVE, MOVIES, SERIES }

data class SourceConfig(
    val mode: SourceMode,
    val m3uUrl: String = "",
    val server: String = "",
    val username: String = "",
    val password: String = ""
)

data class TvCategory(val id: String, val name: String, val count: Int = 0)

data class ContentItem(
    val id: String,
    val name: String,
    val url: String = "",
    val logo: String = "",
    val categoryId: String = "",
    val section: ContentSection = ContentSection.LIVE,
    val seriesId: String = "",
    val tvgId: String = "",
    val extra: String = ""
)

data class EpgEntry(val title: String, val description: String, val start: String, val end: String)

object Prefs {
    private const val FILE = "tvfull_source"

    fun save(context: Context, config: SourceConfig) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putString("mode", config.mode.name)
            .putString("m3u", config.m3uUrl)
            .putString("server", config.server)
            .putString("username", config.username)
            .putString("password", config.password)
            .apply()
    }

    fun load(context: Context): SourceConfig? {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val mode = p.getString("mode", null) ?: return null
        return SourceConfig(
            mode = runCatching { SourceMode.valueOf(mode) }.getOrDefault(SourceMode.M3U),
            m3uUrl = p.getString("m3u", "") ?: "",
            server = p.getString("server", "") ?: "",
            username = p.getString("username", "") ?: "",
            password = p.getString("password", "") ?: ""
        )
    }

    fun clear(context: Context) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().clear().apply()
    }
}

class CatalogRepository(private val config: SourceConfig) {
    private var m3uCache: List<ContentItem>? = null

    fun validate(): Boolean {
        return when (config.mode) {
            SourceMode.M3U -> {
                val first = fetchText(config.m3uUrl, 8_000, 12_000, limitChars = 2048)
                first.contains("#EXTM3U", ignoreCase = true) || first.contains("#EXTINF", ignoreCase = true)
            }
            SourceMode.XTREAM -> {
                val json = JSONObject(fetchText(apiUrl(), 8_000, 12_000))
                val user = json.optJSONObject("user_info")
                user != null && (user.optInt("auth", 0) == 1 || user.optString("status").equals("Active", true))
            }
        }
    }

    fun loadCategories(section: ContentSection): List<TvCategory> {
        return when (config.mode) {
            SourceMode.M3U -> {
                val items = ensureM3u().filter { it.section == section }
                val groups = items.groupBy { it.categoryId.ifBlank { "Sin categoría" } }
                    .map { TvCategory(it.key, it.key, it.value.size) }
                    .sortedBy { it.name.lowercase(Locale.getDefault()) }
                listOf(TvCategory("__all__", "Todos", items.size)) + groups
            }
            SourceMode.XTREAM -> {
                val action = when (section) {
                    ContentSection.LIVE -> "get_live_categories"
                    ContentSection.MOVIES -> "get_vod_categories"
                    ContentSection.SERIES -> "get_series_categories"
                }
                val arr = JSONArray(fetchText(apiUrl(action), 8_000, 15_000))
                val out = ArrayList<TvCategory>(arr.length() + 1)
                out += TvCategory("__all__", "Todos")
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    out += TvCategory(o.optString("category_id"), o.optString("category_name", "Categoría"))
                }
                out
            }
        }
    }

    fun loadItems(section: ContentSection, categoryId: String): List<ContentItem> {
        return when (config.mode) {
            SourceMode.M3U -> ensureM3u().filter {
                it.section == section && (categoryId == "__all__" || it.categoryId == categoryId)
            }
            SourceMode.XTREAM -> loadXtreamItems(section, categoryId)
        }
    }

    fun loadSeriesEpisodes(seriesId: String): List<ContentItem> {
        if (config.mode != SourceMode.XTREAM) return emptyList()
        val json = JSONObject(fetchText(apiUrl("get_series_info", mapOf("series_id" to seriesId)), 8_000, 15_000))
        val episodes = json.optJSONObject("episodes") ?: return emptyList()
        val out = ArrayList<ContentItem>()
        val seasons = episodes.keys().asSequence().toList().sortedBy { it.toIntOrNull() ?: 999 }
        for (season in seasons) {
            val arr = episodes.optJSONArray(season) ?: continue
            for (i in 0 until arr.length()) {
                val ep = arr.optJSONObject(i) ?: continue
                val id = ep.optString("id")
                val ext = ep.optString("container_extension", "mp4").ifBlank { "mp4" }
                val epNum = ep.optString("episode_num", (i + 1).toString())
                val title = ep.optString("title", "Temporada $season · Episodio $epNum")
                out += ContentItem(
                    id = id,
                    name = "T$season · E$epNum · $title",
                    url = "${server()}/series/${enc(config.username)}/${enc(config.password)}/$id.$ext",
                    section = ContentSection.SERIES,
                    extra = "Temporada $season"
                )
            }
        }
        return out
    }

    fun loadShortEpg(streamId: String): List<EpgEntry> {
        if (config.mode != SourceMode.XTREAM || streamId.isBlank()) return emptyList()
        return runCatching {
            val json = JSONObject(fetchText(apiUrl("get_short_epg", mapOf("stream_id" to streamId, "limit" to "4")), 5_000, 8_000))
            val arr = json.optJSONArray("epg_listings") ?: JSONArray()
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    add(
                        EpgEntry(
                            title = decodeMaybeBase64(o.optString("title")),
                            description = decodeMaybeBase64(o.optString("description")),
                            start = o.optString("start"),
                            end = o.optString("end")
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun loadXtreamItems(section: ContentSection, categoryId: String): List<ContentItem> {
        val action = when (section) {
            ContentSection.LIVE -> "get_live_streams"
            ContentSection.MOVIES -> "get_vod_streams"
            ContentSection.SERIES -> "get_series"
        }
        val extras = if (categoryId == "__all__") emptyMap() else mapOf("category_id" to categoryId)
        val arr = JSONArray(fetchText(apiUrl(action, extras), 8_000, 20_000))
        val out = ArrayList<ContentItem>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = when (section) {
                ContentSection.SERIES -> o.optString("series_id")
                else -> o.optString("stream_id")
            }
            val name = o.optString("name", "Sin nombre")
            val cat = o.optString("category_id")
            val logo = o.optString("stream_icon", o.optString("cover"))
            val url = when (section) {
                ContentSection.LIVE -> "${server()}/live/${enc(config.username)}/${enc(config.password)}/$id.ts"
                ContentSection.MOVIES -> {
                    val ext = o.optString("container_extension", "mp4").ifBlank { "mp4" }
                    "${server()}/movie/${enc(config.username)}/${enc(config.password)}/$id.$ext"
                }
                ContentSection.SERIES -> ""
            }
            out += ContentItem(
                id = id,
                name = name,
                url = url,
                logo = logo,
                categoryId = cat,
                section = section,
                seriesId = if (section == ContentSection.SERIES) id else ""
            )
        }
        return out
    }

    private fun ensureM3u(): List<ContentItem> {
        m3uCache?.let { return it }
        val conn = open(config.m3uUrl, 10_000, 20_000)
        val reader = BufferedReader(InputStreamReader(conn.inputStream, StandardCharsets.UTF_8), 32 * 1024)
        val out = ArrayList<ContentItem>()
        var pending: Map<String, String>? = null
        reader.useLines { lines ->
            lines.forEach { raw ->
                val line = raw.trim()
                if (line.startsWith("#EXTINF", true)) {
                    pending = parseExtInf(line)
                } else if (line.isNotBlank() && !line.startsWith("#")) {
                    val meta = pending ?: emptyMap()
                    val name = meta["name"].orEmpty().ifBlank { "Canal" }
                    val group = meta["group-title"].orEmpty().ifBlank { "Sin categoría" }
                    out += ContentItem(
                        id = (out.size + 1).toString(),
                        name = name,
                        url = line,
                        logo = meta["tvg-logo"].orEmpty(),
                        categoryId = group,
                        section = classify(group, name),
                        tvgId = meta["tvg-id"].orEmpty()
                    )
                    pending = null
                }
            }
        }
        conn.disconnect()
        m3uCache = out
        return out
    }

    private fun parseExtInf(line: String): Map<String, String> {
        val result = mutableMapOf<String, String>()
        val comma = line.indexOf(',')
        if (comma >= 0 && comma + 1 < line.length) result["name"] = line.substring(comma + 1).trim()
        val attrRegex = Regex("([A-Za-z0-9_-]+)=\"([^\"]*)\"")
        attrRegex.findAll(line).forEach { result[it.groupValues[1].lowercase()] = it.groupValues[2] }
        return result
    }

    private fun classify(group: String, name: String): ContentSection {
        val s = "$group $name".lowercase(Locale.ROOT)
        return when {
            listOf("movie", "movies", "pelicula", "película", "cine", "vod").any { s.contains(it) } -> ContentSection.MOVIES
            listOf("series", "serie", "temporada").any { s.contains(it) } -> ContentSection.SERIES
            else -> ContentSection.LIVE
        }
    }

    private fun apiUrl(action: String? = null, extras: Map<String, String> = emptyMap()): String {
        val q = mutableListOf(
            "username=${enc(config.username)}",
            "password=${enc(config.password)}"
        )
        if (!action.isNullOrBlank()) q += "action=${enc(action)}"
        extras.forEach { (k, v) -> q += "${enc(k)}=${enc(v)}" }
        return "${server()}/player_api.php?${q.joinToString("&")}" 
    }

    private fun server(): String = config.server.trim().trimEnd('/')

    private fun enc(v: String): String = URLEncoder.encode(v, "UTF-8")

    private fun fetchText(url: String, connect: Int, read: Int, limitChars: Int = Int.MAX_VALUE): String {
        val conn = open(url, connect, read)
        val sb = StringBuilder()
        BufferedReader(InputStreamReader(conn.inputStream, StandardCharsets.UTF_8), 32 * 1024).use { r ->
            val buf = CharArray(8192)
            var total = 0
            while (true) {
                val n = r.read(buf)
                if (n <= 0) break
                val take = minOf(n, limitChars - total)
                if (take > 0) sb.append(buf, 0, take)
                total += take
                if (total >= limitChars) break
            }
        }
        conn.disconnect()
        return sb.toString()
    }

    private fun open(url: String, connect: Int, read: Int): HttpURLConnection {
        return (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = connect
            readTimeout = read
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "TV-FULL-PRO/1.0 AndroidTV")
            setRequestProperty("Accept", "*/*")
        }
    }

    private fun decodeMaybeBase64(value: String): String {
        if (value.isBlank()) return ""
        return runCatching {
            String(Base64.decode(value, Base64.DEFAULT), StandardCharsets.UTF_8).trim().ifBlank { value }
        }.getOrDefault(value)
    }
}
