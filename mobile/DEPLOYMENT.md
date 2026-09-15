# 🚀 SafeRise — Panduan Deployment (Free Tier)

Panduan Task 6.1 (Production Configuration) untuk membawa **backend** ke
lingkungan production **tanpa biaya** dan **tanpa harus menyala di laptop**.
App Android untuk saat ini TIDAK dirilis — cukup tetap `flutter run` mode
development yang mengarah ke backend cloud.

---

## 0. Skenario "Backend-only" (app belum dirilis)

Backend jalan 24/7 di cloud; app di HP tetap versi development:

```powershell
flutter run --dart-define=MQTT_HOST=<broker> --dart-define=MQTT_PORT=8883 `
  --dart-define=MQTT_USERNAME=<user> --dart-define=MQTT_PASSWORD=<pass> `
  --dart-define=BACKEND_URL=https://<nama-service>.onrender.com
```

Dengan begitu notifikasi background/killed tetap masuk walau laptop mati,
dan sinkronisasi status (`GET /api/status`) memakai backend cloud.
Build APK release (`scripts/build-release.ps1`) baru diperlukan saat
app mau dirilis.

---

## 1. Arsitektur Deployment

```
Raspberry Pi / MQTTX ──publish──> HiveMQ Cloud (TLS 8883, FREE)
                                        │
                                        ▼ subscribe
                        Backend Node.js (Render FREE)
                                        │ FCM push (priority high)
                                        ▼
                          HP Android (SafeRise app, release APK)
```

- **Broker**: HiveMQ Cloud free tier (TLS port 8883, ~100 koneksi) — sudah dipakai.
- **Backend**: Render.com **Web Service free** (750 jam/bulan). Koneksi MQTT keluar (TCP/TLS) diizinkan.
- **App**: APK release dibangun via `scripts/build-release.ps1`.

---

## 2. Deploy Backend ke Render (FREE)

1. Push repo `backend/` ke GitHub (pastikan `.env` & service account TIDAK ikut — sudah digitignore).
2. Render Dashboard → **New → Web Service** → pilih repo.
3. Konfigurasi:
   - **Root Directory**: `backend`
   - **Build Command**: `npm install`
   - **Start Command**: `npm run start:prod`
   - **Instance Type**: Free
4. **Environment Variables** (copy dari `.env.production`, isi nilai asli):
   | Key | Nilai |
   |---|---|
   | `NODE_ENV` | `production` |
   | `PORT` | `3000` (Render otomatis override — biarkan) |
   | `FIREBASE_PROJECT_ID` | project ID kamu |
   | `FIREBASE_SERVICE_ACCOUNT_PATH` | `./config/firebase-service-account.json` |
   | `MQTT_BROKER_HOST` | `xxx.s1.eu.hivemq.cloud` |
   | `MQTT_BROKER_PORT` | `8883` |
   | `MQTT_USERNAME` / `MQTT_PASSWORD` | kredensial broker |
   | `STATUS_LOG_INTERVAL_SEC` | `60` |

5. ⚠️ **Service account JSON tidak di-commit** → gunakan env var:
   - Encode file ke base64 (PowerShell):
     ```powershell
     [Convert]::ToBase64String([IO.File]::ReadAllBytes("path\firebase-service-account.json")) | Set-Clipboard
     ```
   - Render → Environment → tambah `FIREBASE_SERVICE_ACCOUNT_B64` = hasil tersebut.
   - Backend otomatis memprioritaskan var ini di atas path file
     (lihat `fcm-service.js` → `initializeFirebase()`).
6. **Keep-alive** (penting!): Render free mematikan service setelah ±15 menit tanpa trafik.
   Buat monitor gratis di [cron-job.org](https://cron-job.org) yang GET
   `https://<service>.onrender.com/health` tiap 10 menit.
7. Verifikasi: buka `/health` — harus `status: ok`, `mqtt.connected: true`.

> **Catatan filesystem Render free**: disk bersifat sementara (ephemeral).
> `device-tokens.json` bisa hilang saat redeploy — tidak fatal, karena app
> mendaftarkan ulang token FCM setiap kali dibuka. Kalau notif ke HP tiba-taba
> berhenti setelah redeploy, cukup buka app sekali untuk re-register.

> Alternatif free lain: Koyeb, Railway trial, Fly.io (butuh kartu). Prinsipnya sama.

---

## 3. Build App Release (OPSIONAL — tunda sampai app mau dirilis)

Selama fase development, app cukup `flutter run` seperti biasa (lihat §0).
Ketika nanti dibutuhkan:

```powershell
# sekali saja:
Copy-Item scripts\build.config.example scripts\build.config
# isi build.config: MQTT_HOST/PORT/USER/PASS + BACKEND_URL=https://<service>.onrender.com

.\scripts\build-release.ps1            # build apk release
.\scripts\build-release.ps1 -Clean     # build bersih dari nol
# Linux/macOS: ./scripts/build-release.sh [--clean] [--target appbundle]
```

Hasil: `saferise-main/build/app/outputs/flutter-apk/app-release.apk`
Install ke HP: `adb install -r app-release.apk` atau salin manual.

Versi app dikelola di `pubspec.yaml` → `version: 1.1.0+2`
(naikkan `+N` setiap update agar Android menganggapnya upgrade).

---

## 4. Checklist Firebase Production (MANUAL)

- [ ] Project Firebase dipisah dev/prod **atau** gunakan project sama dengan aturan ketat.
- [ ] Cloud Messaging API (V1) **enabled** (Firebase Console → Project Settings → Cloud Messaging).
- [ ] Service account key produksi baru dengan role minimal (**Firebase Cloud Messaging API Admin**), disimpan di server produksi saja.
- [ ] `google-services.json` di `android/app/` berasal dari project produksi yang sama dengan service account.
- [ ] Package name (`com.example.saferise_mobileapps`) terdaftar di project — ganti sebelum rilis publik jika perlu.
- [ ] Quota/usage dimonitor di Console (FCM gratis, tapi pantau anomali).

## 5. Checklist MQTT TLS (Production)

- [ ] Port **8883** (bukan 1883) di env produksi → backend & app otomatis pakai TLS.
- [ ] Kredensial broker kuat (bukan default demo).
- [ ] ACL broker (HiveMQ Cloud: Access Management) — hanya client terdaftar yang boleh publish/subscribe.

## 6. Monitoring & Logging (built-in, tanpa dependency)

| Fitur | Cara lihat |
|---|---|
| Health check (+ uptime, jumlah kamera & token) | `GET /health` |
| Log request HTTP (skip /health) | log stream Render |
| Status periodik (mqtt/cameras/tokens) | log tiap `STATUS_LOG_INTERVAL_SEC` detik |
| Error tak tertangkap | tetap di-log, server TIDAK mati (uncaughtException handler) |

---
*Terakhir diperbarui: Task 6.1 — DEPLOY-01 (2026-08-23)*
