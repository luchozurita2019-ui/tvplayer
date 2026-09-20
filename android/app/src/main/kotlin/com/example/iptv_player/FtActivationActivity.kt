package com.example.iptv_player

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.TextView

class FtActivationActivity : Activity() {
    companion object {
        const val EXTRA_URL = "activationUrl"
        const val RESULT_COMPLETED = "completed"
        private const val WORKER_HOST = "novax-online.iptvnovax.workers.dev"
    }

    private lateinit var root: FrameLayout
    private lateinit var webView: WebView
    private lateinit var status: TextView
    private var initialHost = ""
    private var finished = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val rawUrl = intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
        val uri = runCatching { Uri.parse(rawUrl) }.getOrNull()
        if (uri == null || uri.scheme != "https" || uri.host.isNullOrBlank()) {
            finishWith(false)
            return
        }
        initialHost = uri.host.orEmpty().lowercase()

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY

        root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
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

        status = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 15f
            gravity = Gravity.CENTER
            text = "CARGANDO ACTIVACIÓN…"
        }
        root.addView(
            status,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )
        setContentView(root)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            javaScriptCanOpenWindowsAutomatically = true
            setSupportMultipleWindows(false)
            mediaPlaybackRequiresUserGesture = false
            cacheMode = WebSettings.LOAD_DEFAULT
        }
        webView.addJavascriptInterface(FtBridge(), "FT")
        webView.webChromeClient = WebChromeClient()
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                status.visibility = View.GONE
                view?.requestFocus()
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?,
            ): Boolean {
                val target = request?.url ?: return false
                if (target.scheme.equals("ftad", ignoreCase = true)) {
                    finishWith(true)
                    return true
                }
                if (request.isForMainFrame != true) return false

                val host = target.host.orEmpty().lowercase()
                val internal =
                    target.scheme.equals("https", ignoreCase = true) &&
                        (host == WORKER_HOST || host == initialHost)
                if (internal) return false

                return try {
                    startActivity(Intent(Intent.ACTION_VIEW, target))
                    true
                } catch (_: Throwable) {
                    true
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?,
            ) {
                super.onReceivedError(view, request, error)
                if (request?.isForMainFrame == true) {
                    status.text = "NO SE PUDO CARGAR LA ACTIVACIÓN"
                    status.visibility = View.VISIBLE
                }
            }
        }

        webView.loadUrl(rawUrl)
        webView.requestFocus()
    }

    private inner class FtBridge {
        @JavascriptInterface
        fun listo(value: String?) {
            runOnUiThread { finishWith(true) }
        }
    }

    private fun finishWith(completed: Boolean) {
        if (finished) return
        finished = true
        setResult(
            if (completed) RESULT_OK else RESULT_CANCELED,
            Intent().putExtra(RESULT_COMPLETED, completed),
        )
        finish()
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            runCatching { webView.removeJavascriptInterface("FT") }
            runCatching { webView.loadUrl("about:blank") }
            runCatching { webView.stopLoading() }
            runCatching { webView.destroy() }
        }
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        finishWith(false)
    }
}
