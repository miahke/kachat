// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

import android.app.Activity
import com.bitchat.android.net.vk.VkCaptchaCoordinator
import com.bitchat.android.net.vk.VkTransportCaptcha
import com.bitchat.android.net.vk.VkSessionException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class QwdttChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val context = activity.applicationContext
    private val admin = QwdttAdminBridge(context)
    private val engine = QwdttEngine.get(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val channel = MethodChannel(messenger, "app.panchat/qwdtt")
    private val pending = mutableSetOf<MethodChannel.Result>()
    fun close() {
        channel.setMethodCallHandler(null)
        pending.toList().forEach { runCatching { it.error("QWDTT_CANCELLED", "Операция прервана. Повторите действие.", null) } }
        pending.clear()
        scope.cancel()
    }
    init {
        channel.setMethodCallHandler { call, result ->
            pending.add(result)
            scope.launch {
                try {
                    val value = withContext(Dispatchers.IO) {
                        when (call.method) {
                            "sshProbe", "sshDeploy", "sshAdmin" -> admin.execute(call.method, call.arguments as? Map<*, *> ?: emptyMap<String, String>())
                            "initialize" -> engine.initialize()
                            "snapshot" -> engine.snapshot()
                            "select" -> { engine.select(call.argument<String>("route") ?: "VK"); engine.snapshot() }
                            "loginVk" -> { context.startActivity(android.content.Intent(context, VkLoginActivity::class.java).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)); engine.snapshot() }
                            "logoutVk" -> { engine.vkSession.logout(); engine.snapshot() }
                            "generateHash" -> engine.vkSession.generateCallHashWithCaptcha { VkCaptchaCoordinator.solve(activity, it) }
                            "solveCaptcha" -> { VkTransportCaptcha.solvePending(activity); engine.snapshot() }
                            "torSettings" -> engine.torSettings()
                            "connectTor" -> { engine.connectTor(requireNotNull(call.argument<String>("mode")), call.argument<String>("bridges") ?: "", call.argument<Int>("socksPort") ?: 19050); engine.snapshot() }
                            "export" -> engine.export(requireNotNull(call.argument<String>("id")))
                            "import" -> { engine.import(requireNotNull(call.argument<String>("source"))); engine.snapshot() }
                            "save" -> { engine.save(requireNotNull(call.argument<String>("profile")), call.argument("password"), call.argument("hash")); engine.snapshot() }
                            "connect" -> { engine.connect(requireNotNull(call.argument<String>("id"))); engine.snapshot() }
                            "disconnect" -> { engine.stop(false); engine.snapshot() }
                            "direct" -> { engine.stop(true); engine.snapshot() }
                            "delete" -> { engine.delete(requireNotNull(call.argument<String>("id"))); engine.snapshot() }
                            else -> null
                        }
                    }
                    if (pending.remove(result)) { if (value == null) result.notImplemented() else result.success(value) }
                } catch (_: TimeoutCancellationException) {
                    if (pending.remove(result)) result.error("VK_CONFIRMATION", "Проверка VK истекла. Повторите запрос.", null)
                } catch (cancel: CancellationException) {
                    if (pending.remove(result)) result.error("QWDTT_CANCELLED", "Операция прервана.", null)
                    throw cancel
                } catch (error: VkSessionException) {
                    if (pending.remove(result)) result.error("VK_CONFIRMATION", error.publicMessage, null)
                } catch (error: com.bitchat.android.net.bridge.BridgeValidationException) {
                    if (pending.remove(result)) result.error("TOR_BRIDGE", "Некорректная строка моста: " + error.lineNumber, null)
                } catch (_: Exception) {
                    if (pending.remove(result)) result.error("QWDTT_FAILED", "Не удалось выполнить действие. Проверьте параметры подключения и реквизиты.", null)
                }
            }
        }
    }
}
