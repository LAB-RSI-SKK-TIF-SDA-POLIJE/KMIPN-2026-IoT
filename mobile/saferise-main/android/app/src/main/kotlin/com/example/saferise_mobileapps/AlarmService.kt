package com.example.saferise_mobileapps

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground Service pemilik alarm loop SafeRise.
 *
 * Android 12+ MEMBEKUKAN proses yang tidak punya komponen aktif di
 * foreground (Cached App Freezer) -- semua thread/Handler ikut berhenti,
 * sehingga loop getar/suara alarm "mati" beberapa detik setelah app masuk
 * background. Dengan menjalankan alarm sebagai foreground service (dengan
 * notifikasi ongoing), proses mendapat prioritas FOREGROUND sehingga TIDAK
 * bisa dibekukan/dibunuh -- suara + getar loop berjalan stabil sampai
 * push STATUS_NORMAL diterima atau user menghentikannya lewat app.
 *
 * Kontrol dari MyFirebaseMessagingService (background/killed):
 * - DANGER_ALERT  -> AlarmService.start() : promosi foreground + AlarmLooper.start
 * - STATUS_NORMAL -> AlarmService.stop()  : AlarmLooper.stop + lepas foreground
 */
class AlarmService : Service() {

    companion object {
        private const val TAG = "SafeRiseAlarmSvc"
        private const val CHANNEL_ID = "alarm_service"
        private const val NOTIFICATION_ID = 9002
        const val ACTION_START_ALARM = "saferise.action.START_ALARM"
        const val ACTION_STOP_ALARM = "saferise.action.STOP_ALARM"

        /** Mulai alarm sebagai foreground service (aman dipanggil dari background). */
        fun start(context: Context) {
            val intent = Intent(context, AlarmService::class.java)
                .setAction(ACTION_START_ALARM)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** Hentikan alarm + lepas status foreground service. */
        fun stop(context: Context) {
            val intent = Intent(context, AlarmService::class.java)
                .setAction(ACTION_STOP_ALARM)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // WAJIB: service selalu di-start lewat startForegroundService()
        // (termasuk untuk aksi STOP) sehingga harus segera memanggil
        // startForeground() agar sistem tidak melempar exception/ANR.
        promoteToForeground()

        when (intent?.action) {
            ACTION_STOP_ALARM -> {
                Log.i(TAG, "⏹️ STOP alarm via foreground service")
                AlarmLooper.stop(this)
                stopForegroundAndSelf()
                return START_NOT_STICKY
            }
            else -> {
                Log.i(TAG, "▶️ START alarm via foreground service")
                AlarmLooper.start(this)
            }
        }
        return START_STICKY
    }

    private fun promoteToForeground() {
        ensureChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("SafeRise - Alarm Aktif")
            .setContentText("Terdeteksi bahaya. Alarm berbunyi sampai situasi aman.")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        // Channel LOW importance tanpa suara/getar: hanya sebagai penanda
        // foreground service -- alert sesungguhnya lewat channel danger_alerts.
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Alarm Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Menjaga agar alarm keamanan tetap berjalan di background"
                setSound(null, null)
                enableVibration(false)
            }
        )
    }

    private fun stopForegroundAndSelf() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }
}
