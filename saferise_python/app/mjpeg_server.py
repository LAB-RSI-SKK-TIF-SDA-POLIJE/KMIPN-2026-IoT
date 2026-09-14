"""
SafeRise - MJPEG HTTP Server
=============================

Server HTTP ringan yang broadcast frame kamera (yang sudah dianotasi
dengan danger zone + bounding box) sebagai motion-JPEG stream, supaya
Flutter app bisa menampilkan "live camera" tanpa perlu setup RTSP yang
lebih berat untuk Raspberry Pi 3.

Cara kerja:
    - Loop utama di pi_publisher_yolo.py memanggil update_frame(frame)
      tiap iterasi, menyimpan JPEG terbaru di memori (thread-safe).
    - Client (browser/Flutter) yang GET /stream menerima potongan JPEG
      terus-menerus (multipart/x-mixed-replace) -- ini yang membuatnya
      terlihat seperti video walau sebenarnya rangkaian foto.
    - GET /snapshot mengembalikan SATU JPEG terbaru saja (buat thumbnail
      di halaman daftar kamera, tidak perlu buka stream penuh).

Cara tes cepat dari browser laptop (tanpa Flutter):
    http://<ip-laptop-atau-pi>:8000/stream
    http://<ip-laptop-atau-pi>:8000/snapshot

Kenapa bukan Flask: supaya dependency tetap minimal (cukup http.server
bawaan Python), konsisten dengan filosofi dfplayer.py.
"""

import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Optional

import cv2


class _LatestFrame:
    """Buffer JPEG terbaru, aman diakses dari banyak thread sekaligus
    (loop utama menulis, tiap client MJPEG connection membaca)."""

    def __init__(self):
        self._lock = threading.Lock()
        self._jpeg_bytes: Optional[bytes] = None

    def update(self, jpeg_bytes: bytes):
        with self._lock:
            self._jpeg_bytes = jpeg_bytes

    def get(self) -> Optional[bytes]:
        with self._lock:
            return self._jpeg_bytes


class _MjpegHandler(BaseHTTPRequestHandler):
    # di-set oleh MjpegServer lewat `type(...)` sebelum server dijalankan
    latest_frame: _LatestFrame = None  # type: ignore
    stream_fps: int = 10

    def log_message(self, format, *args):
        pass  # bungkam log http.server bawaan yang berisik di terminal

    def do_GET(self):
        if self.path == "/stream":
            self._serve_stream()
        elif self.path == "/snapshot":
            self._serve_snapshot()
        else:
            self.send_response(404)
            self.end_headers()

    def _serve_snapshot(self):
        jpeg = self.latest_frame.get()
        if jpeg is None:
            self.send_response(503)  # belum ada frame sama sekali
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(jpeg)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(jpeg)

    def _serve_stream(self):
        self.send_response(200)
        self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=saferiseframe")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        interval = 1.0 / max(1, self.stream_fps)
        try:
            while True:
                jpeg = self.latest_frame.get()
                if jpeg is not None:
                    self.wfile.write(b"--saferiseframe\r\n")
                    self.wfile.write(b"Content-Type: image/jpeg\r\n")
                    self.wfile.write(f"Content-Length: {len(jpeg)}\r\n\r\n".encode())
                    self.wfile.write(jpeg)
                    self.wfile.write(b"\r\n")
                time.sleep(interval)
        except (BrokenPipeError, ConnectionResetError):
            # client (Flutter/browser) menutup koneksi -- normal, bukan error
            pass


class MjpegServer:
    """Panggil start() sekali di awal program, update_frame(...) tiap
    iterasi loop kamera, dan stop() saat program berhenti."""

    def __init__(self, port: int = 8000, jpeg_quality: int = 70, stream_fps: int = 10):
        self.port = port
        self.jpeg_quality = jpeg_quality
        self._latest = _LatestFrame()

        # Bikin subclass handler yang "tahu" instance _latest & fps ini,
        # karena BaseHTTPRequestHandler diinstansiasi ulang oleh
        # http.server untuk tiap request, jadi tidak bisa lewat __init__.
        handler = type(
            "_BoundMjpegHandler",
            (_MjpegHandler,),
            {"latest_frame": self._latest, "stream_fps": stream_fps},
        )
        self._server = ThreadingHTTPServer(("0.0.0.0", port), handler)
        self._thread: Optional[threading.Thread] = None

    def start(self):
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()

    def update_frame(self, frame_bgr):
        ok, buf = cv2.imencode(".jpg", frame_bgr, [cv2.IMWRITE_JPEG_QUALITY, self.jpeg_quality])
        if ok:
            self._latest.update(buf.tobytes())

    def stop(self):
        self._server.shutdown()
        self._server.server_close()
