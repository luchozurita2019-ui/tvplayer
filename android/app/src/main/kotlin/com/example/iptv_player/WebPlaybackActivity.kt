package com.example.iptv_player

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout

class WebPlaybackActivity : Activity() {
    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_HEADERS = "headers"
        const val EXTRA_COOKIES = "cookies"
        const val EXTRA_CLEAR_COOKIES_ON_EXIT = "clearCookiesOnExit"
        const val EXTRA_PLATFORM = "platform"
        const val EXTRA_REPLACE_PLATFORM_COOKIES = "replacePlatformCookies"
        const val EXTRA_SESSION_REF = "sessionRef"
        const val EXTRA_STREAMING_PREMIUM = "streamingPremium"

        private const val FT_PREMIUM_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) " +
                "Chrome/150.0.0.0 Safari/537.36"

        const val RESULT_DEAD_DETECTED = "deadDetected"
        const val RESULT_PLATFORM = "platform"

        private val PREMIUM_COOKIE_DOMAINS = setOf(
            "netflix.com",
            "max.com",
            "hbomax.com",
            "primevideo.com",
            "amazon.com",
            "crunchyroll.com",
        )

        private val PLATFORM_COOKIE_DOMAINS = mapOf(
            "netflix" to listOf("netflix.com"),
            "hbomax" to listOf("max.com", "hbomax.com"),
            "prime" to listOf("primevideo.com", "amazon.com"),
            "crunchyroll" to listOf("crunchyroll.com"),
        )
    }

    private data class TemporaryCookie(
        val name: String,
        val domain: String,
        val path: String,
        val hostOnly: Boolean,
        val secure: Boolean,
    )

    private lateinit var root: FrameLayout
    private lateinit var webView: WebView
    private var customView: View? = null
    private var customViewCallback: WebChromeClient.CustomViewCallback? = null
    private val temporaryCookies = mutableListOf<TemporaryCookie>()
    private var clearCookiesOnExit = false
    private var platform = ""
    private var sessionRef = ""
    private var deadDetected = false
    private var streamingPremium = false
    private var firstMainPageFinished = false

    @SuppressLint("SetJavaScriptEnabled")
    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val rawUrl = intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
        val uri = runCatching { android.net.Uri.parse(rawUrl) }.getOrNull()
        if (uri == null ||
            (uri.scheme != "http" && uri.scheme != "https") ||
            uri.host.isNullOrBlank()
        ) {
            finish()
            return
        }

        platform = intent.getStringExtra(EXTRA_PLATFORM)?.trim()?.lowercase().orEmpty()
        sessionRef = intent.getStringExtra(EXTRA_SESSION_REF)?.trim().orEmpty()
        streamingPremium = intent.getBooleanExtra(EXTRA_STREAMING_PREMIUM, false)
        if (streamingPremium) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        }

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        applyImmersiveMode()

        root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }
        webView = WebView(this).apply {
            setBackgroundColor(Color.BLACK)
            isFocusable = true
            isFocusableInTouchMode = true
        }
        root.addView(
            webView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        setContentView(root)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            mediaPlaybackRequiresUserGesture = false
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(streamingPremium)
            builtInZoomControls = streamingPremium
            displayZoomControls = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            allowFileAccess = false
            cacheMode = WebSettings.LOAD_DEFAULT
            if (streamingPremium) {
                userAgentString = FT_PREMIUM_UA
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                mixedContentMode = if (streamingPremium) {
                    WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                } else {
                    WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                }
            }
        }

        if (streamingPremium) {
            webView.addJavascriptInterface(TvNavBridge(), "TVFullNavBridge")
        }

        val headerBundle = intent.getBundleExtra(EXTRA_HEADERS)
        val headers = mutableMapOf<String, String>()
        headerBundle?.keySet()?.forEach { key ->
            val value = headerBundle.getString(key)?.trim().orEmpty()
            if (key.isNotBlank() &&
                value.isNotBlank() &&
                !key.contains('\r') &&
                !key.contains('\n') &&
                !value.contains('\r') &&
                !value.contains('\n')
            ) {
                headers[key] = value
            }
        }

        val userAgentKey = headers.keys.firstOrNull {
            it.equals("user-agent", ignoreCase = true)
        }
        if (userAgentKey != null) {
            val userAgent = headers.remove(userAgentKey)?.trim().orEmpty()
            if (!streamingPremium && userAgent.isNotEmpty()) {
                webView.settings.userAgentString = userAgent
            }
        }

        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            cookieManager.setAcceptThirdPartyCookies(webView, true)
        }

        clearCookiesOnExit =
            intent.getBooleanExtra(EXTRA_CLEAR_COOKIES_ON_EXIT, false)

        if (intent.getBooleanExtra(EXTRA_REPLACE_PLATFORM_COOKIES, false)) {
            clearPlatformCookies(cookieManager, platform)
        }

        val cookieBundles =
            intent.getParcelableArrayListExtra<Bundle>(EXTRA_COOKIES)
                ?: arrayListOf()
        installTemporaryCookies(cookieManager, cookieBundles)

        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(
                view: WebView?,
                url: String?,
                favicon: android.graphics.Bitmap?,
            ) {
                super.onPageStarted(view, url, favicon)
                if (streamingPremium && view != null) {
                    injectFtBrowserCompat(view)
                }
                Log.i(
                    "TVFULL_PREMIUM",
                    "page_started platform=$platform " + safePageLabel(url),
                )
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                if (streamingPremium && view != null) {
                    injectFtBrowserCompat(view)
                    if (!firstMainPageFinished) {
                        firstMainPageFinished = true
                        view.clearHistory()
                    }
                }
                CookieManager.getInstance().flush()
                if (streamingPremium && view != null) {
                    installTvRemoteNavigation(view)
                }
                if (!deadDetected && isLoginOrAuthPage(url)) {
                    deadDetected = true
                    Log.w(
                        "TVFULL_PREMIUM",
                        "session_dead platform=$platform " + safePageLabel(url),
                    )
                } else {
                    Log.i(
                        "TVFULL_PREMIUM",
                        "page_finished platform=$platform " + safePageLabel(url),
                    )
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?,
            ) {
                super.onReceivedError(view, request, error)
                if (request?.isForMainFrame == true) {
                    Log.w(
                        "TVFULL_PREMIUM",
                        "main_frame_error platform=$platform code=" +
                            error?.errorCode +
                            " url=" + safePageLabel(request.url?.toString()),
                    )
                }
            }

            override fun onReceivedHttpError(
                view: WebView?,
                request: WebResourceRequest?,
                errorResponse: WebResourceResponse?,
            ) {
                super.onReceivedHttpError(view, request, errorResponse)
                if (request?.isForMainFrame == true) {
                    Log.w(
                        "TVFULL_PREMIUM",
                        "main_frame_http platform=$platform status=" +
                            errorResponse?.statusCode +
                            " url=" + safePageLabel(request.url?.toString()),
                    )
                }
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowCustomView(
                view: View?,
                callback: CustomViewCallback?,
            ) {
                if (view == null) {
                    callback?.onCustomViewHidden()
                    return
                }
                if (customView != null) {
                    callback?.onCustomViewHidden()
                    return
                }
                customView = view
                customViewCallback = callback
                webView.visibility = View.GONE
                root.addView(
                    view,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    ),
                )
                applyImmersiveMode()
            }

            override fun onHideCustomView() {
                hideCustomView()
            }

            override fun onPermissionRequest(request: PermissionRequest?) {
                if (request == null) return
                runOnUiThread {
                    if (!streamingPremium ||
                        !isAllowedProtectedMediaOrigin(request.origin)
                    ) {
                        request.deny()
                        return@runOnUiThread
                    }

                    val requested = request.resources?.toSet().orEmpty()
                    val grant = requested.filter {
                        it == PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID
                    }.toTypedArray()

                    if (grant.isEmpty()) {
                        request.deny()
                        return@runOnUiThread
                    }

                    Log.i(
                        "TVFULL_PREMIUM",
                        "protected_media_granted platform=$platform host=" +
                            request.origin?.host.orEmpty().lowercase(),
                    )
                    request.grant(grant)
                }
            }

            override fun onPermissionRequestCanceled(request: PermissionRequest?) {
                super.onPermissionRequestCanceled(request)
                Log.i(
                    "TVFULL_PREMIUM",
                    "protected_media_canceled platform=$platform",
                )
            }
        }

        webView.loadUrl(rawUrl, headers)
        webView.requestFocus()
    }

    @Volatile private var tvNavTextMode = false
    @Volatile private var tvNavNativeVideoMode = false
    private var lastRemoteNavigationAt = 0L
    private var centerLongPressTriggered = false
    private val centerLongPress = Runnable {
        centerLongPressTriggered = true
        evaluateTvNav("pointer")
    }

    private inner class TvNavBridge {
        @android.webkit.JavascriptInterface
        fun log(message: String) {
            Log.i("TVFULL_NAV", message.take(500))
        }

        @android.webkit.JavascriptInterface
        fun modoTexto(enabled: Boolean) {
            tvNavTextMode = enabled
            Log.d("TVFULL_NAV", "text_mode=$enabled")
        }

        @android.webkit.JavascriptInterface
        fun modoVideo(enabled: Boolean) {
            tvNavNativeVideoMode = enabled
            Log.d("TVFULL_NAV", "native_video_mode=$enabled")
        }
    }

    private fun tvNavScript(): String =
        runCatching {
            assets.open("tvnav_v2.js").bufferedReader(Charsets.UTF_8).use { it.readText() }
        }.onFailure {
            Log.e("TVFULL_NAV", "asset_read_failed", it)
        }.getOrDefault("")

    private fun installTvRemoteNavigation(view: WebView) {
        if (!streamingPremium) return
        val script = tvNavScript()
        if (script.isBlank()) return
        runCatching { view.evaluateJavascript(script, null) }
            .onFailure { Log.e("TVFULL_NAV", "install_failed", it) }
    }

    private fun evaluateTvNav(
        action: String,
        direction: String? = null,
        fallbackKeyCode: Int? = null,
    ) {
        if (!::webView.isInitialized || !streamingPremium) return
        val expression = when (action) {
            "move" -> "window.__tvfullNavV2&&window.__tvfullNavV2.move('${direction.orEmpty()}')"
            "activate" -> "window.__tvfullNavV2&&window.__tvfullNavV2.activate()"
            "back" -> "window.__tvfullNavV2&&window.__tvfullNavV2.back()"
            "pointer" -> "window.__tvfullNavV2&&window.__tvfullNavV2.pointer()"
            "rearm" -> "window.__tvfullNavV2&&window.__tvfullNavV2.rearm()"
            else -> "null"
        }
        runCatching {
            webView.evaluateJavascript(
                "(function(){try{return $expression||'pass:no-engine';}catch(e){return 'pass:error';}})()",
            ) { raw ->
                val result = raw?.trim()?.trim('"')?.replace("\\"", """).orEmpty()
                Log.d("TVFULL_NAV", "action=$action dir=${direction.orEmpty()} result=$result")
                if (result.startsWith("pass:") && fallbackKeyCode != null) {
                    webView.post {
                        val down = KeyEvent(KeyEvent.ACTION_DOWN, fallbackKeyCode)
                        val up = KeyEvent(KeyEvent.ACTION_UP, fallbackKeyCode)
                        webView.dispatchKeyEvent(down)
                        webView.dispatchKeyEvent(up)
                    }
                } else if (action == "back" && result.startsWith("pass:")) {
                    webView.post { performNativeBack() }
                }
            }
        }.onFailure {
            Log.e("TVFULL_NAV", "evaluate_failed action=$action", it)
            if (fallbackKeyCode != null) {
                webView.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, fallbackKeyCode))
                webView.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, fallbackKeyCode))
            }
        }
    }

    private fun performNativeBack() {
        if (customView != null) {
            hideCustomView()
        } else if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!streamingPremium || !::webView.isInitialized) {
            return super.dispatchKeyEvent(event)
        }

        if (tvNavTextMode || tvNavNativeVideoMode) {
            return super.dispatchKeyEvent(event)
        }

        val direction = when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT -> "left"
            KeyEvent.KEYCODE_DPAD_RIGHT -> "right"
            KeyEvent.KEYCODE_DPAD_UP -> "up"
            KeyEvent.KEYCODE_DPAD_DOWN -> "down"
            else -> null
        }

        if (direction != null) {
            if (event.action != KeyEvent.ACTION_DOWN) return true
            val now = android.os.SystemClock.uptimeMillis()
            if (now - lastRemoteNavigationAt < 90L) return true
            lastRemoteNavigationAt = now
            evaluateTvNav("move", direction, event.keyCode)
            return true
        }

        when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    centerLongPressTriggered = false
                    webView.removeCallbacks(centerLongPress)
                    webView.postDelayed(centerLongPress, 700L)
                } else if (event.action == KeyEvent.ACTION_UP) {
                    webView.removeCallbacks(centerLongPress)
                    if (!centerLongPressTriggered) evaluateTvNav("activate")
                }
                return true
            }

            KeyEvent.KEYCODE_BACK -> {
                if (event.action == KeyEvent.ACTION_DOWN) {
                    evaluateTvNav("back")
                }
                return true
            }

            KeyEvent.KEYCODE_MENU -> {
                if (event.action == KeyEvent.ACTION_DOWN) evaluateTvNav("pointer")
                return true
            }
        }

        return super.dispatchKeyEvent(event)
    }

    private fun injectFtBrowserCompat(view: WebView) {
        val metrics = resources.displayMetrics
        val declaredWidth = maxOf(metrics.widthPixels, metrics.heightPixels)
        val declaredHeight = minOf(metrics.widthPixels, metrics.heightPixels)
        val script = """
            (function(){
              try {
                Object.defineProperty(navigator,'platform',{get:function(){return 'Win32';}});
                Object.defineProperty(navigator,'maxTouchPoints',{get:function(){return 0;}});
                Object.defineProperty(navigator,'userAgentData',{get:function(){return undefined;}});
                Object.defineProperty(screen,'width',{get:function(){return $declaredWidth;}});
                Object.defineProperty(screen,'height',{get:function(){return $declaredHeight;}});
              } catch(e) {}
            })();
        """.trimIndent()
        runCatching { view.evaluateJavascript(script, null) }
    }

    private fun isAllowedProtectedMediaOrigin(origin: android.net.Uri?): Boolean {
        if (origin == null ||
            !origin.scheme.equals("https", ignoreCase = true)
        ) {
            return false
        }
        val host = origin.host.orEmpty().lowercase()
        val allowed = when (platform) {
            "hbomax" -> listOf("max.com", "hbomax.com")
            "prime" -> listOf("primevideo.com", "amazon.com")
            "crunchyroll" -> listOf("crunchyroll.com")
            else -> emptyList()
        }
        return allowed.any { domain ->
            host == domain || host.endsWith(".$domain")
        }
    }

    private fun safePageLabel(rawUrl: String?): String {
        val parsed = runCatching { android.net.Uri.parse(rawUrl.orEmpty()) }.getOrNull()
            ?: return "invalid"
        val host = parsed.host.orEmpty().lowercase()
        val path = parsed.path.orEmpty().take(160)
        return if (host.isBlank()) "unknown" else host + path
    }

    private fun isLoginOrAuthPage(rawUrl: String?): Boolean {
        if (platform.isBlank()) return false
        val parsed = runCatching { android.net.Uri.parse(rawUrl.orEmpty()) }.getOrNull()
            ?: return false
        val host = parsed.host.orEmpty().lowercase()
        val path = parsed.path.orEmpty().lowercase()

        if (platform == "hbomax" && host == "auth.max.com") return true

        val markers = listOf(
            "/login",
            "/signin",
            "/sign-in",
            "/log-in",
            "/auth/login",
            "/account/login",
            "/registration",
            "/signup",
            "/welcome",
            "/ap/signin",
        )
        return markers.any { path.contains(it) }
    }

    private fun clearPlatformCookies(
        manager: CookieManager,
        platformKey: String,
    ) {
        val domains = PLATFORM_COOKIE_DOMAINS[platformKey] ?: return
        var cleared = 0

        for (domain in domains) {
            val targetUrl = "https://$domain/"
            val current = manager.getCookie(targetUrl).orEmpty()
            if (current.isBlank()) continue

            val names = current.split(';')
                .mapNotNull { item ->
                    val index = item.indexOf('=')
                    if (index <= 0) null else item.substring(0, index).trim()
                }
                .filter { it.isNotBlank() }
                .distinct()

            for (name in names) {
                manager.setCookie(
                    targetUrl,
                    "$name=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
                )
                manager.setCookie(
                    targetUrl,
                    "$name=; Path=/; Domain=.$domain; Max-Age=0; " +
                        "Expires=Thu, 01 Jan 1970 00:00:00 GMT",
                )
                cleared++
            }
        }

        manager.flush()
        Log.i(
            "TVFULL_PREMIUM",
            "cookies_cleared platform=$platformKey count=$cleared",
        )
    }

    private fun installTemporaryCookies(
        manager: CookieManager,
        bundles: List<Bundle>,
    ) {
        for (bundle in bundles) {
            val name = bundle.getString("name")?.trim().orEmpty()
            val value = bundle.getString("value").orEmpty()
            val rawDomain = bundle.getString("domain")?.trim().orEmpty()
            val path = bundle.getString("path")?.trim().orEmpty()
                .takeIf { it.startsWith("/") }
                ?: "/"
            val hostOnly = bundle.getBoolean("hostOnly", false)
            val secure = bundle.getBoolean("secure", true)
            val domain = rawDomain.removePrefix(".").lowercase()

            if (name.isEmpty() ||
                domain.isEmpty() ||
                !isAllowedPremiumDomain(domain) ||
                name.contains(';') ||
                name.contains('=') ||
                name.contains('\r') ||
                name.contains('\n') ||
                value.contains('\r') ||
                value.contains('\n')
            ) {
                continue
            }

            val targetUrl = "https://$domain$path"
            val cookie = buildString {
                append(name)
                append("=")
                append(value)
                append("; Path=")
                append(path)
                if (!hostOnly) {
                    append("; Domain=")
                    append(rawDomain)
                }
                if (streamingPremium || secure) append("; Secure")
                append("; SameSite=None")
            }

            manager.setCookie(targetUrl, cookie)
            temporaryCookies.add(
                TemporaryCookie(
                    name = name,
                    domain = rawDomain,
                    path = path,
                    hostOnly = hostOnly,
                    secure = secure,
                ),
            )
        }

        if (temporaryCookies.isNotEmpty()) {
            manager.flush()
            Log.i(
                "TVFULL_PREMIUM",
                "cookies_installed platform=$platform count=${temporaryCookies.size}",
            )
        }
    }

    private fun isAllowedPremiumDomain(domain: String): Boolean {
        return PREMIUM_COOKIE_DOMAINS.any { allowed ->
            domain == allowed || domain.endsWith(".$allowed")
        }
    }

    private fun clearTemporaryCookies() {
        if (!clearCookiesOnExit || temporaryCookies.isEmpty()) return
        val manager = CookieManager.getInstance()

        for (cookie in temporaryCookies) {
            val domain = cookie.domain.removePrefix(".").lowercase()
            if (!isAllowedPremiumDomain(domain)) continue
            val targetUrl = "https://$domain/"
            val expired = buildString {
                append(cookie.name)
                append("=; Path=")
                append(cookie.path)
                if (!cookie.hostOnly) {
                    append("; Domain=")
                    append(cookie.domain)
                }
                if (cookie.secure) append("; Secure")
                append("; Max-Age=0")
                append("; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
                append("; SameSite=None")
            }
            manager.setCookie(targetUrl, expired)
        }
        manager.flush()
        temporaryCookies.clear()
    }

    private fun hideCustomView() {
        val view = customView ?: return
        root.removeView(view)
        customView = null
        customViewCallback?.onCustomViewHidden()
        customViewCallback = null
        webView.visibility = View.VISIBLE
        webView.requestFocus()
        applyImmersiveMode()
    }

    @Suppress("DEPRECATION")
    private fun applyImmersiveMode() {
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (streamingPremium && ::webView.isInitialized && !tvNavTextMode && !tvNavNativeVideoMode) {
            evaluateTvNav("back")
            return
        }
        performNativeBack()
    }

    override fun onResume() {
        super.onResume()
        if (::webView.isInitialized) {
            webView.onResume()
            webView.resumeTimers()
            if (streamingPremium) {
                webView.postDelayed({
                    installTvRemoteNavigation(webView)
                    evaluateTvNav("rearm")
                }, 150L)
            }
        }
        applyImmersiveMode()
    }

    override fun onPause() {
        if (::webView.isInitialized) webView.onPause()
        CookieManager.getInstance().flush()
        super.onPause()
    }

    override fun finish() {
        setResult(
            RESULT_OK,
            Intent().apply {
                putExtra(RESULT_DEAD_DETECTED, deadDetected)
                putExtra(RESULT_PLATFORM, platform)
            },
        )
        super.finish()
    }

    override fun onDestroy() {
        clearTemporaryCookies()
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.loadUrl("about:blank")
            webView.clearHistory()
            webView.removeAllViews()
            webView.destroy()
        }
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onDestroy()
    }
}
