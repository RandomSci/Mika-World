# Tremble root cause: reads tremble_probe's dump (per frame, per bone, the raw baked rotation and the final rotation)
# and reports for each clip and bone the tremble (RMS of the angular velocity above 6 Hz, deg/s, and of the angle,
# deg) in the raw bake, in the final pose, and in what the other systems added (final relative to raw). Draws the
# worst bones as curves: raw (blue) and final (red) angle about their mean axis, per frame.
#   python3 tools/qa/tremble_report.py <dump.json> <out dir>
import json
import os
import sys

import cv2
import numpy as np

dump = json.load(open(sys.argv[1]))
outd = sys.argv[2]
os.makedirs(outd, exist_ok=True)
FPS = 30.0


def qarr(rows, key, b):
    q = []
    for r in rows:
        v = r[key].get(b)
        if v is None:
            return None
        q.append(v)
    q = np.array(q, float)
    for i in range(1, len(q)):                       # one hemisphere
        if np.dot(q[i], q[i - 1]) < 0:
            q[i] = -q[i]
    return q


def qmul(a, b):
    ax, ay, az, aw = a.T
    bx, by, bz, bw = b.T
    return np.stack([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz], 1)


def qinv(a):
    return a * np.array([-1, -1, -1, 1])


def rotvec(q):
    # the rotation from the clip's mean pose, as a rotation vector (deg)
    m = q.mean(0)
    m /= np.linalg.norm(m)
    d = qmul(np.repeat(qinv(m)[None], len(q), 0), q)
    d[d[:, 3] < 0] *= -1
    ang = 2 * np.arccos(np.clip(d[:, 3], -1, 1))
    s = np.sin(ang / 2)
    s[s < 1e-6] = 1e-6
    return d[:, :3] / s[:, None] * np.degrees(ang)[:, None]


def hf_rms(x):
    # RMS of the part above 6 Hz (deg)
    x = x - x.mean(0)
    F = np.fft.rfft(x, axis=0)
    f = np.fft.rfftfreq(len(x), 1 / FPS)
    F[f <= 6.0] = 0
    y = np.fft.irfft(F, n=len(x), axis=0)
    return float(np.sqrt((y ** 2).sum(1).mean()))


lines = []
worst = []
for clip, d in dump.items():
    rows = d["rows"]
    if len(rows) < 20:
        continue
    ts = np.array([r["t"] for r in rows])
    dt = np.diff(ts)
    pf = np.diff([r["pf"] for r in rows])
    lines.append("%s  %d frames, clip time step per frame mean %.4f s (min %.4f, max %.4f), physics ticks per frame %s" % (
        clip, len(rows), dt.mean(), dt.min(), dt.max(), sorted(set(pf.tolist()))))
    for b in rows[0]["fin"]:
        qr = qarr(rows, "raw", b)
        qf = qarr(rows, "fin", b)
        if qf is None:
            continue
        hf_f = hf_rms(rotvec(qf))
        hf_r = hf_rms(rotvec(qr)) if qr is not None else float("nan")
        add = float("nan")
        if qr is not None:
            dq = qmul(qinv(qr), qf)
            dq[dq[:, 3] < 0] *= -1
            add = hf_rms(rotvec(dq))
        lines.append("   %-24s raw %6.2f deg   final %6.2f deg   added by other systems %6.2f deg" % (b, hf_r, hf_f, add))
        worst.append((hf_f, clip, b, qr, qf))
open(os.path.join(outd, "tremble_report.txt"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines))

# the worst bones as curves (angle about the main axis of their motion), raw and final
worst.sort(key=lambda w: -w[0])
for k, (v, clip, b, qr, qf) in enumerate(worst[:8]):
    W, H = 900, 260
    img = np.full((H, W, 3), 255, np.uint8)
    rf = rotvec(qf)
    u, s, vt = np.linalg.svd(rf - rf.mean(0), full_matrices=False)
    axis = vt[0]
    yf = rf @ axis
    ys = [yf]
    if qr is not None:
        ys.insert(0, rotvec(qr) @ axis)
    lo, hi = min(y.min() for y in ys), max(y.max() for y in ys)
    for y, col in zip(ys, [(200, 80, 0), (0, 0, 220)] if len(ys) == 2 else [(0, 0, 220)]):
        pts = [(int(10 + i * (W - 20) / (len(y) - 1)), int(H - 20 - (yy - lo) / max(hi - lo, 1e-3) * (H - 50))) for i, yy in enumerate(y)]
        cv2.polylines(img, [np.array(pts, np.int32)], False, col, 1, cv2.LINE_AA)
    cv2.putText(img, "%s  %s  blue raw bake, red final pose  (high freq %.2f deg)" % (clip, b, v), (10, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1)
    cv2.imwrite(os.path.join(outd, "curve_%02d_%s_%s.png" % (k, clip, b)), img)
