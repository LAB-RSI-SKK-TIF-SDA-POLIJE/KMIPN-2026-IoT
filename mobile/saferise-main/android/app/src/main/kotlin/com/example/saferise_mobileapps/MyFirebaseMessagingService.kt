package com.example.saferise_mobileapps

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Native FCM service untuk SafeRise.
 *
 * Extends FlutterFirebaseMessagingService (bukan FirebaseMessagingService)
 * supaya seluruh pipeline plugin (Dart streams onMessage/onBackgroundMessage,
 * background handler) TETAP berjalan -- kita hanya menambah lapisan native.
 *
 * Registered di AndroidManifest.xml menggantikan service plugin
 * (tools:node="remove") sehingga menjadi satu-satunya penerima
 * com.google.firebase.MESSAGING_EVENT.
 *
 * Tanggung jawab tambahan:
 * - Menampilkan notifikasi NATIVE untuk data-only DANGER message saat app
 *   background/killed (pesan tanpa notification payload tidak pernah
 *   ditampilkan sistem otomatis).
 * - Custom vibration pattern [0,1000,500,1000,500,1000] untuk DANGER.
 * - Wakelock singkat agar proses selesai memproses alert kritis.
 */
class MyFirebaseMessagingService : FlutterFirebaseMessagingService() {

    companion object {
        private const val TAG = "SafeRiseFCM"
        private const val CHANNEL_DANGER = "danger_alerts"
        private const val CHANNEL_NORMAL = "normal_alerts"
        private const val DANGER_NOTIFICATION_ID = 9001

        /** Di-set dari MainActivity.onResume/onPause untuk cegah duplikasi
         *  notifikasi ketika app sedang foreground (Dart sudah handle). */
        @JvmStatic
        var isAppForeground = false
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        // PENTING: teruskan ke plugin supaya Dart-side handler tetap menerima.
        super.onMessageReceived(remoteMessage)

        Log.d(TAG, "onMessageReceived: data=${remoteMessage.data}, " +
                "notification=${remoteMessage.notification != null}, " +
                "foreground=$isAppForeground")

        val data = remoteMessage.data

        // STATUS_NORMAL -> hentikan alarm loop di device (dari state apa pun).
        if (data["type"] == "STATUS_NORMAL") {
            Log.i(TAG, "✅ STATUS_NORMAL diterima -> stop alarm loop")
            AlarmLooper.stop(this)
            // Hentikan juga foreground service agar proses tidak tetap
            // berprioritas foreground setelah alarm selesai.
            AlarmService.stop(this)
            // App foreground: Dart (via AppState) sudah menangani notif "aman".
            if (!isAppForeground && remoteMessage.notification == null) {
                showNormalNotification(data)
            }
            return
        }

        if (data["type"] != "DANGER_ALERT") return

        // App foreground -> Dart NotificationService + AppState yang
        // menangani notifikasi dan alarm loop; jangan dobel di sini.
        if (isAppForeground) {
            Log.d(TAG, "App foreground, skip native notification (Dart handles)")
            return
        }

        // App background/killed: posting notifikasi DULU, baru mulai alarm
        // loop native (suara + getar berulang sampai push STATUS_NORMAL
        // diterima / user buka app).
        //
        // URUTAN PENTING: notifikasi DANGER tampil di channel dengan
        // vibrationPattern one-shot. Jika diposting SETELAH AlarmLooper.start,
        // getar notifikasi MENIMPA waveform loop sehingga getar berhenti
        // setelah sekali putar padahal suara masih bunyi. Dengan urutan ini
        // waveform loop adalah yang terakhir memegang vibrator -> looping.
        acquireBriefWakelock()
        if (remoteMessage.notification == null) {
            showDangerNotification(data)
        }
        AlarmLooper.start(this)
        // Foreground service: pemilik alarm yang sesungguhnya. Tanpa ini,
        // Android 12+ membekukan proses cached di background (Cached App
        // Freezer) dan seluruh loop ikut berhenti.
        AlarmService.start(this)
    }

    /**
     * Wakelock singkat (10 detik) agar CPU tetap aktif sampai notifikasi
     * selesai diposting untuk pesan high-priority saat device dozing.
     */
    private fun acquireBriefWakelock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "saferise:danger_alert_wake"
            )
            wakeLock.acquire(10_000L)
        } catch (e: Exception) {
            Log.w(TAG, "Wakelock gagal: ${e.message}")
        }
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (manager.getNotificationChannel(CHANNEL_DANGER) == null) {
            val channel = NotificationChannel(
                CHANNEL_DANGER,
                "Danger Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Critical security alerts that require immediate attention"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    null
                )
                enableLights(true)
                lightColor = android.graphics.Color.RED
            }
            manager.createNotificationChannel(channel)
        }

        if (manager.getNotificationChannel(CHANNEL_NORMAL) == null) {
            val channel = NotificationChannel(
                CHANNEL_NORMAL,
                "Normal Alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Standard security notifications"
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun showDangerNotification(data: Map<String, String>) {
        ensureChannels()

        val cameraId = data["cameraId"] ?: "UNKNOWN"
        val location = data["location"]?.takeIf { it.isNotBlank() }
            ?: "Lokasi tidak diketahui"
        val confidence = data["confidence"] ?: "-"
        val title = data["title"] ?: "⚠️ PERINGATAN BAHAYA!"
        val body = "Bahaya terdeteksi di $location. Confidence: $confidence%"

        // Tap -> buka MainActivity (launch intent), Dart getInitialMessage /
        // navigationKey akan mengarahkan ke CameraDetailScreen via payload.
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            cameraId.hashCode(),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val fullScreenIntent = PendingIntent.getActivity(
            this,
            cameraId.hashCode(),
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("cameraId", cameraId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_DANGER)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(fullScreenIntent, true)
            .setVibrate(longArrayOf(0, 1000, 500, 1000, 500, 1000))
            .build()

        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(DANGER_NOTIFICATION_ID, notification)
        Log.i(TAG, "🚨 Native DANGER notification posted for $cameraId")
    }

    private fun showNormalNotification(data: Map<String, String>) {
        ensureChannels()

        val cameraId = data["cameraId"] ?: "UNKNOWN"
        val notification = NotificationCompat.Builder(this, CHANNEL_NORMAL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(data["title"] ?: "✅ Situasi Aman")
            .setContentText("${data["cameraId"] ?: cameraId} kembali normal. Alarm dihentikan.")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()

        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(DANGER_NOTIFICATION_ID + 1, notification)
        Log.i(TAG, "✅ Native NORMAL notification posted for $cameraId")
    }
}
