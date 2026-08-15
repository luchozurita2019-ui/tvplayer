package com.tvfull.pro

import android.app.ActivityManager
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
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
    companion object {
        private val BG = Color.rgb(7, 11, 20)
        private val TOP = Color.rgb(10, 16, 28)
        private val PANEL = Color.rgb(14, 22, 36)
        private val PANEL_ALT = Color.rgb(18, 28, 45)
        private val CARD = Color.rgb(24, 36, 56)
        private val CARD_SELECTED = Color.rgb(54, 18, 26)
        private val BORDER = Color.rgb(42, 58, 82)
        private val TEXT = Color.rgb(239, 244, 250)
        private val MUTED = Color.rgb(153, 166, 184)
        private val ACCENT = Color.rgb(229, 9, 20)
        private val ACCENT_SOFT = Color.rgb(114, 16, 26)
    }

    private lateinit var repository: CatalogRepository
    private lateinit var sourceConfig: SourceConfig
    private val io = Executors.newFixedThreadPool(3)
    private val handler = Handler(Looper.getMainLooper())

    private lateinit var root: LinearLayout
    private lateinit var topBar: View
    private lateinit var body: LinearLayout
    private lateinit var navRail: LinearLayout
    private lateinit var categoriesPanel: LinearLayout
    private lateinit var itemsPanel: LinearLayout
    private lateinit var rightPanel: LinearLayout
    private lateinit var videoFrame: FrameLayout
    private lateinit var infoCard: LinearLayout

    private lateinit var categoriesView: RecyclerView
    private lateinit var itemsView: RecyclerView
    private lateinit var categoryAdapter: TvListAdapter<TvCategory>
    private lateinit var itemAdapter: TvListAdapter<ContentItem>
    private lateinit var playerView: PlayerView
    private lateinit var loading: View
    private lateinit var loadingText: TextView
    private lateinit var infoTitle: TextView
    private lateinit var infoBody: TextView
    private lateinit var infoHint: TextView
    private lateinit var sectionTitle: TextView
    private lateinit var categoriesTitle: TextView
    private lateinit var itemsTitle: TextView
    private lateinit var clock: TextView
    private lateinit var countText: TextView
    private lateinit var sourceBadge: TextView
    private lateinit var fullscreenButton: Button
    private lateinit var videoHud: LinearLayout
    private lateinit var videoTitle: TextView
    private lateinit var videoMeta: TextView

    private val sectionButtons = linkedMapOf<ContentSection, Button>()

    private var player: ExoPlayer? = null
    private var currentSection = ContentSection.LIVE
    private var currentItems: List<ContentItem> = emptyList()
    private var lastPlayed: ContentItem? = null
    private var waitingFirstFrame = false
    private var startupToken = 0L
    private var isFullscreen = false

    private val hideHud = Runnable {
        if (!waitingFirstFrame) videoHud.visibility = View.GONE
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        immersive()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val config = Prefs.load(this)
        if (config == null) {
            goLogin()
            return
        }
        sourceConfig = config
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
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(BG)
        }

        topBar = buildTopBar(config)
        root.addView(topBar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(68)))

        body = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }
        root.addView(body, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        navRail = buildNavRail(config)
        body.addView(navRail, LinearLayout.LayoutParams(dp(154), ViewGroup.LayoutParams.MATCH_PARENT).apply {
            marginEnd = dp(10)
        })

        categoriesPanel = buildListPanel("CATEGORÍAS", true)
        body.addView(categoriesPanel, LinearLayout.LayoutParams(dp(250), ViewGroup.LayoutParams.MATCH_PARENT).apply {
            marginEnd = dp(10)
        })

        itemsPanel = buildListPanel("CANALES", false)
        body.addView(itemsPanel, LinearLayout.LayoutParams(dp(330), ViewGroup.LayoutParams.MATCH_PARENT).apply {
            marginEnd = dp(10)
        })

        rightPanel = buildRightPanel()
        body.addView(rightPanel, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))

        categoryAdapter = TvListAdapter(
            heightDp = 58,
            label = { c -> if (c.count > 0) "${c.name}   ·   ${c.count}" else c.name },
            onClick = { category -> loadItems(category) },
            onFocus = { c ->
                infoTitle.text = c.name
                infoBody.text = if (c.count > 0) "${c.count} elementos disponibles" else "Abrir categoría"
            }
        )
        categoriesView.adapter = categoryAdapter

        itemAdapter = TvListAdapter(
            heightDp = 62,
            label = { i -> i.name },
            onClick = { item -> openItem(item) },
            onFocus = { item -> showItemInfo(item) }
        )
        itemsView.adapter = itemAdapter

        return root
    }

    private fun buildTopBar(config: SourceConfig): View {
        val top = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), 0, dp(18), 0)
            background = roundedBg(TOP, 0f)
        }

        val brand = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        brand.addView(TextView(this).apply {
            text = "TV FULL"
            textSize = 25f
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            letterSpacing = 0.04f
        })
        brand.addView(TextView(this).apply {
            text = "PRO"
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBg(ACCENT, 7f)
        }, LinearLayout.LayoutParams(dp(48), dp(27)).apply { marginStart = dp(9) })
        top.addView(brand, LinearLayout.LayoutParams(dp(245), ViewGroup.LayoutParams.MATCH_PARENT))

        sectionTitle = TextView(this).apply {
            text = "TV EN VIVO"
            textSize = 20f
            setTextColor(TEXT)
            gravity = Gravity.CENTER_VERTICAL
            setTypeface(typeface, Typeface.BOLD)
        }
        top.addView(sectionTitle, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))

        val service = RemotePrefs.serviceName(this).trim()
        sourceBadge = TextView(this).apply {
            text = when {
                service.isNotBlank() -> service.uppercase(Locale.getDefault())
                config.mode == SourceMode.M3U -> "M3U"
                else -> "XTREAM"
            }
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(TEXT)
            maxLines = 1
            background = roundedBg(PANEL_ALT, 9f, BORDER, 1)
        }
        top.addView(sourceBadge, LinearLayout.LayoutParams(dp(170), dp(34)).apply { marginEnd = dp(14) })

        clock = TextView(this).apply {
            textSize = 18f
            setTextColor(TEXT)
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
        }
        top.addView(clock, LinearLayout.LayoutParams(dp(82), ViewGroup.LayoutParams.MATCH_PARENT))
        return top
    }

    private fun buildNavRail(config: SourceConfig): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(10), dp(8), dp(10))
            background = roundedBg(PANEL, 14f, BORDER, 1)

            addView(TextView(this@MainActivity).apply {
                text = "MENÚ"
                textSize = 11f
                setTextColor(MUTED)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(10), 0, 0, 0)
                letterSpacing = 0.12f
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(38)))

            addView(sectionButton(ContentSection.LIVE, "TV EN VIVO"))
            addView(sectionButton(ContentSection.MOVIES, "PELÍCULAS"))
            addView(sectionButton(ContentSection.SERIES, "SERIES"))
            addView(navButton("BUSCAR") { showSearch() })
            addView(navButton("AJUSTES") { showSettings(config) })

            addView(View(this@MainActivity), LinearLayout.LayoutParams(1, 0, 1f))

            addView(TextView(this@MainActivity).apply {
                val creds = RemotePrefs.loadCredentials(this@MainActivity)
                text = if (creds != null) "DISPOSITIVO\n${creds.code}" else "TV FULL PRO"
                textSize = 10f
                setTextColor(MUTED)
                gravity = Gravity.CENTER
                maxLines = 2
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(50)))

            addView(navButton("SALIR") { finishAffinity() })
        }
    }

    private fun buildListPanel(title: String, categories: Boolean): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(10), dp(10), dp(10))
            background = roundedBg(PANEL, 14f, BORDER, 1)
        }

        val header = TextView(this).apply {
            text = title
            textSize = 12f
            setTextColor(MUTED)
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), 0, 0, 0)
            letterSpacing = 0.10f
        }
        if (categories) categoriesTitle = header else itemsTitle = header
        panel.addView(header, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(42)))

        val recycler = RecyclerView(this).apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(dp(2), dp(2), dp(2), dp(2))
            clipToPadding = false
            clipChildren = false
            isVerticalScrollBarEnabled = false
        }
        if (categories) categoriesView = recycler else itemsView = recycler
        panel.addView(recycler, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        if (!categories) {
            countText = TextView(this).apply {
                text = "0 elementos"
                textSize = 11f
                setTextColor(MUTED)
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(6), 0, 0, 0)
            }
            panel.addView(countText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(34)))
        }
        return panel
    }

    private fun buildRightPanel(): LinearLayout {
        val right = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        videoFrame = FrameLayout(this).apply {
            setPadding(dp(2), dp(2), dp(2), dp(2))
            background = roundedBg(Color.BLACK, 16f, BORDER, 1)
        }

        playerView = PlayerView(this).apply {
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(Color.BLACK)
            setBackgroundColor(Color.BLACK)
            isFocusable = false
        }
        videoFrame.addView(playerView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val loadingWrap = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.argb(115, 0, 0, 0))
        }
        loading = loadingWrap
        loadingWrap.addView(ProgressBar(this).apply { isIndeterminate = true }, LinearLayout.LayoutParams(dp(52), dp(52)))
        loadingText = TextView(this).apply {
            text = "Seleccioná un canal"
            textSize = 15f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
        }
        loadingWrap.addView(loadingText, LinearLayout.LayoutParams(dp(360), dp(46)).apply { topMargin = dp(8) })
        videoFrame.addView(loadingWrap, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        videoHud = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), dp(8), dp(18), dp(8))
            background = roundedBg(Color.argb(190, 4, 7, 12), 0f)
            visibility = View.GONE
        }
        videoTitle = TextView(this).apply {
            textSize = 18f
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            maxLines = 1
        }
        videoMeta = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.rgb(205, 213, 224))
            maxLines = 1
        }
        videoHud.addView(videoTitle)
        videoHud.addView(videoMeta)
        videoFrame.addView(videoHud, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(62), Gravity.BOTTOM))

        fullscreenButton = Button(this).apply {
            text = "PANTALLA COMPLETA"
            textSize = 11f
            isAllCaps = false
            isFocusable = true
            setTextColor(Color.WHITE)
            background = roundedBg(Color.argb(220, 18, 28, 45), 9f, BORDER, 1)
            setOnClickListener {
                if (lastPlayed == null) {
                    infoBody.text = "Seleccioná primero un canal o contenido."
                } else {
                    enterFullscreen()
                }
            }
            setOnFocusChangeListener { v, focused ->
                val b = v as Button
                b.background = roundedBg(if (focused) ACCENT else Color.argb(220, 18, 28, 45), 9f, if (focused) ACCENT else BORDER, 1)
                b.animate().scaleX(if (focused) 1.04f else 1f).scaleY(if (focused) 1.04f else 1f).setDuration(90).start()
            }
        }
        videoFrame.addView(fullscreenButton, FrameLayout.LayoutParams(dp(174), dp(40), Gravity.TOP or Gravity.END).apply {
            topMargin = dp(12)
            marginEnd = dp(12)
        })

        right.addView(videoFrame, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.64f))

        infoCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(16), dp(20), dp(14))
            background = roundedBg(PANEL_ALT, 14f, BORDER, 1)
        }
        infoTitle = TextView(this).apply {
            text = "TV FULL PRO"
            textSize = 20f
            setTextColor(TEXT)
            setTypeface(typeface, Typeface.BOLD)
            maxLines = 1
        }
        infoBody = TextView(this).apply {
            text = "Elegí una categoría y un canal."
            textSize = 14f
            setTextColor(MUTED)
            setPadding(0, dp(8), 0, 0)
            maxLines = 5
        }
        infoHint = TextView(this).apply {
            text = "OK: reproducir   •   OK otra vez: pantalla completa   •   BACK: volver"
            textSize = 11f
            setTextColor(Color.rgb(118, 134, 154))
            gravity = Gravity.BOTTOM
            setPadding(0, dp(8), 0, 0)
        }
        infoCard.addView(infoTitle)
        infoCard.addView(infoBody, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        infoCard.addView(infoHint)
        right.addView(infoCard, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.36f).apply { topMargin = dp(10) })
        return right
    }

    private fun sectionButton(section: ContentSection, label: String): Button {
        val button = navButton(label) { loadSection(section) }
        button.tag = section
        sectionButtons[section] = button
        return button
    }

    private fun navButton(textValue: String, action: () -> Unit): Button {
        return Button(this).apply {
            text = textValue
            textSize = 12f
            isAllCaps = false
            isFocusable = true
            gravity = Gravity.CENTER_VERTICAL or Gravity.START
            setPadding(dp(14), 0, dp(8), 0)
            setTextColor(TEXT)
            background = roundedBg(CARD, 10f)
            setOnClickListener { action() }
            setOnFocusChangeListener { v, focused ->
                val b = v as Button
                val selected = b.tag is ContentSection && b.tag == currentSection
                b.background = when {
                    focused -> roundedBg(ACCENT, 10f)
                    selected -> roundedBg(CARD_SELECTED, 10f, ACCENT_SOFT, 1)
                    else -> roundedBg(CARD, 10f)
                }
                b.setTextColor(Color.WHITE)
                b.animate().scaleX(if (focused) 1.035f else 1f).scaleY(if (focused) 1.035f else 1f).setDuration(90).start()
                b.translationZ = if (focused) dp(4).toFloat() else 0f
            }
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(54)).apply { bottomMargin = dp(7) }
        }
    }

    private fun refreshSectionButtons() {
        sectionButtons.forEach { (section, button) ->
            if (!button.hasFocus()) {
                button.background = if (section == currentSection) {
                    roundedBg(CARD_SELECTED, 10f, ACCENT_SOFT, 1)
                } else {
                    roundedBg(CARD, 10f)
                }
            }
        }
    }

    private fun loadSection(section: ContentSection) {
        currentSection = section
        refreshSectionButtons()
        sectionTitle.text = when (section) {
            ContentSection.LIVE -> "TV EN VIVO"
            ContentSection.MOVIES -> "PELÍCULAS"
            ContentSection.SERIES -> "SERIES"
        }
        itemsTitle.text = when (section) {
            ContentSection.LIVE -> "CANALES"
            ContentSection.MOVIES -> "PELÍCULAS"
            ContentSection.SERIES -> "CONTENIDO"
        }
        categoryAdapter.submit(emptyList())
        itemAdapter.submit(emptyList())
        currentItems = emptyList()
        countText.text = "Cargando…"
        infoTitle.text = sectionTitle.text
        infoBody.text = "Cargando categorías…"
        io.execute {
            val result = runCatching { repository.loadCategories(section) }
            runOnUiThread {
                result.onSuccess { cats ->
                    categoryAdapter.submit(cats)
                    infoBody.text = "${cats.size} categorías disponibles"
                    cats.firstOrNull()?.let { loadItems(it) }
                    categoriesView.post {
                        categoriesView.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus()
                    }
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
                    infoBody.text = if (list.isEmpty()) "No hay contenido en esta categoría." else "${list.size} elementos disponibles"
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
                        itemsTitle.text = "EPISODIOS"
                        countText.text = "${eps.size} episodios"
                        infoBody.text = "${eps.size} episodios disponibles"
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

        val sameItem = lastPlayed?.url == item.url && lastPlayed?.url?.isNotBlank() == true
        if (sameItem && !isFullscreen) {
            enterFullscreen()
        } else {
            play(item)
        }
    }

    private fun showItemInfo(item: ContentItem) {
        infoTitle.text = item.name
        infoBody.text = when (item.section) {
            ContentSection.LIVE -> "${item.categoryId.ifBlank { "TV en vivo" }}\nOK para reproducir · OK nuevamente para pantalla completa"
            ContentSection.MOVIES -> "Película · ${item.categoryId}\nOK para reproducir"
            ContentSection.SERIES -> if (item.url.isBlank()) "Serie · OK para ver episodios" else item.extra.ifBlank { "Episodio · OK para reproducir" }
        }
        if (item.section == ContentSection.LIVE) loadEpg(item)
    }

    private fun loadEpg(item: ContentItem) {
        io.execute {
            val epg = repository.loadShortEpg(item.id)
            if (epg.isEmpty()) return@execute
            val text = epg.take(2).joinToString("\n\n") { e ->
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
            .setUserAgent("TV-FULL-PRO/1.2 AndroidTV")
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
                    Player.STATE_BUFFERING -> showLoading(if (waitingFirstFrame) "ABRIENDO CANAL…" else "RECONECTANDO…")
                    Player.STATE_READY -> if (!waitingFirstFrame) hideLoading()
                    Player.STATE_ENDED -> showLoading("FINALIZADO")
                    Player.STATE_IDLE -> Unit
                }
            }

            override fun onRenderedFirstFrame() {
                waitingFirstFrame = false
                hideLoading()
                showVideoHud()
            }

            override fun onPlayerError(error: PlaybackException) {
                waitingFirstFrame = false
                showLoading("CANAL NO DISPONIBLE")
                infoBody.text = "No se pudo reproducir este contenido."
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
        showLoading("ABRIENDO CANAL…")
        infoTitle.text = item.name
        infoBody.text = "Conectando al stream…"
        videoTitle.text = item.name
        videoMeta.text = sectionLabel(item.section)

        p.stop()
        p.clearMediaItems()
        p.setMediaItem(MediaItem.fromUri(item.url))
        p.prepare()
        p.playWhenReady = true

        handler.postDelayed({
            if (token == startupToken && waitingFirstFrame) {
                p.stop()
                waitingFirstFrame = false
                showLoading("CANAL NO DISPONIBLE")
                infoBody.text = "El canal no respondió a tiempo."
            }
        }, 6_000)
    }

    private fun releasePlayer() {
        startupToken = System.currentTimeMillis()
        waitingFirstFrame = false
        handler.removeCallbacks(hideHud)
        if (::playerView.isInitialized) playerView.player = null
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

    private fun showVideoHud() {
        val item = lastPlayed ?: return
        handler.removeCallbacks(hideHud)
        videoTitle.text = item.name
        videoMeta.text = if (isFullscreen && item.section == ContentSection.LIVE) {
            "TV EN VIVO   ·   ▲▼ cambiar canal   ·   OK pausar/reanudar   ·   BACK volver"
        } else {
            "${sectionLabel(item.section)}   ·   Pantalla completa disponible"
        }
        videoHud.visibility = View.VISIBLE
        handler.postDelayed(hideHud, 3_500)
    }

    private fun enterFullscreen() {
        if (isFullscreen || lastPlayed == null) return
        isFullscreen = true
        topBar.visibility = View.GONE
        navRail.visibility = View.GONE
        categoriesPanel.visibility = View.GONE
        itemsPanel.visibility = View.GONE
        infoCard.visibility = View.GONE
        fullscreenButton.visibility = View.GONE
        body.setPadding(0, 0, 0, 0)
        rightPanel.setPadding(0, 0, 0, 0)
        videoFrame.setPadding(0, 0, 0, 0)
        videoFrame.background = roundedBg(Color.BLACK, 0f)
        immersive()
        showVideoHud()
    }

    private fun exitFullscreen() {
        if (!isFullscreen) return
        isFullscreen = false
        topBar.visibility = View.VISIBLE
        navRail.visibility = View.VISIBLE
        categoriesPanel.visibility = View.VISIBLE
        itemsPanel.visibility = View.VISIBLE
        infoCard.visibility = View.VISIBLE
        fullscreenButton.visibility = View.VISIBLE
        body.setPadding(dp(12), dp(12), dp(12), dp(12))
        videoFrame.setPadding(dp(2), dp(2), dp(2), dp(2))
        videoFrame.background = roundedBg(Color.BLACK, 16f, BORDER, 1)
        immersive()
        itemsView.post {
            val position = currentItems.indexOfFirst { it.url == lastPlayed?.url }.coerceAtLeast(0)
            itemsView.scrollToPosition(position)
            itemsView.findViewHolderForAdapterPosition(position)?.itemView?.requestFocus()
        }
    }

    private fun zap(delta: Int) {
        if (currentSection != ContentSection.LIVE || currentItems.isEmpty()) {
            showVideoHud()
            return
        }
        val currentIndex = currentItems.indexOfFirst { it.url == lastPlayed?.url }
        if (currentIndex < 0) return
        var next = currentIndex
        repeat(currentItems.size) {
            next = (next + delta + currentItems.size) % currentItems.size
            val candidate = currentItems[next]
            if (candidate.url.isNotBlank()) {
                play(candidate)
                showVideoHud()
                return
            }
        }
    }

    private fun showSearch() {
        val input = EditText(this).apply {
            hint = "Buscar en la lista actual"
            inputType = InputType.TYPE_CLASS_TEXT
            setTextColor(Color.WHITE)
            setHintTextColor(Color.LTGRAY)
            setSingleLine(true)
        }
        AlertDialog.Builder(this)
            .setTitle("Buscar")
            .setView(input)
            .setPositiveButton("BUSCAR") { _, _ ->
                val q = input.text.toString().trim().lowercase(Locale.getDefault())
                val filtered = if (q.isBlank()) currentItems else currentItems.filter {
                    it.name.lowercase(Locale.getDefault()).contains(q)
                }
                itemAdapter.submit(filtered)
                countText.text = "${filtered.size} resultados"
                itemsView.post { itemsView.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() }
            }
            .setNegativeButton("CANCELAR", null)
            .show()
    }

    private fun showSettings(config: SourceConfig) {
        val source = if (config.mode == SourceMode.M3U) "Lista M3U" else "Xtream"
        val credentials = RemotePrefs.loadCredentials(this)
        val service = RemotePrefs.serviceName(this).ifBlank { "Sin nombre" }
        val remote = if (credentials != null) {
            "Código: ${credentials.code}\nServicio: $service"
        } else {
            "Activación remota no disponible"
        }

        AlertDialog.Builder(this)
            .setTitle("TV FULL PRO · Ajustes")
            .setMessage("Fuente: $source\n$remote\n\nReproductor: Media3 / ExoPlayer\nRender: SurfaceView\nPantalla completa: habilitada")
            .setPositiveButton("SINCRONIZAR PANEL") { _, _ ->
                startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
                finish()
            }
            .setNeutralButton("CONFIG. MANUAL") { _, _ ->
                RemotePrefs.disableRemote(this)
                Prefs.clear(this)
                goLogin()
            }
            .setNegativeButton("CERRAR", null)
            .show()
    }

    private fun showCatalogError(message: String?) {
        infoTitle.text = "No se pudo cargar"
        infoBody.text = message ?: "Error de red o formato."
        countText.text = "Error"
    }

    private fun updateClock() {
        if (::clock.isInitialized) {
            clock.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        }
        handler.postDelayed({ updateClock() }, 30_000)
    }

    private fun goLogin() {
        startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
        finish()
    }

    private fun sectionLabel(section: ContentSection): String = when (section) {
        ContentSection.LIVE -> "TV EN VIVO"
        ContentSection.MOVIES -> "PELÍCULA"
        ContentSection.SERIES -> "SERIE"
    }

    private fun roundedBg(fill: Int, radiusDp: Float, strokeColor: Int? = null, strokeWidthDp: Int = 0): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dpF(radiusDp)
            if (strokeColor != null && strokeWidthDp > 0) setStroke(dp(strokeWidthDp), strokeColor)
        }
    }

    private fun immersive() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return super.dispatchKeyEvent(event)

        if (isFullscreen) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK -> {
                    exitFullscreen()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_UP,
                KeyEvent.KEYCODE_CHANNEL_UP -> {
                    zap(-1)
                    return true
                }
                KeyEvent.KEYCODE_DPAD_DOWN,
                KeyEvent.KEYCODE_CHANNEL_DOWN -> {
                    zap(1)
                    return true
                }
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                    player?.let { it.playWhenReady = !it.playWhenReady }
                    showVideoHud()
                    return true
                }
                KeyEvent.KEYCODE_MENU,
                KeyEvent.KEYCODE_INFO -> {
                    showVideoHud()
                    return true
                }
            }
        }

        if (event.keyCode == KeyEvent.KEYCODE_MENU && lastPlayed != null) {
            enterFullscreen()
            return true
        }

        if (event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) {
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
    private fun dpF(v: Float): Float = v * resources.displayMetrics.density

    private inner class TvListAdapter<T>(
        private val heightDp: Int,
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
                textSize = 15f
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(14), dp(7), dp(12), dp(7))
                setTextColor(TEXT)
                background = roundedBg(CARD, 10f)
                isFocusable = true
                isFocusableInTouchMode = true
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(heightDp)).apply {
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
                t.background = if (focused) {
                    roundedBg(ACCENT, 10f, Color.rgb(255, 76, 84), 1)
                } else {
                    roundedBg(CARD, 10f)
                }
                t.setTextColor(Color.WHITE)
                t.animate().scaleX(if (focused) 1.025f else 1f).scaleY(if (focused) 1.025f else 1f).setDuration(90).start()
                t.translationZ = if (focused) dp(5).toFloat() else 0f
                if (focused) onFocus(item)
            }
        }

        override fun getItemCount(): Int = data.size

        inner class Holder(val text: TextView) : RecyclerView.ViewHolder(text)
    }
}
