import 'package:flutter/material.dart';
import '../models/camera.dart';
import '../models/camera_status.dart';
import '../services/app_state_scope.dart';
import '../theme/app_colors.dart';
import '../widgets/camera_snapshot.dart';

class CctvScreen extends StatefulWidget {
  const CctvScreen({super.key, required this.onOpenCamera});

  final ValueChanged<String> onOpenCamera;

  @override
  State<CctvScreen> createState() => _CctvScreenState();
}

class _CctvScreenState extends State<CctvScreen> {
  String _query = '';
  String _filter = 'Semua';
  static const _filters = ['Semua', 'Aktif', 'Gedung A', 'Gedung B'];

  List<Camera> _apply(List<Camera> cameras) {
    return cameras.where((c) {
      final matchesQuery = c.name.toLowerCase().contains(_query.toLowerCase());
      final matchesFilter = switch (_filter) {
        'Semua' => true,
        'Aktif' => c.status != CameraStatus.offline,
        _ => c.building == _filter,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final filtered = _apply(appState.cameras);

    return ValueListenableBuilder<String?>(
      valueListenable: appState.piIpAddress,
      builder: (context, piIp, _) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('Daftar CCTV',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Pantau area Anda dengan ketenangan pikiran.',
            style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Cari kamera...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _filters.map((f) {
            final isActive = _filter == f;
            return GestureDetector(
              onTap: () => setState(() => _filter = f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.greenTint : Colors.white,
                  border: Border.all(color: isActive ? const Color(0xFFB9E4C6) : AppColors.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(f,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isActive ? AppColors.greenText : AppColors.textSecondary)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Tidak ada kamera yang cocok.', style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
            ),
          )
        else
          for (final c in filtered) ...[
            _CameraCard(
              camera: c,
              onOpen: () => widget.onOpenCamera(c.id),
              piIp: piIp,
            ),
            const SizedBox(height: 14),
          ],
      ],
    ),
    );
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard({required this.camera, required this.onOpen, this.piIp});

  final Camera camera;
  final VoidCallback onOpen;
  final String? piIp;

  @override
  Widget build(BuildContext context) {
    final isOffline = camera.status == CameraStatus.offline;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              CameraSnapshot(
                status: camera.status,
                label: camera.name.split(' - ').first,
                height: 150,
                cameraId: camera.id,
                cameraName: camera.name,
                piIp: piIp,
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isOffline ? AppColors.amber : AppColors.green).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isOffline ? Icons.wifi_off : Icons.wifi, size: 11, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(isOffline ? 'Offline' : 'Online',
                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(camera.name,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 5),
                    Text('${camera.building}, ${camera.floor}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onOpen,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Lihat', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Pengaturan', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
