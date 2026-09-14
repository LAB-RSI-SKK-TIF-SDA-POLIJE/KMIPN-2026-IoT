"""
SafeRise - Simulasi Skenario DANGER
=====================================
Skrip ini mensimulasikan APA YANG TERJADI ketika status berubah jadi
DANGER -- publish MQTT + trigger DFPlayer -- TANPA perlu kamera/pose
asli. Berguna untuk menguji reaksi sistem (MQTT + audio) secara
terpisah dari akurasi deteksi YOLO, jadi kamu tidak perlu berdiri di
depan kamera dan berpose "memanjat" berulang-ulang cuma buat tes app
& speaker.

Skrip ini memanggil FUNGSI YANG SAMA PERSIS dengan yang dipakai
pi_publisher_yolo.py (publish_detection & audio_player.play_track),
jadi kalau tes ini berhasil, bagian "reaksi saat DANGER" di script
utama juga pasti berhasil -- yang masih perlu diuji terpisah cuma
akurasi deteksi pose-nya sendiri (pakai pose_detector.py).

Cara pakai:
    # tes reaksi risk MEDIUM (danger zone + postur normal/crouching)
    export MQTT_PASSWORD=xxx
    python3 test_danger_scenario.py --risk medium

    # tes reaksi risk HIGH (danger zone + climbing) -- termasuk audio track kedua
    python3 test_danger_scenario.py --risk high

    # tes tanpa audio fisik (belum ada hardware DFPlayer terpasang)
    python3 test_danger_scenario.py --risk high   # AUDIO_ENABLED default 0, aman
"""

import argparse
import json
import os
import ssl
import sys
import time
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

# dfplayer.py sekarang ada di folder app/, bukan sefolder dengan test ini
# (test ini ada di folder tests/) -- tambahkan app/ ke sys.path dulu
# sebelum import, supaya tidak ModuleNotFoundError.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))
# Konfigurasi terpusat: otomatis membaca env var & file config/.env
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config.settings import (  # noqa: E402
    AUDIO_ENABLED,
    AUDIO_TRACK_HIGH,
    AUDIO_TRACK_MEDIUM,
    CAMERA_ID,
    DFPLAYER_PORT,
    DFPLAYER_VOLUME,
    LOCATION,
    MQTT_HOST,
    MQTT_PASSWORD,
    MQTT_PORT,
    MQTT_USERNAME,
    TOPIC,
)
from dfplayer import get_audio_player


def build_client():
    client = mqtt.Client(client_id=f"saferise_test_danger_{int(time.time())}", protocol=mqtt.MQTTv311)
    client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    client.tls_set(cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLS_CLIENT)

    def on_connect(c, userdata, flags, rc):
        print(f"[MQTT] {'connected' if rc == 0 else f'GAGAL connect rc={rc}'} to {MQTT_HOST}:{MQTT_PORT}")

    client.on_connect = on_connect
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
    client.loop_start()
    return client


def publish_detection(client, status, confidence, posture):
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


def main():
    parser = argparse.ArgumentParser(description="Simulasi skenario DANGER SafeRise")
    parser.add_argument("--risk", choices=["medium", "high"], default="high", help="tingkat risiko yang disimulasikan")
    parser.add_argument("--hold-seconds", type=int, default=8, help="berapa lama status DANGER 'ditahan' sebelum kembali NORMAL")
    args = parser.parse_args()

    if not MQTT_PASSWORD:
        print("[PERINGATAN] MQTT_PASSWORD kosong -- isi di config/.env atau export manual")

    posture = "climbing" if args.risk == "high" else "normal"
    track = AUDIO_TRACK_HIGH if args.risk == "high" else AUDIO_TRACK_MEDIUM

    print(f"[INFO] Simulasi risk={args.risk} (posture={posture}, audio track={track})")

    client = build_client()
    audio_player = get_audio_player(AUDIO_ENABLED, DFPLAYER_PORT, DFPLAYER_VOLUME)

    time.sleep(2)  # tunggu MQTT connect selesai

    # --- Ini yang terjadi di pi_publisher_yolo.py saat status jadi DANGER ---
    print("\n>>> Memicu status DANGER (2 aksi bersamaan, sesuai flowchart proposal) <<<")
    publish_detection(client, "DANGER", confidence=0.91, posture=posture)
    audio_player.play_track(track)

    print(f"\n[INFO] Menahan status DANGER selama {args.hold_seconds} detik (cek app Flutter & speaker sekarang)...")
    time.sleep(args.hold_seconds)

    # --- Kembali NORMAL, audio berhenti ---
    print("\n>>> Kembali ke status NORMAL <<<")
    publish_detection(client, "NORMAL", confidence=1.0, posture="normal")
    audio_player.stop()

    time.sleep(1)
    audio_player.close()
    client.loop_stop()
    client.disconnect()

    print("\n=== SELESAI ===")
    print("Yang perlu kamu cek secara manual:")
    print("  1. App Flutter: apakah Critical Alert Card muncul saat DANGER, hilang saat NORMAL?")
    print("  2. Speaker (kalau AUDIO_ENABLED=1): apakah pesan audio benar-benar berbunyi?")
    print("  3. Riwayat deteksi di app: apakah posture tersimpan sesuai (climbing/normal)?")


if __name__ == "__main__":
    main()
