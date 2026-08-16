package com.tvfull.pro

import android.content.Context
import android.content.res.Configuration
import kotlin.math.roundToInt

object UiPreferences {
    private const val FILE = "tvfull_ui"
    private const val KEY_SCALE = "ui_scale"

    const val SMALL = 0.86f
    const val NORMAL = 1.0f
    const val LARGE = 1.14f

    fun scale(context: Context): Float = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        .getFloat(KEY_SCALE, NORMAL)
        .coerceIn(0.80f, 1.20f)

    fun setScale(context: Context, value: Float) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putFloat(KEY_SCALE, value.coerceIn(0.80f, 1.20f))
            .apply()
    }

    fun wrap(base: Context): Context {
        val scale = scale(base)
        if (scale == NORMAL) return base
        val config = Configuration(base.resources.configuration)
        val originalDensity = base.resources.configuration.densityDpi
        config.densityDpi = (originalDensity * scale).roundToInt().coerceAtLeast(120)
        return base.createConfigurationContext(config)
    }

    fun label(context: Context): String = when {
        scale(context) < 0.95f -> "Pequeña"
        scale(context) > 1.05f -> "Grande"
        else -> "Normal"
    }
}
