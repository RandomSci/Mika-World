# Move Library check sheets: every clip as three strips at the same moments, the source video, Mika and Luna (each
# rendered by movelib_show, the log marks "[movelib] <clip> show from frame A to frame B"). `per` clips per sheet,
# `fps` samples per second of the clip.
#   python3 tools/qa/movelib_strips.py <moves dir> <mika dir> <luna dir> <out dir> [fps] [per] [clip,clip,...]
import glob
import os
import re
import sys

import cv2
import numpy as np

moves, mdir, ldir, outd = sys.argv[1:5]
fps_s = float(sys.argv[5]) if len(sys.argv) > 5 else 2.5
per = int(sys.argv[6]) if len(sys.argv) > 6 else 4
only = sys.argv[7].split(",") if len(sys.argv) > 7 else []
os.makedirs(outd, exist_ok=True)
TW, TH = 150, 190


def marks(d):
    m = {}
    for line in open(os.path.join(d, "log.txt"), errors="ignore"):
        g = re.search(r"\[movelib\] (\S+) show from frame (\d+) to frame (\d+)", line)
        if g:
            m[g.group(1)] = (int(g.group(2)), int(g.group(3)))
    return m


def src_of(name):
    for p in glob.glob(os.path.join(moves, "*", "clips", name + ".mp4")):
        return p
    return None


class Reader:
    def __init__(self, path):
        self.cap = cv2.VideoCapture(path)

    def at_frame(self, f):
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, int(f)))
        ok, img = self.cap.read()
        return img if ok else None

    def at_time(self, t):
        self.cap.set(cv2.CAP_PROP_POS_MSEC, max(0.0, t) * 1000.0)
        ok, img = self.cap.read()
        return img if ok else None


def tile(img, frac, label=None):
    if img is None:
        return np.full((TH, TW, 3), 40, np.uint8)
    h, w = img.shape[:2]
    cw = int(w * frac)
    x0 = (w - cw) // 2
    t = cv2.resize(img[:, x0:x0 + cw], (TW, TH), interpolation=cv2.INTER_AREA)
    if label:
        cv2.putText(t, label, (3, 12), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (0, 0, 255), 1, cv2.LINE_AA)
    return t


mm, lm = marks(mdir), marks(ldir)
mr, lr = Reader(os.path.join(mdir, "lab.mp4")), Reader(os.path.join(ldir, "lab.mp4"))
names = [n for n in mm if n in lm and (not only or n in only)]
blocks = []
for n in names:
    sp = src_of(n)
    if not sp:
        continue
    sr = Reader(sp)
    dur = sr.cap.get(cv2.CAP_PROP_FRAME_COUNT) / (sr.cap.get(cv2.CAP_PROP_FPS) or 30.0)
    k = max(1, int(dur * fps_s))
    rows = [[], [], []]
    for i in range(k):
        t = i / fps_s
        rows[0].append(tile(sr.at_time(t), 0.56, "%.1fs" % t))
        a, b = mm[n]
        rows[1].append(tile(mr.at_frame(a + t * 30.0), 0.42))
        a2, b2 = lm[n]
        rows[2].append(tile(lr.at_frame(a2 + t * 30.0), 0.42))
    strip = np.vstack([np.hstack(r) for r in rows])
    head = np.full((22, strip.shape[1], 3), 25, np.uint8)
    cv2.putText(head, "%s   (source, Mika, Luna)" % n, (5, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
    blocks.append(np.vstack([head, strip]))
for s in range(0, len(blocks), per):
    group = blocks[s:s + per]
    wmax = max(b.shape[1] for b in group)
    group = [np.hstack([b, np.full((b.shape[0], wmax - b.shape[1], 3), 255, np.uint8)]) for b in group]
    sheet = np.vstack([np.vstack([b, np.full((6, wmax, 3), 255, np.uint8)]) for b in group])
    p = os.path.join(outd, "movelib_strips_%02d.jpg" % (s // per))
    cv2.imwrite(p, sheet, [cv2.IMWRITE_JPEG_QUALITY, 85])
    print(p)
