/**
 * SafeRise Backend Service - Main Entry Point
 * Integrates MQTT subscriber and FCM notification service
 * Provides HTTP API for device token registration
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const MqttSubscriber = require('./mqtt-subscriber');
const FcmService = require('./fcm-service');

// ============================================================================
// Configuration
// ============================================================================

const config = {
  port: process.env.PORT || 3000,
  nodeEnv: process.env.NODE_ENV || 'development',
  mqtt: {
    host: process.env.MQTT_BROKER_HOST || 'broker.hivemq.com',
    port: parseInt(process.env.MQTT_BROKER_PORT) || 1883,
    username: process.env.MQTT_USERNAME || '',
    password: process.env.MQTT_PASSWORD || '',
    topicPrefix: process.env.MQTT_TOPIC_PREFIX || 'saferise/camera/',
  },
  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID || 'saferise-alert-system',
    serviceAccountPath: process.env.FIREBASE_SERVICE_ACCOUNT_PATH || './config/firebase-service-account.json',
  },
};

// ============================================================================
// Initialize Express App
// ============================================================================

const app = express();
app.use(cors());
app.use(express.json());

// HTTP request logger ringan (tanpa dependency) -- skip /health supaya
// keep-alive pinger tidak membanjiri log di production.
app.use((req, res, next) => {
  if (req.path === '/health') return next();
  const start = Date.now();
  res.on('finish', () => {
    console.log(`[HTTP] ${req.method} ${req.originalUrl} -> ${res.statusCode} (${Date.now() - start}ms)`);
  });
  next();
});

// ============================================================================
// Initialize Services
// ============================================================================

let mqttSubscriber;
let fcmService;

console.log('\n🚀 SafeRise Backend Service Starting...\n');
console.log('📋 Configuration:');
console.log('  Port:', config.port);
console.log('  Node Env:', config.nodeEnv);
console.log('  MQTT Broker:', `${config.mqtt.host}:${config.mqtt.port}`);
console.log('  Firebase Project:', config.firebase.projectId);
console.log('\n');

try {
  // Initialize FCM Service
  fcmService = new FcmService(config.firebase);

  // Initialize MQTT Subscriber
  mqttSubscriber = new MqttSubscriber(config.mqtt);
  mqttSubscriber.connect();

  // ========================================================================
  // MQTT Event Handlers
  // ========================================================================

  // When DANGER status is detected on any camera
  mqttSubscriber.on('danger', async (event) => {
    const { cameraId, payload } = event;

    console.log(`\n🚨🚨🚨 DANGER DETECTED 🚨🚨🚨`);
    console.log(`Camera: ${cameraId}`);
    console.log(`Confidence: ${payload.confidence || 'N/A'}`);
    console.log(`Location: ${payload.location || 'N/A'}`);
    console.log(`Time: ${payload.timestamp || 'N/A'}\n`);

    // Prepare FCM notification payload
    const title = '⚠️ PERINGATAN BAHAYA!';
    const body = `Bahaya terdeteksi di ${payload.location || cameraId}. Confidence: ${Math.round((payload.confidence || 0) * 100)}%`;
    const data = {
      type: 'DANGER_ALERT',
      cameraId: cameraId,
      location: payload.location || '',
      confidence: String(payload.confidence || 0),
      timestamp: payload.timestamp || new Date().toISOString(),
      detectionId: payload.detection_id || '',
    };

    // Send FCM notifications to all registered devices
    const tokens = fcmService.getDeviceTokens();
    if (tokens.length > 0) {
      console.log(`📤 Sending danger notification to ${tokens.length} device(s)...`);
      await fcmService.sendNotificationToAllDevices(title, body, data);
    } else {
      console.log('⚠️ No device tokens registered. Notification not sent.');
    }
  });

  // When a camera that was DANGER returns to NORMAL -> stop alarm on devices
  mqttSubscriber.on('normal', async (event) => {
    const { cameraId, payload } = event;

    console.log(`\n✅ CAMERA BACK TO NORMAL ✅`);
    console.log(`Camera: ${cameraId}`);
    console.log(`Status: ${payload.status}\n`);

    const title = '✅ Situasi Aman';
    const body = `${cameraId} kembali normal. Alarm dihentikan.`;
    const data = {
      type: 'STATUS_NORMAL',
      cameraId: cameraId,
      status: payload.status || 'NORMAL',
      timestamp: payload.timestamp || new Date().toISOString(),
    };

    const tokens = fcmService.getDeviceTokens();
    if (tokens.length > 0) {
      console.log(`📤 Sending all-clear notification to ${tokens.length} device(s)...`);
      await fcmService.sendNotificationToAllDevices(title, body, data, {
        type: 'STATUS_NORMAL',
        alarm: false,
      });
    } else {
      console.log('⚠️ No device tokens registered. Notification not sent.');
    }
  });

  // General message handler (for logging/monitoring)
  mqttSubscriber.on('message', (event) => {
    const { cameraId, payload } = event;
    console.log(`[MSG] Camera ${cameraId}: Status=${payload.status}, Confidence=${payload.confidence}`);
  });

  // MQTT error handler
  mqttSubscriber.on('error', (error) => {
    console.error('❌ MQTT Error:', error.message);
  });

} catch (error) {
  console.error('❌ Failed to initialize services:', error.message);
  process.exit(1);
}

// ============================================================================
// HTTP Routes
// ============================================================================

/**
 * GET /health
 * Health check endpoint (dipakai juga keep-alive pinger di production)
 */
app.get('/health', (req, res) => {
  const mqttStatus = mqttSubscriber ? mqttSubscriber.getStatus() : { connected: false };
  const fcmStatus = { initialized: fcmService ? fcmService.isInitialized : false };

  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptimeSec: Math.round(process.uptime()),
    services: {
      mqtt: mqttStatus,
      fcm: fcmStatus,
    },
    camerasTracked: mqttSubscriber ? mqttSubscriber.getLastStatuses().length : 0,
    deviceTokens: fcmService ? fcmService.getDeviceTokens().length : 0,
  });
});

/**
 * POST /api/tokens
 * Register a new device token for FCM notifications
 * Body: { token: "FCM_TOKEN_STRING" }
 */
app.post('/api/tokens', (req, res) => {
  try {
    const { token } = req.body;

    if (!token) {
      return res.status(400).json({ error: 'Token is required' });
    }

    if (!fcmService) {
      return res.status(503).json({ error: 'FCM service not initialized' });
    }

    const added = fcmService.addDeviceToken(token);

    res.json({
      success: true,
      message: added ? 'Token registered successfully' : 'Token already registered',
      token: token.substring(0, 10) + '...',
      totalTokens: fcmService.getDeviceTokens().length,
    });
  } catch (error) {
    console.error('❌ Error registering token:', error);
    res.status(500).json({ error: 'Failed to register token' });
  }
});

/**
 * DELETE /api/tokens/:token
 * Unregister a device token
 */
app.delete('/api/tokens/:token', (req, res) => {
  try {
    const { token } = req.params;

    if (!fcmService) {
      return res.status(503).json({ error: 'FCM service not initialized' });
    }

    const removed = fcmService.removeDeviceToken(token);

    res.json({
      success: true,
      message: removed ? 'Token unregistered successfully' : 'Token not found',
      totalTokens: fcmService.getDeviceTokens().length,
    });
  } catch (error) {
    console.error('❌ Error unregistering token:', error);
    res.status(500).json({ error: 'Failed to unregister token' });
  }
});

/**
 * GET /api/tokens
 * Get all registered device tokens (for debugging only - should be restricted in production)
 */
app.get('/api/tokens', (req, res) => {
  try {
    if (!fcmService) {
      return res.status(503).json({ error: 'FCM service not initialized' });
    }

    const tokens = fcmService.getDeviceTokens();

    res.json({
      success: true,
      totalTokens: tokens.length,
      tokens: tokens.map(t => t.substring(0, 10) + '...'),
    });
  } catch (error) {
    console.error('❌ Error retrieving tokens:', error);
    res.status(500).json({ error: 'Failed to retrieve tokens' });
  }
});

/**
 * GET /api/status
 * Status terakhir semua kamera (dari pesan MQTT terakhir yang diterima).
 * Dipakai aplikasi Flutter untuk sinkronisasi tampilan saat startup
 * sehingga UI selalu sesuai dengan simulasi/kondisi broker terbaru.
 */
app.get('/api/status', (req, res) => {
  try {
    if (!mqttSubscriber) {
      return res.status(503).json({ error: 'MQTT service not initialized' });
    }

    const cameras = mqttSubscriber.getLastStatuses();

    res.json({
      success: true,
      timestamp: new Date().toISOString(),
      totalCameras: cameras.length,
      cameras,
    });
  } catch (error) {
    console.error('❌ Error retrieving camera status:', error);
    res.status(500).json({ error: 'Failed to retrieve camera status' });
  }
});

/**
 * POST /api/test/notification
 * Send a test notification to all devices (for debugging only)
 * Body: { title: "Test Title", body: "Test Body" }
 */
app.post('/api/test/notification', async (req, res) => {
  try {
    const { title, body } = req.body;

    if (!title || !body) {
      return res.status(400).json({ error: 'Title and body are required' });
    }

    if (!fcmService) {
      return res.status(503).json({ error: 'FCM service not initialized' });
    }

    const totalTokens = fcmService.getDeviceTokens().length;

    if (totalTokens === 0) {
      return res.status(409).json({
        success: false,
        warning: 'No device tokens registered. Launch the Flutter app (with adb reverse tcp:3000 active) to register a token first.',
        result: { successCount: 0, failureCount: 0 },
      });
    }

    const result = await fcmService.sendNotificationToAllDevices(title, body);

    res.json({
      success: true,
      message: 'Test notification sent',
      result: {
        successCount: result?.successCount || 0,
        failureCount: result?.failureCount || 0,
        totalTokens,
      },
    });
  } catch (error) {
    console.error('❌ Error sending test notification:', error);
    res.status(500).json({ error: 'Failed to send test notification' });
  }
});

/**
 * POST /api/mqtt/publish
 * Publish a test message to MQTT broker (for debugging only)
 * Body: { topic: "saferise/camera/TEST/status", message: {...} }
 */
app.post('/api/mqtt/publish', (req, res) => {
  try {
    const { topic, message } = req.body;

    if (!topic || !message) {
      return res.status(400).json({ error: 'Topic and message are required' });
    }

    if (!mqttSubscriber) {
      return res.status(503).json({ error: 'MQTT service not initialized' });
    }

    mqttSubscriber.publish(topic, message);

    res.json({
      success: true,
      message: 'Message published to MQTT',
      topic,
    });
  } catch (error) {
    console.error('❌ Error publishing MQTT message:', error);
    res.status(500).json({ error: 'Failed to publish MQTT message' });
  }
});

// ============================================================================
// Error Handling Middleware
// ============================================================================

app.use((err, req, res, next) => {
  console.error('❌ Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// ============================================================================
// 404 Handler
// ============================================================================

app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// ============================================================================
// Start Server
// ============================================================================

// ============================================================================
// Periodic Status Logging (monitoring ringan, tanpa dependency)
// Aktif saat STATUS_LOG_INTERVAL_SEC > 0 (production: 60 detik).
// ============================================================================

const statusIntervalSec = parseInt(process.env.STATUS_LOG_INTERVAL_SEC) || 0;
if (statusIntervalSec > 0) {
  setInterval(() => {
    const mqttStatus = mqttSubscriber ? mqttSubscriber.getStatus() : { connected: false };
    const tokenCount = fcmService ? fcmService.getDeviceTokens().length : 0;
    const cameraCount = mqttSubscriber ? mqttSubscriber.getLastStatuses().length : 0;
    console.log(
      `[STATUS] uptime=${Math.round(process.uptime())}s ` +
      `mqtt=${mqttStatus.connected ? 'connected' : 'disconnected'} ` +
      `(reconnectAttempts=${mqttStatus.reconnectAttempts ?? 0}) ` +
      `cameras=${cameraCount} tokens=${tokenCount}`
    );
  }, statusIntervalSec * 1000);
}

const server = app.listen(config.port, () => {
  console.log(`\n✅ SafeRise Backend Service is running on port ${config.port}`);
  console.log(`📍 Health check: http://localhost:${config.port}/health\n`);
});

// ============================================================================
// Graceful Shutdown
// ============================================================================

process.on('SIGTERM', () => {
  console.log('\n⚠️ SIGTERM received, shutting down gracefully...\n');
  shutdown();
});

process.on('SIGINT', () => {
  console.log('\n⚠️ SIGINT received, shutting down gracefully...\n');
  shutdown();
});

function shutdown() {
  console.log('🛑 Closing server...');
  server.close(() => {
    console.log('✅ Server closed');
    
    if (mqttSubscriber) {
      console.log('🛑 Disconnecting from MQTT...');
      mqttSubscriber.disconnect();
    }
    
    console.log('👋 Goodbye!\n');
    process.exit(0);
  });

  // Force exit after 10 seconds
  setTimeout(() => {
    console.error('❌ Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
}

// Handle uncaught exceptions: LOG ONLY, jangan shutdown.
// Error MQTT/reconnect loop tidak boleh mematikan server FCM
// (token registry akan hilang). Cukup log & biarkan MQTT client reconnect.
process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception (server tetap berjalan):', error);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection (server tetap berjalan) at:', promise, 'reason:', reason);
});

module.exports = { app, mqttSubscriber, fcmService };
