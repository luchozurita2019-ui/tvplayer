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
import com.tvfull.pro.tvcore.CatalogSyncEngine
import com.tvfull.pro.tvcore.ProvisionedSource
import com.tvfull.pro.tvcore.TvCatalogDatabase
import com.tvfull.pro.tvcore.XtreamStrictSyncEngine
import java.util.concurrent.Executors

class PlaylistActivity : AppCompatActivity() {
    companion object {
        private val BG = Color.rgb(7, 11, 18)
        private val CARD = Color.rgb(17, 27, 42)
        private val BORDER = Color.rgb(48, 67, 93)
        private val ACCENT = Color.rgb(22, 168, 255)
        private val GOLD = Color.rgb(228, 185, 79)
        private val TEXT = Color.rgb(244, 247, 251)
        private val MUTED = Color.rgb(151, 166, 187)
    }

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(UiPreferences.wrap(newBase))
    }

    private val io = Executors.newSingleThreadExecutor()
    private lateinit var status: TextView
    private lateinit var recycler: RecyclerView
    private var services: List<RemoteService> = emptyList()
    private var opening = false

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
        val widthDp = resources.configuration.screenWidthDp.coerceAtLeast(320)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp((widthDp * 0.035f).toInt().coerceIn(16, 42)), dp(18), dp((widthDp * 0.035f).toInt().coerceIn(16, 42)), dp(16))
            setBackgroundColor(BG)
        }

        root.addView(TextView(this).apply {
            text = "TV FULL PRO"
            textSize = if (widthDp < 700) 26f else 32f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
        }, wrapFull())

        root.addView(TextView(this).apply {
            text = "SERVICIOS ASIGNADOS"
            textSize = if (widthDp < 700) 16f else 20f
            gravity = Gravity.CENTER
            setTextColor(GOLD)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(2), 0, 0)
        }, wrapFull())

        root.addView(TextView(this).apply {
            text = "Elegí un servicio. TV FULL lo sincroniza localmente antes de abrir el contenido."
            textSize = if (widthDp < 700) 12f else 14f
            gravity = Gravity.CENTER
            setTextColor(MUTED)
            setPadding(dp(8), dp(4), dp(8), dp(8))
        }, wrapFull())

        recycler = RecyclerView(this).apply {
            layoutManager = LinearLayoutManager(this@PlaylistActivity, RecyclerView.HORIZONTAL, false)
            adapter = ServiceAdapter(services)
            setItemViewCacheSize(4)
            isHorizontalScrollBarEnabled = false
            clipToPadding = false
            setPadding(dp(8), dp(10), dp(8), dp(10))
        }
        root.addView(recycler, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        status = TextView(this).apply {
            text = "${services.size} servicio(s) disponible(s)"
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(MUTED)
            setPadding(dp(8), dp(5), dp(8), dp(5))
        }
        root.addView(status, wrapFull())

        val refresh = tvButton("ACTUALIZAR DESDE PANEL") {
            if (!opening) {
                startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
                finish()
            }
        }
        root.addView(refresh, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(4)
        })

        recycler.post {
            recycler.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() ?: recycler.requestFocus()
        }
        return root
    }

    private fun select(service: RemoteService) {
        if (opening) return
        opening = true
        recycler.isEnabled = false
        status.setTextColor(MUTED)
        status.text = "Sincronizando ${service.name}…"

        io.execute {
            val db = TvCatalogDatabase(applicationContext)
            var resolvedForSession: RemoteService? = null
            val result = runCatching {
                // A service can arrive from the panel as M3U while actually being an
                // Xtream get.php URL. Resolve it before sync so player_api.php stays
                // authoritative for categories, names and ordering.
                val resolvedConfig = SourceResolver.resolve(service.config)
                resolvedForSession = service.copy(config = resolvedConfig)
                val source = ProvisionedSource(
                    serviceId = service.id,
                    serviceName = service.name,
                    config = resolvedConfig,
                    expiresAt = service.expiresAt
                )
                if (resolvedConfig.mode == SourceMode.XTREAM) {
                    XtreamStrictSyncEngine(db).sync(source)
                } else {
                    CatalogSyncEngine(db).sync(source)
                }
            }
            db.close()

            runOnUiThread {
                recycler.isEnabled = true
                result.onSuccess { report ->
                    // Keep the resolved configuration locally for the Activity that is
                    // about to open. This is essential for get_series_info on services
                    // provisioned as an Xtream get.php URL under service_type=m3u.
                    resolvedForSession?.let { resolved ->
                        services = services.map { if (it.id == resolved.id) resolved else it }
                        RemotePrefs.saveServices(this, services)
                    }
                    RemotePrefs.saveService(this, service.id, service.name)
                    status.setTextColor(Color.rgb(117, 221, 154))
                    status.text = "${service.name} · ${report.liveCount} canales · ${report.movieCount} películas · ${report.seriesCount} series"
                    startActivity(Intent(this, TvIptvActivity::class.java))
                    finish()
                }.onFailure { error ->
                    opening = false
                    status.setTextColor(Color.rgb(242, 101, 101))
                    status.text = "No se pudo sincronizar ${service.name}: ${error.message ?: "error de conexión"}"
                }
            }
        }
    }

    private fun tvButton(label: String, action: () -> Unit): Button = Button(this).apply {
        text = label
        textSize = 12f
        isAllCaps = false
        isFocusable = true
        setTextColor(Color.WHITE)
        background = rounded(CARD, 9f, BORDER, 1)
        setOnClickListener { action() }
        setOnFocusChangeListener { v, focused ->
            (v as Button).apply {
                background = rounded(if (focused) ACCENT else CARD, 9f, if (focused) ACCENT else BORDER, if (focused) 2 else 1)
                setTextColor(Color.WHITE)
            }
        }
    }

    private inner class ServiceAdapter(private val data: List<RemoteService>) : RecyclerView.Adapter<ServiceAdapter.Holder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
            val width = if (resources.configuration.screenWidthDp < 700) dp(180) else dp(230)
            val height = if (resources.configuration.screenHeightDp < 500) dp(122) else dp(150)
            val card = LinearLayout(parent.context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(12), dp(10), dp(12), dp(10))
                isFocusable = true
                background = rounded(CARD, 14f, BORDER, 1)
                layoutParams = RecyclerView.LayoutParams(width, height).apply {
                    marginStart = dp(7)
                    marginEnd = dp(7)
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
                textSize = 11f
                gravity = Gravity.CENTER
                setTextColor(GOLD)
                setPadding(0, dp(7), 0, 0)
                maxLines = 1
            }
            card.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            card.addView(type, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            return Holder(card, title, type)
        }

        override fun onBindViewHolder(holder: Holder, position: Int) {
            val service = data[position]
            holder.title.text = service.name
            holder.type.text = if (
                service.config.mode == SourceMode.XTREAM ||
                SourceResolver.looksLikeXtreamUrl(service.config.m3uUrl)
            ) "XTREAM" else "M3U"
            holder.root.setOnClickListener { select(service) }
            holder.root.setOnFocusChangeListener { v, focused ->
                v.background = rounded(
                    if (focused) Color.rgb(13, 74, 112) else CARD,
                    14f,
                    if (focused) ACCENT else BORDER,
                    if (focused) 3 else 1
                )
                if (focused && !opening) status.text = service.name
            }
        }

        override fun getItemCount() = data.size
        inner class Holder(val root: LinearLayout, val title: TextView, val type: TextView) : RecyclerView.ViewHolder(root)
    }

    private fun wrapFull() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    )

    private fun rounded(fill: Int, radius: Float, stroke: Int, strokeWidth: Int): GradientDrawable =
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
