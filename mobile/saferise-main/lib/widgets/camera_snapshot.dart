import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/app_state.dart';
import '../services/app_state_scope.dart';
import 'live_camera_widget.dart';
import '../models/camera_status.dart';

/// Widget untuk menampilkan snapshot kamera.
/// Jika IP Pi tersedia dari MQTT, tampilkan live camera via WebView.
/// Jika tidak, tampilkan placeholder gelap.
class CameraSnapshot extends StatelessWidget {
  const CameraSnapshot({
    super.key,
    required this.status,
    required this.label,
    this.height = 180,
    this.cameraId,
    this.cameraName,
    this.piIp,
    this.streamPort = 8080,
  });

  final CameraStatus status;
  final String label;
  final double height;
  final String? cameraId;
  final String? cameraName;
  final String? piIp;
  final int streamPort;

  @override
  Widget build(BuildContext context) {
    final isDanger = status == CameraStatus.danger;

    // Jika cameraId tersedia, listen ke piIpAddress ValueNotifier
    // supaya auto-update saat IP berubah
    if (cameraId != null) {
      AppState? appState;
      try {
        appState = AppStateScope.of(context);
      } catch (_) {}

      if (appState != null) {
        return ValueListenableBuilder<String?>(
          valueListenable: appState.piIpAddress,
          builder: (context, currentIp, _) {
            if (currentIp != null && currentIp.isNotEmpty) {
              return Stack(
                children: [
                  LiveCameraWidget(
                    cameraId: cameraId!,
                    cameraName: cameraName ?? label,
                    streamPort: streamPort,
                    height: height,
                    piIp: currentIp,
                  ),
                  _statusBadge(isDanger),
                ],
              );
            }
            return _placeholder();
          },
        );
      }
    }

    // Fallback: IP dari parameter langsung
    if (piIp != null && piIp!.isNotEmpty && cameraId != null) {
      return Stack(
        children: [
          LiveCameraWidget(
            cameraId: cameraId!,
            cameraName: cameraName ?? label,
            streamPort: streamPort,
            height: height,
            piIp: piIp!,
          ),
          _statusBadge(isDanger),
        ],
      );
    }

    return _placeholder();
  }

  Widget _statusBadge(bool isDanger) {
    return Positioned(
      bottom: 10,
      right: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: isDanger ? status.color : Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          status.label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1F2937), Color(0xFF111827)],
                ),
              ),
              child: const Center(
                child: Icon(Icons.videocam, color: Color(0xFF9CA3AF), size: 40),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 12),
                    const SizedBox(width: 6),
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: status == CameraStatus.danger ? status.color : Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  status.label,
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}