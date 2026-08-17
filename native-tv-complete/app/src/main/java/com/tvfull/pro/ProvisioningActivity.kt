package com.tvfull.pro

import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import java.util.concurrent.Executors
import kotlin.math.min

class ProvisioningActivity : AppCompatActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var codeText: TextView
    private lateinit var statusText: TextView
    private lateinit var retry: Button
    private var stopped = false
    private var launching = false

    private val poll = object : Runnable {
        override fun run() {
            if (!stopped && !launching) syncNow()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        immersive()
        RemotePrefs.enableRemote(this)
        setContentView(buildUi())

        val existing = RemotePrefs.loadCredentials(this)
        if (existing != null) {
            showCode(existing.code)
            statusText.text = "Conectando con el panel…"
            syncNow()
        } else {
            registerDevice()
        }
    }

    private fun buildUi(): View {
        val widthDp = resources.configuration.screenWidthDp.coerceAtLeast(320)
        val heightDp = resources.configuration.screenHeightDp.coerceAtLeast(240)
        val horizontalPadding = (widthDp * 0.055f).toInt().coerceIn(18, 64)
        val verticalPadding = (heightDp * 0.045f).toInt().coerceIn(12, 36)
        val contentWidth = min((widthDp - horizontalPadding * 2).coerceAtLeast(280), 920)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(horizontalPadding), dp(verticalPadding), dp(horizontalPadding), dp(verticalPadding))
            setBackgroundColor(Color.rgb(7, 11, 18))
        }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(18), dp(12), dp(18), dp(12))
        }
        root.addView(content, LinearLayout.LayoutParams(dp(contentWidth), ViewGroup.LayoutParams.WRAP_CONTENT))

        content.addView(TextView(this).apply {
            text = "TV FULL PRO"
            textSize = if (widthDp < 700) 28f else 38f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            letterSpacing = 0.035f
        }, fullWidthWrap())

        content.addView(TextView(this).apply {
            text = "VINCULACIÓN CON TU SERVICIO"
            textSize = if (widthDp < 700) 15f else 19f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(228, 185, 79))
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(6), 0, dp(4))
        }, fullWidthWrap())

        content.addView(TextView(this).apply {
            text = "Usá este código en el panel de TV FULL. No necesitás escribir ninguna URL en el televisor."
            textSize = if (widthDp < 700) 14f else 17f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 195, 210))
            setPadding(dp(8), dp(4), dp(8), dp(12))
        }, fullWidthWrap())

        codeText = TextView(this).apply {
            text = "GENERANDO CÓDIGO…"
            textSize = if (widthDp < 700) 28f else 40f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            letterSpacing = 0.08f
            setPadding(dp(18), dp(16), dp(18), dp(16))
            background = rounded(Color.rgb(15, 25, 39), 14f, Color.rgb(35, 166, 255), 2)
        }
        content.addView(codeText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(4)
        })

        statusText = TextView(this).apply {
            text = "Registrando dispositivo…"
            textSize = if (widthDp < 700) 13f else 16f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 195, 210))
            setPadding(dp(6), dp(12), dp(6), dp(8))
        }
        content.addView(statusText, fullWidthWrap())

        retry = Button(this).apply {
            text = "REINTENTAR"
            textSize = 14f
            isAllCaps = false
            isFocusable = true
            setTextColor(Color.WHITE)
            setPadding(dp(24), dp(10), dp(24), dp(10))
            background = rounded(Color.rgb(24, 38, 57), 10f, Color.rgb(57, 78, 106), 1)
            setOnClickListener {
                handler.removeCallbacks(poll)
                val credentials = RemotePrefs.loadCredentials(this@ProvisioningActivity)
                if (credentials == null) registerDevice() else syncNow()
            }
            setOnFocusChangeListener { v, focused ->
                (v as Button).apply {
                    background = if (focused) {
                        rounded(Color.rgb(228, 185, 79), 10f, Color.rgb(228, 185, 79), 2)
                    } else {
                        rounded(Color.rgb(24, 38, 57), 10f, Color.rgb(57, 78, 106), 1)
                    }
                    setTextColor(if (focused) Color.BLACK else Color.WHITE)
                }
            }
        }
        content.addView(retry, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(4)
        })

        content.addView(TextView(this).apply {
            text = "El televisor consulta el panel automáticamente. Cuando asignes una lista, se sincronizará sin ingresar datos con el control remoto."
            textSize = if (widthDp < 700) 11f else 13f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(121, 137, 158))
            setPadding(dp(8), dp(12), dp(8), 0)
        }, fullWidthWrap())

        retry.requestFocus()
        return root
    }

    private fun registerDevice() {
        if (launching || stopped) return
        retry.isEnabled = false
        codeText.text = "GENERANDO CÓDIGO…"
        statusText.text = "Registrando dispositivo con TV FULL…"
        io.execute {
            val result = runCatching { RemoteProvisioningClient.register() }
            runOnUiThread {
                retry.isEnabled = true
                result.onSuccess { credentials ->
                    RemotePrefs.saveCredentials(this, credentials)
                    showCode(credentials.code)
                    statusText.text = "Código creado. Esperando asignación desde el panel…"
                    schedulePoll(500)
                }.onFailure {
                    statusText.text = "No se pudo registrar el dispositivo. Revisá Internet y reintentá."
                }
            }
        }
    }

    private fun syncNow() {
        if (launching || stopped) return
        val credentials = RemotePrefs.loadCredentials(this) ?: run {
            registerDevice()
            return
        }
        showCode(credentials.code)
        retry.isEnabled = false
        io.execute {
            val result = RemoteProvisioningClient.fetchConfig(credentials)
            runOnUiThread {
                retry.isEnabled = true
                when (result.state) {
                    RemoteConfigState.READY -> {
                        RemotePrefs.enableRemote(this)
                        RemotePrefs.saveServices(this, result.services)
                        statusText.setTextColor(Color.rgb(117, 221, 154))
                        statusText.text = "${result.services.size} lista(s) recibida(s). Preparando catálogo…"
                        openPlaylists()
                    }
                    RemoteConfigState.UNASSIGNED -> {
                        statusText.setTextColor(Color.rgb(185, 195, 210))
                        statusText.text = "Esperando que asignes un servicio a ${credentials.code}"
                        schedulePoll(5_000)
                    }
                    RemoteConfigState.PAYMENT_DUE -> {
                        statusText.setTextColor(Color.rgb(242, 174, 58))
                        statusText.text = result.message.ifBlank { "Servicio suspendido por falta de pago." }
                        codeText.setTextColor(Color.rgb(242, 174, 58))
                        schedulePoll(15_000)
                    }
                    RemoteConfigState.DISABLED -> {
                        statusText.setTextColor(Color.rgb(242, 80, 80))
                        statusText.text = result.message.ifBlank { "Este dispositivo está deshabilitado desde el panel." }
                        codeText.setTextColor(Color.rgb(242, 80, 80))
                        schedulePoll(15_000)
                    }
                    RemoteConfigState.INVALID -> {
                        statusText.setTextColor(Color.rgb(185, 195, 210))
                        statusText.text = "El registro dejó de ser válido. Generando un código nuevo…"
                        RemotePrefs.clearCredentials(this)
                        handler.postDelayed({ registerDevice() }, 1_000)
                    }
                    RemoteConfigState.ERROR -> {
                        statusText.setTextColor(Color.rgb(185, 195, 210))
                        statusText.text = result.message.ifBlank { "Sin conexión con el panel. Reintentando…" }
                        schedulePoll(8_000)
                    }
                }
            }
        }
    }

    private fun schedulePoll(delay: Long) {
        handler.removeCallbacks(poll)
        if (!stopped && !launching) handler.postDelayed(poll, delay)
    }

    private fun showCode(code: String) {
        codeText.text = code
        codeText.setTextColor(Color.WHITE)
    }

    private fun openPlaylists() {
        if (launching || stopped) return
        launching = true
        handler.removeCallbacksAndMessages(null)
        startActivity(Intent(this, PlaylistActivity::class.java))
        finish()
    }

    override fun onStop() {
        super.onStop()
        stopped = true
        handler.removeCallbacksAndMessages(null)
    }

    override fun onStart() {
        super.onStart()
        if (stopped) {
            stopped = false
            if (!launching && ::statusText.isInitialized) schedulePoll(300)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacksAndMessages(null)
        io.shutdownNow()
    }

    private fun fullWidthWrap() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    )

    private fun rounded(fill: Int, radiusDp: Float, stroke: Int, strokeWidthDp: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dp(radiusDp.toInt()).toFloat()
            setStroke(dp(strokeWidthDp), stroke)
        }

    private fun immersive() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}