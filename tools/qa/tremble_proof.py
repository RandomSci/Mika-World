# Proof frames for the trembling: around a jump in the raw bake, every 30 fps frame as four rows - the source video with
# the tracked hand points (her left cyan, right magenta, confidence), the offline render (fixed 30 fps movie), the real
# game loop screen recording (matched to the render by image, so dropped or doubled recorder frames show as repeats),
# and the bone's raw (blue) and final (red) angle curve with the frame marked.
#   python3 tools/qa/tremble_proof.py <offline.json> <lab.mp4> <realloop.json> <rec.mp4> <clip> <bone> <t0> <t1> <src.mp4> <hands.json> <out.jpg>
import json
import sys

import cv2
import numpy as np

off_j, lab, rt_j, rec, clip, bone, t0, t1, src, hj, out = sys.argv[1:12]
SCY = float(sys.argv[12]) if len(sys.argv) > 12 else 250.0      # source crop centre y, size
SSZ = float(sys.argv[13]) if len(sys.argv) > 13 else 300.0
RCY = float(sys.argv[14]) if len(sys.argv) > 14 else 250.0      # render crop centre y, size
RSZ = float(sys.argv[15]) if len(sys.argv) > 15 else 300.0
t0, t1 = float(t0), float(t1)
off = json.load(open(off_j))[clip]
rt = json.load(open(rt_j))[clip]
H = json.load(open(hj))
TW, TH = 210, 230
CH = [(0, 1, 2, 3, 4), (0, 5, 6, 7, 8), (0, 9, 10, 11, 12), (0, 13, 14, 15, 16), (0, 17, 18, 19, 20), (5, 9, 13, 17)]


def read(cap, i):
    cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, int(i)))
    ok, img = cap.read()
    return img if ok else np.zeros((720, 1280, 3), np.uint8)


def crop_c(img, cx, cy, s):
    h, w = img.shape[:2]
    x0, y0 = int(cx - s / 2), int(cy - s * TH / TW / 2)
    pad = cv2.copyMakeBorder(img, 400, 400, 400, 400, cv2.BORDER_CONSTANT)
    c = pad[y0 + 400:y0 + 400 + int(s * TH / TW), x0 + 400:x0 + 400 + int(s)]
    return cv2.resize(c, (TW, TH))


rows_o = off["rows"]
sel = [i for i, r in enumerate(rows_o) if t0 <= r["t"] <= t1]
cs, cl, cr = cv2.VideoCapture(src), cv2.VideoCapture(lab), cv2.VideoCapture(rec)
nrec = int(cr.get(cv2.CAP_PROP_FRAME_COUNT))
# the recording: find the frame matching the offline render's first selected frame by image (small greyscale)
sm = lambda im: cv2.resize(cv2.cvtColor(im, cv2.COLOR_BGR2GRAY), (96, 54)).astype(np.float32)
ref0 = sm(cv2.resize(read(cl, rows_o[sel[0]]["f"]), (1280, 720)))
# rough start: the same clip's start in the real loop's own timeline (usec) relative to the recording start guess
best = (1e18, 0)
lo = 0
for i in range(0, nrec, 2):
    d = float(((sm(read(cr, i)) - ref0) ** 2).mean())
    if d < best[0]:
        best = (d, i)
r0 = best[1]
src_tiles, lab_tiles, rec_tiles, labels = [], [], [], []
prev = None
for k, i in enumerate(sel):
    r = rows_o[i]
    st = r["t"]
    s_img = read(cs, int(round(st * 30)))
    for side, col in (("l", (255, 255, 0)), ("r", (255, 0, 255))):
        p = H[side + "2d"][min(int(round(st * 30)), len(H[side + "2d"]) - 1)]
        q = H[side + "q"][min(int(round(st * 30)), len(H[side + "q"]) - 1)]
        if p:
            for ch in CH:
                for a, b in zip(ch, ch[1:]):
                    cv2.line(s_img, (int(p[a][0]), int(p[a][1])), (int(p[b][0]), int(p[b][1])), col[::-1], 2, cv2.LINE_AA)
            cv2.putText(s_img, "%s %.2f" % (side.upper(), q), (int(p[0][0]), int(p[0][1]) + 18), cv2.FONT_HERSHEY_SIMPLEX, 0.6, col[::-1], 2)
    src_tiles.append(crop_c(s_img, 640, SCY, SSZ))
    l_img = cv2.resize(read(cl, r["f"]), (1280, 720))
    lab_tiles.append(crop_c(l_img, 640, RCY, RSZ))
    # the recording frame: search near the expected index for the best image match to this render frame
    want = sm(l_img)
    exp = r0 + (r["f"] - rows_o[sel[0]]["f"])
    cand = range(max(0, exp - 4), min(nrec, exp + 5))
    j = min(cand, key=lambda j: float(((sm(cv2.resize(read(cr, j), (1280, 720))) - want) ** 2).mean()))
    g = read(cr, j)
    gh, gw = g.shape[:2]
    rec_tiles.append(crop_c(cv2.resize(g, (1280, 720)), 640, RCY, RSZ))
    labels.append("%.2fs f%d rec%d" % (st, r["f"], j))
# the curve: how far the bone turned since the previous frame (deg), raw bake and final pose
qr = np.array([rows_o[i]["raw"][bone] for i in range(len(rows_o))])
qf = np.array([rows_o[i]["fin"][bone] for i in range(len(rows_o))])
step = lambda q: np.concatenate([[0.0], np.degrees(2 * np.arccos(np.clip(np.abs((q[1:] * q[:-1]).sum(1)), 0, 1)))])
ar, af = step(qr), step(qf)
W = TW * len(sel)
cv_img = np.full((150, W, 3), 255, np.uint8)
hi_ = max(ar[sel].max(), af[sel].max(), 10.0)
for arr, col, off in ((ar, (200, 80, 0), 0), (af, (0, 0, 220), 3)):
    pts = [(int(TW * k + TW / 2) + off, int(140 - arr[i] / hi_ * 115)) for k, i in enumerate(sel)]
    cv2.polylines(cv_img, [np.array(pts, np.int32)], False, col, 2, cv2.LINE_AA)
    for k, p in enumerate(pts):
        cv2.circle(cv_img, p, 3, col, -1)
        if col[0] == 200:
            cv2.putText(cv_img, "%.0f" % arr[sel[k]], (p[0] + 5, p[1] - 4), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 0, 0), 1)
cv2.putText(cv_img, "%s %s, degrees turned since the previous frame (blue raw bake, red final pose, drawn 3 px apart)" % (clip, bone),
            (4, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 0, 0), 1)
rowf = lambda tiles, name: np.vstack([cv2.putText(np.full((18, W, 3), 40, np.uint8), name, (4, 13), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1),
                                      np.hstack(tiles)])
lab_row = np.hstack([cv2.putText(t.copy(), labels[k], (2, 12), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (0, 255, 255), 1) for k, t in enumerate(lab_tiles)])
sheet = np.vstack([rowf(src_tiles, "source video, tracked hands (cyan her left, magenta her right, tracker confidence)"),
                   rowf([lab_row], "offline render (fixed 30 fps)"),
                   rowf(rec_tiles, "real game loop, RTX 5050, screen recorded, matched to the render by image"),
                   cv_img])
cv2.imwrite(out, sheet, [cv2.IMWRITE_JPEG_QUALITY, 88])
print(out, len(sel), "frames, recording start match", r0)
