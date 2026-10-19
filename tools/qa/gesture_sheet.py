# Contact sheet: spells and ultimates on our girls beside their source gesture clips, at the same moments of the
# gesture. Each row is one cast: five moments (the gesture's start, the middle of the gather, just before the release,
# the release, 0.5 s after) as a pair of tiles, the source clip (left) and our render (right).
#   python3 tools/qa/gesture_sheet.py <spec.json> <out.jpg>
# spec: {"rows": [{"label": str, "src": source mp4, "ours": our mp4, "fps": 30,
#                  "src_times": [5 clip seconds], "our_frames": [5 frame numbers of our mp4]}], "tile": [w, h]}
import json
import sys

import cv2
import numpy as np

spec = json.load(open(sys.argv[1]))
out = sys.argv[2]
tw, th = spec.get("tile", [240, 300])
labels = ["start", "gather", "before release", "release", "after"]


def grab(path, t=None, frame=None):
    cap = cv2.VideoCapture(path)
    if frame is not None:
        cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, int(frame)))
    else:
        cap.set(cv2.CAP_PROP_POS_MSEC, max(0.0, float(t)) * 1000.0)
    ok, img = cap.read()
    cap.release()
    if not ok:
        return np.zeros((th, tw, 3), np.uint8)
    return img


def fit(img, centre_frac=0.56):
    h, w = img.shape[:2]
    # the source clips are 16:9 with the actor centred; our renders are 16:9 too: the middle of the frame
    cw = int(w * centre_frac)
    x0 = (w - cw) // 2
    c = img[:, x0:x0 + cw]
    return cv2.resize(c, (tw, th), interpolation=cv2.INTER_AREA)


rows = []
for r in spec["rows"]:
    cells = []
    for i in range(5):
        a = fit(grab(r["src"], t=r["src_times"][i]))
        b = fit(grab(r["ours"], frame=r["our_frames"][i]), r.get("ours_frac", 0.56))
        cv2.putText(a, "source", (4, th - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (40, 40, 220), 1, cv2.LINE_AA)
        cv2.putText(b, "ours", (4, th - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (40, 220, 220), 1, cv2.LINE_AA)
        pair = np.hstack([a, b])
        cv2.putText(pair, labels[i], (4, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.putText(pair, labels[i], (4, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (20, 20, 20), 1, cv2.LINE_AA)
        cells.append(pair)
        cells.append(np.full((th, 6, 3), 255, np.uint8))
    row = np.hstack(cells[:-1])
    head = np.full((26, row.shape[1], 3), 30, np.uint8)
    cv2.putText(head, r["label"], (6, 19), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1, cv2.LINE_AA)
    rows.append(np.vstack([head, row]))
    rows.append(np.full((8, row.shape[1], 3), 255, np.uint8))
sheet = np.vstack(rows[:-1])
cv2.imwrite(out, sheet, [cv2.IMWRITE_JPEG_QUALITY, 88])
print("[gesture_sheet]", out, sheet.shape)
