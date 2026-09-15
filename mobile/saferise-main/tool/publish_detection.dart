// Script untuk menguji payload /detection versi terbaru ke broker MQTT.
//
// Mempublish 4 payload (NORMAL / DANGER+climbing / DANGER+crouching /
// OFFLINE) ke topik saferise/camera/CAM05/detection dengan QoS 1 dan
// flag RETAIN=true, sehingga pesan tersimpan di broker dan app langsung
// menerimanya begitu subscribe.
//
// Pakai:
//   dart run tool/publish_detection.dart --host broker.hivemq.com \
//         [--port 1883] [--camera CAM05] [--sequence 0..3|all]
//
// Contoh publish satu event saja:
//   dart run tool/publish_detection.dart --host 192.168.1.10 --sequence 1

import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

final payloads = <Map<String, dynamic>>[
  {
    'status': 'NORMAL',
    'confidence': 0.95,
    'location': 'Rooftop Gedung A',
    'posture': 'normal',
  },
  {
    'status': 'DANGER',
    'confidence': 0.93,
    'location': 'Rooftop Gedung A',
    'posture': 'climbing',
  },
  {
    'status': 'DANGER',
    'confidence': 0.87,
    'location': 'Rooftop Gedung A',
    'posture': 'crouching',
  },
  {
    'status': 'OFFLINE',
    'confidence': 0,
    'location': 'Rooftop Gedung A',
  },
];

Future<void> main(List<String> args) async {
  String host = '';
  int port = 1883;
  String camera = 'CAM05';
  String sequence = 'all';

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--host':
        host = args[++i];
      case '--port':
        port = int.parse(args[++i]);
      case '--camera':
        camera = args[++i];
      case '--sequence':
        sequence = args[++i];
    }
  }
  if (host.isEmpty) {
    stderr.writeln('Wajib: --host <broker>');
    exit(2);
  }

  final client = MqttServerClient(host, 'saferise_test_publisher')
    ..port = port
    ..keepAlivePeriod = 20
    ..logging(on: false)
    ..setProtocolV311();

  print('Connecting to $host:$port ...');
  await client.connect();
  if (client.connectionStatus?.state != MqttConnectionState.connected) {
    stderr.writeln('Gagal connect: ${client.connectionStatus?.returnCode}');
    exit(1);
  }

  final topic = 'saferise/camera/$camera/detection';
  final indexes = sequence == 'all'
      ? List<int>.generate(payloads.length, (i) => i)
      : [int.parse(sequence)];

  for (final i in indexes) {
    final body = <String, dynamic>{
      'camera_id': camera,
      ...payloads[i],
      // Timestamp live saat publish supaya tidak dianggap basi app.
      'timestamp': DateTime.now().toIso8601String().split('.').first,
    };
    final json = body.entries
        .map((e) => '"${e.key}": ${e.value is String ? '"${e.value}"' : e.value}')
        .join(', ');
    final builder = MqttClientPayloadBuilder()..addString('{$json}');

    // RETAIN=true: broker menyimpan pesan terakhir per topik dan
    // mengirimkannya ulang ke subscriber baru (app yang baru dibuka).
    client.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: true,
    );
    print('[#$i] -> $topic (retain): {$json}');
    await Future.delayed(const Duration(seconds: 1));
  }

  client.disconnect();
  print('Selesai.');
}
