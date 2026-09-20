package com.example.iptv_player

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Base64
import com.byrafael.streamapp.Guard
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.UUID

internal class FtPremiumCompat(private val context: Context) {
    companion object {
        private const val FT_VERSION_CODE = 26
        private const val FT_UA = "FT-PRO/1.0"
        private const val PRIMARY = "https://novax-online.iptvnovax.workers.dev"

        // SHA-256 del certificado público de la APK FT 3.6 autorizada por Rafael.
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
        val session = runCatching { ensureFtSession(id) }
            .getOrElse { FtSessionState(false, -1, 0, false, false, it.message.orEmpty()) }
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
            "source" to "ft36-direct",
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

    private data class FtSessionState(
        val ok: Boolean,
        val httpStatus: Int,
        val queda: Int,
        val libre: Boolean,
        val pro: Boolean,
        val detail: String = "",
    )

    private fun ensureFtSession(id: String): FtSessionState {
        val hw = buildHardwareFingerprint()
        val first = requestFtSession(id, hw)
        if (first.httpStatus == 401 && hw.isNotBlank()) {
            return requestFtSession(id, "")
        }
        return first
    }

    private fun requestFtSession(id: String, hw: String): FtSessionState {
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
                .put("quiero", 0)
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
                    detail = readSafeError(connection).ifBlank { "sesion HTTP $status" },
                )
            }

            val raw = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(raw)
            FtSessionState(
                ok = json.optBoolean("ok", false),
                httpStatus = status,
                queda = json.optInt("queda", 0),
                libre = json.optInt("libre", 0) == 1,
                pro = json.optInt("pro", 0) == 1,
                detail = if (json.optBoolean("ok", false)) "" else "sesion ok=false",
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

        val connection = URL(url).openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "GET"
            connection.connectTimeout = 6000
            connection.readTimeout = 6000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", FT_UA)
            val status = connection.responseCode
            if (status != 200) {
                val safeDetail = readSafeError(connection)
                error(if (safeDetail.isBlank()) "HTTP $status" else "HTTP $status · $safeDetail")
            }
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            JSONObject(body)
        } finally {
            connection.disconnect()
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
