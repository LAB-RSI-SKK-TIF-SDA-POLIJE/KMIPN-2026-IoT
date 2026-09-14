"""
SafeRise - Tes Mandiri Koneksi MQTT
====================================
Skrip ini HANYA menguji jalur MQTT (connect -> subscribe -> publish ->
terima balik), terpisah total dari kamera/YOLO/DFPlayer. Kalau ini
berhasil tapi pi_publisher_yolo.py tidak, berarti masalahnya ada di
kamera/YOLO, BUKAN di MQTT -- jadi kamu tahu persis harus cek di mana.

Cara pakai:
    # pastikan MQTT_PASSWORD sudah terisi di config/.env (atau export manual)
    python3 test_mqtt.py

Hasil yang diharapkan (semua baris [OK]):
    [OK] Berhasil connect ke ...
    [OK] Subscribe ke topic: saferise/camera/CAM05/detection
    [OK] Pesan diterima balik dari broker: {...}
    === HASIL: MQTT BERHASIL ===
"""

import json
import os
import ssl
import sys
import time
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

# Konfigurasi terpusat: otomatis membaca env var & file config/.env
# (lihat config/settings.py). Prioritas: env var > config/.env > default.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config.settings import (  # noqa: E402
    CAMERA_ID,
    MQTT_HOST,
    MQTT_PASSWORD,
    MQTT_PORT,
    MQTT_USERNAME,
    TOPIC,
)

received = {"ok": False}


def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print(f"[OK] Berhasil connect ke {MQTT_HOST}:{MQTT_PORT}")
        client.subscribe(TOPIC)
        print(f"[OK] Subscribe ke topic: {TOPIC}")
    else:
        # rc umum: 4 = username/password salah, 5 = not authorized
        print(f"[GAGAL] Connect gagal, rc={rc}")
        print("        rc=4 -> username/password salah")
        print("        rc=5 -> not authorized (cek permission topic di HiveMQ)")
        print("        Kalau tidak ada rc sama sekali & macet -> kemungkinan port 8883 diblok firewall/jaringan")
        sys.exit(1)


def on_message(client, userdata, msg):
    print(f"[OK] Pesan diterima balik dari broker: {msg.payload.decode()}")
    received["ok"] = True


def on_disconnect(client, userdata, rc):
    print(f"[INFO] Disconnected, rc={rc}")


def main():
    if not MQTT_PASSWORD:
        print("[PERINGATAN] MQTT_PASSWORD kosong! Isi di config/.env (salin dari")
        print("             config/.env.example) atau set: export MQTT_PASSWORD=xxx")
        print("             (lanjut jalan, tapi kemungkinan besar bakal gagal auth)\n")

    client = mqtt.Client(client_id=f"saferise_test_{int(time.time())}", protocol=mqtt.MQTTv311)
    client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    client.tls_set(cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLS_CLIENT)
    client.on_connect = on_connect
    client.on_message = on_message
    client.on_disconnect = on_disconnect

    print(f"[INFO] Mencoba connect ke {MQTT_HOST} sebagai user '{MQTT_USERNAME}'...")
    try:
        client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
    except Exception as e:
        print(f"[GAGAL] Tidak bisa membuka koneksi sama sekali: {e}")
        print("        Cek: koneksi internet Pi, atau MQTT_HOST salah ketik.")
        sys.exit(1)

    client.loop_start()
    time.sleep(2)  # beri waktu proses connect + subscribe selesai

    # payload = {
    #     "camera_id": CAMERA_ID,
    #     "status": "NORMAL",
    #     "confidence": 1.0,
    #     "location": "TEST",
    #     "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    #     "audio": "IDLE",
    #     "posture": "normal",
    # }
    payload = {
        "camera_id": CAMERA_ID,
        "status": "DANGER",       # <- bedanya di sini
        "confidence": 0.91,
        "location": "TEST",
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "audio": "PLAYING",       # <- dan di sini
        "posture": "climbing",    # <- dan di sini
    }
    print(f"[INFO] Publish pesan tes ke {TOPIC}...")
    client.publish(TOPIC, json.dumps(payload), qos=1)

    time.sleep(3)  # tunggu pesan balik lewat subscribe

    if received["ok"]:
        print("\n=== HASIL: MQTT BERHASIL (connect + publish + terima balik) ===")
        print("Jalur MQTT kamu sehat. Kalau pi_publisher_yolo.py masih")
        print("bermasalah, berarti masalahnya di kamera/YOLO, bukan MQTT.")
    else:
        print("\n=== HASIL: PESAN TERKIRIM TAPI TIDAK DITERIMA BALIK ===")
        print("Coba cek juga dari HiveMQ Web Client atau app Flutter apakah")
        print("pesan tetap masuk di sana (kemungkinan cuma subscribe lokal")
        print("di skrip ini yang belum sempat aktif, bukan berarti gagal total).")

    client.loop_stop()
    client.disconnect()


if __name__ == "__main__":
    main()
