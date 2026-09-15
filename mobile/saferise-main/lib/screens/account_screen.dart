import 'package:flutter/material.dart';
import '../models/camera_status.dart';
import '../services/alarm_sound_service.dart';
import '../services/alert_service.dart';
import '../services/app_state_scope.dart';
import '../theme/app_colors.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final AlarmSoundService _alarmSound = AlarmSoundService.instance;
  String _soundTitle = '';
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _loadSoundTitle();
  }

  Future<void> _loadSoundTitle() async {
    final sound = await _alarmSound.getAlarmSound();
    if (!mounted) return;
    setState(() => _soundTitle = sound['title'] ?? 'Suara Alarm Sistem');
  }

  Future<void> _pickSystemSound() async {
    await _stopPreview();
    final title = await _alarmSound.pickSystemSound();
    if (title != null && mounted) setState(() => _soundTitle = title);
  }

  Future<void> _pickFileSound() async {
    await _stopPreview();
    final title = await _alarmSound.pickFileSound();
    if (title != null && mounted) setState(() => _soundTitle = title);
  }

  Future<void> _resetSound() async {
    await _stopPreview();
    await _alarmSound.resetAlarmSound();
    if (mounted) setState(() => _soundTitle = 'Suara Alarm Sistem');
  }

  Future<void> _stopPreview() async {
    await _alarmSound.stopPreview();
    if (mounted) setState(() => _previewing = false);
  }

  Future<void> _togglePreview() async {
    if (_previewing) {
      await _stopPreview();
    } else {
      await _alarmSound.preview();
      if (mounted) setState(() => _previewing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final hasDanger = appState.dangerCamera != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('Akun', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Kelola profil dan pengaturan aplikasi Anda.',
            style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
        const SizedBox(height: 18),

        // Profile card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(color: AppColors.blueTint, shape: BoxShape.circle),
                child: const Icon(Icons.person, color: AppColors.blue, size: 24),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Budi Santoso', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text('Petugas Keamanan', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  Text('budi@saferise.id', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Menu list
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _menuTile('Profil Saya', isLast: false),
              _menuTile('Notifikasi', isLast: false),
              _menuTile('Keamanan', isLast: true),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Sound settings
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Suara Notifikasi',
                      style: TextStyle(fontSize: 14.5, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                  InkWell(
                    onTap: _togglePreview,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        _previewing ? Icons.stop_circle : Icons.play_circle,
                        size: 26,
                        color: _previewing ? AppColors.redText : AppColors.green,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(_soundTitle,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickSystemSound,
                      icon: const Icon(Icons.library_music, size: 15),
                      label: const Text('Suara HP',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFileSound,
                      icon: const Icon(Icons.upload_file, size: 15),
                      label: const Text('Upload',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _resetSound,
                      icon: const Icon(Icons.restart_alt, size: 15),
                      label: const Text('Reset',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Settings
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
               _menuTile('Tentang SafeRise', isLast: true),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Simulation panel
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF0F1F4), borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.podcasts, size: 13, color: AppColors.textMuted),
                  SizedBox(width: 6),
                  Text('SIMULASI EVENT (TESTING)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.4)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Ubah status CAM05 untuk menguji perilaku Dashboard tanpa Raspberry Pi/MQTT nyata.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final s in CameraStatus.values) ...[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: OutlinedButton(
                          onPressed: () => appState.simulateEvent('CAM05', s),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: (hasDanger && s == CameraStatus.danger) ? AppColors.redTint : Colors.white,
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
              const SizedBox(height: 14),

              // TEST-01: trigger notifikasi langsung (bypass MQTT pipeline)
              // untuk isolasi testing layer notifikasi + vibration + tap.
              const Text('TEST NOTIFIKASI LANGSUNG (TEST-01)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.4)),
              const SizedBox(height: 6),
              const Text('Tampilkan notifikasi DANGER segera tanpa mengubah status kamera.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    AlertService.instance.simulateDangerAlert('CAM05'),
                icon: const Icon(Icons.notifications_active, size: 16),
                label: const Text('🚨 Test Notifikasi DANGER',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.border),
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Logout
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.redTint,
              side: const BorderSide(color: AppColors.redBorder),
              foregroundColor: AppColors.redText,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Keluar Akun', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _menuTile(String label, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
          const Icon(Icons.chevron_right, size: 17, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
