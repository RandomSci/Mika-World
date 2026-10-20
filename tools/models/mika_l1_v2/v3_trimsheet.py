"""Mika L1 outfit v2 rework: the four extreme trim close-ups from the look lab next to the matching detail of her
original Level 1 design sheet (source/ref/MIKA_1_9.jpg).  python3 l1_v2/tools/v3_trimsheet.py <light> <out.jpg>"""
import sys, cv2, numpy as np
light, out = sys.argv[1:3]
L = '/home/selwyn/Downloads/Mika-Transformation-Lab'
ref = cv2.imread(L + '/source/ref/MIKA_1_9.jpg')
f = ref.shape[1] / 1500
# design sheet crops (x0, y0, x1, y1 in the 1500 wide sheet): sash and bow detail, the panel's gold pattern,
# the sleeve hem of the front view, the back view's bow and ribbons
CROPS = {'trim_sash': (1372, 688, 1500, 960), 'trim_panel_tip': (300, 808, 410, 962),
         'trim_sleeve_hem': (150, 175, 300, 360), 'trim_back_bow': (812, 20, 902, 230)}
NAMES = {'trim_sash': 'sash star band, bow, brooch', 'trim_panel_tip': 'panel filigree edge and corner',
         'trim_sleeve_hem': 'sleeve filigree hem, cloud lining', 'trim_back_bow': 'back bow cloud ribbons'}
rows = []
for k, (x0, y0, x1, y1) in CROPS.items():
    c = ref[int(y0 * f):int(y1 * f), int(x0 * f):int(x1 * f)]
    c = cv2.resize(c, (int(c.shape[1] * 540 / c.shape[0]), 540), interpolation=cv2.INTER_CUBIC)
    s = cv2.resize(cv2.imread(f'{L}/l1_v2/godot/new_{light}/{k}.png'), (960, 540), interpolation=cv2.INTER_AREA)
    for im, t in ((c, 'design sheet'), (s, 'new, ' + NAMES[k])):
        cv2.rectangle(im, (0, 0), (min(im.shape[1], 12 + 14 * len(t)), 34), (25, 25, 25), -1)
        cv2.putText(im, t, (8, 25), 0, 0.7, (255, 255, 255), 2)
    row = np.hstack([c, np.full((540, 8, 3), 255, np.uint8), s])
    rows.append(row)
W = max(r.shape[1] for r in rows)
rows = [np.pad(r, ((0, 8), (0, W - r.shape[1]), (0, 0)), constant_values=255) for r in rows]
cv2.imwrite(out, np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 90])
