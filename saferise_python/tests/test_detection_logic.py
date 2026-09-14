import os
import sys
import unittest

import numpy as np

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
APP_DIR = os.path.join(PROJECT_ROOT, "app")
for path in (PROJECT_ROOT, APP_DIR):
    if path not in sys.path:
        sys.path.insert(0, path)

from app.detection_logic import analyze_person_pose, validate_danger_zone
from config.settings import DANGER_ZONE_POINTS, FRAME_HEIGHT, FRAME_WIDTH


class DetectionLogicTests(unittest.TestCase):
    def test_default_zone_is_inside_default_frame(self):
        validate_danger_zone(DANGER_ZONE_POINTS, FRAME_WIDTH, FRAME_HEIGHT)

    def test_out_of_frame_zone_fails_fast(self):
        with self.assertRaises(ValueError):
            validate_danger_zone([[0, 0], [320, 0], [0, 239]], 320, 240)

    def test_complete_numpy_keypoints_do_not_crash_and_detect_crouching(self):
        keypoints = np.zeros((17, 2), dtype=float)
        confidence = np.ones(17, dtype=float)
        # Both knees form a 90-degree angle with hip and ankle.
        keypoints[5], keypoints[6] = (-1, -2), (1, -2)
        keypoints[11], keypoints[12] = (-1, 0), (1, 0)
        keypoints[13], keypoints[14] = (0, 0), (2, 0)
        keypoints[15], keypoints[16] = (0, 1), (2, 1)

        foot, posture = analyze_person_pose(
            keypoints,
            confidence,
            keypoint_conf_threshold=0.3,
            narrow_stance_ratio=0.35,
            leg_raised_ratio=0.30,
            crouch_knee_angle_max=140.0,
        )

        self.assertEqual(posture, "crouching")
        self.assertEqual(foot, (1.0, 1.0))


if __name__ == "__main__":
    unittest.main()
