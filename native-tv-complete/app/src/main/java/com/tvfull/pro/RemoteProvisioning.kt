package com.tvfull.pro

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

data class RemoteDeviceCredentials(
    val code: String,
    val secret: String
)

data class RemoteService(
    val id: String,
    val name: String,
    val config: SourceConfig,
    val expiresAt: String = ""
)

enum class RemoteConfigState { READY, UNASSIGNED, DISABLED, INVALID, ERROR }

data class RemoteConfigResult(
    val state: RemoteConfigState,
    val services: List<RemoteService> = emptyList(),
    val message: String = ""
)

object RemotePrefs {
    private const val FILE = "tvfull_remote"

    fun saveCredentials(context: Context, credentials: RemoteDeviceCredentials) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putString("device_code", credentials.code)
            .putString("device_secret", credentials.secret)
            .putBoolean("remote_enabled", true)
            .apply()
    }

    fun loadCredentials(context: Context): RemoteDeviceCredentials? {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val code = p.getString("device_code", "")?.trim().orEmpty()
        val secret = p.getString("device_secret", "")?.trim().orEmpty()
        if (code.isBlank() || secret.isBlank()) return null
        return RemoteDeviceCredentials(code, secret)
    }

    fun saveService(context: Context, serviceId: String, serviceName: String) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putString("service_id", serviceId)
            .putString("service_name", serviceName)
            .putBoolean("remote_enabled", true)
            .apply()
    }

    fun saveServices(context: Context, services: List<RemoteService>) {
        val arr = JSONArray()
        services.forEach { service ->
            arr.put(JSONObject().apply {
                put("id", service.id)
                put("name", service.name)
                put("expires_at", service.expiresAt)
                put("mode", service.config.mode.name)
                put("m3u", service.config.m3uUrl)
                put("server", service.config.server)
                put("username", service.config.username)
                put("password", service.config.password)
                put("fallback_m3u", service.config.fallbackM3uUrl)
            })
        }
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putString("services_json", arr.toString())
            .putBoolean("remote_enabled", true)
            .apply()
    }

    fun loadServices(context: Context): List<RemoteService> {
        val raw = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getString("services_json", "").orEmpty()
        if (raw.isBlank()) return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val mode = runCatching { SourceMode.valueOf(o.optString("mode")) }.getOrDefault(SourceMode.M3U)
                    add(
                        RemoteService(
                            id = o.optString("id"),
                            name = o.optString("name", "Lista ${i + 1}"),
                            expiresAt = o.optString("expires_at"),
                            config = SourceConfig(
                                mode = mode,
                                m3uUrl = o.optString("m3u"),
                                server = o.optString("server"),
                                username = o.optString("username"),
                                password = o.optString("password"),
                                fallbackM3uUrl = o.optString("fallback_m3u")
                            )
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    fun serviceName(context: Context): String =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString("service_name", "").orEmpty()

    fun isRemoteEnabled(context: Context): Boolean {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        return p.getBoolean("remote_enabled", loadCredentials(context) != null)
    }

    fun enableRemote(context: Context) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean("remote_enabled", true).apply()
    }

    fun disableRemote(context: Context) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean("remote_enabled", false).apply()
    }

    fun clearCredentials(context: Context) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .remove("device_code")
            .remove("device_secret")
            .remove("service_id")
            .remove("service_name")
            .remove("services_json")
            .putBoolean("remote_enabled", true)
            .apply()
    }
}

object RemoteProvisioningClient {
    private const val BASE = "https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1"
    private const val REGISTER = "$BASE/tvf-device-register"
    private const val CONFIG = "$BASE/tvf-device-config"

    fun register(): RemoteDeviceCredentials {
        val conn = (URL(REGISTER).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 8_000
            readTimeout = 10_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
        }
        val body = JSONObject()
            .put("platform", "android_tv")
            .put("device_name", listOf(Build.MANUFACTURER, Build.MODEL).filter { it.isNotBlank() }.joinToString(" ").trim())
            .put("app_version", BuildConfig.VERSION_NAME)
            .toString()
        OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(body) }
        val status = conn.responseCode
        val text = readResponse(conn)
        conn.disconnect()
        if (status !in 200..299) throw IllegalStateException("register_http_$status")
        val json = JSONObject(text)
        val code = json.optString("device_code").trim()
        val secret = json.optString("device_secret").trim()
        if (code.isBlank() || secret.isBlank()) throw IllegalStateException("invalid_registration_response")
        return RemoteDeviceCredentials(code, secret)
    }

    fun fetchConfig(credentials: RemoteDeviceCredentials): RemoteConfigResult {
        return try {
            val conn = (URL(CONFIG).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 6_000
                readTimeout = 8_000
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Cache-Control", "no-cache")
                setRequestProperty("x-tvfull-device-code", credentials.code)
                setRequestProperty("x-tvfull-device-secret", credentials.secret)
            }
            val status = conn.responseCode
            val text = readResponse(conn)
            conn.disconnect()

            when (status) {
                200 -> parseConfig(text)
                401 -> RemoteConfigResult(RemoteConfigState.INVALID, message = "Credenciales del dispositivo inválidas")
                403 -> RemoteConfigResult(RemoteConfigState.DISABLED, message = "Dispositivo deshabilitado desde el panel")
                else -> RemoteConfigResult(RemoteConfigState.ERROR, message = "Panel HTTP $status")
            }
        } catch (e: Exception) {
            RemoteConfigResult(RemoteConfigState.ERROR, message = e.message ?: "Error de conexión")
        }
    }

    private fun parseConfig(text: String): RemoteConfigResult {
        val json = JSONObject(text)
        val services = json.optJSONArray("services")
        if (services == null || services.length() == 0) {
            return RemoteConfigResult(RemoteConfigState.UNASSIGNED, message = "Esperando servicio desde el panel")
        }

        val parsed = buildList {
            for (i in 0 until services.length()) {
                val service = services.optJSONObject(i) ?: continue
                val type = service.optString("type").trim().lowercase()
                val id = service.optString("id").trim()
                val name = service.optString("name").trim().ifBlank { "Lista ${i + 1}" }
                val expires = service.optString("expires_at")

                val config = if (type == "m3u") {
                    val url = service.optString("url").trim()
                    if (url.isBlank()) continue
                    SourceConfig(SourceMode.M3U, m3uUrl = url)
                } else {
                    val server = service.optString("server").trim().trimEnd('/')
                    val username = service.optString("username").trim()
                    val password = service.optString("password")
                    if (server.isBlank() || username.isBlank() || password.isBlank()) continue
                    SourceConfig(SourceMode.XTREAM, server = server, username = username, password = password)
                }
                add(RemoteService(id = id, name = name, config = config, expiresAt = expires))
            }
        }

        if (parsed.isEmpty()) {
            return RemoteConfigResult(RemoteConfigState.ERROR, message = "No hay listas válidas asignadas")
        }
        return RemoteConfigResult(RemoteConfigState.READY, services = parsed)
    }

    private fun readResponse(conn: HttpURLConnection): String {
        val stream = if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream
        if (stream == null) return ""
        return BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }
    }
}
