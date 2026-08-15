package com.tvfull.pro

import android.content.Intent
import android.graphics.Color
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

        val forceRemote = intent.getBooleanExtra("force_remote", false)
        if (forceRemote) RemotePrefs.enableRemote(this)

        if (!forceRemote && !RemotePrefs.isRemoteEnabled(this) && Prefs.load(this) != null) {
            openMain()
            return
        }

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
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(70), dp(40), dp(70), dp(40))
            setBackgroundColor(Color.rgb(12, 20, 36))
        }

        root.addView(TextView(this).apply {
            text = "TV FULL PRO"
            textSize = 38f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }, LinearLayout.LayoutParams(dp(760), dp(68)))

        root.addView(TextView(this).apply {
            text = "ACTIVACIÓN REMOTA"
            textSize = 19f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(241, 214, 44))
        }, LinearLayout.LayoutParams(dp(760), dp(46)))

        root.addView(TextView(this).apply {
            text = "Asigná este dispositivo desde el panel de TV FULL.\nLa lista y el servicio se cargarán automáticamente."
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 193, 204))
        }, LinearLayout.LayoutParams(dp(820), dp(86)))

        codeText = TextView(this).apply {
            text = "GENERANDO CÓDIGO…"
            textSize = 34f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.rgb(30, 43, 65))
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
        root.addView(codeText, LinearLayout.LayoutParams(dp(680), dp(90)).apply { topMargin = dp(12) })

        statusText = TextView(this).apply {
            text = "Registrando dispositivo…"
            textSize = 17f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 193, 204))
        }
        root.addView(statusText, LinearLayout.LayoutParams(dp(820), dp(70)).apply { topMargin = dp(12) })

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        retry = tvButton("REINTENTAR") {
            handler.removeCallbacks(poll)
            val credentials = RemotePrefs.loadCredentials(this)
            if (credentials == null) registerDevice() else syncNow()
        }
        actions.addView(retry, LinearLayout.LayoutParams(dp(240), dp(58)).apply { marginEnd = dp(14) })

        actions.addView(tvButton("CONFIGURACIÓN MANUAL") {
            RemotePrefs.disableRemote(this)
            startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
            finish()
        }, LinearLayout.LayoutParams(dp(330), dp(58)))

        root.addView(actions, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(70)).apply { topMargin = dp(8) })

        root.addView(TextView(this).apply {
            text = "El dispositivo consulta el panel automáticamente cada pocos segundos."
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(130, 142, 160))
        }, LinearLayout.LayoutParams(dp(820), dp(42)))

        retry.requestFocus()
        return root
    }

    private fun tvButton(label: String, action: () -> Unit): Button {
        return Button(this).apply {
            text = label
            textSize = 15f
            isAllCaps = false
            isFocusable = true
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.rgb(38, 53, 76))
            setOnClickListener { action() }
            setOnFocusChangeListener { v, focused ->
                (v as Button).apply {
                    setBackgroundColor(if (focused) Color.rgb(241, 214, 44) else Color.rgb(38, 53, 76))
                    setTextColor(if (focused) Color.BLACK else Color.WHITE)
                }
            }
        }
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
                        val config = result.config ?: return@runOnUiThread
                        RemotePrefs.enableRemote(this)
                        RemotePrefs.saveService(this, result.serviceId, result.serviceName)
                        Prefs.save(this, config)
                        statusText.text = if (result.serviceName.isBlank()) "Servicio recibido. Iniciando…" else "${result.serviceName} · conectado"
                        openMain()
                    }
                    RemoteConfigState.UNASSIGNED -> {
                        statusText.text = "Esperando que asignes un servicio a ${credentials.code}"
                        schedulePoll(5_000)
                    }
                    RemoteConfigState.DISABLED -> {
                        statusText.text = "Este dispositivo está DESHABILITADO desde el panel."
                        codeText.setTextColor(Color.rgb(242, 80, 80))
                    }
                    RemoteConfigState.INVALID -> {
                        statusText.text = "El registro dejó de ser válido. Generando un código nuevo…"
                        RemotePrefs.clearCredentials(this)
                        handler.postDelayed({ registerDevice() }, 1_000)
                    }
                    RemoteConfigState.ERROR -> {
                        statusText.text = "Sin conexión con el panel. Reintentando…"
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

    private fun openMain() {
        if (launching || stopped) return
        launching = true
        handler.removeCallbacksAndMessages(null)
        startActivity(Intent(this, MainActivity::class.java))
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
