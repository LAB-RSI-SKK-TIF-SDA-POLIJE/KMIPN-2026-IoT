import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../data/dummy_data.dart';
import '../models/camera.dart';
import '../models/camera_status.dart';
import '../models/detection.dart';
import 'mqtt_service.dart';

/// Single source of truth for the app. Screens read from this via
/// AppStateScope.of(context) and never touch dummy_data.dart or
/// MqttService directly.
class AppState extends ChangeNotifier {
  AppState({required this.mqttService}) {
    // Copy ke list mutable -- buildDummy*() mengembalikan const (immutable)
    // list, sedangkan _handleMqttPayload perlu meng-update elemen.
    _cameras = List<Camera>.of(buildDummyCameras());
    _detections = List<Detection>.of(buildDummyDetections());
    _connect();
    mqttService.messages.listen((payload) => _handleMqttPayload(payload));
    unawaited(syncStatusesFromBackend());
  }

  final MqttService mqttService;

  /// Terisi jika RealMqttService.connect() gagal (host salah, broker mati,
  /// tidak ada jaringan, dll). Null saat memakai DummyMqttService atau
  /// setelah berhasil connect. Screens bisa membaca ini untuk menampilkan
  /// banner; app tetap berjalan dengan data dummy/cache apapun
  /// kondisinya.
  Object? mqttError;

  Future<void> _connect() async {
    try {
      await mqttService.connect();
      mqttError = null;
    } catch (e) {
      mqttError = e;
      print('[AppState] ❌ MQTT connect gagal: $e');
    }
    notifyListeners();
  }

  /// Request navigasi dari notification tap -> didengarkan HomeShell
  /// supaya camera detail terbuka DI DALAM shell (tema konsisten).
  final ValueNotifier<String?> openCameraRequest = ValueNotifier<String?>(null);

  /// IP address Raspberry Pi yang di-detect otomatis dari MQTT.
  /// Pi mempublish IP-nya ke topik saferise/camera/{id}/ip saat boot.
  /// Flutter subscribe dan update IP ini, lalu WebView auto-connect.
  final ValueNotifier<String?> piIpAddress = ValueNotifier<String?>(null);

  late List<Camera> _cameras;
  late List<Detection> _detections;

  /// Timestamp terakhir yang DITERAPKAN per kamera. Dipakai untuk menolak
  /// update basi: push FCM bisa telat (antrean FCM) sehingga STATUS_NORMAL
  /// lama datang setelah DANGER baru -- tanpa guard ini status UI bisa
  /// "berubah normal sendiri lalu danger lagi" tergantung urutan kedatangan.
  final Map<String, DateTime> _lastEventAt = {};

  /// True selama syncStatusesFromBackend() menerapkan status. AlertService
  /// memakai ini untuk TIDAK menampilkan notifikasi hasil sinkronisasi
  /// (notifikasi hanya untuk event live), tapi alarm tetap disinkronkan.
  bool _syncingFromBackend = false;
  bool get syncingFromBackend => _syncingFromBackend;

  DateTime? _parseTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  }

  List<Camera> get cameras => List.unmodifiable(_cameras);
  List<Detection> get detections => List.unmodifiable(_detections);

  Camera? get dangerCamera {
    for (final c in _cameras) {
      if (c.status == CameraStatus.danger) return c;
    }
    return null;
  }

  List<Detection> detectionsForCamera(String cameraId) =>
      _detections.where((d) => d.cameraId == cameraId).toList();

  /// Handles any payload arriving on saferise/camera/{id}/#, plus event
  /// eksternal (FCM / sinkronisasi backend) lewat [applyExternalAlert].
  ///
  /// Guard update basi HANYA berlaku untuk event eksternal ([isExternal]
  /// == true). Pesan live dari broker MQTT selalu diterapkan apa pun
  /// timestamp-nya -- jam Raspberry Pi/broker tidak selalu sinkron dengan
  /// jam HP, dan guard tadinya justru membuang pesan valid. Timestamp tetap
  /// dicatat ke _lastEventAt supaya FCM/backend yang telat tetap tersaring.
  void _handleMqttPayload(
    Map<String, dynamic> payload, {
    bool isExternal = false,
  }) {
    final cameraId = payload['camera_id'] as String?;

    // Handle IP broadcast dari Pi (topik saferise/camera/{id}/ip)
    if (payload.containsKey('ip') && payload['ip'] != null) {
      final newIp = payload['ip'].toString();
      if (newIp.isNotEmpty && piIpAddress.value != newIp) {
        piIpAddress.value = newIp;
        print('[AppState] Pi IP updated: $newIp');
      }
    }

    if (cameraId == null) {
      print('[AppState] payload tanpa camera_id, diabaikan: $payload');
      return;
    }

    final index = _cameras.indexWhere((c) => c.id == cameraId);
    if (index == -1) {
      print('[AppState] tidak ada kamera dengan id "$cameraId", diabaikan. '
          'Known ids: ${_cameras.map((c) => c.id).toList()}');
      return;
    }

    final incomingAt = _parseTimestamp(payload['timestamp']?.toString());
    final existingAt = _lastEventAt[cameraId];
    if (isExternal &&
        incomingAt != null &&
        existingAt != null &&
        incomingAt.isBefore(existingAt)) {
      print('[AppState] ⏳ Event eksternal basi diabaikan untuk $cameraId '
          '($incomingAt < $existingAt)');
      return;
    }
    if (incomingAt != null) {
      _lastEventAt[cameraId] =
          existingAt != null && existingAt.isAfter(incomingAt)
              ? existingAt
              : incomingAt;
    }

    final updated = Camera.applyMqttPayload(_cameras[index], payload);
    _cameras[index] = updated;

    final status = updated.status;
    if (status != CameraStatus.offline) {
      final confidencePct = (payload['confidence'] as num? ?? 0) <= 1
          ? ((payload['confidence'] as num? ?? 0) * 100).round()
          : (payload['confidence'] as num? ?? 0).round();

      _detections.insert(
        0,
        Detection(
          id: 'd${DateTime.now().millisecondsSinceEpoch}',
          cameraId: cameraId,
          cameraName: updated.name.split(' - ').first,
          status: status,
          confidence: confidencePct,
          time: DateFormat('HH:mm:ss').format(DateTime.now()),
        ),
      );
      if (_detections.length > 20) _detections.removeLast();
    }

    notifyListeners();
  }

  /// Convenience used by the "Simulasi Event" controls in the UI --
  /// forwards straight into the same MQTT message pipeline so the
  /// simulate path and the real-broker path share all logic above.
  void simulateEvent(String cameraId, CameraStatus status, {String? posture}) {
    final service = mqttService;
    if (service is DummyMqttService) {
      service.simulate(cameraId, status.wireValue, posture: posture);
    }
  }

  /// Update status kamera dari event eksternal (push FCM), bukan MQTT.
  ///
  /// Dipakai main.dart saat pesan DANGER_ALERT / STATUS_NORMAL masuk di
  /// foreground: status kamera di-update lewat pipeline yang sama dengan
  /// MQTT sehingga AlertService otomatis menyalakan/mematikan alarm loop
  /// sampai status kembali NORMAL.
  ///
  /// [timestamp] = timestamp asli dari data FCM (dikirim backend) supaya
  /// guard update basi bisa membandingkan dengan event MQTT sebelumnya.
  /// Jika null, dipakai waktu HP saat ini (mis. hasil sinkronisasi backend,
  /// yang memang harus selalu menang sebagai kondisi terkini).
  ///
  /// Return false jika [cameraId] tidak dikenal (pemanggil bisa fallback).
  bool applyExternalAlert({
    required String cameraId,
    required bool danger,
    num? confidence,
    String? timestamp,
  }) {
    if (_cameras.indexWhere((c) => c.id == cameraId) == -1) return false;

    final now = DateTime.now();
    _handleMqttPayload(
      {
        'camera_id': cameraId,
        'status': danger ? 'DANGER' : 'NORMAL',
        if (confidence != null) 'confidence': confidence,
        'timestamp': timestamp ??
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      },
      isExternal: true,
    );
    return true;
  }

  /// Minta HomeShell membuka halaman detail kamera (dari notification tap).
  void requestOpenCamera(String cameraId) {
    openCameraRequest.value = cameraId;
  }

  /// Sinkronisasi status kamera dari backend saat startup.
  ///
  /// Backend menyimpan payload MQTT terakhir per kamera dan mengeksposnya
  /// via GET /api/status. Tanpa ini, app yang dibuka langsung dari ikon
  /// selalu tampil NORMAL karena tidak menerima pesan transisi apa pun --
  /// padahal simulasi HiveMQ bisa saja sedang DANGER. Jika ada kamera yang
  /// ternyata DANGER, AlertService otomatis menyalakan alarm (transisi
  /// NORMAL -> DANGER tertangkap seperti pesan MQTT biasa).
  Future<void> syncStatusesFromBackend() async {
    final definedUrl = const String.fromEnvironment('BACKEND_URL');
    final candidates = <String>{
      if (definedUrl.isNotEmpty) definedUrl,
      'http://localhost:3000',
      'http://10.0.2.2:3000', // alias host loopback dari Android emulator
    };

    for (final base in candidates) {
      try {
        final response = await http
            .get(Uri.parse('$base/api/status'))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) {
          print('[AppState] ⚠️ $base responded ${response.statusCode}');
          continue;
        }

        final body = jsonDecode(response.body);
        if (body is! Map<String, dynamic> || body['cameras'] is! List) {
          continue;
        }

        var applied = 0;
        // Tandai sedang sync: AlertService tidak menampilkan notifikasi
        // untuk transisi yang berasal dari sinkronisasi ini -- notifikasi
        // hanya untuk event live. Alarm tetap disinkronkan.
        _syncingFromBackend = true;
        try {
          for (final entry in body['cameras'] as List) {
            if (entry is! Map) continue;
            final confidenceRaw = entry['confidence'];
            final appliedOk = applyExternalAlert(
              cameraId: '${entry['cameraId'] ?? ''}',
              danger:
                  '${entry['status'] ?? ''}'.toUpperCase() == 'DANGER',
              confidence:
                  confidenceRaw is num ? confidenceRaw : num.tryParse('${confidenceRaw ?? ''}'),
            );
            if (appliedOk) applied++;
          }
        } finally {
          _syncingFromBackend = false;
        }

        print('[AppState] ✅ Sinkron $applied status kamera dari backend ($base)');
        return;
      } catch (_) {
        // Coba kandidat URL berikutnya.
      }
    }
    print('[AppState] ⚠️ Gagal sinkron status dari backend (tidak ada yang merespons)');
  }

  @override
  void dispose() {
    openCameraRequest.dispose();
    super.dispose();
  }
}
