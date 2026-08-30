package com.example.iptv_player

import android.content.Context
import java.security.MessageDigest

/**
 * Tiny local memory for channels that proved unstable.
 *
 * Only non-zero protection levels are persisted, so large playlists do not
 * create a large database. URLs are hashed before becoming preference keys.
 */
class TvFullAdaptiveLiveProfileStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(
        "tvfull_live_adaptive_profiles_v1",
        Context.MODE_PRIVATE,
    )

    fun loadLevel(url: String): Int {
        if (url.isBlank()) return 0
        return prefs.getInt(key(url), 0).coerceIn(0, 3)
    }

    fun saveLevel(url: String, level: Int) {
        if (url.isBlank()) return
        val key = key(url)
        val safeLevel = level.coerceIn(0, 3)
        if (safeLevel == 0) {
            prefs.edit().remove(key).apply()
        } else {
            prefs.edit().putInt(key, safeLevel).apply()
        }
    }

    private fun key(url: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(url.toByteArray(Charsets.UTF_8))
        val shortHash = digest.take(12).joinToString("") { "%02x".format(it) }
        return "channel_$shortHash"
    }
}
