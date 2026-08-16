package com.tvfull.pro

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import java.util.concurrent.Executors

class LoginActivity : AppCompatActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(UiPreferences.wrap(newBase))
    }

    private val io = Executors.newSingleThreadExecutor()
    private lateinit var xtream: RadioButton
    private lateinit var m3u: RadioButton
    private lateinit var server: EditText
    private lateinit var user: EditText
    private lateinit var pass: EditText
    private lateinit var m3uUrl: EditText
    private lateinit var connect: Button
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        immersive()

        if (Prefs.load(this) != null && !intent.getBooleanExtra("force_login", false)) {
            startActivity(Intent(this, TvHomeActivity::class.java))
            finish()
            return
        }
        setContentView(buildUi())
    }

    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(48), dp(30), dp(48), dp(30))
            setBackgroundColor(Color.rgb(12, 20, 36))
        }
        root.addView(TextView(this).apply {
            text = "TV FULL PRO"
            textSize = 34f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }, LinearLayout.LayoutParams(dp(620), dp(60)))
        root.addView(TextView(this).apply {
            text = "Configuración manual de respaldo"
            textSize = 16f
            setTextColor(Color.rgb(185, 193, 204))
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(dp(620), dp(42)))

        val modes = RadioGroup(this).apply { orientation = RadioGroup.HORIZONTAL; gravity = Gravity.CENTER }
        xtream = RadioButton(this).apply {
            id = View.generateViewId(); text = "Xtream"; textSize = 18f; setTextColor(Color.WHITE); isChecked = true; isFocusable = true
        }
        m3u = RadioButton(this).apply {
            id = View.generateViewId(); text = "M3U / Auto"; textSize = 18f; setTextColor(Color.WHITE); isFocusable = true
        }
        modes.addView(xtream, LinearLayout.LayoutParams(dp(180), dp(54)))
        modes.addView(m3u, LinearLayout.LayoutParams(dp(210), dp(54)))
        root.addView(modes)

        server = field("Servidor · http://servidor:puerto")
        user = field("Usuario")
        pass = field("Contraseña").apply { inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD }
        m3uUrl = field("URL M3U o get.php de Xtream").apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            visibility = View.GONE
        }
        root.addView(server); root.addView(user); root.addView(pass); root.addView(m3uUrl)

        connect = Button(this).apply {
            text = "CONECTAR"; textSize = 17f; isAllCaps = true; isFocusable = true
            setTextColor(Color.WHITE); setBackgroundColor(Color.rgb(242, 13, 22)); setOnClickListener { connect() }
        }
        root.addView(connect, LinearLayout.LayoutParams(dp(270), dp(58)).apply { topMargin = dp(18) })

        status = TextView(this).apply {
            textSize = 15f; setTextColor(Color.rgb(185, 193, 204)); gravity = Gravity.CENTER
        }
        root.addView(status, LinearLayout.LayoutParams(dp(760), dp(54)))

        modes.setOnCheckedChangeListener { _, checked ->
            val useM3u = checked == m3u.id
            server.visibility = if (useM3u) View.GONE else View.VISIBLE
            user.visibility = if (useM3u) View.GONE else View.VISIBLE
            pass.visibility = if (useM3u) View.GONE else View.VISIBLE
            m3uUrl.visibility = if (useM3u) View.VISIBLE else View.GONE
            if (useM3u) m3uUrl.requestFocus() else server.requestFocus()
        }
        server.requestFocus()
        return root
    }

    private fun field(hintText: String) = EditText(this).apply {
        hint = hintText; setHintTextColor(Color.rgb(145, 155, 170)); setTextColor(Color.WHITE); textSize = 18f
        setSingleLine(true); isFocusable = true; setPadding(dp(16), 0, dp(16), 0)
        backgroundTintList = android.content.res.ColorStateList.valueOf(Color.rgb(140, 150, 165))
        layoutParams = LinearLayout.LayoutParams(dp(620), dp(58)).apply { topMargin = dp(8) }
    }

    private fun connect() {
        val input = if (m3u.isChecked) {
            SourceConfig(SourceMode.M3U, m3uUrl = m3uUrl.text.toString().trim())
        } else {
            SourceConfig(SourceMode.XTREAM, server = server.text.toString().trim(), username = user.text.toString().trim(), password = pass.text.toString())
        }
        if ((input.mode == SourceMode.M3U && input.m3uUrl.isBlank()) ||
            (input.mode == SourceMode.XTREAM && (input.server.isBlank() || input.username.isBlank() || input.password.isBlank()))) {
            status.text = "Completá los datos para continuar."
            return
        }

        connect.isEnabled = false
        status.text = "Detectando servicio y resolviendo Xtream…"
        io.execute {
            val resolved = runCatching { SourceResolver.resolve(input) }.getOrElse { input }
            val ok = runCatching { CatalogRepository(resolved).validate() }.getOrDefault(false)
            runOnUiThread {
                connect.isEnabled = true
                if (ok) {
                    RemotePrefs.disableRemote(this)
                    Prefs.save(this, resolved)
                    status.text = if (resolved.mode == SourceMode.XTREAM) "Conectado · Xtream" else "Conectado · M3U"
                    startActivity(Intent(this, TvHomeActivity::class.java))
                    finish()
                } else status.text = "No se pudo validar la lista o las credenciales."
            }
        }
    }

    private fun immersive() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        super.onDestroy()
        io.shutdownNow()
    }
}
