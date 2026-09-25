package com.setkeep.app

import android.content.Context
import android.content.Intent
import org.json.JSONObject

/** One writer on the main looper, shared with the legacy Flutter draft key.
 * Receiver commits before returning; no Flutter engine or Activity is required.
 */
object WorkoutNotificationState {
    const val COMPLETE = "setkeep.rest.COMPLETE_SET"
    private const val DRAFT = "flutter.active_workout_draft"
    private const val ACTION = "musclemory.lock_action"
    private const val LAST_ACTION_AT = "musclemory.last_set_action_at"
    private fun prefs(c: Context) = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    fun read(c: Context): String? = prefs(c).getString(DRAFT, null)
    fun invalidate(c: Context) { check(prefs(c).edit().remove(ACTION).commit()) }
    fun clear(c: Context) {
        check(prefs(c).edit().remove(DRAFT).remove(ACTION).remove(LAST_ACTION_AT).commit())
        RestTimerState.cancel(c)
    }
    fun write(c: Context, encoded: String): String {
        val incoming = JSONObject(encoded)
        val old = read(c)?.let { JSONObject(it) }
        if (old != null && old.optString("sessionId") == incoming.optString("sessionId")) {
            val seen = incoming.optLong("lockRevision")
            val journal = old.optJSONObject("lockCompleted") ?: JSONObject()
            val exercises = incoming.getJSONArray("exercises")
            for (i in 0 until exercises.length()) {
                val sets = exercises.getJSONObject(i).getJSONArray("sets")
                for (j in 0 until sets.length()) {
                    val set = sets.getJSONObject(j)
                    if (journal.optLong(set.optString("setId")) > seen) set.put("completed", true)
                }
            }
            incoming.put("lockRevision", old.optLong("lockRevision"))
            incoming.put("lockCompleted", journal)
        }
        incoming.put("draftVersion", (old?.optLong("draftVersion") ?: 0) + 1)
        val result = incoming.toString()
        // Numeric/note edits must not remove the next-set action. Keep its
        // stable target only while that exact exercise/set is still unfinished.
        val action = pending(c)
        val targetExercise = action?.let { exercise(incoming, it) }
        val editor = prefs(c).edit().putString(DRAFT, result)
        if (action != null && targetExercise != null && targetIndex(targetExercise, action) >= 0 &&
            targetExercise.optString("exerciseId") == action.optString("exerciseId")) {
            action.put("draftVersion", incoming.optLong("draftVersion"))
                .put("exerciseName", targetExercise.optString("name"))
                .put("setNumber", (targetIndex(targetExercise, action) + 1).toString())
            editor.putString(ACTION, action.toString())
        } else editor.remove(ACTION)
        check(editor.commit())
        return result
    }
    private fun exercise(draft: JSONObject, target: JSONObject): JSONObject? {
        if (listOf("sessionId", "exerciseInstanceId", "targetSetId")
            .any { target.optString(it).isBlank() }) return null
        if (draft.optString("sessionId").isEmpty() || draft.optString("sessionId") != target.optString("sessionId")) return null
        val exercises = draft.optJSONArray("exercises") ?: return null
        for (i in 0 until exercises.length()) {
            val e = exercises.getJSONObject(i)
            if (e.optString("instanceId") == target.optString("exerciseInstanceId")) return e
        }
        return null
    }
    private fun targetIndex(e: JSONObject, target: JSONObject): Int {
        val sets = e.getJSONArray("sets")
        for (i in 0 until sets.length()) {
            val set = sets.getJSONObject(i)
            if (!set.optBoolean("completed")) {
                // Undoing an earlier check changes which set is next. An old
                // action must not skip that newly unfinished set.
                return if (set.optString("setId") == target.optString("targetSetId")) i else -1
            }
        }
        return -1
    }
    /** Shared by the app checkbox and receiver. Start with this exercise, then
     * following exercises, finally earlier unfinished exercises. Never infer IDs. */
    fun nextTarget(c: Context, session: String, exerciseId: String): JSONObject? {
        val draft = read(c)?.let { JSONObject(it) } ?: return null
        if (draft.optString("sessionId") != session) return null
        val exercises = draft.optJSONArray("exercises") ?: return null
        val start = (0 until exercises.length()).firstOrNull {
            exercises.getJSONObject(it).optString("instanceId") == exerciseId
        } ?: return null
        for (offset in 0 until exercises.length()) {
            val e = exercises.getJSONObject((start + offset) % exercises.length())
            val sets = e.getJSONArray("sets")
            for (i in 0 until sets.length()) {
                val set = sets.getJSONObject(i)
                if (!set.optBoolean("completed") && set.optString("setId").isNotBlank()) {
                    return JSONObject().put("sessionId", session)
                        .put("exerciseInstanceId", e.getString("instanceId"))
                        .put("targetSetId", set.getString("setId"))
                        .put("exerciseName", e.optString("name"))
                        .put("setNumber", (i + 1).toString())
                }
            }
        }
        return null
    }
    fun arm(c: Context, target: JSONObject?, timerId: String, seconds: Int) {
        invalidate(c)
        if (target == null) return
        val draft = read(c)?.let { JSONObject(it) } ?: return
        val e = exercise(draft, target) ?: return
        if (targetIndex(e, target) < 0) return
        val action = JSONObject(target.toString()).put("timerId", timerId)
            .put("draftVersion", draft.optLong("draftVersion"))
            .put("exerciseId", e.optString("exerciseId"))
            .put("exerciseName", e.optString("name"))
            .put("setNumber", (targetIndex(e, target) + 1).toString())
            .put("restSeconds", seconds.coerceIn(1, 3599))
        check(prefs(c).edit().putString(ACTION, action.toString()).commit())
    }
    fun pending(c: Context): JSONObject? = prefs(c).getString(ACTION, null)?.let { JSONObject(it) }
    fun valid(c: Context, timerId: String): JSONObject? {
        val a = pending(c) ?: return null
        val draft = read(c)?.let { JSONObject(it) } ?: return null
        if (a.optString("timerId") != timerId || a.optLong("draftVersion") != draft.optLong("draftVersion")) return null
        val e = exercise(draft, a) ?: return null
        if (e.optString("exerciseId") != a.optString("exerciseId") || targetIndex(e, a) < 0) return null
        return a
    }
    fun complete(c: Context, intent: Intent) {
        val id = intent.getStringExtra("timerId") ?: return
        val a = valid(c, id) ?: return
        if (intent.getStringExtra("targetSetId") != a.optString("targetSetId")) return
        val rest = c.getSharedPreferences("rest_timer", Context.MODE_PRIVATE)
        val running = rest.getString("timerId", null) == id
        val ended = rest.getLong("deadline", 0) == 0L && rest.getString("lastCompletionTimerId", null) == id
        if (!running && !ended) return
        // A replacement notification can render between the two taps of a
        // double tap. Persist this short debounce as well as generation checks.
        val now = System.currentTimeMillis()
        val sinceLast = now - prefs(c).getLong(LAST_ACTION_AT, 0)
        if (sinceLast in 0 until 1000) return
        val draft = JSONObject(read(c)!!)
        val e = exercise(draft, a)!!
        val sets = e.getJSONArray("sets")
        val index = targetIndex(e, a)
        if (index < 0) return
        sets.getJSONObject(index).put("completed", true)
        val revision = draft.optLong("lockRevision") + 1
        val journal = draft.optJSONObject("lockCompleted") ?: JSONObject()
        journal.put(a.getString("targetSetId"), revision)
        draft.put("lockCompleted", journal).put("lockRevision", revision)
            .put("draftVersion", draft.optLong("draftVersion") + 1)
        // Atomically consume the action and persist the actual set values.
        if (!prefs(c).edit().putString(DRAFT, draft.toString()).remove(ACTION)
            .putLong(LAST_ACTION_AT, now).commit()) return
        val next = nextTarget(c, a.getString("sessionId"), a.getString("exerciseInstanceId"))
        if (next != null) {
            val seconds = a.getInt("restSeconds")
            RestTimerState.schedule(c, System.currentTimeMillis() + seconds * 1000L,
                next.optString("exerciseName"), next, seconds)
        } else RestTimerState.cancel(c)
        RestTimerState.onChanged?.invoke()
    }
}
