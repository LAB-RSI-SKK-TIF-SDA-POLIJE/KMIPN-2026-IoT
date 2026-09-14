"""
SafeRise - Konfigurasi Terpusat
================================

SATU-SATUNYA tempat mendefinisikan konfigurasi untuk semua varian
publisher (pi_publisher_yolo.py / _lite.py / _tflite.py).

Sumber nilai, urutan prioritas (yang atas menang):
  1. Environment variable proses   ->  export MQTT_PASSWORD=xxx
  2. File config/.env              ->  salin dari config/.env.example lalu isi
  3. Default hardcoded di bawah    ->  nilai awal yang dipakai tim

File .env dimuat TANPA dependency tambahan (parser mini sendiri), jadi
tetap ringan untuk Raspberry Pi. Nilai dari .env TIDAK menimpa env var
yang sudah ada (setdefault), supaya override sementara di terminal tetap
bisa dilakukan tanpa mengedit file.

Modul ini sengaja TIDAK import numpy/cv2 -- pure stdlib, sehingga bisa
di-import di mana saja (tes, tools, laptop tanpa dependency AI).
"""

import json
import os

# ----------------------------------------------------------------------
# Loader file .env mini (tanpa python-dotenv)
# ----------------------------------------------------------------------
_ENV_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")


def _load_env_file(path: str):
    if not os.path.isfile(path):
        return
    parsed = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            if key.startswith("export "):
                key = key[len("export "):].strip()
            value = value.split(" #")[0].strip().strip('"').strip("'")
            if key:
                # duplikat: nilai yang paling bawah yang menang
                parsed[key] = value
    for key, value in parsed.items():
        # nilai kosong diabaikan (mis. MQTT_PASSWORD= di template),
        # supaya copy .env.example tanpa mengedit tetap tidak menimpa default
        if value:
            os.environ.setdefault(key, value)


_load_env_file(_ENV_FILE)


def _str(name: str, default: str) -> str:
    return os.environ.get(name, default)


def _int(name: str, default: int) -> int:
    return int(os.environ.get(name, default))


def _float(name: str, default: float) -> float:
    return float(os.environ.get(name, default))


def _bool(name: str, default: bool) -> bool:
    # Konvensi lama dipertahankan: hanya "1" yang dianggap True
    return os.environ.get(name, "1" if default else "0") == "1"


def _points(name: str, default: list[list[int]]) -> list[list[int]]:
    """Read a JSON polygon from the environment and validate its shape.

    Example: DANGER_ZONE_POINTS='[[25,144],[295,144],[295,230],[25,230]]'
    Invalid values fail fast instead of silently disabling danger detection.
    """
    raw = os.environ.get(name)
    if not raw:
        return default
    try:
        points = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{name} must be valid JSON: {exc.msg}") from exc
    if not isinstance(points, list) or len(points) < 3:
        raise ValueError(f"{name} must contain at least three [x, y] points")
    if any(
        not isinstance(point, list)
        or len(point) != 2
        or not all(isinstance(value, (int, float)) for value in point)
        for point in points
    ):
        raise ValueError(f"{name} must contain only [x, y] numeric points")
    return [[int(x), int(y)] for x, y in points]


# ----------------------------------------------------------------------
# 1. MQTT (broker HiveMQ Cloud, TLS port 8883)
# ----------------------------------------------------------------------
MQTT_HOST = _str(
    "MQTT_HOST", "1c66eefbd54741318908908707bafb17.s1.eu.hivemq.cloud"
)
MQTT_PORT = _int("MQTT_PORT", 8883)
MQTT_USERNAME = _str("MQTT_USERNAME", "syahrizal")
MQTT_PASSWORD = _str("MQTT_PASSWORD", "")  # WAJIB diisi via env var / .env, jangan hardcode
# Set 0 for a trusted-LAN broker (for example Mosquitto on the laptop).
MQTT_TLS_ENABLED = _bool("MQTT_TLS_ENABLED", True)

# Identitas kamera & topic publish
CAMERA_ID = _str("CAMERA_ID", "CAM05")
LOCATION = _str("LOCATION", "Rooftop Gedung A")
TOPIC = f"saferise/camera/{CAMERA_ID}/detection"

# ----------------------------------------------------------------------
# 2. Path model (dianchor ke folder project, bukan cwd)
# ----------------------------------------------------------------------
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(PROJECT_ROOT, "models")

MODEL_PT_PATH = os.path.join(MODELS_DIR, "yolov8n-pose.pt")          # versi PyTorch
MODEL_NCNN_DIR = os.path.join(MODELS_DIR, "yolov8n-pose_ncnn_model")  # hasil `yolo export format=ncnn`

# Override path model via env (kosong = pakai default masing-masing varian;
# varian tflite TANPA default -- wajib diisi karena nama file hasil export
# tidak bisa ditebak otomatis)
YOLO_MODEL = _str("YOLO_MODEL", "")

# ----------------------------------------------------------------------
# 3. Ambang deteksi YOLO pose
# ----------------------------------------------------------------------
CONF_THRESHOLD = _float("CONF_THRESHOLD", 0.5)        # minimum confidence box orang
KEYPOINT_CONF_THRESHOLD = _float("KEYPOINT_CONF_THRESHOLD", 0.3)  # minimum confidence per keypoint

# Index keypoint format COCO (dipakai YOLOv8-pose)
LEFT_SHOULDER, RIGHT_SHOULDER = 5, 6
LEFT_HIP, RIGHT_HIP = 11, 12
LEFT_KNEE, RIGHT_KNEE = 13, 14
LEFT_ANKLE, RIGHT_ANKLE = 15, 16

# ----------------------------------------------------------------------
# 4. Heuristik postur (hasil kalibrasi tools/pose_detector.py)
# ----------------------------------------------------------------------
NARROW_STANCE_RATIO = _float("NARROW_STANCE_RATIO", 0.35)  # ankle_dist/shoulder_dist < ini -> kaki rapat
LEG_RAISED_RATIO = _float("LEG_RAISED_RATIO", 0.30)        # selisih tinggi ankle/panjang kaki > ini -> kaki terangkat
CROUCH_KNEE_ANGLE_MAX = _float("CROUCH_KNEE_ANGLE_MAX", 140.0)  # sudut hip-knee-ankle < ini (kedua kaki) -> jongkok

# Polygon danger zone dalam koordinat piksel (x, y). List biasa supaya
# modul ini bebas numpy -- tiap publisher mengkonversi ke np.array(int32).
# Kalibrasi titik: python scripts/calibrate_zone.py
# Default is valid for the default 320x240 capture size. It is only a
# starting point; calibrate it for the actual camera before deployment.
DANGER_ZONE_POINTS = _points(
    "DANGER_ZONE_POINTS",
    [
        [25, 144],
        [295, 144],
        [295, 230],
        [25, 230],
    ],
)

# ----------------------------------------------------------------------
# 5. Debounce status & interval publish
# ----------------------------------------------------------------------
DANGER_CONSECUTIVE_FRAMES = _int("DANGER_CONSECUTIVE_FRAMES", 5)      # frame beruntun utk risk MEDIUM -> DANGER
HIGH_RISK_CONSECUTIVE_FRAMES = _int("HIGH_RISK_CONSECUTIVE_FRAMES", 2)  # frame beruntun utk risk HIGH -> DANGER
DANGER_REPUBLISH_INTERVAL = _int("DANGER_REPUBLISH_INTERVAL", 10)     # detik antar republish selama masih DANGER
NORMAL_PUBLISH_INTERVAL = _int("NORMAL_PUBLISH_INTERVAL", 5)          # detik heartbeat saat NORMAL

# ----------------------------------------------------------------------
# 6. DFPlayer Mini (intervensi audio lokal)
# ----------------------------------------------------------------------
AUDIO_ENABLED = _bool("AUDIO_ENABLED", False)  # default OFF -- aman dites tanpa hardware
DFPLAYER_PORT = _str("DFPLAYER_PORT", "/dev/serial0")
DFPLAYER_VOLUME = _int("DFPLAYER_VOLUME", 20)  # 0-30
AUDIO_TRACK_MEDIUM = _int("AUDIO_TRACK_MEDIUM", 1)  # pesan lembut, utk risk medium
AUDIO_TRACK_HIGH = _int("AUDIO_TRACK_HIGH", 2)      # pesan lebih tegas, utk risk high
AUDIO_REPLAY_INTERVAL = _int("AUDIO_REPLAY_INTERVAL", 15)  # detik antar replay selama DANGER

# ----------------------------------------------------------------------
# 7. Kamera
# ----------------------------------------------------------------------
CAMERA_SOURCE = _str("CAMERA_SOURCE", "0")       # index webcam ATAU path file video
CAMERA_BACKEND = _str("CAMERA_BACKEND", "picamera2")  # picamera2 | opencv | video
FRAME_WIDTH = _int("FRAME_WIDTH", 1280)           # kecil sengaja, biar ringan di Pi 3
FRAME_HEIGHT = _int("FRAME_HEIGHT", 768)
PROCESS_EVERY_N_FRAMES = _int("PROCESS_EVERY_N_FRAMES", 3)  # skip inference tiap N frame
SHOW_PREVIEW = _bool("SHOW_PREVIEW", False)      # window cv2.imshow (butuh GUI)

# ----------------------------------------------------------------------
# 8. Live stream MJPEG untuk app Flutter (dipakai laptop_inference.py;
#    dulu juga dipakai pi_publisher_yolo.py di arsitektur lama)
# ----------------------------------------------------------------------
MJPEG_ENABLED = _bool("MJPEG_ENABLED", True)     # default ON
MJPEG_PORT = _int("MJPEG_PORT", 8080)            # HARUS 8080: app Flutter hardcode port ini (CameraSnapshot.streamPort)
MJPEG_QUALITY = _int("MJPEG_QUALITY", 70)        # 0-100, makin rendah makin ringan
MJPEG_FPS = _int("MJPEG_FPS", 10)

# ----------------------------------------------------------------------
# 9. Motion-gating (hanya dipakai versi lite & tflite)
# ----------------------------------------------------------------------
MOTION_GATING_ENABLED = _bool("MOTION_GATING_ENABLED", True)
MOTION_PIXEL_THRESHOLD = _int("MOTION_PIXEL_THRESHOLD", 400)  # jumlah piksel "berubah" utk dianggap ada gerakan
MOTION_DIFF_THRESHOLD = _int("MOTION_DIFF_THRESHOLD", 25)     # selisih intensitas grayscale per piksel
FORCE_INFERENCE_INTERVAL = _float("FORCE_INFERENCE_INTERVAL", 5.0)  # detik, paksa inference walau tanpa gerakan

# ----------------------------------------------------------------------
# 10. Offloaded inference: Pi Camera 3 streams H.264, laptop runs YOLO
# ----------------------------------------------------------------------
# Pi agent uses rpicam-vid/libcamera-vid hardware encoding and listens on
# this TCP port. The laptop reads STREAM_URL with an OpenCV build that has
# FFmpeg support. Keep this on a trusted LAN.
STREAM_PORT = _int("STREAM_PORT", 8888)
STREAM_FPS = _int("STREAM_FPS", 15)
STREAM_URL = _str("STREAM_URL", "")

# Pi subscribes here for PLAY/STOP commands from the laptop inference app.
ALARM_COMMAND_TOPIC = f"saferise/camera/{CAMERA_ID}/alarm-command"

# ----------------------------------------------------------------------
# 11. Broker untuk alarm command Pi<->laptop (dual-broker, opsional)
# ----------------------------------------------------------------------
# Kosongkan LOCAL_MQTT_HOST -> alarm command ikut lewat HiveMQ Cloud
# (MQTT_HOST) seperti status detection, satu broker untuk semua. Cocok
# kalau belum sempat/tidak perlu setup Mosquitto lokal (mis. demo
# singkat di venue dengan internet stabil).
#
# Isi LOCAL_MQTT_HOST (IP laptop yang menjalankan Mosquitto, mis.
# 192.168.1.10) -> alarm command lewat broker LAN lokal, terpisah dari
# ketergantungan internet, sementara status detection ke app Flutter
# TETAP lewat HiveMQ Cloud seperti biasa (tidak terpengaruh).
LOCAL_MQTT_HOST = _str("LOCAL_MQTT_HOST", "")
LOCAL_MQTT_PORT = _int("LOCAL_MQTT_PORT", 1883)
LOCAL_MQTT_USERNAME = _str("LOCAL_MQTT_USERNAME", "")  # kosong = anonymous (cocok dgn allow_anonymous true)
LOCAL_MQTT_PASSWORD = _str("LOCAL_MQTT_PASSWORD", "")
LOCAL_MQTT_TLS_ENABLED = _bool("LOCAL_MQTT_TLS_ENABLED", False)  # Mosquitto LAN biasanya tanpa TLS

# Nilai yang BENAR-BENAR dipakai kode untuk koneksi alarm command --
# resolve fallback di SATU tempat ini saja, supaya pi_camera_alarm_agent.py
# dan laptop_inference.py tidak perlu duplikasi logic if/else yang sama.
ALARM_MQTT_USES_LOCAL_BROKER = bool(LOCAL_MQTT_HOST)
ALARM_MQTT_HOST = LOCAL_MQTT_HOST or MQTT_HOST
ALARM_MQTT_PORT = LOCAL_MQTT_PORT if ALARM_MQTT_USES_LOCAL_BROKER else MQTT_PORT
ALARM_MQTT_USERNAME = LOCAL_MQTT_USERNAME if ALARM_MQTT_USES_LOCAL_BROKER else MQTT_USERNAME
ALARM_MQTT_PASSWORD = LOCAL_MQTT_PASSWORD if ALARM_MQTT_USES_LOCAL_BROKER else MQTT_PASSWORD
ALARM_MQTT_TLS_ENABLED = LOCAL_MQTT_TLS_ENABLED if ALARM_MQTT_USES_LOCAL_BROKER else MQTT_TLS_ENABLED