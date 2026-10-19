# Move Library mocap, step 1: MediaPipe Pose world landmarks (33 points, metres, hip-centred) for every frame of a
# reference clip, smoothed (the softness pass: a small Gaussian over time, plus low-visibility points held), written as
# JSON in Godot's frame (x = the subject's left, y up, z toward the camera = her forward).
# Runs inside Blender's Python (the BlendArMocap profile ships mediapipe 0.10.14):
#   ~/.cache/mika_qa/blender_anime.sh -b --python tools/mocap/extract_landmarks.py -- <clip.mp4> <out.json> [sigma]
import json
import math
import sys

import cv2
import mediapipe as mp

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
sigma = float(argv[2]) if len(argv) > 2 else 1.6

cap = cv2.VideoCapture(src)
fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
frames, vis = [], []
with mp.solutions.pose.Pose(static_image_mode=False, model_complexity=2, smooth_landmarks=True,
                            min_detection_confidence=0.5, min_tracking_confidence=0.5) as pose:
    while True:
        ok, img = cap.read()
        if not ok:
            break
        res = pose.process(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
        if res.pose_world_landmarks is None:
            frames.append(None)
            vis.append(None)
            continue
        # MediaPipe: x to the image right, y down, z smaller = nearer the camera. The subject faces the camera, so
        # the image right is her left: Godot (x left, y up, z forward) = (x, -y, -z)
        frames.append([[p.x, -p.y, -p.z] for p in res.pose_world_landmarks.landmark])
        vis.append([p.visibility for p in res.pose_world_landmarks.landmark])
cap.release()

# frames without a detection take the nearest detected one
idx = [i for i, f in enumerate(frames) if f is not None]
if not idx:
    sys.exit("no pose found in " + src)
for i, f in enumerate(frames):
    if f is None:
        j = min(idx, key=lambda k: abs(k - i))
        frames[i], vis[i] = frames[j], vis[j]

# a point the model barely sees keeps its last well-seen place (no jitter from guesses)
for i in range(1, len(frames)):
    for k in range(33):
        if vis[i][k] < 0.3:
            frames[i][k] = frames[i - 1][k]

# softness: Gaussian over time, per coordinate
r = max(1, int(math.ceil(sigma * 3)))
w = [math.exp(-0.5 * (d / sigma) ** 2) for d in range(-r, r + 1)]
n = len(frames)
smooth = []
for i in range(n):
    pts = []
    for k in range(33):
        acc = [0.0, 0.0, 0.0]
        tw = 0.0
        for d in range(-r, r + 1):
            j = min(max(i + d, 0), n - 1)
            for c in range(3):
                acc[c] += frames[j][k][c] * w[d + r]
            tw += w[d + r]
        pts.append([round(a / tw, 5) for a in acc])
    smooth.append(pts)

with open(out, "w") as fh:
    json.dump({"src": src, "fps": fps, "frames": smooth, "detected": len(idx), "total": n}, fh)
print("[mocap] %s: %d/%d frames with a pose -> %s" % (src, len(idx), n, out))
