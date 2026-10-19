# Eye check for extract_hands.py: the 21 hand points drawn on the source frames at 10 fps, a close crop round each
# hand (her left in cyan, her right in magenta), tiled into one sheet.
#   python3 tools/mocap/hands_overlay.py <clip.mp4> <clip.hands.json> <out.jpg> [cols]
import json
import sys

import cv2
import numpy as np

src, hj, out = sys.argv[1], sys.argv[2], sys.argv[3]
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 10
H = json.load(open(hj))
CH = [(0, 1, 2, 3, 4), (0, 5, 6, 7, 8), (0, 9, 10, 11, 12), (0, 13, 14, 15, 16), (0, 17, 18, 19, 20), (5, 9, 13, 17)]
cap = cv2.VideoCapture(src)
fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
step = max(1, int(round(fps / 10.0)))
tiles, i = [], 0
while True:
    ok, img = cap.read()
    if not ok:
        break
    if i % step == 0:
        cells = []
        for s, col in (("r", (255, 0, 255)), ("l", (255, 255, 0))):
            p = H[s + "2d"][i] if i < len(H[s + "2d"]) else None
            q = H[s + "q"][i] if i < len(H[s + "q"]) else 0
            if p is None:
                cells.append(np.full((150, 150, 3), 40, np.uint8))
                continue
            im = img.copy()
            for ch in CH:
                for a, b in zip(ch, ch[1:]):
                    cv2.line(im, (int(p[a][0]), int(p[a][1])), (int(p[b][0]), int(p[b][1])), col[::-1], 1, cv2.LINE_AA)
            xs = [pt[0] for pt in p]
            ys = [pt[1] for pt in p]
            cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
            sz = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.5 + 20
            x0, y0 = int(cx - sz / 2), int(cy - sz / 2)
            pad = cv2.copyMakeBorder(im, int(sz), int(sz), int(sz), int(sz), cv2.BORDER_CONSTANT, value=(0, 0, 0))
            c = pad[y0 + int(sz):y0 + 2 * int(sz), x0 + int(sz):x0 + 2 * int(sz)]
            c = cv2.resize(c, (150, 150))
            cv2.putText(c, "%s %.2f" % ("R" if s == "r" else "L", q), (3, 145), cv2.FONT_HERSHEY_SIMPLEX, 0.4, col[::-1], 1)
            cells.append(c)
        cell = np.hstack(cells)
        cv2.putText(cell, "%.1fs" % (i / fps), (3, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 0, 255), 1)
        tiles.append(cell)
    i += 1
while len(tiles) % cols:
    tiles.append(np.zeros_like(tiles[0]))
rows = [np.hstack(tiles[k:k + cols]) for k in range(0, len(tiles), cols)]
cv2.imwrite(out, np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 85])
print("[hands_overlay]", out, len(tiles), "frames")
