"""
SafeRise - Raspberry Pi Publisher (YOLO Edition)
=================================================

Mengganti fungsi dummy run_ai_detection() pada pi_publisher.py dengan
deteksi orang (person) nyata menggunakan YOLOv8, dikombinasikan dengan
"danger zone" (area rawan di rooftop, misalnya area dekat pagar/tepi
atap) yang digambar sebagai polygon di atas frame kamera.

Logika status:
- NORMAL  : tidak ada orang dengan risk MEDIUM/HIGH di dalam danger zone.
- DANGER  : ada orang berisiko (posisi kaki di danger zone) yang bertahan
            beberapa frame berturut-turut (anti flicker):
              - risk MEDIUM (di zona saja)              -> butuh DANGER_CONSECUTIVE_FRAMES frame
              - risk HIGH   (di zona + narrow stance)    -> butuh HIGH_RISK_CONSECUTIVE_FRAMES frame (lebih cepat trigger)

Kenapa perlu "consecutive frames" & "cooldown"?
- Kenapa perlu debounce: satu frame yang salah deteksi (false positive)
  tidak langsung memicu alarm sirine di HP. Butuh beberapa frame beruntun
  yang konsisten dulu.
- Kenapa perlu cooldown: begitu status DANGER terkirim, script tidak akan
  spam publish ke broker setiap 1-2 detik selama orang masih di zona;
  publish ulang hanya tiap DANGER_REPUBLISH_INTERVAL detik supaya HP
  tidak dibanjiri notifikasi tapi tetap "hidup" alarmnya.

Catatan khusus Raspberry Pi 3:
    Pi 3 (quad-core Cortex-A53 @ 1.2GHz, tanpa GPU/NPU untuk inference)
    JAUH lebih lemah dari Pi 4/5. YOLOv8n dengan backend PyTorch biasa
    bisa sangat lambat (kadang < 1 FPS). Untuk mengejar performa yang
    lebih layak:
      1. Gunakan resolusi input sekecil mungkin (sudah di-set 320x320
         di bawah, bukan 640x480).
      2. Gunakan PROCESS_EVERY_N_FRAMES supaya tidak setiap frame
         di-inference (untuk kasus rooftop, orang tidak bergerak
         secepat itu, jadi ini aman).
      3. Kalau masih terlalu berat, export model ke format NCNN yang
         jauh lebih cepat di ARM tanpa GPU:
             yolo export model=yolov8n.pt format=ncnn imgsz=320
         lalu ganti MODEL_PATH ke folder hasil export
         (yolov8n_ncnn_model). NCNN dioptimalkan khusus untuk CPU ARM
         seperti di Pi, jadi biasanya 3-5x lebih cepat dari PyTorch.
      4. Pastikan pakai Raspberry Pi OS 64-bit — versi 32-bit membuat
         PyTorch/ultralytics jauh lebih lambat atau bahkan tidak semua
         versi tersedia.
      5. Jangan jalankan SHOW_PREVIEW=1 saat produksi di Pi 3 (headless)
         — rendering preview ikut membebani CPU yang sama dengan
         inference.

Catatan tentang model pose:
    Model yang dipakai sekarang adalah yolov8n-pose.pt (bukan yolov8n.pt
    biasa) — modelnya sekaligus mendeteksi orang DAN 17 titik keypoint
    tubuh (bahu, pinggul, lutut, pergelangan kaki, dst mengikuti format
    COCO keypoints).

    Sistem menggabungkan DUA sinyal independen untuk memutuskan status:
      1. ZONA -- apakah posisi kaki orang ada di dalam "danger zone"
         (area rawan seperti tepi/pagar rooftop) atau di "safe zone"
         (area tengah/aman).
      2. POSTUR -- diklasifikasikan jadi salah satu dari tiga label:
           a. "climbing": narrow stance (kedua kaki rapat dibanding
              lebar bahu, indikasi berdiri di permukaan sempit) ATAU
              leg raised (salah satu ankle jauh lebih tinggi dari
              ankle lainnya relatif panjang kaki, indikasi satu kaki
              terangkat/hendak memanjat).
           b. "crouching": KEDUA lutut menekuk tajam (sudut hip-knee-
              ankle < CROUCH_KNEE_ANGLE_MAX) -- dicek LEBIH DULU
              sebelum climbing, supaya orang jongkok/menunduk (mis.
              bersih-bersih dekat pagar) tidak salah kepicu leg_raised
              dan dianggap climbing.
           c. "normal": selain dua kondisi di atas.

    Matriks keputusan (INI PENTING, bukan cuma "ada climbing = bahaya"):
      - safe zone  + apa saja   -> NORMAL   (aman -- postur apapun di
                                    tengah rooftop bukan indikasi bahaya)
      - danger zone+ normal     -> risk MEDIUM (waspada, mungkin cuma lewat)
      - danger zone+ crouching  -> risk MEDIUM (jongkok dekat tepi tetap
                                    diwaspadai, tapi tidak dinaikkan ke
                                    HIGH -- belum tentu indikasi memanjat)
      - danger zone+ climbing   -> risk HIGH   (kombinasi paling berisiko,
                                    memicu status DANGER lebih cepat)

    PENTING: heuristik "climbing_pose" ini adalah pendekatan sederhana
    berbasis geometri, BUKAN model yang dilatih khusus mengenali "niat
    bunuh diri". Ini murni membantu menaikkan level kepercayaan (risk
    level) ketika kombinasi zona + postur terpenuhi bersamaan. Untuk
    KMIPN, jelaskan ke juri bahwa sistem ini bersifat early-warning
    (membantu memicu perhatian manusia lebih cepat), bukan pengganti
    penilaian/intervensi manusia.

Instalasi (di Raspberry Pi, untuk Camera Module 3 via picamera2):
    sudo apt update
    sudo apt install -y python3-picamera2 --no-install-recommends
    pip install ultralytics opencv-python paho-mqtt pyserial --break-system-packages
    # Kalau pakai webcam USB biasa (bukan Camera Module 3), set
    # CAMERA_BACKEND=opencv dan tidak perlu python3-picamera2.

Cara pakai:
    python3 pi_publisher_yolo.py

Cara kalibrasi danger zone:
    Jalankan dengan SHOW_PREVIEW=True dulu di monitor yang tersambung ke
    Pi (atau via VNC), lalu klik kanan/kiri pada window untuk melihat
    koordinat piksel, sesuaikan DANGER_ZONE_POINTS di bawah.
"""

import json
import os
import ssl
import sys
import time
from collections import deque
from datetime import datetime, timezone

import cv2
import numpy as np
import paho.mqtt.client as mqtt
from ultralytics import YOLO

from dfplayer import get_audio_player
from detection_logic import validate_danger_zone
from mjpeg_server import MjpegServer

# ----------------------------------------------------------------------
# 1. Konfigurasi terpusat (config/settings.py)
#    Semua nilai diambil dari environment variable / file config/.env
#    (template: config/.env.example) -- supaya kredensial & tuning tidak
#    ter-hardcode di kode. Prioritas: env var > config/.env > default.
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
    MJPEG_ENABLED,
    MJPEG_FPS,
    MJPEG_PORT,
    MJPEG_QUALITY,
    MODEL_PT_PATH,
    MQTT_HOST,
    MQTT_PASSWORD,
    MQTT_PORT,
    MQTT_USERNAME,
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
MODEL_PATH = YOLO_MODEL or MODEL_PT_PATH  # model pose (bukan deteksi biasa)
DANGER_ZONE_POINTS = np.array(DANGER_ZONE_POINTS_RAW, dtype=np.int32)

# ----------------------------------------------------------------------
# 3. Setup MQTT client (sama seperti pi_publisher.py)
# ----------------------------------------------------------------------
client = mqtt.Client(client_id=f"saferise_pi_{CAMERA_ID}", protocol=mqtt.MQTTv311)
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
        "posture": posture,  # "normal" | "crouching" (jongkok/menunduk) | "climbing" (indikasi memanjat)
    }
    client.publish(TOPIC, json.dumps(payload), qos=1)
    print(f"[PUBLISH] {TOPIC} -> {payload}")


# ----------------------------------------------------------------------
# 4. Helper: zona bahaya + analisis postur dari keypoint pose
# ----------------------------------------------------------------------
def point_in_danger_zone(point) -> bool:
    result = cv2.pointPolygonTest(DANGER_ZONE_POINTS, point, False)
    return result >= 0


def _knee_angle(hip, knee, ankle):
    """Sudut di titik lutut (hip-knee-ankle). ~180 derajat = kaki lurus
    (berdiri normal). Semakin kecil = lutut semakin menekuk."""
    v1 = np.array(hip) - np.array(knee)
    v2 = np.array(ankle) - np.array(knee)
    cos_angle = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-6)
    cos_angle = np.clip(cos_angle, -1.0, 1.0)
    return float(np.degrees(np.arccos(cos_angle)))


MIN_VALID_KEYPOINTS = 4  # minimal 4 dari 8 keypoint inti (angle ke atas mungkin tidak lihat ankle)


def analyze_person_pose(keypoints_xy, keypoints_conf):
    """
    keypoints_xy: array (17, 2) posisi (x, y) tiap titik keypoint COCO.
    keypoints_conf: array (17,) confidence tiap titik.

    Return: (foot_point, posture)
    - foot_point: titik acuan posisi kaki (dipakai untuk cek danger zone).
      Kalau kedua ankle tidak cukup yakin terdeteksi (mis. tertutup
      objek), fallback ke titik pinggul.
    - posture: salah satu dari "normal" | "climbing" | "crouching"
        - "crouching": KEDUA lutut menekuk tajam (sudut hip-knee-ankle
          < CROUCH_KNEE_ANGLE_MAX) -- indikasi jongkok/menunduk, dicek
          LEBIH DULU supaya tidak salah dianggap climbing.
        - "climbing": (dan bukan crouching) narrow stance ATAU leg
          raised terpenuhi -- indikasi berdiri di permukaan sempit /
          satu kaki terangkat seperti hendak memanjat.
        - "normal": selain dua kondisi di atas, termasuk kalau data
          keypoint tidak cukup untuk dihitung.
    """

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

    # --- crouching: dicek lebih dulu, prioritas di atas climbing ---
    crouching = False
    if all(point is not None for point in (left_hip, left_knee, left_ankle, right_hip, right_knee, right_ankle)):
        left_angle = _knee_angle(left_hip, left_knee, left_ankle)
        right_angle = _knee_angle(right_hip, right_knee, right_ankle)
        crouching = left_angle < CROUCH_KNEE_ANGLE_MAX and right_angle < CROUCH_KNEE_ANGLE_MAX

    if crouching:
        return foot_point, "crouching"

    # --- narrow stance ---
    narrow_stance = False
    if left_ankle is not None and right_ankle is not None and left_shoulder is not None and right_shoulder is not None:
        ankle_dist = abs(left_ankle[0] - right_ankle[0])
        shoulder_dist = abs(left_shoulder[0] - right_shoulder[0]) + 1e-6
        narrow_stance = (ankle_dist / shoulder_dist) < NARROW_STANCE_RATIO

    # --- leg raised ---
    leg_raised = False
    if left_ankle is not None and right_ankle is not None and left_hip is not None and right_hip is not None:
        left_leg_len = abs(left_ankle[1] - left_hip[1])
        right_leg_len = abs(right_ankle[1] - right_hip[1])
        avg_leg_len = (left_leg_len + right_leg_len) / 2 + 1e-6
        ankle_height_diff = abs(left_ankle[1] - right_ankle[1])
        leg_raised = (ankle_height_diff / avg_leg_len) > LEG_RAISED_RATIO

    posture = "climbing" if (narrow_stance or leg_raised) else "normal"
    return foot_point, posture


class CameraCapture:
    """
    Wrapper supaya main loop tidak perlu tahu apakah kamera itu
    Camera Module 3 (picamera2/CSI) atau webcam USB (opencv). Panggil
    .read() sama seperti cv2.VideoCapture.
    """

    def __init__(self, backend: str):
        self.backend = backend
        if backend == "picamera2":
            from picamera2 import Picamera2  # import di sini biar opencv-only setup tidak wajib install ini

            self.picam2 = Picamera2()
            config = self.picam2.create_video_configuration(
                main={"size": (FRAME_WIDTH, FRAME_HEIGHT), "format": "RGB888"}
            )
            self.picam2.configure(config)
            self.picam2.start()
            time.sleep(1)  # beri waktu sensor warm-up
        elif backend in ("opencv", "video"):
            # cv2.VideoCapture menerima index kamera (int) atau path file
            # video (str) dengan cara yang sama.
            source = int(CAMERA_SOURCE) if CAMERA_SOURCE.isdigit() else CAMERA_SOURCE
            self.cap = cv2.VideoCapture(source)
            if backend == "opencv":
                self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
                self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
            if not self.cap.isOpened():
                raise RuntimeError(
                    f"Tidak bisa membuka sumber kamera/video: {source}. "
                    "Cek CAMERA_SOURCE (index webcam atau path file video) "
                    "dan CAMERA_BACKEND."
                )
        else:
            raise ValueError(f"CAMERA_BACKEND tidak dikenal: {backend}")

    def read(self):
        if self.backend == "picamera2":
            frame = self.picam2.capture_array()  # RGB888
            # picamera2 mengembalikan RGB, sedangkan YOLO/opencv di script
            # ini bekerja dalam ruang warna BGR -> konversi dulu
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


# ----------------------------------------------------------------------
# 5. Main loop: capture -> YOLO inference -> cek danger zone -> publish
# ----------------------------------------------------------------------
def main():
    validate_danger_zone(DANGER_ZONE_POINTS_RAW, FRAME_WIDTH, FRAME_HEIGHT)
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
    client.loop_start()

    print(f"[YOLO] loading model: {MODEL_PATH}")
    model = YOLO(MODEL_PATH)

    audio_player = get_audio_player(AUDIO_ENABLED, DFPLAYER_PORT, DFPLAYER_VOLUME)

    mjpeg_server = None
    if MJPEG_ENABLED:
        mjpeg_server = MjpegServer(port=MJPEG_PORT, jpeg_quality=MJPEG_QUALITY, stream_fps=MJPEG_FPS)
        mjpeg_server.start()
        print(f"[MJPEG] live stream: http://<ip-device-ini>:{MJPEG_PORT}/stream")
        print(f"[MJPEG] snapshot:    http://<ip-device-ini>:{MJPEG_PORT}/snapshot")

    cap = get_camera_capture()

    danger_streak = 0
    last_status = "NORMAL"
    last_publish_time = 0.0
    frame_counter = 0
    last_risk_level = "none"  # "none" | "medium" (di zona) | "high" (di zona + narrow stance)
    last_posture = "normal"  # "normal" | "crouching" | "climbing"
    last_best_confidence = 0.0
    last_audio_play_time = 0.0

    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                print("[CAM] gagal membaca frame, retry...")
                time.sleep(1)
                continue

            frame_counter += 1
            run_inference_this_frame = (frame_counter % PROCESS_EVERY_N_FRAMES == 0)

            if run_inference_this_frame:
                results = model.predict(frame, conf=CONF_THRESHOLD, imgsz=640, verbose=False)[0]

                frame_risk_level = "none"  # risk tertinggi di frame ini, dari semua orang terdeteksi
                frame_posture = "normal"  # postur orang dengan risk tertinggi di frame ini
                best_confidence = 0.0

                boxes = results.boxes
                keypoints = results.keypoints  # None kalau tidak ada orang terdeteksi

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
                        # fallback kalau keypoint tidak tersedia: pakai tengah-bawah bounding box
                        foot_point, posture = ((x1 + x2) / 2, y2), "normal"

                    in_zone = foot_point is not None and point_in_danger_zone(foot_point)

                    # Matriks keputusan:
                    #   safe zone  + apa saja   -> none   (aman)
                    #   danger zone+ normal     -> medium (waspada, mungkin cuma lewat)
                    #   danger zone+ crouching  -> medium (jongkok/menunduk -- belum tentu mau memanjat,
                    #                              disamakan dgn normal, bukan dinaikkan ke high)
                    #   danger zone+ climbing   -> high   (kombinasi paling berisiko)
                    if not in_zone:
                        person_risk = "none"
                    elif posture == "climbing":
                        person_risk = "high"
                    else:  # "normal" atau "crouching"
                        person_risk = "medium"

                    if person_risk != "none":
                        best_confidence = max(best_confidence, box_conf)
                    if person_risk == "high":
                        frame_risk_level = "high"
                        frame_posture = posture
                    elif person_risk == "medium" and frame_risk_level != "high":
                        frame_risk_level = "medium"
                        frame_posture = posture

                    if MJPEG_ENABLED or SHOW_PREVIEW:
                        color = {"high": (0, 0, 255), "medium": (0, 165, 255), "none": (0, 255, 0)}[person_risk]
                        cv2.rectangle(frame, (int(x1), int(y1)), (int(x2), int(y2)), color, 2)
                        if foot_point is not None:
                            cv2.circle(frame, (int(foot_point[0]), int(foot_point[1])), 5, color, -1)
                        label = f"{person_risk} ({posture})"
                        cv2.putText(frame, label, (int(x1), int(y1) - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)

                last_risk_level = frame_risk_level
                last_posture = frame_posture
                last_best_confidence = best_confidence
            else:
                # frame ini di-skip dari inference; pakai hasil terakhir
                # supaya status tidak "berkedip" jadi NORMAL palsu
                frame_risk_level = last_risk_level
                frame_posture = last_posture
                best_confidence = last_best_confidence

            # debounce: risk HIGH butuh lebih sedikit frame beruntun
            # dibanding risk MEDIUM sebelum status DANGER dinyatakan
            required_frames = HIGH_RISK_CONSECUTIVE_FRAMES if frame_risk_level == "high" else DANGER_CONSECUTIVE_FRAMES

            if frame_risk_level != "none":
                danger_streak += 1
            else:
                danger_streak = 0

            current_status = "DANGER" if danger_streak >= required_frames else "NORMAL"
            current_posture = frame_posture
            now = time.time()

            should_publish = False
            if current_status == "DANGER":
                # publish segera saat transisi NORMAL -> DANGER, lalu
                # republish tiap DANGER_REPUBLISH_INTERVAL detik selama
                # masih DANGER
                if last_status != "DANGER" or (now - last_publish_time) >= DANGER_REPUBLISH_INTERVAL:
                    should_publish = True
            else:
                # heartbeat NORMAL tiap NORMAL_PUBLISH_INTERVAL detik,
                # supaya app tahu koneksi/kamera masih hidup
                if (now - last_publish_time) >= NORMAL_PUBLISH_INTERVAL:
                    should_publish = True

            if should_publish:
                publish_detection(
                    current_status,
                    best_confidence if current_status == "DANGER" else 1.0,
                    posture=current_posture,
                )
                last_publish_time = now

            # --- Intervensi audio (DFPlayer Mini) ---
            # Sesuai proposal: begitu status DANGER, Pi memicu DUA tindakan
            # SEKALIGUS -- audio via DFPlayer DAN notifikasi via MQTT (di
            # atas). Track pesan dipilih sesuai tingkat risiko: HIGH pakai
            # pesan lebih tegas, MEDIUM pakai pesan lebih lembut.
            if current_status == "DANGER":
                should_play_audio = (
                    last_status != "DANGER"  # baru transisi ke DANGER -> mainkan segera
                    or (now - last_audio_play_time) >= AUDIO_REPLAY_INTERVAL
                )
                if should_play_audio:
                    track = AUDIO_TRACK_HIGH if frame_risk_level == "high" else AUDIO_TRACK_MEDIUM
                    audio_player.play_track(track)
                    last_audio_play_time = now
            else:
                # begitu situasi kembali NORMAL, hentikan audio yang mungkin
                # masih berputar (kalau ada) supaya tidak nyambung terus
                if last_status == "DANGER":
                    audio_player.stop()

            last_status = current_status

            if MJPEG_ENABLED or SHOW_PREVIEW:
                cv2.polylines(frame, [DANGER_ZONE_POINTS], True, (0, 165, 255), 2)
                cv2.putText(
                    frame,
                    f"STATUS: {current_status} ({frame_risk_level})",
                    (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.8,
                    (0, 0, 255) if current_status == "DANGER" else (0, 255, 0),
                    2,
                )

            if mjpeg_server is not None:
                mjpeg_server.update_frame(frame)

            if SHOW_PREVIEW:
                cv2.imshow("SafeRise - CAM05", frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break

    except KeyboardInterrupt:
        print("Stopping...")
    finally:
        cap.release()
        if SHOW_PREVIEW:
            cv2.destroyAllWindows()
        if mjpeg_server is not None:
            mjpeg_server.stop()
        audio_player.close()
        client.loop_stop()
        client.disconnect()


if __name__ == "__main__":
    main()
