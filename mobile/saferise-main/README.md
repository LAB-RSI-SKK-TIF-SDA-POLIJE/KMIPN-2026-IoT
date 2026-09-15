# SafeRise (Flutter MVP)

Aplikasi mobile monitoring keamanan rooftop/gedung berbasis AI, sesuai
mockup Dashboard dan Daftar CCTV. AI berjalan di Raspberry Pi (bukan di
HP) dan mengirim status via MQTT; aplikasi ini hanya menampilkan status
tersebut secara real-time.

## STATUS DEPLOYMENT

| Komponen | Status |
|---|---|
| **Backend service** | DEPLOYED ke **Railway** (`https://saferise-main-production.up.railway.app`) |
| **Mobile app** | Belum dirilis -- mode development via `flutter run` |

> HANYA backend yang sudah di-deploy. App Android tidak ada APK release;
> notifikasi background/killed tetap berfungsi saat pengujian karena push
> dikirim oleh backend Railway lewat FCM. 

## Menjalankan (development)

Butuh Flutter SDK terpasang (`flutter --version` untuk cek).

```bash
flutter pub get
flutter run \
  --dart-define=MQTT_HOST=<broker-hivemq> \
  --dart-define=MQTT_PORT=8883 \
  --dart-define=MQTT_USERNAME=<user> \
  --dart-define=MQTT_PASSWORD=<pass> \
  --dart-define=BACKEND_URL=https://saferise-main-production.up.railway.app
```

Tanpa `MQTT_HOST`, app jalan dengan `DummyMqttService` (mode simulasi UI).
Tanpa `BACKEND_URL`, registrasi token FCM hanya mencoba backend lokal.

Untuk build APK release (opsional, saat app mau dirilis):
lihat `scripts/build-release.ps1` di root repo.

## Struktur folder

```
lib/
  main.dart                     # entry point, inject AppState + MqttService
  models/
    camera.dart                 # model Camera + parser payload MQTT
    camera_status.dart          # enum NORMAL/DANGER/OFFLINE + warna/label
    detection.dart              # model riwayat deteksi
  data/
    dummy_data.dart             # dummy cameras & detections untuk MVP
  services/
    mqtt_service.dart           # MqttService: DummyMqttService + RealMqttService
    app_state.dart              # single source of truth (ChangeNotifier)
    app_state_scope.dart        # InheritedNotifier untuk akses state
    firebase_service.dart       # FCM init, token management, navigasi notif
    notification_service.dart   # Local notifications + alarm loop bridge
    alert_service.dart          # Transisi status -> notifikasi + alarm
  theme/
    app_colors.dart             # design tokens warna
  widgets/
    app_header.dart, main_bottom_nav.dart, status_pill.dart,
    camera_snapshot.dart, sector_row.dart, critical_alert_card.dart
  screens/
    home_shell.dart             # bottom-nav shell
    dashboard_screen.dart       # Halaman Beranda
    cctv_screen.dart            # Halaman Daftar CCTV (search + filter)
    camera_detail_screen.dart   # Detail kamera + riwayat + simulasi
    account_screen.dart         # Halaman Akun + simulasi event
```

## Menyambungkan ke MQTT broker sungguhan

Sudah otomatis -- cukup jalankan dengan `--dart-define=MQTT_HOST=...`
(lihat bagian Menjalankan). `main.dart` memakai `RealMqttService` saat
`MQTT_HOST` tersedia dan langsung subscribe ke `saferise/camera/+/#`.
Semua layar membaca dari `AppState`, yang menangani payload MQTT lewat
`_handleMqttPayload` di `app_state.dart`.

## Topic & payload MQTT

```
saferise/camera/{camera_id}/status
saferise/camera/{camera_id}/detection
saferise/camera/{camera_id}/audio
saferise/camera/{camera_id}/connection
```

Contoh payload (`saferise/camera/CAM05/detection`):

```json
{
  "camera_id": "CAM05",
  "status": "DANGER",
  "confidence": 0.91,
  "location": "Gedung A, Lantai 15, Atap Timur",
  "timestamp": "2026-08-15T14:32:10",
  "audio": "PLAYING"
}
```

## Simulasi tanpa Raspberry Pi

Selama perangkat AI belum terpasang, gunakan tombol simulasi:
- Halaman **Akun** -> panel "Simulasi Event" (mengubah CAM05).
- Halaman **Detail Kamera** -> panel "Simulasi Event" (mengubah kamera yang dibuka).

Keduanya memanggil `AppState.simulateEvent(cameraId, status)`, yang
mendorong payload lewat `DummyMqttService` -- jalur logikanya identik
dengan pesan MQTT asli, jadi perilaku UI akan sama persis begitu broker
sungguhan terpasang.

## Alur alert end-to-end

```
HiveMQ (publish DANGER)
  ├─> App foreground : MQTT langsung -> AppState -> notif + alarm loop (instan)
  └─> Backend Railway: MQTT -> FCM push -> app background/killed
         - Native AlarmService (foreground service): suara+getar loop
         - STATUS_NORMAL -> alarm berhenti, buzz sekali
Buka app kapan pun -> GET /api/status -> UI & alarm sinkron dengan broker
```
