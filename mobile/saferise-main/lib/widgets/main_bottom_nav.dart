import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum MainTab { beranda, cctv, akun }

class MainBottomNav extends StatelessWidget {
  const MainBottomNav({super.key, required this.active, required this.onChanged});

  final MainTab active;
  final ValueChanged<MainTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _item(MainTab.beranda, Icons.home_rounded, 'Beranda'),
            _item(MainTab.cctv, Icons.videocam_rounded, 'CCTV'),
            _item(MainTab.akun, Icons.person_rounded, 'Akun'),
          ],
        ),
      ),
    );
  }

  Widget _item(MainTab tab, IconData icon, String label) {
    final isActive = active == tab;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(tab),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? AppColors.greenTint : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 19, color: isActive ? AppColors.greenText : AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? AppColors.greenText : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
