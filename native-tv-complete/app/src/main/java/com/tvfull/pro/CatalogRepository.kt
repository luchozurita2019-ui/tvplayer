package com.tvfull.pro

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Locale

enum class SourceMode { M3U, XTREAM }
enum class ContentSection { LIVE, MOVIES, SERIES, RADIO }

data class SourceConfig(
    val mode: SourceMode,
    val m3uUrl: String = "",
    val server: String = "",
    val username: String = "",
    val password: String = "",
    val fallbackM3uUrl: String = "",
    val streamServer: String = ""
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
    val extra: String = "",
    val categoryName: String = "",
    val extension: String = "",
    val directSource: String = "",
    val rating: String = "",
    val releaseDate: String = "",
    val genre: String = ""
)

data class EpgEntry(val title: String, val description: String, val start: String, val end: String)

data class MovieDetails(
    val movie: ContentItem,
    val plot: String = "",
    val cast: String = "",
    val director: String = "",
    val genre: String = "",
    val releaseDate: String = "",
    val rating: String = "",
    val duration: String = "",
    val country: String = "",
    val backdrop: String = "",
    val trailer: String = "",
    val playableUrl: String = ""
)

object Prefs {
    private const val FILE = "tvfull_source"

    fun save(context: Context, config: SourceConfig) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putString("mode", config.mode.name)
            .putString("m3u", config.m3uUrl)
            .putString("server", config.server)
            .putString("username", config.username)
            .putString("password", config.password)
            .putString("fallback_m3u", config.fallbackM3uUrl)
            .putString("stream_server", config.streamServer)
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
            password = p.getString("password", "") ?: "",
            fallbackM3uUrl = p.getString("fallback_m3u", "") ?: "",
            streamServer = p.getString("stream_server", "") ?: ""
        )
    }

    fun clear(context: Context) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().clear().apply()
    }
}

object SourceResolver {
    fun resolve(input: SourceConfig): SourceConfig {
        return when (input.mode) {
            SourceMode.XTREAM -> XtreamConnectionResolver.resolve(input)
            SourceMode.M3U -> resolveM3uOrXtream(input)
        }
    }

    fun looksLikeXtreamUrl(url: String): Boolean = xtreamCandidate(url) != null

    private fun resolveM3uOrXtream(input: SourceConfig): SourceConfig {
        val original = input.m3uUrl.trim()
        val candidate = xtreamCandidate(original) ?: return input.copy(m3uUrl = original)
        val resolved = runCatching { XtreamConnectionResolver.resolve(candidate) }.getOrNull()
        return resolved?.copy(fallbackM3uUrl = original) ?: input.copy(m3uUrl = original)
    }

    private fun xtreamCandidate(raw: String): SourceConfig? {
        if (raw.isBlank()) return null
        return runCatching {
            val u = URL(raw)
            if (u.protocol.lowercase(Locale.ROOT) !in listOf("http", "https")) return null
            val params = queryParams(u.query.orEmpty())
            val username = params["username"].orEmpty().trim()
            val password = params["password"].orEmpty()
            val path = u.path.orEmpty()
            val lower = path.lowercase(Locale.ROOT)
            if (!(lower.endsWith("/get.php") || lower.endsWith("get.php")) || username.isBlank() || password.isBlank()) return null

            var basePath = when {
                lower.endsWith("/get.php") -> path.dropLast("/get.php".length)
                else -> path.dropLast("get.php".length).trimEnd('/')
            }
            if (basePath == "/") basePath = ""
            val port = if (u.port >= 0) ":${u.port}" else ""
            val server = "${u.protocol}://${u.host}$port$basePath"
            SourceConfig(
                mode = SourceMode.XTREAM,
                server = server,
                username = username,
                password = password,
                fallbackM3uUrl = raw
            )
        }.getOrNull()
    }

    private fun queryParams(query: String): Map<String, String> {
        if (query.isBlank()) return emptyMap()
        return query.split('&').mapNotNull { part ->
            val idx = part.indexOf('=')
            if (idx <= 0) return@mapNotNull null
            val key = URLDecoder.decode(part.substring(0, idx), "UTF-8").lowercase(Locale.ROOT)
            val value = URLDecoder.decode(part.substring(idx + 1), "UTF-8")
            key to value
        }.toMap()
    }
}

private object XtreamConnectionResolver {
    private const val UA = "Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 Chrome/120 Safari/537.36"

    fun resolve(input: SourceConfig): SourceConfig {
        val apiServer = normalizeServer(input.server)
        val authUrl = endpoint(apiServer, "player_api.php", mapOf(
            "username" to input.username.trim(),
            "password" to input.password
        ))
        val json = JSONObject(fetch(authUrl, 8_000, 12_000))
        val user = json.optJSONObject("user_info") ?: throw IllegalStateException("Xtream sin user_info")
        val auth = user.opt("auth")
        val valid = auth == 1 || auth == "1" || auth == true || user.optString("status").equals("Active", true)
        if (!valid) throw IllegalStateException("Credenciales Xtream inactivas")

        val serverInfo = json.optJSONObject("server_info") ?: JSONObject()
        val streamServer = resolveStreamServer(apiServer, serverInfo)
        return input.copy(
            mode = SourceMode.XTREAM,
            server = apiServer,
            username = input.username.trim(),
            streamServer = streamServer
        )
    }

    private fun normalizeServer(raw: String): String {
        var value = raw.trim()
        if (!value.contains("://")) value = "http://$value"
        val uri = URI(value)
        require(uri.scheme == "http" || uri.scheme == "https") { "Servidor Xtream inválido" }
        require(!uri.host.isNullOrBlank()) { "Servidor Xtream inválido" }
        return value.trimEnd('/')
    }

    private fun resolveStreamServer(apiServer: String, info: JSONObject): String {
        val api = URI(apiServer)
        val requestedProtocol = info.optString("server_protocol").lowercase(Locale.ROOT)
        val scheme = if (requestedProtocol == "http" || requestedProtocol == "https") requestedProtocol else api.scheme

        var host = api.host
        val rawUrl = info.optString("url").trim()
        if (rawUrl.isNotBlank()) {
            val candidate = runCatching { URI(if (rawUrl.contains("://")) rawUrl else "$scheme://$rawUrl") }.getOrNull()
            if (candidate != null && !candidate.host.isNullOrBlank()) host = candidate.host
        }

        val preferredPort = if (scheme == "https") info.opt("https_port") ?: info.opt("port") else info.opt("port")
        var port = preferredPort?.toString()?.toIntOrNull()
        if (port == null || port !in 1..65535) port = if (api.port > 0) api.port else -1

        val path = api.path?.takeIf { it.isNotBlank() && it != "/" } ?: ""
        return URI(scheme, null, host, port, path, null, null).toString().trimEnd('/')
    }

    private fun endpoint(base: String, file: String, query: Map<String, String>): String {
        val uri = URI(base)
        val basePath = uri.path.orEmpty().trimEnd('/')
        val path = if (basePath.isBlank()) "/$file" else "$basePath/$file"
        val q = query.entries.joinToString("&") { "${enc(it.key)}=${enc(it.value)}" }
        return URI(uri.scheme, null, uri.host, uri.port, path, q, null).toASCIIString()
    }

    private fun fetch(url: String, connect: Int, read: Int): String {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = connect
            readTimeout = read
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", UA)
            setRequestProperty("Accept", "application/json,text/plain,*/*")
            setRequestProperty("Connection", "keep-alive")
        }
        try {
            val status = conn.responseCode
            if (status !in 200..299) throw IllegalStateException("Xtream HTTP $status")
            return BufferedReader(InputStreamReader(conn.inputStream, StandardCharsets.UTF_8), 32 * 1024).use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    private fun enc(v: String): String = URLEncoder.encode(v, "UTF-8")
}

class CatalogRepository(private val config: SourceConfig) {
    companion object {
        private const val API_UA = "Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 Chrome/120 Safari/537.36"
    }

    private var m3uCache: List<ContentItem>? = null

    fun validate(): Boolean {
        return when (config.mode) {
            SourceMode.M3U -> {
                val first = fetchText(config.m3uUrl, 8_000, 12_000, limitChars = 4096)
                first.contains("#EXTM3U", ignoreCase = true) || first.contains("#EXTINF", ignoreCase = true)
            }
            SourceMode.XTREAM -> {
                val json = JSONObject(fetchText(apiUrl(), 8_000, 12_000))
                val user = json.optJSONObject("user_info")
                user != null && (user.optInt("auth", 0) == 1 || user.optString("auth") == "1" || user.optString("status").equals("Active", true))
            }
        }
    }

    fun loadCategories(section: ContentSection): List<TvCategory> {
        return when (config.mode) {
            SourceMode.M3U -> categoriesFromItems(ensureM3u().filter { it.section == section })
            SourceMode.XTREAM -> when (section) {
                ContentSection.LIVE -> loadXtreamCategories("get_live_categories")
                ContentSection.MOVIES -> loadXtreamCategories("get_vod_categories")
                ContentSection.SERIES -> loadXtreamCategories("get_series_categories")
                ContentSection.RADIO -> {
                    val native = safeArray("get_radio_categories")
                    if (native.length() > 0) categoriesFromJson(native)
                    else categoriesFromItems(loadRadioItems("__all__"))
                }
            }
        }
    }

    fun loadItems(section: ContentSection, categoryId: String): List<ContentItem> {
        return when (config.mode) {
            SourceMode.M3U -> ensureM3u().filter {
                it.section == section && (categoryId == "__all__" || it.categoryId == categoryId)
            }
            SourceMode.XTREAM -> when (section) {
                ContentSection.LIVE -> loadLiveItems(categoryId)
                ContentSection.MOVIES -> loadMovieItems(categoryId)
                ContentSection.SERIES -> loadSeriesItems(categoryId)
                ContentSection.RADIO -> loadRadioItems(categoryId)
            }
        }
    }

    fun loadVodDetails(movie: ContentItem): MovieDetails {
        if (config.mode != SourceMode.XTREAM || movie.id.isBlank()) {
            return MovieDetails(movie = movie, genre = movie.genre, releaseDate = movie.releaseDate, rating = movie.rating, playableUrl = movie.url)
        }

        return runCatching {
            val root = JSONObject(fetchText(apiUrl("get_vod_info", mapOf("vod_id" to movie.id)), 8_000, 16_000))
            val info = root.optJSONObject("info") ?: JSONObject()
            val data = root.optJSONObject("movie_data") ?: JSONObject()
            fun pick(vararg keys: String): String {
                for (key in keys) {
                    cleanText(info.opt(key))?.let { return it }
                    cleanText(data.opt(key))?.let { return it }
                }
                return ""
            }

            val ext = cleanExtension(pick("container_extension", "extension").ifBlank { movie.extension }, movie.extension.ifBlank { "mp4" })
            val direct = pick("direct_source").ifBlank { movie.directSource }
            val playable = resolveDirectSource(direct) ?: movieUrl(movie.id, ext)
            val backdrop = firstImage(info.opt("backdrop_path"))
                .ifBlank { firstImage(info.opt("backdrop")) }
                .ifBlank { firstImage(info.opt("backdrops")) }
                .ifBlank { pick("cover_big") }

            MovieDetails(
                movie = movie,
                plot = pick("plot", "description", "overview"),
                cast = pick("cast", "actors"),
                director = pick("director"),
                genre = pick("genre").ifBlank { movie.genre },
                releaseDate = pick("releasedate", "releaseDate", "release_date", "year").ifBlank { movie.releaseDate },
                rating = pick("rating", "rating_5based").ifBlank { movie.rating },
                duration = pick("duration", "duration_secs"),
                country = pick("country"),
                backdrop = backdrop,
                trailer = pick("trailer_url", "trailer", "youtube_trailer"),
                playableUrl = playable
            )
        }.getOrElse {
            MovieDetails(
                movie = movie,
                genre = movie.genre,
                releaseDate = movie.releaseDate,
                rating = movie.rating,
                playableUrl = movie.url
            )
        }
    }

    fun loadSeriesEpisodes(seriesId: String): List<ContentItem> {
        if (config.mode != SourceMode.XTREAM) return emptyList()
        val json = JSONObject(fetchText(apiUrl("get_series_info", mapOf("series_id" to seriesId)), 8_000, 20_000))
        val episodes = json.optJSONObject("episodes") ?: return emptyList()
        val out = ArrayList<ContentItem>()
        val seasons = episodes.keys().asSequence().toList().sortedBy { it.toIntOrNull() ?: 999 }
        for (season in seasons) {
            val arr = episodes.optJSONArray(season) ?: continue
            for (i in 0 until arr.length()) {
                val ep = arr.optJSONObject(i) ?: continue
                val id = cleanText(ep.opt("id")) ?: continue
                val ext = cleanExtension(cleanText(ep.opt("container_extension")), "mp4")
                val epNum = cleanText(ep.opt("episode_num")) ?: (i + 1).toString()
                val title = cleanText(ep.opt("title")) ?: "Temporada $season · Episodio $epNum"
                val direct = cleanText(ep.opt("direct_source")).orEmpty()
                out += ContentItem(
                    id = id,
                    name = "T$season · E$epNum · $title",
                    url = resolveDirectSource(direct) ?: seriesUrl(id, ext),
                    section = ContentSection.SERIES,
                    extension = ext,
                    directSource = direct,
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
                    add(EpgEntry(
                        title = decodeMaybeBase64(o.optString("title")),
                        description = decodeMaybeBase64(o.optString("description")),
                        start = o.optString("start"),
                        end = o.optString("end")
                    ))
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun loadXtreamCategories(action: String): List<TvCategory> {
        val arr = safeArray(action)
        return categoriesFromJson(arr)
    }

    private fun categoriesFromJson(arr: JSONArray): List<TvCategory> {
        val out = ArrayList<TvCategory>(arr.length() + 1)
        out += TvCategory("__all__", "Todos")
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = cleanText(o.opt("category_id")) ?: continue
            val name = cleanText(o.opt("category_name")) ?: "Categoría"
            out += TvCategory(id, name)
        }
        return out
    }

    private fun loadLiveItems(categoryId: String): List<ContentItem> {
        val arr = actionArray("get_live_streams", categoryId)
        val out = ArrayList<ContentItem>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = cleanText(o.opt("stream_id")) ?: continue
            val name = cleanText(o.opt("name")) ?: continue
            val cat = cleanText(o.opt("category_id")).orEmpty()
            if (categoryId != "__all__" && cat.isNotBlank() && cat != categoryId) continue
            val ext = cleanExtension(cleanText(o.opt("container_extension")), "ts")
            val direct = cleanText(o.opt("direct_source")).orEmpty()
            out += ContentItem(
                id = id,
                name = name,
                url = resolveDirectSource(direct) ?: liveUrl(id, ext),
                logo = firstText(o, "stream_icon", "logo", "icon"),
                categoryId = cat,
                categoryName = firstText(o, "category_name", "category"),
                section = ContentSection.LIVE,
                tvgId = firstText(o, "epg_channel_id", "tvg_id"),
                extension = ext,
                directSource = direct
            )
        }
        return out
    }

    private fun loadMovieItems(categoryId: String): List<ContentItem> {
        val arr = actionArray("get_vod_streams", categoryId)
        val out = ArrayList<ContentItem>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = cleanText(o.opt("stream_id")) ?: continue
            val name = cleanText(o.opt("name")) ?: continue
            val cat = cleanText(o.opt("category_id")).orEmpty()
            if (categoryId != "__all__" && cat.isNotBlank() && cat != categoryId) continue
            val ext = cleanExtension(firstText(o, "container_extension", "extension"), "mp4")
            val direct = cleanText(o.opt("direct_source")).orEmpty()
            out += ContentItem(
                id = id,
                name = name,
                url = resolveDirectSource(direct) ?: movieUrl(id, ext),
                logo = firstText(o, "stream_icon", "movie_image", "cover"),
                categoryId = cat,
                categoryName = firstText(o, "category_name", "category"),
                section = ContentSection.MOVIES,
                extension = ext,
                directSource = direct,
                rating = firstText(o, "rating", "rating_5based"),
                releaseDate = firstText(o, "releasedate", "releaseDate", "year"),
                genre = firstText(o, "genre")
            )
        }
        return out
    }

    private fun loadSeriesItems(categoryId: String): List<ContentItem> {
        val arr = actionArray("get_series", categoryId)
        val out = ArrayList<ContentItem>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = cleanText(o.opt("series_id")) ?: continue
            val name = cleanText(o.opt("name")) ?: continue
            val cat = cleanText(o.opt("category_id")).orEmpty()
            if (categoryId != "__all__" && cat.isNotBlank() && cat != categoryId) continue
            out += ContentItem(
                id = id,
                name = name,
                logo = firstText(o, "cover", "stream_icon"),
                categoryId = cat,
                categoryName = firstText(o, "category_name", "category"),
                section = ContentSection.SERIES,
                seriesId = id,
                rating = firstText(o, "rating", "rating_5based"),
                releaseDate = firstText(o, "releaseDate", "releasedate", "year"),
                genre = firstText(o, "genre")
            )
        }
        return out
    }

    private fun loadRadioItems(categoryId: String): List<ContentItem> {
        var arr = safeArray("get_radio_streams", if (categoryId == "__all__") emptyMap() else mapOf("category_id" to categoryId))
        if (arr.length() == 0) arr = safeArray("get_radios", if (categoryId == "__all__") emptyMap() else mapOf("category_id" to categoryId))

        val out = ArrayList<ContentItem>()
        if (arr.length() > 0) {
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                makeRadioItem(o, categoryId)?.let(out::add)
            }
            return out
        }

        // Fallback conservador: sólo usamos streams que el propio proveedor
        // marca explícitamente como radio. No inferimos por "música", FM, etc.
        val live = safeArray("get_live_streams")
        for (i in 0 until live.length()) {
            val o = live.optJSONObject(i) ?: continue
            val explicitRadio = o.optString("stream_type").equals("radio", true) || o.optInt("is_radio", 0) == 1
            if (!explicitRadio) continue
            makeRadioItem(o, categoryId)?.let(out::add)
        }
        return out
    }

    private fun makeRadioItem(o: JSONObject, categoryId: String): ContentItem? {
        val id = cleanText(o.opt("stream_id")) ?: cleanText(o.opt("id")) ?: return null
        val name = cleanText(o.opt("name")) ?: return null
        val cat = cleanText(o.opt("category_id")).orEmpty()
        if (categoryId != "__all__" && cat.isNotBlank() && cat != categoryId) return null
        val ext = cleanExtension(cleanText(o.opt("container_extension")), "ts")
        val direct = cleanText(o.opt("direct_source")).orEmpty()
        return ContentItem(
            id = id,
            name = name,
            url = resolveDirectSource(direct) ?: liveUrl(id, ext),
            logo = firstText(o, "stream_icon", "logo", "icon"),
            categoryId = cat,
            categoryName = firstText(o, "category_name", "category"),
            section = ContentSection.RADIO,
            extension = ext,
            directSource = direct
        )
    }

    private fun actionArray(action: String, categoryId: String): JSONArray {
        val extras = if (categoryId == "__all__") emptyMap() else mapOf("category_id" to categoryId)
        return JSONArray(fetchText(apiUrl(action, extras), 8_000, 35_000))
    }

    private fun safeArray(action: String, extras: Map<String, String> = emptyMap()): JSONArray {
        return runCatching { JSONArray(fetchText(apiUrl(action, extras), 8_000, 20_000)) }.getOrElse { JSONArray() }
    }

    private fun categoriesFromItems(items: List<ContentItem>): List<TvCategory> {
        val groups = items.groupBy { it.categoryId.ifBlank { it.categoryName.ifBlank { "Sin categoría" } } }
            .map { (id, values) -> TvCategory(id, values.firstOrNull()?.categoryName?.ifBlank { id } ?: id, values.size) }
            .sortedBy { it.name.lowercase(Locale.getDefault()) }
        return listOf(TvCategory("__all__", "Todos", items.size)) + groups
    }

    private fun ensureM3u(): List<ContentItem> {
        m3uCache?.let { return it }
        val conn = open(config.m3uUrl, 10_000, 25_000)
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
                        categoryName = group,
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
        val g = group.lowercase(Locale.ROOT)
        val s = "$group $name".lowercase(Locale.ROOT)
        return when {
            g.contains("radio") || g.contains("emisora") -> ContentSection.RADIO
            listOf("movie", "movies", "pelicula", "película", "cine", "vod").any { s.contains(it) } -> ContentSection.MOVIES
            listOf("series", "serie", "temporada").any { s.contains(it) } -> ContentSection.SERIES
            else -> ContentSection.LIVE
        }
    }

    private fun liveUrl(id: String, extension: String): String = streamUrl("live", id, extension)
    private fun movieUrl(id: String, extension: String): String = streamUrl("movie", id, extension)
    private fun seriesUrl(id: String, extension: String): String = streamUrl("series", id, extension)

    private fun streamUrl(section: String, id: String, extension: String): String {
        val base = URI(streamServer())
        val prefix = base.path.orEmpty().trim('/').takeIf { it.isNotBlank() }
        val path = buildString {
            append('/')
            if (prefix != null) append(prefix).append('/')
            append(section).append('/')
            append(pathEnc(config.username)).append('/')
            append(pathEnc(config.password)).append('/')
            append(pathEnc(id)).append('.').append(extension)
        }
        return URI(base.scheme, null, base.host, base.port, path, null, null).toASCIIString()
    }

    private fun resolveDirectSource(raw: String): String? {
        val value = raw.trim()
        if (value.isBlank() || value.equals("null", true)) return null
        val parsed = runCatching { URI(value) }.getOrNull()
        if (parsed != null && (parsed.scheme == "http" || parsed.scheme == "https") && !parsed.host.isNullOrBlank()) return parsed.toString()
        if (value.startsWith('/')) {
            return runCatching { URI(streamServer()).resolve(value).toString() }.getOrNull()
        }
        return null
    }

    private fun apiUrl(action: String? = null, extras: Map<String, String> = emptyMap()): String {
        val base = URI(apiServer())
        val basePath = base.path.orEmpty().trimEnd('/')
        val path = if (basePath.isBlank()) "/player_api.php" else "$basePath/player_api.php"
        val q = mutableListOf(
            "username=${enc(config.username)}",
            "password=${enc(config.password)}"
        )
        if (!action.isNullOrBlank()) q += "action=${enc(action)}"
        extras.forEach { (k, v) -> q += "${enc(k)}=${enc(v)}" }
        return URI(base.scheme, null, base.host, base.port, path, q.joinToString("&"), null).toASCIIString()
    }

    private fun apiServer(): String = config.server.trim().trimEnd('/')
    private fun streamServer(): String = config.streamServer.trim().ifBlank { apiServer() }.trimEnd('/')
    private fun enc(v: String): String = URLEncoder.encode(v, "UTF-8")
    private fun pathEnc(v: String): String = URLEncoder.encode(v, "UTF-8").replace("+", "%20")

    private fun fetchText(url: String, connect: Int, read: Int, limitChars: Int = Int.MAX_VALUE): String {
        val conn = open(url, connect, read)
        try {
            val status = conn.responseCode
            if (status !in 200..299) throw IllegalStateException("HTTP $status")
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
            return sb.toString()
        } finally {
            conn.disconnect()
        }
    }

    private fun open(url: String, connect: Int, read: Int): HttpURLConnection {
        return (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = connect
            readTimeout = read
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", API_UA)
            setRequestProperty("Accept", "application/json,text/plain,*/*")
            setRequestProperty("Connection", "keep-alive")
        }
    }

    private fun cleanExtension(raw: String?, fallback: String): String {
        val value = raw.orEmpty().trim().lowercase(Locale.ROOT).removePrefix(".")
        return if (value.matches(Regex("^[a-z0-9]{2,6}$"))) value else fallback
    }

    private fun cleanText(raw: Any?): String? {
        if (raw == null || raw == JSONObject.NULL) return null
        val value = raw.toString().trim()
        if (value.isBlank() || value.equals("null", true)) return null
        return value
    }

    private fun firstText(o: JSONObject, vararg keys: String): String {
        for (key in keys) cleanText(o.opt(key))?.let { return it }
        return ""
    }

    private fun firstImage(raw: Any?): String {
        when (raw) {
            is JSONArray -> for (i in 0 until raw.length()) cleanText(raw.opt(i))?.let { return it }
            is String -> {
                val value = raw.trim()
                if (value.startsWith("[")) {
                    runCatching { JSONArray(value) }.getOrNull()?.let { arr ->
                        for (i in 0 until arr.length()) cleanText(arr.opt(i))?.let { return it }
                    }
                }
                cleanText(value)?.let { return it }
            }
        }
        return ""
    }

    private fun decodeMaybeBase64(value: String): String {
        if (value.isBlank()) return ""
        return runCatching {
            String(Base64.decode(value, Base64.DEFAULT), StandardCharsets.UTF_8).trim().ifBlank { value }
        }.getOrDefault(value)
    }
}
