"""Mika L1 outfit v2: old outfit left, new right, the look lab's six shots in one light.
  python3 l1_v2/tools/v2_compare.py <day|night> <out.jpg>"""
import sys, cv2, numpy as np
light, out = sys.argv[1:3]
D = '/home/selwyn/Downloads/Mika-Transformation-Lab/l1_v2/godot'
rows = []
for n in ['chest_sleeves', 'side', 'folded_arm', 'front', 'back_neck', 'medium']:
    pair = []
    for side in ('old', 'new'):
        im = cv2.resize(cv2.imread(f'{D}/{side}_{light}/{n}.png'), (960, 540), interpolation=cv2.INTER_AREA)
        cv2.rectangle(im, (0, 0), (330, 38), (25, 25, 25), -1)
        cv2.putText(im, f'{side} {n.replace("_", " ")}', (10, 27), 0, 0.8, (255, 255, 255), 2)
        pair.append(im)
    rows.append(np.hstack([pair[0], np.full((540, 8, 3), 255, np.uint8), pair[1]]))
head = np.full((56, rows[0].shape[1], 3), 25, np.uint8)
cv2.putText(head, f'Mika L1 outfit, {light}, look prototype   left current outfit   right v2 parts', (12, 38), 0, 1.0, (255, 255, 255), 2)
cv2.imwrite(out, np.vstack([head] + [np.vstack([r, np.full((8, r.shape[1], 3), 255, np.uint8)]) for r in rows]), [cv2.IMWRITE_JPEG_QUALITY, 88])
