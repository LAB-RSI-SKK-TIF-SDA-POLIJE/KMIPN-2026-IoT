import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../services/app_state_scope.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';
import '../widgets/main_bottom_nav.dart';
import 'account_screen.dart';
import 'camera_detail_screen.dart';
import 'cctv_screen.dart';
import 'dashboard_screen.dart';

/// Top-level shell: owns which of the 3 bottom-nav tabs is active plus
/// whether a camera detail view is currently pushed on top of it.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  MainTab _tab = MainTab.beranda;
  String? _selectedCameraId;
  AppState? _appState;

  void _openCamera(String id) => setState(() => _selectedCameraId = id);
  void _closeCamera() => setState(() => _selectedCameraId = null);

  void _changeTab(MainTab tab) {
    setState(() {
      _selectedCameraId = null;
      _tab = tab;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = AppStateScope.of(context);
    if (_appState != appState) {
      _appState?.openCameraRequest.removeListener(_onOpenCameraRequest);
      _appState = appState;
      _appState!.openCameraRequest.addListener(_onOpenCameraRequest);
    }
  }

  /// Dipanggil saat notification tap meminta buka detail kamera.
  void _onOpenCameraRequest() {
    final id = _appState?.openCameraRequest.value;
    if (id != null && id.isNotEmpty) {
      _appState!.openCameraRequest.value = null; // konsumsi request
      _tab = MainTab.cctv;
      _openCamera(id);
    }
  }

  @override
  void dispose() {
    _appState?.openCameraRequest.removeListener(_onOpenCameraRequest);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cameraId = _selectedCameraId;

    Widget body;
    if (cameraId != null) {
      body = CameraDetailScreen(cameraId: cameraId, onBack: _closeCamera);
    } else {
      body = switch (_tab) {
        MainTab.beranda => DashboardScreen(onOpenCamera: _openCamera),
        MainTab.cctv => CctvScreen(onOpenCamera: _openCamera),
        MainTab.akun => const AccountScreen(),
      };
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppHeader(onProfileTap: () => _changeTab(MainTab.akun)),
      body: SafeArea(top: false, child: body),
      bottomNavigationBar: MainBottomNav(
        active: cameraId != null ? MainTab.cctv : _tab,
        onChanged: _changeTab,
      ),
    );
  }
}
