import 'package:flutter/material.dart';
import '../models/camera_status.dart';
import '../services/app_state_scope.dart';
import '../theme/app_colors.dart';
import '../widgets/critical_alert_card.dart';
import '../widgets/sector_row.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenCamera});

  final ValueChanged<String> onOpenCamera;

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final cameras = appState.cameras;
    final activeCount = cameras.where((c) => c.status != CameraStatus.offline).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('Dashboard SafeRise',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Pemantauan lingkungan dan respons insiden real-time.',
            style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        ValueListenableBuilder<String?>(
          valueListenable: appState.piIpAddress,
          builder: (context, piIp, _) => CriticalAlertCard(
            camera: appState.dangerCamera,
            onOpenCamera: onOpenCamera,
            piIp: piIp,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Status Sektor',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFF0F1F4), borderRadius: BorderRadius.circular(20)),
              child: Text('$activeCount Active',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final c in cameras) ...[
          SectorRow(camera: c, onTap: () => onOpenCamera(c.id)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
