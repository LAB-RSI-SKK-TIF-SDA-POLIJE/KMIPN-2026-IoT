"""SafeRise - Simple Camera Viewer
==================================

Tampilan kamera bersih tanpa overlay danger zone, bounding box, atau
deteksi YOLO. Hanya menampilkan feed mentah dari Kamera Module 3
yang di-stream oleh pi_camera_alarm_agent.py.

Cara pakai:
    set STREAM_URL=tcp://192.168.1.50:8888
    python app/camera_viewer.py

Atau langsung via argumen:
    python app/camera_viewer.py tcp://192.168.1.50:8888

Tekan 'q' atau ESC untuk keluar.
Tekan 'f' untuk toggle fullscreen.
Tekan 's' untuk screenshot (tersimpan di folder screenshots/).
"""

from __future__ import annotations

import os
import sys
import time
from datetime import datetime

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
APP_DIR = os.path.dirname(__file__)
for path in (PROJECT_ROOT, APP_DIR):
    if path not in sys.path:
        sys.path.insert(0, path)

import cv2

from config.settings import FRAME_HEIGHT, FRAME_WIDTH, STREAM_PORT, STREAM_URL


WINDOW_NAME = "SafeRise Camera Viewer"
SCREENSHOT_DIR = os.path.join(PROJECT_ROOT, "screenshots")


def get_stream_url() -> str:
    if len(sys.argv) > 1:
        return sys.argv[1]
    if STREAM_URL:
        return STREAM_URL
    return ""


def main() -> None:
    stream_url = get_stream_url()
    if not stream_url:
        print("[ERROR] STREAM_URL belum diset.")
        print("Contoh: python app/camera_viewer.py tcp://192.168.1.50:8888")
        print("Atau set env: set STREAM_URL=tcp://192.168.1.50:8888")
        sys.exit(1)

    print(f"[CAMERA] Connecting ke {stream_url} ...")
    capture = cv2.VideoCapture(stream_url)
    if not capture.isOpened():
        print(f"[ERROR] Tidak dapat membuka stream: {stream_url}")
        print("Pastikan Pi agent (pi_camera_alarm_agent.py) sedang berjalan.")
        sys.exit(1)

    is_video_file = os.path.isfile(stream_url)
    if is_video_file:
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
        print(f"[CAMERA] Video file mode! Resize ke Pi Camera resolusi: {FRAME_WIDTH}x{FRAME_HEIGHT}")
    else:
        print(f"[CAMERA] Stream connected!")
    print("[CAMERA] Tekan 'q'/ESC=keluar, 'f'=fullscreen, 's'=screenshot")

    is_fullscreen = False

    while True:
        ok, frame = capture.read()
        if not ok:
            if is_video_file:
                capture.set(cv2.CAP_PROP_POS_FRAMES, 0)
                continue
            print("[WARN] Frame gagal diterima, mencoba reconnect...")
            capture.release()
            time.sleep(2)
            capture = cv2.VideoCapture(stream_url)
            if not capture.isOpened():
                print("[ERROR] Reconnect gagal. Keluar.")
                break
            continue

        if is_video_file:
            frame = cv2.resize(frame, (FRAME_WIDTH, FRAME_HEIGHT))

        cv2.imshow(WINDOW_NAME, frame)

        key = cv2.waitKey(1) & 0xFF
        if key in (ord("q"), 27):
            break
        elif key == ord("f"):
            is_fullscreen = not is_fullscreen
            flag = cv2.WINDOW_FULLSCREEN if is_fullscreen else cv2.WINDOW_NORMAL
            cv2.setWindowProperty(WINDOW_NAME, cv2.WND_PROP_FULLSCREEN, flag)
        elif key == ord("s"):
            os.makedirs(SCREENSHOT_DIR, exist_ok=True)
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            path = os.path.join(SCREENSHOT_DIR, f"screenshot_{timestamp}.jpg")
            cv2.imwrite(path, frame)
            print(f"[SCREENSHOT] Tersimpan: {path}")

    capture.release()
    cv2.destroyAllWindows()
    print("[CAMERA] Selesai.")


if __name__ == "__main__":
    main()
