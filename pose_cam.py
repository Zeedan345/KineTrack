# pose_landmarks_simple.py
import cv2
import json
import time
import numpy as np
from datetime import datetime
from typing import Optional, Union, Dict, Any
import argparse
import os

import mediapipe as mp


def save_pose_landmarks_json(
    image: Union[bytes, str, np.ndarray],
    pose,
    *,
    image_id: Optional[str] = None,
    draw_overlay: bool = False,
    overlay_output_path: Optional[str] = None
) -> Dict[str, Any]:
    """
    Analyze a still image and WRITE a JSON with:
      - key landmarks (nose, shoulders, elbows, wrists, hips, knees, ankles)
      - calculated_features: shoulder_slope, hip_slope, torso_length, forward_lean
    No exercise context/state.
    """
    start_time = time.time()

    # ---- Load image (BGR) ----
    bgr = None
    source_path = None

    if isinstance(image, bytes):
        np_arr = np.frombuffer(image, np.uint8)
        bgr = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
    elif isinstance(image, str):
        source_path = image
        bgr = cv2.imread(image)
    elif isinstance(image, np.ndarray):
        bgr = image
    else:
        raise TypeError("image must be bytes, str (path), or numpy.ndarray (BGR)")

    if bgr is None:
        out = {
                "timestamp": datetime.now().isoformat(),
                "relative_time": time.time() - start_time,
                "image_id": image_id,
                "image_path": source_path,
                "image_size": {"width": 0, "height": 0},
                "detected": False,
                "landmarks": {},
                "calculated_features": {},
                "message": "Could not decode image."
            }
        return out

    h, w = bgr.shape[:2]
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)

    # ---- MediaPipe Pose (static image mode) ----
    mp_draw = mp.solutions.drawing_utils
    results = pose.process(rgb)

    if not results.pose_landmarks:
        frame = {
            "timestamp": datetime.now().isoformat(),
            "relative_time": time.time() - start_time,
            "image_id": image_id,
            "image_path": source_path,
            "image_size": {"width": int(w), "height": int(h)},
            "detected": False,
            "landmarks": {},
            "calculated_features": {},
            "message": "No pose landmarks detected."
        }
        return frame 

    lms = results.pose_landmarks.landmark

    # ---- Landmarks dict (normalized + pixels) ----
    landmarks: Dict[str, Any] = {}
    for name, idx in _KEYS.items():
        lm = lms[idx]
        landmarks[name] = {
            "x": float(lm.x),
            "y": float(lm.y),
            "z": float(lm.z),
            "visibility": float(lm.visibility),
            "x_px": float(lm.x * w),
            "y_px": float(lm.y * h),
        }

    feats = _calc_features(lms)

    frame = {
        "timestamp": datetime.now().isoformat(),
        "relative_time": time.time() - start_time,
        "image_id": image_id,
        "image_path": source_path,
        "image_size": {"width": int(w), "height": int(h)},
        "detected": True,
        "landmarks": landmarks,
        "calculated_features": feats
    }
    if draw_overlay:
        frame["overlay_path"] = overlay_output_path

    return frame 


# ---------------- helpers ----------------

_KEYS = {
    "nose": 0,
    "left_shoulder": 11, "right_shoulder": 12,
    "left_elbow": 13, "right_elbow": 14,
    "left_wrist": 15, "right_wrist": 16,
    "left_hip": 23, "right_hip": 24,
    "left_knee": 25, "right_knee": 26,
    "left_ankle": 27, "right_ankle": 28,
}

def _calc_features(lms) -> Dict[str, float]:
    eps = 1e-6
    left_shoulder, right_shoulder = lms[11], lms[12]
    left_hip, right_hip = lms[23], lms[24]
    nose = lms[0]

    shoulder_slope = (right_shoulder.y - left_shoulder.y) / ((right_shoulder.x - left_shoulder.x) + eps)
    hip_slope = (right_hip.y - left_hip.y) / ((right_hip.x - left_hip.x) + eps)

    shoulder_center_y = (left_shoulder.y + right_shoulder.y) / 2.0
    hip_center_y = (left_hip.y + right_hip.y) / 2.0
    torso_length = abs(hip_center_y - shoulder_center_y)

    hip_center_x = (left_hip.x + right_hip.x) / 2.0
    forward_lean = nose.x - hip_center_x

    return {
        "shoulder_slope": float(shoulder_slope),
        "hip_slope": float(hip_slope),
        "torso_length": float(torso_length),
        "forward_lean": float(forward_lean),
    }

def _wrap_metadata(frame: Dict[str, Any], start_time: float) -> Dict[str, Any]:
    return {
        "metadata": {
            "mode": "image",
            "total_images": 1,
            "duration_seconds": time.time() - start_time,
            "collection_date": datetime.now().isoformat(),
            "key_landmarks": list(_KEYS.keys())
        },
        "frames": [frame]
    }

def _splitext(path: str):
    dot = path.rfind(".")
    return (path if dot == -1 else path[:dot], "" if dot == -1 else path[dot:])

def _default_json_path(image_path: str) -> str:
    root, _ = _splitext(image_path)
    return f"{root}_pose.json"

def _default_overlay_path(image_path: Optional[str]) -> str:
    if image_path:
        root, _ = _splitext(image_path)
        return f"{root}_pose.png"
    return "overlay_pose.png"

def _write_json(path: str, payload: Dict[str, Any]) -> None:
    with open(path, "w") as f:
        json.dump(payload, f, indent=2)


# ---------------- CLI: local quick run ----------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract pose landmarks & features from a single image and save JSON locally.")
    parser.add_argument("image_path", help="Path to an input image (jpg/png).")
    parser.add_argument("--out", help="Output JSON path (default: <image>_pose.json)")
    parser.add_argument("--overlay", action="store_true", help="Also save a PNG with pose overlay.")
    parser.add_argument("--overlay-out", help="Overlay PNG path (default: <image>_pose.png)")
    parser.add_argument("--image-id", help="Optional ID stored in the JSON.")
    args = parser.parse_args()

    img_path = args.image_path
    if not os.path.isfile(img_path):
        raise SystemExit(f"Image not found: {img_path}")

    out_json = args.out or _default_json_path(img_path)
    overlay_path = args.overlay_out if args.overlay else None

    result = save_pose_landmarks_json(
        image=img_path,
        output_json_path=out_json,
        image_id=args.image_id,
        draw_overlay=args.overlay,
        overlay_output_path=overlay_path
    )
    print(f"Wrote JSON to: {out_json}")
    if args.overlay:
        print(f"Wrote overlay to: {result['frames'][0].get('overlay_path', overlay_path or _default_overlay_path(img_path))}")
