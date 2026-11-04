// SPDX-License-Identifier: AGPL-3.0-only
// Adapted from panchat VkAuthActivity; original qWDTT notices retained.
package com.panchat.qwdtt

import android.app.Activity
import android.graphics.Bitmap
import android.os.Bundle
import android.webkit.*
import android.widget.*
import com.bitchat.android.net.vk.VkLoginFlow
import com.bitchat.android.net.vk.VkOAuthParser
import kotlinx.coroutines.*

class VkLoginActivity : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val nonce = QwdttEngine.randomSecret()
    private val flow = VkLoginFlow(nonce)
    private lateinit var web: WebView
    private lateinit var status: TextView
    private var generation: Long? = null
    private var committed = false
    private var accepting = false
    private var prepared = false
    private var attempt = 0
    private val popups = mutableSetOf<WebView>()
    private val session get() = QwdttEngine.get(applicationContext).vkSession
    private fun message(text: String) { status.text = text }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.importantForAutofill = android.view.View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.setOnApplyWindowInsetsListener { view, insets ->
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars()); view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            } else view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            insets
        }
        val controls = LinearLayout(this)
        controls.addView(Button(this).apply { text = "Закрыть"; setOnClickListener { finish() } })
        controls.addView(Button(this).apply { text = "Повторить"; setOnClickListener { if (prepared && !accepting) web.loadUrl(flow.loginUrl(attempt)) } })
        controls.addView(Button(this).apply { text = "Другой вход"; setOnClickListener {
            if (prepared && !accepting) {
                attempt = (attempt + 1) % 3
                web.settings.userAgentString = if (attempt == 2) "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" else WebSettings.getDefaultUserAgent(this@VkLoginActivity)
                web.loadUrl(flow.loginUrl(attempt))
            }
        } })
        root.addView(controls)
        status = TextView(this).apply { text = "Вход на официальной странице VK для получения хэшей звонка"; setPadding(16, 8, 16, 8) }
        root.addView(status)
        web = WebView(this).apply {
            settings.javaScriptEnabled = true; settings.domStorageEnabled = true
            settings.allowFileAccess = false; settings.allowContentAccess = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.cacheMode = WebSettings.LOAD_NO_CACHE; settings.safeBrowsingEnabled = true
            settings.javaScriptCanOpenWindowsAutomatically = false; settings.setSupportMultipleWindows(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
            webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback?) { callback?.invoke(origin, false, false) }
                override fun onCreateWindow(view: WebView, dialog: Boolean, gesture: Boolean, msg: android.os.Message): Boolean {
                    if (!gesture || popups.isNotEmpty()) return false
                    val popup = WebView(this@VkLoginActivity)
                    popup.settings.allowFileAccess = false; popup.settings.allowContentAccess = false
                    popup.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                    popup.webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(child: WebView, request: WebResourceRequest): Boolean {
                            if (request.isForMainFrame) {
                                val target = request.url.toString()
                                if (!acceptUrl(target) && VkOAuthParser.allowedNavigation(target)) web.loadUrl(target)
                                child.stopLoading(); popups.remove(child); child.destroy()
                            }
                            return true
                        }
                    }
                    popups.add(popup); (msg.obj as WebView.WebViewTransport).webView = popup; msg.sendToTarget(); return true
                }
            }
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = acceptUrl(request.url.toString()) || !VkOAuthParser.allowedNavigation(request.url.toString())
                override fun onPageStarted(view: WebView, url: String, icon: Bitmap?) { if (acceptUrl(url) || !VkOAuthParser.allowedNavigation(url)) view.stopLoading() }
                override fun onPageFinished(view: WebView, url: String) { if (!acceptUrl(url)) nextOAuth(url) }
                override fun doUpdateVisitedHistory(view: WebView, url: String, reload: Boolean) { acceptUrl(url) }
                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: android.net.http.SslError) { handler.cancel(); message("Ошибка сертификата VK. Вход остановлен.") }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) { if (request.isForMainFrame) message("Страница VK не загрузилась. Повторите вход или выберите другой вариант.") }
            }
        }
        root.addView(web, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
        scope.launch {
            generation = withContext(Dispatchers.IO) { session.generation }
            CookieManager.getInstance().removeAllCookies {
                if (!isFinishing && !isDestroyed) { WebStorage.getInstance().deleteAllData(); prepared = true; web.loadUrl(flow.loginUrl(attempt)) }
            }
        }
        scope.launch {
            while (isActive) {
                if (prepared && !accepting && !flow.oauthRequested && hasWindowFocus()) nextOAuth(web.url.orEmpty())
                delay(750)
            }
        }
    }
    private fun nextOAuth(url: String) {
        if (!VkOAuthParser.allowedNavigation(url)) return
        val hasSession = listOf("https://vk.com", "https://vk.ru", "https://m.vk.com", "https://m.vk.ru").any { domain ->
            CookieManager.getInstance().getCookie(domain).orEmpty().split(';').any { it.trim().startsWith("remixsid=") && it.trim().substringAfter('=').isNotEmpty() }
        }
        flow.afterPage(url, hasSession)?.let { message("Подтвердите получение хэшей звонка"); web.loadUrl(it) }
    }
    private fun acceptUrl(url: String): Boolean {
        val token = VkOAuthParser.token(url, nonce) ?: return false
        if (!accepting && generation != null) {
            accepting = true; web.stopLoading()
            scope.launch {
                try {
                    session.acceptToken(token, requireNotNull(generation)); committed = true
                    CookieManager.getInstance().removeAllCookies { CookieManager.getInstance().flush(); setResult(RESULT_OK); finish() }
                } catch (_: Exception) { accepting = false; message("Не удалось сохранить сессию VK") }
            }
        }
        return true
    }
    override fun onDestroy() {
        if (!committed) generation?.let { session.cancelSignIn(it) }
        scope.cancel()
        popups.toList().forEach { it.stopLoading(); it.destroy() }; popups.clear()
        if (::web.isInitialized) { web.stopLoading(); web.clearCache(true); web.clearHistory(); web.destroy() }
        CookieManager.getInstance().removeAllCookies(null); WebStorage.getInstance().deleteAllData()
        super.onDestroy()
    }
}
