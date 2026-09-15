import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'screens/home_shell.dart';
import 'services/alert_service.dart';
import 'services/app_state.dart';
import 'services/app_state_scope.dart';
import 'services/firebase_service.dart';
import 'services/mqtt_service.dart';
import 'services/notification_service.dart';
import 'theme/app_colors.dart';

/// Background message handler - must be top-level function
///
/// DANGER_ALERT / STATUS_NORMAL TIDAK ditangani di sini: native
/// MyFirebaseMessagingService sudah posting notifikasi + start/stop
/// AlarmLooper (suara + getar loop) saat app background/killed. Jika
/// isolate Dart ikut mem-vibrate/menampilkan notif, hasilnya dobel dan
/// one-shot vibration dari sini MENIMPA getar loop native sehingga HP
/// terasa berhenti bergetar padahal suara masih bunyi.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final type = message.data['type'];
  if (type == 'DANGER_ALERT' || type == 'STATUS_NORMAL') return;

  print('[Firebase] Background message received: ${message.notification?.title}');
  await NotificationService().initialize();
  await NotificationService().showNotificationFromFCM(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await FirebaseService().initialize();

  // Initialize Notification Service
  await NotificationService().initialize();

  // Setup background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Buat AppState SEDINI dan daftarkan ke FirebaseService supaya
  // notification tap (foreground/background/killed) selalu punya
  // referensi AppState -- tidak bergantung pada widget tree.
  //
  // RealMqttService dipakai saat MQTT_HOST di-set via --dart-define;
  // tanpa itu app tetap jalan dengan DummyMqttService (mode simulasi).
  //
  // --dart-define=MQTT_DEBUG=true : cetak log packet-level mqtt_client
  // --dart-define=MQTT_SECURE=false : override TLS otomatis (default: on
  //   saat port 8883)
  const mqttHost = String.fromEnvironment('MQTT_HOST');
  final appState = AppState(
    mqttService: mqttHost.isNotEmpty
        ? RealMqttService(
            host: mqttHost,
            port: const int.fromEnvironment('MQTT_PORT', defaultValue: 1883),
            username: const String.fromEnvironment('MQTT_USERNAME'),
            password: const String.fromEnvironment('MQTT_PASSWORD'),
            secure: bool.hasEnvironment('MQTT_SECURE')
                ? bool.fromEnvironment('MQTT_SECURE')
                : null,
            verbose: const bool.fromEnvironment('MQTT_DEBUG',
                defaultValue: false),
          )
        : DummyMqttService(),
  );
  FirebaseService().setAppState(appState);

  runApp(SafeRiseApp(appState: appState));
}

class SafeRiseApp extends StatefulWidget {
  const SafeRiseApp({super.key, required this.appState});

  final AppState appState;

  @override
  State<SafeRiseApp> createState() => _SafeRiseAppState();
}

class _SafeRiseAppState extends State<SafeRiseApp>
    with WidgetsBindingObserver {
  final _firebaseService = FirebaseService();
  final _notificationService = NotificationService();
  // AlertService listen status kamera di AppState -> trigger notifikasi
  // lokal + vibration saat ada kamera berubah ke DANGER.
  late final AlertService _alertService = AlertService(appState: widget.appState);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Pastikan AlertService terpasang segera setelah state dibuat.
    _alertService;
    _setupFCMListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Saat user kembali ke app (resume), sinkronkan status kamera dari
    // backend. Tanpa ini, transisi DANGER -> NORMAL yang terjadi selama
    // app di background tidak pernah terlihat: main isolate Dart beku dan
    // retained MQTT hanya dikirim saat subscribe, bukan saat resume --
    // sehingga UI bisa masih menampilkan DANGER padahal sudah NORMAL.
    if (state == AppLifecycleState.resumed) {
      print('[AppState] 👀 App resumed -> sync status dari backend');
      widget.appState.syncStatusesFromBackend();
    }
  }

  /// Setup listeners untuk FCM messages
  void _setupFCMListeners() {
    // Handle foreground messages.
    // DANGER_ALERT / STATUS_NORMAL di-route ke AppState supaya AlertService
    // yang menangani notifikasi + alarm loop (getar & suara berulang sampai
    // status kembali NORMAL) -- tidak ada notifikasi dobel.
    _firebaseService.messageStream.listen((message) {
      print('[FCM] Foreground message: ${message.notification?.title}');
      final data = message.data;
      final type = data['type'];
      if (type == 'DANGER_ALERT' || type == 'STATUS_NORMAL') {
        final handled = widget.appState.applyExternalAlert(
          cameraId: data['cameraId'] ?? '',
          danger: type == 'DANGER_ALERT',
          confidence: num.tryParse(data['confidence'] ?? ''),
          // Timestamp asli event dari backend -- dipakai guard update basi
          // untuk menolak FCM yang telat datang setelah pesan MQTT lebih baru.
          timestamp: data['timestamp'],
        );
        if (handled) return;
      }
      // Fallback: tipe lain / cameraId tak dikenal -> tampilkan langsung.
      _notificationService.showNotificationFromFCM(message);
    });

    // Handle notification opened
    _firebaseService.notificationOpenedStream.listen((message) {
      print('[FCM] Notification opened: ${message.data}');
      _handleNotificationOpen(message);
    });

    // Check for initial message (app opened from notification - killed state)
    _firebaseService.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotificationOpen(message);
      }
    });
  }

  /// Handle notification open - navigate ke camera detail
  void _handleNotificationOpen(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'DANGER_ALERT') {
      final cameraId = data['cameraId'] ?? '';
      // Delay singkat agar Navigator sudah siap saat app dibuka dari
      // notifikasi (killed state).
      Future.delayed(const Duration(milliseconds: 500), () {
        if (cameraId.isNotEmpty) {
          _firebaseService.navigateToCameraDetail(cameraId);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertService.dispose();
    widget.appState.mqttService.disconnect();
    _firebaseService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeRise',
      debugShowCheckedModeBanner: false,
      navigatorKey: FirebaseService.navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.blue),
        fontFamily: 'Roboto',
      ),
      home: AppStateScope(
        appState: widget.appState,
        child: const HomeShell(),
      ),
    );
  }
}
