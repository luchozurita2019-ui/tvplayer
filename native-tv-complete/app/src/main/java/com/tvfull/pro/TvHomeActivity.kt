package com.tvfull.pro

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
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
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.SeekBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

@UnstableApi
class TvHomeActivity : AppCompatActivity() {
    companion object {
        private const val LIVE_START_TIMEOUT = 12_000L
        private const val LIVE_STALL_NOTICE = 1_500L
        private const val LIVE_STALL_REOPEN = 45_000L
        private const val HUD_HIDE = 4_000L
        private const val SEEK_STEP = 10_000L
        private const val MAX_RECONNECTS = 4

        private val BG = Color.rgb(6, 10, 18)
        private val TOP = Color.rgb(10, 16, 27)
        private val PANEL = Color.rgb(13, 21, 34)
        private val PANEL_ALT = Color.rgb(18, 28, 44)
        private val CARD = Color.rgb(25, 37, 56)
        private val BORDER = Color.rgb(48, 65, 91)
        private val TEXT = Color.rgb(241, 245, 250)
        private val MUTED = Color.rgb(154, 167, 187)
        private val ACCENT = Color.rgb(229, 9, 20)
        private val LIVE = Color.rgb(220, 23, 38)
        private val WARNING = Color.rgb(244, 178, 49)
    }

    private enum class BrowseLevel { CATEGORIES, ITEMS, EPISODES, MOVIE_DETAILS }

    private data class PlaybackDiagnostics(
        var bufferingCount: Int = 0,
        var bufferingStarted: Long = 0,
        var bufferingMs: Long = 0,
        var reconnects: Int = 0,
        var width: Int = 0,
        var height: Int = 0,
        var error: String = ""
    )

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(UiPreferences.wrap(newBase))
    }

    private lateinit var sourceConfig: SourceConfig
    private lateinit var repository: CatalogRepository
    private lateinit var imageLoader: LiteImageLoader
    private val io = Executors.newFixedThreadPool(3)
    private val handler = Handler(Looper.getMainLooper())

    private lateinit var root: LinearLayout
    private lateinit var topBar: LinearLayout
    private lateinit var body: LinearLayout
    private lateinit var navRail: LinearLayout
    private lateinit var browsePanel: LinearLayout
    private lateinit var browseTitle: TextView
    private lateinit var browseSubtitle: TextView
    private lateinit var recycler: RecyclerView
    private lateinit var rightPanel: LinearLayout
    private lateinit var videoFrame: FrameLayout
    private lateinit var playerView: PlayerView
    private lateinit var loading: LinearLayout
    private lateinit var loadingText: TextView
    private lateinit var infoTitle: TextView
    private lateinit var infoBody: TextView
    private lateinit var detailPanel: LinearLayout
    private lateinit var sectionTitle: TextView
    private lateinit var clock: TextView

    private lateinit var hud: LinearLayout
    private lateinit var hudLogo: ImageView
    private lateinit var hudBadge: TextView
    private lateinit var hudTitle: TextView
    private lateinit var hudSubtitle: TextView
    private lateinit var hudHint: TextView
    private lateinit var liveProgressRow: LinearLayout
    private lateinit var liveStart: TextView
    private lateinit var liveEnd: TextView
    private lateinit var liveProgress: SeekBar
    private lateinit var vodProgressRow: LinearLayout
    private lateinit var vodCurrent: TextView
    private lateinit var vodDuration: TextView
    private lateinit var vodProgress: SeekBar

    private lateinit var channelOverlay: LinearLayout
    private lateinit var channelOverlayTitle: TextView
    private lateinit var channelOverlayRecycler: RecyclerView

    private val sectionButtons = linkedMapOf<ContentSection, Button>()
    private var player: ExoPlayer? = null
    private var currentSection = ContentSection.LIVE
    private var browseLevel = BrowseLevel.CATEGORIES
    private var selectedCategory: TvCategory? = null
    private var currentCategories: List<TvCategory> = emptyList()
    private var currentItems: List<ContentItem> = emptyList()
    private var seriesGridItems: List<ContentItem> = emptyList()
    private var currentMovie: ContentItem? = null
    private var currentMovieDetails: MovieDetails? = null
    private var lastPlayed: ContentItem? = null
    private var currentEpg: EpgEntry? = null
    private var isFullscreen = false
    private var channelOverlayVisible = false
    private var waitingFirstFrame = false
    private var reconnectAttempts = 0
    private var startupToken = 0L
    private var stallToken = 0L
    private var reconnectToken = 0L
    private var diagnostics = PlaybackDiagnostics()

    private val hideHud = Runnable {
        if (::hud.isInitialized && !channelOverlayVisible && !waitingFirstFrame) hud.visibility = View.GONE
    }

    private val progressTick = object : Runnable {
        override fun run() {
            updateVodProgress()
            handler.postDelayed(this, 500L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        immersive()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val config = Prefs.load(this)
        if (config == null) {
            startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
            finish()
            return
        }
        sourceConfig = config
        repository = CatalogRepository(config)
        imageLoader = LiteImageLoader(this)
        setContentView(buildUi())
        updateClock()
        showCategories(ContentSection.LIVE)
        handler.post(progressTick)
    }

    override fun onStart() {
        super.onStart()
        if (::playerView.isInitialized && player == null) initPlayer()
    }

    override fun onStop() {
        super.onStop()
        releasePlayer()
    }

    private fun buildUi(): View {
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(BG)
        }
        topBar = buildTopBar()
        root.addView(topBar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(64)))

        body = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(12), dp(10), dp(12), dp(12))
        }
        root.addView(body, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        navRail = buildNavRail()
        body.addView(navRail, LinearLayout.LayoutParams(dp(154), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(10) })

        browsePanel = buildBrowsePanel()
        body.addView(browsePanel, LinearLayout.LayoutParams(dp(400), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(10) })

        rightPanel = buildRightPanel()
        body.addView(rightPanel, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))

        detailPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(dp(18), dp(10), dp(18), dp(12))
        }
        body.addView(detailPanel, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
        return root
    }

    private fun buildTopBar(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), 0, dp(18), 0)
            setBackgroundColor(TOP)

            addView(TextView(this@TvHomeActivity).apply {
                text = "TV FULL"
                textSize = 24f
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
            }, LinearLayout.LayoutParams(dp(128), ViewGroup.LayoutParams.MATCH_PARENT).apply { gravity = Gravity.CENTER_VERTICAL })

            addView(TextView(this@TvHomeActivity).apply {
                text = "PRO"
                textSize = 11f
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                background = rounded(ACCENT, 7f)
            }, LinearLayout.LayoutParams(dp(46), dp(26)).apply { marginEnd = dp(20) })

            sectionTitle = TextView(this@TvHomeActivity).apply {
                text = "TV EN VIVO"
                textSize = 19f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER_VERTICAL
            }
            addView(sectionTitle, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))

            addView(TextView(this@TvHomeActivity).apply {
                text = RemotePrefs.serviceName(this@TvHomeActivity).ifBlank { if (sourceConfig.mode == SourceMode.XTREAM) "XTREAM" else "M3U" }
                textSize = 12f
                setTextColor(MUTED)
                gravity = Gravity.CENTER
                background = rounded(PANEL_ALT, 8f, BORDER, 1)
            }, LinearLayout.LayoutParams(dp(170), dp(32)).apply { marginEnd = dp(14) })

            clock = TextView(this@TvHomeActivity).apply {
                textSize = 16f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER
            }
            addView(clock, LinearLayout.LayoutParams(dp(72), ViewGroup.LayoutParams.MATCH_PARENT))
        }
    }

    private fun buildNavRail(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = rounded(PANEL, 12f, BORDER, 1)
            addView(sectionButton(ContentSection.LIVE, "TV EN VIVO"))
            addView(sectionButton(ContentSection.MOVIES, "PELÍCULAS"))
            addView(sectionButton(ContentSection.SERIES, "SERIES"))
            addView(sectionButton(ContentSection.RADIO, "RADIO"))
            addView(navButton("BUSCAR") { showSearch() })
            addView(View(this@TvHomeActivity), LinearLayout.LayoutParams(1, 0, 1f))
            addView(navButton("MIS LISTAS") { openPlaylists() })
            addView(navButton("AJUSTES") { showSettings() })
        }
    }

    private fun buildBrowsePanel(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = rounded(PANEL, 12f, BORDER, 1)

            browseTitle = TextView(this@TvHomeActivity).apply {
                text = "CATEGORÍAS"
                textSize = 15f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER_VERTICAL
                maxLines = 1
            }
            addView(browseTitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(32)))

            browseSubtitle = TextView(this@TvHomeActivity).apply {
                text = "Elegí una categoría"
                textSize = 11f
                setTextColor(MUTED)
                gravity = Gravity.CENTER_VERTICAL
                maxLines = 1
            }
            addView(browseSubtitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(27)))

            recycler = RecyclerView(this@TvHomeActivity).apply {
                setBackgroundColor(Color.TRANSPARENT)
                setPadding(dp(1), dp(4), dp(1), dp(2))
                clipToPadding = false
                isVerticalScrollBarEnabled = false
                setItemViewCacheSize(2)
            }
            addView(recycler, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        }
    }

    private fun buildRightPanel(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL

            videoFrame = FrameLayout(this@TvHomeActivity).apply {
                background = rounded(Color.BLACK, 14f, BORDER, 1)
                setPadding(dp(2), dp(2), dp(2), dp(2))
            }
            playerView = PlayerView(this@TvHomeActivity).apply {
                useController = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                setShutterBackgroundColor(Color.BLACK)
                setBackgroundColor(Color.BLACK)
                isFocusable = false
            }
            videoFrame.addView(playerView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

            loading = LinearLayout(this@TvHomeActivity).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setBackgroundColor(Color.argb(110, 0, 0, 0))
                addView(ProgressBar(this@TvHomeActivity).apply { isIndeterminate = true }, LinearLayout.LayoutParams(dp(46), dp(46)))
                loadingText = TextView(this@TvHomeActivity).apply {
                    text = "Seleccioná un canal"
                    textSize = 14f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                    setTypeface(typeface, Typeface.BOLD)
                    setPadding(0, dp(8), 0, 0)
                }
                addView(loadingText, LinearLayout.LayoutParams(dp(390), dp(46)))
            }
            videoFrame.addView(loading, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

            hud = buildHud()
            videoFrame.addView(hud, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(126), Gravity.BOTTOM))

            channelOverlay = buildChannelOverlay()
            videoFrame.addView(channelOverlay, FrameLayout.LayoutParams(dp(370), ViewGroup.LayoutParams.MATCH_PARENT, Gravity.START))

            addView(videoFrame, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.70f))

            val info = LinearLayout(this@TvHomeActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(18), dp(14), dp(18), dp(12))
                background = rounded(PANEL_ALT, 12f, BORDER, 1)
            }
            infoTitle = TextView(this@TvHomeActivity).apply {
                text = "TV FULL PRO"
                textSize = 19f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 1
            }
            infoBody = TextView(this@TvHomeActivity).apply {
                text = "Elegí una categoría y un canal."
                textSize = 13f
                setTextColor(MUTED)
                setPadding(0, dp(6), 0, 0)
                maxLines = 7
            }
            info.addView(infoTitle)
            info.addView(infoBody)
            addView(info, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.30f).apply { topMargin = dp(8) })
        }
    }

    private fun buildHud(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(10), dp(16), dp(8))
            setBackgroundColor(Color.argb(220, 3, 6, 11))
            visibility = View.GONE

            val row = LinearLayout(this@TvHomeActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            hudLogo = ImageView(this@TvHomeActivity).apply { scaleType = ImageView.ScaleType.CENTER_INSIDE }
            row.addView(hudLogo, LinearLayout.LayoutParams(dp(54), dp(44)).apply { marginEnd = dp(10) })

            hudBadge = TextView(this@TvHomeActivity).apply {
                text = "LIVE"
                textSize = 11f
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                background = rounded(LIVE, 7f)
            }
            row.addView(hudBadge, LinearLayout.LayoutParams(dp(60), dp(28)).apply { marginEnd = dp(12) })

            val texts = LinearLayout(this@TvHomeActivity).apply { orientation = LinearLayout.VERTICAL }
            hudTitle = TextView(this@TvHomeActivity).apply {
                textSize = 17f
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 1
            }
            hudSubtitle = TextView(this@TvHomeActivity).apply {
                textSize = 12f
                setTextColor(Color.rgb(205, 213, 225))
                maxLines = 1
            }
            texts.addView(hudTitle)
            texts.addView(hudSubtitle)
            row.addView(texts, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(row, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)))

            liveProgressRow = LinearLayout(this@TvHomeActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            liveStart = timeText()
            liveEnd = timeText()
            liveProgress = SeekBar(this@TvHomeActivity).apply {
                max = 1000
                isEnabled = false
                isFocusable = false
            }
            liveProgressRow.addView(liveStart, LinearLayout.LayoutParams(dp(58), dp(28)))
            liveProgressRow.addView(liveProgress, LinearLayout.LayoutParams(0, dp(28), 1f))
            liveProgressRow.addView(liveEnd, LinearLayout.LayoutParams(dp(58), dp(28)))
            addView(liveProgressRow, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(28)))

            vodProgressRow = LinearLayout(this@TvHomeActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            vodCurrent = timeText()
            vodDuration = timeText()
            vodProgress = SeekBar(this@TvHomeActivity).apply {
                max = 1000
                isEnabled = false
                isFocusable = false
            }
            vodProgressRow.addView(vodCurrent, LinearLayout.LayoutParams(dp(64), dp(28)))
            vodProgressRow.addView(vodProgress, LinearLayout.LayoutParams(0, dp(28), 1f))
            vodProgressRow.addView(vodDuration, LinearLayout.LayoutParams(dp(70), dp(28)))
            addView(vodProgressRow, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(28)))

            hudHint = TextView(this@TvHomeActivity).apply {
                textSize = 10f
                setTextColor(MUTED)
                gravity = Gravity.CENTER_VERTICAL
                maxLines = 1
            }
            addView(hudHint, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(22)))
        }
    }

    private fun buildChannelOverlay(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(14), dp(12), dp(10))
            setBackgroundColor(Color.argb(244, 8, 13, 22))
            visibility = View.GONE
            channelOverlayTitle = TextView(this@TvHomeActivity).apply {
                text = "CANALES"
                textSize = 17f
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
            }
            addView(channelOverlayTitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(32)))
            addView(TextView(this@TvHomeActivity).apply {
                text = "↑ ↓ navegar · OK cambiar · BACK cerrar"
                textSize = 10f
                setTextColor(MUTED)
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(26)))
            channelOverlayRecycler = RecyclerView(this@TvHomeActivity).apply {
                layoutManager = verticalManager()
                setItemViewCacheSize(2)
                isVerticalScrollBarEnabled = false
            }
            addView(channelOverlayRecycler, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        }
    }

    private fun timeText() = TextView(this).apply {
        text = "00:00"
        textSize = 11f
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER
    }

    private fun sectionButton(section: ContentSection, label: String): Button =
        navButton(label) { showCategories(section) }.also { sectionButtons[section] = it }

    private fun navButton(label: String, action: () -> Unit): Button {
        return Button(this).apply {
            text = label
            textSize = 11f
            isAllCaps = false
            isFocusable = true
            setTextColor(TEXT)
            background = rounded(Color.TRANSPARENT, 8f)
            setOnClickListener { action() }
            setOnFocusChangeListener { v, focused ->
                (v as Button).background = rounded(if (focused) ACCENT else Color.TRANSPARENT, 8f)
            }
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(43)).apply { bottomMargin = dp(3) }
        }
    }

    private fun showCategories(section: ContentSection) {
        if (lastPlayed != null && lastPlayed?.section != section) stopPlayback(true)
        currentSection = section
        browseLevel = BrowseLevel.CATEGORIES
        selectedCategory = null
        currentItems = emptyList()
        currentMovie = null
        currentMovieDetails = null
        detailPanel.visibility = View.GONE
        browsePanel.visibility = View.VISIBLE
        sectionTitle.text = sectionLabel(section)
        browseTitle.text = "${sectionLabel(section)} · CATEGORÍAS"
        browseSubtitle.text = "Cargando categorías…"
        configurePanels(section, categories = true)
        recycler.adapter = null
        recycler.layoutManager = verticalManager()
        infoTitle.text = sectionLabel(section)
        infoBody.text = "Cargando…"
        sectionButtons.forEach { (s, b) -> b.background = rounded(if (s == section) Color.rgb(72, 18, 28) else Color.TRANSPARENT, 8f) }

        io.execute {
            val result = runCatching { repository.loadCategories(section) }
            runOnUiThread {
                result.onSuccess { cats ->
                    currentCategories = cats
                    recycler.adapter = CategoryAdapter(cats) { showItems(it) }
                    browseSubtitle.text = "${cats.size} categorías"
                    infoBody.text = if (cats.size <= 1) "No hay contenido disponible." else "Elegí una categoría."
                    focusFirst()
                }.onFailure { showCatalogError(it.message) }
            }
        }
    }

    private fun showItems(category: TvCategory) {
        selectedCategory = category
        browseLevel = BrowseLevel.ITEMS
        browseTitle.text = "${sectionLabel(currentSection)} · ${category.name}"
        browseSubtitle.text = "Cargando contenido…"
        recycler.adapter = null
        detailPanel.visibility = View.GONE
        browsePanel.visibility = View.VISIBLE
        configurePanels(currentSection, categories = false)
        recycler.layoutManager = if (currentSection == ContentSection.MOVIES || currentSection == ContentSection.SERIES) gridManager(5) else verticalManager()

        io.execute {
            val result = runCatching { repository.loadItems(currentSection, category.id) }
            runOnUiThread {
                result.onSuccess { list ->
                    currentItems = list
                    if (currentSection == ContentSection.SERIES) seriesGridItems = list
                    recycler.adapter = ContentAdapter(list, currentSection == ContentSection.MOVIES || currentSection == ContentSection.SERIES)
                    browseSubtitle.text = "${list.size} elementos · BACK para volver"
                    if (currentSection == ContentSection.LIVE || currentSection == ContentSection.RADIO) {
                        infoTitle.text = category.name
                        infoBody.text = if (list.isEmpty()) "No hay contenido." else "${list.size} disponibles"
                    }
                    focusFirst()
                }.onFailure { showCatalogError(it.message) }
            }
        }
    }

    private fun openItem(item: ContentItem) {
        when (item.section) {
            ContentSection.LIVE -> {
                if (lastPlayed?.id == item.id && player?.isPlaying == true) enterFullscreen()
                else startPlayback(item, false)
            }
            ContentSection.RADIO -> startPlayback(item, false)
            ContentSection.MOVIES -> showMovieDetails(item)
            ContentSection.SERIES -> {
                if (item.url.isBlank() && item.seriesId.isNotBlank()) showEpisodes(item)
                else {
                    startPlayback(item, false)
                    enterFullscreen()
                }
            }
        }
    }

    private fun showEpisodes(series: ContentItem) {
        browseLevel = BrowseLevel.EPISODES
        browseTitle.text = series.name
        browseSubtitle.text = "Cargando episodios…"
        configurePanels(ContentSection.SERIES, categories = false)
        recycler.adapter = null
        recycler.layoutManager = verticalManager()
        io.execute {
            val result = runCatching { repository.loadSeriesEpisodes(series.seriesId) }
            runOnUiThread {
                result.onSuccess { episodes ->
                    currentItems = episodes
                    recycler.adapter = ContentAdapter(episodes, false)
                    browseSubtitle.text = "${episodes.size} episodios · BACK para volver"
                    focusFirst()
                }.onFailure { showCatalogError(it.message) }
            }
        }
    }

    private fun restoreSeriesGrid() {
        browseLevel = BrowseLevel.ITEMS
        currentItems = seriesGridItems
        browseTitle.text = "SERIES · ${selectedCategory?.name.orEmpty()}"
        browseSubtitle.text = "${currentItems.size} series · BACK para volver"
        configurePanels(ContentSection.SERIES, categories = false)
        recycler.layoutManager = gridManager(5)
        recycler.adapter = ContentAdapter(currentItems, true)
        focusFirst()
    }

    private fun showMovieDetails(movie: ContentItem) {
        currentMovie = movie
        currentMovieDetails = null
        browseLevel = BrowseLevel.MOVIE_DETAILS
        sectionTitle.text = "PELÍCULAS · ${movie.name}"
        browsePanel.visibility = View.GONE
        rightPanel.visibility = View.GONE
        detailPanel.visibility = View.VISIBLE
        detailPanel.removeAllViews()
        detailPanel.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            addView(ProgressBar(this@TvHomeActivity).apply { isIndeterminate = true }, LinearLayout.LayoutParams(dp(46), dp(46)))
            addView(TextView(this@TvHomeActivity).apply {
                text = "Cargando información de la película…"
                textSize = 15f
                setTextColor(MUTED)
                gravity = Gravity.CENTER
                setPadding(0, dp(12), 0, 0)
            })
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        io.execute {
            val details = repository.loadVodDetails(movie)
            runOnUiThread {
                if (browseLevel != BrowseLevel.MOVIE_DETAILS || currentMovie?.id != movie.id) return@runOnUiThread
                currentMovieDetails = details
                renderMovieDetails(details)
            }
        }
    }

    private fun renderMovieDetails(details: MovieDetails) {
        detailPanel.removeAllViews()
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(10), dp(8), dp(10), dp(8))
        }

        val posterWrap = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        }
        val poster = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = rounded(PANEL_ALT, 16f, BORDER, 1)
        }
        posterWrap.addView(poster, LinearLayout.LayoutParams(dp(260), dp(390)))
        imageLoader.load(poster, details.movie.logo, dp(260), dp(390))
        row.addView(posterWrap, LinearLayout.LayoutParams(dp(290), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(22) })

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(4), dp(8), dp(8))
        }
        content.addView(TextView(this).apply {
            text = details.movie.name
            textSize = 28f
            setTextColor(TEXT)
            setTypeface(typeface, Typeface.BOLD)
            maxLines = 2
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        val meta = listOf(details.releaseDate, details.genre, details.rating.takeIf { it.isNotBlank() }?.let { "★ $it" }, details.duration)
            .filterNotNull().filter { it.isNotBlank() }.joinToString("   •   ")
        content.addView(TextView(this).apply {
            text = meta
            textSize = 14f
            setTextColor(MUTED)
            setPadding(0, dp(8), 0, dp(10))
            maxLines = 2
        })

        content.addView(TextView(this).apply {
            text = details.plot.ifBlank { "Sin descripción disponible." }
            textSize = 16f
            setTextColor(TEXT)
            maxLines = 8
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        val extra = buildString {
            if (details.cast.isNotBlank()) append("Reparto: ${details.cast}\n")
            if (details.director.isNotBlank()) append("Director: ${details.director}\n")
            if (details.country.isNotBlank()) append("País: ${details.country}")
        }.trim()
        if (extra.isNotBlank()) {
            content.addView(TextView(this).apply {
                text = extra
                textSize = 12f
                setTextColor(MUTED)
                maxLines = 4
                setPadding(0, dp(8), 0, dp(8))
            })
        }

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
        }
        val play = actionButton("▶  REPRODUCIR") {
            val item = details.movie.copy(url = details.playableUrl.ifBlank { details.movie.url })
            startPlayback(item, false)
            enterFullscreen()
        }
        actions.addView(play, LinearLayout.LayoutParams(dp(210), dp(54)).apply { marginEnd = dp(12) })

        if (details.trailer.isNotBlank()) {
            actions.addView(actionButton("TRÁILER") { playTrailer(details) }, LinearLayout.LayoutParams(dp(170), dp(54)))
        }
        content.addView(actions, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(64)))
        row.addView(content, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
        detailPanel.addView(row, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        play.requestFocus()
    }

    private fun playTrailer(details: MovieDetails) {
        val raw = details.trailer.trim()
        if (raw.isBlank()) return
        val lower = raw.lowercase(Locale.ROOT)
        val looksDirect = raw.startsWith("http", true) && !lower.contains("youtube.com") && !lower.contains("youtu.be") && !lower.contains("vimeo.com")
        if (looksDirect) {
            startPlayback(ContentItem(
                id = "trailer-${details.movie.id}",
                name = "Tráiler · ${details.movie.name}",
                url = raw,
                logo = details.backdrop.ifBlank { details.movie.logo },
                section = ContentSection.MOVIES
            ), false)
            enterFullscreen()
            return
        }

        val uri = when {
            raw.startsWith("http", true) -> Uri.parse(raw)
            raw.matches(Regex("^[A-Za-z0-9_-]{6,}$")) -> Uri.parse("https://www.youtube.com/watch?v=$raw")
            else -> null
        } ?: return
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }
    }

    private fun actionButton(textValue: String, action: () -> Unit): Button = Button(this).apply {
        text = textValue
        textSize = 13f
        isAllCaps = false
        isFocusable = true
        setTextColor(Color.WHITE)
        background = rounded(ACCENT, 9f)
        setOnClickListener { action() }
        setOnFocusChangeListener { v, focused ->
            (v as Button).background = rounded(if (focused) Color.rgb(255, 33, 48) else ACCENT, 9f, if (focused) Color.WHITE else ACCENT, if (focused) 2 else 0)
        }
    }

    private fun configurePanels(section: ContentSection, categories: Boolean) {
        detailPanel.visibility = View.GONE
        browsePanel.visibility = View.VISIBLE
        val liveLike = section == ContentSection.LIVE || section == ContentSection.RADIO
        rightPanel.visibility = if (liveLike) View.VISIBLE else View.GONE
        val lp = browsePanel.layoutParams as LinearLayout.LayoutParams
        if (liveLike) {
            lp.width = dp(if (categories) 390 else 405)
            lp.weight = 0f
            lp.marginEnd = dp(10)
        } else {
            lp.width = 0
            lp.weight = 1f
            lp.marginEnd = 0
        }
        browsePanel.layoutParams = lp
    }

    private fun initPlayer() {
        // Importante v1.6: no fijamos 16/28 MB. Media3 calcula el target de
        // memoria según las pistas, igual que corresponde para video pesado.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(5_000, 15_000, 2_500, 1_000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val renderers = DefaultRenderersFactory(this)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)

        val dataSource = DefaultHttpDataSource.Factory()
            .setUserAgent("Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 Chrome/120 Safari/537.36")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(8_000)
            .setReadTimeoutMs(30_000)

        val p = ExoPlayer.Builder(this, renderers)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSource))
            .build()

        p.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_BUFFERING -> {
                        beginBuffering()
                        if (waitingFirstFrame) showLoading("Inicializando…")
                        else if (isLiveLike()) scheduleStallWatch()
                        else showLoading("Cargando…")
                    }
                    Player.STATE_READY -> {
                        endBuffering()
                        cancelStallWatch()
                        if (lastPlayed?.section == ContentSection.RADIO && waitingFirstFrame) playbackStarted()
                        if (!waitingFirstFrame) hideLoading()
                    }
                    Player.STATE_ENDED -> {
                        endBuffering()
                        cancelStallWatch()
                        if (isLiveLike()) scheduleReconnect("La señal terminó")
                        else showLoading("Finalizado")
                    }
                    else -> Unit
                }
            }

            override fun onRenderedFirstFrame() {
                playbackStarted()
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                diagnostics.width = videoSize.width
                diagnostics.height = videoSize.height
            }

            override fun onPlayerError(error: PlaybackException) {
                endBuffering()
                cancelStallWatch()
                diagnostics.error = "${PlaybackException.getErrorCodeName(error.errorCode)} ${error.message.orEmpty()}".trim()
                if (isLiveLike()) {
                    val status = httpStatus(error)
                    if (status == 401 || status == 403 || status == 404 || status == 410) markUnavailable("HTTP $status")
                    else scheduleReconnect("Error de señal")
                } else {
                    waitingFirstFrame = false
                    showLoading("No se pudo reproducir")
                }
            }
        })
        player = p
        playerView.player = p
    }

    private fun startPlayback(item: ContentItem, reconnect: Boolean) {
        val p = player ?: run { initPlayer(); player ?: return }
        if (!reconnect) {
            reconnectAttempts = 0
            diagnostics = PlaybackDiagnostics()
        }
        lastPlayed = item
        currentEpg = null
        waitingFirstFrame = true
        startupToken++
        reconnectToken++
        cancelStallWatch()
        val token = startupToken

        showLoading(if (reconnect) "Reconectando…" else "Inicializando…")
        p.stop()
        p.clearMediaItems()
        p.setMediaItem(MediaItem.fromUri(item.url))
        p.prepare()
        p.playWhenReady = true
        if (item.section == ContentSection.LIVE) loadEpg(item)

        handler.postDelayed({
            if (token == startupToken && waitingFirstFrame && lastPlayed?.url == item.url) {
                if (isLiveLike()) scheduleReconnect("Inicio sin señal")
                else {
                    p.stop()
                    waitingFirstFrame = false
                    showLoading("No se pudo iniciar")
                }
            }
        }, LIVE_START_TIMEOUT)
    }

    private fun playbackStarted() {
        waitingFirstFrame = false
        reconnectAttempts = 0
        cancelStallWatch()
        hideLoading()
        showHud()
    }

    private fun scheduleStallWatch() {
        if (!isLiveLike() || waitingFirstFrame) return
        stallToken++
        val token = stallToken
        handler.postDelayed({
            if (token == stallToken && player?.playbackState == Player.STATE_BUFFERING && !waitingFirstFrame && isLiveLike()) {
                hudBadge.text = "SEÑAL"
                hudBadge.background = rounded(WARNING, 7f)
                hudSubtitle.text = "Recuperando señal sin cortar el canal…"
                showHud()
            }
        }, LIVE_STALL_NOTICE)
        handler.postDelayed({
            if (token == stallToken && player?.playbackState == Player.STATE_BUFFERING && !waitingFirstFrame && isLiveLike()) {
                scheduleReconnect("Buffering prolongado")
            }
        }, LIVE_STALL_REOPEN)
    }

    private fun cancelStallWatch() { stallToken++ }

    private fun scheduleReconnect(reason: String) {
        val item = lastPlayed ?: return
        if (!isLiveLike()) return
        if (reconnectAttempts >= MAX_RECONNECTS) {
            markUnavailable("Máximo de reintentos")
            return
        }
        reconnectAttempts++
        diagnostics.reconnects++
        reconnectToken++
        val token = reconnectToken
        val delay = when (reconnectAttempts) {
            1 -> 700L
            2 -> 1_500L
            3 -> 3_000L
            else -> 5_000L
        }
        showLoading("Reconectando…")
        infoTitle.text = item.name
        infoBody.text = "$reason · intento $reconnectAttempts de $MAX_RECONNECTS"
        handler.postDelayed({
            if (token == reconnectToken && lastPlayed?.url == item.url) startPlayback(item, true)
        }, delay)
    }

    private fun markUnavailable(reason: String) {
        waitingFirstFrame = false
        cancelStallWatch()
        player?.stop()
        showLoading("Canal no disponible")
        diagnostics.error = reason
        infoBody.text = reason
    }

    private fun loadEpg(item: ContentItem) {
        io.execute {
            val epg = repository.loadShortEpg(item.id)
            val current = epg.firstOrNull()
            runOnUiThread {
                if (lastPlayed?.id == item.id) {
                    currentEpg = current
                    if (hud.visibility == View.VISIBLE) showHud()
                }
                if (infoTitle.text.toString() == item.name && epg.isNotEmpty()) {
                    infoBody.text = epg.joinToString("\n\n") { e ->
                        buildString {
                            append(e.title.ifBlank { "Programa" })
                            if (e.start.isNotBlank()) append("\n${e.start} → ${e.end}")
                        }
                    }
                }
            }
        }
    }

    private fun showHud() {
        val item = lastPlayed ?: return
        if (channelOverlayVisible) return
        handler.removeCallbacks(hideHud)
        hud.visibility = View.VISIBLE
        imageLoader.load(hudLogo, item.logo, dp(54), dp(44))
        hudTitle.text = item.name

        when (item.section) {
            ContentSection.LIVE -> {
                hudBadge.text = "LIVE"
                hudBadge.background = rounded(LIVE, 7f)
                hudSubtitle.text = currentEpg?.title?.ifBlank { "EN VIVO" } ?: "EN VIVO"
                hudHint.text = "↓ canales · OK pausa · BACK volver"
                vodProgressRow.visibility = View.GONE
                updateLiveProgress()
            }
            ContentSection.RADIO -> {
                hudBadge.text = "RADIO"
                hudBadge.background = rounded(ACCENT, 7f)
                hudSubtitle.text = "En vivo"
                hudHint.text = "OK pausa · BACK volver"
                liveProgressRow.visibility = View.GONE
                vodProgressRow.visibility = View.GONE
            }
            ContentSection.MOVIES, ContentSection.SERIES -> {
                hudBadge.text = if (item.name.startsWith("Tráiler")) "TRÁILER" else "PLAY"
                hudBadge.background = rounded(ACCENT, 7f)
                hudSubtitle.text = if (player?.isPlaying == true) "Reproduciendo" else "Pausa"
                hudHint.text = "← -10s · → +10s · OK pausa · BACK volver"
                liveProgressRow.visibility = View.GONE
                vodProgressRow.visibility = View.VISIBLE
                updateVodProgress()
            }
        }
        handler.postDelayed(hideHud, HUD_HIDE)
    }

    private fun updateLiveProgress() {
        val epg = currentEpg
        if (epg == null) {
            liveProgressRow.visibility = View.GONE
            return
        }
        val start = parseEpgTime(epg.start)
        val end = parseEpgTime(epg.end)
        val now = System.currentTimeMillis()
        if (start == null || end == null || end <= start) {
            liveProgressRow.visibility = View.GONE
            return
        }
        liveProgressRow.visibility = View.VISIBLE
        liveStart.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(start))
        liveEnd.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(end))
        liveProgress.progress = (((now - start).toDouble() / (end - start).toDouble()) * 1000).toInt().coerceIn(0, 1000)
    }

    private fun parseEpgTime(value: String): Long? {
        if (value.isBlank()) return null
        for (pattern in listOf("yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm")) {
            runCatching { SimpleDateFormat(pattern, Locale.getDefault()).parse(value)?.time }.getOrNull()?.let { return it }
        }
        return null
    }

    private fun updateVodProgress() {
        val item = lastPlayed ?: return
        if (item.section == ContentSection.LIVE || item.section == ContentSection.RADIO) return
        val p = player ?: return
        val duration = p.duration
        val position = p.currentPosition.coerceAtLeast(0)
        vodCurrent.text = formatTime(position)
        if (duration == C.TIME_UNSET || duration <= 0) {
            vodDuration.text = "--:--"
            vodProgress.progress = 0
        } else {
            vodDuration.text = formatTime(duration)
            vodProgress.progress = ((position.toDouble() / duration.toDouble()) * 1000).toInt().coerceIn(0, 1000)
        }
    }

    private fun formatTime(ms: Long): String {
        val total = (ms / 1000).coerceAtLeast(0)
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) String.format(Locale.getDefault(), "%d:%02d:%02d", h, m, s)
        else String.format(Locale.getDefault(), "%02d:%02d", m, s)
    }

    private fun seekVod(delta: Long) {
        if (isLiveLike()) return
        val p = player ?: return
        val duration = p.duration
        val max = if (duration == C.TIME_UNSET || duration <= 0) Long.MAX_VALUE else duration
        p.seekTo((p.currentPosition + delta).coerceAtLeast(0).coerceAtMost(max))
        showHud()
    }

    private fun togglePause() {
        player?.let { if (it.isPlaying) it.pause() else it.play() }
        showHud()
    }

    private fun enterFullscreen() {
        if (isFullscreen || lastPlayed == null || lastPlayed?.section == ContentSection.RADIO) return
        isFullscreen = true
        hideChannelOverlay(false)
        immersive()
        topBar.visibility = View.GONE
        navRail.visibility = View.GONE
        browsePanel.visibility = View.GONE
        detailPanel.visibility = View.GONE
        body.setPadding(0, 0, 0, 0)
        rightPanel.visibility = View.VISIBLE
        (rightPanel.layoutParams as LinearLayout.LayoutParams).apply { width = 0; weight = 1f; marginEnd = 0 }.also { rightPanel.layoutParams = it }
        (videoFrame.layoutParams as LinearLayout.LayoutParams).apply { height = 0; weight = 1f; topMargin = 0; bottomMargin = 0 }.also { videoFrame.layoutParams = it }
        videoFrame.background = null
        videoFrame.setPadding(0, 0, 0, 0)
        showHud()
    }

    private fun exitFullscreen() {
        if (!isFullscreen) return
        hideChannelOverlay(false)
        isFullscreen = false
        topBar.visibility = View.VISIBLE
        navRail.visibility = View.VISIBLE
        body.setPadding(dp(12), dp(10), dp(12), dp(12))
        videoFrame.background = rounded(Color.BLACK, 14f, BORDER, 1)
        videoFrame.setPadding(dp(2), dp(2), dp(2), dp(2))
        (videoFrame.layoutParams as LinearLayout.LayoutParams).apply { height = 0; weight = 0.70f }.also { videoFrame.layoutParams = it }
        handler.removeCallbacks(hideHud)
        hud.visibility = View.GONE

        if (browseLevel == BrowseLevel.MOVIE_DETAILS) {
            rightPanel.visibility = View.GONE
            browsePanel.visibility = View.GONE
            detailPanel.visibility = View.VISIBLE
        } else {
            configurePanels(currentSection, browseLevel == BrowseLevel.CATEGORIES)
            recycler.post { recycler.requestFocus() }
        }
    }

    private fun showChannelOverlay() {
        if (!isFullscreen || lastPlayed?.section != ContentSection.LIVE || currentItems.isEmpty()) return
        channelOverlayVisible = true
        handler.removeCallbacks(hideHud)
        hud.visibility = View.GONE
        channelOverlayTitle.text = selectedCategory?.name?.let { "CANALES · $it" } ?: "CANALES"
        val adapter = ContentAdapter(currentItems, false) { item ->
            startPlayback(item, false)
            hideChannelOverlay(true)
        }
        channelOverlayRecycler.adapter = adapter
        channelOverlay.visibility = View.VISIBLE
        val index = currentItems.indexOfFirst { it.id == lastPlayed?.id }.coerceAtLeast(0)
        channelOverlayRecycler.scrollToPosition(index)
        channelOverlayRecycler.post {
            channelOverlayRecycler.findViewHolderForAdapterPosition(index)?.itemView?.requestFocus() ?: channelOverlayRecycler.requestFocus()
        }
    }

    private fun hideChannelOverlay(showHudAfter: Boolean = true) {
        if (!::channelOverlay.isInitialized) return
        channelOverlayVisible = false
        channelOverlay.visibility = View.GONE
        channelOverlayRecycler.adapter = null
        if (showHudAfter && isFullscreen) showHud()
    }

    private fun showItemInfo(item: ContentItem) {
        if (currentSection != ContentSection.LIVE && currentSection != ContentSection.RADIO) return
        infoTitle.text = item.name
        infoBody.text = if (item.section == ContentSection.RADIO) "Radio en vivo" else "Canal ${item.id}"
    }

    private fun showSearch() {
        val input = EditText(this).apply {
            hint = "Buscar en esta pantalla"
            inputType = InputType.TYPE_CLASS_TEXT
            setTextColor(Color.WHITE)
            setHintTextColor(Color.LTGRAY)
        }
        AlertDialog.Builder(this)
            .setTitle("Buscar")
            .setView(input)
            .setPositiveButton("BUSCAR") { _, _ ->
                val q = input.text.toString().trim().lowercase(Locale.getDefault())
                if (browseLevel == BrowseLevel.CATEGORIES) {
                    recycler.adapter = CategoryAdapter(currentCategories.filter { q.isBlank() || it.name.lowercase(Locale.getDefault()).contains(q) }) { showItems(it) }
                } else if (browseLevel == BrowseLevel.ITEMS || browseLevel == BrowseLevel.EPISODES) {
                    val filtered = currentItems.filter { q.isBlank() || it.name.lowercase(Locale.getDefault()).contains(q) || it.genre.lowercase(Locale.getDefault()).contains(q) }
                    recycler.adapter = ContentAdapter(filtered, currentSection == ContentSection.MOVIES || (currentSection == ContentSection.SERIES && browseLevel != BrowseLevel.EPISODES))
                }
                focusFirst()
            }
            .setNegativeButton("CANCELAR", null)
            .show()
    }

    private fun showSettings() {
        val wrap = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(8), dp(18), dp(8))
        }
        val status = TextView(this).apply {
            text = "Interfaz: ${UiPreferences.label(this@TvHomeActivity)}\nFuente: ${if (sourceConfig.mode == SourceMode.XTREAM) "Xtream" else "M3U"}\nVideo: ${diagnostics.width}x${diagnostics.height} · Buffering: ${diagnostics.bufferingCount} · Reconexiones: ${diagnostics.reconnects}"
            textSize = 14f
            setTextColor(Color.WHITE)
            setPadding(0, 0, 0, dp(10))
        }
        wrap.addView(status)

        val sizes = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER }
        sizes.addView(settingsButton("ACHICAR") { UiPreferences.setScale(this, UiPreferences.SMALL); recreate() }, LinearLayout.LayoutParams(0, dp(50), 1f).apply { marginEnd = dp(6) })
        sizes.addView(settingsButton("NORMAL") { UiPreferences.setScale(this, UiPreferences.NORMAL); recreate() }, LinearLayout.LayoutParams(0, dp(50), 1f).apply { marginEnd = dp(6) })
        sizes.addView(settingsButton("AGRANDAR") { UiPreferences.setScale(this, UiPreferences.LARGE); recreate() }, LinearLayout.LayoutParams(0, dp(50), 1f))
        wrap.addView(sizes)

        val speed = settingsButton("TEST DE VELOCIDAD") {
            status.text = "Midiendo velocidad… puede tardar unos segundos."
            io.execute {
                val result = runCatching { InternetSpeedTestService.run() }
                runOnUiThread {
                    result.onSuccess {
                        status.text = String.format(Locale.getDefault(), "Velocidad: %.1f Mbps\nLatencia: %d ms\nDatos medidos: %.1f MB", it.downloadMbps, it.latencyMs, it.bytesTransferred / 1024.0 / 1024.0)
                    }.onFailure { status.text = "No se pudo medir: ${it.message ?: "error de conexión"}" }
                }
            }
        }
        wrap.addView(speed, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)).apply { topMargin = dp(10) })

        wrap.addView(settingsButton("SINCRONIZAR PANEL") {
            startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
            finish()
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)).apply { topMargin = dp(8) })

        AlertDialog.Builder(this)
            .setTitle("AJUSTES · TV FULL PRO")
            .setView(wrap)
            .setNegativeButton("CERRAR", null)
            .show()
    }

    private fun settingsButton(label: String, action: () -> Unit) = Button(this).apply {
        text = label
        textSize = 12f
        isAllCaps = false
        isFocusable = true
        setTextColor(Color.WHITE)
        background = rounded(CARD, 8f, BORDER, 1)
        setOnClickListener { action() }
        setOnFocusChangeListener { v, focused -> (v as Button).background = rounded(if (focused) ACCENT else CARD, 8f, if (focused) ACCENT else BORDER, 1) }
    }

    private fun openPlaylists() {
        stopPlayback(true)
        if (RemotePrefs.loadServices(this).isNotEmpty()) startActivity(Intent(this, PlaylistActivity::class.java))
        else startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
        finish()
    }

    private fun restoreMovieGrid() {
        browseLevel = BrowseLevel.ITEMS
        currentMovie = null
        currentMovieDetails = null
        sectionTitle.text = "PELÍCULAS"
        detailPanel.visibility = View.GONE
        browsePanel.visibility = View.VISIBLE
        configurePanels(ContentSection.MOVIES, false)
        recycler.layoutManager = gridManager(5)
        recycler.adapter = ContentAdapter(currentItems, true)
        focusFirst()
    }

    private fun stopPlayback(clear: Boolean) {
        startupToken++
        reconnectToken++
        cancelStallWatch()
        waitingFirstFrame = false
        reconnectAttempts = 0
        player?.stop()
        player?.clearMediaItems()
        if (clear) lastPlayed = null
        currentEpg = null
        hideLoading()
        handler.removeCallbacks(hideHud)
        if (::hud.isInitialized) hud.visibility = View.GONE
    }

    private fun releasePlayer() {
        startupToken++
        reconnectToken++
        cancelStallWatch()
        waitingFirstFrame = false
        if (::playerView.isInitialized) playerView.player = null
        player?.release()
        player = null
    }

    private fun beginBuffering() {
        if (diagnostics.bufferingStarted == 0L) {
            diagnostics.bufferingStarted = System.currentTimeMillis()
            diagnostics.bufferingCount++
        }
    }

    private fun endBuffering() {
        if (diagnostics.bufferingStarted > 0) {
            diagnostics.bufferingMs += System.currentTimeMillis() - diagnostics.bufferingStarted
            diagnostics.bufferingStarted = 0
        }
    }

    private fun httpStatus(error: PlaybackException): Int? {
        var cause: Throwable? = error
        while (cause != null) {
            if (cause is HttpDataSource.InvalidResponseCodeException) return cause.responseCode
            cause = cause.cause
        }
        return null
    }

    private fun isLiveLike() = lastPlayed?.section == ContentSection.LIVE || lastPlayed?.section == ContentSection.RADIO

    private fun showLoading(text: String) {
        loadingText.text = text
        loading.visibility = View.VISIBLE
    }

    private fun hideLoading() { loading.visibility = View.GONE }

    private fun showCatalogError(message: String?) {
        browseSubtitle.text = message ?: "Error de red o formato"
        infoTitle.text = "No se pudo cargar"
        infoBody.text = message ?: "Error de red o formato"
    }

    private fun focusFirst() {
        recycler.post { recycler.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() ?: recycler.requestFocus() }
    }

    private fun verticalManager() = LinearLayoutManager(this).apply { isItemPrefetchEnabled = false }
    private fun gridManager(columns: Int) = GridLayoutManager(this, columns).apply { isItemPrefetchEnabled = false }

    private fun sectionLabel(section: ContentSection) = when (section) {
        ContentSection.LIVE -> "TV EN VIVO"
        ContentSection.MOVIES -> "PELÍCULAS"
        ContentSection.SERIES -> "SERIES"
        ContentSection.RADIO -> "RADIO"
    }

    private fun updateClock() {
        if (::clock.isInitialized) clock.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        handler.postDelayed({ updateClock() }, 30_000)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            if (isFullscreen && !channelOverlayVisible) {
                when (event.keyCode) {
                    KeyEvent.KEYCODE_DPAD_LEFT -> { if (!isLiveLike()) seekVod(-SEEK_STEP) else showHud(); return true }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> { if (!isLiveLike()) seekVod(SEEK_STEP) else showHud(); return true }
                    KeyEvent.KEYCODE_DPAD_UP -> { showHud(); return true }
                }
            }
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK -> {
                    when {
                        channelOverlayVisible -> hideChannelOverlay(true)
                        isFullscreen && !isLiveLike() -> { stopPlayback(true); exitFullscreen() }
                        isFullscreen -> exitFullscreen()
                        browseLevel == BrowseLevel.MOVIE_DETAILS -> restoreMovieGrid()
                        browseLevel == BrowseLevel.EPISODES -> restoreSeriesGrid()
                        browseLevel == BrowseLevel.ITEMS -> showCategories(currentSection)
                        else -> sectionButtons[currentSection]?.requestFocus()
                    }
                    return true
                }
                KeyEvent.KEYCODE_DPAD_DOWN -> if (isFullscreen && lastPlayed?.section == ContentSection.LIVE && !channelOverlayVisible) {
                    showChannelOverlay(); return true
                }
                KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> if (isFullscreen && !channelOverlayVisible) {
                    togglePause(); return true
                }
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> if (isFullscreen) { togglePause(); return true }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacksAndMessages(null)
        io.shutdownNow()
        if (::imageLoader.isInitialized) imageLoader.shutdown()
    }

    private fun immersive() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }

    private fun rounded(fill: Int, radius: Float, stroke: Int? = null, strokeWidth: Int = 0): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dp(radius.toInt()).toFloat()
            if (stroke != null && strokeWidth > 0) setStroke(dp(strokeWidth), stroke)
        }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private inner class CategoryAdapter(
        private val data: List<TvCategory>,
        private val click: (TvCategory) -> Unit
    ) : RecyclerView.Adapter<CategoryAdapter.Holder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
            val text = TextView(parent.context).apply {
                textSize = 16f
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), 0, dp(12), 0)
                setTextColor(TEXT)
                isFocusable = true
                maxLines = 1
                background = rounded(CARD, 9f, BORDER, 1)
                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(54)).apply { bottomMargin = dp(6) }
            }
            return Holder(text)
        }
        override fun onBindViewHolder(holder: Holder, position: Int) {
            val item = data[position]
            holder.text.text = if (item.count > 0) "${item.name}   ·   ${item.count}" else item.name
            holder.text.setOnClickListener { click(item) }
            holder.text.setOnFocusChangeListener { v, focused ->
                (v as TextView).background = rounded(if (focused) ACCENT else CARD, 9f, if (focused) ACCENT else BORDER, 1)
            }
        }
        override fun getItemCount() = data.size
        inner class Holder(val text: TextView) : RecyclerView.ViewHolder(text)
    }

    private inner class ContentAdapter(
        private val data: List<ContentItem>,
        private val grid: Boolean,
        private val clickOverride: ((ContentItem) -> Unit)? = null
    ) : RecyclerView.Adapter<ContentAdapter.Holder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder = if (grid) gridHolder(parent) else listHolder(parent)

        private fun listHolder(parent: ViewGroup): Holder {
            val row = LinearLayout(parent.context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(8), dp(5), dp(12), dp(5))
                isFocusable = true
                background = rounded(CARD, 9f, BORDER, 1)
                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(62)).apply { bottomMargin = dp(6) }
            }
            val image = ImageView(parent.context).apply { scaleType = ImageView.ScaleType.CENTER_INSIDE }
            val title = TextView(parent.context).apply {
                textSize = 15f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER_VERTICAL
                maxLines = 2
            }
            row.addView(image, LinearLayout.LayoutParams(dp(52), dp(46)).apply { marginEnd = dp(10) })
            row.addView(title, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
            return Holder(row, image, title)
        }

        private fun gridHolder(parent: ViewGroup): Holder {
            val card = LinearLayout(parent.context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(dp(5), dp(5), dp(5), dp(7))
                isFocusable = true
                background = rounded(CARD, 10f, BORDER, 1)
                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(250)).apply {
                    marginStart = dp(4); marginEnd = dp(4); topMargin = dp(4); bottomMargin = dp(5)
                }
            }
            val image = ImageView(parent.context).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                background = rounded(PANEL_ALT, 8f)
            }
            val title = TextView(parent.context).apply {
                textSize = 12f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER
                maxLines = 2
            }
            card.addView(image, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            card.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(46)))
            return Holder(card, image, title)
        }

        override fun onBindViewHolder(holder: Holder, position: Int) {
            val item = data[position]
            holder.item = item
            holder.title.text = item.name
            holder.root.setOnClickListener { (clickOverride ?: ::openItem)(item) }
            holder.root.setOnFocusChangeListener { v, focused ->
                v.background = rounded(if (focused) Color.rgb(73, 21, 31) else CARD, if (grid) 10f else 9f, if (focused) ACCENT else BORDER, if (focused) 2 else 1)
                if (focused) showItemInfo(item)
            }
        }

        override fun onViewAttachedToWindow(holder: Holder) {
            super.onViewAttachedToWindow(holder)
            val item = holder.item ?: return
            val w = if (grid) dp(180) else dp(52)
            val h = if (grid) dp(190) else dp(46)
            imageLoader.load(holder.image, item.logo, w, h)
        }

        override fun onViewDetachedFromWindow(holder: Holder) {
            imageLoader.cancel(holder.image)
            super.onViewDetachedFromWindow(holder)
        }

        override fun getItemCount() = data.size
        inner class Holder(val root: LinearLayout, val image: ImageView, val title: TextView) : RecyclerView.ViewHolder(root) {
            var item: ContentItem? = null
        }
    }
}
