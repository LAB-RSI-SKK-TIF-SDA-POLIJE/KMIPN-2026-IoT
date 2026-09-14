"""Shared, dependency-light danger-zone and YOLO pose classification helpers."""

from __future__ import annotations

import numpy as np


LEFT_SHOULDER, RIGHT_SHOULDER = 5, 6
LEFT_HIP, RIGHT_HIP = 11, 12
LEFT_KNEE, RIGHT_KNEE = 13, 14
LEFT_ANKLE, RIGHT_ANKLE = 15, 16


def validate_danger_zone(points, frame_width: int, frame_height: int) -> None:
    """Raise a clear error when a calibrated polygon cannot match a frame."""
    if frame_width <= 0 or frame_height <= 0:
        raise ValueError("Frame dimensions must be positive")
    if len(points) < 3:
        raise ValueError("DANGER_ZONE_POINTS must contain at least three points")
    invalid = [
        (x, y)
        for x, y in points
        if x < 0 or y < 0 or x >= frame_width or y >= frame_height
    ]
    if invalid:
        raise ValueError(
            "DANGER_ZONE_POINTS contains points outside the configured "
            f"{frame_width}x{frame_height} frame: {invalid}. "
            "Recalibrate with scripts/calibrate_zone.py."
        )


def knee_angle(hip, knee, ankle) -> float:
    v1 = np.array(hip) - np.array(knee)
    v2 = np.array(ankle) - np.array(knee)
    cosine = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-6)
    return float(np.degrees(np.arccos(np.clip(cosine, -1.0, 1.0))))


MIN_VALID_KEYPOINTS = 4  # minimal 4 dari 8 keypoint inti (angle ke atas mungkin tidak lihat ankle)


def analyze_person_pose(
    keypoints_xy,
    keypoints_conf,
    *,
    keypoint_conf_threshold: float,
    narrow_stance_ratio: float,
    leg_raised_ratio: float,
    crouch_knee_angle_max: float,
):
    """Return ``(foot_point, posture)`` where posture is normal/climbing/crouching."""

    def get(index):
        if keypoints_conf[index] >= keypoint_conf_threshold:
            return keypoints_xy[index]
        return None

    left_ankle, right_ankle = get(LEFT_ANKLE), get(RIGHT_ANKLE)
    left_shoulder, right_shoulder = get(LEFT_SHOULDER), get(RIGHT_SHOULDER)
    left_hip, right_hip = get(LEFT_HIP), get(RIGHT_HIP)
    left_knee, right_knee = get(LEFT_KNEE), get(RIGHT_KNEE)

    # Foot point: ankle jika ada, fallback ke hip
    ankles = [p for p in (left_ankle, right_ankle) if p is not None]
    if ankles:
        foot_point = tuple(np.mean(ankles, axis=0))
    else:
        hips = [p for p in (left_hip, right_hip) if p is not None]
        foot_point = tuple(np.mean(hips, axis=0)) if hips else None

    # Validasi: pastikan cukup banyak keypoint inti yang terdeteksi.
    # Anjing/hewan menghasilkan keypoint palsu yang sedikit -> skip.
    # Angle ke atas: ankle mungkin tidak terlihat, cukup shoulder+hip+knee.
    core_keypoints = [left_shoulder, right_shoulder, left_hip, right_hip,
                      left_knee, right_knee, left_ankle, right_ankle]
    num_valid = sum(1 for p in core_keypoints if p is not None)
    if num_valid < MIN_VALID_KEYPOINTS:
        return foot_point, "normal"

    ankles = [point for point in (left_ankle, right_ankle) if point is not None]
    if ankles:
        foot_point = tuple(np.mean(ankles, axis=0))
    else:
        hips = [point for point in (left_hip, right_hip) if point is not None]
        foot_point = tuple(np.mean(hips, axis=0)) if hips else None

    leg_points = (left_hip, left_knee, left_ankle, right_hip, right_knee, right_ankle)
    if all(point is not None for point in leg_points):
        left_angle = knee_angle(left_hip, left_knee, left_ankle)
        right_angle = knee_angle(right_hip, right_knee, right_ankle)
        if left_angle < crouch_knee_angle_max and right_angle < crouch_knee_angle_max:
            return foot_point, "crouching"

    narrow_stance = False
    if all(point is not None for point in (left_ankle, right_ankle, left_shoulder, right_shoulder)):
        ankle_distance = abs(left_ankle[0] - right_ankle[0])
        shoulder_distance = abs(left_shoulder[0] - right_shoulder[0]) + 1e-6
        narrow_stance = (ankle_distance / shoulder_distance) < narrow_stance_ratio

    leg_raised = False
    if all(point is not None for point in (left_ankle, right_ankle, left_hip, right_hip)):
        left_length = abs(left_ankle[1] - left_hip[1])
        right_length = abs(right_ankle[1] - right_hip[1])
        average_length = (left_length + right_length) / 2 + 1e-6
        leg_raised = abs(left_ankle[1] - right_ankle[1]) / average_length > leg_raised_ratio

    return foot_point, "climbing" if narrow_stance or leg_raised else "normal"
