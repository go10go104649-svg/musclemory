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
        val id = intent.getStringExtra("timerId")
        val deadline = intent.getLongExtra("deadline", 0)
        RestTimerDiagnostics.log(context, id, "receiver fired")
        // Alarm events carry the generation AND deadline; an old broadcast cannot
        // finish a replacement even if the replacement is already due.
        if (id == null || deadline == 0L) {
            RestTimerDiagnostics.log(context, id, "stale alarm ignored missing identity")
            return
        }
        RestTimerState.completeIfDue(context, id, deadline, "alarm")
    }

    companion object {
    fun deliverCompletion(context: Context, id: String) {
        RestTimerDiagnostics.log(context, id, "foreground=${RestTimerFeedback.foreground}")
        if (RestTimerFeedback.foreground) {
            when (RestTimerFeedback.play(context, id)) {
                RestTimerFeedback.Output.STARTED -> {
                    RestTimerDiagnostics.set("lastCompletionPath", "foreground_native_sound")
                    return
                }
                RestTimerFeedback.Output.SUPPRESSED -> {
                    RestTimerDiagnostics.set("lastCompletionPath", "suppressed_by_os")
                    return
                }
                RestTimerFeedback.Output.FAILED -> {
                    // No direct playback started: a single notification fallback.
                    RestTimerDiagnostics.set("lastCompletionPath", "foreground_notification_fallback")
                }
            }
        } else RestTimerDiagnostics.set("lastCompletionPath", "background_notification")
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
        val suppressed = RestTimerFeedback.suppression(context)
        if (suppressed != null) {
            RestTimerDiagnostics.set("lastCompletionPath", "suppressed_by_os")
            RestTimerDiagnostics.set("lastSuppressedReason", suppressed)
            RestTimerDiagnostics.log(context, id, "suppressed reason=$suppressed")
        }
        try {
            manager.notify(7341, notification)
            RestTimerDiagnostics.now("lastNotificationPostedAt")
            RestTimerDiagnostics.increment("notificationPostCount")
            RestTimerDiagnostics.log(context, id, "notification posted")
        } catch (error: Exception) {
            RestTimerDiagnostics.set("lastCompletionPath", "failed")
            RestTimerDiagnostics.set("lastSoundError", "notification: $error")
            RestTimerDiagnostics.log(context, id, "notification failed: $error")
        }
    }
}
}
