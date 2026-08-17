package com.tvfull.pro

import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.tvfull.pro.tvcore.CatalogItem
import com.tvfull.pro.tvcore.CatalogSyncEngine
import com.tvfull.pro.tvcore.DecoderMode
import com.tvfull.pro.tvcore.IjkPlaybackEngine
import com.tvfull.pro.tvcore.PlaybackPolicy
import com.tvfull.pro.tvcore.PlaybackSourceResolver
import com.tvfull.pro.tvcore.ProvisionedSource
import com.tvfull.pro.tvcore.TvCatalogDatabase
import java.util.concurrent.Executors

class TvIptvActivity : AppCompatActivity(), SurfaceHolder.Callback {
    companion object {
        private val BG = Color.rgb(7, 11, 18)
        private val TOP = Color.rgb(11, 17, 27)
        private val PANEL = Color.rgb(14, 23, 36)
        private val CARD = Color.rgb(19, 31, 48)
        private val BORDER = Color.rgb(43, 61, 86)
        private val BLUE = Color.rgb(22, 168, 255)
        private val GOLD = Color.rgb(228, 185, 79)
        private val TEXT = Color.rgb(244, 247, 251)
        private val MUTED = Color.rgb(146, 161, 183)
        private val GREEN = Color.rgb(76, 206, 127)
        private val RED = Color.rgb(238, 84, 92)
    }

    private enum class BrowseLevel { CATEGORIES, ITEMS, EPISODES }

    private val io = Executors.newFixedThreadPool(3)
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var database: TvCatalogDatabase
    private lateinit var source: ProvisionedSource
    private lateinit var player: IjkPlaybackEngine
    private val resolver = PlaybackSourceResolver()

    private lateinit var root: LinearLayout
    private lateinit var topBar: LinearLayout
    private lateinit var body: LinearLayout
    private lateinit var navRail: LinearLayout
    private lateinit var browsePanel: LinearLayout
    private lateinit var videoPanel: LinearLayout
    private lateinit var browseTitle: TextView
    private lateinit var browseSubtitle: TextView
    private lateinit var recycler: RecyclerView
    private lateinit var surfaceFrame: FrameLayout
    private lateinit var surfaceView: SurfaceView
    private lateinit var loading: LinearLayout
    private lateinit var loadingText: TextView
    private lateinit var playerTitle: TextView
    private lateinit var playerStatus: TextView
    private lateinit var playerInfo: TextView
    private lateinit var fullscreenButton: Button

    private var surfaceReady = false
    private var currentSection = ContentSection.LIVE
    private var browseLevel = BrowseLevel.CATEGORIES
    private var currentCategoryId = ""
    private var currentItems: List<CatalogItem> = emptyList()
    private var selectedSeries: CatalogItem? = null
    private var pendingPlay: CatalogItem? = null
    private var playingItem: CatalogItem? = null
    private var isFullscreen = false
    private var lastVideoWidth = 0
    private var lastVideoHeight = 0
    private var playerGeneration = 0L

    private val watchdog = object : Runnable {
        override fun run() {
            verifyPanelState()
            handler.postDelayed(this, 15_000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        immersive()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val serviceId = RemotePrefs.selectedServiceId(this)
        val remoteService = RemotePrefs.loadServices(this).firstOrNull { it.id == serviceId }
        if (remoteService == null) {
            goProvisioning()
            return
        }
        source = ProvisionedSource(remoteService.id, remoteService.name, remoteService.config, remoteService.expiresAt)
        database = TvCatalogDatabase(applicationContext)
        player = IjkPlaybackEngine()

        setContentView(buildUi())
        showCategories(ContentSection.LIVE)
        handler.post(watchdog)
    }

    private fun buildUi(): View {
        val widthDp = resources.configuration.screenWidthDp.coerceAtLeast(320)
        val railWidth = (widthDp * 0.14f).toInt().coerceIn(108, 170)
        val browseWidth = (widthDp * 0.32f).toInt().coerceIn(260, 410)

        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(BG)
        }

        topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), 0, dp(18), 0)
            setBackgroundColor(TOP)

            addView(TextView(this@TvIptvActivity).apply {
                text = "TV FULL"
                textSize = 23f
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
            }, LinearLayout.LayoutParams(dp(150), ViewGroup.LayoutParams.MATCH_PARENT).apply { gravity = Gravity.CENTER_VERTICAL })

            addView(TextView(this@TvIptvActivity).apply {
                text = source.serviceName
                textSize = 14f
                gravity = Gravity.CENTER_VERTICAL
                setTextColor(MUTED)
                maxLines = 1
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))

            addView(TextView(this@TvIptvActivity).apply {
                text = "IJK · FFmpeg"
                textSize = 12f
                gravity = Gravity.CENTER
                setTextColor(GOLD)
                background = rounded(Color.rgb(28, 34, 38), 9f, Color.rgb(91, 76, 42), 1)
                setPadding(dp(12), dp(5), dp(12), dp(5))
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        root.addView(topBar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(60)))

        body = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(10), dp(10), dp(10), dp(10))
        }
        root.addView(body, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        navRail = buildNavigation()
        body.addView(navRail, LinearLayout.LayoutParams(dp(railWidth), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(9) })

        browsePanel = buildBrowser()
        body.addView(browsePanel, LinearLayout.LayoutParams(dp(browseWidth), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(9) })

        videoPanel = buildPlayerPanel()
        body.addView(videoPanel, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))

        return root
    }

    private fun buildNavigation(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.TOP
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = rounded(PANEL, 12f, BORDER, 1)

            addView(navButton("TV EN VIVO", ContentSection.LIVE))
            addView(navButton("PELÍCULAS", ContentSection.MOVIES))
            addView(navButton("SERIES", ContentSection.SERIES))
            addView(navButton("RADIO", ContentSection.RADIO))

            addView(View(this@TvIptvActivity), LinearLayout.LayoutParams(1, 0, 1f))

            addView(simpleButton("CAMBIAR LISTA") {
                stopPlayback()
                startActivity(Intent(this@TvIptvActivity, PlaylistActivity::class.java))
                finish()
            })
        }
    }

    private fun navButton(label: String, section: ContentSection): Button {
        return simpleButton(label) { showCategories(section) }.apply {
            tag = section
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(54)).apply { bottomMargin = dp(7) }
        }
    }

    private fun simpleButton(label: String, action: () -> Unit): Button = Button(this).apply {
        text = label
        textSize = 12f
        isAllCaps = false
        isFocusable = true
        setTextColor(TEXT)
        background = rounded(CARD, 9f, BORDER, 1)
        setOnClickListener { action() }
        setOnFocusChangeListener { v, focused ->
            (v as Button).apply {
                background = rounded(if (focused) Color.rgb(12, 79, 121) else CARD, 9f, if (focused) BLUE else BORDER, if (focused) 2 else 1)
                setTextColor(Color.WHITE)
            }
        }
    }

    private fun buildBrowser(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(10), dp(10), dp(10))
            background = rounded(PANEL, 12f, BORDER, 1)

            browseTitle = TextView(this@TvIptvActivity).apply {
                text = "TV EN VIVO"
                textSize = 18f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 1
            }
            addView(browseTitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

            browseSubtitle = TextView(this@TvIptvActivity).apply {
                text = "Categorías"
                textSize = 12f
                setTextColor(MUTED)
                setPadding(0, dp(2), 0, dp(6))
            }
            addView(browseSubtitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

            recycler = RecyclerView(this@TvIptvActivity).apply {
                layoutManager = LinearLayoutManager(this@TvIptvActivity)
                isVerticalScrollBarEnabled = false
                setItemViewCacheSize(8)
            }
            addView(recycler, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        }
    }

    private fun buildPlayerPanel(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(9), dp(9), dp(9), dp(9))
            background = rounded(PANEL, 12f, BORDER, 1)

            surfaceFrame = FrameLayout(this@TvIptvActivity).apply {
                setBackgroundColor(Color.BLACK)
                clipChildren = true

                surfaceView = SurfaceView(this@TvIptvActivity).apply {
                    holder.addCallback(this@TvIptvActivity)
                    setBackgroundColor(Color.BLACK)
                }
                addView(surfaceView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.CENTER))

                loading = LinearLayout(this@TvIptvActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    visibility = View.GONE
                    setBackgroundColor(Color.argb(155, 0, 0, 0))
                    addView(ProgressBar(this@TvIptvActivity), LinearLayout.LayoutParams(dp(38), dp(38)))
                    loadingText = TextView(this@TvIptvActivity).apply {
                        text = "Cargando…"
                        textSize = 14f
                        gravity = Gravity.CENTER
                        setTextColor(Color.WHITE)
                        setPadding(dp(8), dp(8), dp(8), 0)
                    }
                    addView(loadingText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
                }
                addView(loading, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            }
            addView(surfaceFrame, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

            val info = LinearLayout(this@TvIptvActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(8), dp(7), dp(4), dp(3))

                val texts = LinearLayout(this@TvIptvActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    playerTitle = TextView(this@TvIptvActivity).apply {
                        text = "Seleccioná un contenido"
                        textSize = 16f
                        setTextColor(TEXT)
                        setTypeface(typeface, Typeface.BOLD)
                        maxLines = 1
                    }
                    addView(playerTitle)
                    playerStatus = TextView(this@TvIptvActivity).apply {
                        text = "El reproductor se inicia sólo al elegir contenido"
                        textSize = 11f
                        setTextColor(MUTED)
                        maxLines = 1
                    }
                    addView(playerStatus)
                    playerInfo = TextView(this@TvIptvActivity).apply {
                        text = ""
                        textSize = 10f
                        setTextColor(Color.rgb(112, 132, 156))
                        maxLines = 1
                    }
                    addView(playerInfo)
                }
                addView(texts, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

                fullscreenButton = simpleButton("PANTALLA COMPLETA") { toggleFullscreen() }
                addView(fullscreenButton, LinearLayout.LayoutParams(dp(175), dp(48)).apply { marginStart = dp(8) })
            }
            addView(info, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
    }

    private fun showCategories(section: ContentSection) {
        currentSection = section
        browseLevel = BrowseLevel.CATEGORIES
        currentCategoryId = ""
        selectedSeries = null
        browseTitle.text = sectionLabel(section)
        val categories = database.categories(source.serviceId, section)
        browseSubtitle.text = "${categories.size} categorías"
        recycler.adapter = CategoryAdapter(categories.map { it.categoryId to it.name })
        recycler.post { recycler.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() }
    }

    private fun showItems(categoryId: String, categoryName: String) {
        browseLevel = BrowseLevel.ITEMS
        currentCategoryId = categoryId
        currentItems = database.items(source.serviceId, currentSection, categoryId)
        browseTitle.text = categoryName
        browseSubtitle.text = "${currentItems.size} contenidos"
        recycler.adapter = ContentAdapter(currentItems)
        recycler.post { recycler.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() }
    }

    private fun openItem(item: CatalogItem) {
        if (currentSection == ContentSection.SERIES && item.playbackUrl.isBlank() && item.seriesId.isNotBlank()) {
            openSeries(item)
            return
        }
        play(item)
    }

    private fun openSeries(series: CatalogItem) {
        selectedSeries = series
        browseSubtitle.text = "Cargando episodios…"
        io.execute {
            val cached = database.seriesEpisodes(source.serviceId, series.seriesId)
            val episodes = if (cached.isNotEmpty()) cached else {
                runCatching { CatalogSyncEngine(database).syncSeriesEpisodes(source, series) }.getOrDefault(emptyList())
            }
            runOnUiThread {
                if (episodes.isEmpty()) {
                    browseSubtitle.text = "No se encontraron episodios"
                    return@runOnUiThread
                }
                browseLevel = BrowseLevel.EPISODES
                currentItems = episodes
                browseTitle.text = series.name
                browseSubtitle.text = "${episodes.size} episodios"
                recycler.adapter = ContentAdapter(episodes)
                recycler.post { recycler.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() }
            }
        }
    }

    private fun play(item: CatalogItem) {
        pendingPlay = item
        playerTitle.text = item.name
        playerStatus.setTextColor(MUTED)
        playerStatus.text = "Preparando fuente…"
        showLoading(if (item.section == ContentSection.LIVE || item.section == ContentSection.RADIO) "Conectando señal…" else "Cargando contenido…")
        if (surfaceReady) startPendingPlayback()
    }

    private fun startPendingPlayback() {
        val item = pendingPlay ?: return
        pendingPlay = null
        val candidate = runCatching { resolver.resolve(item) }.getOrElse {
            hideLoading()
            playerStatus.setTextColor(RED)
            playerStatus.text = it.message ?: "Fuente inválida"
            return
        }

        val resumeMs = if (item.section == ContentSection.MOVIES || item.section == ContentSection.SERIES) {
            database.progress(source.serviceId, item.section, item.itemId)
        } else 0L

        playerGeneration++
        val generation = playerGeneration
        playingItem = item
        playerTitle.text = item.name
        playerInfo.text = "${candidate.containerHint.uppercase()} · URL ${if (candidate.isDirectSource) "directa" else "resuelta"}"

        val policy = PlaybackPolicy(
            decoderMode = DecoderMode.AUTO,
            liveBufferBytes = 30L * 1024L * 1024L,
            vodBufferBytes = 50L * 1024L * 1024L,
            reconnectEnabled = true,
            frameDrop = 1
        )

        runCatching {
            player.open(
                url = candidate.url,
                surfaceHolder = surfaceView.holder,
                section = item.section,
                startPositionMs = resumeMs,
                policy = policy,
                listener = object : IjkPlaybackEngine.Listener {
                    override fun onOpening(url: String, decoderMode: DecoderMode) = runOnUiThread {
                        if (generation != playerGeneration) return@runOnUiThread
                        playerStatus.setTextColor(MUTED)
                        playerStatus.text = "Abriendo · ${decoderLabel(decoderMode)}"
                    }

                    override fun onPrepared(durationMs: Long) = runOnUiThread {
                        if (generation != playerGeneration) return@runOnUiThread
                        playerStatus.text = if (resumeMs > 0L) "Reanudando reproducción…" else "Iniciando…"
                    }

                    override fun onPlaying() = runOnUiThread {
                        if (generation != playerGeneration) return@runOnUiThread
                        hideLoading()
                        playerStatus.setTextColor(GREEN)
                        playerStatus.text = "REPRODUCIENDO · ${decoderLabel(player.decoderMode())}"
                    }

                    override fun onBuffering(started: Boolean, percent: Int) = runOnUiThread {
                        if (generation != playerGeneration) return@runOnUiThread
                        if (started) {
                            playerStatus.setTextColor(GOLD)
                            playerStatus.text = "Buffering · ${percent.coerceIn(0, 100)}%"
                        } else if (player.isPlaying()) {
                            playerStatus.setTextColor(GREEN)
                            playerStatus.text = "REPRODUCIENDO · ${decoderLabel(player.decoderMode())}"
                        }
                    }

                    override fun onVideoSize(width: Int, height: Int) = runOnUiThread {
                        if (generation != playerGeneration) return@runOnUiThread
                        lastVideoWidth = width
                        lastVideoHeight = height
                        playerInfo.text = "$width×$height · ${candidate.containerHint.uppercase()} · ${decoderLabel(player.decoderMode())}"
                        updateVideoAspect()
                    }

                    override fun onDecoderFallback(from: DecoderMode, to: DecoderMode, reason: String) = runOnUiThread {
                        if (generation != playerGeneration) return@runOnUiThread
                        playerStatus.setTextColor(GOLD)
                        playerStatus.text = "Decoder hardware incompatible · probando FFmpeg"
                        showLoading("Cambiando decodificador…")
                    }

                    override fun onCompleted() = runOnUiThread {
                        if (generation != playerGeneration) return@runOnUiThread
                        saveProgress()
                        hideLoading()
                        playerStatus.setTextColor(MUTED)
                        playerStatus.text = "Finalizado"
                    }

                    override fun onError(code: Int, extra: Int, message: String) = runOnUiThread {
                        if (generation != playerGeneration) return@runOnUiThread
                        saveProgress()
                        hideLoading()
                        playerStatus.setTextColor(RED)
                        playerStatus.text = "No se pudo reproducir · $code/$extra"
                    }
                }
            )
        }.onFailure {
            hideLoading()
            playerStatus.setTextColor(RED)
            playerStatus.text = it.message ?: "No se pudo iniciar el reproductor"
        }
    }

    private fun stopPlayback() {
        saveProgress()
        playerGeneration++
        pendingPlay = null
        playingItem = null
        runCatching { player.stop() }
        hideLoading()
    }

    private fun saveProgress() {
        val item = playingItem ?: return
        if (item.section != ContentSection.MOVIES && item.section != ContentSection.SERIES) return
        val position = player.currentPosition()
        val duration = player.duration()
        if (position > 0L) database.saveProgress(source.serviceId, item.section, item.itemId, position, duration)
    }

    private fun toggleFullscreen() {
        isFullscreen = !isFullscreen
        topBar.visibility = if (isFullscreen) View.GONE else View.VISIBLE
        navRail.visibility = if (isFullscreen) View.GONE else View.VISIBLE
        browsePanel.visibility = if (isFullscreen) View.GONE else View.VISIBLE
        (body.layoutParams as LinearLayout.LayoutParams).apply {
            body.layoutParams = this
        }
        fullscreenButton.text = if (isFullscreen) "SALIR" else "PANTALLA COMPLETA"
        surfaceFrame.post { updateVideoAspect() }
        if (isFullscreen) surfaceFrame.requestFocus() else fullscreenButton.requestFocus()
    }

    private fun updateVideoAspect() {
        val vw = lastVideoWidth
        val vh = lastVideoHeight
        val cw = surfaceFrame.width
        val ch = surfaceFrame.height
        if (vw <= 0 || vh <= 0 || cw <= 0 || ch <= 0) return
        val videoRatio = vw.toFloat() / vh.toFloat()
        val containerRatio = cw.toFloat() / ch.toFloat()
        val width: Int
        val height: Int
        if (videoRatio > containerRatio) {
            width = cw
            height = (cw / videoRatio).toInt().coerceAtLeast(1)
        } else {
            height = ch
            width = (ch * videoRatio).toInt().coerceAtLeast(1)
        }
        surfaceView.layoutParams = FrameLayout.LayoutParams(width, height, Gravity.CENTER)
    }

    private fun verifyPanelState() {
        val credentials = RemotePrefs.loadCredentials(this) ?: return
        io.execute {
            val state = RemoteProvisioningClient.fetchConfig(credentials)
            if (state.state == RemoteConfigState.READY) {
                RemotePrefs.saveServices(this, state.services)
                return@execute
            }
            if (state.state == RemoteConfigState.PAYMENT_DUE || state.state == RemoteConfigState.DISABLED || state.state == RemoteConfigState.INVALID) {
                runOnUiThread {
                    stopPlayback()
                    startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
                    finish()
                }
            }
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        surfaceReady = true
        startPendingPlayback()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        surfaceReady = true
        surfaceFrame.post { updateVideoAspect() }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        surfaceReady = false
        saveProgress()
        runCatching { player.stop() }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && isFullscreen) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK -> {
                    toggleFullscreen()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_LEFT -> {
                    val item = playingItem
                    if (item != null && item.section != ContentSection.LIVE && item.section != ContentSection.RADIO) {
                        player.seekTo((player.currentPosition() - 10_000L).coerceAtLeast(0L))
                        return true
                    }
                }
                KeyEvent.KEYCODE_DPAD_RIGHT -> {
                    val item = playingItem
                    if (item != null && item.section != ContentSection.LIVE && item.section != ContentSection.RADIO) {
                        player.seekTo(player.currentPosition() + 10_000L)
                        return true
                    }
                }
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                    if (player.isPlaying()) player.pause() else player.resume()
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onBackPressed() {
        when {
            isFullscreen -> toggleFullscreen()
            browseLevel == BrowseLevel.EPISODES -> selectedSeries?.let { series ->
                showItems(series.categoryId, "SERIES")
            } ?: showCategories(ContentSection.SERIES)
            browseLevel == BrowseLevel.ITEMS -> showCategories(currentSection)
            else -> super.onBackPressed()
        }
    }

    override fun onStop() {
        super.onStop()
        saveProgress()
        runCatching { player.stop() }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        saveProgress()
        if (::player.isInitialized) player.release()
        if (::database.isInitialized) database.close()
        io.shutdownNow()
        super.onDestroy()
    }

    private fun goProvisioning() {
        startActivity(Intent(this, ProvisioningActivity::class.java).putExtra("force_remote", true))
        finish()
    }

    private fun showLoading(message: String) {
        loadingText.text = message
        loading.visibility = View.VISIBLE
    }

    private fun hideLoading() {
        loading.visibility = View.GONE
    }

    private fun decoderLabel(mode: DecoderMode): String = when (mode) {
        DecoderMode.HARDWARE -> "MediaCodec"
        DecoderMode.SOFTWARE -> "FFmpeg"
        DecoderMode.AUTO -> "Auto"
    }

    private fun sectionLabel(section: ContentSection): String = when (section) {
        ContentSection.LIVE -> "TV EN VIVO"
        ContentSection.MOVIES -> "PELÍCULAS"
        ContentSection.SERIES -> "SERIES"
        ContentSection.RADIO -> "RADIO"
    }

    private inner class CategoryAdapter(private val data: List<Pair<String, String>>) : RecyclerView.Adapter<CategoryAdapter.Holder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder = Holder(rowView(parent))
        override fun onBindViewHolder(holder: Holder, position: Int) {
            val item = data[position]
            holder.text.text = item.second
            holder.text.setOnClickListener { showItems(item.first, item.second) }
            bindFocus(holder.text)
        }
        override fun getItemCount() = data.size
        inner class Holder(val text: TextView) : RecyclerView.ViewHolder(text)
    }

    private inner class ContentAdapter(private val data: List<CatalogItem>) : RecyclerView.Adapter<ContentAdapter.Holder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder = Holder(rowView(parent))
        override fun onBindViewHolder(holder: Holder, position: Int) {
            val item = data[position]
            holder.text.text = when {
                item.seasonNumber != null && item.episodeNumber != null -> "T${item.seasonNumber} · E${item.episodeNumber} · ${item.name}"
                else -> item.name
            }
            holder.text.setOnClickListener { openItem(item) }
            bindFocus(holder.text)
        }
        override fun getItemCount() = data.size
        inner class Holder(val text: TextView) : RecyclerView.ViewHolder(text)
    }

    private fun rowView(parent: ViewGroup): TextView = TextView(parent.context).apply {
        textSize = 14f
        setTextColor(TEXT)
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(13), dp(8), dp(10), dp(8))
        maxLines = 2
        isFocusable = true
        background = rounded(CARD, 8f, BORDER, 1)
        layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(58)).apply {
            bottomMargin = dp(5)
        }
    }

    private fun bindFocus(view: TextView) {
        view.setOnFocusChangeListener { v, focused ->
            (v as TextView).apply {
                background = rounded(if (focused) Color.rgb(12, 78, 120) else CARD, 8f, if (focused) BLUE else BORDER, if (focused) 2 else 1)
                setTextColor(Color.WHITE)
            }
        }
    }

    private fun rounded(fill: Int, radiusDp: Float, stroke: Int, strokeWidthDp: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dp(radiusDp.toInt()).toFloat()
            setStroke(dp(strokeWidthDp), stroke)
        }

    private fun immersive() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}