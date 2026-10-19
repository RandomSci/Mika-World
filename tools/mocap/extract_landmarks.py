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
sigma = float(argv[2]) if len(argv) > 2 and not argv[2].startswith("--") else 1.6
aerial = "--aerial" in argv          # jumps / flips: also the hips' height above the floor from the 2D image (below)

cap = cv2.VideoCapture(src)
fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
frames, vis = [], []
hip_px, foot_px, torso_px, torso_m = [], [], [], []      # 2D (pixels) per frame, for --aerial
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
            if aerial:
                hip_px.append(None); foot_px.append(None); torso_px.append(None); torso_m.append(None)
            continue
        # MediaPipe: x to the image right, y down, z smaller = nearer the camera. The subject faces the camera, so
        # the image right is her left: Godot (x left, y up, z forward) = (x, -y, -z)
        frames.append([[p.x, -p.y, -p.z] for p in res.pose_world_landmarks.landmark])
        vis.append([p.visibility for p in res.pose_world_landmarks.landmark])
        if aerial and res.pose_landmarks is not None:
            h_img, w_img = img.shape[0], img.shape[1]
            L = res.pose_landmarks.landmark
            W = res.pose_world_landmarks.landmark
            hy = (L[23].y + L[24].y) * 0.5 * h_img
            fy = max(L[k].y for k in (27, 28, 29, 30, 31, 32)) * h_img
            sx, sy = (L[11].x + L[12].x) * 0.5 * w_img, (L[11].y + L[12].y) * 0.5 * h_img
            hx = (L[23].x + L[24].x) * 0.5 * w_img
            tp = math.hypot(sx - hx, sy - hy)
            tm = math.dist(((W[11].x + W[12].x) / 2, (W[11].y + W[12].y) / 2, (W[11].z + W[12].z) / 2),
                           ((W[23].x + W[24].x) / 2, (W[23].y + W[24].y) / 2, (W[23].z + W[24].z) / 2))
            hip_px.append(hy); foot_px.append(fy); torso_px.append(tp); torso_m.append(tm)
        elif aerial:
            hip_px.append(None); foot_px.append(None); torso_px.append(None); torso_m.append(None)
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

data = {"src": src, "fps": fps, "frames": smooth, "detected": len(idx), "total": n}
if aerial:
    # the hips' height above the floor (metres, the actor's scale) from the 2D image of a still camera: the floor is
    # the line her lowest foot rests on most of the time; pixels -> metres from her torso (shoulders to hips)
    ok = [i for i in range(n) if hip_px[i] is not None and torso_px[i] and torso_px[i] > 5]
    if ok:
        fl = sorted(foot_px[i] for i in ok)
        floor = fl[int(len(fl) * 0.85)]
        ratio = sorted(torso_m[i] / torso_px[i] for i in ok)[len(ok) // 2]
        hh = []
        for i in range(n):
            j = min(ok, key=lambda k: abs(k - i))
            hh.append(max((floor - hip_px[j]) * ratio, 0.0))
        hs = []
        for i in range(n):
            a, tw = 0.0, 0.0
            for d in range(-r, r + 1):
                j = min(max(i + d, 0), n - 1)
                a += hh[j] * w[d + r]
                tw += w[d + r]
            hs.append(round(a / tw, 4))
        data["hip_h"] = hs
with open(out, "w") as fh:
    json.dump(data, fh)
print("[mocap] %s: %d/%d frames with a pose -> %s" % (src, len(idx), n, out))
