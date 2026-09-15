import 'package:flutter_test/flutter_test.dart';
import 'package:saferise/models/camera.dart';
import 'package:saferise/models/camera_status.dart';
import 'package:saferise/models/posture.dart';

/// Verifikasi parsing payload /detection versi terbaru (dengan field
/// "posture") sesuai spesifikasi topik saferise/camera/CAM05/detection.
void main() {
  final base = {
    'camera_id': 'CAM05',
    'location': 'Rooftop Gedung A',
  };

  Camera parse(Map<String, dynamic> payload) => Camera.applyMqttPayload(
        _seed(),
        {...base, ...payload},
      );

  test('NORMAL -> hijau, confidence 0.95 jadi 95%, posture normal', () {
    final cam = parse({
      'status': 'NORMAL',
      'confidence': 0.95,
      'timestamp': '2026-08-23T10:00:00',
      'posture': 'normal',
    });

    expect(cam.status, CameraStatus.normal);
    expect(cam.confidence, 95);
    expect(cam.posture, Posture.normal);
    expect(cam.updatedAt, '2026-08-23 10:00:00');
    expect(cam.lastSeen, '10:00:00');
  });

  test('DANGER + climbing -> merah "Indikasi Memanjat", 0.93 jadi 93%', () {
    final cam = parse({
      'status': 'DANGER',
      'confidence': 0.93,
      'timestamp': '2026-08-23T10:01:00',
      'posture': 'climbing',
    });

    expect(cam.status, CameraStatus.danger);
    expect(cam.confidence, 93);
    expect(cam.posture, Posture.climbing);
    // Warna badge climbing = merah.
    expect(cam.posture.color, isNot(Posture.crouching.color));
  });

  test('DANGER + crouching -> amber "Menunduk / Jongkok", 0.87 jadi 87%', () {
    final cam = parse({
      'status': 'DANGER',
      'confidence': 0.87,
      'timestamp': '2026-08-23T10:02:00',
      'posture': 'crouching',
    });

    expect(cam.status, CameraStatus.danger);
    expect(cam.confidence, 87);
    expect(cam.posture, Posture.crouching);
    // Crouching harus amber/oranye, berbeda dari climbing yang merah.
    expect(cam.posture.color, Posture.crouching.color);
  });

  test('OFFLINE tanpa posture -> posture reset normal, confidence 0', () {
    final cam = parse({
      'status': 'OFFLINE',
      'confidence': 0,
      'timestamp': '2026-08-23T10:03:00',
    });

    expect(cam.status, CameraStatus.offline);
    expect(cam.confidence, 0);
    expect(cam.posture, Posture.normal);
  });
}

Camera _seed() => const Camera(
      id: 'CAM05',
      name: 'Camera 5 - Rooftop Gedung A',
      sector: 'Rooftop',
      building: 'Gedung A',
      floor: 'Atap',
      status: CameraStatus.normal,
      confidence: 0,
      lastSeen: '',
      audio: 'IDLE',
      updatedAt: '',
    );
