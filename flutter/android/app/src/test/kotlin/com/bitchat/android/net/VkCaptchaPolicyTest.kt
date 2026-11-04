package com.bitchat.android.net

import com.bitchat.android.net.vk.*
import org.junit.Assert.*
import org.junit.Test

class VkCaptchaPolicyTest {
    @Test fun `captcha only permits exact official HTTPS hosts`() {
        listOf("https://api.vk.ru/captcha.php?sid=synthetic", "https://id.vk.com/not_robot_captcha?session_token=synthetic").forEach { assertTrue(VkCaptchaPolicy.allowedUrl(it)) }
        listOf("http://vk.com/captcha", "https://vk.com.evil.test/captcha", "https://evil.vk.com/captcha", "https://vk.com@evil.test", "https://evil@vk.com/captcha", "https://vk.com:8443/", "javascript:alert(1)", "file:///captcha").forEach { assertFalse(it, VkCaptchaPolicy.allowedUrl(it)) }
    }
    @Test fun `answer diagnostics redact secrets`() {
        assertFalse(VkCaptchaAnswer.SuccessToken("synthetic-secret").toString().contains("synthetic-secret"))
        assertFalse(VkCaptchaAnswer.ImageKey("synthetic-key").toString().contains("synthetic-key"))
    }
    @Test fun `login challenge is not interrupted by a session cookie`() {
        val flow = VkLoginFlow("synthetic")
        assertNull(flow.afterPage("https://m.vk.ru/login",true))
        assertNull(flow.afterPage("https://vk.com/captcha.php",true))
        assertNull(flow.afterPage("https://id.vk.com/auth",true))
        assertNotNull(flow.afterPage("https://m.vk.ru/feed",true))
    }
}
