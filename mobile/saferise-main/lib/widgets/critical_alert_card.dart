import 'package:flutter/material.dart';
import '../models/camera.dart';
import '../models/posture.dart';
import '../theme/app_colors.dart';
import 'camera_snapshot.dart';

class CriticalAlertCard extends StatelessWidget {
  const CriticalAlertCard({super.key, required this.camera, required this.onOpenCamera, this.piIp});

  /// Null means no camera is currently in DANGER -> render the safe state.
  final Camera? camera;
  final ValueChanged<String> onOpenCamera;
  final String? piIp;

  @override
  Widget build(BuildContext context) {
    final cam = camera;
    if (cam == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.greenTint,
          border: Border.all(color: const Color(0xFFB9E4C6)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.greenText, size: 20),
                SizedBox(width: 8),
                Text('SISTEM AMAN',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.greenText)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Semua kamera terpantau normal saat ini.',
              style: TextStyle(fontSize: 13, color: AppColors.greenText.withOpacity(0.85)),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.redTint,
        border: Border.all(color: AppColors.redBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PERINGATAN',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.redText, height: 1.15)),
                      Text('KRITIS',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.redText, height: 1.15)),
                      Text('POTENSIAL',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.redText, height: 1.15)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 6,
                        height: 6,
                        child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                      ),
                      SizedBox(width: 5),
                      Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => onOpenCamera(cam.id),
                  child: CameraSnapshot(
                    status: cam.status,
                    label: cam.name.split(' - ').first,
                    cameraId: cam.id,
                    cameraName: cam.name,
                    piIp: piIp,
                  ),
                ),
                const SizedBox(height: 14),
                _label('LOKASI'),
                _row(Icons.location_on, '${cam.building}, ${cam.floor}, ${cam.sector}'),
                const SizedBox(height: 12),
                if (cam.posture != Posture.normal) ...[
                  _PostureBadge(posture: cam.posture),
                  const SizedBox(height: 12),
                ],
                _label('WAKTU'),
                _row(Icons.access_time, cam.updatedAt),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.redBorder),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('STATUS SISTEM'),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Audio Intervensi',
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Row(
                            children: [
                              const Icon(Icons.volume_up, size: 14, color: AppColors.blue),
                              const SizedBox(width: 4),
                              Text(cam.audio == 'PLAYING' ? 'Memutar' : 'Siaga',
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.blue)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: const LinearProgressIndicator(
                          value: 0.2,
                          minHeight: 5,
                          backgroundColor: Color(0xFFEFEFEF),
                          valueColor: AlwaysStoppedAnimation(AppColors.blue),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0:15', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          Text('1:30', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Confidence AI', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    Text('${cam.confidence}%',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.redText)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5),
      );

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.blue),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
          ],
        ),
      );
}

/// Badge "POSTUR TERDETEKSI" di Critical Alert Card.
/// Warna mengikuti tingkat keparahan: merah (climbing) /
/// amber-oranye (crouching).
class _PostureBadge extends StatelessWidget {
  const _PostureBadge({required this.posture});

  final Posture posture;

  @override
  Widget build(BuildContext context) {
    final color = posture.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color.withOpacity(0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.accessibility_new, size: 16, color: color),
          const SizedBox(width: 8),
          Text('POSTUR TERDETEKSI',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: color.withOpacity(0.75))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
            child: Text(posture.label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
