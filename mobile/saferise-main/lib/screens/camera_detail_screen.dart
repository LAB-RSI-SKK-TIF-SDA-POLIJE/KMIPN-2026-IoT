import 'package:flutter/material.dart';
import '../models/camera_status.dart';
import '../services/alert_service.dart';
import '../services/app_state.dart';
import '../services/app_state_scope.dart';
import '../theme/app_colors.dart';
import '../widgets/camera_snapshot.dart';
import '../widgets/status_pill.dart';

class CameraDetailScreen extends StatelessWidget {
  const CameraDetailScreen({
    super.key, 
    required this.cameraId, 
    required this.onBack,
    this.appState,
  });

  final String cameraId;
  final VoidCallback onBack;
  final AppState? appState;

  /// Resolusi AppState dengan fallback berlapis supaya tidak crash
  /// saat dibuka dari notification tap di kondisi apapun.
  static AppState _resolveState(BuildContext context, AppState? injected) {
    if (injected != null) return injected;
    try {
      return AppStateScope.of(context);
    } catch (_) {
      return AlertService.instance.appState;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _resolveState(context, appState);
    final camera = state.cameras.firstWhere(
      (c) => c.id == cameraId,
      orElse: () => state.cameras.first,
    );
    final history = state.detectionsForCamera(camera.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        TextButton.icon(
          onPressed: onBack,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: AppColors.blue,
            alignment: Alignment.centerLeft,
          ),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Kembali ke Daftar CCTV', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Text(camera.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        ValueListenableBuilder<String?>(
          valueListenable: state.piIpAddress,
          builder: (context, piIp, _) => CameraSnapshot(
            status: camera.status,
            label: camera.name.split(' - ').first,
            height: 200,
            cameraId: camera.id,
            cameraName: camera.name,
            piIp: piIp,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _row('Status', StatusPill(status: camera.status)),
              const SizedBox(height: 12),
              _row(
                'AI Detection',
                Text(camera.status == CameraStatus.danger ? 'Bahaya terdeteksi' : 'Normal',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 12),
              _row(
                'Lokasi',
                Flexible(
                  child: Text('${camera.building}, ${camera.floor}, ${camera.sector}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(height: 12),
              _row('Last Detection',
                  Text(camera.lastSeen, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
              const SizedBox(height: 12),
              _row(
                'Confidence',
                Text(
                  camera.status == CameraStatus.offline ? '-' : '${camera.confidence}%',
                  style: TextStyle(fontWeight: FontWeight.w700, color: camera.status.textColor),
                ),
              ),
              const SizedBox(height: 12),
              _row('Update terakhir',
                  Text(camera.updatedAt, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('Riwayat deteksi',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        if (history.isEmpty)
          const Text('Belum ada riwayat untuk kamera ini.', style: TextStyle(fontSize: 13, color: AppColors.textMuted))
        else
          for (final d in history) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(d.time, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  StatusPill(status: d.status),
                  Text('${d.confidence}%',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF0F1F4), borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SIMULASI EVENT (TESTING)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final s in CameraStatus.values) ...[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: OutlinedButton(
                           onPressed: () => state.simulateEvent(camera.id, s),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: s.textColor,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                          ),
                          child: Text(s.wireValue, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, Widget value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        value,
      ],
    );
  }
}
