package com.musclememory.muscle_memory

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log

/** Bounded process-local diagnostics; no workout/account data or credentials. */
internal object RestTimerDiagnostics {
    private val values = mutableMapOf<String, Any>()
    fun set(key: String, value: Any) { values[key] = value }
    fun increment(key: String) { values[key] = (values[key] as? Int ?: 0) + 1 }
    fun now(key: String) { set(key, System.currentTimeMillis()) }
    fun snapshot(): Map<String, Any> = values.toMap()
    fun log(c: Context, id: String?, event: String) {
        if (c.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            Log.d("REST_TIMER", "timerId=${id ?: "none"} $event")
        }
    }
}
