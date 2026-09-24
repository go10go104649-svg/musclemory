package com.musclememory.muscle_memory

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioFocusRequest
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator

/** Native lifetime: removing the countdown widget does not cut off the cue. */
internal object RestTimerFeedback {
    const val CHANNEL = "musclemory_rest_timer_sound_v3"
    var foreground = false
    private var player: MediaPlayer? = null
    private var focus: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { }
    private fun releaseFocus(context: Context) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focus?.let { audio.abandonAudioFocusRequest(it) }
            focus = null
        } else {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(focusListener)
        }
    }
    val isPlaying: Boolean get() = player?.isPlaying == true
    val vibration = longArrayOf(0, 180, 120, 180, 120, 180, 500, 180, 120, 180)
    fun sound(context: Context): Uri = Uri.parse("android.resource://${context.packageName}/raw/rest_complete")

    fun ensureChannel(context: Context): NotificationChannel? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL) == null) {
            val previous = manager.getNotificationChannel("musclemory_rest_timer_sound_v2")
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "休憩タイマー",
                previous?.importance ?: NotificationManager.IMPORTANCE_HIGH).apply {
                description = "セット間の休憩終了を知らせます"
                enableVibration(previous?.shouldVibrate() ?: true)
                vibrationPattern = vibration
                // Preserve silence or a user-selected sound from the existing channel.
                val oldSound = previous?.sound
                val defaultSound = android.provider.Settings.System.DEFAULT_NOTIFICATION_URI
                setSound(if (previous == null || oldSound == defaultSound) sound(context) else oldSound,
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            })
        }
        return manager.getNotificationChannel(CHANNEL)
    }

    enum class Output { STARTED, SUPPRESSED, FAILED }

    fun status(context: Context): Map<String, Any> {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val channel = ensureChannel(context)
        return mapOf("foreground" to foreground, "notificationPermission" to manager.areNotificationsEnabled(),
            "channelImportance" to (channel?.importance ?: NotificationManager.IMPORTANCE_HIGH),
            "channelHasSound" to (channel == null || channel.sound != null),
            "channelVibrates" to (channel?.shouldVibrate() != false),
            "ringerMode" to audio.ringerMode, "interruptionFilter" to manager.currentInterruptionFilter,
            "notificationVolume" to audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION))
    }

    fun suppression(context: Context): String? {
        val s = status(context)
        return when {
            s["notificationPermission"] != true -> "notification_permission"
            (s["channelImportance"] as Int) < NotificationManager.IMPORTANCE_DEFAULT -> "channel_importance"
            s["channelHasSound"] != true -> "channel_sound_none"
            s["ringerMode"] != AudioManager.RINGER_MODE_NORMAL -> "ringer_mode"
            s["interruptionFilter"] != NotificationManager.INTERRUPTION_FILTER_ALL -> "do_not_disturb"
            s["notificationVolume"] == 0 -> "notification_volume_zero"
            else -> null
        }
    }

    fun play(context: Context, timerId: String? = null): Output {
        stop(context)
        RestTimerDiagnostics.now("lastSoundAttemptAt")
        RestTimerDiagnostics.set("lastSoundTimerId", timerId ?: "explicit_feedback")
        RestTimerDiagnostics.set("lastSoundError", "")
        RestTimerDiagnostics.log(context, timerId, "sound attempt")
        val reason = suppression(context)
        if (reason != null) {
            RestTimerDiagnostics.set("lastSuppressedReason", reason)
            RestTimerDiagnostics.log(context, timerId, "suppressed reason=$reason")
            return Output.SUPPRESSED
        }
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val channel = ensureChannel(context)
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        try {
            val focusResult = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                    .setAudioAttributes(attributes).setOnAudioFocusChangeListener(focusListener).build()
                audio.requestAudioFocus(focus!!)
            } else {
                @Suppress("DEPRECATION")
                audio.requestAudioFocus(focusListener, AudioManager.STREAM_NOTIFICATION,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            }
            RestTimerDiagnostics.set("audioFocusResult", focusResult)
            RestTimerDiagnostics.log(context, timerId, "audio focus result=$focusResult")
            if (focusResult != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                RestTimerDiagnostics.set("lastSoundError", "audio_focus_denied")
                releaseFocus(context)
                return Output.FAILED // Lifecycle boundary: notification is still a valid output.
            }
            val cue = MediaPlayer()
            player = cue // assign before prepare so every failure can release it
            RestTimerDiagnostics.log(context, timerId, "media player created")
            cue.setAudioAttributes(attributes)
            RestTimerDiagnostics.log(context, timerId, "audio attributes set")
            cue.setDataSource(context.applicationContext, channel?.sound ?: sound(context))
            RestTimerDiagnostics.log(context, timerId, "data source set")
            cue.setOnCompletionListener { finished ->
                RestTimerDiagnostics.now("lastSoundCompletedAt")
                RestTimerDiagnostics.log(context, timerId, "media player complete")
                if (player === finished) { player = null; releaseFocus(context) }
                finished.release()
            }
            cue.setOnErrorListener { failed, what, extra ->
                RestTimerDiagnostics.set("lastSoundError", "media_error:$what/$extra")
                RestTimerDiagnostics.log(context, timerId, "media player error=$what/$extra")
                if (player === failed) { player = null; releaseFocus(context) }
                failed.release()
                true // Do not replay after possibly audible playback.
            }
            cue.prepare()
            RestTimerDiagnostics.log(context, timerId, "media player prepared")
            cue.start()
            RestTimerDiagnostics.now("lastSoundStartedAt")
            RestTimerDiagnostics.increment("soundStartCount")
            RestTimerDiagnostics.log(context, timerId, "media player start")
        } catch (error: Exception) {
            RestTimerDiagnostics.set("lastSoundError", "${error.javaClass.simpleName}: ${error.message}")
            RestTimerDiagnostics.log(context, timerId, "sound failed: $error")
            player?.release(); player = null; releaseFocus(context)
            return Output.FAILED
        }
        if (channel?.shouldVibrate() != false) {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(vibration, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(vibration, -1)
            }
        }
        return Output.STARTED
    }

    fun stop(context: Context) {
        if (player != null) {
            RestTimerDiagnostics.now("lastSoundStoppedAt")
            RestTimerDiagnostics.log(context, null, "media player stopped explicitly")
        }
        releaseFocus(context)
        player?.release()
        player = null
        (context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator).cancel()
    }
}
