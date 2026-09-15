import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vibration/vibration.dart';
import 'dart:io' show Platform;
import 'dart:typed_data' show Int64List;

import 'firebase_service.dart';

/// Service untuk handle local notifications dan vibration
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Channel ke native alarm player (MainActivity) untuk suara alarm
  /// yang berputar terus-menerus via system alarm sound.
  static const MethodChannel _alarmChannel = MethodChannel('saferise.alarm');

  bool _isInitialized = false;
  bool _alarmActive = false;

  /// Initialize notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Android initialization
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS initialization
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create notification channels untuk Android
      await _createNotificationChannels();

      _isInitialized = true;
      print('[Notification] ✅ Notification service initialized');
    } catch (e) {
      print('[Notification] ❌ Error initializing notifications: $e');
    }
  }

  static final Int64List _dangerVibrationPattern = Int64List.fromList([0, 1000, 500, 1000, 500, 1000]);

  /// Create notification channels (Android only)
  Future<void> _createNotificationChannels() async {
    if (!Platform.isAndroid) return;

    // Channel untuk DANGER alerts
    final AndroidNotificationChannel dangerChannel = AndroidNotificationChannel(
      'danger_alerts', // id
      'Danger Alerts', // name
      description: 'Critical security alerts that require immediate attention',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _dangerVibrationPattern,
      showBadge: true,
      // Tampil full-screen/heads-up untuk alert kritis (lock screen)
      enableLights: true,
      ledColor: const Color.fromARGB(255, 255, 0, 0),
    );

    // Channel untuk normal alerts
    final AndroidNotificationChannel normalChannel = AndroidNotificationChannel(
      'normal_alerts', // id
      'Normal Alerts', // name
      description: 'Standard security notifications',
      importance: Importance.defaultImportance,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    // Register channels
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(dangerChannel);

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(normalChannel);

    print('[Notification] ✅ Notification channels created');
  }

  /// Show notification from FCM message
  Future<void> showNotificationFromFCM(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    if (notification == null) return;

    final isDanger = data['type'] == 'DANGER_ALERT';
    final channelId = isDanger ? 'danger_alerts' : 'normal_alerts';

    await showNotification(
      title: notification.title ?? 'SafeRise Alert',
      body: notification.body ?? '',
      channelId: channelId,
      payload: data['cameraId'] ?? '',
      vibrate: isDanger,
    );
  }

   /// Show custom notification
  Future<void> showNotification({
    required String title,
    required String body,
    String channelId = 'normal_alerts',
    String? payload,
    bool vibrate = false,
  }) async {
    if (!_isInitialized) {
      print('[Notification] ⚠️ Service not initialized');
      return;
    }

    try {
      // Channel details dinamis berdasarkan channelId:
      // - danger_alerts: high importance + priority + vibration pattern panjang
      // - normal_alerts: default importance + priority, vibration standar
      final isDanger = channelId == 'danger_alerts';
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        channelId,
        isDanger ? 'Danger Alerts' : 'Normal Alerts',
        channelDescription: isDanger
            ? 'Critical security alerts'
            : 'Standard security notifications',
        importance: isDanger ? Importance.high : Importance.defaultImportance,
        priority: isDanger ? Priority.high : Priority.defaultPriority,
        playSound: true,
        enableVibration: true,
        vibrationPattern: isDanger ? _dangerVibrationPattern : null,
        icon: '@mipmap/ic_launcher',
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      // Vibrate jika diminta.
      // Skip saat alarm loop aktif -- getar sekali jalan di sini akan
      // MENIMPA pattern looping dari startAlarmLoop() sehingga getar
      // terasa berhenti sebentar padahal suara masih berputar.
      if (vibrate && !_alarmActive) {
        await _triggerVibration();
      }

      print('[Notification] ✅ Notification shown: $title');
    } catch (e) {
      print('[Notification] ❌ Error showing notification: $e');
    }
  }

  /// Trigger vibration dengan pattern untuk DANGER
  Future<void> _triggerVibration() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Pattern: wait 0ms, vibrate 1000ms, wait 500ms, vibrate 1000ms, wait 500ms, vibrate 1000ms
        await Vibration.vibrate(
          pattern: [0, 1000, 500, 1000, 500, 1000],
        );
        print('[Notification] 📳 Vibration triggered');
      }
    } catch (e) {
      print('[Notification] ⚠️ Error triggering vibration: $e');
    }
  }

  // ==========================================================================
  // ALARM LOOP: getar + suara terus-menerus selama ada status DANGER.
  // Dipanggil AlertService saat transisi ke DANGER / kembali NORMAL.
  // ==========================================================================

  /// Mulai alarm berulang.
  ///
  /// Seluruh loop (suara + getar + wakelock) dipegang SATU sumber kebenaran:
  /// native AlarmLooper via MethodChannel. Dart tidak lagi mem-vibrate
  /// sendiri -- pattern dari plugin vibration bisa menimpa (atau tertimpa)
  /// waveform native sehingga getar "mati" padahal suara masih bunyi,
  /// atau sebaliknya tetap bergetar saat alarm sudah di-stop.
  Future<void> startAlarmLoop() async {
    if (_alarmActive) return;
    _alarmActive = true;

    print('[Notification] 🔁 ALARM STARTED (continuous until NORMAL)');

    try {
      await _alarmChannel.invokeMethod('startAlarm');
    } on MissingPluginException {
      print('[Notification] ⚠️ Native alarm player tidak tersedia (iOS?)');
      // Fallback minimal: tanpa native, pakai plugin vibration looping.
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          await Vibration.vibrate(
            pattern: [0, 800, 400, 800, 400, 800],
            repeat: 1, // loop mulai dari index 1 -> vibrate-pause tanpa henti
            amplitude: 255,
          );
        }
      } catch (e) {
        print('[Notification] ⚠️ Alarm vibration error: $e');
      }
    } catch (e) {
      print('[Notification] ⚠️ Native alarm error: $e');
    }
  }

  /// Hentikan seluruh alarm (vibration + sound).
  ///
  /// Vibration.cancel() tetap dipanggil sebagai safety net untuk pattern
  /// yang mungkin tersisa dari jalur non-loop (mis. fallback di atas).
  Future<void> stopAlarmLoop() async {
    if (!_alarmActive) return;
    _alarmActive = false;

    print('[Notification] ⏹️ ALARM STOPPED');

    try {
      await Vibration.cancel();
    } catch (_) {}

    try {
      await _alarmChannel.invokeMethod('stopAlarm');
    } catch (_) {}
  }

  /// Handle notification tap -- buka camera detail lewat HomeShell
  /// (delegasi ke FirebaseService agar tampilan konsisten dengan app).
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    print('[Notification] 🔔 Notification tapped with payload: $payload');

    if (payload != null && payload.isNotEmpty) {
      FirebaseService().navigateToCameraDetail(payload);
    }
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
    print('[Notification] 🗑️ All notifications cancelled');
  }

  /// Cancel specific notification
  Future<void> cancel(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
    print('[Notification] 🗑️ Notification $id cancelled');
  }
}
