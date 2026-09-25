package com.setkeep.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.widget.RemoteViews
import android.view.View
import java.util.UUID
import org.json.JSONObject

/** One persisted wall-clock deadline, shared by Flutter and notification actions. */
object RestTimerState {
    const val ONGOING = 7340
    const val CHANNEL = "rest_timer_running"
    const val STOP = "setkeep.rest.STOP"
    const val EXTEND = "setkeep.rest.EXTEND"
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

    fun schedule(c: Context, deadline: Long, name: String = "", target: JSONObject? = null, restSeconds: Int = 90) {
        clearDeadlineTask()
        RestTimerFeedback.stop(c)
        val id = UUID.randomUUID().toString()
        prefs(c).edit().putLong("deadline", deadline).putInt("remainingSeconds", 0)
            .putString("exerciseName", name).putString("timerId", id).commit()
        manager(c).cancel(7341)
        WorkoutNotificationState.arm(c, target, id, restSeconds)
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
        WorkoutNotificationState.invalidate(c)
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
        if (WorkoutNotificationState.valid(c, id) == null) manager(c).cancel(ONGOING)
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
        val pending = WorkoutNotificationState.pending(c)
        val target = listOf("sessionId", "exerciseInstanceId", "previousSetId", "targetSetId", "exerciseName", "setNumber")
            .associateWith { pending?.optString(it) ?: "" }
        return mapOf("target" to target, "timerId" to (p.getString("timerId", "") ?: ""),
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
        else {
            val target = WorkoutNotificationState.pending(c)
            schedule(c, deadline + 30_000, p.getString("exerciseName", "") ?: "", target, target?.optInt("restSeconds", 90) ?: 90)
        }
        onChanged?.invoke()
        return true
    }

    private fun completeIntent(c: Context, id: String, target: JSONObject) = PendingIntent.getBroadcast(c, 7345,
        Intent(c, RestTimerReceiver::class.java).setAction(WorkoutNotificationState.COMPLETE)
            .setData(android.net.Uri.parse("setkeep://rest-action/$id"))
            .putExtra("timerId", id).putExtra("targetSetId", target.getString("targetSetId")),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** System Chronometer ticks in SystemUI; Flutter never posts once per second.
     * Custom layout intentionally prioritizes legibility over promoted-chip eligibility. */
    private fun timerLayout(c: Context, builder: Notification.Builder, deadline: Long,
                            target: JSONObject?, complete: PendingIntent?, name: String) {
        if (Build.VERSION.SDK_INT < 24) return
        fun view(expanded: Boolean): RemoteViews {
            val layout = RemoteViews(c.packageName, if (expanded) R.layout.rest_notification_expanded else R.layout.rest_notification_compact)
            val running = deadline > System.currentTimeMillis()
            layout.setViewVisibility(R.id.rest_clock, if (running) View.VISIBLE else View.GONE)
            layout.setViewVisibility(R.id.rest_zero, if (running) View.GONE else View.VISIBLE)
            layout.setChronometer(R.id.rest_clock,
                SystemClock.elapsedRealtime() + (deadline - System.currentTimeMillis()).coerceAtLeast(0), null, running)
            layout.setChronometerCountDown(R.id.rest_clock, true)
            val detail = target?.optString("exerciseName")?.takeIf { it.isNotBlank() } ?: name
            val number = target?.optString("setNumber")?.takeIf { it.isNotBlank() }
            layout.setTextViewText(R.id.rest_detail, detail)
            layout.setTextViewText(R.id.rest_next, number?.let { if (expanded) "次：${it}セット目" else "次：$it" } ?: "休憩")
            if (expanded) layout.setTextViewText(R.id.rest_label, if (running) "休憩タイマー" else "休憩終了")
            else {
                layout.setViewVisibility(R.id.rest_complete, if (complete == null) View.GONE else View.VISIBLE)
                if (complete != null) layout.setOnClickPendingIntent(R.id.rest_complete, complete)
            }
            return layout
        }
        builder.setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomContentView(view(false)).setCustomBigContentView(view(true))
            .setCustomHeadsUpContentView(view(false))
    }

    fun show(c: Context) {
        val p = prefs(c)
        val deadline = p.getLong("deadline", 0)
        if (deadline <= System.currentTimeMillis()) {
            if (deadline > 0) completeIfDue(c, source = "display_resume")
            val id = p.getString("lastCompletionTimerId", "") ?: ""
            if (WorkoutNotificationState.valid(c, id) != null) {
                if (manager(c).activeNotifications.none { it.id == ONGOING }) showReady(c, id)
            } else manager(c).cancel(ONGOING)
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
            Intent(c, RestTimerReceiver::class.java).setAction(action)
                .setData(android.net.Uri.parse("setkeep://rest-action/${p.getString("timerId", "")}/$action"))
                .putExtra("timerId", p.getString("timerId", "")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        builder.setSmallIcon(R.mipmap.ic_launcher).setContentTitle("休憩タイマー")
            .setContentText("残り時間 · ${p.getString("exerciseName", "")}").setContentIntent(open)
            .setStyle(Notification.BigTextStyle().bigText("休憩タイマー — 残り時間\n${p.getString("exerciseName", "")}"))
            .setCategory(Notification.CATEGORY_STATUS).setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true).setOnlyAlertOnce(true).setWhen(deadline).setShowWhen(true).setUsesChronometer(true)
            .addAction(Notification.Action.Builder(null, "停止", actionIntent(STOP, 7343)).build())
            .addAction(Notification.Action.Builder(null, "+30秒", actionIntent(EXTEND, 7344)).build())
        val id = p.getString("timerId", "") ?: ""
        val target = WorkoutNotificationState.valid(c, id)
        val complete = target?.let { completeIntent(c, id, it) }
        if (complete != null) builder.addAction(Notification.Action.Builder(null, "セット完了", complete).build())
        timerLayout(c, builder, deadline, target, complete, p.getString("exerciseName", "") ?: "")
        if (Build.VERSION.SDK_INT >= 24) builder.setChronometerCountDown(true)
        // No timeout: completion replaces this same slot with the set action.
        try { manager(c).notify(ONGOING, builder.build()) } catch (_: SecurityException) { }
    }
    fun readyNotification(c: Context, id: String, alert: Boolean = false): Notification? {
        val target = WorkoutNotificationState.valid(c, id) ?: return null
        val channel = if (alert) RestTimerFeedback.CHANNEL else CHANNEL
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channel) else Notification.Builder(c)
        if (alert && Build.VERSION.SDK_INT < 26) builder.setSound(RestTimerFeedback.sound(c)).setVibrate(RestTimerFeedback.vibration)
        val complete = completeIntent(c, id, target)
        val open = PendingIntent.getActivity(c, ONGOING, Intent(c, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        builder.setSmallIcon(R.mipmap.ic_launcher).setContentTitle("休憩終了")
            .setContentText("次のセットを行ってください")
            .setStyle(Notification.BigTextStyle().bigText("次のセットを行ってください"))
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(!alert)
            .setVisibility(Notification.VISIBILITY_PUBLIC).setUsesChronometer(false).setShowWhen(false)
            .addAction(Notification.Action.Builder(null, "セット完了", complete).build())
        timerLayout(c, builder, 0, target, complete, target.optString("exerciseName"))
        return builder.build()
    }
    fun showReady(c: Context, id: String) {
        val notification = readyNotification(c, id) ?: return
        try { manager(c).notify(ONGOING, notification) } catch (_: SecurityException) { }
    }

}
