import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Topic layout used across the whole system:
///   saferise/camera/{camera_id}/status
///   saferise/camera/{camera_id}/detection
///   saferise/camera/{camera_id}/audio
///   saferise/camera/{camera_id}/connection
///
/// Example payload published by the Raspberry Pi on the /detection topic:
/// {
///   "camera_id": "CAM05",
///   "status": "DANGER",
///   "confidence": 0.91,
///   "location": "Gedung A, Lantai 15, Atap Timur",
///   "timestamp": "2026-08-15T14:32:10",
///   "audio": "PLAYING"
/// }
abstract class MqttService {
  /// Fires whenever a message arrives on any saferise/camera/# topic.
  /// The screens/state layer subscribes to this and merges the payload
  /// into the matching Camera.
  Stream<Map<String, dynamic>> get messages;

  Future<void> connect();
  void disconnect();
}

/// Default implementation for the MVP: no real broker yet, so this lets
/// the Account/Camera-detail screens simulate NORMAL/DANGER/OFFLINE events
/// by pushing a payload into the same stream real MQTT messages would use.
/// Swap this for RealMqttService (below) once the Raspberry Pi + broker
/// are online -- no screen code needs to change, they only depend on
/// the MqttService interface.
class DummyMqttService implements MqttService {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    // no-op: nothing to connect to in dummy mode
  }

  @override
  void disconnect() {
    _controller.close();
  }

  /// Used by the "Simulasi Event" controls in the UI.
  /// [posture] hanya dipakai saat status DANGER (mis. 'climbing' /
  /// 'crouching') supaya badge POSTUR TERDETEKSI bisa diuji.
  void simulate(String cameraId, String status, {String? posture}) {
    final rand = Random();
    final confidence = status == 'DANGER'
        ? 0.88 + rand.nextInt(10) / 100
        : status == 'NORMAL'
            ? 0.92 + rand.nextInt(7) / 100
            : 0.0;

    _controller.add({
      'camera_id': cameraId,
      'status': status,
      'confidence': confidence,
      'timestamp': DateTime.now().toIso8601String(),
      if (status == 'DANGER' && posture != null) 'posture': posture,
      'audio': status == 'DANGER' ? 'PLAYING' : 'IDLE',
    });
  }
}

/// ---------------------------------------------------------------------
/// Real implementation using the `mqtt_client` package (HiveMQ / HiveMQ
/// Cloud compatible). Activated from main.dart when MQTT_HOST is provided
/// via --dart-define; otherwise the app falls back to DummyMqttService.
///
///   flutter run --dart-define=MQTT_HOST=broker.hivemq.com \
///               --dart-define=MQTT_PORT=8883 \
///               --dart-define=MQTT_USERNAME=... \
///               --dart-define=MQTT_PASSWORD=...
///
/// NOTE: TLS is enabled automatically for port 8883 (HiveMQ Cloud and most
/// managed brokers). Pass MQTT_SECURE=false to override if needed.
/// ---------------------------------------------------------------------
class RealMqttService implements MqttService {
  RealMqttService({
    required this.host,
    this.port = 1883,
    String? username,
    String? password,
    bool? secure,
    this.clientIdPrefix = 'saferise_app',
    this.topicFilter = 'saferise/camera/+/#',
    this.keepAlivePeriodSeconds = 30,
    this.verbose = false,
  })  : username = (username == null || username.isEmpty) ? null : username,
        password = (password == null || password.isEmpty) ? null : password,
        secure = secure ?? (port == 8883);

  final String host;
  final int port;
  final String? username;
  final String? password;

  /// TLS on/off. Defaults to true when [port] is 8883 (HiveMQ Cloud, dan
  /// kebanyakan managed broker, mewajibkan TLS di port itu) dan false
  /// selainnya (mis. 1883 di broker lokal/test).
  final bool secure;

  final String clientIdPrefix;
  final String topicFilter;
  final int keepAlivePeriodSeconds;

  /// Bila true, mencetak log packet-level mqtt_client -- berguna untuk
  /// diagnosa "no CONNACK" / masalah handshake. Default off karena sangat
  /// berisik.
  final bool verbose;

  late final MqttServerClient _client;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  bool get isConnected =>
      _client.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Future<void> connect() async {
    // Client identifier harus unik per sesi agar broker tidak menendang
    // koneksi lama saat app restart / hot restart.
    final clientId = '${clientIdPrefix}_${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient(host, clientId)
      ..port = port
      ..keepAlivePeriod = keepAlivePeriodSeconds
      // 10s -- koneksi data seluler / TLS handshake bisa lambat.
      ..connectTimeoutPeriod = 10000
      ..autoReconnect = true
      ..logging(on: verbose)
      ..setProtocolV311()
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected
      ..onAutoReconnect = _onAutoReconnect
      ..onAutoReconnected = _onAutoReconnected;

    if (secure) {
      _client
        ..secure = true
        ..securityContext = SecurityContext.defaultContext;
    }

    _client.connectionMessage =
        MqttConnectMessage().withClientIdentifier(clientId).startClean();

    try {
      if (username != null && password != null) {
        await _client.connect(username, password);
      } else {
        await _client.connect();
      }
    } catch (e) {
      print('[MQTT] ❌ Connect failed: $e');
      _client.disconnect();
      rethrow;
    }

    if (_client.connectionStatus?.state != MqttConnectionState.connected) {
      final status = _client.connectionStatus;
      print('[MQTT] ❌ Connect failed: state=${status?.state} '
          'returnCode=${status?.returnCode}');
      _client.disconnect();
      throw Exception('MQTT connection failed (${status?.returnCode})');
    }

    _client.subscribe(topicFilter, MqttQos.atLeastOnce);

    _updatesSub = _client.updates!.listen((events) {
      for (final event in events) {
        final recMess = event.payload as MqttPublishMessage;
        final rawPayload =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        _handleIncoming(event.topic, rawPayload);
      }
    });
  }

  void _handleIncoming(String topic, String rawPayload) {
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map) return;
      final payload =
          decoded is Map<String, dynamic> ? decoded : decoded.cast<String, dynamic>();

      // Fallback: sebagian sub-topik (mis. .../connection) mempublikasikan
      // payload tanpa camera_id -- pulihkan dari topic-nya sendiri:
      // saferise/camera/{camera_id}/{subtopic}
      if (payload['camera_id'] == null) {
        final segments = topic.split('/');
        if (segments.length >= 3 &&
            segments[0] == 'saferise' &&
            segments[1] == 'camera') {
          payload['camera_id'] = segments[2];
        }
      }

      _controller.add(payload);
    } catch (e) {
      print('[MQTT] ⚠️ Invalid JSON payload on '
          '$topic: ${e.toString().split('\n').first}');
    }
  }

  void _onConnected() {
    print('[MQTT] ✅ Connected to $host:$port, subscribed to $topicFilter');
  }

  void _onDisconnected() {
    print('[MQTT] 🔌 Disconnected from $host:$port');
  }

  void _onAutoReconnect() {
    print('[MQTT] 🔄 Connection lost, auto-reconnecting to $host:$port...');
  }

  void _onAutoReconnected() {
    print('[MQTT] ✅ Auto reconnected, re-subscribing to $topicFilter');
    _client.subscribe(topicFilter, MqttQos.atLeastOnce);
  }

  @override
  void disconnect() {
    _updatesSub?.cancel();
    _updatesSub = null;
    _client.disconnect();
    _controller.close();
  }
}
