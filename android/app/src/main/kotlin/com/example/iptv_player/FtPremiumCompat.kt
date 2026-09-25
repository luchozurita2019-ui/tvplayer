package com.example.iptv_player

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.provider.Settings
import android.util.Base64
import com.byrafael.streamapp.Guard
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.UUID

internal class FtPremiumCompat(private val context: Context) {
    companion object {
        private const val FT_VERSION_CODE = 27
        private const val FT_UA = "FT-PRO/1.0"
        private const val PRIMARY = "https://novax-online.iptvnovax.workers.dev"

        // SHA-256 del certificado público de la APK FT de pruebas autorizada por Rafael.
        // No es una clave privada ni una credencial de usuario.
        private const val FT_CERT_SHA256 =
            "51718e3d28348acf72fc57a395bcb9f1b1a9fe63bc1fcfa3f41b8e8b403cadbe"

        private data class PlatformConfig(
            val url: String,
            val defaultDomain: String,
            val extraDomains: List<String>,
        )

        private val platforms = mapOf(
            "hbomax" to PlatformConfig(
                "https://play.hbomax.com",
                ".max.com",
                listOf(".hbomax.com", ".max.com"),
            ),
            "prime" to PlatformConfig(
                "https://www.primevideo.com",
                ".primevideo.com",
                listOf(".amazon.com"),
            ),
            "crunchyroll" to PlatformConfig(
                "https://www.crunchyroll.com",
                ".crunchyroll.com",
                emptyList(),
            ),
        )
    }

    private val certDigest = hexToBytes(FT_CERT_SHA256)

    init {
        Guard.b = certDigest
        Guard.d = true
        Guard.c = try {
            System.loadLibrary("guard")
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun prepare(platform: String, intento: Int): Map<String, Any?> {
        val key = platform.trim().lowercase()
        val config = platforms[key]
            ?: return mapOf("available" to false, "status" to "unsupported")

        val id = getAnonId()
        val pingOk = runCatching { ping(id) }.getOrDefault(false)
        var session = runCatching { ensureFtSession(id, wantAd = false) }
            .getOrElse {
                FtSessionState(
                    ok = false,
                    httpStatus = -1,
                    queda = 0,
                    libre = false,
                    pro = false,
                    sessionToken = "",
                    vastUrl = "",
                    fallbackAdUrl = "",
                    detail = it.message.orEmpty(),
                )
            }

        if (session.ok &&
            session.queda <= 0 &&
            !session.libre &&
            !session.pro
        ) {
            val activationSession = runCatching {
                ensureFtSession(id, wantAd = true)
            }.getOrElse {
                FtSessionState(
                    ok = false,
                    httpStatus = -1,
                    queda = 0,
                    libre = false,
                    pro = false,
                    sessionToken = "",
                    vastUrl = "",
                    fallbackAdUrl = "",
                    detail = it.message.orEmpty(),
                )
            }
            session = activationSession

            if (session.queda <= 0 && !session.libre && !session.pro) {
                val mode = when {
                    session.fallbackAdUrl.isNotBlank() -> "web"
                    session.vastUrl.isNotBlank() -> "vast"
                    else -> "none"
                }
                return mapOf(
                    "available" to false,
                    "status" to "activation_required",
                    "stage" to "activation",
                    "activation_mode" to mode,
                    "ping_ok" to pingOk,
                    "session_ok" to session.ok,
                    "session_http" to session.httpStatus,
                    "session_queda" to session.queda,
                    "session_libre" to session.libre,
                    "session_pro" to session.pro,
                    "session_token" to session.hasToken,
                    "detail" to when (mode) {
                        "web" -> "activación web disponible"
                        "vast" -> "activación de video disponible"
                        else -> session.detail.ifBlank { "sin método de activación" }
                    },
                )
            }
        }

        val sig = Guard.a.b("plat:ft:$FT_VERSION_CODE:$id")
        if (sig.isBlank()) {
            return mapOf(
                "available" to false,
                "status" to "guard_failed",
                "stage" to "sign",
                "ping_ok" to pingOk,
                "session_ok" to session.ok,
                "session_http" to session.httpStatus,
                "session_queda" to session.queda,
                "session_token" to session.hasToken,
            )
        }

        val map = runCatching { fetchMap(id, sig, intento) }.getOrElse { error ->
            return mapOf(
                "available" to false,
                "status" to "map_failed",
                "stage" to "map",
                "ping_ok" to pingOk,
                "session_ok" to session.ok,
                "session_http" to session.httpStatus,
                "session_queda" to session.queda,
                "session_libre" to session.libre,
                "session_pro" to session.pro,
                "session_token" to session.hasToken,
                "detail" to listOfNotNull(
                    error.message ?: error.javaClass.simpleName,
                    session.detail.takeIf { it.isNotBlank() },
                ).joinToString(" · "),
            )
        }

        val disabled = map.optJSONObject("apagadas")
        if (disabled?.optBoolean(key, false) == true) {
            return mapOf(
                "available" to false,
                "status" to "disabled",
                "stage" to "map",
                "ping_ok" to pingOk,
            )
        }

        val refs = map.optJSONObject("refs")
        val ref = refs?.optString(key, "")?.trim().orEmpty()
        val shared = map.optJSONObject("libres")?.has(key) == true
        val rawCode = map.optJSONObject("codigos")
            ?.optString(key, "")
            ?.trim()
            .orEmpty()

        if (!rawCode.startsWith("premium_id:")) {
            return mapOf(
                "available" to false,
                "status" to if (shared) "free_without_session" else "no_session",
                "stage" to "codes",
                "ping_ok" to pingOk,
                "has_ref" to ref.isNotBlank(),
                "intento" to intento,
            )
        }

        val parsed = decodePremiumCode(rawCode, key, config)
            ?: return mapOf(
                "available" to false,
                "status" to "decode_failed",
                "stage" to "decode",
                "ping_ok" to pingOk,
                "has_ref" to ref.isNotBlank(),
            )

        return mapOf(
            "platform" to key,
            "available" to true,
            "mode" to "webview",
            "shared" to shared,
            "url" to config.url,
            "cookies" to parsed,
            "ref" to ref,
            "intento" to intento,
            "ping_ok" to pingOk,
            "source" to "ft37-direct-web-activation-parity",
        )
    }

    fun reportDead(platform: String, ref: String): Boolean {
        if (!platforms.containsKey(platform)) return false
        if (ref.isBlank() || ref.length > 256) return false

        val id = getAnonId()
        val sig = Guard.a.b("plat:ft:$FT_VERSION_CODE:$id")
        if (sig.isBlank()) return false

        val url = URL(
            "$PRIMARY/pool/dead?vc=$FT_VERSION_CODE" +
                "&id=$id&sig=$sig&ref=$ref"
        )
        val connection = url.openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 6000
            connection.readTimeout = 6000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", FT_UA)
            connection.setRequestProperty("Accept", "application/json")
            connection.responseCode in 200..299
        } finally {
            connection.disconnect()
        }
    }

    private data class FtActivationResult(
        val ok: Boolean,
        val rounds: Int,
        val session: FtSessionState?,
        val detail: String = "",
    )

    internal data class FtAdActivation(
        val token: String,
        val vastUrl: String,
        val fallbackAdUrl: String,
    )

    internal data class FtAdRound(
        val videoUrl: String,
        val skipSeconds: Int,
        val clickUrl: String,
        val round: Int,
        val totalRounds: Int,
        val impressionUrls: List<String>,
        val startUrls: List<String>,
    )

    private data class FtSessionState(
        val ok: Boolean,
        val httpStatus: Int,
        val queda: Int,
        val libre: Boolean,
        val pro: Boolean,
        val sessionToken: String,
        val vastUrl: String,
        val fallbackAdUrl: String,
        val detail: String = "",
    ) {
        val hasToken: Boolean get() = sessionToken.isNotBlank()
    }

    private fun activateAuthorized(id: String): FtActivationResult {
        val activation = ensureFtSession(id, wantAd = true)
        if (!activation.ok || !activation.hasToken) {
            return FtActivationResult(
                ok = false,
                rounds = 0,
                session = activation,
                detail = "activación sin token válido",
            )
        }

        if (activation.queda > 0 || activation.libre || activation.pro) {
            return FtActivationResult(
                ok = true,
                rounds = 0,
                session = activation,
            )
        }

        if (activation.vastUrl.isBlank()) {
            return FtActivationResult(
                ok = false,
                rounds = 0,
                session = activation,
                detail = if (activation.fallbackAdUrl.isNotBlank()) {
                    "activación web requerida"
                } else {
                    "activación sin VAST disponible"
                },
            )
        }

        var rounds = 0
        for (attempt in 0 until 6) {
            val round = fetchAdRound(activation.vastUrl)
                ?: return FtActivationResult(
                    ok = false,
                    rounds = rounds,
                    session = activation,
                    detail = "no se pudo preparar la ronda de activación",
                )

            rounds++
            // Modo de prueba autorizado por el propietario:
            // validamos la ronda en el Worker sin registrar impresiones/start
            // de terceros que no fueron realmente reproducidas.
            val finished = completeAdRound(activation.sessionToken)
                ?: return FtActivationResult(
                    ok = false,
                    rounds = rounds,
                    session = activation,
                    detail = "el Worker no confirmó la ronda",
                )

            if (finished) {
                var latest = activation
                repeat(4) {
                    Thread.sleep(350L)
                    latest = ensureFtSession(id, wantAd = false)
                    if (latest.queda > 0 || latest.libre || latest.pro) {
                        return FtActivationResult(
                            ok = true,
                            rounds = rounds,
                            session = latest,
                        )
                    }
                }
                return FtActivationResult(
                    ok = false,
                    rounds = rounds,
                    session = latest,
                    detail = "activación confirmada pero queda=0",
                )
            }

            // Si el Worker indica más rondas, volvemos a consultar el mismo VAST.
            // El límite de seis iteraciones evita dejar la UI bloqueada indefinidamente.
        }

        return FtActivationResult(
            ok = false,
            rounds = rounds,
            session = ensureFtSession(id, wantAd = false),
            detail = "activación incompleta",
        )
    }

    internal fun prepareWebActivationUrl(): String? {
        val id = getAnonId()
        val session = ensureFtSession(id, wantAd = true)
        if (!session.ok || !session.hasToken) return null
        if (session.queda > 0 || session.libre || session.pro) return ""

        val base = session.fallbackAdUrl.trim()
        if (!isSafeHttpsUrl(base)) return null

        val tvSuffix = if (isTelevision()) "&d=tv" else ""
        return base + tvSuffix + "&auto=1"
    }

    internal fun refreshAfterWebActivation(): Map<String, Any?> {
        val id = getAnonId()
        var latest = ensureFtSession(id, wantAd = false)
        repeat(5) {
            if (latest.queda > 0 || latest.libre || latest.pro) {
                return mapOf(
                    "completed" to true,
                    "http" to latest.httpStatus,
                    "queda" to latest.queda,
                    "libre" to latest.libre,
                    "pro" to latest.pro,
                    "token" to latest.hasToken,
                )
            }
            Thread.sleep(450L)
            latest = ensureFtSession(id, wantAd = false)
        }
        return mapOf(
            "completed" to false,
            "http" to latest.httpStatus,
            "queda" to latest.queda,
            "libre" to latest.libre,
            "pro" to latest.pro,
            "token" to latest.hasToken,
        )
    }

    private fun isTelevision(): Boolean {
        return runCatching {
            val manager = context.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
            manager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        }.getOrDefault(false)
    }

    internal fun requestAdActivation(): FtAdActivation? {
        val id = getAnonId()
        val session = ensureFtSession(id, wantAd = true)
        if (!session.ok || !session.hasToken) return null
        if (session.vastUrl.isBlank() && session.fallbackAdUrl.isBlank()) return null
        return FtAdActivation(
            token = session.sessionToken,
            vastUrl = session.vastUrl,
            fallbackAdUrl = session.fallbackAdUrl,
        )
    }

    internal fun fetchAdRound(vastUrl: String): FtAdRound? {
        if (!isSafeHttpsUrl(vastUrl)) return null
        val connection = URL(vastUrl).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 8000
            connection.readTimeout = 8000
            connection.instanceFollowRedirects = true
            val stream = if (connection.responseCode == 200) {
                connection.inputStream
            } else {
                connection.errorStream
            } ?: return null
            val json = JSONObject(stream.bufferedReader().use { it.readText() })
            if (!json.optBoolean("ok", false)) return null
            val video = json.optString("video", "").trim()
            if (!isSafeHttpsUrl(video)) return null
            FtAdRound(
                videoUrl = video,
                skipSeconds = json.optInt("skip", 8).coerceAtLeast(1),
                clickUrl = json.optString("click", "").trim()
                    .takeIf { isSafeHttpsUrl(it) }
                    .orEmpty(),
                round = json.optInt("n", 1).coerceAtLeast(1),
                totalRounds = json.optInt("de", 1).coerceAtLeast(1),
                impressionUrls = json.optJSONArray("imp").toSafeHttpsList(),
                startUrls = json.optJSONArray("start").toSafeHttpsList(),
            )
        } finally {
            connection.disconnect()
        }
    }

    internal fun fireAdTrackers(urls: List<String>) {
        for (url in urls.distinct().take(16)) {
            if (!isSafeHttpsUrl(url)) continue
            runCatching {
                val connection = URL(url).openConnection() as HttpURLConnection
                try {
                    connection.connectTimeout = 4000
                    connection.readTimeout = 4000
                    connection.instanceFollowRedirects = true
                    connection.responseCode
                } finally {
                    connection.disconnect()
                }
            }
        }
    }

    internal fun completeAdRound(token: String): Boolean? {
        if (token.isBlank()) return null
        val connection = URL("$PRIMARY/vast/ok?t=$token").openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 8000
            connection.readTimeout = 8000
            connection.instanceFollowRedirects = true
            val stream = if (connection.responseCode == 200) {
                connection.inputStream
            } else {
                connection.errorStream
            } ?: return null
            val json = JSONObject(stream.bufferedReader().use { it.readText() })
            json.optBoolean("fin", true)
        } finally {
            connection.disconnect()
        }
    }

    internal fun sessionAfterAd(): Map<String, Any?> {
        val id = getAnonId()
        val session = ensureFtSession(id, wantAd = false)
        return mapOf(
            "ok" to session.ok,
            "http" to session.httpStatus,
            "queda" to session.queda,
            "libre" to session.libre,
            "pro" to session.pro,
            "token" to session.hasToken,
        )
    }

    private fun ensureFtSession(id: String, wantAd: Boolean): FtSessionState {
        val hw = buildHardwareFingerprint()
        val first = requestFtSession(id, hw, wantAd)
        if (first.httpStatus == 401 && hw.isNotBlank()) {
            return requestFtSession(id, "", wantAd)
        }
        return first
    }

    private fun requestFtSession(
        id: String,
        hw: String,
        wantAd: Boolean,
    ): FtSessionState {
        val signInput = buildString {
            append("sesion:ft:")
            append(FT_VERSION_CODE)
            append(":")
            append(id)
            if (hw.isNotBlank()) {
                append(":")
                append(hw)
            }
        }
        val sig = Guard.a.b(signInput)
        if (sig.isBlank()) {
            return FtSessionState(
                ok = false,
                httpStatus = -1,
                queda = 0,
                libre = false,
                pro = false,
                sessionToken = "",
                vastUrl = "",
                fallbackAdUrl = "",
                detail = "sesion sin firma",
            )
        }

        val connection = URL("$PRIMARY/sesion").openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.connectTimeout = 8000
            connection.readTimeout = 8000
            connection.setRequestProperty("content-type", "application/json")

            val body = JSONObject()
                .put("id", id)
                .put("vc", FT_VERSION_CODE)
                .put("hw", hw)
                .put("sig", sig)
                .put("quiero", if (wantAd) 1 else 0)
                .toString()
                .toByteArray(StandardCharsets.UTF_8)
            connection.outputStream.use { it.write(body) }

            val status = connection.responseCode
            if (status != 200) {
                return FtSessionState(
                    ok = false,
                    httpStatus = status,
                    queda = 0,
                    libre = false,
                    pro = false,
                    sessionToken = "",
                    vastUrl = "",
                    fallbackAdUrl = "",
                    detail = readSafeError(connection).ifBlank { "sesion HTTP $status" },
                )
            }

            val raw = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(raw)
            val libre = json.optInt("libre", 0) == 1
            val token = json.optString("t", "").trim()
            FtSessionState(
                ok = json.optBoolean("ok", false) && (token.isNotBlank() || libre || json.optInt("pro", 0) == 1 || json.optInt("queda", 0) > 0),
                httpStatus = status,
                queda = json.optInt("queda", 0),
                libre = libre,
                pro = json.optInt("pro", 0) == 1,
                sessionToken = token,
                vastUrl = json.optString("vast", "").trim(),
                fallbackAdUrl = json.optString("ad", "").trim(),
                detail = when {
                    !json.optBoolean("ok", false) -> "sesion ok=false"
                    token.isBlank() && !libre && json.optInt("pro", 0) != 1 && json.optInt("queda", 0) <= 0 -> "sesion sin autorizacion activa"
                    else -> ""
                },
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun buildHardwareFingerprint(): String {
        return runCatching {
            val androidId = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ANDROID_ID,
            ).orEmpty()
            val source =
                "${Build.MANUFACTURER}|${Build.MODEL}|${Build.DEVICE}|$androidId"
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(source.toByteArray(StandardCharsets.UTF_8))
            digest.joinToString("") { byte -> "%02x".format(byte) }
        }.getOrDefault("")
    }

    private fun getAnonId(): String {
        val prefs = context.getSharedPreferences("ft_state", Context.MODE_PRIVATE)
        val existing = prefs.getString("anon_id", null)
        if (!existing.isNullOrBlank()) return existing
        val created = UUID.randomUUID().toString()
        prefs.edit().putString("anon_id", created).apply()
        return created
    }

    private fun ping(id: String): Boolean {
        val connection = (URL("$PRIMARY/ping").openConnection() as HttpURLConnection)
        return try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 6000
            connection.readTimeout = 6000
            connection.doOutput = true
            connection.instanceFollowRedirects = true
            // FT 3.6 en /ping sólo envía Content-Type.
            connection.setRequestProperty("Content-Type", "application/json")
            val body = JSONObject()
                .put("id", id)
                .put("app", "ft")
                .put("vc", FT_VERSION_CODE)
                .toString()
                .toByteArray(StandardCharsets.UTF_8)
            connection.outputStream.use { it.write(body) }
            connection.responseCode in 200..299
        } finally {
            connection.disconnect()
        }
    }

    private fun fetchMap(id: String, sig: String, intento: Int): JSONObject {
        val url = buildString {
            append(PRIMARY)
            append("/plat/get?vc=")
            append(FT_VERSION_CODE)
            append("&id=")
            append(id)
            append("&sig=")
            append(sig)
            if (intento > 0) {
                append("&intento=")
                append(intento.coerceIn(1, 9))
            }
        }

        fun executeRequest(): JSONObject {
            val connection = URL(url).openConnection() as HttpURLConnection
            return try {
                connection.requestMethod = "GET"
                connection.connectTimeout = 8000
                connection.readTimeout = 8000
                connection.instanceFollowRedirects = true
                connection.setRequestProperty("User-Agent", FT_UA)
                connection.setRequestProperty("Accept", "application/json")
                connection.setRequestProperty("Cache-Control", "no-cache")
                connection.setRequestProperty("Pragma", "no-cache")

                val status = connection.responseCode
                if (status != 200) {
                    val upgrade = connection.getHeaderField("Upgrade").orEmpty()
                    val required = connection.getHeaderField("X-Required-Version").orEmpty()
                    val server = connection.getHeaderField("Server").orEmpty()
                    val safeDetail = readSafeError(connection)

                    val detail = buildString {
                        append("HTTP $status")
                        if (upgrade.isNotBlank()) append(" · Upgrade=$upgrade")
                        if (required.isNotBlank()) append(" · Required-Version=$required")
                        if (server.isNotBlank()) append(" · Server=$server")
                        if (safeDetail.isNotBlank()) append(" · $safeDetail")
                    }
                    error(detail)
                }

                val body = connection.inputStream.bufferedReader().use { it.readText() }
                if (body.isBlank()) error("plat/get respondió vacío")
                JSONObject(body)
            } finally {
                connection.disconnect()
            }
        }

        return try {
            executeRequest()
        } catch (firstError: Throwable) {
            val message = firstError.message.orEmpty()
            if (!message.contains("HTTP 426", ignoreCase = true)) {
                throw firstError
            }

            Thread.sleep(250L)

            runCatching { executeRequest() }.getOrElse { secondError ->
                error(
                    buildString {
                        append("HTTP 426 · reintento fallido")
                        secondError.message?.takeIf { it.isNotBlank() }?.let {
                            append(" · ")
                            append(it)
                        }
                    }
                )
            }
        }
    }
    private fun decodePremiumCode(
        rawCode: String,
        requested: String,
        config: PlatformConfig,
    ): List<Map<String, Any?>>? {
        return runCatching {
            val parts = rawCode.split(":")
            if (parts.size < 5) return null
            if (parts[1].trim().lowercase() != requested) return null

            val payloadText = parts.drop(4).joinToString(":")
            val decoded = String(Base64.decode(payloadText, Base64.DEFAULT), Charsets.UTF_8)
            val payload = JSONObject(decoded)
            val cookies = ArrayList<Map<String, Any?>>()

            if (payload.has("cookiesFull")) {
                val full = payload.getJSONArray("cookiesFull")
                for (i in 0 until full.length()) {
                    val item = full.optJSONObject(i) ?: continue
                    val name = item.optString("name", "")
                    if (name.isBlank()) continue
                    val value = item.optString("value", "")
                    val domain = item.optString("domain", config.defaultDomain)
                    val path = item.optString("path", "/").ifBlank { "/" }
                    cookies.add(
                        mapOf(
                            "name" to name,
                            "value" to value,
                            "domain" to domain,
                            "path" to if (path.startsWith("/")) path else "/",
                            "hostOnly" to item.optBoolean("hostOnly", false),
                            "secure" to true,
                        )
                    )
                }
            } else {
                val legacy = payload.optString("cookies", "")
                for (piece in legacy.split("; ")) {
                    val index = piece.indexOf('=')
                    if (index <= 0) continue
                    val name = piece.substring(0, index)
                    val value = piece.substring(index + 1)
                    if (value.isEmpty()) continue
                    val domains = listOf(config.defaultDomain) + config.extraDomains
                    for (domain in domains) {
                        cookies.add(
                            mapOf(
                                "name" to name,
                                "value" to value,
                                "domain" to domain,
                                "path" to "/",
                                "hostOnly" to false,
                                "secure" to true,
                            )
                        )
                    }
                }
            }

            if (cookies.isEmpty()) null else cookies
        }.getOrNull()
    }

    private fun isSafeHttpsUrl(raw: String): Boolean {
        return runCatching {
            val url = URL(raw)
            url.protocol.equals("https", ignoreCase = true) &&
                url.host.isNotBlank()
        }.getOrDefault(false)
    }

    private fun JSONArray?.toSafeHttpsList(): List<String> {
        if (this == null) return emptyList()
        val out = ArrayList<String>()
        for (index in 0 until length()) {
            val value = optString(index, "").trim()
            if (isSafeHttpsUrl(value)) out.add(value)
        }
        return out
    }

    private fun readSafeError(connection: HttpURLConnection): String {
        val raw = runCatching {
            connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
        }.getOrDefault("")
        if (raw.isBlank()) return ""

        val text = runCatching {
            val json = JSONObject(raw)
            listOf("error", "message", "status", "reason", "code", "detail")
                .mapNotNull { key ->
                    val value = json.opt(key)?.toString()?.trim().orEmpty()
                    if (value.isBlank()) null else "$key=$value"
                }
                .joinToString(" · ")
        }.getOrElse { raw.trim() }

        return text
            .replace(Regex("""[A-Za-z0-9_\-+/=]{40,}"""), "[oculto]")
            .replace(Regex("""\s+"""), " ")
            .take(180)
    }

    private fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0)
        return ByteArray(hex.length / 2) { index ->
            hex.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }
}
