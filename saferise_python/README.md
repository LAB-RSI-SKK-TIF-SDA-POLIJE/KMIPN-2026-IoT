# SafeRise

Sistem monitoring keselamatan berbasis YOLOv8 Pose untuk area berisiko tinggi (rooftop). Menggabungkan deteksi posisi tubuh dengan zona bahaya untuk menghasilkan peringatan dini, dilengkapi audio intervensi lokal via DFPlayer Mini.

## Arsitektur

```
Camera Module 3 (Pi 3)
        |
        v
Raspberry Pi 3                 Laptop (inference)
  - rpicam-vid H.264          - YOLOv8 Pose detection
  - DFPlayer Mini             - Klasifikasi NORMAL/DANGER
  - MQTT subscriber           - Publish status ke HiveMQ
        |                     - Command PLAY/STOP ke Pi
        +---- LAN/HiveMQ ----+
                                |
                                v
                           Flutter App
```

## Fitur

- **Deteksi Pose**: YOLOv8-pose untuk mendeteksi 17 keypoint tubuh
- **Zona Bahaya**: Polygon danger zone yang bisa dikalibrasi
- **Analisis Postur**: Klasifikasi normal / crouching / climbing (narrow stance, leg raised)
- **Level Risiko**: Kombinasi zona + postur (medium / high)
- **Debounce**: Anti false-positive dengan consecutive frames
- **Audio Alert**: DFPlayer Mini untuk intervensi lokal
- **Live Stream**: MJPEG server untuk preview di browser/Flutter
- **MQTT**: Publish status ke HiveMQ Cloud, alarm command via Mosquitto lokal

## Varian Publisher

| File | Model | Target | Catatan |
|------|-------|--------|---------|
| `pi_publisher_yolo.py` | PyTorch (.pt) | Pi 4/5 / Laptop | Full fitur, paling berat |
| `pi_publisher_yolo_lite.py` | NCNN | Pi 3 | + motion-gating, 3-5x lebih cepat di ARM |
| `pi_publisher_yolo_tflite.py` | TFLite INT8 | Pi 3 | Paling ringan, perlu verifikasi akurasi |
| `pi_camera_alarm_agent.py` | Tanpa YOLO | Pi 3 | Hanya stream H.264 + kontrol DFPlayer |

**Rekomendasi untuk Raspberry Pi 3**: Gunakan `pi_camera_alarm_agent.py` di Pi + `laptop_inference.py` di laptop. Pi hanya mengirim stream H.264, inference dilakukan di laptop.

## Instalasi

### 1. Prasyarat

- Python 3.10 atau 3.11
- Model `yolov8n-pose.pt` (dapatkan dari tim, letakkan di `models/`)

### 2. Setup Environment

```bash
python -m venv .venv
source .venv/bin/activate          # Linux/Mac
# .venv\Scripts\activate           # Windows

pip install -r requirements/requirements.txt
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
```

### 3. Konfigurasi

```bash
cp config/.env.example config/.env
```

Edit `config/.env` -- minimal isi `MQTT_PASSWORD`. Lihat `config/.env.example` untuk daftar lengkap variabel.

### 4. Kalibrasi Danger Zone

```bash
python scripts/calibrate_zone.py
```

Klik titik-titik area berbahaya, tekan `s`, lalu copy hasil ke `config/.env`.

## Menjalankan

### Mode Laptop Inference (Recommended untuk Pi 3)

```bash
# Di Pi:
python app/pi_camera_alarm_agent.py

# Di laptop:
set STREAM_URL=tcp://<IP_PI>:8888
python app/laptop_inference.py
```

### Mode On-Device (Pi 4/5)

```bash
# PyTorch:
python app/pi_publisher_yolo.py

# NCNN (lebih cepat di ARM):
python app/pi_publisher_yolo_lite.py

# TFLite INT8 (paling ringan):
python app/pi_publisher_yolo_tflite.py
```

### Tools Kalibrasi

```bash
python tools/pose_detector.py --source 0       # kalibrasi threshold pose
python scripts/calibrate_zone.py               # kalibrasi zona bahaya
```

### Testing

```bash
python tests/test_mqtt.py                      # tes koneksi MQTT
python tests/test_danger_scenario.py --risk high  # simulasi DANGER
python tests/test_detection_logic.py           # unit test logic deteksi
```

## Struktur Project

```
saferise_rasppython/
  app/
    pi_publisher_yolo.py          # Publisher PyTorch (full)
    pi_publisher_yolo_lite.py     # Publisher NCNN + motion-gating
    pi_publisher_yolo_tflite.py   # Publisher TFLite INT8
    pi_camera_alarm_agent.py      # Pi agent (stream + DFPlayer)
    laptop_inference.py           # Inference di laptop
    detection_logic.py            # Shared pose classification
    dfplayer.py                   # DFPlayer Mini controller
    mjpeg_server.py               # MJPEG HTTP server
    camera_viewer.py              # Simple camera viewer
  config/
    settings.py                   # Konfigurasi terpusat
    .env.example                  # Template environment
  models/
    yolov8n-pose.pt               # Model PyTorch (gitignored)
    yolov8n-pose_ncnn_model/      # Model NCNN (gitignored)
  scripts/
    calibrate_zone.py             # Tool kalibrasi zona bahaya
  tools/
    pose_detector.py              # Tool kalibrasi pose
  tests/
    test_mqtt.py                  # Test koneksi MQTT
    test_danger_scenario.py       # Simulasi skenario DANGER
    test_detection_logic.py       # Unit test
  requirements/
    requirements.txt              # Python dependencies
```

## Troubleshooting

- **MQTT gagal connect**: Cek `MQTT_PASSWORD` di `config/.env`, pastikan port 8883 terbuka
- **Stream tidak bisa dibuka**: Pastikan Pi dan laptop satu jaringan, cek firewall port 8888
- **DFPlayer tidak bunyi**: Cek wiring TX/RX, GND, file audio di microSD
- **Deteksi sering salah**: Kalibrasi ulang danger zone dan threshold pose

## Panduan Lengkap

- [Panduan Install](README_INSTALL.md)
- [Setup Raspberry Pi 3 + Laptop](SETUP_PI3_LAPTOP.md)
