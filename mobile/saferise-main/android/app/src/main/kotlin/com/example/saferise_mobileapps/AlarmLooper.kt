package com.example.saferise_mobileapps

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Singleton alarm loop SafeRise.
 *
 * Suara alarm (TYPE_ALARM, USAGE_ALARM) berputar terus-menerus + getar
 * berulang dengan pattern [0,1000,500,1000,500,1000] selama ada status
 * DANGER. Dihentikan ketika push STATUS_NORMAL diterima atau user
 * membuka app dan Dart memanggil stopAlarm.
 *
 * Singleton supaya bisa dikontrol dari dua tempat:
 * - MainActivity (MethodChannel dari Dart NotificationService)
 * - MyFirebaseMessagingService (saat app background/killed)
 * sehingga tidak ada dua MediaPlayer/vibrator yang bentrok.
 */
object AlarmLooper {

    private const val TAG = "SafeRiseAlarm"

    /** Pattern getar: diam 0ms, getar 1s, diam 0.5s, getar 1s, diam 0.5s,
     *  getar 1s -- total satu siklus 4000ms. */
    private val VIBRATE_PATTERN = longArrayOf(0, 1000, 500, 1000, 500, 1000)

    /** Durasi satu siklus getar (total pattern) untuk penjadwalan ulang. */
    private const val CYCLE_MS = 4000L

    private var player: MediaPlayer? = null
    private var vibrating = false
    private var wakeLock: PowerManager.WakeLock? = null

    /**
     * Getar loop AKTIF (self-healing): pattern diputar ulang oleh Handler
     * setiap siklus, bukan mengandalkan waveform `repeat` pasif. Kalau ada
     * getar lain (notifikasi, redelivery FCM, dsb.) menimpa vibrator di
     * tengah siklus, loop pulih sendiri dalam maksimal satu siklus.
     */
    private val handler = Handler(Looper.getMainLooper())
    private val vibrateCycle = object : Runnable {
        override fun run() {
            if (!vibrating) return
            val v = vibratorFor(appContext) ?: return
            try {
                // repeat=-1 -> satu siklus penuh; Handler yang memutar ulang.
                v.vibrate(VibrationEffect.createWaveform(VIBRATE_PATTERN, -1))
            } catch (e: Exception) {
                Log.w(TAG, "Gagal memutar getaran: ${e.message}")
            }
            handler.postDelayed(this, CYCLE_MS)
        }
    }

    private var appContext: Context? = null

    val isRunning: Boolean
        get() = player?.isPlaying == true || vibrating

    @Synchronized
    fun start(context: Context) {
        // Wakelock sampai alarm di-stop agar suara tetap berbunyi saat
        // layar mati / device masuk Doze (bukan hanya 10 detik).
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "saferise:alarm_loop_wake"
            ).apply { acquire() /* dilepas di stop() */ }
        } catch (e: Exception) {
            Log.w(TAG, "Wakelock gagal: ${e.message}")
        }

        startSound(context)
        startVibration(context)
        Log.i(TAG, "🔁 Alarm loop STARTED")
    }

    @Synchronized
    fun stop(context: Context) {
        stopSound()
        stopVibration(context)
        appContext = null
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {}
        wakeLock = null
        Log.i(TAG, "⏹️ Alarm loop STOPPED")
    }

    // ------------------------------------------------------------------
    // Sound
    // ------------------------------------------------------------------

    private fun startSound(context: Context) {
        if (player?.isPlaying == true) return
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            player?.release()
            player = MediaPlayer().apply {
                setDataSource(context.applicationContext, uri)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                // Pastikan CPU tetap bangun selama alarm berbunyi di Doze.
                setWakeMode(
                    context.applicationContext,
                    PowerManager.PARTIAL_WAKE_LOCK
                )
                setVolume(1.0f, 1.0f) // volume relatif maksimal
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Gagal memulai suara alarm: ${e.message}")
        }
    }

    private fun stopSound() {
        player?.let { p ->
            try {
                if (p.isPlaying) p.stop()
                p.reset()
                p.release()
            } catch (_: Exception) {}
        }
        player = null
    }

    // ------------------------------------------------------------------
    // Vibration
    // ------------------------------------------------------------------

    private fun obtainVibrator(context: Context): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vm.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    private fun vibratorFor(context: Context?): Vibrator? {
        val ctx = context ?: return null
        return try {
            obtainVibrator(ctx).takeIf { it.hasVibrator() }
        } catch (_: Exception) {
            null
        }
    }

    private fun startVibration(context: Context) {
        if (vibrating) return
        appContext = context.applicationContext
        vibrating = true
        // Siklus pertama langsung; siklus berikutnya dijadwalkan ulang oleh
        // vibrateCycle -- sehingga getar yang tertimpa pihak lain otomatis
        // pulih dalam maksimal satu siklus.
        handler.removeCallbacks(vibrateCycle)
        handler.post(vibrateCycle)
    }

    private fun stopVibration(context: Context) {
        // Hentikan penjadwalan ulang SEBELUM cancel agar tidak ada siklus
        // baru yang menyala setelah stop.
        handler.removeCallbacks(vibrateCycle)
        vibrating = false
        // Selalu cancel -- jangan early-return walau bendera `vibrating`
        // false, karena waveform loop bisa juga dimulai dari jalur lain
        // (mis. plugin vibration Dart). Tanpa cancel di sini getar bisa
        // terus berjalan padahal suara alarm sudah mati.
        try {
            obtainVibrator(context).cancel()
        } catch (_: Exception) {}
    }
}
