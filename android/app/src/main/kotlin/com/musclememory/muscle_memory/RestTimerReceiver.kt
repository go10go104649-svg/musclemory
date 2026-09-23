package com.musclememory.muscle_memory

import android.app.Notification
import android.app.PendingIntent
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class RestTimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (RestTimerState.action(context, intent)) return
        val preferences = context.getSharedPreferences("rest_timer", Context.MODE_PRIVATE)
        val deadline = preferences.getLong("deadline", 0)
        // A queued broadcast after stop, or after extending/restarting, is obsolete.
        if (deadline == 0L || System.currentTimeMillis() < deadline) return
        RestTimerState.finished(context)
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
        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openApp = PendingIntent.getActivity(context, 7341, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = builder
            .setContentIntent(openApp)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MUSCLEMORY")
            .setContentText("休憩終了。次のセットへ！")
            .setPriority(Notification.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        try { manager.notify(7341, notification) } catch (_: SecurityException) { }
    }
}
