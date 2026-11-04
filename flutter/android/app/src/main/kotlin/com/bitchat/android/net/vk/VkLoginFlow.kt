package com.bitchat.android.net.vk

import java.net.URLEncoder

/** Browser-owned login followed by a nonce-bound OAuth flow; no DOM/password extraction. */
class VkLoginFlow(private val nonce:String) {
    var oauthRequested=false
        private set
    fun loginUrl(attempt:Int):String {
        oauthRequested=false
        return when(attempt.coerceIn(0,2)){0->"https://m.vk.ru/login";1->"https://m.vk.ru/";else->"https://vk.ru/login"}
    }
    fun afterPage(url:String,hasSessionCookie:Boolean):String? {
        if(oauthRequested || !hasSessionCookie || !VkOAuthParser.allowedNavigation(url))return null
        // A cookie can appear before VK finishes its login/security challenge.
        val uri = java.net.URI(url)
        if (uri.host !in setOf("vk.com", "vk.ru", "m.vk.com", "m.vk.ru") ||
            uri.path !in setOf("", "/", "/feed", "/im", "/news")) return null
        oauthRequested=true
        return authorizeUrl(nonce)
    }
    companion object {
        fun authorizeUrl(nonce:String):String {
            require(nonce.isNotEmpty() && nonce.length<=256)
            return "https://oauth.vk.com/authorize?client_id=6287487&display=mobile"+
                "&redirect_uri="+URLEncoder.encode("https://oauth.vk.com/blank.html","UTF-8")+
                "&response_type=token&scope=messages&state="+URLEncoder.encode(nonce,"UTF-8")+"&v=5.199"
        }
    }
}
