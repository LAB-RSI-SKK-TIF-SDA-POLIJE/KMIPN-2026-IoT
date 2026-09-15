import 'package:flutter/material.dart';
import '../models/camera.dart';
import '../models/camera_status.dart';
import '../theme/app_colors.dart';
import 'status_pill.dart';

class SectorRow extends StatelessWidget {
  const SectorRow({super.key, required this.camera, required this.onTap});

  final Camera camera;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDanger = camera.status == CameraStatus.danger;
    final iconColor = isDanger
        ? AppColors.red
        : camera.status == CameraStatus.offline
            ? AppColors.amber
            : AppColors.green;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDanger ? AppColors.redTint : AppColors.card,
          border: Border.all(color: isDanger ? AppColors.redBorder : AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: camera.status.tint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.videocam, color: iconColor, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    camera.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  Text(
                    '${camera.building}, ${camera.floor}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            StatusPill(status: camera.status),
          ],
        ),
      ),
    );
  }
}
