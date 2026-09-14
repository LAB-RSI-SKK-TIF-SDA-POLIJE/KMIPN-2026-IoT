"""
SafeRise - Raspberry Pi Publisher (VERSI RINGAN / LITE)
=========================================================

Ini VERSI TERPISAH dari pi_publisher_yolo.py -- bukan menggantikan,
dua-duanya tetap ada dan bisa dipilih sesuai kebutuhan:

  - pi_publisher_yolo.py       -> versi awal, model PyTorch biasa (.pt)
  - pi_publisher_yolo_lite.py  -> versi ini, 2 optimasi tambahan:

      1. MODEL FORMAT NCNN (bukan PyTorch)
         NCNN adalah format inference yang dioptimalkan khusus untuk CPU
         ARM (seperti di Raspberry Pi), tanpa perlu library PyTorch yang
         berat. Umumnya 3-5x lebih cepat dari model .pt biasa di Pi 3.

         WAJIB export dulu sebelum run script ini (tidak auto-download
         seperti file .pt biasa, karena NCNN adalah hasil konversi lokal):

             yolo export model=models/yolov8n-pose.pt format=ncnn imgsz=320

         Perintah di atas akan membuat folder baru:
             models/yolov8n-pose_ncnn_model/
         Itu yang dipakai MODEL_PATH di bawah secara default.

      2. MOTION-GATING (pre-filter gerakan sebelum YOLO dipanggil)
         Sebelum YOLO (berat) dipanggil, script ini cek dulu pakai
         perbandingan grayscale antar-frame (murah/cepat) apakah ada
         gerakan di sekitar danger zone. Kalau TIDAK ada gerakan sama
         sekali, YOLO di-skip untuk frame itu -- rooftop biasanya sepi,
         jadi ini menghemat komputasi signifikan.

         PENTING -- KETERBATASAN YANG WAJIB DIPAHAMI:
         Orang yang BERDIRI DIAM di danger zone (skenario paling
         berisiko -- seseorang sudah di tepi dan tidak bergerak) TIDAK
         akan terdeteksi motion-nya. Makanya ditambahkan DUA pengaman:
           a. FORCE_INFERENCE_INTERVAL -- walau tidak ada motion sama
              sekali, YOLO tetap dipaksa jalan setiap beberapa detik
              (default 5 detik) untuk cek ulang penuh.
           b. Begitu status pernah DANGER, motion-gating OTOMATIS
              dimatikan sementara (selalu full inference tiap siklus)
              sampai kembali NORMAL -- supaya tidak kehilangan jejak
              orang yang berhenti bergerak setelah terdeteksi berisiko.

         Kalau untuk KMIPN kamu ditanya juri "bagaimana kalau orangnya
         diam saja", jawabannya ada di poin (a) dan (b) di atas -- BUKAN
         celah yang diabaikan, tapi sudah diantisipasi.

Semua logika deteksi (danger zone, klasifikasi postur normal/crouching/
climbing, matriks keputusan risk, publish MQTT, audio DFPlayer) SAMA
PERSIS dengan pi_publisher_yolo.py -- yang beda cuma DUA hal di atas.
Kalau mau ubah logic zona/postur, ubah juga di kedua file supaya
konsisten (atau minta bantuan pindahkan logic itu ke modul bersama).

Instalasi tambahan (di atas requirements/requirements.txt):
    pip install ultralytics opencv-python paho-mqtt pyserial --break-system-packages
    # NCNN runtime ikut terpasang otomatis lewat ultralytics, tidak perlu
    # install terpisah.

Cara pakai:
    # 1) Export model dulu (sekali saja, hasilnya disimpan di models/):
    yolo export model=models/yolov8n-pose.pt format=ncnn imgsz=320

    # 2) Jalankan versi lite:
    python3 app/pi_publisher_yolo_lite.py
"""

import json
import os
import ssl
import sys
import time
from datetime import datetime, timezone

import cv2
import numpy as np
import paho.mqtt.client as mqtt
from ultralytics import YOLO

from dfplayer import get_audio_player
from detection_logic import validate_danger_zone

# ----------------------------------------------------------------------
# 1. Konfigurasi terpusat (config/settings.py)
#    Semua nilai diambil dari environment variable / file config/.env
#    (template: config/.env.example). Prioritas: env var > .env > default.
# ----------------------------------------------------------------------
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from config.settings import (  # noqa: E402
    AUDIO_ENABLED,
    AUDIO_REPLAY_INTERVAL,
    AUDIO_TRACK_HIGH,
    AUDIO_TRACK_MEDIUM,
    CAMERA_BACKEND,
    CAMERA_ID,
    CAMERA_SOURCE,
    CONF_THRESHOLD,
    CROUCH_KNEE_ANGLE_MAX,
    DANGER_CONSECUTIVE_FRAMES,
    DANGER_REPUBLISH_INTERVAL,
    DANGER_ZONE_POINTS as DANGER_ZONE_POINTS_RAW,
    DFPLAYER_PORT,
    DFPLAYER_VOLUME,
    FORCE_INFERENCE_INTERVAL,
    FRAME_HEIGHT,
    FRAME_WIDTH,
    HIGH_RISK_CONSECUTIVE_FRAMES,
    KEYPOINT_CONF_THRESHOLD,
    LEFT_ANKLE,
    LEFT_HIP,
    LEFT_KNEE,
    LEFT_SHOULDER,
    LEG_RAISED_RATIO,
    LOCATION,
    MODEL_NCNN_DIR,
    MODEL_PT_PATH,
    MQTT_HOST,
    MQTT_PASSWORD,
    MQTT_PORT,
    MQTT_USERNAME,
    MOTION_DIFF_THRESHOLD,
    MOTION_GATING_ENABLED,
    MOTION_PIXEL_THRESHOLD,
    NARROW_STANCE_RATIO,
    NORMAL_PUBLISH_INTERVAL,
    PROCESS_EVERY_N_FRAMES,
    RIGHT_ANKLE,
    RIGHT_HIP,
    RIGHT_KNEE,
    RIGHT_SHOULDER,
    SHOW_PREVIEW,
    TOPIC,
    YOLO_MODEL,
)

# ----------------------------------------------------------------------
# 2. Model pose & danger zone (konversi ke tipe yang dipakai loop utama)
# ----------------------------------------------------------------------
# Nama folder NCNN otomatis dibuat oleh perintah `yolo export ... format=ncnn`
MODEL_PATH = YOLO_MODEL or MODEL_NCNN_DIR
DANGER_ZONE_POINTS = np.array(DANGER_ZONE_POINTS_RAW, dtype=np.int32)

# ----------------------------------------------------------------------
# 3. Setup MQTT client
# ----------------------------------------------------------------------
client = mqtt.Client(client_id=f"saferise_pi_{CAMERA_ID}_lite", protocol=mqtt.MQTTv311)
client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
client.tls_set(cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLS_CLIENT)


def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print(f"[MQTT] connected to {MQTT_HOST}:{MQTT_PORT}")
    else:
        print(f"[MQTT] connect failed, rc={rc}")


def on_disconnect(client, userdata, rc):
    print(f"[MQTT] disconnected, rc={rc}")


client.on_connect = on_connect
client.on_disconnect = on_disconnect


def publish_detection(status: str, confidence: float, posture: str = "normal"):
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


# ----------------------------------------------------------------------
# 4. Helper: zona bahaya + analisis postur (SAMA PERSIS dengan versi non-lite)
# ----------------------------------------------------------------------
def point_in_danger_zone(point) -> bool:
    return cv2.pointPolygonTest(DANGER_ZONE_POINTS, point, False) >= 0


def _knee_angle(hip, knee, ankle):
    v1 = np.array(hip) - np.array(knee)
    v2 = np.array(ankle) - np.array(knee)
    cos_angle = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-6)
    cos_angle = np.clip(cos_angle, -1.0, 1.0)
    return float(np.degrees(np.arccos(cos_angle)))


MIN_VALID_KEYPOINTS = 4  # minimal 4 dari 8 keypoint inti (angle ke atas mungkin tidak lihat ankle)


def analyze_person_pose(keypoints_xy, keypoints_conf):
    def get(idx):
        if keypoints_conf[idx] >= KEYPOINT_CONF_THRESHOLD:
            return keypoints_xy[idx]
        return None

    left_ankle, right_ankle = get(LEFT_ANKLE), get(RIGHT_ANKLE)
    left_shoulder, right_shoulder = get(LEFT_SHOULDER), get(RIGHT_SHOULDER)
    left_hip, right_hip = get(LEFT_HIP), get(RIGHT_HIP)
    left_knee, right_knee = get(LEFT_KNEE), get(RIGHT_KNEE)

    # Foot point: ankle jika ada, fallback ke hip
    ankles = [p for p in (left_ankle, right_ankle) if p is not None]
    if ankles:
        foot_point = tuple(np.mean(ankles, axis=0))
    else:
        hips = [p for p in (left_hip, right_hip) if p is not None]
        foot_point = tuple(np.mean(hips, axis=0)) if hips else None

    # Validasi: pastikan cukup banyak keypoint inti yang terdeteksi.
    # Anjing/hewan menghasilkan keypoint palsu yang sedikit -> skip.
    # Angle ke atas: ankle mungkin tidak terlihat, cukup shoulder+hip+knee.
    core_keypoints = [left_shoulder, right_shoulder, left_hip, right_hip,
                      left_knee, right_knee, left_ankle, right_ankle]
    num_valid = sum(1 for p in core_keypoints if p is not None)
    if num_valid < MIN_VALID_KEYPOINTS:
        return foot_point, "normal"

    ankles = [p for p in (left_ankle, right_ankle) if p is not None]
    if ankles:
        foot_point = tuple(np.mean(ankles, axis=0))
    else:
        hips = [p for p in (left_hip, right_hip) if p is not None]
        foot_point = tuple(np.mean(hips, axis=0)) if hips else None

    crouching = False
    if all(point is not None for point in (left_hip, left_knee, left_ankle, right_hip, right_knee, right_ankle)):
        left_angle = _knee_angle(left_hip, left_knee, left_ankle)
        right_angle = _knee_angle(right_hip, right_knee, right_ankle)
        crouching = left_angle < CROUCH_KNEE_ANGLE_MAX and right_angle < CROUCH_KNEE_ANGLE_MAX

    if crouching:
        return foot_point, "crouching"

    narrow_stance = False
    if left_ankle is not None and right_ankle is not None and left_shoulder is not None and right_shoulder is not None:
        ankle_dist = abs(left_ankle[0] - right_ankle[0])
        shoulder_dist = abs(left_shoulder[0] - right_shoulder[0]) + 1e-6
        narrow_stance = (ankle_dist / shoulder_dist) < NARROW_STANCE_RATIO

    leg_raised = False
    if left_ankle is not None and right_ankle is not None and left_hip is not None and right_hip is not None:
        left_leg_len = abs(left_ankle[1] - left_hip[1])
        right_leg_len = abs(right_ankle[1] - right_hip[1])
        avg_leg_len = (left_leg_len + right_leg_len) / 2 + 1e-6
        ankle_height_diff = abs(left_ankle[1] - right_ankle[1])
        leg_raised = (ankle_height_diff / avg_leg_len) > LEG_RAISED_RATIO

    posture = "climbing" if (narrow_stance or leg_raised) else "normal"
    return foot_point, posture


# ----------------------------------------------------------------------
# 4a. Helper BARU: motion-gating
# ----------------------------------------------------------------------
# Bounding rect dari danger zone, dihitung sekali di awal -- dipakai untuk
# crop area yang dicek gerakannya (tidak perlu cek seluruh frame, cukup
# sekitar danger zone supaya lebih relevan & lebih cepat).
_zone_x, _zone_y, _zone_w, _zone_h = cv2.boundingRect(DANGER_ZONE_POINTS)


def detect_motion(gray_frame, prev_gray_frame):
    """
    Return True kalau ada perubahan piksel signifikan di sekitar danger
    zone dibanding frame grayscale sebelumnya. Operasi ini MURAH
    (cuma absdiff + threshold + hitung piksel), jauh lebih ringan
    dibanding inference YOLO -- makanya aman dijalankan tiap frame.
    """
    if prev_gray_frame is None:
        return True  # frame pertama, belum ada pembanding -> anggap ada "motion" supaya inference pertama tetap jalan

    roi_now = gray_frame[_zone_y:_zone_y + _zone_h, _zone_x:_zone_x + _zone_w]
    roi_prev = prev_gray_frame[_zone_y:_zone_y + _zone_h, _zone_x:_zone_x + _zone_w]
    if roi_now.size == 0 or roi_prev.size == 0:
        return True  # danger zone di luar frame / salah konfigurasi -> jangan sampai motion-gating diam-diam mematikan semua inference

    diff = cv2.absdiff(roi_now, roi_prev)
    changed_pixels = int(np.count_nonzero(diff > MOTION_DIFF_THRESHOLD))
    return changed_pixels > MOTION_PIXEL_THRESHOLD


class CameraCapture:
    def __init__(self, backend: str):
        self.backend = backend
        if backend == "picamera2":
            from picamera2 import Picamera2

            self.picam2 = Picamera2()
            config = self.picam2.create_video_configuration(
                main={"size": (FRAME_WIDTH, FRAME_HEIGHT), "format": "RGB888"}
            )
            self.picam2.configure(config)
            self.picam2.start()
            time.sleep(1)
        elif backend in ("opencv", "video"):
            source = int(CAMERA_SOURCE) if CAMERA_SOURCE.isdigit() else CAMERA_SOURCE
            self.cap = cv2.VideoCapture(source)
            if backend == "opencv":
                self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
                self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
            if not self.cap.isOpened():
                raise RuntimeError(
                    f"Tidak bisa membuka sumber kamera/video: {source}. "
                    "Cek CAMERA_SOURCE dan CAMERA_BACKEND."
                )
        else:
            raise ValueError(f"CAMERA_BACKEND tidak dikenal: {backend}")

    def read(self):
        if self.backend == "picamera2":
            frame = self.picam2.capture_array()
            frame = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
            return True, frame
        else:
            return self.cap.read()

    def release(self):
        if self.backend == "picamera2":
            self.picam2.stop()
        else:
            self.cap.release()


def get_camera_capture():
    print(f"[CAM] backend: {CAMERA_BACKEND}")
    return CameraCapture(CAMERA_BACKEND)


def load_model():
    if not os.path.exists(MODEL_PATH):
        raise FileNotFoundError(
            f"Model NCNN tidak ditemukan di: {MODEL_PATH}\n"
            "Model ini TIDAK auto-download seperti file .pt biasa -- kamu "
            "harus export dulu dari model .pt yang sudah ada:\n\n"
            f"    yolo export model={MODEL_PT_PATH} "
            "format=ncnn imgsz=320\n\n"
            "Setelah export selesai, folder yolov8n-pose_ncnn_model akan "
            "muncul di models/, baru jalankan script ini lagi."
        )
    print(f"[YOLO] loading model (NCNN): {MODEL_PATH}")
    return YOLO(MODEL_PATH)


# ----------------------------------------------------------------------
# 5. Main loop
# ----------------------------------------------------------------------
def main():
    validate_danger_zone(DANGER_ZONE_POINTS_RAW, FRAME_WIDTH, FRAME_HEIGHT)
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
    client.loop_start()

    model = load_model()
    audio_player = get_audio_player(AUDIO_ENABLED, DFPLAYER_PORT, DFPLAYER_VOLUME)
    cap = get_camera_capture()

    danger_streak = 0
    last_status = "NORMAL"
    last_publish_time = 0.0
    frame_counter = 0
    last_risk_level = "none"
    last_posture = "normal"
    last_best_confidence = 0.0
    last_audio_play_time = 0.0
    last_inference_time = 0.0
    prev_gray = None

    motion_skipped_count = 0  # cuma buat statistik/log, tidak mempengaruhi logic

    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                print("[CAM] gagal membaca frame, retry...")
                time.sleep(1)
                continue

            frame_counter += 1
            now = time.time()

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            gray = cv2.GaussianBlur(gray, (5, 5), 0)
            motion_detected = detect_motion(gray, prev_gray) if MOTION_GATING_ENABLED else True
            prev_gray = gray

            on_cadence = (frame_counter % PROCESS_EVERY_N_FRAMES == 0)
            force_due = (now - last_inference_time) >= FORCE_INFERENCE_INTERVAL
            # Begitu status TERAKHIR DANGER, motion-gating dimatikan sementara
            # (selalu full inference) -- lihat catatan keterbatasan di atas.
            bypass_gating = (last_status == "DANGER")

            run_inference_this_frame = on_cadence and (motion_detected or force_due or bypass_gating or not MOTION_GATING_ENABLED)

            if run_inference_this_frame:
                last_inference_time = now
                results = model.predict(frame, conf=CONF_THRESHOLD, imgsz=640, verbose=False)[0]

                frame_risk_level = "none"
                frame_posture = "normal"
                best_confidence = 0.0

                boxes = results.boxes
                keypoints = results.keypoints

                MAX_PEOPLE = 10
                processed = 0
                num_people = len(boxes) if boxes is not None else 0
                for i in range(num_people):
                    if processed >= MAX_PEOPLE:
                        break
                    if int(boxes.cls[i]) != 0:  # class 0 = person, skip non-person (e.g. dog)
                        continue
                    processed += 1
                    box_conf = float(boxes.conf[i])
                    x1, y1, x2, y2 = boxes.xyxy[i].tolist()

                    kp_xy = keypoints.xy[i].cpu().numpy() if keypoints is not None else None
                    kp_conf = keypoints.conf[i].cpu().numpy() if keypoints is not None else None

                    if kp_xy is not None and kp_conf is not None:
                        foot_point, posture = analyze_person_pose(kp_xy, kp_conf)
                    else:
                        foot_point, posture = ((x1 + x2) / 2, y2), "normal"

                    in_zone = foot_point is not None and point_in_danger_zone(foot_point)

                    if not in_zone:
                        person_risk = "none"
                    elif posture == "climbing":
                        person_risk = "high"
                    else:
                        person_risk = "medium"

                    if person_risk != "none":
                        best_confidence = max(best_confidence, box_conf)
                    if person_risk == "high":
                        frame_risk_level = "high"
                        frame_posture = posture
                    elif person_risk == "medium" and frame_risk_level != "high":
                        frame_risk_level = "medium"
                        frame_posture = posture

                    if SHOW_PREVIEW:
                        color = {"high": (0, 0, 255), "medium": (0, 165, 255), "none": (0, 255, 0)}[person_risk]
                        cv2.rectangle(frame, (int(x1), int(y1)), (int(x2), int(y2)), color, 2)
                        if foot_point is not None:
                            cv2.circle(frame, (int(foot_point[0]), int(foot_point[1])), 5, color, -1)
                        cv2.putText(frame, f"{person_risk} ({posture})", (int(x1), int(y1) - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)

                last_risk_level = frame_risk_level
                last_posture = frame_posture
                last_best_confidence = best_confidence
            else:
                motion_skipped_count += 1
                frame_risk_level = last_risk_level
                frame_posture = last_posture
                best_confidence = last_best_confidence

            required_frames = HIGH_RISK_CONSECUTIVE_FRAMES if frame_risk_level == "high" else DANGER_CONSECUTIVE_FRAMES

            if frame_risk_level != "none":
                danger_streak += 1
            else:
                danger_streak = 0

            current_status = "DANGER" if danger_streak >= required_frames else "NORMAL"
            current_posture = frame_posture

            should_publish = False
            if current_status == "DANGER":
                if last_status != "DANGER" or (now - last_publish_time) >= DANGER_REPUBLISH_INTERVAL:
                    should_publish = True
            else:
                if (now - last_publish_time) >= NORMAL_PUBLISH_INTERVAL:
                    should_publish = True

            if should_publish:
                publish_detection(
                    current_status,
                    best_confidence if current_status == "DANGER" else 1.0,
                    posture=current_posture,
                )
                last_publish_time = now

            if current_status == "DANGER":
                should_play_audio = (
                    last_status != "DANGER"
                    or (now - last_audio_play_time) >= AUDIO_REPLAY_INTERVAL
                )
                if should_play_audio:
                    track = AUDIO_TRACK_HIGH if frame_risk_level == "high" else AUDIO_TRACK_MEDIUM
                    audio_player.play_track(track)
                    last_audio_play_time = now
            else:
                if last_status == "DANGER":
                    audio_player.stop()

            last_status = current_status

            if SHOW_PREVIEW:
                cv2.rectangle(frame, (_zone_x, _zone_y), (_zone_x + _zone_w, _zone_y + _zone_h), (100, 100, 100), 1)
                cv2.polylines(frame, [DANGER_ZONE_POINTS], True, (0, 165, 255), 2)
                motion_text = "MOTION" if motion_detected else "still"
                cv2.putText(
                    frame,
                    f"STATUS: {current_status} ({frame_risk_level}) | {motion_text} | skipped={motion_skipped_count}",
                    (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.6,
                    (0, 0, 255) if current_status == "DANGER" else (0, 255, 0),
                    2,
                )
                cv2.imshow("SafeRise LITE - CAM05", frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break

    except KeyboardInterrupt:
        print("Stopping...")
    finally:
        cap.release()
        if SHOW_PREVIEW:
            cv2.destroyAllWindows()
        audio_player.close()
        client.loop_stop()
        client.disconnect()
        print(f"[INFO] Total frame yang di-skip motion-gating: {motion_skipped_count}")


if __name__ == "__main__":
    main()
