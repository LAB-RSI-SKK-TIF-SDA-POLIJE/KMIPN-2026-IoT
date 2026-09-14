"""
SafeRise - Pose Detector (standalone, tanpa zona & MQTT)
=========================================================

Tujuan file ini: menguji & mengkalibrasi klasifikasi POSTUR saja
(NORMAL / CLIMBING / CROUCHING / UNKNOWN) dari keypoint YOLOv8-pose,
sebelum digabung dengan danger zone + publish MQTT di
pi_publisher_yolo.py.

Kategori postur:
- NORMAL     : berdiri wajar, kedua kaki cukup lebar & sejajar.
- CLIMBING   : indikasi memanjat/berdiri di permukaan sempit --
               narrow_stance ATAU leg_raised terpenuhi, DAN bukan
               crouching (lihat di bawah).
- CROUCHING  : jongkok/menunduk -- lutut sangat menekuk (hip dekat
               ke ketinggian lutut). Sengaja dipisah dari CLIMBING
               karena orang jongkok (mis. bersih-bersih, mengikat
               tali sepatu) bisa salah kepicu leg_raised padahal
               bukan pose memanjat.
- UNKNOWN    : keypoint kunci (ankle/hip/shoulder) tidak cukup yakin
               terdeteksi (mis. tertutup objek / sudut kamera jelek)
               untuk dihitung.

Cara pakai:
    # webcam laptop
    python3 pose_detector.py --source 0

    # video rekaman simulasi
    python3 pose_detector.py --source test_rooftop.mp4

Kontrol saat preview jalan:
    q       : keluar
    s       : simpan frame saat ini (buat dokumentasi laporan)
    +/-     : naik/turun NARROW_STANCE_RATIO on-the-fly
    [ / ]   : naik/turun LEG_RAISED_RATIO on-the-fly
    (nilai ratio ditampilkan live di layar & dicetak ke terminal
     tiap kali diubah, supaya gampang cari angka yang pas)

Setelah dapat angka yang pas dari sesi kalibrasi ini, salin nilai
NARROW_STANCE_RATIO / LEG_RAISED_RATIO / CROUCH_KNEE_ANGLE_MAX ke
pi_publisher_yolo.py.
"""

import argparse
import os
import time

import cv2
import numpy as np
from ultralytics import YOLO

_DEFAULT_MODEL = os.path.join(os.path.dirname(__file__), "..", "models", "yolov8n-pose.pt")

# ----------------------------------------------------------------------
# Index keypoint format COCO (dipakai YOLOv8-pose)
# ----------------------------------------------------------------------
LEFT_SHOULDER, RIGHT_SHOULDER = 5, 6
LEFT_HIP, RIGHT_HIP = 11, 12
LEFT_KNEE, RIGHT_KNEE = 13, 14
LEFT_ANKLE, RIGHT_ANKLE = 15, 16

KEYPOINT_CONF_THRESHOLD = 0.3

# ----------------------------------------------------------------------
# Threshold awal -- akan dikalibrasi live saat preview jalan
# ----------------------------------------------------------------------
NARROW_STANCE_RATIO = 0.35  # ankle_dist / shoulder_dist < ini -> kaki rapat
LEG_RAISED_RATIO = 0.30  # selisih tinggi ankle / panjang kaki rata-rata > ini -> satu kaki terangkat
CROUCH_KNEE_ANGLE_MAX = 140.0  # derajat. sudut hip-knee-ankle < ini di KEDUA kaki -> dianggap jongkok

POSE_COLORS = {
    "NORMAL": (0, 255, 0),
    "CLIMBING": (0, 0, 255),
    "CROUCHING": (0, 165, 255),
    "UNKNOWN": (160, 160, 160),
}


def get_point(keypoints_xy, keypoints_conf, idx):
    if keypoints_conf[idx] >= KEYPOINT_CONF_THRESHOLD:
        return keypoints_xy[idx]
    return None


def knee_angle(hip, knee, ankle):
    """Sudut di titik lutut, dibentuk oleh vektor lutut->hip dan lutut->ankle.
    ~180 derajat = kaki lurus (berdiri normal).
    Semakin kecil = lutut semakin menekuk (jongkok/memanjat dengan lutut ditekuk)."""
    v1 = np.array(hip) - np.array(knee)
    v2 = np.array(ankle) - np.array(knee)
    cos_angle = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-6)
    cos_angle = np.clip(cos_angle, -1.0, 1.0)
    return np.degrees(np.arccos(cos_angle))


def classify_pose(keypoints_xy, keypoints_conf):
    """
    Return dict berisi:
      - label: "NORMAL" | "CLIMBING" | "CROUCHING" | "UNKNOWN"
      - foot_point: titik acuan posisi kaki (buat dipakai zona nanti)
      - debug: nilai-nilai ratio/sudut mentah, buat ditampilkan di layar
        saat kalibrasi
    """
    left_ankle = get_point(keypoints_xy, keypoints_conf, LEFT_ANKLE)
    right_ankle = get_point(keypoints_xy, keypoints_conf, RIGHT_ANKLE)
    left_shoulder = get_point(keypoints_xy, keypoints_conf, LEFT_SHOULDER)
    right_shoulder = get_point(keypoints_xy, keypoints_conf, RIGHT_SHOULDER)
    left_hip = get_point(keypoints_xy, keypoints_conf, LEFT_HIP)
    right_hip = get_point(keypoints_xy, keypoints_conf, RIGHT_HIP)
    left_knee = get_point(keypoints_xy, keypoints_conf, LEFT_KNEE)
    right_knee = get_point(keypoints_xy, keypoints_conf, RIGHT_KNEE)

    debug = {}

    # foot point (rata-rata ankle, fallback ke hip)
    ankles = [p for p in (left_ankle, right_ankle) if p is not None]
    if ankles:
        foot_point = tuple(np.mean(ankles, axis=0))
    else:
        hips = [p for p in (left_hip, right_hip) if p is not None]
        foot_point = tuple(np.mean(hips, axis=0)) if hips else None

    # perlu minimal ankle + shoulder + hip untuk klasifikasi yang bermakna
    have_core = all(p is not None for p in (left_ankle, right_ankle, left_shoulder, right_shoulder, left_hip, right_hip))
    if not have_core:
        return {"label": "UNKNOWN", "foot_point": foot_point, "debug": debug}

    # --- narrow stance ---
    ankle_dist = abs(left_ankle[0] - right_ankle[0])
    shoulder_dist = abs(left_shoulder[0] - right_shoulder[0]) + 1e-6
    narrow_ratio = ankle_dist / shoulder_dist
    narrow_stance = narrow_ratio < NARROW_STANCE_RATIO
    debug["narrow_ratio"] = narrow_ratio

    # --- leg raised ---
    left_leg_len = abs(left_ankle[1] - left_hip[1])
    right_leg_len = abs(right_ankle[1] - right_hip[1])
    avg_leg_len = (left_leg_len + right_leg_len) / 2 + 1e-6
    ankle_height_diff = abs(left_ankle[1] - right_ankle[1])
    leg_raised_ratio = ankle_height_diff / avg_leg_len
    leg_raised = leg_raised_ratio > LEG_RAISED_RATIO
    debug["leg_raised_ratio"] = leg_raised_ratio

    # --- crouching (butuh knee, kalau tidak ada -> anggap tidak crouching) ---
    crouching = False
    if left_knee is not None and right_knee is not None:
        left_angle = knee_angle(left_hip, left_knee, left_ankle)
        right_angle = knee_angle(right_hip, right_knee, right_ankle)
        debug["left_knee_angle"] = left_angle
        debug["right_knee_angle"] = right_angle
        # kedua lutut menekuk tajam -> jongkok, bukan cuma satu kaki
        # terangkat sedikit
        crouching = left_angle < CROUCH_KNEE_ANGLE_MAX and right_angle < CROUCH_KNEE_ANGLE_MAX

    if crouching:
        label = "CROUCHING"
    elif narrow_stance or leg_raised:
        label = "CLIMBING"
    else:
        label = "NORMAL"

    return {"label": label, "foot_point": foot_point, "debug": debug}


def draw_result(frame, box_xyxy, result):
    x1, y1, x2, y2 = [int(v) for v in box_xyxy]
    label = result["label"]
    color = POSE_COLORS[label]
    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
    cv2.putText(frame, label, (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)

    if result["foot_point"] is not None:
        fx, fy = result["foot_point"]
        cv2.circle(frame, (int(fx), int(fy)), 5, color, -1)

    # tampilkan angka debug kecil di bawah box, berguna saat kalibrasi
    debug = result["debug"]
    y_text = y2 + 16
    for key, val in debug.items():
        cv2.putText(frame, f"{key}: {val:.2f}", (x1, y_text), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (255, 255, 255), 1)
        y_text += 15


def main():
    parser = argparse.ArgumentParser(description="SafeRise pose-only detector (kalibrasi)")
    parser.add_argument("--source", default="0", help="index webcam (0) atau path file video")
    parser.add_argument("--model", default=_DEFAULT_MODEL, help="path model YOLO pose")
    parser.add_argument("--conf", type=float, default=0.5, help="confidence threshold YOLO")
    args = parser.parse_args()

    global NARROW_STANCE_RATIO, LEG_RAISED_RATIO

    print(f"[YOLO] loading model: {args.model}")
    model = YOLO(args.model)

    source = int(args.source) if args.source.isdigit() else args.source
    cap = cv2.VideoCapture(source)
    if not cap.isOpened():
        raise RuntimeError(f"Tidak bisa membuka sumber: {args.source}")

    save_count = 0
    print("[INFO] q=keluar, s=simpan frame, +/-=narrow_stance ratio, [ / ]=leg_raised ratio")

    while True:
        ok, frame = cap.read()
        if not ok:
            print("[CAM] gagal membaca frame / video selesai")
            break

        results = model.predict(frame, conf=args.conf, verbose=False)[0]
        boxes = results.boxes
        keypoints = results.keypoints
        num_people = len(boxes) if boxes is not None else 0

        for i in range(num_people):
            x1, y1, x2, y2 = boxes.xyxy[i].tolist()
            if keypoints is not None:
                kp_xy = keypoints.xy[i].cpu().numpy()
                kp_conf = keypoints.conf[i].cpu().numpy()
                result = classify_pose(kp_xy, kp_conf)
            else:
                result = {"label": "UNKNOWN", "foot_point": None, "debug": {}}
            draw_result(frame, (x1, y1, x2, y2), result)

        cv2.putText(
            frame,
            f"narrow={NARROW_STANCE_RATIO:.2f} leg_raised={LEG_RAISED_RATIO:.2f} crouch_angle<{CROUCH_KNEE_ANGLE_MAX:.0f}",
            (10, 20),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (255, 255, 0),
            1,
        )
        cv2.imshow("SafeRise - Pose Detector (kalibrasi)", frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            break
        elif key == ord("s"):
            fname = f"pose_calib_{save_count}.jpg"
            cv2.imwrite(fname, frame)
            print(f"[SAVE] {fname}")
            save_count += 1
        elif key in (ord("+"), ord("=")):
            NARROW_STANCE_RATIO = round(NARROW_STANCE_RATIO + 0.02, 2)
            print(f"[CALIBRATE] NARROW_STANCE_RATIO -> {NARROW_STANCE_RATIO}")
        elif key == ord("-"):
            NARROW_STANCE_RATIO = round(max(0.0, NARROW_STANCE_RATIO - 0.02), 2)
            print(f"[CALIBRATE] NARROW_STANCE_RATIO -> {NARROW_STANCE_RATIO}")
        elif key == ord("]"):
            LEG_RAISED_RATIO = round(LEG_RAISED_RATIO + 0.02, 2)
            print(f"[CALIBRATE] LEG_RAISED_RATIO -> {LEG_RAISED_RATIO}")
        elif key == ord("["):
            LEG_RAISED_RATIO = round(max(0.0, LEG_RAISED_RATIO - 0.02), 2)
            print(f"[CALIBRATE] LEG_RAISED_RATIO -> {LEG_RAISED_RATIO}")

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
