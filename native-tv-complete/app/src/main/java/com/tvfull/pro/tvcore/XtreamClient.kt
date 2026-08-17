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
import java.util.Locale

internal data class HttpPayload(
    val status: Int,
    val finalUrl: String,
    val body: String
)

data class XtreamSession(
    val originalServer: String,
    /** Final player_api.php base, including a panel sub-path when present. */
    val server: String,
    /** Host/base that actually serves /live, /movie and /series streams. */
    val streamServer: String,
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
        "${streamServer.trimEnd('/')}/live/${encPath(username)}/${encPath(password)}/${encPath(streamId)}.${cleanExt(extension, "ts")}" 

    fun movieUrl(streamId: String, extension: String = "mp4"): String =
        "${streamServer.trimEnd('/')}/movie/${encPath(username)}/${encPath(password)}/${encPath(streamId)}.${cleanExt(extension, "mp4")}" 

    fun seriesUrl(streamId: String, extension: String = "mp4"): String =
        "${streamServer.trimEnd('/')}/series/${encPath(username)}/${encPath(password)}/${encPath(streamId)}.${cleanExt(extension, "mp4")}" 

    companion object {
        private fun enc(value: String): String =
            URLEncoder.encode(value, Charsets.UTF_8.name())

        private fun encPath(value: String): String = enc(value).replace("+", "%20")

        private fun cleanExt(value: String, fallback: String): String =
            value.trim().trimStart('.').ifBlank { fallback }
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
        if (payload.status !in 200..299) {
            error("Xtream login HTTP ${payload.status}")
        }

        val json = JSONObject(payload.body)
        val user = json.optJSONObject("user_info")
            ?: error("Xtream sin user_info")
        val authValue = user.opt("auth")
        val status = user.optString("status", "")
        val authorized = authValue == 1 || authValue == "1" || authValue == true ||
            status.equals("Active", true)
        if (!authorized || status.equals("Disabled", true) || status.equals("Banned", true)) {
            error("Cuenta Xtream no autorizada")
        }

        // Keep API redirects and media-serving redirects as two independent
        // concepts. Some Xtream panels authenticate on one host and tell clients
        // to play streams from another host/port in server_info.
        val finalApiServer = serverFromPlayerApi(payload.finalUrl) ?: original
        val serverInfo = json.optJSONObject("server_info") ?: JSONObject()
        val mediaServer = resolveStreamServer(
            apiServer = finalApiServer,
            serverInfo = serverInfo,
            configuredStreamServer = config.streamServer
        )

        return XtreamSession(
            originalServer = original,
            server = finalApiServer,
            streamServer = mediaServer,
            username = config.username.trim(),
            password = config.password,
            fallbackM3uUrl = config.fallbackM3uUrl
        )
    }

    fun array(
        session: XtreamSession,
        action: String,
        extras: Map<String, String> = emptyMap()
    ): JSONArray {
        val payload = fetch(session.apiUrl(action, extras))
        if (payload.status !in 200..299) error("Xtream $action HTTP ${payload.status}")
        return JSONArray(payload.body)
    }

    fun objectResponse(
        session: XtreamSession,
        action: String,
        extras: Map<String, String> = emptyMap()
    ): JSONObject {
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
            setRequestProperty("User-Agent", "TVFULLPlayer/1.0")
            setRequestProperty("Connection", "keep-alive")
        }

        val status = conn.responseCode
        if (status in REDIRECT_CODES) {
            val location = conn.getHeaderField("Location")
            conn.disconnect()
            if (location.isNullOrBlank() || redirectsLeft <= 0) {
                error("Redirección Xtream inválida")
            }
            val next = URI(inputUrl).resolve(location).toString()
            return fetch(next, redirectsLeft - 1)
        }

        val stream = if (status in 200..299) conn.inputStream else conn.errorStream
        val body = if (stream == null) {
            ""
        } else {
            BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }
        }
        conn.disconnect()
        return HttpPayload(status, inputUrl, body)
    }

    /** Preserve an Xtream installation sub-path when a redirected API uses one. */
    private fun serverFromPlayerApi(url: String): String? {
        return runCatching {
            val uri = URI(url)
            if (uri.scheme !in setOf("http", "https") || uri.host.isNullOrBlank()) return null
            var path = uri.path.orEmpty()
            if (path.endsWith("/player_api.php", true)) {
                path = path.dropLast("/player_api.php".length)
            } else if (path.endsWith("player_api.php", true)) {
                path = path.dropLast("player_api.php".length).trimEnd('/')
            }
            URI(uri.scheme, null, uri.host, uri.port, path.ifBlank { null }, null, null)
                .toString()
                .trimEnd('/')
        }.getOrNull()
    }

    private fun resolveStreamServer(
        apiServer: String,
        serverInfo: JSONObject,
        configuredStreamServer: String
    ): String {
        if (configuredStreamServer.isNotBlank()) {
            return normalizeServer(configuredStreamServer)
        }

        val api = URI(normalizeServer(apiServer))
        val requestedProtocol = serverInfo.optString("server_protocol")
            .trim()
            .lowercase(Locale.ROOT)
        val scheme = if (requestedProtocol == "http" || requestedProtocol == "https") {
            requestedProtocol
        } else {
            api.scheme
        }

        var host = api.host
        val rawUrl = serverInfo.optString("url").trim()
        if (rawUrl.isNotBlank()) {
            val candidate = runCatching {
                URI(if (rawUrl.contains("://")) rawUrl else "$scheme://$rawUrl")
            }.getOrNull()
            if (candidate != null && !candidate.host.isNullOrBlank()) {
                host = candidate.host
            }
        }

        val preferredPort = if (scheme == "https") {
            serverInfo.opt("https_port").takeUnless { it == null || it === JSONObject.NULL }
                ?: serverInfo.opt("port")
        } else {
            serverInfo.opt("port")
        }
        var port = preferredPort?.toString()?.toIntOrNull()
        if (port == null || port !in 1..65535) {
            port = if (api.port > 0) api.port else -1
        }

        val path = api.path?.takeIf { it.isNotBlank() && it != "/" }
        return URI(scheme, null, host, port, path, null, null)
            .toString()
            .trimEnd('/')
    }

    private fun normalizeServer(raw: String): String {
        var value = raw.trim().trimEnd('/')
        if (!value.contains("://")) value = "http://$value"
        value = value.substringBefore("/player_api.php").substringBefore("/get.php").trimEnd('/')
        val uri = URI(value)
        require(uri.scheme == "http" || uri.scheme == "https") {
            "Servidor Xtream inválido"
        }
        require(!uri.host.isNullOrBlank()) { "Servidor Xtream inválido" }
        return value
    }

    companion object {
        private val REDIRECT_CODES = setOf(301, 302, 303, 307, 308)
        private fun enc(value: String): String =
            URLEncoder.encode(value, Charsets.UTF_8.name())
    }
}
