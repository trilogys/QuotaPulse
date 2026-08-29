package com.trilogys.quotapulse.core

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import kotlin.math.roundToInt

class QuotaNotifier(private val context: Context) {
    private val prefs = context.getSharedPreferences("quotapulse_alert_state", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(NotificationManager::class.java)

    fun evaluate(account: AccountRecord, snapshot: UsageSnapshot) {
        if (snapshot.stale || snapshot.windows.isEmpty()) return
        ensureChannel()
        snapshot.windows.forEach { window ->
            val remaining = window.remainingPercent.coerceIn(0.0, 100.0)
            val level = when {
                remaining <= 0.5 -> 3
                remaining <= 10.0 -> 2
                remaining <= 20.0 -> 1
                else -> 0
            }
            val key = "${account.id}.${window.id}"
            val previous = prefs.getInt(key, 0)
            if (level == 0) {
                if (previous != 0) prefs.edit().putInt(key, 0).apply()
                return@forEach
            }
            if (level <= previous) return@forEach
            prefs.edit().putInt(key, level).apply()
            notifyQuota(account, window, level)
        }
    }

    private fun notifyQuota(account: AccountRecord, window: UsageWindow, level: Int) {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val remaining = window.remainingPercent.coerceIn(0.0, 100.0).roundToInt()
        val title = when (level) {
            3 -> "${account.provider.name} 额度已耗尽"
            2 -> "${account.provider.name} 额度仅剩 10%"
            else -> "${account.provider.name} 额度仅剩 20%"
        }
        val text = "${account.name} · ${window.label} · 剩余 $remaining%"
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .build()
        manager.notify((account.id + window.id + level).hashCode(), notification)
    }

    private fun ensureChannel() {
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "额度提醒",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Codex、Claude、Kimi 等 AI 服务额度接近上限时提醒"
            }
        )
    }

    companion object {
        const val CHANNEL_ID = "quota_alerts"
    }
}
