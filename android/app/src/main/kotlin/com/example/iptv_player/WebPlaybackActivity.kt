package com.example.iptv_player

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebChromeClient
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

        private val PREMIUM_COOKIE_DOMAINS = setOf(
            "netflix.com",
            "max.com",
            "hbomax.com",
            "primevideo.com",
            "amazon.com",
            "crunchyroll.com",
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
            mediaPlaybackRequiresUserGesture = false
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            allowFileAccess = false
            cacheMode = WebSettings.LOAD_DEFAULT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            }
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
            if (userAgent.isNotEmpty()) webView.settings.userAgentString = userAgent
        }

        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            cookieManager.setAcceptThirdPartyCookies(webView, true)
        }

        clearCookiesOnExit =
            intent.getBooleanExtra(EXTRA_CLEAR_COOKIES_ON_EXIT, false)
        val cookieBundles =
            intent.getParcelableArrayListExtra<Bundle>(EXTRA_COOKIES)
                ?: arrayListOf()
        installTemporaryCookies(cookieManager, cookieBundles)

        webView.webViewClient = WebViewClient()
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
        }

        webView.loadUrl(rawUrl, headers)
        webView.requestFocus()
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
                value.isEmpty() ||
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

            val targetUrl = "https://" + domain + "/"
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
                if (secure) append("; Secure")
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
        if (temporaryCookies.isNotEmpty()) manager.flush()
    }

    private fun isAllowedPremiumDomain(domain: String): Boolean {
        return PREMIUM_COOKIE_DOMAINS.any { allowed ->
            domain == allowed || domain.endsWith("." + allowed)
        }
    }

    private fun clearTemporaryCookies() {
        if (!clearCookiesOnExit || temporaryCookies.isEmpty()) return
        val manager = CookieManager.getInstance()

        for (cookie in temporaryCookies) {
            val domain = cookie.domain.removePrefix(".").lowercase()
            if (!isAllowedPremiumDomain(domain)) continue
            val targetUrl = "https://" + domain + "/"
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
        if (customView != null) {
            hideCustomView()
            return
        }
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
            return
        }
        super.onBackPressed()
    }

    override fun onResume() {
        super.onResume()
        if (::webView.isInitialized) webView.onResume()
        applyImmersiveMode()
    }

    override fun onPause() {
        if (::webView.isInitialized) webView.onPause()
        super.onPause()
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
