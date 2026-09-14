"""SafeRise Pi Camera 3 + DFPlayer agent.

Run this on the Raspberry Pi 3. It keeps CPU-heavy pose inference off the Pi:
- rpicam-vid hardware-encodes Camera Module 3 output as H.264 over TCP;
- this process subscribes to MQTT PLAY/STOP commands and controls the local
  DFPlayer Mini speaker.

Laptop inference reads tcp://<PI_LAN_IP>:<STREAM_PORT> and publishes commands
on ALARM_COMMAND_TOPIC. Use a trusted LAN; the raw H.264 TCP stream has no
transport encryption or authentication.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import paho.mqtt.client as mqtt

from config.settings import (  # noqa: E402
    ALARM_COMMAND_TOPIC,
    ALARM_MQTT_HOST,
    ALARM_MQTT_PASSWORD,
    ALARM_MQTT_PORT,
    ALARM_MQTT_TLS_ENABLED,
    ALARM_MQTT_USERNAME,
    ALARM_MQTT_USES_LOCAL_BROKER,
    AUDIO_ENABLED,
    AUDIO_TRACK_HIGH,
    AUDIO_TRACK_MEDIUM,
    CAMERA_ID,
    DFPLAYER_PORT,
    DFPLAYER_VOLUME,
    FRAME_HEIGHT,
    FRAME_WIDTH,
    STREAM_FPS,
    STREAM_PORT,
)
from dfplayer import get_audio_player  # noqa: E402


def stream_command() -> list[str]:
    executable = shutil.which("rpicam-vid") or shutil.which("libcamera-vid")
    if not executable:
        raise RuntimeError(
            "rpicam-vid/libcamera-vid tidak ditemukan. Install Raspberry Pi OS "
            "Bookworm camera stack, aktifkan Camera Module 3, lalu coba lagi."
        )
    return [
        executable,
        "--timeout", "0",
        "--nopreview",
        "--width", str(FRAME_WIDTH),
        "--height", str(FRAME_HEIGHT),
        "--framerate", str(STREAM_FPS),
        "--codec", "h264",
        "--inline",
        "--listen",
        "--output", f"tcp://0.0.0.0:{STREAM_PORT}",
    ]


def main() -> None:
    player = get_audio_player(AUDIO_ENABLED, DFPLAYER_PORT, DFPLAYER_VOLUME)
    process = subprocess.Popen(stream_command())
    client = mqtt.Client(client_id=f"saferise_pi_agent_{CAMERA_ID}", protocol=mqtt.MQTTv311)
    if ALARM_MQTT_USERNAME:
        client.username_pw_set(ALARM_MQTT_USERNAME, ALARM_MQTT_PASSWORD)
    if ALARM_MQTT_TLS_ENABLED:
        client.tls_set()

    broker_kind = "Mosquitto LOKAL" if ALARM_MQTT_USES_LOCAL_BROKER else "HiveMQ Cloud (fallback, LOCAL_MQTT_HOST kosong)"
    print(f"[MQTT] alarm command broker: {broker_kind} -> {ALARM_MQTT_HOST}:{ALARM_MQTT_PORT}")

    def on_connect(mqtt_client, userdata, flags, rc):
        if rc == 0:
            mqtt_client.subscribe(ALARM_COMMAND_TOPIC, qos=1)
            print(f"[MQTT] subscribed: {ALARM_COMMAND_TOPIC}")
        else:
            print(f"[MQTT] connect failed, rc={rc}")

    def on_message(mqtt_client, userdata, message):
        try:
            command = json.loads(message.payload.decode("utf-8"))
            action = command["action"].upper()
        except (UnicodeDecodeError, json.JSONDecodeError, KeyError, AttributeError) as exc:
            print(f"[ALARM] ignored invalid command: {exc}")
            return

        if action == "PLAY":
            risk = command.get("risk", "medium").lower()
            track = AUDIO_TRACK_HIGH if risk == "high" else AUDIO_TRACK_MEDIUM
            player.play_track(track)
            print(f"[ALARM] PLAY risk={risk}, track={track}")
        elif action == "STOP":
            player.stop()
            print("[ALARM] STOP")
        else:
            print(f"[ALARM] ignored unsupported action: {action}")

    client.on_connect = on_connect
    client.on_message = on_message
    try:
        client.connect(ALARM_MQTT_HOST, ALARM_MQTT_PORT, keepalive=30)
        client.loop_start()
        print(f"[STREAM] H.264 TCP listening at tcp://0.0.0.0:{STREAM_PORT}")
        while process.poll() is None:
            time.sleep(1)
        raise RuntimeError(f"Camera stream exited with code {process.returncode}")
    except KeyboardInterrupt:
        print("Stopping Pi agent...")
    finally:
        player.stop()
        player.close()
        client.loop_stop()
        client.disconnect()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


if __name__ == "__main__":
    main()
