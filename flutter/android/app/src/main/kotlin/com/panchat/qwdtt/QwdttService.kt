// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

import android.app.*
import android.content.Intent
import android.os.IBinder

class QwdttService : Service() {
    private var generation: Long? = null
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("qwdtt_transport", "qWDTT", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, com.nym.bar.MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        startForeground(4108, Notification.Builder(this, "qwdtt_transport")
            .setSmallIcon(android.R.drawable.stat_sys_upload_done).setContentTitle("kachat · qWDTT")
            .setContentText("Выбран защищённый транспорт через VK TURN").setOngoing(true).setContentIntent(open).build())
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.hasExtra("generation") == true) generation = intent.getLongExtra("generation", -1)
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        generation?.let { QwdttEngine.get(this).serviceDestroyed(it) }
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
