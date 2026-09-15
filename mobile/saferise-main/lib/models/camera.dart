import 'camera_status.dart';
import 'posture.dart';

/// Represents a single CCTV camera / sector.
/// This is the app-side shape; `Camera.fromMqttPayload` shows how a
/// real MQTT JSON payload from the Raspberry Pi maps onto it.
class Camera {
  final String id; // e.g. "CAM05"
  final String name; // e.g. "Camera 5 - Atap Timur"
  final String sector; // e.g. "Atap Timur"
  final String building; // e.g. "Gedung A"
  final String floor; // e.g. "Lantai 15"
  final CameraStatus status;
  final int confidence; // 0-100
  final String lastSeen; // HH:mm:ss
  final String audio; // "IDLE" | "PLAYING"
  final Posture posture; // pose terakhir yang dideteksi AI
  final String updatedAt; // yyyy-MM-dd HH:mm:ss

  const Camera({
    required this.id,
    required this.name,
    required this.sector,
    required this.building,
    required this.floor,
    required this.status,
    required this.confidence,
    required this.lastSeen,
    required this.audio,
    this.posture = Posture.normal,
    required this.updatedAt,
  });

  Camera copyWith({
    CameraStatus? status,
    int? confidence,
    String? lastSeen,
    String? audio,
    Posture? posture,
    String? updatedAt,
  }) {
    return Camera(
      id: id,
      name: name,
      sector: sector,
      building: building,
      floor: floor,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      lastSeen: lastSeen ?? this.lastSeen,
      audio: audio ?? this.audio,
      posture: posture ?? this.posture,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Example of parsing a real MQTT payload, e.g.:
  /// {
  ///   "camera_id": "CAM05",
  ///   "status": "DANGER",
  ///   "confidence": 0.91,
  ///   "location": "Gedung A, Lantai 15, Atap Timur",
  ///   "timestamp": "2026-08-15T14:32:10",
  ///   "posture": "climbing",
  ///   "audio": "PLAYING"
  /// }
  static Camera applyMqttPayload(Camera current, Map<String, dynamic> json) {
    final confidenceRaw = json['confidence'];
    final confidencePct = confidenceRaw is num
        ? (confidenceRaw <= 1 ? (confidenceRaw * 100).round() : confidenceRaw.round())
        : current.confidence;

    final status =
        CameraStatusX.fromString(json['status'] as String? ?? current.status.wireValue);

    // Posture hanya relevan saat DANGER. Payload NORMAL/OFFLINE boleh saja
    // tidak membawa field ini -> kembali ke normal.
    final postureRaw = json['posture'];
    final nextPosture = postureRaw != null
        ? PostureX.fromString(postureRaw)
        : (status == CameraStatus.danger ? current.posture : Posture.normal);

    return current.copyWith(
      status: status,
      confidence: confidencePct,
      audio: json['audio'] as String? ?? current.audio,
      posture: nextPosture,
      updatedAt: (json['timestamp'] as String?)?.replaceFirst('T', ' ') ?? current.updatedAt,
      lastSeen: ((json['timestamp'] as String?) ?? '').contains('T')
          ? (json['timestamp'] as String).split('T').last
          : current.lastSeen,
    );
  }
}
