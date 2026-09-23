package com.musclememory.muscle_memory

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.UUID

/** One persisted wall-clock deadline, shared by Flutter and notification actions. */
object RestTimerState {
    const val ONGOING = 7340
    const val CHANNEL = "rest_timer_running"
    const val STOP = "musclemory.rest.STOP"
    const val EXTEND = "musclemory.rest.EXTEND"
    var onChanged: (() -> Unit)? = null
    private fun prefs(c: Context) = c.getSharedPreferences("rest_timer", Context.MODE_PRIVATE)
    private fun manager(c: Context) = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private fun alarm(c: Context) = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private fun alarmIntent(c: Context) = PendingIntent.getBroadcast(c, 7341,
        Intent(c, RestTimerReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun schedule(c: Context, deadline: Long, name: String = "") {
        RestTimerFeedback.stop(c)
        prefs(c).edit().putLong("deadline", deadline).putInt("remainingSeconds", 0)
            .putString("exerciseName", name).putString("timerId", UUID.randomUUID().toString()).apply()
        manager(c).cancel(7341)
        if (deadline <= System.currentTimeMillis()) { cancel(c); return }
        alarm(c).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, alarmIntent(c))
        show(c)
    }

    fun cancel(c: Context, remaining: Int = 0) {
        prefs(c).edit().remove("deadline").remove("timerId")
            .putInt("remainingSeconds", remaining.coerceAtLeast(0)).apply()
        alarm(c).cancel(alarmIntent(c))
        RestTimerFeedback.stop(c)
        manager(c).cancel(ONGOING)
        manager(c).cancel(7341)
    }

    fun finished(c: Context) {
        prefs(c).edit().remove("deadline").remove("timerId").putInt("remainingSeconds", 0).apply()
        manager(c).cancel(ONGOING)
    }

    fun snapshot(c: Context): Map<String, Any> {
        val p = prefs(c)
        val deadline = p.getLong("deadline", 0)
        return mapOf("endsAtMilliseconds" to deadline, "remainingSeconds" to p.getInt("remainingSeconds", 0),
            "exerciseName" to (p.getString("exerciseName", "") ?: ""))
    }

    fun action(c: Context, intent: Intent): Boolean {
        if (intent.action != STOP && intent.action != EXTEND) return false
        val p = prefs(c)
        if (intent.getStringExtra("timerId") != p.getString("timerId", null)) return true
        val deadline = p.getLong("deadline", 0)
        if (deadline <= System.currentTimeMillis()) return true
        if (intent.action == STOP) cancel(c, ((deadline - System.currentTimeMillis() + 999) / 1000).toInt())
        else schedule(c, deadline + 30_000, p.getString("exerciseName", "") ?: "")
        onChanged?.invoke()
        return true
    }

    fun show(c: Context) {
        val p = prefs(c)
        val deadline = p.getLong("deadline", 0)
        if (deadline <= System.currentTimeMillis()) { manager(c).cancel(ONGOING); return }
        if (Build.VERSION.SDK_INT >= 26) {
            manager(c).createNotificationChannel(NotificationChannel(CHANNEL, "休憩タイマー実行中", NotificationManager.IMPORTANCE_LOW).apply {
                setSound(null, null); enableVibration(false); lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            })
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CHANNEL) else Notification.Builder(c)
        val open = PendingIntent.getActivity(c, ONGOING, Intent(c, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun actionIntent(action: String, code: Int) = PendingIntent.getBroadcast(c, code,
            Intent(c, RestTimerReceiver::class.java).setAction(action).putExtra("timerId", p.getString("timerId", "")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        builder.setSmallIcon(R.mipmap.ic_launcher).setContentTitle("MUSCLEMORY · 休憩タイマー")
            .setContentText(p.getString("exerciseName", "")).setContentIntent(open)
            .setCategory(Notification.CATEGORY_STATUS).setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true).setOnlyAlertOnce(true).setWhen(deadline).setShowWhen(true).setUsesChronometer(true)
            .addAction(Notification.Action.Builder(null, "停止", actionIntent(STOP, 7343)).build())
            .addAction(Notification.Action.Builder(null, "+30秒", actionIntent(EXTEND, 7344)).build())
        if (Build.VERSION.SDK_INT >= 24) builder.setChronometerCountDown(true)
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(deadline - System.currentTimeMillis())
        try { manager(c).notify(ONGOING, builder.build()) } catch (_: SecurityException) { }
    }
}
