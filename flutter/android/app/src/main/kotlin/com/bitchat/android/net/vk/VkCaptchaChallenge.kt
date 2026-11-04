// SPDX-License-Identifier: AGPL-3.0-only
package com.bitchat.android.net.vk

import java.net.URI
import java.util.UUID
import org.json.JSONObject

/** Challenge values stay in memory and must never be included in diagnostics. */
class VkCaptchaChallenge internal constructor(
    val id: String = UUID.randomUUID().toString(),
    val redirectUrl: String?, val imageUrl: String?,
    internal val sid: String, internal val epoch: Long,
    internal val createdAt: Long = System.nanoTime(),
    internal val timestamp: String = "", internal val attempt: String = "",
) {
    internal fun isFresh() = System.nanoTime() - createdAt in 0..180_000_000_000L
    override fun toString() = "VkCaptchaChallenge(redacted)"
}
sealed class VkCaptchaAnswer {
    class ImageKey(val value: String) : VkCaptchaAnswer()
    class SuccessToken(val value: String) : VkCaptchaAnswer()
    internal fun value() = when(this) { is ImageKey -> value; is SuccessToken -> value }
    override fun toString() = "VkCaptchaAnswer(redacted)"
}
class VkCaptchaRequired(val challenge: VkCaptchaChallenge) : VkSessionException("VK просит пройти проверку безопасности.")

object VkCaptchaPolicy {
    // Exact official hosts only: no wildcard suffixes, userinfo, alternate ports or cleartext.
    private val hosts = setOf("vk.com", "vk.ru", "m.vk.com", "m.vk.ru", "api.vk.com", "api.vk.ru", "id.vk.com", "id.vk.ru", "captcha.vk.com", "captcha.vk.ru")
    fun allowedUrl(value: String): Boolean = runCatching {
        val uri = URI(value)
        value.length <= 16384 && uri.scheme == "https" && uri.host?.lowercase() in hosts &&
            uri.userInfo == null && uri.port in setOf(-1, 443) && !value.any { it.isISOControl() }
    }.getOrDefault(false)
    internal fun parse(error: JSONObject, epoch: Long): VkCaptchaChallenge {
        val redirect = error.optString("redirect_uri").takeIf { it.isNotEmpty() }
        val image = error.optString("captcha_img").takeIf { it.isNotEmpty() }
        val sid = error.optString("captcha_sid")
        if ((redirect == null && image == null) || (redirect != null && !allowedUrl(redirect)) ||
            (image != null && !allowedUrl(image)) || sid.length > 512 || sid.any { it.isISOControl() })
            throw VkSessionException("VK вернул неподдерживаемую проверку безопасности. Повторите получение хэша.")
        if (redirect == null && sid.isEmpty()) throw VkSessionException("VK не выдал идентификатор проверки.")
        return VkCaptchaChallenge(redirectUrl=redirect, imageUrl=image, sid=sid, epoch=epoch,
            timestamp=error.optString("captcha_ts").take(128), attempt=error.optString("captcha_attempt").take(128))
    }
}
