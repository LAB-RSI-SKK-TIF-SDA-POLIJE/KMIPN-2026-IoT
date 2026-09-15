package com.example.saferise_mobileapps

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Channel untuk alarm loop (suara + getar DANGER berputar terus).
        // Implementasi ada di AlarmLooper (singleton) supaya state konsisten
        // dengan handler FCM native saat app background/killed.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "saferise.alarm"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAlarm" -> {
                    AlarmLooper.start(this)
                    result.success(true)
                }
                "stopAlarm" -> {
                    AlarmLooper.stop(this)
                    // Lepas juga foreground service agar notifikasi ongoing
                    // hilang dan proses kembali normal.
                    AlarmService.stop(this)
                    result.success(true)
                }
                "isAlarming" -> {
                    result.success(AlarmLooper.isRunning)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        MyFirebaseMessagingService.isAppForeground = true
    }

    override fun onPause() {
        MyFirebaseMessagingService.isAppForeground = false
        super.onPause()
    }

    override fun onDestroy() {
        // Safety: jangan biarkan alarm bunyi terus setelah activity dimatikan.
        // (AlarmService tetap bisa menyala lagi dari push DANGER berikutnya.)
        AlarmLooper.stop(this)
        super.onDestroy()
    }
}
