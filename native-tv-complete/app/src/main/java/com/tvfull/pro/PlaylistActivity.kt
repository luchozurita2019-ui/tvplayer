package com.tvfull.pro

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
        private val CARD = Color.rgb(31, 43, 63)
        private val BORDER = Color.rgb(112, 126, 147)
        private val ACCENT = Color.rgb(229, 9, 20)
        private val TEXT = Color.rgb(244, 247, 251)
        private val MUTED = Color.rgb(159, 171, 190)
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
            setPadding(dp(38), dp(28), dp(38), dp(24))
            setBackgroundColor(BG)
        }

        val brand = TextView(this).apply {
            text = "TV FULL PRO"
            textSize = 37f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
        }
        root.addView(brand, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(58)))

        root.addView(TextView(this).apply {
            text = "ELEGÍ TU LISTA DE REPRODUCCIÓN"
            textSize = 22f
            gravity = Gravity.CENTER
            setTextColor(TEXT)
            setTypeface(typeface, Typeface.BOLD)
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(58)))

        root.addView(TextView(this).apply {
            text = "Seleccioná una lista para abrir TV en vivo, películas, series y radio"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(MUTED)
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(42)))

        recycler = RecyclerView(this).apply {
            layoutManager = LinearLayoutManager(this@PlaylistActivity, RecyclerView.HORIZONTAL, false).apply {
                isItemPrefetchEnabled = false
            }
            adapter = ServiceAdapter(services)
            setItemViewCacheSize(2)
            isHorizontalScrollBarEnabled = false
            clipToPadding = false
            setPadding(dp(16), dp(18), dp(16), dp(18))
        }
        root.addView(recycler, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        actions.addView(tvButton("ACTUALIZAR LISTAS") {
            startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
            finish()
        }, LinearLayout.LayoutParams(dp(260), dp(54)).apply { marginEnd = dp(14) })
        actions.addView(tvButton("CONFIGURACIÓN MANUAL") {
            RemotePrefs.disableRemote(this)
            startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
            finish()
        }, LinearLayout.LayoutParams(dp(300), dp(54)))
        root.addView(actions, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(70)))

        status = TextView(this).apply {
            text = "${services.size} lista(s) disponibles"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(MUTED)
        }
        root.addView(status, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(42)))

        recycler.post {
            recycler.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() ?: recycler.requestFocus()
        }
        return root
    }

    private fun select(service: RemoteService) {
        status.text = "Analizando ${service.name}…"
        recycler.isEnabled = false
        io.execute {
            val resolved = runCatching { SourceResolver.resolve(service.config) }.getOrElse { service.config }
            val ok = runCatching { CatalogRepository(resolved).validate() }.getOrDefault(false)
            runOnUiThread {
                recycler.isEnabled = true
                if (!ok) {
                    status.text = "No se pudo abrir ${service.name}. Revisá el servicio o la conexión."
                    return@runOnUiThread
                }
                Prefs.save(this, resolved)
                RemotePrefs.saveService(this, service.id, service.name)
                status.text = if (resolved.mode == SourceMode.XTREAM) {
                    "${service.name} · Xtream detectado"
                } else {
                    "${service.name} · M3U detectado"
                }
                startActivity(Intent(this, MainActivity::class.java))
                finish()
            }
        }
    }

    private fun tvButton(label: String, action: () -> Unit): Button {
        return Button(this).apply {
            text = label
            textSize = 14f
            isAllCaps = false
            isFocusable = true
            setTextColor(Color.WHITE)
            background = rounded(CARD, 9f, BORDER)
            setOnClickListener { action() }
            setOnFocusChangeListener { v, focused ->
                (v as Button).background = rounded(if (focused) ACCENT else CARD, 9f, if (focused) ACCENT else BORDER)
            }
        }
    }

    private inner class ServiceAdapter(private val data: List<RemoteService>) : RecyclerView.Adapter<ServiceAdapter.Holder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
            val card = LinearLayout(parent.context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(18), dp(18), dp(18), dp(18))
                isFocusable = true
                background = rounded(CARD, 22f, BORDER)
                layoutParams = RecyclerView.LayoutParams(dp(260), dp(230)).apply {
                    marginStart = dp(10)
                    marginEnd = dp(10)
                }
            }
            val title = TextView(parent.context).apply {
                textSize = 23f
                gravity = Gravity.CENTER
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 2
            }
            val type = TextView(parent.context).apply {
                textSize = 12f
                gravity = Gravity.CENTER
                setTextColor(MUTED)
                setPadding(0, dp(12), 0, 0)
                maxLines = 2
            }
            card.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            card.addView(type, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(42)))
            return Holder(card, title, type)
        }

        override fun onBindViewHolder(holder: Holder, position: Int) {
            val service = data[position]
            holder.title.text = service.name
            holder.type.text = when {
                service.config.mode == SourceMode.XTREAM -> "XTREAM"
                SourceResolver.looksLikeXtreamUrl(service.config.m3uUrl) -> "AUTO · M3U / XTREAM"
                else -> "M3U"
            }
            holder.root.setOnClickListener { select(service) }
            holder.root.setOnFocusChangeListener { v, focused ->
                v.background = rounded(if (focused) Color.rgb(69, 22, 31) else CARD, 22f, if (focused) ACCENT else BORDER, if (focused) 3 else 1)
                if (focused) status.text = service.name
            }
        }

        override fun getItemCount(): Int = data.size

        inner class Holder(val root: LinearLayout, val title: TextView, val type: TextView) : RecyclerView.ViewHolder(root)
    }

    private fun rounded(fill: Int, radius: Float, stroke: Int, strokeWidth: Int = 1): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dp(radius.toInt()).toFloat()
            setStroke(dp(strokeWidth), stroke)
        }
    }

    private fun immersive() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        )
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        super.onDestroy()
        io.shutdownNow()
    }
}
