package com.tvfull.pro

import android.app.ActivityManager
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

@UnstableApi
class MainActivity : AppCompatActivity() {
    private lateinit var repository: CatalogRepository
    private val io = Executors.newFixedThreadPool(3)
    private val handler = Handler(Looper.getMainLooper())

    private lateinit var categoriesView: RecyclerView
    private lateinit var itemsView: RecyclerView
    private lateinit var categoryAdapter: TvListAdapter<TvCategory>
    private lateinit var itemAdapter: TvListAdapter<ContentItem>
    private lateinit var playerView: PlayerView
    private lateinit var loading: View
    private lateinit var loadingText: TextView
    private lateinit var infoTitle: TextView
    private lateinit var infoBody: TextView
    private lateinit var sectionTitle: TextView
    private lateinit var clock: TextView
    private lateinit var countText: TextView

    private var player: ExoPlayer? = null
    private var currentSection = ContentSection.LIVE
    private var currentItems: List<ContentItem> = emptyList()
    private var lastPlayed: ContentItem? = null
    private var waitingFirstFrame = false
    private var startupToken = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        immersive()
        val config = Prefs.load(this)
        if (config == null) {
            goLogin()
            return
        }
        repository = CatalogRepository(config)
        setContentView(buildUi(config))
        updateClock()
        loadSection(ContentSection.LIVE)
    }

    override fun onStart() {
        super.onStart()
        if (::playerView.isInitialized && player == null) initPlayer()
    }

    override fun onStop() {
        super.onStop()
        releasePlayer()
    }

    private fun buildUi(config: SourceConfig): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(12, 20, 36))
        }

        val top = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), 0, dp(18), 0)
            setBackgroundColor(Color.rgb(15, 25, 44))
        }
        top.addView(TextView(this).apply {
            text = "🔥 TV FULL PRO"
            textSize = 24f
            setTextColor(Color.WHITE)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }, LinearLayout.LayoutParams(dp(280), dp(64)))

        sectionTitle = TextView(this).apply {
            text = "TV EN VIVO"
            textSize = 18f
            setTextColor(Color.rgb(241, 214, 44))
            gravity = Gravity.CENTER_VERTICAL
        }
        top.addView(sectionTitle, LinearLayout.LayoutParams(0, dp(64), 1f))

        countText = TextView(this).apply {
            text = if (config.mode == SourceMode.M3U) "M3U" else "XTREAM"
            textSize = 15f
            setTextColor(Color.rgb(185, 193, 204))
            gravity = Gravity.CENTER
        }
        top.addView(countText, LinearLayout.LayoutParams(dp(180), dp(64)))

        clock = TextView(this).apply {
            textSize = 17f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        top.addView(clock, LinearLayout.LayoutParams(dp(100), dp(64)))
        root.addView(top)

        val body = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        root.addView(body, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        val rail = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            setPadding(dp(8), dp(10), dp(8), dp(10))
            setBackgroundColor(Color.rgb(15, 25, 44))
        }
        body.addView(rail, LinearLayout.LayoutParams(dp(142), ViewGroup.LayoutParams.MATCH_PARENT))
        rail.addView(navButton("TV EN VIVO") { loadSection(ContentSection.LIVE) })
        rail.addView(navButton("PELÍCULAS") { loadSection(ContentSection.MOVIES) })
        rail.addView(navButton("SERIES") { loadSection(ContentSection.SERIES) })
        rail.addView(navButton("BUSCAR") { showSearch() })
        rail.addView(navButton("AJUSTES") { showSettings(config) })
        rail.addView(navButton("SALIR") { finishAffinity() })

        categoriesView = RecyclerView(this).apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            setBackgroundColor(Color.rgb(21, 31, 49))
            setPadding(dp(8), dp(8), dp(8), dp(8))
            clipToPadding = false
        }
        body.addView(categoriesView, LinearLayout.LayoutParams(dp(320), ViewGroup.LayoutParams.MATCH_PARENT))

        itemsView = RecyclerView(this).apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            setBackgroundColor(Color.rgb(17, 27, 44))
            setPadding(dp(8), dp(8), dp(8), dp(8))
            clipToPadding = false
        }
        body.addView(itemsView, LinearLayout.LayoutParams(dp(390), ViewGroup.LayoutParams.MATCH_PARENT))

        val right = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
        }
        body.addView(right, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))

        val videoFrame = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        playerView = PlayerView(this).apply {
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(Color.BLACK)
        }
        videoFrame.addView(playerView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val loadingWrap = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.argb(80, 0, 0, 0))
        }
        loading = loadingWrap
        loadingWrap.addView(ProgressBar(this).apply { isIndeterminate = true }, LinearLayout.LayoutParams(dp(58), dp(58)))
        loadingText = TextView(this).apply {
            text = "Seleccioná un canal"
            textSize = 15f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        loadingWrap.addView(loadingText, LinearLayout.LayoutParams(dp(360), dp(50)))
        videoFrame.addView(loadingWrap, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        right.addView(videoFrame, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.60f))

        val info = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22), dp(18), dp(22), dp(18))
            setBackgroundColor(Color.rgb(30, 43, 65))
        }
        infoTitle = TextView(this).apply {
            text = "TV FULL PRO"
            textSize = 21f
            setTextColor(Color.WHITE)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
        infoBody = TextView(this).apply {
            text = "Elegí una categoría y un canal."
            textSize = 16f
            setTextColor(Color.rgb(185, 193, 204))
            setPadding(0, dp(12), 0, 0)
        }
        info.addView(infoTitle)
        info.addView(infoBody)
        right.addView(info, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.40f).apply { topMargin = dp(8) })

        categoryAdapter = TvListAdapter(
            label = { c -> if (c.count > 0) "${c.name}\nTotal: ${c.count}" else c.name },
            onClick = { category -> loadItems(category) },
            onFocus = { c -> infoTitle.text = c.name }
        )
        categoriesView.adapter = categoryAdapter

        itemAdapter = TvListAdapter(
            label = { i -> i.name },
            onClick = { item -> openItem(item) },
            onFocus = { item -> showItemInfo(item) }
        )
        itemsView.adapter = itemAdapter

        return root
    }

    private fun navButton(textValue: String, action: () -> Unit): Button {
        return Button(this).apply {
            text = textValue
            textSize = 13f
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
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(66)).apply { bottomMargin = dp(8) }
        }
    }

    private fun loadSection(section: ContentSection) {
        currentSection = section
        sectionTitle.text = when (section) {
            ContentSection.LIVE -> "TV EN VIVO"
            ContentSection.MOVIES -> "PELÍCULAS"
            ContentSection.SERIES -> "SERIES"
        }
        categoryAdapter.submit(emptyList())
        itemAdapter.submit(emptyList())
        currentItems = emptyList()
        infoTitle.text = sectionTitle.text
        infoBody.text = "Cargando categorías…"
        io.execute {
            val result = runCatching { repository.loadCategories(section) }
            runOnUiThread {
                result.onSuccess { cats ->
                    categoryAdapter.submit(cats)
                    infoBody.text = "${cats.size} categorías disponibles"
                    cats.firstOrNull()?.let { loadItems(it) }
                    categoriesView.post { categoriesView.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() }
                }.onFailure { showCatalogError(it.message) }
            }
        }
    }

    private fun loadItems(category: TvCategory) {
        infoTitle.text = category.name
        infoBody.text = "Cargando contenido…"
        itemAdapter.submit(emptyList())
        io.execute {
            val result = runCatching { repository.loadItems(currentSection, category.id) }
            runOnUiThread {
                result.onSuccess { list ->
                    currentItems = list
                    itemAdapter.submit(list)
                    countText.text = "${list.size} elementos"
                    infoBody.text = if (list.isEmpty()) "No hay contenido en esta categoría." else "${list.size} elementos"
                }.onFailure { showCatalogError(it.message) }
            }
        }
    }

    private fun openItem(item: ContentItem) {
        if (item.section == ContentSection.SERIES && item.url.isBlank() && item.seriesId.isNotBlank()) {
            infoTitle.text = item.name
            infoBody.text = "Cargando episodios…"
            io.execute {
                val result = runCatching { repository.loadSeriesEpisodes(item.seriesId) }
                runOnUiThread {
                    result.onSuccess { eps ->
                        currentItems = eps
                        itemAdapter.submit(eps)
                        sectionTitle.text = "SERIES · ${item.name}"
                        infoBody.text = "${eps.size} episodios"
                        itemsView.post { itemsView.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() }
                    }.onFailure { showCatalogError(it.message) }
                }
            }
            return
        }
        if (item.url.isBlank()) {
            infoBody.text = "Este elemento no tiene una URL reproducible."
            return
        }
        play(item)
    }

    private fun showItemInfo(item: ContentItem) {
        infoTitle.text = item.name
        infoBody.text = when (item.section) {
            ContentSection.LIVE -> "Canal ${item.id} · ${item.categoryId.ifBlank { "TV en vivo" }}"
            ContentSection.MOVIES -> "Película · ${item.categoryId}"
            ContentSection.SERIES -> if (item.url.isBlank()) "Serie · OK para ver episodios" else item.extra
        }
        if (item.section == ContentSection.LIVE) loadEpg(item)
    }

    private fun loadEpg(item: ContentItem) {
        io.execute {
            val epg = repository.loadShortEpg(item.id)
            if (epg.isEmpty()) return@execute
            val text = epg.joinToString("\n\n") { e ->
                buildString {
                    append(e.title.ifBlank { "Programa" })
                    if (e.start.isNotBlank()) append("\n${e.start}  →  ${e.end}")
                    if (e.description.isNotBlank()) append("\n${e.description}")
                }
            }
            runOnUiThread {
                if (infoTitle.text.toString() == item.name) infoBody.text = text
            }
        }
    }

    private fun initPlayer() {
        val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val lowRam = am.isLowRamDevice
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(5_000, 15_000, 2_500, 1_000)
            .setTargetBufferBytes(if (lowRam) 16 * 1024 * 1024 else 28 * 1024 * 1024)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val renderers = DefaultRenderersFactory(this)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)

        val dataSource = DefaultHttpDataSource.Factory()
            .setUserAgent("TV-FULL-PRO/1.0 AndroidTV")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(8_000)
            .setReadTimeoutMs(15_000)

        val p = ExoPlayer.Builder(this, renderers)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSource))
            .build()

        p.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_BUFFERING -> showLoading(if (waitingFirstFrame) "Inicializando…" else "Reconectando…")
                    Player.STATE_READY -> if (!waitingFirstFrame) hideLoading()
                    Player.STATE_ENDED -> showLoading("Finalizado")
                    Player.STATE_IDLE -> Unit
                }
            }

            override fun onRenderedFirstFrame() {
                waitingFirstFrame = false
                hideLoading()
            }

            override fun onPlayerError(error: PlaybackException) {
                waitingFirstFrame = false
                showLoading("Canal no disponible")
                infoBody.text = "Error de reproducción: ${error.errorCodeName}"
            }
        })
        player = p
        playerView.player = p
        lastPlayed?.let { play(it) }
    }

    private fun play(item: ContentItem) {
        val p = player ?: run {
            initPlayer()
            player ?: return
        }
        lastPlayed = item
        waitingFirstFrame = true
        startupToken = System.currentTimeMillis()
        val token = startupToken
        showLoading("Inicializando…")
        infoTitle.text = item.name
        infoBody.text = "Abriendo stream…"

        p.stop()
        p.clearMediaItems()
        p.setMediaItem(MediaItem.fromUri(item.url))
        p.prepare()
        p.playWhenReady = true

        handler.postDelayed({
            if (token == startupToken && waitingFirstFrame) {
                p.stop()
                waitingFirstFrame = false
                showLoading("Canal no disponible")
                infoBody.text = "No llegó el primer cuadro a tiempo."
            }
        }, 6_000)
    }

    private fun releasePlayer() {
        startupToken = System.currentTimeMillis()
        waitingFirstFrame = false
        playerView.player = null
        player?.release()
        player = null
    }

    private fun showLoading(text: String) {
        loadingText.text = text
        loading.visibility = View.VISIBLE
    }

    private fun hideLoading() {
        loading.visibility = View.GONE
    }

    private fun showSearch() {
        val input = EditText(this).apply {
            hint = "Buscar en la lista actual"
            inputType = InputType.TYPE_CLASS_TEXT
            setTextColor(Color.WHITE)
            setHintTextColor(Color.LTGRAY)
        }
        AlertDialog.Builder(this)
            .setTitle("Buscar")
            .setView(input)
            .setPositiveButton("BUSCAR") { _, _ ->
                val q = input.text.toString().trim().lowercase(Locale.getDefault())
                val filtered = if (q.isBlank()) currentItems else currentItems.filter { it.name.lowercase(Locale.getDefault()).contains(q) }
                itemAdapter.submit(filtered)
                countText.text = "${filtered.size} resultados"
                itemsView.post { itemsView.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() }
            }
            .setNegativeButton("CANCELAR", null)
            .show()
    }

    private fun showSettings(config: SourceConfig) {
        val source = if (config.mode == SourceMode.M3U) "Lista M3U" else "Xtream"
        AlertDialog.Builder(this)
            .setTitle("Ajustes · $source")
            .setMessage("Reproductor: Media3 / ExoPlayer\nRender: SurfaceView\nBuffer: 5–15 s\nInicio objetivo: 2,5 s\nTimeout de canal: 6 s")
            .setPositiveButton("CAMBIAR LISTA") { _, _ ->
                Prefs.clear(this)
                goLogin()
            }
            .setNegativeButton("CERRAR", null)
            .show()
    }

    private fun showCatalogError(message: String?) {
        infoTitle.text = "No se pudo cargar"
        infoBody.text = message ?: "Error de red o formato."
    }

    private fun updateClock() {
        clock.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        handler.postDelayed({ updateClock() }, 30_000)
    }

    private fun goLogin() {
        startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
        finish()
    }

    private fun immersive() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) {
            player?.let { it.playWhenReady = !it.playWhenReady }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacksAndMessages(null)
        io.shutdownNow()
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private inner class TvListAdapter<T>(
        private val label: (T) -> String,
        private val onClick: (T) -> Unit,
        private val onFocus: (T) -> Unit
    ) : RecyclerView.Adapter<TvListAdapter<T>.Holder>() {
        private var data: List<T> = emptyList()

        fun submit(newData: List<T>) {
            data = newData
            notifyDataSetChanged()
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
            val tv = TextView(parent.context).apply {
                textSize = 17f
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(8), dp(12), dp(8))
                setTextColor(Color.WHITE)
                setBackgroundColor(Color.rgb(38, 53, 76))
                isFocusable = true
                isFocusableInTouchMode = true
                maxLines = 2
                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(64)).apply {
                    bottomMargin = dp(7)
                }
            }
            return Holder(tv)
        }

        override fun onBindViewHolder(holder: Holder, position: Int) {
            val item = data[position]
            holder.text.text = label(item)
            holder.text.setOnClickListener { onClick(item) }
            holder.text.setOnFocusChangeListener { v, focused ->
                val t = v as TextView
                t.setBackgroundColor(if (focused) Color.rgb(241, 214, 44) else Color.rgb(38, 53, 76))
                t.setTextColor(if (focused) Color.BLACK else Color.WHITE)
                if (focused) onFocus(item)
            }
        }

        override fun getItemCount(): Int = data.size

        inner class Holder(val text: TextView) : RecyclerView.ViewHolder(text)
    }
}
