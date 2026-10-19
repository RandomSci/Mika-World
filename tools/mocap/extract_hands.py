# Move Library mocap, step 1b: the hands. MediaPipe Pose (33 points) only knows the wrist, the index and pinky
# knuckles and the thumb tip, so fingers stayed at rest and the palm's roll was a guess. Here every frame's wrists
# (from Pose, image space) give a square crop around each hand, upscaled, and MediaPipe Hands reads its 21 points
# there (a hand is ~40 px in a 720p full-body shot: too small for the full-frame detector). The hand whose wrist lands
# nearest the crop's wrist is hers (the other hand may share the crop in a prayer or a seal), so left and right never
# swap. Written next to the body landmarks as <clip>.hands.json, Godot's frame (x = her left, y up, z toward the
# camera = her forward), metres, origin at the hand's centre (MediaPipe hand world landmarks):
#   {"fps", "l": [frame -> 21 x [x,y,z] or null], "r": [...], "l2d"/"r2d": [frame -> 21 x [px,py] or null],
#    "lq"/"rq": [frame -> 0..1 confidence]}
# Short gaps (<= 0.4 s) are filled from both neighbours, the rest stay null (the bake relaxes the hand there).
# Runs inside Blender's Python (the BlendArMocap profile ships mediapipe 0.10.14):
#   ~/.cache/mika_qa/blender_anime.sh -b --python tools/mocap/extract_hands.py -- <clip.mp4> <out.hands.json>
import json
import math
import sys

import cv2
import mediapipe as mp

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
CROP = 256
SIGMA = 1.2

cap = cv2.VideoCapture(src)
fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
res = {"l": [], "r": [], "l2d": [], "r2d": [], "lq": [], "rq": []}
pose = mp.solutions.pose.Pose(static_image_mode=False, model_complexity=1, smooth_landmarks=True,
                              min_detection_confidence=0.5, min_tracking_confidence=0.5)
hands = mp.solutions.hands.Hands(static_image_mode=True, max_num_hands=2, model_complexity=1,
                                 min_detection_confidence=0.35)
# pose image landmarks: wrist, pinky knuckle, index knuckle, thumb tip, elbow per side
SIDE = {"l": (15, 17, 19, 21, 13), "r": (16, 18, 20, 22, 14)}
while True:
    ok, img = cap.read()
    if not ok:
        break
    H, W = img.shape[0], img.shape[1]
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    pr = pose.process(rgb)
    for s, (wi, pi, ii, ti, ei) in SIDE.items():
        world, flat, q = None, None, 0.0
        if pr.pose_landmarks is not None:
            L = pr.pose_landmarks.landmark
            wx, wy = L[wi].x * W, L[wi].y * H
            kx = (L[pi].x + L[ii].x + L[ti].x) / 3.0 * W
            ky = (L[pi].y + L[ii].y + L[ti].y) / 3.0 * H
            fore = math.hypot(L[ei].x * W - wx, L[ei].y * H - wy)
            # the hand is about 0.75 of the forearm; the crop is centred a little past the knuckles, ~2.4 hands wide
            size = max(fore * 1.6, math.hypot(kx - wx, ky - wy) * 5.0, 48.0)
            cx, cy = wx + (kx - wx) * 0.9, wy + (ky - wy) * 0.9
            x0, y0 = int(round(cx - size / 2)), int(round(cy - size / 2))
            sz = int(round(size))
            pad = cv2.copyMakeBorder(rgb, sz, sz, sz, sz, cv2.BORDER_CONSTANT, value=(235, 235, 235))
            crop = pad[y0 + sz:y0 + 2 * sz, x0 + sz:x0 + 2 * sz]
            if crop.shape[0] > 8 and crop.shape[1] > 8:
                crop = cv2.resize(crop, (CROP, CROP), interpolation=cv2.INTER_CUBIC)
                hr = hands.process(crop)
                if hr.multi_hand_landmarks:
                    # hers: the detection whose wrist is nearest the body model's wrist (in crop pixels)
                    wcx, wcy = (wx - x0) / sz * CROP, (wy - y0) / sz * CROP
                    best, bd = None, 1e9
                    for k, hl in enumerate(hr.multi_hand_landmarks):
                        d = math.hypot(hl.landmark[0].x * CROP - wcx, hl.landmark[0].y * CROP - wcy)
                        if d < bd:
                            best, bd = k, d
                    if bd < CROP * 0.25:
                        hl = hr.multi_hand_landmarks[best]
                        hw = hr.multi_hand_world_landmarks[best]
                        world = [[p.x, -p.y, -p.z] for p in hw.landmark]
                        flat = [[round(x0 + p.x * sz, 1), round(y0 + p.y * sz, 1)] for p in hl.landmark]
                        q = float(hr.multi_handedness[best].classification[0].score) * max(0.0, 1.0 - bd / (CROP * 0.25))
        res[s].append(world)
        res[s + "2d"].append(flat)
        res[s + "q"].append(round(q, 3))
cap.release()

n = len(res["l"])
gap_max = int(round(0.4 * fps))
for s in ("l", "r"):
    A, F2, Q = res[s], res[s + "2d"], res[s + "q"]
    have = [i for i in range(n) if A[i] is not None]
    # fill short gaps by blending the neighbours
    for a, b in zip(have, have[1:]):
        if 1 < b - a <= gap_max + 1:
            for i in range(a + 1, b):
                t = (i - a) / float(b - a)
                A[i] = [[A[a][k][c] * (1 - t) + A[b][k][c] * t for c in range(3)] for k in range(21)]
                F2[i] = [[F2[a][k][c] * (1 - t) + F2[b][k][c] * t for c in range(2)] for k in range(21)]
                Q[i] = round(min(Q[a], Q[b]) * 0.6, 3)
    # softness: a small Gaussian over time inside each run of frames that have a hand
    r = max(1, int(math.ceil(SIGMA * 3)))
    w = [math.exp(-0.5 * (d / SIGMA) ** 2) for d in range(-r, r + 1)]
    sm = list(A)
    for i in range(n):
        if A[i] is None:
            continue
        pts = []
        for k in range(21):
            acc, tw = [0.0, 0.0, 0.0], 0.0
            for d in range(-r, r + 1):
                j = i + d
                if 0 <= j < n and A[j] is not None:
                    for c in range(3):
                        acc[c] += A[j][k][c] * w[d + r]
                    tw += w[d + r]
            pts.append([round(a / tw, 5) for a in acc])
        sm[i] = pts
    res[s] = sm

found = {s: sum(1 for f in res[s] if f is not None) for s in ("l", "r")}
data = {"src": src, "fps": fps, "total": n, "found": found}
data.update(res)
with open(out, "w") as fh:
    json.dump(data, fh)
print("[hands] %s: left %d, right %d of %d frames -> %s" % (src, found["l"], found["r"], n, out))
