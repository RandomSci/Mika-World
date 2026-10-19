# Close-up sheet for the audit's eye check: audit_shots' front and side frames of each flagged moment, with every
# full-body fault the audit found on that side at that moment printed above them.
#   python3 tools/qa/audit_closeups.py <shots dir> <audit report.json> <girl> <out.jpg>
import json
import re
import sys

import cv2
import numpy as np

sd, rj, girl, out = sys.argv[1:5]
rep = json.load(open(rj))
cap = cv2.VideoCapture(sd + "/lab.mp4")
pairs = {}
for l in open(sd + "/log.txt", errors="ignore"):
    g = re.match(r"\[shot\] (\S+) ([\d.]+) (\S+) (\S+) at frame (\d+)", l)
    if g:
        pairs.setdefault((g.group(1), g.group(2), g.group(3)), []).append(int(g.group(5)))
tiles = []
for (clip, t, bone), fs in pairs.items():
    full = rep[clip][girl]["full"]
    near = ["%s %s%s" % (k.split(" ", 1)[1], v["worst"], (" into " + v["into"]) if v.get("into") else "")
            for k, v in full.items() if k.startswith(bone[0]) and abs(float(v["t"]) - float(t)) < 0.05]
    ims = []
    for f in fs:
        cap.set(cv2.CAP_PROP_POS_FRAMES, f - 2)
        ok, img = cap.read()
        img = cv2.resize(img, (1280, 720))[40:720, 300:980]
        ims.append(cv2.resize(img, (380, 380)))
    pair = np.hstack(ims)
    bar = np.zeros((40, pair.shape[1], 3), np.uint8)
    cv2.putText(bar, "%s %ss %s (front, side)" % (clip, t, bone), (4, 15), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
    cv2.putText(bar, ("; ".join(near) or "worst value of this clip is elsewhere")[:105], (4, 33), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (0, 255, 255), 1)
    tiles.append(np.vstack([bar, pair]))
if len(tiles) % 2:
    tiles.append(np.zeros_like(tiles[0]))
sheet = np.vstack([np.hstack(tiles[i:i + 2]) for i in range(0, len(tiles), 2)])
cv2.imwrite(out, sheet, [cv2.IMWRITE_JPEG_QUALITY, 88])
print(out)
