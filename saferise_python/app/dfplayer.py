"""
SafeRise - DFPlayer Mini Controller
====================================

Modul untuk mengontrol DFPlayer Mini via UART (protokol serial standar
DFPlayer, BUKAN library pihak ketiga -- supaya dependency minimal, cukup
pyserial yang sudah ringan untuk Pi).

Wiring ke Raspberry Pi (sesuai skema di proposal):
    DFPlayer RX -> Pi TX (GPIO14 / pin 8)   -- lewat resistor 1k disarankan
    DFPlayer TX -> Pi RX (GPIO15 / pin 10)
    DFPlayer VCC -> 5V
    DFPlayer GND -> GND
    Speaker -> terminal SPK_1/SPK_2 DFPlayer

PENTING sebelum pakai:
    1. Aktifkan UART di Pi: `sudo raspi-config` -> Interface Options ->
       Serial Port -> "login shell over serial" = NO, "serial hardware
       enabled" = YES. Reboot.
    2. Port serial biasanya /dev/serial0 atau /dev/ttyS0 (Pi 3/Zero 2 W)
       -- cek dengan `ls /dev/serial*` atau `ls /dev/ttyS*`.
    3. Siapkan microSD card untuk DFPlayer (FAT32), isi file MP3 di folder
       root, diberi nama urut: 0001.mp3, 0002.mp3, dst -- DFPlayer membaca
       berdasarkan urutan penulisan file ke kartu, bukan nama file semata,
       jadi copy file SATU PER SATU berurutan (bukan drag semua sekaligus)
       supaya track index-nya sesuai dugaan.
    4. Install dependency: pip install pyserial --break-system-packages

Cara pakai cepat (tes mandiri):
    python3 dfplayer.py --port /dev/serial0 --track 1 --volume 20
"""

import argparse
import time

import serial

START_BYTE = 0x7E
VERSION = 0xFF
END_BYTE = 0xEF
FEEDBACK_NONE = 0x00

# Command codes (subset yang relevan untuk SafeRise)
CMD_PLAY_TRACK = 0x03  # mainkan track ke-N (berdasar urutan penulisan ke SD)
CMD_SET_VOLUME = 0x06
CMD_STOP = 0x16
CMD_RESET = 0x0C


class DFPlayerMini:
    """Controller sederhana untuk DFPlayer Mini via UART."""

    def __init__(self, port: str, baudrate: int = 9600, timeout: float = 1.0):
        self.ser = serial.Serial(port, baudrate=baudrate, timeout=timeout)
        # DFPlayer butuh sedikit waktu warm-up setelah power-on/koneksi
        time.sleep(1.0)

    def _send(self, command: int, param1: int = 0, param2: int = 0):
        packet = bytearray(
            [START_BYTE, VERSION, 0x06, command, FEEDBACK_NONE, param1, param2]
        )
        checksum = 0xFFFF - sum(packet[1:7]) + 1
        packet.append((checksum >> 8) & 0xFF)
        packet.append(checksum & 0xFF)
        packet.append(END_BYTE)
        self.ser.write(bytes(packet))

    def play_track(self, track_number: int):
        """Mainkan file ke-N di kartu SD (1-indexed, sesuai urutan copy file)."""
        self._send(CMD_PLAY_TRACK, 0x00, track_number & 0xFF)

    def set_volume(self, volume: int):
        """Volume 0 (mute) - 30 (max)."""
        volume = max(0, min(30, volume))
        self._send(CMD_SET_VOLUME, 0x00, volume)

    def stop(self):
        self._send(CMD_STOP)

    def reset(self):
        self._send(CMD_RESET)
        time.sleep(1.5)  # DFPlayer butuh waktu re-init kartu SD setelah reset

    def close(self):
        self.ser.close()


class NullAudioPlayer:
    """
    Dipakai kalau AUDIO_ENABLED=0 atau DFPlayer belum terpasang (mis. saat
    testing di laptop tanpa hardware). Semua method jadi no-op + log,
    supaya pi_publisher_yolo.py tidak perlu percabangan if/else di
    banyak tempat.
    """

    def play_track(self, track_number: int):
        print(f"[DFPlayer:DUMMY] would play track {track_number}")

    def set_volume(self, volume: int):
        print(f"[DFPlayer:DUMMY] would set volume {volume}")

    def stop(self):
        print("[DFPlayer:DUMMY] would stop")

    def reset(self):
        print("[DFPlayer:DUMMY] would reset")

    def close(self):
        pass


def get_audio_player(enabled: bool, port: str, volume: int):
    """Factory: return DFPlayerMini asli kalau enabled & port valid, atau
    NullAudioPlayer kalau tidak (aman dipanggil dari lingkungan tanpa
    hardware, mis. laptop dev)."""
    if not enabled:
        print("[DFPlayer] AUDIO_ENABLED=0 -> pakai dummy player (tidak ada suara asli)")
        return NullAudioPlayer()
    try:
        player = DFPlayerMini(port)
        player.set_volume(volume)
        print(f"[DFPlayer] terhubung di {port}, volume={volume}")
        return player
    except Exception as e:
        print(f"[DFPlayer] GAGAL konek ke {port} ({e}) -> fallback ke dummy player")
        return NullAudioPlayer()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Tes mandiri DFPlayer Mini")
    parser.add_argument("--port", default="/dev/serial0")
    parser.add_argument("--track", type=int, default=1)
    parser.add_argument("--volume", type=int, default=20)
    args = parser.parse_args()

    player = DFPlayerMini(args.port)
    player.set_volume(args.volume)
    print(f"Memutar track {args.track}...")
    player.play_track(args.track)
    time.sleep(5)
    player.close()
