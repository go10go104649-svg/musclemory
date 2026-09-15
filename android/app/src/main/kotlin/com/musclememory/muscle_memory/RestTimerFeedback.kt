package com.musclememory.muscle_memory

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
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

    fun play(context: Context) {
        stop(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val channel = ensureChannel(context)
        if (!manager.areNotificationsEnabled() || channel?.importance == NotificationManager.IMPORTANCE_NONE ||
            audio.ringerMode == AudioManager.RINGER_MODE_SILENT ||
            manager.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL) return
        if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL &&
            (channel == null || channel.sound != null)) {
            try {
                player = MediaPlayer().apply {
                    setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    setDataSource(context.applicationContext, channel?.sound ?: sound(context))
                    setOnCompletionListener { finished ->
                        if (player === finished) player = null
                        finished.release()
                    }
                    prepare()
                    start()
                }
            } catch (_: Exception) { player?.release(); player = null }
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
    }

    fun stop(context: Context) {
        player?.release()
        player = null
        (context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator).cancel()
    }
}
