"""tile the v2_qc.py views of one run into sheet.jpg:  python3 l1_v2/tools/v2_qcsheet.py <qc dir>"""
import sys, cv2, numpy as np
d = sys.argv[1]
a = np.hstack([cv2.resize(cv2.imread(f'{d}/{v}.png'), (420, 600)) for v in ['front', 'q34', 'side', 'back']])
b = np.hstack([cv2.resize(cv2.imread(f'{d}/{v}.png'), (450, 350)) for v in ['waist', 'waistf', 'chest', 'arm']])
b = cv2.resize(b, (a.shape[1], int(b.shape[0] * a.shape[1] / b.shape[1])))
cv2.imwrite(f'{d}/sheet.jpg', np.vstack([a, b]))
