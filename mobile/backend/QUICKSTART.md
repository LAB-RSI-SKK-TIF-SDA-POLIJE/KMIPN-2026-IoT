# 🚀 Quick Start Guide - SafeRise Backend Service

## Prerequisites Checklist

Before starting the backend service, ensure you have:

- [x] Node.js v18+ installed
- [x] npm dependencies installed (`npm install` completed)
- [ ] Firebase project created
- [ ] Firebase service account key downloaded
- [ ] `.env` file configured

## Step-by-Step Setup

### 1. Firebase Setup (Required)

If you haven't set up Firebase yet, follow these steps:

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a new project: "SafeRise Alert System"
3. Add Android app with package: `com.example.saferise_mobileapps`
4. Download `google-services.json` (for Flutter app)
5. Go to Project Settings → Service Accounts
6. Click "Generate new private key"
7. Save the downloaded JSON file as `firebase-service-account.json`
8. Copy it to: `backend/config/firebase-service-account.json`

**⚠️ IMPORTANT**: Never commit this file to Git!

### 2. Configure Environment Variables

Edit `backend/.env` file:

```env
FIREBASE_PROJECT_ID=your-actual-project-id
FIREBASE_SERVICE_ACCOUNT_PATH=./config/firebase-service-account.json
MQTT_BROKER_HOST=broker.hivemq.com
MQTT_BROKER_PORT=1883
MQTT_TOPIC_PREFIX=saferise/camera/
PORT=3000
NODE_ENV=development
```

### 3. Start the Backend Service

```bash
cd backend
npm start
```

You should see:

```
🚀 SafeRise Backend Service Starting...

📋 Configuration:
  Port: 3000
  Node Env: development
  MQTT Broker: broker.hivemq.com:1883
  Firebase Project: your-project-id

[FCM] ✅ Firebase Admin SDK initialized successfully
[MQTT] Connecting to mqtt://broker.hivemq.com:1883...
[MQTT] ✅ Connected to MQTT broker
[MQTT] ✅ Subscribed to: saferise/camera/+/status
[MQTT] ✅ Subscribed to: saferise/camera/+/detection
[MQTT] ✅ Subscribed to: saferise/camera/+/connection

✅ SafeRise Backend Service is running on port 3000
📍 Health check: http://localhost:3000/health
```

### 4. Test the Service

Open a new terminal and test the health endpoint:

```bash
curl http://localhost:3000/health
```

Expected response:

```json
{
  "status": "ok",
  "timestamp": "2026-08-22T16:36:00.000Z",
  "services": {
    "mqtt": {
      "connected": true,
      "reconnectAttempts": 0
    },
    "fcm": {
      "initialized": true
    }
  }
}
```

## Testing MQTT to FCM Flow

### Test 1: Register a Device Token

```bash
curl -X POST http://localhost:3000/api/tokens \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_FCM_TOKEN_FROM_FLUTTER_APP"}'
```

### Test 2: Simulate DANGER Alert

```bash
curl -X POST http://localhost:3000/api/mqtt/publish \
  -H "Content-Type: application/json" \
  -d '{
    "topic": "saferise/camera/CAM01/status",
    "message": {
      "camera_id": "CAM01",
      "status": "DANGER",
      "confidence": 0.95,
      "location": "Gedung A, Lantai 15",
      "timestamp": "2026-08-22T16:36:00Z"
    }
  }'
```

The backend should:
1. Receive the MQTT message
2. Detect "DANGER" status
3. Send FCM notification to all registered devices

### Test 3: Send Test Notification

```bash
curl -X POST http://localhost:3000/api/test/notification \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Alert","body":"Testing FCM notifications"}'
```

## Common Issues

### Issue: "Firebase Admin SDK initialization failed"

**Solution:** 
- Check if `firebase-service-account.json` exists in `backend/config/`
- Verify the file is valid JSON
- Ensure `FIREBASE_SERVICE_ACCOUNT_PATH` in `.env` is correct

### Issue: "MQTT connection failed"

**Solution:**
- Check internet connection
- Try a different public broker: `test.mosquitto.org:1883`
- Verify firewall settings

### Issue: "No device tokens registered"

**Solution:**
- Register a device token first using POST `/api/tokens`
- Get the FCM token from your Flutter app using `FirebaseMessaging.instance.getToken()`

## Next Steps

1. ✅ Backend service running
2. [ ] Set up Flutter app to get FCM token
3. [ ] Register Flutter app token with backend
4. [ ] Connect Raspberry Pi to publish MQTT messages
5. [ ] Test end-to-end flow

## Useful Commands

```bash
# View logs in real-time
npm start

# Stop service (Ctrl+C)

# Check service status
curl http://localhost:3000/health

# View all registered tokens
curl http://localhost:3000/api/tokens
```

## Production Deployment

For production, consider:

1. Use PM2 for process management:
   ```bash
   npm install -g pm2
   pm2 start src/index.js --name saferise-backend
   ```

2. Set environment to production:
   ```env
   NODE_ENV=production
   ```

3. Use a dedicated MQTT broker (not public broker)

4. Add authentication to API endpoints

5. Set up HTTPS/SSL

See `README.md` for detailed documentation.

---

**Service created:** 2026-08-22  
**Last updated:** 2026-08-22
