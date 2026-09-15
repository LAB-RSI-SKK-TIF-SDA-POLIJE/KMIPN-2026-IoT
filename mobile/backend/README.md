# 🚀 SafeRise Backend Service

**Backend service untuk SafeRise Alert System** - menghubungkan MQTT messages dari Raspberry Pi AI dengan FCM push notifications ke mobile app.

## STATUS DEPLOYMENT

| Komponen | Status |
|---|---|
| **Backend service** | DEPLOYED ke **Railway** (`https://saferise-main-production.up.railway.app`) |
| **Mobile app** | Belum dirilis -- masih mode development (`flutter run` dengan `--dart-define`) |

> **Penting**: HANYA backend service yang sudah di-deploy. App Android belum
> dirilis (tidak ada APK release); untuk pengujian gunakan
> `flutter run` dengan `--dart-define=BACKEND_URL=https://saferise-main-production.up.railway.app`.


## 📋 Deskripsi

Service ini bertugas untuk:
- 🔌 Subscribe ke MQTT broker untuk menerima status camera dari Raspberry Pi
- 🔍 Mendeteksi status "DANGER" dari payload MQTT
- 📤 Mengirim FCM push notifications ke semua device yang terdaftar
- 🌐 Menyediakan HTTP API untuk registrasi device tokens
- 📊 Monitoring dan logging real-time

## 🏗️ Arsitektur

```
Raspberry Pi (AI) 
    ↓ (publish MQTT)
MQTT Broker (HiveMQ)
    ↓ (subscribe)
SafeRise Backend Service
    ↓ (send FCM)
Firebase Cloud Messaging
    ↓ (push notification)
Mobile App (Flutter)
```

## 📦 Requirements

- **Node.js**: v18.0.0 atau lebih tinggi
- **npm** atau **yarn**
- **Firebase Project** dengan Cloud Messaging enabled
- **Service Account Key** dari Firebase
- **MQTT Broker** (HiveMQ atau lainnya)

## 🛠️ Installation

### 1. Install Dependencies

```bash
cd backend
npm install
```

### 2. Setup Environment Variables

Copy `.env.example` ke `.env`:

```bash
cp .env.example .env
```

Edit file `.env` dan isi dengan konfigurasi Anda:

```env
# Firebase Configuration
FIREBASE_PROJECT_ID=saferise-alert-system
FIREBASE_SERVICE_ACCOUNT_PATH=./config/firebase-service-account.json

# MQTT Configuration
MQTT_BROKER_HOST=broker.hivemq.com
MQTT_BROKER_PORT=1883
MQTT_USERNAME=
MQTT_PASSWORD=
MQTT_TOPIC_PREFIX=saferise/camera/

# Server Configuration
PORT=3000
NODE_ENV=development
```

### 3. Add Firebase Service Account

Download `firebase-service-account.json` dari Firebase Console dan simpan di folder `backend/config/`:

**Alternatif hosting cloud (Railway/Render/Koyeb):** tidak perlu file --
set env var FIREBASE_SERVICE_ACCOUNT_B64 berisi base64 dari JSON tersebut


```
backend/
  └── config/
      └── firebase-service-account.json
```

**⚠️ PENTING**: Jangan commit file ini ke Git!

## 🚀 Running the Service

### Development Mode

```bash
npm start
```

atau dengan auto-reload (menggunakan nodemon):

```bash
npm run dev
```

### Production Mode

```bash
npm run start:prod
```

### Deployed (Railway)

Service sudah berjalan di Railway -- lihat bagian **STATUS DEPLOYMENT** di atas.
Konfigurasi produksi memakai environment variables dashboard Railway
(`NODE_ENV=production`, MQTT TLS port 8883, `FIREBASE_SERVICE_ACCOUNT_B64`,
 `TOKENS_FILE_PATH` untuk persistent volume). 

Local service akan berjalan di `http://localhost:3000` (atau port yang dikonfigurasi di `.env`).

## 📡 API Endpoints

### Health Check

**GET** `/health`

Cek status service dan koneksi MQTT/FCM (dipakai juga sebagai uptime probe).

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2026-08-23T03:42:11.250Z",
  "uptimeSec": 49,
  "services": {
    "mqtt": {
      "connected": true,
      "reconnectAttempts": 0
    },
    "fcm": {
      "initialized": true
    }
  },
  "camerasTracked": 1,
  "deviceTokens": 1
}
```

### Get Camera Status (untuk sinkronisasi app)

**GET** `/api/status`

Status terakhir semua kamera dari pesan MQTT yang diterima. Dipakai aplikasi
Flutter saat startup/resume agar tampilan selalu sesuai kondisi broker.

**Response:**
```json
{
  "success": true,
  "timestamp": "2026-08-23T03:42:20.000Z",
  "totalCameras": 1,
  "cameras": [
    {
      "camera_id": "CAM05",
      "status": "DANGER",
      "confidence": 0.91,
      "location": "Rooftop Gedung A",
      "topic": "saferise/camera/CAM05/status",
      "receivedAt": "2026-08-23T03:40:00.000Z"
    }
  ]
}
```

### Register Device Token

**POST** `/api/tokens`

Registrasi FCM token dari mobile device.

**Body:**
```json
{
  "token": "FCM_DEVICE_TOKEN_HERE"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Token registered successfully",
  "token": "dA7g8K9s2...",
  "totalTokens": 1
}
```

### Unregister Device Token

**DELETE** `/api/tokens/:token`

Hapus device token dari registry.

**Response:**
```json
{
  "success": true,
  "message": "Token unregistered successfully",
  "totalTokens": 0
}
```

### Get All Tokens (Debug Only)

**GET** `/api/tokens`

Dapatkan semua registered tokens.

**Response:**
```json
{
  "success": true,
  "totalTokens": 2,
  "tokens": ["dA7g8K9s2...", "xB3h7L2m9..."]
}
```

### Send Test Notification (Debug Only)

**POST** `/api/test/notification`

Kirim test notification ke semua device.

**Body:**
```json
{
  "title": "Test Notification",
  "body": "This is a test message"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Test notification sent",
  "result": {
    "successCount": 2,
    "failureCount": 0
  }
}
```

### Publish MQTT Message (Debug Only)

**POST** `/api/mqtt/publish`

Publish test message ke MQTT broker.

**Body:**
```json
{
  "topic": "saferise/camera/TEST01/status",
  "message": {
    "camera_id": "TEST01",
    "status": "DANGER",
    "confidence": 0.95,
    "location": "Test Location",
    "timestamp": "2026-08-22T16:30:00Z"
  }
}
```

## 📨 MQTT Topics

Service subscribe ke topics berikut:

- `saferise/camera/+/status` - Status camera (NORMAL/DANGER/OFFLINE)
- `saferise/camera/+/detection` - Detection events
- `saferise/camera/+/connection` - Connection status

### ⚠️ Aturan Protokol Publishing

> **Semua transisi status (NORMAL / DANGER / OFFLINE) WAJIB dipublish ke
> `saferise/camera/{camera_id}/status`.**

- Topik `/detection` dan `/connection` bersifat **fire-and-forget**: hanya
  diterima oleh device yang sedang online pada saat pesan dikirim, dan
  **tidak di-retain**. Jangan pernah mengirim transisi status lewat topik
  ini -- status akan hilang saat app/backend reconnect.
- Hanya pesan di `/status` yang di-retain: backend menyimpan dan
  re-publish pesan `/status` terakhir sebagai retained message, sehingga
  app yang baru online / reconnect langsung menerima status terkini
  (mis. alarm DANGER tetap berbunyi meski HP sempat mati).
- **Hati-hati salah ketik topik** (mis. `detaction` ≠ `detection`): MQTT
  tidak menghasilkan error apa pun untuk topik tak dikenal -- pesannya
  hilang diam-diam tanpa diproses siapa pun.

### Payload Format

Contoh payload DANGER yang dipublish ke `saferise/camera/CAM05/status`:

```json
{
  "camera_id": "CAM05",
  "status": "DANGER",
  "confidence": 0.91,
  "location": "Gedung A, Lantai 15, Atap Timur",
  "timestamp": "2026-08-22T14:32:10Z",
  "audio": "PLAYING",
  "detection_id": "det_1234567890"
}
```

## 🔔 FCM Notification Format

Ketika status "DANGER" terdeteksi, service mengirim notification dengan format:

**Title:** `⚠️ PERINGATAN BAHAYA!`

**Body:** `Bahaya terdeteksi di [location]. Confidence: [confidence]%`

**Data Payload:**
```json
{
  "type": "DANGER_ALERT",
  "cameraId": "CAM05",
  "location": "Gedung A, Lantai 15, Atap Timur",
  "confidence": "0.91",
  "timestamp": "2026-08-22T14:32:10Z",
  "detectionId": "det_1234567890"
}
```

**Android Configuration:**
- Priority: `high`
- Sound: `default`
- Vibration pattern: `[0, 1000, 500, 1000, 500, 1000]` (vibrate 3x with pauses)
- Channel ID: `danger_alerts`

## 🧪 Testing

### 1. Test MQTT Connection

Gunakan MQTT client seperti [MQTTX](https://mqttx.app/) atau `mosquitto_pub`:

```bash
mosquitto_pub -h broker.hivemq.com -t "saferise/camera/TEST01/status" -m '{"camera_id":"TEST01","status":"DANGER","confidence":0.95,"location":"Test Location","timestamp":"2026-08-22T16:30:00Z"}'
```

### 2. Test FCM Notification via API

```bash
# Register device token
curl -X POST http://localhost:3000/api/tokens \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_FCM_TOKEN_HERE"}'

# Send test notification
curl -X POST http://localhost:3000/api/test/notification \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Alert","body":"This is a test"}'
```

### 3. Simulate DANGER via API

```bash
curl -X POST http://localhost:3000/api/mqtt/publish \
  -H "Content-Type: application/json" \
  -d '{
    "topic": "saferise/camera/TEST01/status",
    "message": {
      "camera_id": "TEST01",
      "status": "DANGER",
      "confidence": 0.95,
      "location": "Test Location",
      "timestamp": "2026-08-22T16:30:00Z"
    }
  }'
```

## 📁 Project Structure

```
backend/
├── src/
│   ├── index.js              # Main entry point
│   ├── mqtt-subscriber.js    # MQTT service
│   └── fcm-service.js        # FCM notification service
├── config/
│   └── firebase-service-account.json  # Firebase credentials (not in git)
├── .env                      # Environment variables (not in git)
├── .env.example              # Template for .env
├── package.json              # Dependencies
└── README.md                 # This file
```

## 🔐 Security Best Practices

1. **Never commit credentials** - Add ke `.gitignore`:
   - `firebase-service-account.json`
   - `.env`

2. **Restrict API endpoints** - Dalam production:
   - Batasi akses ke `/api/tokens` (GET)
   - Disable atau protect `/api/test/*` endpoints
   - Gunakan authentication/authorization

3. **Use environment variables** - Jangan hardcode credentials di kode

4. **HTTPS only** - Gunakan HTTPS untuk production deployment

5. **Token validation** - Validasi FCM tokens sebelum registrasi

## 🚧 Troubleshooting

### Problem: Service tidak bisa connect ke MQTT

**Solution:**
- Cek konfigurasi `MQTT_BROKER_HOST` dan `MQTT_BROKER_PORT` di `.env`
- Pastikan broker accessible dari network Anda
- Cek firewall settings
- Coba gunakan public broker: `broker.hivemq.com:1883`

### Problem: Firebase Admin SDK initialization failed

**Solution:**
- Pastikan file `firebase-service-account.json` ada di folder `config/`
- Cek path di `FIREBASE_SERVICE_ACCOUNT_PATH` benar
- Validasi format JSON file (harus valid JSON)
- Pastikan service account punya permission yang cukup

### Problem: Notifications tidak sampai ke device

**Solution:**
- Pastikan FCM token sudah registered (`POST /api/tokens`)
- Cek logs untuk error messages
- Pastikan Cloud Messaging API enabled di Firebase Console
- Test dengan `/api/test/notification` endpoint
- Pastikan mobile app sudah setup Firebase dengan benar

### Problem: "Invalid registration token" error

**Solution:**
- Token sudah expired atau invalid
- Re-register device token dari mobile app
- Service akan auto-remove invalid tokens

## 🔄 Deployment

### Using PM2 (Production)

```bash
# Install PM2
npm install -g pm2

# Start service
pm2 start src/index.js --name saferise-backend

# View logs
pm2 logs saferise-backend

# Monitor
pm2 monit

# Restart
pm2 restart saferise-backend

# Stop
pm2 stop saferise-backend
```

### Using Docker (Optional)

Create `Dockerfile`:

```dockerfile
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 3000

CMD ["node", "src/index.js"]
```

Build and run:

```bash
docker build -t saferise-backend .
docker run -p 3000:3000 --env-file .env saferise-backend
```

### Environment Variables for Production

```env
NODE_ENV=production
PORT=3000
MQTT_BROKER_HOST=your-production-broker.com
FIREBASE_PROJECT_ID=your-production-project-id
LOG_LEVEL=warn
```

## 📊 Monitoring & Logging

Service logs ke console dengan format:

- `[MQTT]` - MQTT related logs
- `[FCM]` - FCM notification logs
- `[MSG]` - General message logs
- `[HTTP]` - HTTP request log (skip /health)
- `[STATUS]` - Status periodik tiap STATUS_LOG_INTERVAL_SEC detik (mqtt connected, jumlah kamera & token terdaftar)

**Log levels:**
- ✅ Success/Info
- ⚠️ Warning
- ❌ Error
- 🚨 Danger detected

## 🤝 Integration dengan Flutter App

Di Flutter app, panggil API untuk register token setelah dapat FCM token:

```dart
// Get FCM token
String? token = await FirebaseMessaging.instance.getToken();

// Register with backend
final response = await http.post(
  Uri.parse('http://your-backend-url:3000/api/tokens'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'token': token}),
);
```

## 📝 TODO / Future Improvements

- [ ] Database untuk persistent token storage (PostgreSQL/MongoDB)
- [ ] User authentication & authorization
- [ ] Rate limiting untuk API endpoints
- [ ] Webhook untuk delivery reports
- [ ] Dashboard untuk monitoring
- [ ] Email/SMS alerts sebagai backup
- [ ] Clustering untuk high availability
- [ ] Message queue (RabbitMQ/Redis) untuk reliability

## 📄 License

MIT

## 👨‍💻 Support

Untuk issues atau pertanyaan, buat issue di repository atau contact tim development.

---

**Last updated:** 2026-08-23
**Version:** 1.1.0 (backend deployed ke Railway; app belum dirilis)
