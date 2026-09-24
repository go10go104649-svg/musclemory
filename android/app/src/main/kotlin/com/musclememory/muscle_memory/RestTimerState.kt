package com.musclememory.muscle_memory

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
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
    private val handler = Handler(Looper.getMainLooper())
    private var deadlineTask: Runnable? = null
    private fun alarmIntent(c: Context, id: String? = null, deadline: Long = 0) = PendingIntent.getBroadcast(c, 7341,
        Intent(c, RestTimerReceiver::class.java).putExtra("timerId", id).putExtra("deadline", deadline),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun clearDeadlineTask() {
        deadlineTask?.let { handler.removeCallbacks(it) }
        deadlineTask = null
    }

    fun schedule(c: Context, deadline: Long, name: String = "") {
        clearDeadlineTask()
        RestTimerFeedback.stop(c)
        val id = UUID.randomUUID().toString()
        prefs(c).edit().putLong("deadline", deadline).putInt("remainingSeconds", 0)
            .putString("exerciseName", name).putString("timerId", id).commit()
        manager(c).cancel(7341)
        if (deadline <= System.currentTimeMillis()) {
            completeIfDue(c, id, deadline, "schedule_due")
            return
        }
        alarm(c).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, alarmIntent(c, id, deadline))
        // One deadline callback, not a per-second notification update. AlarmManager
        // remains the background/process-death fallback; both enter the same claim.
        deadlineTask = object : Runnable {
            override fun run() {
                val current = prefs(c)
                if (current.getString("timerId", null) != id || current.getLong("deadline", 0) != deadline) return
                val remaining = deadline - System.currentTimeMillis()
                if (remaining > 0) {
                    // Handler uses uptime, deadline uses wall time. Millisecond
                    // rounding/clock adjustment must not drop an early callback.
                    handler.postDelayed(this, remaining.coerceAtLeast(10))
                } else completeIfDue(c.applicationContext, id, deadline, "native_deadline")
            }
        }
        handler.postDelayed(deadlineTask!!, (deadline - System.currentTimeMillis()).coerceAtLeast(1))
        RestTimerDiagnostics.log(c, id, "scheduled deadline=$deadline")
        show(c)
    }

    fun cancel(c: Context, remaining: Int = 0) {
        clearDeadlineTask()
        RestTimerDiagnostics.log(c, prefs(c).getString("timerId", null), "cancelled")
        RestTimerDiagnostics.set("lastCancellationAt", System.currentTimeMillis())
        prefs(c).edit().remove("deadline").remove("timerId")
            .putInt("remainingSeconds", remaining.coerceAtLeast(0)).apply()
        alarm(c).cancel(alarmIntent(c))
        RestTimerFeedback.stop(c)
        manager(c).cancel(ONGOING)
        manager(c).cancel(7341)
    }

    /** All callers run on the main looper; persisted claim also survives recreation. */
    @Synchronized
    fun completeIfDue(c: Context, expectedId: String? = null, expectedDeadline: Long = 0,
                      source: String = "state_sync"): Boolean {
        val p = prefs(c)
        val id = p.getString("timerId", null)
        val deadline = p.getLong("deadline", 0)
        if (id == null || deadline == 0L ||
            (expectedId != null && expectedId != id) ||
            (expectedDeadline != 0L && expectedDeadline != deadline)) {
            RestTimerDiagnostics.log(c, expectedId, "stale alarm ignored source=$source")
            RestTimerDiagnostics.set("lastIgnoredEvent", "stale_alarm:$source")
            return false
        }
        if (System.currentTimeMillis() < deadline) return false
        RestTimerDiagnostics.log(c, id, "deadline valid source=$source")
        if (p.getString("lastCompletionTimerId", null) == id) return false
        val at = System.currentTimeMillis()
        // Claim before output. Duplicate Alarm/Dart/resume events cannot replay it.
        if (!p.edit().remove("deadline").remove("timerId").putInt("remainingSeconds", 0)
            .putString("lastCompletionTimerId", id).putLong("lastCompletionAt", at)
            .putLong("lastCompletionDeadline", deadline).commit()) {
            RestTimerDiagnostics.set("lastSoundError", "completion claim persistence failed")
            return false
        }
        clearDeadlineTask()
        alarm(c).cancel(alarmIntent(c))
        manager(c).cancel(ONGOING)
        RestTimerDiagnostics.increment("completionCount")
        RestTimerDiagnostics.log(c, id, "completion claimed")
        RestTimerReceiver.deliverCompletion(c, id)
        onChanged?.invoke()
        return true
    }

    fun snapshot(c: Context): Map<String, Any> {
        completeIfDue(c)
        val p = prefs(c)
        val deadline = p.getLong("deadline", 0)
        return mapOf("timerId" to (p.getString("timerId", "") ?: ""),
            "lastCompletionTimerId" to (p.getString("lastCompletionTimerId", "") ?: ""),
            "lastCompletionAt" to p.getLong("lastCompletionAt", 0),
            "lastCompletionDeadline" to p.getLong("lastCompletionDeadline", 0), "endsAtMilliseconds" to deadline, "remainingSeconds" to p.getInt("remainingSeconds", 0),
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
        if (deadline <= System.currentTimeMillis()) {
            if (deadline > 0) completeIfDue(c, source = "display_resume")
            manager(c).cancel(ONGOING)
            return
        }
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
