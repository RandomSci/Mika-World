# 10 fps hand frames for the tremble fix: the source clip (tracked hands drawn), the render before and after, cropped
# on the hands. Probe dumps give each render frame's clip time, so the three rows show the same moment.
#   python3 tools/qa/before_after_hands.py <before.json> <before lab.mp4> <after.json> <after lab.mp4> <clip> <t0> <t1> <src.mp4> <out.jpg> [src cy size] [render cy size]
import json
import sys

import cv2
import numpy as np

bj, bm, aj, am, clip, t0, t1, src, out = sys.argv[1:10]
t0, t1 = float(t0), float(t1)
scy, ssz = (float(sys.argv[10]), float(sys.argv[11])) if len(sys.argv) > 11 else (250.0, 300.0)
rcy, rsz = (float(sys.argv[12]), float(sys.argv[13])) if len(sys.argv) > 13 else (250.0, 300.0)
TW, TH = 180, 200


def frame_at(rows, t):
    return min(rows, key=lambda r: abs(r["t"] - t))["f"]


def read(cap, i=None, ms=None):
    if ms is not None:
        cap.set(cv2.CAP_PROP_POS_MSEC, ms)
    else:
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(i))
    ok, img = cap.read()
    return cv2.resize(img, (1280, 720)) if ok else np.zeros((720, 1280, 3), np.uint8)


def crop(img, cy, s):
    x0, y0 = int(640 - s / 2), int(cy - s * TH / TW / 2)
    pad = cv2.copyMakeBorder(img, 500, 500, 500, 500, cv2.BORDER_CONSTANT)
    return cv2.resize(pad[y0 + 500:y0 + 500 + int(s * TH / TW), x0 + 500:x0 + 500 + int(s)], (TW, TH))


B = json.load(open(bj))[clip]["rows"]
A = json.load(open(aj))[clip]["rows"]
cs, cb, ca = cv2.VideoCapture(src), cv2.VideoCapture(bm), cv2.VideoCapture(am)
rows = [[], [], []]
t = t0
while t <= t1 + 1e-6:
    s = crop(read(cs, ms=t * 1000.0), scy, ssz)
    cv2.putText(s, "%.1fs" % t, (3, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 0, 255), 1)
    rows[0].append(s)
    rows[1].append(crop(read(cb, frame_at(B, t)), rcy, rsz))
    rows[2].append(crop(read(ca, frame_at(A, t)), rcy, rsz))
    t += 0.1
W = TW * len(rows[0])
bar = lambda txt: cv2.putText(np.full((20, W, 3), 35, np.uint8), txt, (4, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
sheet = np.vstack([bar("%s  source, 10 fps" % clip), np.hstack(rows[0]), bar("before (raw bake)"), np.hstack(rows[1]),
                   bar("after (swaps fixed, holds, 0.2 s crossfades, fitted hand shapes, elbow continuity, One Euro)"), np.hstack(rows[2])])
cv2.imwrite(out, sheet, [cv2.IMWRITE_JPEG_QUALITY, 88])
print(out, len(rows[0]))
