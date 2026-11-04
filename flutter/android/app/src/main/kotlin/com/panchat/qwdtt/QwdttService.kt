// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

import android.app.*
import android.content.Intent
import android.os.IBinder
import kotlinx.coroutines.*

/** One foreground lifetime for the selected protected route, with real Tor progress. */
class QwdttService : Service() {
    @Volatile private var generation: Long? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var lastStatus: String? = null
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("qwdtt_transport", "Tor и qWDTT", NotificationManager.IMPORTANCE_LOW))
        startForeground(4108, notification("Сетевое подключение", "Запуск защищённого маршрута…", null))
        scope.launch {
            while (isActive) {
                runCatching {
                    val data = QwdttEngine.get(this@QwdttService).snapshot()
                    val epoch = data["generation"] as? Long
                    val route = data["route"] as? String
                    val state = data["state"] as? String
                    val tor = data["tor"] as? Map<*, *>
                    val percent = if (route != "TOR") null else if (state == "READY") 100
                        else if (state == "STOPPED") 0 else ((tor?.get("percent") as? Number)?.toInt() ?: 0).coerceIn(0, 99)
                    val captcha = data["captcha"] != null
                    val signature = listOf(epoch, route, state, percent, captcha).joinToString(":")
                    if (epoch == generation && signature != lastStatus) {
                        val title = if (route == "TOR") "Tor" else "qWDTT"
                        val body = if (captcha) "VK ожидает подтверждения. Откройте kachat для прохождения капчи."
                            else when (state) {
                                "READY" -> "Локальный прокси готов"
                                "STARTING" -> if (route == "TOR") "Загрузка сети Tor: " + percent + " %" else "Устанавливаем соединение через VK TURN…"
                                "RECONNECTING" -> "Восстанавливаем защищённое соединение…"
                                "ERROR" -> "Не удалось подключиться. Откройте сведения о подключении."
                                else -> "Выбранный маршрут остановлен"
                            }
                        manager.notify(4108, notification(title, body, percent))
                        lastStatus = signature
                    }
                }
                delay(1000)
            }
        }
    }
    private fun notification(title: String, text: String, percent: Int?): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, com.nym.bar.MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "qwdtt_transport").setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle("kachat · " + title).setContentText(text).setOngoing(true).setOnlyAlertOnce(true)
            .setContentIntent(open).apply { if (percent != null) setProgress(100, percent, false) }.build()
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.hasExtra("generation") == true) generation = intent.getLongExtra("generation", -1)
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) { stopSelf() }
    override fun onDestroy() {
        scope.cancel()
        generation?.let { QwdttEngine.get(this).serviceDestroyed(it) }
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
