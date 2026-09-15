import '../models/camera.dart';
import '../models/camera_status.dart';
import '../models/detection.dart';

/// Seed dataset: hanya kamera nyata (CAM05), sesuai panel "SIMULASI EVENT"
/// dan topik Raspberry Pi / HiveMQ yang dipakai testing
/// (saferise/camera/CAM05/#). Status awal OFFLINE -- semua transisi
/// selanjutnya datang dari pesan MQTT/FCM sungguhan, dan UI tidak salah
/// menampilkan "NORMAL" padahal belum ada data sama sekali.
List<Camera> buildDummyCameras() {
  return const [
    Camera(
      id: 'CAM05',
      name: 'Camera 5 - Atap Timur',
      sector: 'Atap Timur',
      building: 'Gedung A',
      floor: 'Lantai 15',
      status: CameraStatus.offline,
      confidence: 0,
      lastSeen: '--:--:--',
      audio: 'IDLE',
      updatedAt: 'Belum ada data',
    ),
  ];
}

/// Riwayat deteksi kosong saat startup -- terisi dari pesan MQTT nyata.
List<Detection> buildDummyDetections() {
  return const [];
}
