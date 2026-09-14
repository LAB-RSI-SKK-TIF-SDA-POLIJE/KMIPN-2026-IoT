"""
SafeRise - Tool Kalibrasi Danger Zone
======================================

Tujuan: membantu kamu menentukan DANGER_ZONE_POINTS tanpa harus menebak
koordinat. Jalankan file ini, sebuah jendela kamera akan muncul, lalu:

  - KLIK KIRI di titik-titik yang membentuk sudut area berbahaya
    (misalnya sudut-sudut dekat railing/tepi rooftop), urut searah
    jarum jam atau berlawanan (asal konsisten, jangan menyilang).
  - Tiap klik akan ditandai bulatan kuning + garis penghubung otomatis
    ke titik sebelumnya, supaya kamu bisa lihat bentuk polygon-nya
    langsung terbentuk secara live.
  - Tekan 'u' untuk UNDO titik terakhir kalau salah klik.
  - Tekan 'r' untuk RESET semua titik dan mulai ulang.
  - Tekan 's' untuk SELESAI -> koordinat final akan dicetak ke terminal
    dalam format yang tinggal copy-paste ke DANGER_ZONE_POINTS di
    config/.env.
  - Tekan 'q' untuk keluar tanpa menyimpan.
  - Tekan SPASI untuk PAUSE/RESUME (berguna saat pakai video file).

Cara pakai dengan kamera langsung:
    set CAMERA_BACKEND=opencv
    python calibrate_zone.py

Cara pakai dengan video file:
    set CAMERA_SOURCE=D:\\video.mp4
    python calibrate_zone.py
"""

import os
import sys

import cv2
import numpy as np

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from config.settings import CAMERA_BACKEND, CAMERA_SOURCE, FRAME_HEIGHT, FRAME_WIDTH  # noqa: E402

points = []  # daftar titik (x, y) yang sudah diklik


def on_mouse(event, x, y, flags, userdata):
    if event == cv2.EVENT_LBUTTONDOWN:
        points.append((x, y))
        print(f"[TITIK #{len(points)}] ({x}, {y})")


def get_frame_source():
    is_video = not CAMERA_SOURCE.isdigit() and os.path.isfile(CAMERA_SOURCE)
    if CAMERA_BACKEND == "picamera2":
        from picamera2 import Picamera2

        picam2 = Picamera2()
        config = picam2.create_video_configuration(
            main={"size": (FRAME_WIDTH, FRAME_HEIGHT), "format": "RGB888"}
        )
        picam2.configure(config)
        picam2.start()

        def read():
            frame = picam2.capture_array()
            return True, cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)

        return read, picam2.stop, False
    else:
        source = int(CAMERA_SOURCE) if CAMERA_SOURCE.isdigit() else CAMERA_SOURCE
        cap = cv2.VideoCapture(source)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
        if not cap.isOpened():
            raise RuntimeError(f"Tidak bisa membuka kamera/video: {source}")

        def read_video():
            ok, frame = cap.read()
            if not ok and is_video:
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                return cap.read()
            return ok, frame

        return read_video, cap.release, is_video


def main():
    read_frame, release, is_video = get_frame_source()

    window_name = "SafeRise - Kalibrasi Danger Zone"
    cv2.namedWindow(window_name)
    cv2.setMouseCallback(window_name, on_mouse)

    paused = False
    last_frame = None

    print("=" * 60)
    print("Klik kiri untuk menandai sudut danger zone.")
    print("Tombol: u=undo, r=reset, s=selesai, q=keluar, spasi=pause/resume")
    if is_video:
        print("Mode: VIDEO FILE (loop otomatis)")
    print("=" * 60)

    try:
        while True:
            if not paused:
                ok, frame = read_frame()
                if not ok:
                    print("[CAM] gagal membaca frame")
                    continue
                if is_video:
                    frame = cv2.resize(frame, (FRAME_WIDTH, FRAME_HEIGHT))
                last_frame = frame

            display = last_frame.copy()

            for i, p in enumerate(points):
                cv2.circle(display, p, 5, (0, 255, 255), -1)
                cv2.putText(
                    display, str(i + 1), (p[0] + 8, p[1] - 8),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1,
                )
                if i > 0:
                    cv2.line(display, points[i - 1], p, (0, 255, 255), 2)

            if len(points) >= 3:
                cv2.line(display, points[-1], points[0], (0, 165, 255), 1)

            status = "PAUSED" if paused else "LIVE"
            cv2.putText(
                display, f"Titik: {len(points)}  [{status}]  (u=undo r=reset s=selesai q=keluar spasi=pause)",
                (10, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1,
            )

            cv2.imshow(window_name, display)
            key = cv2.waitKey(1 if not paused else 50) & 0xFF

            if key == ord("q"):
                print("Keluar tanpa menyimpan.")
                break
            elif key == ord(" "):
                paused = not paused
                print(f"[{'PAUSE' if paused else 'RESUME'}]")
            elif key == ord("u") and points:
                removed = points.pop()
                print(f"[UNDO] menghapus titik {removed}")
            elif key == ord("r"):
                points.clear()
                print("[RESET] semua titik dihapus")
            elif key == ord("s"):
                if len(points) < 3:
                    print("Minimal butuh 3 titik untuk membentuk polygon, klik dulu.")
                    continue
                print("\n" + "=" * 60)
                print("HASIL KALIBRASI -- tambahkan ke config/.env:")
                print("=" * 60)
                print("DANGER_ZONE_POINTS=" + str([[x, y] for x, y in points]).replace(" ", ""))
                print("\nRestart publisher setelah menyimpan config/.env.")
                print("=" * 60)
                break

    finally:
        release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
