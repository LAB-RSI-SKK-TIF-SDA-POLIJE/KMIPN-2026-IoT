"""SafeRise laptop inference for a Raspberry Pi Camera 3 H.264 stream.

Example (run on laptop, Pi stream):
    set STREAM_URL=tcp://192.168.1.50:8888
    python app/laptop_inference.py

Example (run on laptop, test with video file):
    set STREAM_URL=D:\videos\test.mp4
    python app/laptop_inference.py

The Pi must run app/pi_camera_alarm_agent.py first. This laptop process owns
YOLO inference and sends local-speaker commands to the Pi over MQTT.
Video file mode auto-resizes to Pi Camera resolution (320x240) and loops.
"""

from __future__ import annotations

import json
import os
import socket
import ssl
import sys
import time
from datetime import datetime, timezone

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
APP_DIR = os.path.dirname(__file__)
for path in (PROJECT_ROOT, APP_DIR):
    if path not in sys.path:
        sys.path.insert(0, path)

import cv2
import numpy as np
import paho.mqtt.client as mqtt
from ultralytics import YOLO

from mjpeg_server import MjpegServer  # noqa: E402

from config.settings import (  # noqa: E402
    ALARM_COMMAND_TOPIC,
    ALARM_MQTT_HOST,
    ALARM_MQTT_PASSWORD,
    ALARM_MQTT_PORT,
    ALARM_MQTT_TLS_ENABLED,
    ALARM_MQTT_USERNAME,
    ALARM_MQTT_USES_LOCAL_BROKER,
    AUDIO_REPLAY_INTERVAL,
    AUDIO_TRACK_HIGH,
    AUDIO_TRACK_MEDIUM,
    CAMERA_ID,
    CONF_THRESHOLD,
    CROUCH_KNEE_ANGLE_MAX,
    DANGER_CONSECUTIVE_FRAMES,
    DANGER_REPUBLISH_INTERVAL,
    DANGER_ZONE_POINTS,
    FRAME_HEIGHT,
    FRAME_WIDTH,
    HIGH_RISK_CONSECUTIVE_FRAMES,
    KEYPOINT_CONF_THRESHOLD,
    LEG_RAISED_RATIO,
    LOCATION,
    MJPEG_ENABLED,
    MJPEG_FPS,
    MJPEG_PORT,
    MJPEG_QUALITY,
    MODEL_PT_PATH,
    MQTT_HOST,
    MQTT_PASSWORD,
    MQTT_PORT,
    MQTT_TLS_ENABLED,
    MQTT_USERNAME,
    NARROW_STANCE_RATIO,
    NORMAL_PUBLISH_INTERVAL,
    PROCESS_EVERY_N_FRAMES,
    SHOW_PREVIEW,
    STREAM_URL,
    TOPIC,
    YOLO_MODEL,
)
from detection_logic import analyze_person_pose, validate_danger_zone  # noqa: E402


ZONE = np.array(DANGER_ZONE_POINTS, dtype=np.int32)


def publish_detection(client, status: str, confidence: float, posture: str) -> None:
    payload = {
        "camera_id": CAMERA_ID,
        "status": status,
        "confidence": round(float(confidence), 2),
        "location": LOCATION,
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "audio": "PLAYING" if status == "DANGER" else "IDLE",
        "posture": posture,
    }
    client.publish(TOPIC, json.dumps(payload), qos=1)
    print(f"[PUBLISH] {TOPIC} -> {payload}")


def publish_alarm_command(client, action: str, risk: str = "medium") -> None:
    track = AUDIO_TRACK_HIGH if risk == "high" else AUDIO_TRACK_MEDIUM
    payload = {
        "camera_id": CAMERA_ID,
        "action": action,
        "risk": risk,
        "track": track,
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    client.publish(ALARM_COMMAND_TOPIC, json.dumps(payload), qos=1)
    print(f"[ALARM COMMAND] {ALARM_COMMAND_TOPIC} -> {payload}")


def get_lan_ip() -> str:
    """Ambil IP LAN laptop ini (bukan 127.0.0.1) tanpa perlu library
    tambahan -- trik umum: buka socket UDP ke alamat luar TANPA benar-benar
    mengirim data, cukup untuk membuat OS memilih interface LAN yang aktif."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


def publish_connection_info(client, ip: str, mjpeg_port: int) -> None:
    """Broadcast IP+port MJPEG laptop ke app Flutter (dibaca lewat
    MqttService -> AppState.piIpAddress) supaya live preview di app tahu
    kemana harus connect. Nama field 'ip' & topic '.../connection' mengikuti
    kontrak yang sudah dipakai app (lib/services/app_state.dart)."""
    topic = f"saferise/camera/{CAMERA_ID}/connection"
    payload = {"camera_id": CAMERA_ID, "ip": ip, "mjpeg_port": mjpeg_port}
    client.publish(topic, json.dumps(payload), qos=1, retain=True)
    print(f"[MJPEG] live stream utk app Flutter: http://{ip}:{mjpeg_port}/stream")
    print(f"[PUBLISH] {topic} -> {payload}")


def assess_frame(results):
    risk, posture, best_confidence = "none", "normal", 0.0
    detections = []  # untuk preview: satu entri per orang -> box + risk masing-masing
    boxes, keypoints = results.boxes, results.keypoints
    MAX_PEOPLE = 20
    processed = 0
    for index in range(len(boxes) if boxes is not None else 0):
        if processed >= MAX_PEOPLE:
            break
        if int(boxes.cls[index]) != 0:  # class 0 = person, skip non-person (e.g. dog)
            continue
        processed += 1
        confidence = float(boxes.conf[index])
        x1, y1, x2, y2 = boxes.xyxy[index].tolist()
        if keypoints is None:
            foot_point, person_posture = ((x1 + x2) / 2, y2), "normal"
        else:
            foot_point, person_posture = analyze_person_pose(
                keypoints.xy[index].cpu().numpy(),
                keypoints.conf[index].cpu().numpy(),
                keypoint_conf_threshold=KEYPOINT_CONF_THRESHOLD,
                narrow_stance_ratio=NARROW_STANCE_RATIO,
                leg_raised_ratio=LEG_RAISED_RATIO,
                crouch_knee_angle_max=CROUCH_KNEE_ANGLE_MAX,
            )
        in_zone = foot_point is not None and cv2.pointPolygonTest(ZONE, foot_point, False) >= 0
        if not in_zone:
            person_risk = "none"
        elif person_posture == "climbing":
            person_risk = "high"
        elif person_posture == "crouching":
            person_risk = "medium"
        else:
            person_risk = "none"
        detections.append({
            "box": (int(x1), int(y1), int(x2), int(y2)),
            "risk": person_risk,
            "posture": person_posture,
            "confidence": confidence,
        })
        if person_risk != "none":
            best_confidence = max(best_confidence, confidence)
        if person_risk == "high" or (person_risk == "medium" and risk != "high"):
            risk, posture = person_risk, person_posture
    return risk, posture, best_confidence, detections


# Warna kotak per level risiko orang (BGR, sesuai konvensi OpenCV)
_BOX_COLOR = {"none": (0, 200, 0), "medium": (0, 165, 255), "high": (0, 0, 255)}


def draw_detections(frame, detections):
    """Gambar bounding box + label per orang yang terdeteksi di frame preview."""
    for detection in detections:
        x1, y1, x2, y2 = detection["box"]
        color = _BOX_COLOR.get(detection["risk"], (0, 200, 0))
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
        label = f"{detection['posture']} {detection['confidence']:.2f}"
        cv2.putText(frame, label, (x1, max(0, y1 - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)


def main() -> None:
    if not STREAM_URL:
        raise ValueError("STREAM_URL belum diset, contoh: tcp://192.168.1.50:8888")
    validate_danger_zone(DANGER_ZONE_POINTS, FRAME_WIDTH, FRAME_HEIGHT)

    is_video_file = os.path.isfile(STREAM_URL)

    model_path = YOLO_MODEL or MODEL_PT_PATH
    print(f"[YOLO] loading model on laptop: {model_path}")
    model = YOLO(model_path)
    capture = cv2.VideoCapture(STREAM_URL)
    if not capture.isOpened():
        raise RuntimeError(
            f"Tidak dapat membuka stream: {STREAM_URL}. "
            + ("Pastikan file video ada." if is_video_file
               else "Pastikan Pi agent berjalan, IP/port benar, dan OpenCV laptop dibangun dengan FFmpeg.")
        )

    if is_video_file:
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
        print(f"[CAMERA] Video file mode! Resize ke Pi Camera resolusi: {FRAME_WIDTH}x{FRAME_HEIGHT}")
    else:
        print(f"[CAMERA] H.264 TCP stream: {STREAM_URL}")

    hive_client = mqtt.Client(client_id=f"saferise_laptop_{CAMERA_ID}", protocol=mqtt.MQTTv311)
    hive_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    if MQTT_TLS_ENABLED:
        hive_client.tls_set(cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLS_CLIENT)
    hive_client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
    hive_client.loop_start()
    print(f"[MQTT] status detection -> HiveMQ Cloud {MQTT_HOST}:{MQTT_PORT} (untuk app Flutter)")

    if ALARM_MQTT_USES_LOCAL_BROKER:
        alarm_client = mqtt.Client(client_id=f"saferise_laptop_alarm_{CAMERA_ID}", protocol=mqtt.MQTTv311)
        if ALARM_MQTT_USERNAME:
            alarm_client.username_pw_set(ALARM_MQTT_USERNAME, ALARM_MQTT_PASSWORD)
        if ALARM_MQTT_TLS_ENABLED:
            alarm_client.tls_set(cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLS_CLIENT)
        alarm_client.connect(ALARM_MQTT_HOST, ALARM_MQTT_PORT, keepalive=30)
        alarm_client.loop_start()
        print(f"[MQTT] alarm command -> Mosquitto LOKAL {ALARM_MQTT_HOST}:{ALARM_MQTT_PORT} "
              "(independen dari internet)")
    else:
        # LOCAL_MQTT_HOST kosong -> tidak perlu koneksi kedua, pakai
        # broker HiveMQ yang sama untuk alarm command juga.
        alarm_client = hive_client
        print("[MQTT] alarm command -> HiveMQ Cloud juga (LOCAL_MQTT_HOST kosong, single-broker fallback)")

    mjpeg_server = None
    if MJPEG_ENABLED:
        # Server MJPEG jalan di LAPTOP (bukan Pi) supaya tidak menambah
        # beban apapun ke Raspberry Pi 3 -- laptop sudah punya frame yang
        # sudah didecode + dianotasi (danger zone + bounding box) untuk
        # YOLO, jadi tinggal broadcast ulang, nyaris tanpa biaya tambahan.
        mjpeg_server = MjpegServer(port=MJPEG_PORT, jpeg_quality=MJPEG_QUALITY, stream_fps=MJPEG_FPS)
        mjpeg_server.start()
        publish_connection_info(hive_client, get_lan_ip(), MJPEG_PORT)

    frame_counter = danger_streak = 0
    last_risk, last_posture, last_confidence = "none", "normal", 0.0
    last_detections = []
    last_status, last_publish, last_audio = "NORMAL", 0.0, 0.0
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                if is_video_file:
                    capture.set(cv2.CAP_PROP_POS_FRAMES, 0)
                    continue
                print("[WARN] H.264 stream terputus, mencoba reconnect...")
                capture.release()
                time.sleep(2)
                capture = cv2.VideoCapture(STREAM_URL)
                if not capture.isOpened():
                    print("[ERROR] Reconnect gagal. Keluar.")
                    break
                continue

            if is_video_file:
                frame = cv2.resize(frame, (FRAME_WIDTH, FRAME_HEIGHT))

            frame_counter += 1
            if frame_counter % PROCESS_EVERY_N_FRAMES == 0:
                last_risk, last_posture, last_confidence, last_detections = assess_frame(
                    model.predict(frame, conf=CONF_THRESHOLD, imgsz=640, verbose=False)[0]
                )
            required = HIGH_RISK_CONSECUTIVE_FRAMES if last_risk == "high" else DANGER_CONSECUTIVE_FRAMES
            danger_streak = danger_streak + 1 if last_risk != "none" else 0
            status = "DANGER" if danger_streak >= required else "NORMAL"
            now = time.time()
            should_publish = (status == "DANGER" and (last_status != "DANGER" or now - last_publish >= DANGER_REPUBLISH_INTERVAL)) or (status == "NORMAL" and now - last_publish >= NORMAL_PUBLISH_INTERVAL)
            if should_publish:
                publish_detection(hive_client, status, last_confidence if status == "DANGER" else 1.0, last_posture)
                last_publish = now
            if status == "DANGER" and (last_status != "DANGER" or now - last_audio >= AUDIO_REPLAY_INTERVAL):
                publish_alarm_command(alarm_client, "PLAY", last_risk)
                last_audio = now
            elif status == "NORMAL" and last_status == "DANGER":
                publish_alarm_command(alarm_client, "STOP")
            last_status = status
            if SHOW_PREVIEW or mjpeg_server is not None:
                cv2.polylines(frame, [ZONE], True, (0, 165, 255), 2)
                draw_detections(frame, last_detections)
                cv2.putText(frame, f"{status} ({last_risk})", (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255) if status == "DANGER" else (0, 255, 0), 2)
                timestamp_text = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
                (tw, th), _ = cv2.getTextSize(timestamp_text, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
                cv2.putText(frame, timestamp_text, (frame.shape[1] - tw - 10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 2)
            if mjpeg_server is not None:
                mjpeg_server.update_frame(frame)
            if SHOW_PREVIEW:
                cv2.imshow(f"SafeRise laptop inference - {CAMERA_ID}", frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
    finally:
        if mjpeg_server is not None:
            mjpeg_server.stop()
        if last_status == "DANGER":
            publish_alarm_command(alarm_client, "STOP")
        capture.release()
        cv2.destroyAllWindows()
        hive_client.loop_stop()
        hive_client.disconnect()
        if alarm_client is not hive_client:
            alarm_client.loop_stop()
            alarm_client.disconnect()


if __name__ == "__main__":
    main()