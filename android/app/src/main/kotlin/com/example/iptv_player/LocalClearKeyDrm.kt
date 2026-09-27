package com.example.iptv_player

import android.media.MediaDrm
import android.os.Build
import android.util.Base64
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import org.json.JSONObject

/** Licencia temporal provista por el usuario; sin URL, red ni logging. */
@UnstableApi
object LocalClearKeyDrm {
    class ConfigurationException(message: String) : IllegalArgumentException(message)

    fun validate(jwk: String) {
        try {
            require(jwk.length <= 2048)
            val json = JSONObject(jwk)
            require(json.getString("type") == "temporary")
            val keys = json.getJSONArray("keys")
            require(keys.length() == 1)
            val entry = keys.getJSONObject(0)
            require(entry.getString("kty") == "oct")
            for (name in listOf("kid", "k")) {
                val value = entry.getString(name)
                require(Regex("^[A-Za-z0-9_-]{22}$").matches(value))
                require(Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP).size == 16)
            }
        } catch (_: Exception) {
            // No propagar mensajes de JSONObject/Base64: podrían contener claves.
            throw ConfigurationException("La configuración ClearKey local es inválida.")
        }
        if (Build.VERSION.SDK_INT < 21 || !MediaDrm.isCryptoSchemeSupported(C.CLEARKEY_UUID)) {
            throw ConfigurationException("Este dispositivo no admite ClearKey.")
        }
    }

    fun create(jwk: String): DefaultDrmSessionManager {
        validate(jwk)
        return DefaultDrmSessionManager.Builder()
            .setUuidAndExoMediaDrmProvider(C.CLEARKEY_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
            .setSessionKeepaliveMs(C.TIME_UNSET)
            .build(LocalMediaDrmCallback(jwk.toByteArray(Charsets.UTF_8)))
    }
}
