# SafeRise -- Panduan Install untuk Anggota Tim Baru

## 1. Prasyarat
- Python 3.10 atau 3.11 terinstal (cek: `python --version`)
- (Opsional tapi disarankan) Anaconda/Miniconda untuk isolasi environment

## 2. Dapatkan kode project
Minta ZIP/clone repo dari anggota tim yang sudah punya (via GitHub, Google Drive, atau USB).

## 3. Buat environment terisolasi
    conda create -n saferise python=3.11 -y
    conda activate saferise

## 4. Install dependency
    pip install -r requirements/requirements.txt
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu

(Baris torch dipisah dari requirements.txt karena butuh index URL khusus
untuk versi CPU-only -- lihat requirements/requirements.txt untuk detail.)

## 5. Dapatkan file model
File `models/yolov8n-pose.pt` TIDAK ikut ter-share otomatis (ukurannya besar,
sengaja di-.gitignore). Minta file ini secara terpisah (Google Drive/USB) dari
anggota tim yang sudah punya, taruh di folder `models/`.

## 6. Dapatkan kredensial MQTT
JANGAN minta/kirim password lewat chat grup atau commit ke kode. Ada DUA cara
set kredensial (pilih salah satu, boleh dikombinasi):

### Cara A -- file config/.env (disarankan, sekali isi)
Salin template lalu isi password:
    copy config\.env.example config\.env      # Windows
    cp config/.env.example config/.env        # Linux/Mac/Pi

Semua publisher otomatis membaca config/.env saat start. File ini sengaja
di-.gitignore, jadi tidak akan ikut ter-commit.

### Cara B -- environment variable manual
Set sebagai environment variable SETIAP KALAU buka terminal baru:

    # Windows (Command Prompt / Anaconda Prompt)
    set MQTT_PASSWORD=xxx

    # Windows (PowerShell)
    $env:MQTT_PASSWORD="xxx"

    # Linux/Mac/Raspberry Pi
    export MQTT_PASSWORD=xxx

Prioritas nilai: env var terminal > config/.env > default di config/settings.py.
Daftar lengkap semua variabel yang didukung ada di config/.env.example.

## 7. Test instalasi
    python tests/test_mqtt.py
    python tests/test_danger_scenario.py --risk high
    python tools/pose_detector.py --source 0

Kalau ketiga test ini jalan tanpa error, instalasi sudah benar.

## 8. Arsitektur yang disarankan untuk Raspberry Pi 3
Untuk Pi 3, jalankan Pi hanya sebagai pengirim H.264 dari Camera Module 3 dan
controller DFPlayer. Jalankan YOLO di laptop yang satu jaringan lokal:

    # Di Pi: aktifkan Camera Module 3 dan UART DFPlayer, lalu
    python3 app/pi_camera_alarm_agent.py

    # Di laptop (ganti IP Pi sesuai jaringan)
    export STREAM_URL=tcp://192.168.1.50:8888
    python app/laptop_inference.py

Pi memakai `rpicam-vid`/`libcamera-vid` dengan hardware H.264 encoder. Laptop
mengirim perintah PLAY/STOP lewat MQTT ke Pi, sehingga speaker DFPlayer tetap
berbunyi di lokasi kamera. Gunakan jaringan LAN tepercaya: stream H.264 TCP
ini tidak memiliki enkripsi atau autentikasi sendiri.

Untuk alarm tetap berfungsi jika internet putus, gunakan broker Mosquitto di
jaringan lokal dan set pada `config/.env` kedua perangkat: `MQTT_HOST=<IP
laptop>`, `MQTT_PORT=1883`, dan `MQTT_TLS_ENABLED=0`. Jangan gunakan mode
tanpa TLS di jaringan publik/tidak tepercaya.

Sebelum deployment, kalibrasi zona menggunakan resolusi yang sama:

    python scripts/calibrate_zone.py

Salin baris `DANGER_ZONE_POINTS=...` yang dicetak tool ke `config/.env`, lalu
restart agent/publisher.
