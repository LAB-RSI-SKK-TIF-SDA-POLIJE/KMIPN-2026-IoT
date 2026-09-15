import '../models/camera.dart';
import '../models/camera_status.dart';
import 'app_state.dart';
import 'notification_service.dart';

/// Tingkat keparahan alert berdasarkan confidence level.
/// - >= 90 : critical (getaran panjang + channel danger)
/// - >= 75 : high
/// - < 75  : warning
enum AlertSeverity { critical, high, warning }

extension AlertSeverityX on AlertSeverity {
  String get titlePrefix {
    switch (this) {
      case AlertSeverity.critical:
        return '🚨 BAHAYA KRITIS!';
      case AlertSeverity.high:
        return '⚠️ PERINGATAN BAHAYA!';
      case AlertSeverity.warning:
        return '⚠️ Peringatan Dini';
    }
  }
}

/// Bridges AppState camera-status changes to local notifications.
///
/// Listens to AppState (ChangeNotifier), detects transitions into
/// DANGER, and fires local notifications (+ vibration) with severity
/// derived from the detection confidence. Also fires an informational
/// notification when a camera returns to NORMAL.
class AlertService {
  AlertService({
    required AppState appState,
    NotificationService? notificationService,
  })  : _appState = appState,
        _notifications = notificationService ?? NotificationService() {
    // Snapshot status awal supaya tidak spam notifikasi saat startup.
    for (final camera in _appState.cameras) {
      _previousStatuses[camera.id] = camera.status;
    }
    _appState.addListener(_onStateChanged);
    _instance = this;
    print('[Alert] ✅ AlertService attached (${_previousStatuses.length} cameras)');

    // Sinkronkan alarm dengan kondisi awal: jika ada kamera yang sudah
    // DANGER sejak startup, alarm langsung berbunyi sampai kembali NORMAL.
    _syncAlarmLoop();
  }

  /// Instance aktif -- di-set saat konstruktor berjalan (dari main.dart),
  /// memudahkan akses dari layar debugging tanpa InheritedWidget tambahan.
  static AlertService? _instance;
  static AlertService get instance =>
      _instance ?? (throw StateError('AlertService belum di-initialize'));

  final AppState _appState;
  final NotificationService _notifications;
  final Map<String, CameraStatus> _previousStatuses = {};

  /// Akses AppState dari luar (untuk fallback navigasi notifikasi).
  AppState get appState => _appState;

  /// Dipanggil setiap AppState.notifyListeners() (payload MQTT masuk).
  void _onStateChanged() {
    // Selama sinkronisasi dari backend (startup / resume app), transisi
    // status TIDAK memunculkan notifikasi -- notifikasi hanya untuk event
    // live dari HiveMQ. Snapshot status & alarm loop tetap disinkronkan.
    final silent = _appState.syncingFromBackend;

    for (final camera in _appState.cameras) {
      final previous = _previousStatuses[camera.id];
      if (previous == null || previous == camera.status) continue;

      _previousStatuses[camera.id] = camera.status;

      if (silent) continue;

      if (camera.status == CameraStatus.danger &&
          previous != CameraStatus.danger) {
        _fireDangerAlert(camera);
      } else if (camera.status == CameraStatus.normal &&
          previous == CameraStatus.danger) {
        _fireResolvedAlert(camera);
      }
    }

    // Getar + suara terus-menerus selama ada DANGER,
    // berhenti otomatis saat semua kamera kembali NORMAL.
    _syncAlarmLoop();
  }

  /// Alarm loop: aktif selama `dangerCamera != null`.
  /// Idempotent -- NotificationService menjaga agar tidak double-start.
  void _syncAlarmLoop() {
    final hasDanger = _appState.dangerCamera != null;
    if (hasDanger) {
      _notifications.startAlarmLoop();
    } else {
      _notifications.stopAlarmLoop();
    }
  }

  /// Peta confidence (0-100) -> severity alert.
  AlertSeverity _severityFor(int confidence) {
    if (confidence >= 90) return AlertSeverity.critical;
    if (confidence >= 75) return AlertSeverity.high;
    return AlertSeverity.warning;
  }

  Future<void> _fireDangerAlert(Camera camera) async {
    final severity = _severityFor(camera.confidence);
    final location = '${camera.building}, ${camera.floor}';

    print('[Alert] 🚨 DANGER on ${camera.id} '
        '(confidence=${camera.confidence}%, severity=${severity.name})');

    await _notifications.showNotification(
      title: '${severity.titlePrefix} - ${camera.sector}',
      body: 'Terdeteksi bahaya di $location. '
          'Confidence: ${camera.confidence}%.',
      channelId: 'danger_alerts',
      payload: camera.id,
      vibrate: true,
    );
  }

  Future<void> _fireResolvedAlert(Camera camera) async {
    print('[Alert] ✅ ${camera.id} kembali NORMAL');

    await _notifications.showNotification(
      title: '✅ Situasi Aman - ${camera.sector}',
      body: '${camera.building}, ${camera.floor} kembali normal.',
      channelId: 'normal_alerts',
      payload: camera.id,
      vibrate: false,
    );
  }

  /// Simulasi alert dari UI untuk debugging -- memicu notifikasi DANGER
  /// seolah-olah kamera ini baru saja mendeteksi bahaya.
  Future<void> simulateDangerAlert(String cameraId) async {
    Camera? camera;
    for (final c in _appState.cameras) {
      if (c.id == cameraId) {
        camera = c;
        break;
      }
    }
    if (camera == null) {
      print('[Alert] ⚠️ simulateDangerAlert: kamera $cameraId tidak dikenal');
      return;
    }
    await _fireDangerAlert(camera);
  }

  void dispose() {
    _appState.removeListener(_onStateChanged);
    // Pastikan alarm tidak menyala terus setelah service dilepas.
    _notifications.stopAlarmLoop();
    print('[Alert] 🔌 AlertService detached');
  }
}
