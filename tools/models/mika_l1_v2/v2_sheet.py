"""before | after sheet for one part: python3 tools/v2_sheet.py <render dir> <out.jpg> <title> [left label] [right label]"""
import sys, glob, os, numpy as np, cv2
d, out, title = sys.argv[1:4]
tags = sys.argv[4:6] if len(sys.argv) > 5 else ['before', 'after']          # labels for the two columns
names = sorted({os.path.basename(f).rsplit('_', 1)[0] for f in glob.glob(f'{d}/*_before.png')}, key=lambda s: (s[0] != 'f', s))
rows = []
for n in names:
    a = cv2.imread(f'{d}/{n}_before.png'); b = cv2.imread(f'{d}/{n}_after.png')
    h = 560; a = cv2.resize(a, (h, h), interpolation=cv2.INTER_AREA); b = cv2.resize(b, (h, h), interpolation=cv2.INTER_AREA)
    for im, t in ((a, tags[0]), (b, tags[1])):
        cv2.rectangle(im, (0, 0), (250, 34), (30, 30, 30), -1); cv2.putText(im, f'{n} {t}', (8, 25), 0, 0.75, (255, 255, 255), 2)
    rows.append(np.hstack([a, np.full((h, 8, 3), 255, np.uint8), b]))
head = np.full((50, rows[0].shape[1], 3), 30, np.uint8); cv2.putText(head, title, (10, 35), 0, 1.0, (255, 255, 255), 2)
cv2.imwrite(out, np.vstack([head] + [np.vstack([r, np.full((8, r.shape[1], 3), 255, np.uint8)]) for r in rows]), [cv2.IMWRITE_JPEG_QUALITY, 90])
