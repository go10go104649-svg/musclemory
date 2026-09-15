package com.musclememory.muscle_memory

import android.app.Notification
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class RestTimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val preferences = context.getSharedPreferences("rest_timer", Context.MODE_PRIVATE)
        val deadline = preferences.getLong("deadline", 0)
        // A queued broadcast after stop, or after extending/restarting, is obsolete.
        if (deadline == 0L || System.currentTimeMillis() < deadline) return
        preferences.edit().remove("deadline").apply()
        if (RestTimerFeedback.foreground) return // Dart shows the in-app message and plays once.
        RestTimerFeedback.ensureChannel(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, RestTimerFeedback.CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setSound(RestTimerFeedback.sound(context))
                .setVibrate(RestTimerFeedback.vibration)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MUSCLEMORY")
            .setContentText("休憩終了。次のセットへ！")
            .setPriority(Notification.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        try { manager.notify(7341, notification) } catch (_: SecurityException) { }
    }
}
