/**
 * FCM Notification Service
 * Initializes Firebase Admin SDK and handles sending push notifications.
 */

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

class FcmService {
  constructor(config) {
    this.config = config;
    this.isInitialized = false;
    // Token disimpan in-memory untuk akses cepat, tapi dipersist ke file
    // supaya tidak hilang saat proses backend restart.
    // Path di-resolve relatif terhadap folder backend (src/..) supaya
    // tidak tergantung current working directory saat node dijalankan.
    // Override via env TOKENS_FILE_PATH untuk persistent volume di hosting
    // cloud (mis. Railway volume di-mount ke /data).
    this.deviceTokens = [];
    this.tokensFilePath = process.env.TOKENS_FILE_PATH
      ? path.resolve(process.env.TOKENS_FILE_PATH)
      : path.resolve(
          config.tokensFilePath || path.join(__dirname, '..', 'config', 'device-tokens.json')
        );

    this.loadDeviceTokens();
    this.initializeFirebase();
  }

  /**
   * Load persisted device tokens from disk (survives restarts)
   */
  loadDeviceTokens() {
    try {
      if (fs.existsSync(this.tokensFilePath)) {
        const raw = fs.readFileSync(this.tokensFilePath, 'utf8');
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) {
          this.deviceTokens = parsed.filter(t => typeof t === 'string' && t.length > 0);
        }
      }
    } catch (error) {
      console.error('[FCM] ⚠️ Failed to load device tokens from disk:', error.message);
    }
    console.log(`[FCM] ℹ️ Loaded ${this.deviceTokens.length} device token(s) from ${this.tokensFilePath}`);
  }

  /**
   * Persist device tokens to disk
   */
  saveDeviceTokens() {
    try {
      const dir = path.dirname(this.tokensFilePath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      fs.writeFileSync(this.tokensFilePath, JSON.stringify(this.deviceTokens, null, 2), 'utf8');
    } catch (error) {
      console.error('[FCM] ⚠️ Failed to save device tokens to disk:', error.message);
    }
  }

  /**
   * Initialize Firebase Admin SDK
   *
   * Dua sumber service account (urut prioritas):
   * 1. FIREBASE_SERVICE_ACCOUNT_B64 : isi env var = base64 dari file JSON
   *    service account. Dipakai di hosting cloud (Render dll) yang tidak
   *    memungkinkan commit file rahasia -- cukup tempel base64 di dashboard.
   * 2. FIREBASE_SERVICE_ACCOUNT_PATH: file JSON di disk (mode lokal/VPS).
   */
  initializeFirebase() {
    try {
      let serviceAccount;

      const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_B64;
      if (b64 && b64.trim()) {
        console.log('[FCM] Loading service account from FIREBASE_SERVICE_ACCOUNT_B64 (env)');
        const json = Buffer.from(b64.trim(), 'base64').toString('utf8');
        serviceAccount = JSON.parse(json);
      } else {
        const serviceAccountPath = path.resolve(this.config.serviceAccountPath);
        console.log(`[FCM] Loading service account from: ${serviceAccountPath}`);
        delete require.cache[require.resolve(serviceAccountPath)];
        serviceAccount = require(serviceAccountPath);
      }

      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: this.config.projectId || serviceAccount.project_id,
      });

      this.isInitialized = true;
      console.log('[FCM] ✅ Firebase Admin SDK initialized successfully');
    } catch (error) {
      console.error('[FCM] ❌ Failed to initialize Firebase Admin SDK:', error.message);
      // Exit process if Firebase fails to initialize, as it's a core dependency
      process.exit(1);
    }
  }

  /**
   * Register a new device token
   */
  addDeviceToken(token) {
    if (!this.deviceTokens.includes(token)) {
      this.deviceTokens.push(token);
      this.saveDeviceTokens();
      console.log(`[FCM] ✅ Device token added: ${token.substring(0, 10)}...`);
      return true;
    }
    console.log(`[FCM] ℹ️ Device token already exists: ${token.substring(0, 10)}...`);
    return false;
  }

  /**
   * Remove a device token
   */
  removeDeviceToken(token) {
    const initialLength = this.deviceTokens.length;
    this.deviceTokens = this.deviceTokens.filter(t => t !== token);
    if (this.deviceTokens.length < initialLength) {
      this.saveDeviceTokens();
      console.log(`[FCM] ✅ Device token removed: ${token.substring(0, 10)}...`);
      return true;
    }
    console.log(`[FCM] ℹ️ Device token not found: ${token.substring(0, 10)}...`);
    return false;
  }

  /**
   * Get all registered device tokens
   */
  getDeviceTokens() {
    return this.deviceTokens;
  }

  /**
   * Send a single FCM notification to a specific device token.
   */
  async sendNotificationToDevice(token, title, body, data = {}) {
    if (!this.isInitialized) {
      console.error('[FCM] ❌ Firebase Admin SDK not initialized.');
      return null;
    }

    const message = {
      token: token,
      notification: {
        title: title,
        body: body,
      },
      data: { ...data, type: 'DANGER_ALERT' },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          // Custom vibration pattern: wait 0s, vibrate 1s, wait 0.5s, vibrate 1s, wait 0.5s, vibrate 1s
          vibrationPattern: [0, 1000, 500, 1000, 500, 1000],
          // Custom channel ID (must match what's configured in the Android app)
          channelId: 'danger_alerts',
        },
      },
      apns: { // Apple Push Notification Service for iOS
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            alert: {
              title: title,
              body: body,
            },
            sound: 'default',
            // For custom vibration on iOS, typically requires client-side handling
          },
        },
      },
      webpush: { // Web Push for web clients
        headers: {
          Urgency: 'high',
        },
        notification: {
          title: title,
          body: body,
          vibrate: [0, 1000, 500, 1000, 500, 1000],
        },
      },
    };

    try {
      const response = await admin.messaging().send(message);
      console.log('[FCM] ✅ Successfully sent message to device:', response);
      return response;
    } catch (error) {
      console.error('[FCM] ❌ Error sending message to device:', error);
      // Handle specific error codes if needed, e.g., token invalidation
      if (error.code === 'messaging/invalid-registration-token' ||
          error.code === 'messaging/registration-token-not-registered') {
        console.warn(`[FCM] Removing invalid token: ${token.substring(0, 10)}...`);
        this.removeDeviceToken(token);
      }
      return null;
    }
  }

  /**
   * Send an FCM notification to all registered devices.
   * @param {object} options
   *   - type: tipe data message ('DANGER_ALERT' default | 'STATUS_NORMAL')
   *   - alarm: true -> prioritas high (DANGER); false -> normal
   */
  async sendNotificationToAllDevices(title, body, data = {}, options = {}) {
    if (!this.isInitialized) {
      console.error('[FCM] ❌ Firebase Admin SDK not initialized.');
      return [];
    }

    const {
      type = 'DANGER_ALERT',
      alarm = type === 'DANGER_ALERT',
    } = options;

    if (this.deviceTokens.length === 0) {
      console.log('[FCM] ℹ️ No device tokens registered. Skipping notification.');
      return [];
    }

    console.log(`[FCM] Sending notification to ${this.deviceTokens.length} devices.`);

    // PENTING (Android): pesan HARUS data-only (tanpa top-level `notification`
    // dan tanpa android.notification). Jika ada notification payload, saat
    // app background/killed Android menampilkan tray sendiri dan
    // onMessageReceived TIDAK dipanggil -> alarm loop native tidak pernah
    // start. Dengan data-only, MyFirebaseMessagingService selalu menerima
    // pesan: posting notifikasi + mulai/mati-kan AlarmLooper.
    const message = {
      data: {
        type: options.type || 'DANGER_ALERT',
        title,
        body,
        ...data,
      },
      android: {
        priority: alarm ? 'high' : 'normal',
      },
      // iOS & Web tetap pakai notification payload (tidak ada handler native).
      apns: {
        headers: {
          'apns-priority': alarm ? '10' : '5',
        },
        payload: {
          aps: {
            alert: {
              title: title,
              body: body,
            },
            sound: 'default',
          },
        },
      },
      webpush: {
        headers: {
          Urgency: alarm ? 'high' : 'normal',
        },
        notification: {
          title: title,
          body: body,
          ...(alarm ? { vibrate: [0, 1000, 500, 1000, 500, 1000] } : {}),
        },
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast({
        ...message,
        tokens: this.deviceTokens,
      });
      console.log(`[FCM] ✅ Successfully sent multicast message. Success: ${response.successCount}, Failure: ${response.failureCount}`);

      // Clean up invalid tokens
      if (response.failureCount > 0) {
        const tokensToRemove = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success && (
              resp.error.code === 'messaging/invalid-registration-token' ||
              resp.error.code === 'messaging/registration-token-not-registered')) {
            tokensToRemove.push(this.deviceTokens[idx]);
          }
        });
        this.deviceTokens = this.deviceTokens.filter(token => !tokensToRemove.includes(token));
        this.saveDeviceTokens();
        console.log(`[FCM] Removed ${tokensToRemove.length} invalid tokens.`);
      }

      return response;
    } catch (error) {
      console.error('[FCM] ❌ Error sending multicast message:', error);
      return null;
    }
  }
}

module.exports = FcmService;
