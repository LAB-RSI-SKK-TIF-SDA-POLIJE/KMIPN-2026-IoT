# SafeRise: Setup Raspberry Pi 3, Camera Module 3, Laptop Inference, dan DFPlayer

Panduan ini menggunakan arsitektur berikut:

```text
Camera Module 3
      │
      ▼
Raspberry Pi 3
  - rpicam-vid hardware H.264 encoder
  - kirim video melalui LAN
  - menerima perintah MQTT
  - DFPlayer Mini + speaker
      │
      ▼
Laptop
  - menerima stream H.264
  - menjalankan YOLO Pose
  - menentukan NORMAL / DANGER
  - mengirim command PLAY / STOP ke Pi
  - opsional publish status ke Flutter/HiveMQ
```

Penting:
- Model YOLO hanya perlu berada di laptop.
- Raspberry Pi tidak perlu menginstal PyTorch, Ultralytics, atau model YOLO.
- Raspberry Pi hanya perlu library MQTT dan DFPlayer.
- Laptop dan Pi harus berada pada jaringan yang sama.

## A. Persiapan hardware

### 1. Hardware Raspberry Pi

Yang diperlukan:
- Raspberry Pi 3 dengan power supply stabil.
- Raspberry Pi Camera Module 3.
- Kabel CSI camera yang sesuai.
- MicroSD dengan Raspberry Pi OS 64-bit Bookworm.
- DFPlayer Mini.
- MicroSD untuk DFPlayer, format FAT32.
- Speaker.
- Resistor sekitar 1 kΩ untuk jalur Pi TX → DFPlayer RX.
- Kabel jumper.

### 2. Wiring DFPlayer Mini

```text
Raspberry Pi GPIO14 / TX, pin 8  -> resistor 1kΩ -> DFPlayer RX coklat
Raspberry Pi GPIO15 / RX, pin 10 -> DFPlayer TX merah
Raspberry Pi 5V                  -> DFPlayer VCCoren
Raspberry Pi GND                 -> DFPlayer GND
DFPlayer SPK_1 dan SPK_2         -> speaker
```

Jangan lupa:
- DFPlayer dan Raspberry Pi wajib memakai GND yang sama.
- Siapkan audio pada microSD DFPlayer:
  - `0001.mp3` untuk medium risk;
  - `0002.mp3` untuk high risk.
- Salin audio satu per satu secara berurutan agar track order DFPlayer konsisten.

## B. Menyiapkan Raspberry Pi 3

### 1. Instal Raspberry Pi OS

Gunakan Raspberry Pi OS 64-bit Bookworm terbaru.

Setelah boot:
- Sambungkan Pi ke Wi-Fi atau Ethernet yang sama dengan laptop.
- Aktifkan SSH bila ingin mengakses Pi dari laptop.
- Catat IP Pi:

```bash
hostname -I
```

Contoh hasil:

```text
192.168.1.50
```

### 2. Update sistem

```bash
sudo apt update
sudo apt upgrade -y
sudo reboot
```

### 3. Aktifkan Camera Module 3

Masuk ke konfigurasi:

```bash
sudo raspi-config
```

Lalu:
- Interface Options;
- Camera;
- aktifkan kamera;
- reboot bila diminta.

Setelah reboot, cek kamera:

```bash
rpicam-hello
```

Jika command tidak ditemukan, coba:

```bash
sudo apt install -y rpicam-apps
```

Pada sistem lama, nama command dapat berupa:

```bash
libcamera-hello
```

Code SafeRise mendukung `rpicam-vid` maupun `libcamera-vid`.

### 4. Aktifkan UART untuk DFPlayer

Jalankan:

```bash
sudo raspi-config
```

Masuk ke:
- Interface Options;
- Serial Port.

Atur:
- “Would you like a login shell to be accessible over serial?” → No
- “Would you like the serial port hardware to be enabled?” → Yes

Kemudian reboot:

```bash
sudo reboot
```

### 5. Instal dependency minimal Pi

Pada Pi, jangan instal seluruh requirements untuk inference. Pi agent tidak memerlukan YOLO, Torch, atau OpenCV.

Instal Python tooling dan library yang diperlukan:

```bash
sudo apt install -y python3-pip python3-venv
```

Buat virtual environment:

```bash
mkdir -p ~/saferise_rasppython
cd ~/saferise_rasppython
python3 -m venv .venv
source .venv/bin/activate
```

Nanti, setelah project disalin ke Pi, instal:

```bash
pip install paho-mqtt pyserial
```

### 6. Beri izin serial ke user Pi

```bash
sudo usermod -aG dialout $USER
sudo reboot
```

Cek port UART:

```bash
ls -l /dev/serial0
```

## C. Memindahkan project ke Raspberry Pi

Saat ini ada file baru dan perubahan lokal yang belum di-commit. Jika Anda hanya melakukan `git clone`, perubahan lokal tersebut tidak ikut masuk ke Pi.

Pilihan terbaik: commit dulu perubahan yang memang ingin dipakai, lalu clone/pull dari repository.

Jika belum ingin commit, salin file secara manual dari laptop ke Pi.

Dari Git Bash di Windows, di root project:

```bash
cd /d/Project/SAFERISE/saferise_rasppython
scp -r app config requirements scripts pi@192.168.1.50:~/saferise_rasppython/
```

Ganti:
- `pi` dengan username Raspberry Pi Anda;
- `192.168.1.50` dengan IP Pi sebenarnya.

Masuk ke Pi:

```bash
ssh pi@192.168.1.50
cd ~/saferise_rasppython
source .venv/bin/activate
pip install paho-mqtt pyserial
```

File penting yang harus ada di Pi:

```text
app/pi_camera_alarm_agent.py
app/dfplayer.py
config/settings.py
config/.env.example
```

Pi tidak perlu:
- `models/yolov8n-pose.pt`;
- `ultralytics`;
- `torch`;
- `opencv-python`;
- `app/laptop_inference.py` untuk proses Pi, walaupun tidak masalah bila file ikut tersalin.

## D. Konfigurasi MQTT lokal di laptop

Untuk alarm, lebih baik gunakan MQTT broker lokal daripada hanya HiveMQ Cloud.

Keuntungan:
- Jika internet putus, alarm tetap dapat dikirim laptop ke Pi.
- Latency lebih rendah.
- Tidak bergantung layanan cloud.
- DFPlayer tetap bisa berbunyi saat kondisi bahaya.

### 1. Instal Mosquitto pada laptop

Instal Mosquitto untuk Windows. Setelah terinstal, buka terminal baru dan cek:

```bash
mosquitto -v
```

Broker biasanya memakai port `1883`. Jalankan broker:

```bash
mosquitto -v
```

Biarkan terminal ini terbuka selama testing.

### 2. Cari IP laptop

Di Git Bash Windows:

```bash
ipconfig
```

Cari IPv4 jaringan aktif, misalnya:

```text
192.168.1.10
```

### 3. Izinkan firewall Windows

Jika Pi tidak dapat connect ke laptop:
- izinkan aplikasi Mosquitto pada Windows Defender Firewall;
- atau buka inbound TCP port `1883` untuk jaringan private.

### 4. Konfigurasi MQTT pada Pi

Di Pi:

```bash
cd ~/saferise_rasppython
cp config/.env.example config/.env
nano config/.env
```

Isi bagian ini:

```text
MQTT_HOST=192.168.1.10
MQTT_PORT=1883
MQTT_TLS_ENABLED=0
MQTT_USERNAME=saferise
MQTT_PASSWORD=

CAMERA_ID=CAM05
LOCATION=Rooftop Gedung A

AUDIO_ENABLED=1
DFPLAYER_PORT=/dev/serial0
DFPLAYER_VOLUME=20
AUDIO_TRACK_MEDIUM=1
AUDIO_TRACK_HIGH=2

FRAME_WIDTH=320
FRAME_HEIGHT=240
STREAM_PORT=8888
STREAM_FPS=15
```

Ganti `192.168.1.10` dengan IP laptop.

Catatan:
- Jangan gunakan `MQTT_TLS_ENABLED=0` pada jaringan publik.
- Untuk testing LAN lokal, setting ini normal.
- Pastikan `CAMERA_ID` Pi dan laptop sama.

## E. Menguji DFPlayer sebelum streaming

Di Pi:

```bash
cd ~/saferise_rasppython
source .venv/bin/activate
python3 app/dfplayer.py --port /dev/serial0 --track 1 --volume 80
```

Harusnya speaker memainkan track pertama. Jika tidak:
- cek wiring TX/RX;
- cek GND;
- cek microSD DFPlayer;
- cek file audio;
- cek UART dengan `ls -l /dev/serial0`.

Setelah track 1 berhasil, tes track 2:

```bash
python3 app/dfplayer.py --port /dev/serial0 --track 2 --volume 20
```

## F. Menjalankan Pi Camera + DFPlayer Agent

Di Pi:

```bash
cd ~/saferise_rasppython
source .venv/bin/activate
python3 app/pi_camera_alarm_agent.py
```

Jika berhasil, output akan serupa:

```text
[STREAM] H.264 TCP listening at tcp://0.0.0.0:8888
[MQTT] subscribed: saferise/camera/CAM05/alarm-command
```

Pi sekarang:
- menunggu laptop membuka video stream;
- menerima command MQTT;
- dapat memainkan audio DFPlayer.

Jangan jalankan publisher YOLO lama di Pi bersamaan dengan agent ini:

```text
app/pi_publisher_yolo.py
app/pi_publisher_yolo_lite.py
app/pi_publisher_yolo_tflite.py
```

## G. Menyiapkan laptop untuk inference

Laptop perlu:
- Python 3.10 atau 3.11;
- dependency Python;
- model YOLO Pose;
- source code SafeRise terbaru;
- koneksi ke Wi-Fi/LAN yang sama dengan Pi.

### 1. Pastikan source code laptop terbaru

Project berada di:

```text
D:\Project\SAFERISE\saferise_rasppython
```

### 2. Buat environment Python

Di Git Bash:

```bash
cd /d/Project/SAFERISE/saferise_rasppython
python -m venv .venv
source .venv/Scripts/activate
```

Jika menggunakan Command Prompt Windows:

```text
.venv\Scripts\activate
```

### 3. Instal library laptop

```bash
pip install -r requirements/requirements.txt
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
```

Jika laptop memiliki GPU NVIDIA dan ingin memakai GPU, instal PyTorch sesuai panduan resmi PyTorch/CUDA, bukan command CPU-only di atas.

### 4. Siapkan model YOLO Pose

File model tidak ikut Git karena ukurannya besar.

Pastikan file ini tersedia:

```text
models/yolov8n-pose.pt
```

Jika tidak ada:
- salin dari anggota tim;
- atau download/export sesuai model yang dipakai project;
- letakkan di folder `models/`.

### 5. Buat konfigurasi laptop

```bash
cp config/.env.example config/.env
```

Edit `config/.env` laptop:

```text
MQTT_HOST=192.168.1.10
MQTT_PORT=1883
MQTT_TLS_ENABLED=0
MQTT_USERNAME=saferise
MQTT_PASSWORD=

CAMERA_ID=CAM05
LOCATION=Rooftop Gedung A

FRAME_WIDTH=320
FRAME_HEIGHT=240
STREAM_URL=tcp://192.168.1.50:8888

YOLO_MODEL=
SHOW_PREVIEW=1
PROCESS_EVERY_N_FRAMES=1
```

Ganti:
- `192.168.1.10` → IP laptop;
- `192.168.1.50` → IP Raspberry Pi.

Untuk laptop yang cukup kuat, mulai dari `PROCESS_EVERY_N_FRAMES=1`. Jika inference terlalu berat, ubah ke `2` atau `3`.

## H. Kalibrasi danger zone

Kalibrasi harus dilakukan sebelum demo.

Penting:
- Resolusi kalibrasi harus sama dengan streaming.
- Untuk konfigurasi awal, gunakan 320×240 di Pi dan laptop.
- Jangan ubah `FRAME_WIDTH`/`FRAME_HEIGHT` setelah kalibrasi tanpa kalibrasi ulang.

Di Pi, hentikan agent sementara dengan `Ctrl+C`, lalu jalankan:

```bash
cd ~/saferise_rasppython
source .venv/bin/activate
python3 scripts/calibrate_zone.py
```

Klik titik bahaya di preview:
- buat polygon di area railing/tepi rooftop;
- tekan `s` ketika selesai;
- tool mencetak hasil seperti:

```text
DANGER_ZONE_POINTS=[[20,150],[300,150],[300,230],[20,230]]
```

Salin baris tersebut ke:
- `config/.env` pada Pi;
- `config/.env` pada laptop.

Setelah itu jalankan ulang Pi agent.

## I. Menguji command alarm MQTT

Sebelum menjalankan YOLO, pastikan laptop dapat memicu speaker Pi.

Dari laptop, gunakan MQTT client atau buat test sederhana. Jika Mosquitto client tersedia:

```bash
mosquitto_pub -h 192.168.1.10 -p 1883 \
  -t saferise/camera/CAM05/alarm-command \
  -m "{\"camera_id\":\"CAM05\",\"action\":\"PLAY\",\"risk\":\"high\"}"
```

Pi harus menjalankan track high risk, biasanya track 2.

Untuk menghentikan audio:

```bash
mosquitto_pub -h 192.168.1.10 -p 1883 \
  -t saferise/camera/CAM05/alarm-command \
  -m "{\"camera_id\":\"CAM05\",\"action\":\"STOP\"}"
```

Jika command tidak diterima:
- cek IP laptop pada `.env` Pi;
- cek Mosquitto masih berjalan;
- cek firewall Windows;
- cek `CAMERA_ID`;
- cek output Pi agent dan topic subscribe.

## J. Menjalankan inference di laptop

Pastikan:
- Pi agent sedang hidup;
- Mosquitto sedang hidup;
- stream Pi tersedia;
- `STREAM_URL` laptop benar;
- model ada di `models/yolov8n-pose.pt`.

Di laptop:

```bash
cd /d/Project/SAFERISE/saferise_rasppython
source .venv/Scripts/activate
python app/laptop_inference.py
```

Jika berhasil:
- window preview muncul bila `SHOW_PREVIEW=1`;
- polygon danger zone muncul;
- model memproses video;
- saat DANGER terdeteksi, laptop publish command `PLAY`;
- Pi memainkan audio;
- saat kembali NORMAL, laptop publish `STOP`.

Keluar dari preview dengan tombol `q`.

## K. Urutan testing yang aman

Ikuti urutan ini, jangan langsung YOLO:

1. `rpicam-hello` berhasil di Pi.
2. DFPlayer track 1 dan track 2 berhasil.
3. Mosquitto berjalan di laptop.
4. Pi agent berhasil connect MQTT dan subscribe.
5. Laptop dapat mengirim command `PLAY` dan `STOP`.
6. Pi agent membuat H.264 stream.
7. Laptop dapat membuka H.264 stream.
8. Kalibrasi danger zone.
9. Jalankan YOLO pada laptop.
10. Uji normal, medium risk, dan high risk.
11. Uji kondisi jaringan putus.
12. Uji restart Pi/laptop dan recovery sistem.

## L. Jika terjadi masalah

### 1. `rpicam-vid` tidak ditemukan

```bash
sudo apt update
sudo apt install -y rpicam-apps
```

Atau gunakan Raspberry Pi OS Bookworm yang lebih baru.

### 2. Kamera tidak muncul

- cek kabel CSI;
- pastikan orientasi kabel benar;
- jalankan `rpicam-hello`;
- reboot Pi;
- pastikan Camera Module 3 terdeteksi.

### 3. DFPlayer tidak berbunyi

- cek TX/RX tidak tertukar;
- cek resistor ke DFPlayer RX;
- cek GND bersama;
- cek file `0001.mp3` dan `0002.mp3`;
- cek microSD FAT32;
- cek `/dev/serial0`;
- pastikan login shell serial sudah dimatikan.

### 4. Laptop tidak bisa membuka stream

- cek `STREAM_URL`;
- cek Pi agent masih berjalan;
- cek Pi dan laptop satu jaringan;
- cek firewall Windows port 8888;
- coba Ethernet;
- set `STREAM_FPS=10`;
- pastikan OpenCV laptop memiliki backend FFmpeg.

### 5. Laptop mendeteksi tetapi speaker tidak berbunyi

- cek MQTT broker;
- cek topic command;
- cek `CAMERA_ID` sama di laptop dan Pi;
- cek `AUDIO_ENABLED=1` di Pi;
- cek output terminal Pi agent.

### 6. Alarm sering salah

- kalibrasi danger zone ulang;
- naikkan `DANGER_CONSECUTIVE_FRAMES`;
- naikkan `HIGH_RISK_CONSECUTIVE_FRAMES`;
- lakukan kalibrasi threshold pose pada beberapa kondisi nyata;
- kumpulkan video simulasi untuk menguji false positive dan false negative.

## Prioritas implementasi

1. Siapkan Pi Camera 3.
2. Pastikan DFPlayer mandiri bekerja.
3. Setup Mosquitto lokal.
4. Jalankan Pi agent.
5. Uji command alarm manual.
6. Uji H.264 stream.
7. Baru jalankan YOLO pada laptop.




1. Nyalakan Mosquitto (jendela sendiri)
Di laptop, jendela terminal khusus, biarkan tetap terbuka selama sistem jalan: ``` cd D:\Project\SAFERISE\saferise_rasppython mosquitto -v -c mosquitto_local.conf ``` Pastikan log terakhir `running`, bukan `terminating`.
2
2. Nyalakan Pi agent
Di Pi lewat SSH: ``` cd ~/saferise_rasppython source .venv/bin/activate python3 app/pi_camera_alarm_agent.py ``` Ini yang menyalakan stream H.264 dari Camera Module 3 dan mendengarkan command alarm MQTT. Biarkan tetap berjalan.
3
3. Kalibrasi danger zone (kalau belum/berubah posisi kamera)
Kalau danger zone belum pernah dikalibrasi untuk resolusi/posisi kamera saat ini, jalankan dulu (laptop, jendela lain): ``` cd D:\Project\SAFERISE\saferise_rasppython .venv\Scripts\activate set CAMERA_BACKEND=opencv set CAMERA_SOURCE=tcp://192.168.1.23:8888 python scripts\calibrate_zone.py ``` Klik sudut-sudut danger zone, tekan `s`, lalu copy baris `DANGER_ZONE_POINTS=...` yang dicetak ke `config/.env` di Pi DAN laptop. Kalau sudah pernah dikalibrasi dan kamera belum dipindah, lewati langkah ini.
4
4. Jalankan inference YOLO di laptop -- ini 'project utama'-nya
Masih di laptop, jendela terpisah lagi: ``` cd D:\Project\SAFERISE\saferise_rasppython .venv\Scripts\activate python app\laptop_inference.py ``` Ini yang benar-benar menjalankan YOLO Pose terhadap stream Pi, menentukan NORMAL/DANGER, publish status ke HiveMQ Cloud (dibaca app Flutter), dan kirim command PLAY/STOP ke Pi lewat Mosquitto lokal.
5
5. Verifikasi
Kalau `SHOW_PREVIEW=1`, jendela preview dari laptop_inference.py akan menampilkan polygon danger zone + status NORMAL/DANGER secara live. Buka app Flutter untuk konfirmasi status juga masuk ke sana. Tekan `q` di jendela preview untuk berhenti dengan aman (otomatis kirim STOP kalau lagi DANGER).