# Grip library, step 1 (2026-10-20, Selwyn's Grip_Library_v1: close-up clips of real hands holding a rapier, a sword,
# a staff and a longsword): MediaPipe Hands on every frame (both hands, world landmarks in metres and image landmarks
# in pixels, MediaPipe's handedness and score) plus the weapon's line in the image (the longest straight edge through
# or beside the fist: Canny + probabilistic Hough), so the next step can measure how each finger curls and at what
# angle the handle crosses the hand. Runs inside Blender's Python (the BlendArMocap profile ships mediapipe 0.10.14):
#   ~/.cache/mika_qa/blender_anime.sh -b --python tools/mocap/extract_grip.py -- <clip.mp4> <out.json>
import json
import math
import sys

import cv2
import mediapipe as mp
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
cap = cv2.VideoCapture(src)
fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
frames = []
with mp.solutions.hands.Hands(static_image_mode=False, max_num_hands=2, model_complexity=1,
                              min_detection_confidence=0.5, min_tracking_confidence=0.5) as hands:
    while True:
        ok, img = cap.read()
        if not ok:
            break
        h, w = img.shape[:2]
        res = hands.process(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
        hs = []
        if res.multi_hand_landmarks:
            for i, lm in enumerate(res.multi_hand_landmarks):
                wl = res.multi_hand_world_landmarks[i]
                hd = res.multi_handedness[i].classification[0]
                hs.append({"label": hd.label, "score": round(hd.score, 3),
                           "img": [[round(p.x * w, 1), round(p.y * h, 1)] for p in lm.landmark],
                           "world": [[round(p.x, 5), round(p.y, 5), round(p.z, 5)] for p in wl.landmark]})
        # the weapon: straight edges, the longest ones that pass near a hand's centre
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        edges = cv2.Canny(cv2.GaussianBlur(gray, (5, 5), 0), 40, 120)
        lines = cv2.HoughLinesP(edges, 1, np.pi / 360, threshold=60, minLineLength=int(0.18 * h), maxLineGap=12)
        segs = []
        if lines is not None:
            for l in lines[:, 0, :]:
                x1, y1, x2, y2 = [float(v) for v in l]
                segs.append([x1, y1, x2, y2, math.hypot(x2 - x1, y2 - y1)])
            segs.sort(key=lambda s: -s[4])
            segs = segs[:24]
        frames.append({"hands": hs, "lines": [[round(v, 1) for v in s] for s in segs]})
cap.release()
json.dump({"src": src, "fps": fps, "frames": frames}, open(out, "w"))
print("[grip] %s: %d frames, hands in %d" % (src, len(frames), sum(1 for f in frames if f["hands"])))
