package com.tvfull.pro.tvcore

import com.tvfull.pro.SourceConfig
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLEncoder

internal data class HttpPayload(val status: Int, val finalUrl: String, val body: String)

data class XtreamSession(
    val originalServer: String,
    val server: String,
    val username: String,
    val password: String,
    val fallbackM3uUrl: String = ""
) {
    fun apiUrl(action: String? = null, extras: Map<String, String> = emptyMap()): String {
        val params = LinkedHashMap<String, String>()
        params["username"] = username
        params["password"] = password
        if (!action.isNullOrBlank()) params["action"] = action
        params.putAll(extras)
        return server.trimEnd('/') + "/player_api.php?" + params.entries.joinToString("&") {
            enc(it.key) + "=" + enc(it.value)
        }
    }

    fun liveUrl(streamId: String, extension: String = "ts"): String =
        "${server.trimEnd('/')}/live/${encPath(username)}/${encPath(password)}/${encPath(streamId)}.${cleanExt(extension, "ts")}" 

    fun movieUrl(streamId: String, extension: String = "mp4"): String =
        "${server.trimEnd('/')}/movie/${encPath(username)}/${encPath(password)}/${encPath(streamId)}.${cleanExt(extension, "mp4")}" 

    fun seriesUrl(streamId: String, extension: String = "mp4"): String =
        "${server.trimEnd('/')}/series/${encPath(username)}/${encPath(password)}/${encPath(streamId)}.${cleanExt(extension, "mp4")}" 

    companion object {
        private fun enc(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())
        private fun encPath(value: String): String = enc(value).replace("+", "%20")
        private fun cleanExt(value: String, fallback: String): String = value.trim().trimStart('.').ifBlank { fallback }
    }
}

class XtreamClient {
    fun authenticate(config: SourceConfig): XtreamSession {
        require(config.server.isNotBlank()) { "Xtream server vacío" }
        require(config.username.isNotBlank()) { "Xtream usuario vacío" }
        require(config.password.isNotBlank()) { "Xtream contraseña vacía" }

        val original = normalizeServer(config.server)
        val initial = "$original/player_api.php?username=${enc(config.username)}&password=${enc(config.password)}"
        val payload = fetch(initial)
        if (payload.status !in 200..299) error("Xtream login HTTP ${payload.status}")

        val json = JSONObject(payload.body)
        val user = json.optJSONObject("user_info")
        if (user != null) {
            val auth = user.optInt("auth", 1)
            val status = user.optString("status", "Active")
            if (auth == 0 || status.equals("Disabled", true) || status.equals("Banned", true)) {
                error("Cuenta Xtream no autorizada")
            }
        }

        val finalServer = serverFromPlayerApi(payload.finalUrl) ?: original
        return XtreamSession(
            originalServer = original,
            server = finalServer,
            username = config.username,
            password = config.password,
            fallbackM3uUrl = config.fallbackM3uUrl
        )
    }

    fun array(session: XtreamSession, action: String, extras: Map<String, String> = emptyMap()): JSONArray {
        val payload = fetch(session.apiUrl(action, extras))
        if (payload.status !in 200..299) error("Xtream $action HTTP ${payload.status}")
        return JSONArray(payload.body)
    }

    fun objectResponse(session: XtreamSession, action: String, extras: Map<String, String> = emptyMap()): JSONObject {
        val payload = fetch(session.apiUrl(action, extras))
        if (payload.status !in 200..299) error("Xtream $action HTTP ${payload.status}")
        return JSONObject(payload.body)
    }

    fun fetchText(url: String): String {
        val payload = fetch(url)
        if (payload.status !in 200..299) error("HTTP ${payload.status}")
        return payload.body
    }

    private fun fetch(inputUrl: String, redirectsLeft: Int = 5): HttpPayload {
        val conn = (URL(inputUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = false
            connectTimeout = 10_000
            readTimeout = 30_000
            setRequestProperty("Accept", "application/json,text/plain,*/*")
            setRequestProperty("User-Agent", "TV FULL PRO")
            setRequestProperty("Connection", "keep-alive")
        }

        val status = conn.responseCode
        if (status in setOf(301, 302, 303, 307, 308)) {
            val location = conn.getHeaderField("Location")
            conn.disconnect()
            if (location.isNullOrBlank() || redirectsLeft <= 0) error("Redirección Xtream inválida")
            val next = URI(inputUrl).resolve(location).toString()
            return fetch(next, redirectsLeft - 1)
        }

        val stream = if (status in 200..299) conn.inputStream else conn.errorStream
        val body = if (stream == null) "" else BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }
        conn.disconnect()
        return HttpPayload(status, inputUrl, body)
    }

    private fun serverFromPlayerApi(url: String): String? {
        return runCatching {
            val uri = URI(url)
            val port = if (uri.port > 0) ":${uri.port}" else ""
            "${uri.scheme}://${uri.host}$port"
        }.getOrNull()?.takeIf { it.startsWith("http") }
    }

    private fun normalizeServer(raw: String): String {
        var s = raw.trim().trimEnd('/')
        if (!s.startsWith("http://", true) && !s.startsWith("https://", true)) s = "http://$s"
        return s.substringBefore("/player_api.php").substringBefore("/get.php").trimEnd('/')
    }

    companion object {
        private fun enc(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())
    }
}
