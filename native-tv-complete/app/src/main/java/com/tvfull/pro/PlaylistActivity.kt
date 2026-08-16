package com.tvfull.pro

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.util.concurrent.Executors

class PlaylistActivity : AppCompatActivity() {
    companion object {
        private val BG = Color.rgb(8, 15, 29)
        private val CARD = Color.rgb(27, 39, 58)
        private val BORDER = Color.rgb(91, 108, 134)
        private val ACCENT = Color.rgb(229, 9, 20)
        private val TEXT = Color.rgb(244, 247, 251)
        private val MUTED = Color.rgb(159, 171, 190)
    }

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(UiPreferences.wrap(newBase))
    }

    private val io = Executors.newSingleThreadExecutor()
    private lateinit var status: TextView
    private lateinit var recycler: RecyclerView
    private var services: List<RemoteService> = emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        immersive()

        services = RemotePrefs.loadServices(this)
        if (services.isEmpty()) {
            startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
            finish()
            return
        }
        setContentView(buildUi())
    }

    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(22), dp(28), dp(18))
            setBackgroundColor(BG)
        }

        root.addView(TextView(this).apply {
            text = "TV FULL PRO"
            textSize = 31f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)))

        root.addView(TextView(this).apply {
            text = "MIS LISTAS"
            textSize = 20f
            gravity = Gravity.CENTER
            setTextColor(TEXT)
            setTypeface(typeface, Typeface.BOLD)
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(42)))

        root.addView(TextView(this).apply {
            text = "Elegí una lista para continuar"
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(MUTED)
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(34)))

        recycler = RecyclerView(this).apply {
            layoutManager = LinearLayoutManager(this@PlaylistActivity, RecyclerView.HORIZONTAL, false).apply {
                isItemPrefetchEnabled = false
            }
            adapter = ServiceAdapter(services)
            setItemViewCacheSize(2)
            isHorizontalScrollBarEnabled = false
            clipToPadding = false
            setPadding(dp(8), dp(12), dp(8), dp(12))
        }
        root.addView(recycler, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        actions.addView(tvButton("ACTUALIZAR") {
            startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
            finish()
        }, LinearLayout.LayoutParams(dp(190), dp(48)).apply { marginEnd = dp(10) })
        actions.addView(tvButton("CONFIGURACIÓN MANUAL") {
            RemotePrefs.disableRemote(this)
            startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
            finish()
        }, LinearLayout.LayoutParams(dp(250), dp(48)))
        root.addView(actions, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(60)))

        status = TextView(this).apply {
            text = "${services.size} lista(s) disponibles"
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(MUTED)
        }
        root.addView(status, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(34)))

        recycler.post {
            recycler.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() ?: recycler.requestFocus()
        }
        return root
    }

    private fun select(service: RemoteService) {
        status.text = "Abriendo ${service.name}…"
        recycler.isEnabled = false
        io.execute {
            val resolved = runCatching { SourceResolver.resolve(service.config) }.getOrElse { service.config }
            val ok = runCatching { CatalogRepository(resolved).validate() }.getOrDefault(false)
            runOnUiThread {
                recycler.isEnabled = true
                if (!ok) {
                    status.text = "No se pudo abrir ${service.name}. Revisá la conexión."
                    return@runOnUiThread
                }
                Prefs.save(this, resolved)
                RemotePrefs.saveService(this, service.id, service.name)
                status.text = if (resolved.mode == SourceMode.XTREAM) "${service.name} · Xtream" else "${service.name} · M3U"
                startActivity(Intent(this, TvHomeActivity::class.java))
                finish()
            }
        }
    }

    private fun tvButton(label: String, action: () -> Unit): Button = Button(this).apply {
        text = label
        textSize = 12f
        isAllCaps = false
        isFocusable = true
        setTextColor(Color.WHITE)
        background = rounded(CARD, 8f, BORDER)
        setOnClickListener { action() }
        setOnFocusChangeListener { v, focused ->
            (v as Button).background = rounded(if (focused) ACCENT else CARD, 8f, if (focused) ACCENT else BORDER)
        }
    }

    private inner class ServiceAdapter(private val data: List<RemoteService>) : RecyclerView.Adapter<ServiceAdapter.Holder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
            val card = LinearLayout(parent.context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(10), dp(10), dp(10), dp(10))
                isFocusable = true
                background = rounded(CARD, 16f, BORDER)
                layoutParams = RecyclerView.LayoutParams(dp(190), dp(132)).apply {
                    marginStart = dp(6)
                    marginEnd = dp(6)
                }
            }
            val title = TextView(parent.context).apply {
                textSize = 17f
                gravity = Gravity.CENTER
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 2
            }
            val type = TextView(parent.context).apply {
                textSize = 10f
                gravity = Gravity.CENTER
                setTextColor(MUTED)
                setPadding(0, dp(6), 0, 0)
                maxLines = 1
            }
            card.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            card.addView(type, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(25)))
            return Holder(card, title, type)
        }

        override fun onBindViewHolder(holder: Holder, position: Int) {
            val service = data[position]
            holder.title.text = service.name
            holder.type.text = when {
                service.config.mode == SourceMode.XTREAM -> "XTREAM"
                SourceResolver.looksLikeXtreamUrl(service.config.m3uUrl) -> "AUTO"
                else -> "M3U"
            }
            holder.root.setOnClickListener { select(service) }
            holder.root.setOnFocusChangeListener { v, focused ->
                v.background = rounded(if (focused) Color.rgb(70, 20, 30) else CARD, 16f, if (focused) ACCENT else BORDER, if (focused) 3 else 1)
                if (focused) status.text = service.name
            }
        }

        override fun getItemCount() = data.size
        inner class Holder(val root: LinearLayout, val title: TextView, val type: TextView) : RecyclerView.ViewHolder(root)
    }

    private fun rounded(fill: Int, radius: Float, stroke: Int, strokeWidth: Int = 1): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dp(radius.toInt()).toFloat()
            setStroke(dp(strokeWidth), stroke)
        }

    private fun immersive() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        super.onDestroy()
        io.shutdownNow()
    }
}
