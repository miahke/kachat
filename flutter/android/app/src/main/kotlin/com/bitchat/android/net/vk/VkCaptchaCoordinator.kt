// SPDX-License-Identifier: AGPL-3.0-only
package com.bitchat.android.net.vk

import android.app.Activity
import android.app.Dialog
import android.graphics.Bitmap
import android.webkit.*
import android.widget.*
import kotlinx.coroutines.*
import org.json.JSONTokener

/** Visible user interaction only. No clicks, fingerprint spoofing, native JS bridge or TLS bypass. */
object VkCaptchaCoordinator {
    suspend fun solve(activity: Activity, challenge: VkCaptchaChallenge): VkCaptchaAnswer = withContext(Dispatchers.Main) {
        if (!challenge.isFresh()) throw VkSessionException("Проверка VK истекла.")
        if (challenge.redirectUrl != null) VkCaptchaAnswer.SuccessToken(solveRedirect(activity, challenge.redirectUrl))
        else VkCaptchaAnswer.ImageKey(show(activity, requireNotNull(challenge.imageUrl), true))
    }

    /** For a native VK challenge, caller owns correlation, retry, and session invalidation. */
    suspend fun solveRedirect(activity: Activity, officialUrl: String): String = withContext(Dispatchers.Main) {
        if (!VkCaptchaPolicy.allowedUrl(officialUrl)) throw VkSessionException("Небезопасный адрес проверки VK.")
        show(activity, officialUrl, false)
    }

    private suspend fun show(activity: Activity, url: String, image: Boolean): String = coroutineScope {
        check(VkCaptchaPolicy.allowedUrl(url))
        if (activity.isFinishing || activity.isDestroyed) throw VkSessionException("Откройте приложение, чтобы пройти проверку VK.")
        val result = CompletableDeferred<String>()
        val dialog = Dialog(activity)
        val root = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(16, 16, 16, 16) }
        root.addView(TextView(activity).apply { text = "Проверка безопасности VK. Выполните задание самостоятельно." })
        val web = WebView(activity)
        val input = EditText(activity).apply { hint = "Текст с картинки"; isSingleLine = true }
        web.settings.apply {
            javaScriptEnabled = !image; domStorageEnabled = !image
            allowFileAccess = false; allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = WebSettings.LOAD_NO_CACHE; safeBrowsingEnabled = true
            javaScriptCanOpenWindowsAutomatically = false; setSupportMultipleWindows(false)
            mediaPlaybackRequiresUserGesture = true
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback?) { callback?.invoke(origin, false, false) }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = !VkCaptchaPolicy.allowedUrl(request.url.toString())
            override fun onPageStarted(view: WebView, target: String, icon: Bitmap?) {
                if (!VkCaptchaPolicy.allowedUrl(target)) { view.stopLoading(); result.completeExceptionally(VkSessionException("VK открыл неподдерживаемую страницу проверки.")) }
                else if (!image) view.evaluateJavascript(CAPTURE_RESULT, null)
            }
            override fun onPageFinished(view: WebView, target: String) { if (!image && VkCaptchaPolicy.allowedUrl(target)) view.evaluateJavascript(CAPTURE_RESULT, null) }
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: android.net.http.SslError) {
                handler.cancel(); result.completeExceptionally(VkSessionException("Ошибка сертификата страницы проверки VK."))
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) result.completeExceptionally(VkSessionException("Страница проверки VK не загрузилась. Повторите запрос."))
            }
        }
        root.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        if (image) {
            root.addView(input)
            root.addView(Button(activity).apply { text = "Отправить"; setOnClickListener {
                val value = input.text.toString().trim()
                if (value.length in 1..512 && value.none { it.isISOControl() }) result.complete(value)
            } })
        }
        root.addView(Button(activity).apply { text = "Отменить"; setOnClickListener { result.completeExceptionally(VkSessionException("Проверка VK отменена.")) } })
        dialog.setContentView(root)
        dialog.setOnCancelListener { result.completeExceptionally(VkSessionException("Проверка VK отменена.")) }
        try {
            dialog.show()
            dialog.window?.setLayout(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT)
            web.loadUrl(url)
            val observer = launch {
                while (isActive && !result.isCompleted) {
                    if (activity.isFinishing || activity.isDestroyed) result.cancel()
                    if (!image && VkCaptchaPolicy.allowedUrl(web.url.orEmpty())) {
                        web.evaluateJavascript("window.__kachatCaptchaResult || null") { encoded ->
                            val value = runCatching { JSONTokener(encoded).nextValue() as? String }.getOrNull()
                            if (value != null && value.length in 1..8192 && value.none { it.isISOControl() }) result.complete(value)
                        }
                    }
                    delay(200)
                }
            }
            try { withTimeout(180_000) { result.await() } } finally { observer.cancel() }
        } finally {
            web.stopLoading(); web.clearHistory(); web.clearCache(true)
            root.removeView(web); web.destroy(); dialog.dismiss()
        }
    }

    // Observe only the official response after the user interacts. All values stay in this page;
    // evaluateJavascript reads a value, never exposes an Android object to frames or third parties.
    private val CAPTURE_RESULT = """
        (function() {
          if (window.__kachatCaptchaObserver) return;
          window.__kachatCaptchaObserver = true;
          function official(u) { try { var x = new URL(u, location.href); return x.protocol === 'https:' && ['api.vk.com','api.vk.ru'].indexOf(x.hostname) >= 0 && x.pathname === '/method/captchaNotRobot.check'; } catch(e) { return false; } }
          function capture(d) { var t = d && d.response && d.response.success_token; if (typeof t === 'string' && t.length > 0 && t.length <= 8192) window.__kachatCaptchaResult = t; }
          var fetch = window.fetch;
          window.fetch = function(input) {
            var response = fetch.apply(this, arguments);
            if (official(typeof input === 'string' ? input : input.url)) response.then(function(r) { r.clone().json().then(capture).catch(function(){}); }).catch(function(){});
            return response;
          };
          var open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(method, url) { this.__kachatOfficial = official(url); return open.apply(this, arguments); };
          XMLHttpRequest.prototype.send = function() {
            if (this.__kachatOfficial) this.addEventListener('load', function() { try { capture(this.responseType === 'json' ? this.response : JSON.parse(this.responseText)); } catch(e){} });
            return send.apply(this, arguments);
          };
        })();
    """.trimIndent()
}
