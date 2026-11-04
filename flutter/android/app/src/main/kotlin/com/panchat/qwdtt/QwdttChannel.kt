// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class QwdttChannel(private val context: Context, messenger: BinaryMessenger) {
    private val admin = QwdttAdminBridge(context)
    private val engine = QwdttEngine.get(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val channel = MethodChannel(messenger, "app.panchat/qwdtt")
    fun close() { channel.setMethodCallHandler(null); scope.cancel() }
    init {
        channel.setMethodCallHandler { call, result ->
            scope.launch {
                try {
                    val value = withContext(Dispatchers.IO) {
                        when (call.method) {
                            "sshProbe", "sshDeploy", "sshAdmin" -> admin.execute(call.method, call.arguments as? Map<*, *> ?: emptyMap<String, String>())
                            "initialize" -> engine.initialize()
                            "snapshot" -> engine.snapshot()
                            "select" -> { engine.select(); engine.snapshot() }
                            "loginVk" -> { context.startActivity(android.content.Intent(context, VkLoginActivity::class.java).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)); engine.snapshot() }
                            "logoutVk" -> { engine.vkSession.logout(); engine.snapshot() }
                            "generateHash" -> engine.vkSession.generateCallHash()
                            "import" -> { engine.import(requireNotNull(call.argument<String>("source"))); engine.snapshot() }
                            "save" -> { engine.save(requireNotNull(call.argument<String>("profile")), call.argument("password"), call.argument("hash")); engine.snapshot() }
                            "connect" -> { engine.connect(requireNotNull(call.argument<String>("id"))); engine.snapshot() }
                            "disconnect" -> { engine.stop(false); engine.snapshot() }
                            "direct" -> { engine.stop(true); engine.snapshot() }
                            "delete" -> { engine.delete(requireNotNull(call.argument<String>("id"))); engine.snapshot() }
                            else -> null
                        }
                    }
                    if (value == null) result.notImplemented() else result.success(value)
                } catch (cancel: CancellationException) { throw cancel } catch (_: Exception) {
                    result.error("QWDTT_FAILED", "Не удалось выполнить действие qWDTT. Проверьте профиль и реквизиты.", null)
                }
            }
        }
    }
}
