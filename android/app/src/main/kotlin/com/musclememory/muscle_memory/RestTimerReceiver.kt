package com.musclememory.muscle_memory

import android.app.NotificationChannel
import android.app.Notification
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class RestTimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val channelId = "musclemory_rest_timer"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "休憩タイマー",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "セット間の休憩終了を知らせます"
                    enableVibration(true)
                }
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MUSCLEMORY")
            .setContentText("休憩終了。次のセットへ！")
            .setPriority(Notification.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_ALL)
            .setAutoCancel(true)
            .build()
        try {
            manager.notify(7341, notification)
        } catch (_: SecurityException) {
            // The in-app message still informs users who declined notifications.
        }
    }
}
