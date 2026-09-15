import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

import 'app_state.dart';
import 'firebase_options.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();

  factory FirebaseService() {
    return _instance;
  }

  FirebaseService._internal();

  /// Global navigator key agar notifikasi bisa navigate dari mana saja
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  AppState? _appState;
  FirebaseMessaging? _firebaseMessaging;
  SharedPreferences? _prefs;

  // Streams untuk komunikasi dengan app
  final _tokenStream = StreamController<String>.broadcast();
  final _messageStream = StreamController<RemoteMessage>.broadcast();
  final _notificationOpenedStream = StreamController<RemoteMessage>.broadcast();

  Stream<String> get tokenStream => _tokenStream.stream;
  Stream<RemoteMessage> get messageStream => _messageStream.stream;
  Stream<RemoteMessage> get notificationOpenedStream => _notificationOpenedStream.stream;

  String? _currentToken;
  String? get currentToken => _currentToken;

  /// Backend URL untuk mengirim token.
  /// Override saat build/run: --dart-define=BACKEND_URL=http://192.168.x.x:3000
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// Initialize Firebase dan setup FCM
  Future<void> initialize() async {
    try {
      // Plugin FCM Android sudah auto-init [DEFAULT] via google-services.json
      // sebelum main() berjalan -- init ulang akan throw duplicate-app,
      // jadi tangkap dan lanjutkan (app tetap valid).
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print('[Firebase] ✅ Firebase.initializeApp success');
      } on FirebaseException catch (e) {
        if (e.code == 'duplicate-app') {
          print('[Firebase] ℹ️ Already initialized natively '
              '(google-services.json), continuing');
        } else {
          rethrow;
        }
      }

      _firebaseMessaging = FirebaseMessaging.instance;
      _prefs = await SharedPreferences.getInstance();

      // Request notification permissions (Android 13+)
      await _requestNotificationPermissions();

      // Get initial token
      await _getAndSaveToken();

      // Setup message handlers
      _setupMessageHandlers();

      // Listen untuk token refresh
      _firebaseMessaging!.onTokenRefresh.listen((newToken) {
        _handleTokenRefresh(newToken);
      });

      print('[Firebase] ✅ Firebase initialized successfully');
      print('[Firebase] 📱 Current FCM token: $_currentToken');
    } catch (e) {
      print('[Firebase] ❌ Error initializing Firebase: $e');
    }
  }

  /// Set AppState reference untuk navigasi dari notifikasi
  void setAppState(AppState appState) {
    _appState = appState;
    print('[Firebase] ✅ AppState reference set');
  }

  /// Request notification permissions (iOS dan Android 13+)
  Future<void> _requestNotificationPermissions() async {
    if (_firebaseMessaging == null) return;

    try {
      final settings = await _firebaseMessaging!.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      print('[Firebase] 📬 Notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      print('[Firebase] ⚠️ Error requesting permissions: $e');
    }
  }

  /// Get FCM token dan simpan ke shared preferences.
  ///
  /// Skip pengiriman ke backend jika token sudah pernah berhasil diregistrasi
  /// KE BACKEND YANG SAMA (tersimpan di 'registered_token' +
  /// 'registered_backend') -- app restart tidak spam endpoint /api/tokens.
  /// Status per-backend penting: pindah dari backend lokal ke cloud (mis.
  /// Railway) harus memicu registrasi ulang, karena server baru belum
  /// memiliki token tersebut walau token FCM-nya tidak berubah.
  Future<void> _getAndSaveToken() async {
    try {
      if (_firebaseMessaging == null) return;

      final token = await _firebaseMessaging!.getToken();

      if (token != null) {
        _currentToken = token;

        // Simpan ke shared preferences
        await _prefs?.setString('fcm_token', token);

        final registeredToken = _prefs?.getString('registered_token');
        final registeredBackend = _prefs?.getString('registered_backend');
        final candidates = _backendUrlCandidates();

        // Skip hanya jika token sama DAN backend-nya juga sama (masih ada
        // di daftar kandidat aktif saat ini).
        if (registeredToken == token &&
            registeredBackend != null &&
            candidates.contains(registeredBackend)) {
          print('[Firebase] ℹ️ Token already registered to $registeredBackend, skipping send');
        } else {
          // Token baru / backend berganti / registrasi sebelumnya gagal
          // -> kirim ke backend.
          await _sendTokenToBackend(token);
        }

        _tokenStream.add(token);
        print('[Firebase] ✅ FCM token obtained and saved');
      }
    } catch (e) {
      print('[Firebase] ❌ Error getting FCM token: $e');
    }
  }

  /// Handle token refresh.
  ///
  /// Token lama dihapus dari backend agar registry tidak menumpuk token
  /// mati (FCM tetap mengirim ke token lama yang belum expired, sehingga
  /// tanpa cleanup bisa terjadi notifikasi dobel).
  Future<void> _handleTokenRefresh(String newToken) async {
    final oldToken = _currentToken;
    _currentToken = newToken;
    _tokenStream.add(newToken);

    // Simpan token baru
    await _prefs?.setString('fcm_token', newToken);

    // Hapus token lama dari backend (fire-and-forget), lalu daftarkan baru.
    if (oldToken != null && oldToken != newToken) {
      unawaited(_deleteTokenFromBackend(oldToken));
    }
    await _sendTokenToBackend(newToken);

    print('[Firebase] 🔄 FCM token refreshed');
  }

  /// Send token ke backend service dengan retry logic (max 3 attempts).
  ///
  /// Mencoba beberapa kandidat URL agar bekerja di semua skenario:
  /// - HP fisik via `adb reverse tcp:3000 tcp:3000` -> localhost
  /// - Emulator Android -> localhost emulator = emulator itu sendiri,
  ///   host PC harus diakses lewat alias khusus 10.0.2.2
  /// - Backend di LAN/server -> atur lewat --dart-define=BACKEND_URL=...
  /// Daftar kandidat URL backend (urutan prioritas):
  /// - HP fisik via `adb reverse tcp:3000 tcp:3000` -> localhost
  /// - Emulator Android -> host PC diakses lewat alias khusus 10.0.2.2
  /// - Backend di LAN/cloud -> atur lewat --dart-define=BACKEND_URL=...
  List<String> _backendUrlCandidates() {
    return [
      if (const String.fromEnvironment('BACKEND_URL').isNotEmpty)
        const String.fromEnvironment('BACKEND_URL'),
      backendUrl,
      'http://10.0.2.2:3000', // alias host loopback dari Android emulator
    ];
  }

  Future<void> _sendTokenToBackend(String token, {int attempt = 1}) async {
    const maxAttempts = 3;
    try {
      final candidates = _backendUrlCandidates();

      String? successBase;
      for (final base in candidates.toSet()) {
        try {
          final response = await http
              .post(
                Uri.parse('$base/api/tokens'),
                headers: {'Content-Type': 'application/json'},
                body: '{"token":"$token"}',
              )
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            successBase = base;
            break;
          }
          print('[Firebase] ⚠️ $base responded with status: ${response.statusCode}');
        } catch (e) {
          print('[Firebase] ℹ️ Gagal ke $base: ${e.toString().split('\n').first}');
        }
      }

      if (successBase != null) {
        print('[Firebase] ✅ Token sent to backend successfully ($successBase)');
        // Simpan status registrasi agar tidak retry saat app restart --
        // catat JUGA backend mana yang berhasil, supaya pindah backend
        // (lokal <-> cloud) memicu registrasi ulang secara otomatis.
        await _prefs?.setString('registered_token', token);
        await _prefs?.setString('registered_backend', successBase);
      } else {
        _scheduleRetry(token, attempt, maxAttempts);
      }
    } catch (e) {
      print('[Firebase] ⚠️ Error sending token to backend (attempt $attempt): $e');
      _scheduleRetry(token, attempt, maxAttempts);
    }
  }

  /// Schedule ulang pengiriman token dengan delay (exponential backoff sederhana)
  void _scheduleRetry(String token, int attempt, int maxAttempts) {
    if (attempt >= maxAttempts) {
      print('[Firebase] ❌ Max retry attempts reached. Token not registered.');
      return;
    }
    final delay = Duration(seconds: attempt * 5);
    Timer(delay, () {
      print('[Firebase] 🔄 Retrying token registration (attempt ${attempt + 1})...');
      _sendTokenToBackend(token, attempt: attempt + 1);
    });
  }

  /// Hapus token lama dari backend (dipanggil saat FCM token refresh).
  /// Fire-and-forget: kegagalan tidak fatal karena backend juga membersihkan
  /// token invalid otomatis saat pengiriman FCM gagal.
  Future<void> _deleteTokenFromBackend(String token) async {
    final candidates = _backendUrlCandidates().toSet();
    for (final base in candidates) {
      try {
        final response = await http
            .delete(Uri.parse('$base/api/tokens/$token'))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200 || response.statusCode == 404) {
          print('[Firebase] 🗑️ Old token removed from backend ($base)');
          return;
        }
      } catch (_) {
        // Coba kandidat berikutnya.
      }
    }
    print('[Firebase] ⚠️ Failed to delete old token from backend');
  }

  /// Setup message handlers untuk foreground dan background
  void _setupMessageHandlers() {
    if (_firebaseMessaging == null) return;

    // Handle notification ketika app di foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('[Firebase] 📨 Message received while foreground:');
      print('  Title: ${message.notification?.title}');
      print('  Body: ${message.notification?.body}');
      _messageStream.add(message);
    });

    // Handle notification click (app di foreground atau background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('[Firebase] 🔔 Notification opened from app:');
      print('  Title: ${message.notification?.title}');
      _notificationOpenedStream.add(message);
      _navigateToScreen(message);
    });
  }

  /// Get initial message jika app dibuka dari notification (killed state)
  Future<RemoteMessage?> getInitialMessage() async {
    try {
      final message = await _firebaseMessaging?.getInitialMessage();
      if (message != null) {
        print('[Firebase] 📭 App opened from notification (killed state):');
        print('  Title: ${message.notification?.title}');
        _notificationOpenedStream.add(message);
        return message;
      }
    } catch (e) {
      print('[Firebase] ⚠️ Error getting initial message: $e');
    }
    return null;
  }

  /// Navigate ke screen berdasarkan notification data
  void _navigateToScreen(RemoteMessage message) {
    final data = message.data;

    if (data['type'] == 'DANGER_ALERT') {
      final cameraId = data['cameraId'] ?? '';
      if (cameraId.isNotEmpty) {
        navigateToCameraDetail(cameraId);
      }
    }
  }

  /// Buka camera detail dari notification tap.
  /// Tidak push route baru -- kirim request ke AppState yang didengarkan
  /// HomeShell, sehingga halaman tampil DI DALAM shell (tema konsisten).
  void navigateToCameraDetail(String cameraId) {
    if (cameraId.isEmpty) return;
    print('[Firebase] 🚨 Request open camera detail: $cameraId');
    _appState?.requestOpenCamera(cameraId);
  }

  /// Get saved token dari shared preferences
  Future<String?> getSavedToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('fcm_token');
    } catch (e) {
      print('[Firebase] ⚠️ Error getting saved token: $e');
      return null;
    }
  }

  /// Cleanup streams
  void dispose() {
    _tokenStream.close();
    _messageStream.close();
    _notificationOpenedStream.close();
  }
}
