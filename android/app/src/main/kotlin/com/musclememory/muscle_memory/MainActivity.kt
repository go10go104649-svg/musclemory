package com.musclememory.muscle_memory

import android.Manifest
import android.app.NotificationManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationPermissionRequested = false
    private val channelName = "com.musclememory/rest_timer"
    private val imageChannelName = "com.musclememory/workout_image"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "debugScreenshot" -> {
                        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0 ||
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                            result.notImplemented()
                        } else {
                            fun surface(view: android.view.View): android.view.SurfaceView? {
                                if (view is android.view.SurfaceView) return view
                                if (view is android.view.ViewGroup) {
                                    for (i in 0 until view.childCount) surface(view.getChildAt(i))?.let { return it }
                                }
                                return null
                            }
                            val target = surface(window.decorView)
                            if (target == null || target.width <= 0 || target.height <= 0) {
                                result.error("NO_SURFACE", "Flutter surface is not ready", null)
                            } else {
                                val bitmap = android.graphics.Bitmap.createBitmap(target.width, target.height, android.graphics.Bitmap.Config.ARGB_8888)
                                android.view.PixelCopy.request(target, bitmap, { status ->
                                    if (status == android.view.PixelCopy.SUCCESS) {
                                        val output = java.io.ByteArrayOutputStream()
                                        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output)
                                        result.success(output.toByteArray())
                                    } else result.error("PIXEL_COPY", "Could not capture Flutter surface: $status", null)
                                    bitmap.recycle()
                                }, android.os.Handler(mainLooper))
                            }
                        }
                    }
                    "debugStatus" -> {
                        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0) {
                            result.notImplemented()
                        } else {
                            result.success(mapOf("playing" to RestTimerFeedback.isPlaying, "deadline" to getSharedPreferences("rest_timer", MODE_PRIVATE).getLong("deadline", 0),
                                "delivered" to (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).activeNotifications.map { it.id }))
                        }
                    }
                    "schedule" -> {
                        val seconds = call.argument<Int>("seconds") ?: 1
                        requestNotificationPermission()
                        RestTimerFeedback.stop(this)
                        val deadline = call.argument<Number>("endsAtMilliseconds")?.toLong()
                            ?: (System.currentTimeMillis() + seconds.coerceAtLeast(1) * 1000L)
                        getSharedPreferences("rest_timer", MODE_PRIVATE).edit()
                            .putLong("deadline", deadline).apply()
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        alarmManager.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            deadline,
                            restTimerIntent()
                        )
                        result.success(null)
                    }
                    "cancel" -> {
                        getSharedPreferences("rest_timer", MODE_PRIVATE).edit().remove("deadline").apply()
                        RestTimerFeedback.stop(this)
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        alarmManager.cancel(restTimerIntent())
                        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(7341)
                        result.success(null)
                    }
                    "playCompletionFeedback" -> {
                        RestTimerFeedback.play(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, imageChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "deviceInfo") {
                    result.success(mapOf(
                        "os" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
                        "device" to "${Build.MANUFACTURER} ${Build.MODEL}"
                    ))
                    return@setMethodCallHandler
                }
                if (call.method != "save") return@setMethodCallHandler result.notImplemented()
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName")
                if (bytes == null || fileName.isNullOrBlank()) {
                    result.error("invalid_arguments", "Image bytes and file name are required", null)
                    return@setMethodCallHandler
                }
                try {
                    saveWorkoutImage(bytes, fileName)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("image_save_failed", error.localizedMessage, null)
                }
            }
    }

    override fun onResume() {
        super.onResume()
        RestTimerFeedback.foreground = true
    }

    override fun onPause() {
        RestTimerFeedback.foreground = false
        super.onPause()
    }

    private fun saveWorkoutImage(bytes: ByteArray, fileName: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/MUSCLEMORY")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create image")
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Could not open image")
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (error: Exception) {
                contentResolver.delete(uri, null, null)
                throw error
            }
            return
        }

        val pictures = getExternalFilesDir(Environment.DIRECTORY_PICTURES)
            ?: throw IllegalStateException("Pictures directory unavailable")
        val directory = java.io.File(pictures, "MUSCLEMORY").apply { mkdirs() }
        val file = java.io.File(directory, fileName)
        file.writeBytes(bytes)
        android.media.MediaScannerConnection.scanFile(
            this,
            arrayOf(file.absolutePath),
            arrayOf("image/png"),
            null
        )
    }

    private fun restTimerIntent(): PendingIntent {
        val intent = Intent(this, RestTimerReceiver::class.java)
        return PendingIntent.getBroadcast(
            this,
            7341,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun requestNotificationPermission() {
        if (!notificationPermissionRequested && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionRequested = true
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                7342
            )
        }
    }
}
