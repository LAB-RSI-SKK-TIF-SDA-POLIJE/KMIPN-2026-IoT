import 'camera_status.dart';

/// A single entry in the detection history log.
class Detection {
  final String id;
  final String cameraId;
  final String cameraName;
  final CameraStatus status;
  final int confidence;
  final String time; // HH:mm:ss

  const Detection({
    required this.id,
    required this.cameraId,
    required this.cameraName,
    required this.status,
    required this.confidence,
    required this.time,
  });
}
