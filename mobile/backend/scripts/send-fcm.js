/**
 * Standalone FCM test sender - bypasses HTTP server.
 * Usage: node send-fcm.js <deviceToken> [title] [body] [count]
 */
require('dotenv').config();
const admin = require('firebase-admin');
const path = require('path');

const serviceAccountPath = path.resolve(
  process.env.FIREBASE_SERVICE_ACCOUNT_PATH || './config/firebase-service-account.json'
);
const serviceAccount = require(serviceAccountPath);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: process.env.FIREBASE_PROJECT_ID || 'saferise-alert-system',
});

const token = process.argv[2];
const title = process.argv[3] || '🚨 BAHAYA KRITIS! - TEST-02';
const body =
  process.argv[4] || 'Terdeteksi bahaya di Gedung A, Lantai 15. Confidence: 95%.';
const count = parseInt(process.argv[5] || '1', 10);

if (!token) {
  console.error('Usage: node send-fcm.js <deviceToken> [title] [body] [count]');
  process.exit(1);
}

async function main() {
  const results = [];
  for (let i = 0; i < count; i++) {
    const suffix = count > 1 ? ` #${i + 1}` : '';
    const message = {
      token,
      // Data-only untuk Android: wajib supaya onMessageReceived dipanggil
      // saat app background/killed (pemicu alarm loop native).
      data: {
        type: 'DANGER_ALERT',
        title: `${title}${suffix}`,
        body,
        cameraId: 'CAM05',
        confidence: '95',
        timestamp: new Date().toISOString(),
      },
      android: {
        priority: 'high',
        ttl: 3600000,
      },
    };
    try {
      const res = await admin.messaging().send(message);
      console.log(`[${i + 1}/${count}] ✅ Sent: ${res}`);
      results.push(res);
    } catch (err) {
      console.error(`[${i + 1}/${count}] ❌ Error: ${err.code || err.message}`);
      process.exitCode = 1;
      return;
    }
    if (i < count - 1) await new Promise((r) => setTimeout(r, 1500));
  }
  console.log(`\nDone. ${results.length}/${count} delivered.`);
}

main();
