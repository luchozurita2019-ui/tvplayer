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
import android.util.Log
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
class MainActivity : AppCompatActivity() {
    companion object {
        private const val TAG = "TVFullPlayback"
        private const val LIVE_STARTUP_TIMEOUT_MS = 10_000L
        private const val LIVE_RECONNECT_STARTUP_TIMEOUT_MS = 8_000L
        private const val LIVE_REBUFFER_NOTICE_MS = 1_400L
        private const val LIVE_MAX_RECOVERIES = 4
        private const val HUD_HIDE_MS = 4_000L
        private const val VOD_SEEK_MS = 10_000L

        private val BG = Color.rgb(6, 10, 18)
        private val TOP = Color.rgb(10, 16, 27)
        private val PANEL = Color.rgb(13, 21, 34)
        private val PANEL_ALT = Color.rgb(17, 27, 43)
        private val CARD = Color.rgb(24, 36, 55)
        private val BORDER = Color.rgb(41, 57, 80)
        private val TEXT = Color.rgb(240, 244, 249)
        private val MUTED = Color.rgb(149, 162, 181)
        private val ACCENT = Color.rgb(229, 9, 20)
        private val LIVE_GREEN = Color.rgb(31, 176, 91)
        private val WARNING = Color.rgb(241, 174, 38)
    }

    private enum class BrowseLevel { CATEGORIES, ITEMS, EPISODES }

    private data class PlaybackDiagnostics(
        var bufferingCount: Int = 0,
        var bufferingStartedAt: Long = 0L,
        var bufferingTotalMs: Long = 0L,
        var recoveries: Int = 0,
        var lastError: String = "",
        var width: Int = 0,
        var height: Int = 0,
        var transport: String = ""
    )

    private lateinit var repository: CatalogRepository
    private lateinit var sourceConfig: SourceConfig
    private lateinit var imageLoader: LiteImageLoader
    private val io = Executors.newFixedThreadPool(3)
    private val handler = Handler(Looper.getMainLooper())

    private lateinit var root: LinearLayout
    private lateinit var topBar: View
    private lateinit var body: LinearLayout
    private lateinit var navRail: LinearLayout
    private lateinit var browsePanel: LinearLayout
    private lateinit var browseRecycler: RecyclerView
    private lateinit var browseTitle: TextView
    private lateinit var browseSubtitle: TextView
    private lateinit var rightPanel: LinearLayout
    private lateinit var videoFrame: FrameLayout
    private lateinit var infoCard: LinearLayout
    private lateinit var playerView: PlayerView
    private lateinit var loading: View
    private lateinit var loadingText: TextView
    private lateinit var infoTitle: TextView
    private lateinit var infoBody: TextView
    private lateinit var sectionTitle: TextView
    private lateinit var clock: TextView
    private lateinit var sourceBadge: TextView
    private lateinit var fullscreenButton: Button

    private lateinit var videoHud: LinearLayout
    private lateinit var hudLogo: ImageView
    private lateinit var hudBadge: TextView
    private lateinit var hudTitle: TextView
    private lateinit var hudSubtitle: TextView
    private lateinit var hudHint: TextView
    private lateinit var liveEpgRow: LinearLayout
    private lateinit var liveEpgStart: TextView
    private lateinit var liveEpgEnd: TextView
    private lateinit var liveEpgProgress: SeekBar
    private lateinit var vodProgressRow: LinearLayout
    private lateinit var vodCurrent: TextView
    private lateinit var vodDuration: TextView
    private lateinit var vodProgress: SeekBar

    private lateinit var fullscreenChannelPanel: LinearLayout
    private lateinit var fullscreenChannelTitle: TextView
    private lateinit var fullscreenChannelRecycler: RecyclerView

    private val sectionButtons = linkedMapOf<ContentSection, Button>()
    private var categoryAdapter: CategoryAdapter? = null
    private var contentAdapter: ContentAdapter? = null
    private var fullscreenChannelAdapter: ContentAdapter? = null

    private var player: ExoPlayer? = null
    private var currentSection = ContentSection.LIVE
    private var browseLevel = BrowseLevel.CATEGORIES
    private var selectedCategory: TvCategory? = null
    private var currentItems: List<ContentItem> = emptyList()
    private var seriesItemsBeforeEpisodes: List<ContentItem> = emptyList()
    private var lastPlayed: ContentItem? = null
    private var currentEpg: EpgEntry? = null

    private var waitingFirstFrame = false
    private var hasPlayedCurrent = false
    private var startupToken = 0L
    private var stallToken = 0L
    private var reconnectToken = 0L
    private var recoveryAttempts = 0
    private var recoveryPending = false
    private var isFullscreen = false
    private var fullscreenChannelListVisible = false
    private var diagnostics = PlaybackDiagnostics()

    private val hideHud = Runnable {
        if (::videoHud.isInitialized && !fullscreenChannelListVisible && !waitingFirstFrame) {
            videoHud.visibility = View.GONE
        }
    }

    private val vodProgressTick = object : Runnable {
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
            goLogin()
            return
        }
        sourceConfig = config
        repository = CatalogRepository(config)
        imageLoader = LiteImageLoader(this)
        setContentView(buildUi(config))
        updateClock()
        showCategories(ContentSection.LIVE)
        handler.post(vodProgressTick)
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
        body.addView(navRail, LinearLayout.LayoutParams(dp(158), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(10) })

        browsePanel = buildBrowsePanel()
        body.addView(browsePanel, LinearLayout.LayoutParams(dp(390), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(10) })

        rightPanel = buildRightPanel()
        body.addView(rightPanel, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))

        return root
    }

    private fun buildTopBar(config: SourceConfig): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), 0, dp(18), 0)
            setBackgroundColor(TOP)

            val brand = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            brand.addView(TextView(this@MainActivity).apply {
                text = "TV FULL"
                textSize = 25f
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                letterSpacing = 0.04f
            })
            brand.addView(TextView(this@MainActivity).apply {
                text = "PRO"
                textSize = 12f
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                background = roundedBg(ACCENT, 7f)
            }, LinearLayout.LayoutParams(dp(48), dp(27)).apply { marginStart = dp(9) })
            addView(brand, LinearLayout.LayoutParams(dp(245), ViewGroup.LayoutParams.MATCH_PARENT))

            sectionTitle = TextView(this@MainActivity).apply {
                text = "TV EN VIVO"
                textSize = 20f
                setTextColor(TEXT)
                gravity = Gravity.CENTER_VERTICAL
                setTypeface(typeface, Typeface.BOLD)
            }
            addView(sectionTitle, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))

            val service = RemotePrefs.serviceName(this@MainActivity).trim()
            sourceBadge = TextView(this@MainActivity).apply {
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
            addView(sourceBadge, LinearLayout.LayoutParams(dp(190), dp(34)).apply { marginEnd = dp(14) })

            clock = TextView(this@MainActivity).apply {
                textSize = 18f
                setTextColor(TEXT)
                gravity = Gravity.CENTER
                setTypeface(typeface, Typeface.BOLD)
            }
            addView(clock, LinearLayout.LayoutParams(dp(82), ViewGroup.LayoutParams.MATCH_PARENT))
        }
    }

    private fun buildNavRail(config: SourceConfig): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = roundedBg(PANEL, 14f, BORDER, 1)

            addView(TextView(this@MainActivity).apply {
                text = "MENÚ"
                textSize = 11f
                setTextColor(MUTED)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(10), 0, 0, 0)
                letterSpacing = 0.12f
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(32)))

            addView(sectionButton(ContentSection.LIVE, "TV EN VIVO"))
            addView(sectionButton(ContentSection.MOVIES, "PELÍCULAS"))
            addView(sectionButton(ContentSection.SERIES, "SERIES"))
            addView(sectionButton(ContentSection.RADIO, "RADIO"))
            addView(navButton("BUSCAR") { showSearch() })
            addView(navButton("MIS LISTAS") { openPlaylistSelector() })
            addView(navButton("AJUSTES") { showSettings(config) })
            addView(View(this@MainActivity), LinearLayout.LayoutParams(1, 0, 1f))
            addView(navButton("SALIR") { finishAffinity() })
        }
    }

    private fun buildBrowsePanel(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = roundedBg(PANEL, 14f, BORDER, 1)

            browseTitle = TextView(this@MainActivity).apply {
                text = "CATEGORÍAS"
                textSize = 15f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER_VERTICAL
            }
            addView(browseTitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(34)))

            browseSubtitle = TextView(this@MainActivity).apply {
                text = "Elegí una categoría"
                textSize = 11f
                setTextColor(MUTED)
                gravity = Gravity.CENTER_VERTICAL
            }
            addView(browseSubtitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(28)))

            browseRecycler = RecyclerView(this@MainActivity).apply {
                setBackgroundColor(Color.TRANSPARENT)
                setPadding(dp(1), dp(4), dp(1), dp(2))
                clipToPadding = false
                clipChildren = false
                isVerticalScrollBarEnabled = false
                setItemViewCacheSize(2)
            }
            addView(browseRecycler, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        }
    }

    private fun buildRightPanel(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL

            videoFrame = FrameLayout(this@MainActivity).apply {
                setPadding(dp(2), dp(2), dp(2), dp(2))
                background = roundedBg(Color.BLACK, 16f, BORDER, 1)
            }

            playerView = PlayerView(this@MainActivity).apply {
                useController = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                setShutterBackgroundColor(Color.BLACK)
                setBackgroundColor(Color.BLACK)
                isFocusable = false
            }
            videoFrame.addView(playerView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

            val loadingWrap = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setBackgroundColor(Color.argb(110, 0, 0, 0))
            }
            loading = loadingWrap
            loadingWrap.addView(ProgressBar(this@MainActivity).apply { isIndeterminate = true }, LinearLayout.LayoutParams(dp(52), dp(52)))
            loadingText = TextView(this@MainActivity).apply {
                text = "Seleccioná un canal"
                textSize = 15f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                setTypeface(typeface, Typeface.BOLD)
            }
            loadingWrap.addView(loadingText, LinearLayout.LayoutParams(dp(420), dp(46)).apply { topMargin = dp(8) })
            videoFrame.addView(loadingWrap, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

            videoHud = buildPlaybackHud()
            videoFrame.addView(videoHud, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))

            fullscreenButton = Button(this@MainActivity).apply {
                text = "PANTALLA COMPLETA"
                textSize = 11f
                isAllCaps = false
                isFocusable = true
                setTextColor(Color.WHITE)
                background = roundedBg(Color.argb(225, 18, 28, 45), 9f, BORDER, 1)
                setOnClickListener { if (lastPlayed != null && lastPlayed?.section != ContentSection.RADIO) enterFullscreen() }
                setOnFocusChangeListener { v, focused ->
                    val b = v as Button
                    b.background = roundedBg(if (focused) ACCENT else Color.argb(225, 18, 28, 45), 9f, if (focused) ACCENT else BORDER, 1)
                }
            }
            videoFrame.addView(fullscreenButton, FrameLayout.LayoutParams(dp(174), dp(40), Gravity.TOP or Gravity.END).apply {
                topMargin = dp(12)
                marginEnd = dp(12)
            })

            fullscreenChannelPanel = buildFullscreenChannelPanel()
            videoFrame.addView(fullscreenChannelPanel, FrameLayout.LayoutParams(dp(390), ViewGroup.LayoutParams.MATCH_PARENT, Gravity.START))

            addView(videoFrame, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.68f))

            infoCard = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(20), dp(16), dp(20), dp(14))
                background = roundedBg(PANEL_ALT, 14f, BORDER, 1)
            }
            infoTitle = TextView(this@MainActivity).apply {
                text = "TV FULL PRO"
                textSize = 20f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 1
            }
            infoBody = TextView(this@MainActivity).apply {
                text = "Elegí una categoría y un canal."
                textSize = 14f
                setTextColor(MUTED)
                setPadding(0, dp(8), 0, 0)
                maxLines = 6
            }
            infoCard.addView(infoTitle)
            infoCard.addView(infoBody)
            addView(infoCard, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.32f).apply { topMargin = dp(10) })
        }
    }

    private fun buildPlaybackHud(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(12), dp(18), dp(12))
            setBackgroundColor(Color.argb(220, 4, 7, 12))
            visibility = View.GONE

            val header = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            hudLogo = ImageView(this@MainActivity).apply {
                scaleType = ImageView.ScaleType.CENTER_INSIDE
                setBackgroundColor(Color.rgb(18, 25, 37))
            }
            header.addView(hudLogo, LinearLayout.LayoutParams(dp(54), dp(54)).apply { marginEnd = dp(12) })

            hudBadge = TextView(this@MainActivity).apply {
                text = "LIVE"
                textSize = 12f
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                background = roundedBg(LIVE_GREEN, 7f)
            }
            header.addView(hudBadge, LinearLayout.LayoutParams(dp(82), dp(32)).apply { marginEnd = dp(12) })

            val titles = LinearLayout(this@MainActivity).apply { orientation = LinearLayout.VERTICAL }
            hudTitle = TextView(this@MainActivity).apply {
                textSize = 19f
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 1
            }
            hudSubtitle = TextView(this@MainActivity).apply {
                textSize = 13f
                setTextColor(Color.rgb(205, 213, 224))
                maxLines = 1
            }
            titles.addView(hudTitle)
            titles.addView(hudSubtitle)
            header.addView(titles, LinearLayout.LayoutParams(0, dp(54), 1f))
            addView(header, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(56)))

            liveEpgRow = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                visibility = View.GONE
            }
            liveEpgStart = timeText()
            liveEpgEnd = timeText()
            liveEpgProgress = SeekBar(this@MainActivity).apply {
                max = 1000
                isEnabled = false
                isFocusable = false
            }
            liveEpgRow.addView(liveEpgStart, LinearLayout.LayoutParams(dp(58), dp(32)))
            liveEpgRow.addView(liveEpgProgress, LinearLayout.LayoutParams(0, dp(32), 1f))
            liveEpgRow.addView(liveEpgEnd, LinearLayout.LayoutParams(dp(58), dp(32)))
            addView(liveEpgRow, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(34)))

            vodProgressRow = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                visibility = View.GONE
            }
            vodCurrent = timeText()
            vodDuration = timeText()
            vodProgress = SeekBar(this@MainActivity).apply {
                max = 1000
                isEnabled = false
                isFocusable = false
            }
            vodProgressRow.addView(vodCurrent, LinearLayout.LayoutParams(dp(72), dp(38)))
            vodProgressRow.addView(vodProgress, LinearLayout.LayoutParams(0, dp(38), 1f))
            vodProgressRow.addView(vodDuration, LinearLayout.LayoutParams(dp(72), dp(38)))
            addView(vodProgressRow, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(40)))

            hudHint = TextView(this@MainActivity).apply {
                textSize = 11f
                setTextColor(MUTED)
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                maxLines = 1
            }
            addView(hudHint, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(24)))
        }
    }

    private fun timeText(): TextView = TextView(this).apply {
        text = "00:00"
        textSize = 12f
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER
    }

    private fun buildFullscreenChannelPanel(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(16), dp(12), dp(12))
            setBackgroundColor(Color.argb(242, 8, 13, 22))
            visibility = View.GONE

            fullscreenChannelTitle = TextView(this@MainActivity).apply {
                text = "CANALES"
                textSize = 18f
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 1
            }
            addView(fullscreenChannelTitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(34)))
            addView(TextView(this@MainActivity).apply {
                text = "↑ ↓ navegar · OK cambiar · BACK cerrar"
                textSize = 11f
                setTextColor(MUTED)
                maxLines = 1
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(28)))

            fullscreenChannelRecycler = RecyclerView(this@MainActivity).apply {
                setBackgroundColor(Color.TRANSPARENT)
                setPadding(0, dp(5), 0, 0)
                clipToPadding = false
                clipChildren = false
                isVerticalScrollBarEnabled = false
                setItemViewCacheSize(2)
            }
            addView(fullscreenChannelRecycler, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        }
    }

    private fun sectionButton(section: ContentSection, label: String): Button {
        return navButton(label) { showCategories(section) }.also { sectionButtons[section] = it }
    }

    private fun navButton(label: String, action: () -> Unit): Button {
        return Button(this).apply {
            text = label
            textSize = 12f
            isAllCaps = false
            isFocusable = true
            setTextColor(TEXT)
            background = roundedBg(Color.TRANSPARENT, 9f)
            setOnClickListener { action() }
            setOnFocusChangeListener { v, focused ->
                val b = v as Button
                b.background = roundedBg(if (focused) ACCENT else Color.TRANSPARENT, 9f)
                b.setTextColor(Color.WHITE)
            }
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(45)).apply { bottomMargin = dp(4) }
        }
    }

    private fun showCategories(section: ContentSection) {
        if (lastPlayed != null && lastPlayed?.section != section) stopPlayback(clearItem = true)
        currentSection = section
        browseLevel = BrowseLevel.CATEGORIES
        selectedCategory = null
        currentItems = emptyList()
        seriesItemsBeforeEpisodes = emptyList()
        sectionTitle.text = sectionLabel(section)
        browseTitle.text = "${sectionLabel(section)} · CATEGORÍAS"
        browseSubtitle.text = "Elegí una categoría para continuar"
        sectionButtons.forEach { (s, b) ->
            b.background = roundedBg(if (s == section) Color.rgb(74, 18, 27) else Color.TRANSPARENT, 9f)
        }

        configurePanelsForCategories(section)
        browseRecycler.adapter = null
        browseRecycler.layoutManager = verticalLayoutManager()
        infoTitle.text = sectionLabel(section)
        infoBody.text = "Cargando categorías…"

        io.execute {
            val result = runCatching { repository.loadCategories(section) }
            runOnUiThread {
                result.onSuccess { cats ->
                    categoryAdapter = CategoryAdapter(cats) { category -> showItems(category) }
                    browseRecycler.adapter = categoryAdapter
                    browseSubtitle.text = "${cats.size} categorías"
                    infoBody.text = if (cats.size <= 1) "No hay contenido disponible en esta sección." else "Elegí una categoría para continuar."
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
        browseRecycler.adapter = null

        if (currentSection == ContentSection.LIVE || currentSection == ContentSection.RADIO) {
            configurePanelsForLiveItems()
            browseRecycler.layoutManager = verticalLayoutManager()
            infoTitle.text = category.name
            infoBody.text = "Cargando…"
        } else {
            configurePanelsForLibraryItems()
            browseRecycler.layoutManager = gridLayoutManager(5)
        }

        io.execute {
            val result = runCatching { repository.loadItems(currentSection, category.id) }
            runOnUiThread {
                result.onSuccess { list ->
                    currentItems = list
                    if (currentSection == ContentSection.SERIES) seriesItemsBeforeEpisodes = list
                    contentAdapter = ContentAdapter(list, grid = currentSection == ContentSection.MOVIES || currentSection == ContentSection.SERIES)
                    browseRecycler.adapter = contentAdapter
                    browseSubtitle.text = "${list.size} elementos · BACK para volver"
                    if (currentSection == ContentSection.LIVE || currentSection == ContentSection.RADIO) {
                        infoBody.text = if (list.isEmpty()) "No hay contenido en esta categoría." else "${list.size} disponibles"
                    }
                    focusFirst()
                }.onFailure { showCatalogError(it.message) }
            }
        }
    }

    private fun showEpisodes(series: ContentItem) {
        browseLevel = BrowseLevel.EPISODES
        browseTitle.text = series.name
        browseSubtitle.text = "Cargando episodios…"
        configurePanelsForLibraryItems()
        browseRecycler.adapter = null
        browseRecycler.layoutManager = verticalLayoutManager()

        io.execute {
            val result = runCatching { repository.loadSeriesEpisodes(series.seriesId) }
            runOnUiThread {
                result.onSuccess { episodes ->
                    currentItems = episodes
                    contentAdapter = ContentAdapter(episodes, grid = false)
                    browseRecycler.adapter = contentAdapter
                    browseSubtitle.text = "${episodes.size} episodios · BACK para volver"
                    focusFirst()
                }.onFailure { showCatalogError(it.message) }
            }
        }
    }

    private fun restoreSeriesGrid() {
        browseLevel = BrowseLevel.ITEMS
        currentItems = seriesItemsBeforeEpisodes
        browseTitle.text = "SERIES · ${selectedCategory?.name.orEmpty()}"
        browseSubtitle.text = "${currentItems.size} series · BACK para volver"
        configurePanelsForLibraryItems()
        browseRecycler.layoutManager = gridLayoutManager(5)
        contentAdapter = ContentAdapter(currentItems, grid = true)
        browseRecycler.adapter = contentAdapter
        focusFirst()
    }

    private fun openItem(item: ContentItem) {
        if (item.section == ContentSection.SERIES && item.url.isBlank() && item.seriesId.isNotBlank()) {
            showEpisodes(item)
            return
        }
        if (item.url.isBlank()) return

        when (item.section) {
            ContentSection.LIVE -> {
                if (lastPlayed?.id == item.id && player?.isPlaying == true) enterFullscreen()
                else startPlayback(item, reconnect = false)
            }
            ContentSection.RADIO -> startPlayback(item, reconnect = false)
            ContentSection.MOVIES, ContentSection.SERIES -> {
                startPlayback(item, reconnect = false)
                enterFullscreen()
            }
        }
    }

    private fun showItemInfo(item: ContentItem) {
        if ((currentSection != ContentSection.LIVE && currentSection != ContentSection.RADIO) || !::infoTitle.isInitialized) return
        infoTitle.text = item.name
        infoBody.text = if (item.section == ContentSection.RADIO) "Radio en vivo" else "Canal ${item.id}"
        if (item.section == ContentSection.LIVE) loadEpg(item)
    }

    private fun loadEpg(item: ContentItem) {
        io.execute {
            val epg = repository.loadShortEpg(item.id)
            val current = epg.firstOrNull()
            runOnUiThread {
                if (lastPlayed?.id == item.id) {
                    currentEpg = current
                    if (::videoHud.isInitialized && videoHud.visibility == View.VISIBLE) showPlaybackHud()
                }
                if (infoTitle.text.toString() == item.name && epg.isNotEmpty()) {
                    infoBody.text = epg.joinToString("\n\n") { e ->
                        buildString {
                            append(e.title.ifBlank { "Programa" })
                            if (e.start.isNotBlank()) append("\n${e.start}  →  ${e.end}")
                        }
                    }
                }
            }
        }
    }

    private fun configurePanelsForCategories(section: ContentSection) {
        browsePanel.visibility = View.VISIBLE
        val liveLike = section == ContentSection.LIVE || section == ContentSection.RADIO
        rightPanel.visibility = if (liveLike) View.VISIBLE else View.GONE
        val lp = browsePanel.layoutParams as LinearLayout.LayoutParams
        if (liveLike) {
            lp.width = dp(390)
            lp.weight = 0f
            lp.marginEnd = dp(10)
        } else {
            lp.width = 0
            lp.weight = 1f
            lp.marginEnd = 0
        }
        browsePanel.layoutParams = lp
    }

    private fun configurePanelsForLiveItems() {
        rightPanel.visibility = View.VISIBLE
        val lp = browsePanel.layoutParams as LinearLayout.LayoutParams
        lp.width = dp(405)
        lp.weight = 0f
        lp.marginEnd = dp(10)
        browsePanel.layoutParams = lp
    }

    private fun configurePanelsForLibraryItems() {
        rightPanel.visibility = View.GONE
        val lp = browsePanel.layoutParams as LinearLayout.LayoutParams
        lp.width = 0
        lp.weight = 1f
        lp.marginEnd = 0
        browsePanel.layoutParams = lp
    }

    private fun verticalLayoutManager(): LinearLayoutManager = LinearLayoutManager(this).apply { isItemPrefetchEnabled = false }
    private fun gridLayoutManager(spanCount: Int): GridLayoutManager = GridLayoutManager(this, spanCount).apply { isItemPrefetchEnabled = false }

    private fun focusFirst() {
        browseRecycler.post {
            browseRecycler.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() ?: browseRecycler.requestFocus()
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
            .setUserAgent("TV-FULL-PRO/1.5 AndroidTV")
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
                        beginBufferingDiagnostic()
                        if (waitingFirstFrame && !hasPlayedCurrent) {
                            showLoading("Inicializando…")
                        } else if (isCurrentLiveLike()) {
                            scheduleStallRecovery()
                        } else {
                            showLoading("Cargando…")
                        }
                    }
                    Player.STATE_READY -> {
                        endBufferingDiagnostic()
                        cancelStallRecovery()
                        recoveryPending = false
                        if (isCurrentRadio() && waitingFirstFrame) confirmPlaybackStarted()
                        if (!waitingFirstFrame) hideLoading()
                        restoreLiveBadgeIfNeeded()
                    }
                    Player.STATE_ENDED -> {
                        endBufferingDiagnostic()
                        cancelStallRecovery()
                        if (isCurrentLiveLike()) scheduleLiveRecovery("Fin inesperado del stream", hard = true)
                        else showLoading("Finalizado")
                    }
                    Player.STATE_IDLE -> Unit
                }
            }

            override fun onRenderedFirstFrame() {
                confirmPlaybackStarted()
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                diagnostics.width = videoSize.width
                diagnostics.height = videoSize.height
            }

            override fun onPlayerError(error: PlaybackException) {
                endBufferingDiagnostic()
                cancelStallRecovery()
                diagnostics.lastError = "${PlaybackException.getErrorCodeName(error.errorCode)} ${error.message.orEmpty()}".trim()
                logDiagnostics("player_error")
                if (isCurrentLiveLike()) {
                    val status = httpStatus(error)
                    if (status == 401 || status == 403 || status == 404 || status == 410) {
                        markCurrentUnavailable("HTTP $status")
                    } else {
                        scheduleLiveRecovery("Error recuperable", hard = false)
                    }
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
        val p = player ?: run {
            initPlayer()
            player ?: return
        }

        if (!reconnect) {
            recoveryAttempts = 0
            diagnostics = PlaybackDiagnostics(transport = transportOf(item.url))
            hasPlayedCurrent = false
        }
        lastPlayed = item
        currentEpg = null
        waitingFirstFrame = true
        recoveryPending = false
        startupToken++
        reconnectToken++
        cancelStallRecovery()
        val token = startupToken

        showLoading(if (reconnect) "Reconectando…" else "Inicializando…")
        p.stop()
        p.clearMediaItems()
        p.setMediaItem(MediaItem.fromUri(item.url))
        p.prepare()
        p.playWhenReady = true
        if (item.section == ContentSection.LIVE) loadEpg(item)

        val timeout = if (reconnect) LIVE_RECONNECT_STARTUP_TIMEOUT_MS else LIVE_STARTUP_TIMEOUT_MS
        handler.postDelayed({
            if (token == startupToken && waitingFirstFrame && lastPlayed?.url == item.url) {
                if (isCurrentLiveLike()) scheduleLiveRecovery("Inicio sin señal", hard = false)
                else {
                    p.stop()
                    waitingFirstFrame = false
                    showLoading("No se pudo iniciar")
                }
            }
        }, timeout)
    }

    private fun confirmPlaybackStarted() {
        waitingFirstFrame = false
        hasPlayedCurrent = true
        recoveryAttempts = 0
        recoveryPending = false
        cancelStallRecovery()
        hideLoading()
        showPlaybackHud()
        logDiagnostics("playback_confirmed")
    }

    private fun scheduleStallRecovery() {
        if (!isCurrentLiveLike() || waitingFirstFrame) return
        stallToken++
        val token = stallToken

        handler.postDelayed({
            if (token == stallToken && player?.playbackState == Player.STATE_BUFFERING && isCurrentLiveLike() && !waitingFirstFrame) {
                showLiveRecoveryHud()
            }
        }, LIVE_REBUFFER_NOTICE_MS)

        val stallLimit = stallLimitFor(lastPlayed?.url.orEmpty())
        handler.postDelayed({
            if (token == stallToken && player?.playbackState == Player.STATE_BUFFERING && isCurrentLiveLike() && !waitingFirstFrame) {
                scheduleLiveRecovery("Buffering prolongado", hard = false)
            }
        }, stallLimit)
    }

    private fun cancelStallRecovery() {
        stallToken++
    }

    private fun scheduleLiveRecovery(reason: String, hard: Boolean) {
        val item = lastPlayed ?: return
        if (!isCurrentLiveLike() || recoveryPending) return
        if (recoveryAttempts >= LIVE_MAX_RECOVERIES) {
            markCurrentUnavailable("Máximo de recuperaciones")
            return
        }

        recoveryAttempts++
        diagnostics.recoveries++
        recoveryPending = true
        reconnectToken++
        val token = reconnectToken
        cancelStallRecovery()
        showLiveRecoveryHud()
        infoTitle.text = item.name
        infoBody.text = "$reason · recuperación $recoveryAttempts de $LIVE_MAX_RECOVERIES"

        val delay = when (recoveryAttempts) {
            1 -> 600L
            2 -> 1_200L
            3 -> 2_500L
            else -> 4_000L
        }

        handler.postDelayed({
            if (token != reconnectToken || lastPlayed?.url != item.url) return@postDelayed
            recoveryPending = false
            if (hard || recoveryAttempts >= 3) {
                startPlayback(item, reconnect = true)
            } else {
                softReprepare(item)
            }
        }, delay)
    }

    private fun softReprepare(item: ContentItem) {
        val p = player ?: return
        waitingFirstFrame = true
        startupToken++
        val token = startupToken
        p.prepare()
        p.playWhenReady = true
        handler.postDelayed({
            if (token == startupToken && waitingFirstFrame && lastPlayed?.url == item.url) {
                scheduleLiveRecovery("Reintento suave sin respuesta", hard = true)
            }
        }, LIVE_RECONNECT_STARTUP_TIMEOUT_MS)
    }

    private fun markCurrentUnavailable(reason: String) {
        waitingFirstFrame = false
        recoveryPending = false
        cancelStallRecovery()
        player?.stop()
        showLoading("Canal no disponible")
        diagnostics.lastError = reason
        infoBody.text = reason
        logDiagnostics("unavailable")
    }

    private fun beginBufferingDiagnostic() {
        if (diagnostics.bufferingStartedAt == 0L) {
            diagnostics.bufferingStartedAt = System.currentTimeMillis()
            diagnostics.bufferingCount++
        }
    }

    private fun endBufferingDiagnostic() {
        if (diagnostics.bufferingStartedAt > 0L) {
            diagnostics.bufferingTotalMs += System.currentTimeMillis() - diagnostics.bufferingStartedAt
            diagnostics.bufferingStartedAt = 0L
        }
    }

    private fun logDiagnostics(event: String) {
        Log.i(
            TAG,
            "$event transport=${diagnostics.transport} buffers=${diagnostics.bufferingCount} bufferMs=${diagnostics.bufferingTotalMs} recoveries=${diagnostics.recoveries} video=${diagnostics.width}x${diagnostics.height} error=${diagnostics.lastError}"
        )
    }

    private fun httpStatus(error: PlaybackException): Int? {
        var cause: Throwable? = error
        while (cause != null) {
            if (cause is HttpDataSource.InvalidResponseCodeException) return cause.responseCode
            cause = cause.cause
        }
        return null
    }

    private fun stallLimitFor(url: String): Long {
        val lower = url.lowercase(Locale.ROOT)
        return when {
            lower.contains(".m3u8") -> 35_000L
            lower.contains(".ts") -> 30_000L
            else -> 30_000L
        }
    }

    private fun transportOf(url: String): String {
        val lower = url.lowercase(Locale.ROOT)
        return when {
            lower.contains(".m3u8") -> "HLS"
            lower.contains(".ts") -> "MPEG-TS"
            lower.contains(".mp4") -> "MP4"
            lower.contains(".mkv") -> "MKV"
            else -> "AUTO"
        }
    }

    private fun isCurrentLive(): Boolean = lastPlayed?.section == ContentSection.LIVE
    private fun isCurrentRadio(): Boolean = lastPlayed?.section == ContentSection.RADIO
    private fun isCurrentLiveLike(): Boolean = isCurrentLive() || isCurrentRadio()

    private fun stopPlayback(clearItem: Boolean) {
        startupToken++
        reconnectToken++
        cancelStallRecovery()
        waitingFirstFrame = false
        hasPlayedCurrent = false
        recoveryPending = false
        recoveryAttempts = 0
        player?.stop()
        player?.clearMediaItems()
        if (clearItem) lastPlayed = null
        currentEpg = null
        hideLoading()
        handler.removeCallbacks(hideHud)
        if (::videoHud.isInitialized) videoHud.visibility = View.GONE
    }

    private fun releasePlayer() {
        startupToken++
        reconnectToken++
        cancelStallRecovery()
        waitingFirstFrame = false
        if (::playerView.isInitialized) playerView.player = null
        player?.release()
        player = null
    }

    private fun showLoading(text: String) {
        if (!::loadingText.isInitialized) return
        loadingText.text = text
        loading.visibility = View.VISIBLE
    }

    private fun hideLoading() {
        if (::loading.isInitialized) loading.visibility = View.GONE
    }

    private fun showPlaybackHud() {
        val item = lastPlayed ?: return
        if (fullscreenChannelListVisible) return

        hudTitle.text = item.name
        hudLogo.setImageDrawable(null)
        if (item.logo.isNotBlank()) imageLoader.load(hudLogo, item.logo, dp(54), dp(54))

        when (item.section) {
            ContentSection.LIVE -> {
                hudBadge.text = "● LIVE"
                hudBadge.background = roundedBg(LIVE_GREEN, 7f)
                hudSubtitle.text = currentEpg?.title?.ifBlank { "EN VIVO" } ?: "EN VIVO"
                hudHint.text = "↓ canales · OK pausa · BACK volver"
                vodProgressRow.visibility = View.GONE
                updateLiveEpgProgress()
            }
            ContentSection.RADIO -> {
                hudBadge.text = "● RADIO"
                hudBadge.background = roundedBg(LIVE_GREEN, 7f)
                hudSubtitle.text = "EN VIVO"
                hudHint.text = "OK pausa · BACK volver"
                liveEpgRow.visibility = View.GONE
                vodProgressRow.visibility = View.GONE
            }
            ContentSection.MOVIES -> {
                hudBadge.text = "PELÍCULA"
                hudBadge.background = roundedBg(ACCENT, 7f)
                hudSubtitle.text = "Reproduciendo"
                hudHint.text = "← -10s · → +10s · OK pausa/reanuda · BACK volver"
                liveEpgRow.visibility = View.GONE
                vodProgressRow.visibility = View.VISIBLE
                updateVodProgress()
            }
            ContentSection.SERIES -> {
                hudBadge.text = "EPISODIO"
                hudBadge.background = roundedBg(ACCENT, 7f)
                hudSubtitle.text = item.extra.ifBlank { "Reproduciendo" }
                hudHint.text = "← -10s · → +10s · OK pausa/reanuda · BACK volver"
                liveEpgRow.visibility = View.GONE
                vodProgressRow.visibility = View.VISIBLE
                updateVodProgress()
            }
        }
        videoHud.visibility = View.VISIBLE
        handler.removeCallbacks(hideHud)
        if (!waitingFirstFrame) handler.postDelayed(hideHud, HUD_HIDE_MS)
    }

    private fun showLiveRecoveryHud() {
        val item = lastPlayed ?: return
        if (!::videoHud.isInitialized || fullscreenChannelListVisible) return
        hudTitle.text = item.name
        hudBadge.text = "RECUPERANDO"
        hudBadge.background = roundedBg(WARNING, 7f)
        hudSubtitle.text = "Esperando datos sin cerrar la conexión"
        liveEpgRow.visibility = View.GONE
        vodProgressRow.visibility = View.GONE
        hudHint.text = "La reproducción continuará automáticamente"
        videoHud.visibility = View.VISIBLE
        handler.removeCallbacks(hideHud)
    }

    private fun restoreLiveBadgeIfNeeded() {
        if (isCurrentLiveLike() && ::videoHud.isInitialized && videoHud.visibility == View.VISIBLE) {
            showPlaybackHud()
        }
    }

    private fun updateLiveEpgProgress() {
        val epg = currentEpg
        if (epg == null) {
            liveEpgRow.visibility = View.GONE
            return
        }
        val start = parseEpgTime(epg.start)
        val end = parseEpgTime(epg.end)
        if (start == null || end == null || end <= start) {
            liveEpgRow.visibility = View.GONE
            return
        }
        val now = System.currentTimeMillis()
        val progress = (((now - start).toDouble() / (end - start).toDouble()) * 1000.0).toInt().coerceIn(0, 1000)
        liveEpgStart.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(start))
        liveEpgEnd.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(end))
        liveEpgProgress.progress = progress
        liveEpgRow.visibility = View.VISIBLE
    }

    private fun parseEpgTime(value: String): Long? {
        if (value.isBlank()) return null
        val patterns = listOf("yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm")
        for (pattern in patterns) {
            val parsed = runCatching { SimpleDateFormat(pattern, Locale.getDefault()).parse(value)?.time }.getOrNull()
            if (parsed != null) return parsed
        }
        return null
    }

    private fun updateVodProgress() {
        val item = lastPlayed ?: return
        if (item.section == ContentSection.LIVE || item.section == ContentSection.RADIO) return
        val p = player ?: return
        val duration = p.duration
        val position = p.currentPosition.coerceAtLeast(0L)
        vodCurrent.text = formatTime(position)
        if (duration == C.TIME_UNSET || duration <= 0L) {
            vodDuration.text = "--:--"
            vodProgress.progress = 0
        } else {
            vodDuration.text = formatTime(duration)
            vodProgress.progress = ((position.toDouble() / duration.toDouble()) * 1000.0).toInt().coerceIn(0, 1000)
        }
    }

    private fun formatTime(ms: Long): String {
        val total = (ms / 1000L).coerceAtLeast(0L)
        val h = total / 3600L
        val m = (total % 3600L) / 60L
        val s = total % 60L
        return if (h > 0) String.format(Locale.getDefault(), "%d:%02d:%02d", h, m, s)
        else String.format(Locale.getDefault(), "%02d:%02d", m, s)
    }

    private fun seekVod(deltaMs: Long) {
        val item = lastPlayed ?: return
        if (item.section == ContentSection.LIVE || item.section == ContentSection.RADIO) return
        val p = player ?: return
        val duration = p.duration
        val max = if (duration == C.TIME_UNSET || duration <= 0L) Long.MAX_VALUE else duration
        val target = (p.currentPosition + deltaMs).coerceAtLeast(0L).coerceAtMost(max)
        p.seekTo(target)
        showPlaybackHud()
    }

    private fun togglePlayPause() {
        player?.let { if (it.isPlaying) it.pause() else it.play() }
        showPlaybackHud()
    }

    private fun enterFullscreen() {
        if (isFullscreen || lastPlayed == null || lastPlayed?.section == ContentSection.RADIO) return
        isFullscreen = true
        hideFullscreenChannelList(showHudAfter = false)
        immersive()
        topBar.visibility = View.GONE
        navRail.visibility = View.GONE
        browsePanel.visibility = View.GONE
        infoCard.visibility = View.GONE
        fullscreenButton.visibility = View.GONE
        body.setPadding(0, 0, 0, 0)
        rightPanel.visibility = View.VISIBLE
        (rightPanel.layoutParams as LinearLayout.LayoutParams).apply {
            width = 0
            weight = 1f
            marginStart = 0
            marginEnd = 0
        }.also { rightPanel.layoutParams = it }
        (videoFrame.layoutParams as LinearLayout.LayoutParams).apply {
            height = 0
            weight = 1f
            topMargin = 0
            bottomMargin = 0
        }.also { videoFrame.layoutParams = it }
        videoFrame.background = null
        videoFrame.setPadding(0, 0, 0, 0)
        showPlaybackHud()
    }

    private fun exitFullscreen() {
        if (!isFullscreen) return
        hideFullscreenChannelList(showHudAfter = false)
        isFullscreen = false
        topBar.visibility = View.VISIBLE
        navRail.visibility = View.VISIBLE
        fullscreenButton.visibility = View.VISIBLE
        body.setPadding(dp(12), dp(12), dp(12), dp(12))
        videoFrame.background = roundedBg(Color.BLACK, 16f, BORDER, 1)
        videoFrame.setPadding(dp(2), dp(2), dp(2), dp(2))
        (videoFrame.layoutParams as LinearLayout.LayoutParams).apply {
            height = 0
            weight = 0.68f
        }.also { videoFrame.layoutParams = it }
        infoCard.visibility = View.VISIBLE
        (rightPanel.layoutParams as LinearLayout.LayoutParams).apply {
            width = 0
            weight = 1f
        }.also { rightPanel.layoutParams = it }

        when {
            browseLevel == BrowseLevel.CATEGORIES -> configurePanelsForCategories(currentSection)
            currentSection == ContentSection.LIVE || currentSection == ContentSection.RADIO -> configurePanelsForLiveItems()
            else -> configurePanelsForLibraryItems()
        }
        handler.removeCallbacks(hideHud)
        videoHud.visibility = View.GONE
        browseRecycler.post { browseRecycler.requestFocus() }
    }

    private fun showFullscreenChannelList() {
        if (!isFullscreen || !isCurrentLive() || currentItems.isEmpty()) return
        fullscreenChannelListVisible = true
        handler.removeCallbacks(hideHud)
        videoHud.visibility = View.GONE
        fullscreenChannelTitle.text = selectedCategory?.name?.let { "CANALES · $it" } ?: "CANALES"
        fullscreenChannelRecycler.layoutManager = verticalLayoutManager()
        fullscreenChannelAdapter = ContentAdapter(
            data = currentItems,
            grid = false,
            clickOverride = { item ->
                startPlayback(item, reconnect = false)
                hideFullscreenChannelList(showHudAfter = true)
            },
            showFocusInfo = false
        )
        fullscreenChannelRecycler.adapter = fullscreenChannelAdapter
        fullscreenChannelPanel.visibility = View.VISIBLE

        val index = currentItems.indexOfFirst { it.id == lastPlayed?.id }.coerceAtLeast(0)
        fullscreenChannelRecycler.scrollToPosition(index)
        fullscreenChannelRecycler.post {
            fullscreenChannelRecycler.findViewHolderForAdapterPosition(index)?.itemView?.requestFocus() ?: fullscreenChannelRecycler.requestFocus()
        }
    }

    private fun hideFullscreenChannelList(showHudAfter: Boolean = true) {
        if (!::fullscreenChannelPanel.isInitialized) return
        fullscreenChannelListVisible = false
        fullscreenChannelPanel.visibility = View.GONE
        fullscreenChannelRecycler.adapter = null
        fullscreenChannelAdapter = null
        if (showHudAfter && isFullscreen) showPlaybackHud()
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
                    val source = categoryAdapter?.allItems.orEmpty()
                    browseRecycler.adapter = CategoryAdapter(source.filter { q.isBlank() || it.name.lowercase(Locale.getDefault()).contains(q) }) { showItems(it) }
                } else {
                    val source = currentItems
                    contentAdapter = ContentAdapter(
                        source.filter { q.isBlank() || it.name.lowercase(Locale.getDefault()).contains(q) },
                        grid = (currentSection == ContentSection.MOVIES || currentSection == ContentSection.SERIES) && browseLevel != BrowseLevel.EPISODES
                    )
                    browseRecycler.adapter = contentAdapter
                }
                focusFirst()
            }
            .setNegativeButton("CANCELAR", null)
            .show()
    }

    private fun openPlaylistSelector() {
        stopPlayback(clearItem = true)
        if (RemotePrefs.loadServices(this).isNotEmpty()) {
            startActivity(Intent(this, PlaylistActivity::class.java))
            finish()
        } else {
            startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
            finish()
        }
    }

    private fun showSettings(config: SourceConfig) {
        val source = if (config.mode == SourceMode.M3U) "M3U" else "Xtream"
        val code = RemotePrefs.loadCredentials(this)?.code ?: "Sin código remoto"
        val service = RemotePrefs.serviceName(this).ifBlank { "Sin nombre" }
        val diag = "Buffering: ${diagnostics.bufferingCount} · ${diagnostics.bufferingTotalMs / 1000.0}s\n" +
            "Recuperaciones: ${diagnostics.recoveries} · Transporte: ${diagnostics.transport}\n" +
            "Video: ${diagnostics.width}x${diagnostics.height}\n" +
            "Último error: ${diagnostics.lastError.ifBlank { "ninguno" }}"
        AlertDialog.Builder(this)
            .setTitle("TV FULL PRO")
            .setMessage("Fuente: $source\nLista: $service\nDispositivo: $code\n\nReproductor: Media3 / ExoPlayer\n\nDiagnóstico actual\n$diag")
            .setPositiveButton("SINCRONIZAR PANEL") { _, _ ->
                startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
                finish()
            }
            .setNeutralButton("CONFIGURACIÓN MANUAL") { _, _ ->
                startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
                finish()
            }
            .setNegativeButton("CERRAR", null)
            .show()
    }

    private fun showCatalogError(message: String?) {
        browseSubtitle.text = message ?: "Error de red o formato"
        if (::infoTitle.isInitialized) {
            infoTitle.text = "No se pudo cargar"
            infoBody.text = message ?: "Error de red o formato"
        }
    }

    private fun updateClock() {
        if (::clock.isInitialized) clock.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        handler.postDelayed({ updateClock() }, 30_000)
    }

    private fun sectionLabel(section: ContentSection): String = when (section) {
        ContentSection.LIVE -> "TV EN VIVO"
        ContentSection.MOVIES -> "PELÍCULAS"
        ContentSection.SERIES -> "SERIES"
        ContentSection.RADIO -> "RADIO"
    }

    private fun goLogin() {
        startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
        finish()
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
        if (event.action == KeyEvent.ACTION_DOWN) {
            if (isFullscreen && !fullscreenChannelListVisible) {
                when (event.keyCode) {
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        if (!isCurrentLiveLike()) seekVod(-VOD_SEEK_MS) else showPlaybackHud()
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        if (!isCurrentLiveLike()) seekVod(VOD_SEEK_MS) else showPlaybackHud()
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_UP -> {
                        showPlaybackHud()
                        return true
                    }
                }
            }

            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK -> {
                    when {
                        fullscreenChannelListVisible -> hideFullscreenChannelList(showHudAfter = true)
                        isFullscreen && !isCurrentLiveLike() -> {
                            stopPlayback(clearItem = true)
                            exitFullscreen()
                        }
                        isFullscreen -> exitFullscreen()
                        browseLevel == BrowseLevel.EPISODES -> restoreSeriesGrid()
                        browseLevel == BrowseLevel.ITEMS -> showCategories(currentSection)
                        else -> sectionButtons[currentSection]?.requestFocus()
                    }
                    return true
                }
                KeyEvent.KEYCODE_DPAD_DOWN -> if (isFullscreen && isCurrentLive() && !fullscreenChannelListVisible) {
                    showFullscreenChannelList()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER -> if (isFullscreen && !fullscreenChannelListVisible) {
                    togglePlayPause()
                    return true
                }
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> if (isFullscreen) {
                    togglePlayPause()
                    return true
                }
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

    private fun roundedBg(fill: Int, radiusDp: Float, stroke: Int? = null, strokeDp: Int = 0): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dp(radiusDp.toInt()).toFloat()
            if (stroke != null && strokeDp > 0) setStroke(dp(strokeDp), stroke)
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private inner class CategoryAdapter(
        val allItems: List<TvCategory>,
        private val click: (TvCategory) -> Unit
    ) : RecyclerView.Adapter<CategoryAdapter.Holder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
            val text = TextView(parent.context).apply {
                textSize = 17f
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(18), 0, dp(14), 0)
                setTextColor(TEXT)
                isFocusable = true
                maxLines = 1
                background = roundedBg(CARD, 10f, BORDER, 1)
                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(58)).apply { bottomMargin = dp(7) }
            }
            return Holder(text)
        }

        override fun onBindViewHolder(holder: Holder, position: Int) {
            val item = allItems[position]
            holder.text.text = if (item.count > 0) "${item.name}   ·   ${item.count}" else item.name
            holder.text.setOnClickListener { click(item) }
            holder.text.setOnFocusChangeListener { v, focused ->
                val t = v as TextView
                t.background = roundedBg(if (focused) ACCENT else CARD, 10f, if (focused) ACCENT else BORDER, 1)
                t.setTextColor(Color.WHITE)
            }
        }

        override fun getItemCount(): Int = allItems.size
        inner class Holder(val text: TextView) : RecyclerView.ViewHolder(text)
    }

    private inner class ContentAdapter(
        private val data: List<ContentItem>,
        private val grid: Boolean,
        private val clickOverride: ((ContentItem) -> Unit)? = null,
        private val showFocusInfo: Boolean = true
    ) : RecyclerView.Adapter<ContentAdapter.Holder>() {

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
            return if (grid) createGridHolder(parent) else createListHolder(parent)
        }

        private fun createListHolder(parent: ViewGroup): Holder {
            val row = LinearLayout(parent.context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(8), dp(6), dp(12), dp(6))
                isFocusable = true
                background = roundedBg(CARD, 10f, BORDER, 1)
                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(70)).apply { bottomMargin = dp(7) }
            }
            val image = ImageView(parent.context).apply {
                scaleType = ImageView.ScaleType.CENTER_INSIDE
                setBackgroundColor(Color.rgb(16, 24, 38))
            }
            row.addView(image, LinearLayout.LayoutParams(dp(56), dp(56)).apply { marginEnd = dp(12) })
            val text = TextView(parent.context).apply {
                textSize = 17f
                gravity = Gravity.CENTER_VERTICAL
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 2
            }
            row.addView(text, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
            return Holder(row, image, text, grid = false)
        }

        private fun createGridHolder(parent: ViewGroup): Holder {
            val card = LinearLayout(parent.context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(dp(7), dp(7), dp(7), dp(8))
                isFocusable = true
                background = roundedBg(CARD, 11f, BORDER, 1)
                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(250)).apply {
                    setMargins(dp(5), dp(5), dp(5), dp(5))
                }
            }
            val image = ImageView(parent.context).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                setBackgroundColor(Color.rgb(16, 24, 38))
            }
            card.addView(image, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(190)))
            val text = TextView(parent.context).apply {
                textSize = 14f
                gravity = Gravity.CENTER_VERTICAL
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 2
                setPadding(dp(3), dp(6), dp(3), 0)
            }
            card.addView(text, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            return Holder(card, image, text, grid = true)
        }

        override fun onBindViewHolder(holder: Holder, position: Int) {
            val item = data[position]
            holder.bound = item
            holder.text.text = item.name
            holder.image.setImageDrawable(null)
            holder.image.visibility = if (!holder.grid && item.logo.isBlank() && browseLevel == BrowseLevel.EPISODES) View.GONE else View.VISIBLE
            holder.root.setOnClickListener { clickOverride?.invoke(item) ?: openItem(item) }
            holder.root.setOnFocusChangeListener { v, focused ->
                v.background = roundedBg(if (focused) ACCENT else CARD, if (holder.grid) 11f else 10f, if (focused) ACCENT else BORDER, 1)
                if (focused && showFocusInfo) showItemInfo(item)
            }
        }

        override fun onViewAttachedToWindow(holder: Holder) {
            super.onViewAttachedToWindow(holder)
            val item = holder.bound ?: return
            val url = item.logo
            if (url.isBlank()) return
            if (holder.grid) imageLoader.load(holder.image, url, dp(150), dp(190))
            else imageLoader.load(holder.image, url, dp(56), dp(56))
        }

        override fun onViewDetachedFromWindow(holder: Holder) {
            imageLoader.cancel(holder.image)
            super.onViewDetachedFromWindow(holder)
        }

        override fun onViewRecycled(holder: Holder) {
            imageLoader.cancel(holder.image)
            holder.bound = null
            holder.image.setImageDrawable(null)
            super.onViewRecycled(holder)
        }

        override fun getItemCount(): Int = data.size

        inner class Holder(
            val root: LinearLayout,
            val image: ImageView,
            val text: TextView,
            val grid: Boolean
        ) : RecyclerView.ViewHolder(root) {
            var bound: ContentItem? = null
        }
    }
}
