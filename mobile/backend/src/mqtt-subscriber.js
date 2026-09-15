/**
 * MQTT Subscriber Service
 * Connects to MQTT broker and listens for camera status updates
 * Emits events when DANGER status is detected
 */

const mqtt = require('mqtt');
const EventEmitter = require('events');

class MqttSubscriber extends EventEmitter {
  constructor(config) {
    super();
    this.config = config;
    this.client = null;
    this.isConnected = false;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 10;
    // Track status terakhir per kamera untuk deteksi transisi
    // (mis. DANGER -> NORMAL) supaya event tidak spam berulang.
    this.lastStatus = {};
    // Track payload lengkap terakhir per kamera (untuk GET /api/status)
    this.lastPayloads = {};
  }

  /**
   * Initialize and connect to MQTT broker
   */
  connect() {
    const { host, port, username, password, topicPrefix } = this.config;

    // Port 8883 = TLS (HiveMQ Cloud). Gunakan mqtts:// agar handshake benar.
    const protocol = this.config.protocol || (parseInt(port) === 8883 ? 'mqtts' : 'mqtt');
    const brokerUrl = `${protocol}://${host}:${port}`;
    const options = {
      clientId: `saferise-backend-${Math.random().toString(16).slice(2, 10)}`,
      clean: true,
      connectTimeout: 30000,
      reconnectPeriod: 5000,
    };

    // Add credentials if provided
    if (username) {
      options.username = username;
    }
    if (password) {
      options.password = password;
    }

    console.log(`[MQTT] Connecting to ${brokerUrl}...`);
    this.client = mqtt.connect(brokerUrl, options);

    // Event: Connection established
    this.client.on('connect', () => {
      this.isConnected = true;
      this.reconnectAttempts = 0;
      console.log('[MQTT] ✅ Connected to MQTT broker');
      
      // Subscribe to all camera topics
      this.subscribeToTopics(topicPrefix);
    });

    // Event: Message received
    this.client.on('message', (topic, message) => {
      this.handleMessage(topic, message);
    });

    // Event: Connection error
    this.client.on('error', (error) => {
      console.error('[MQTT] ❌ Connection error:', error.message);
      this.emit('error', error);
    });

    // Event: Connection closed
    this.client.on('close', () => {
      this.isConnected = false;
      console.log('[MQTT] ⚠️ Connection closed');
    });

    // Event: Reconnecting
    this.client.on('reconnect', () => {
      this.reconnectAttempts++;
      console.log(`[MQTT] 🔄 Reconnecting... (attempt ${this.reconnectAttempts})`);
      
      if (this.reconnectAttempts >= this.maxReconnectAttempts) {
        console.error('[MQTT] ❌ Max reconnection attempts reached');
        this.client.end();
      }
    });

    // Event: Offline
    this.client.on('offline', () => {
      console.log('[MQTT] ⚠️ Client is offline');
    });
  }

  /**
   * Subscribe to camera status topics
   */
  subscribeToTopics(topicPrefix) {
    // Subscribe to all camera status topics with wildcard
    const topics = [
      `${topicPrefix}+/status`,
      `${topicPrefix}+/detection`,
      `${topicPrefix}+/connection`
    ];

    topics.forEach(topic => {
      this.client.subscribe(topic, { qos: 1 }, (err) => {
        if (err) {
          console.error(`[MQTT] ❌ Failed to subscribe to ${topic}:`, err.message);
        } else {
          console.log(`[MQTT] ✅ Subscribed to: ${topic}`);
        }
      });
    });
  }

  /**
   * Handle incoming MQTT message
   */
  handleMessage(topic, message) {
    try {
      const payload = JSON.parse(message.toString());
      console.log(`[MQTT] 📨 Message received on ${topic}:`, payload);

      // Extract camera ID from topic
      const cameraId = this.extractCameraId(topic);

      // Simpan payload lengkap terakhir per kamera (dipakai GET /api/status)
      this.lastPayloads[cameraId] = {
        ...payload,
        topic,
        receivedAt: new Date().toISOString(),
      };

      // Abaikan echo dari re-publish retained milik backend ini sendiri,
      // supaya tidak terjadi loop publish dan tidak ada FCM ganda --
      // cukup perbarui lastStatus agar deteksi transisi tetap akurat.
      if (payload.retainedBy === 'saferise-backend') {
        console.log(`[MQTT] ♻️ Retained echo skipped on ${topic}`);
        this.lastStatus[cameraId] = payload.status;
        return;
      }

      // Simpan status terakhir sebagai retained message di broker sehingga
      // subscriber baru (mis. aplikasi yang baru dibuka dari ikon) langsung
      // menerima status terkini tanpa harus menunggu transisi berikutnya.
      if (topic.endsWith('/status')) {
        const retainedPayload = JSON.stringify({
          ...payload,
          retainedBy: 'saferise-backend',
        });
        this.client.publish(topic, retainedPayload, { qos: 1, retain: true }, (err) => {
          if (err) {
            console.error(`[MQTT] ❌ Failed to retain ${topic}:`, err.message);
          } else {
            console.log(`[MQTT] 📌 Status retained on ${topic}`);
          }
        });
      }

      // Deteksi transisi status (mis. DANGER -> NORMAL)
      const previousStatus = this.lastStatus[cameraId];
      this.lastStatus[cameraId] = payload.status;

      // Check if this is a DANGER status
      if (payload.status === 'DANGER') {
        console.log(`[MQTT] 🚨 DANGER DETECTED on ${cameraId}!`);

        // Emit danger event with full payload
        this.emit('danger', {
          cameraId,
          topic,
          payload,
          previousStatus,
          timestamp: new Date().toISOString()
        });
      }

      // Transisi keluar dari DANGER -> kamera kembali aman.
      if (
        previousStatus === 'DANGER' &&
        payload.status &&
        payload.status !== 'DANGER'
      ) {
        console.log(`[MQTT] ✅ ${cameraId} kembali ${payload.status}`);
        this.emit('normal', {
          cameraId,
          topic,
          payload,
          timestamp: new Date().toISOString()
        });
      }

      // Emit general message event for all messages
      this.emit('message', {
        cameraId,
        topic,
        payload,
        timestamp: new Date().toISOString()
      });

    } catch (error) {
      console.error('[MQTT] ❌ Error parsing message:', error.message);
      console.error('[MQTT] Raw message:', message.toString());
    }
  }

  /**
   * Extract camera ID from topic
   * Example: "saferise/camera/CAM05/status" -> "CAM05"
   */
  extractCameraId(topic) {
    const parts = topic.split('/');
    return parts[2] || 'UNKNOWN';
  }

  /**
   * Publish a message to a topic (for testing)
   */
  publish(topic, message) {
    if (!this.isConnected) {
      console.error('[MQTT] ❌ Cannot publish: not connected');
      return;
    }

    const payload = typeof message === 'string' ? message : JSON.stringify(message);
    
    this.client.publish(topic, payload, { qos: 1 }, (err) => {
      if (err) {
        console.error(`[MQTT] ❌ Failed to publish to ${topic}:`, err.message);
      } else {
        console.log(`[MQTT] ✅ Published to ${topic}`);
      }
    });
  }

  /**
   * Disconnect from MQTT broker
   */
  disconnect() {
    if (this.client) {
      console.log('[MQTT] Disconnecting...');
      this.client.end();
      this.isConnected = false;
    }
  }

  /**
   * Get connection status
   */
  getStatus() {
    return {
      connected: this.isConnected,
      reconnectAttempts: this.reconnectAttempts
    };
  }

  /**
   * Get payload terakhir yang diterima per kamera (untuk GET /api/status).
   * Dipakai aplikasi untuk sinkronisasi status saat startup sehingga
   * tampilan selalu sesuai dengan kondisi broker terbaru.
   */
  getLastStatuses() {
    return Object.entries(this.lastPayloads).map(([cameraId, payload]) => ({
      cameraId,
      ...payload,
    }));
  }
}

module.exports = MqttSubscriber;
