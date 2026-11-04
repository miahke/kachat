// SPDX-License-Identifier: AGPL-3.0-only
package com.bitchat.android.net.vk

import android.app.Activity
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

/** Native pipe challenges are process-scoped, transient and never exposed through diagnostics. */
object VkTransportCaptcha {
    private class Pending(val id: String, val challenge: VkCaptchaChallenge, val result: CompletableDeferred<VkCaptchaAnswer>)
    private val serial = Mutex()
    private val showing = Mutex()
    private val lock = Any()
    private var pending: Pending? = null
    fun pendingSnapshot(): Map<String, Any?>? = synchronized(lock) {
        pending?.let { mapOf("id" to it.id, "kind" to "vk", "manual" to true) }
    }
    suspend fun awaitChallenge(encodedJson: String): String = serial.withLock {
        require(encodedJson.length <= 32768)
        val json = JSONObject(encodedJson)
        val id = json.getString("id")
        require(id.matches(Regex("[A-Za-z0-9-]{1,80}")))
        val challenge = VkCaptchaPolicy.parse(json, -1)
        val request = Pending(id, challenge, CompletableDeferred())
        synchronized(lock) { check(pending == null); pending = request }
        try {
            val value = withTimeout(180_000) { request.result.await() }
            JSONObject().put("id", id).put(if (value is VkCaptchaAnswer.SuccessToken) "success_token" else "captcha_key", value.value()).toString()
        } catch (e: CancellationException) {
            // A user cancellation is a protocol answer; coroutine cancellation still stops the process.
            currentCoroutineContext().ensureActive()
            JSONObject().put("id", id).put("cancelled", true).toString()
        } finally {
            synchronized(lock) { if (pending === request) pending = null }
            request.result.cancel()
        }
    }
    suspend fun solvePending(activity: Activity) {
        if (!showing.tryLock()) return
        try { solvePendingLocked(activity) } finally { showing.unlock() }
    }
    private suspend fun solvePendingLocked(activity: Activity) {
        val request = synchronized(lock) { pending } ?: throw VkSessionException("Нет ожидающей проверки VK.")
        if (!request.challenge.isFresh()) { cancelPending(); throw VkSessionException("Проверка VK истекла.") }
        try {
            val answer = coroutineScope {
                val observer = launch { request.result.join(); if (request.result.isCancelled) this@coroutineScope.cancel() }
                try { VkCaptchaCoordinator.solve(activity, request.challenge) }
                finally { observer.cancel() }
            }
            synchronized(lock) { if (pending === request) request.result.complete(answer) }
        } catch (e: CancellationException) {
            request.result.cancel()
            currentCoroutineContext().ensureActive()
            throw VkSessionException("Проверка VK отменена или истекла.")
        } catch (e: Exception) { request.result.cancel(); throw e }
    }
    fun cancelPending() { synchronized(lock) { pending?.result?.cancel(); pending = null } }
}
