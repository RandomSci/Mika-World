"""Mika L1 v2 parts, face budget (Selwyn 2026-10-20): snap a raw bake to the 4 palette colours.
The bake averages 32 samples per texel, so a texel on a border holds a blend of two colours. Plain nearest colour
would turn a white and navy blend into sky blue, so each texel is unmixed instead: in linear light it is matched
against every blend of two colours (the palette plus black, which is a ray that hit nothing) and takes the colour
with the larger share of the best fitting pair. Texels where black wins take the colour of the nearest baked texel.
Everything outside the islands is filled with the nearest island colour too, so the 16 px padding and the mip
levels never show background.
  python3 tools/v2_snap.py <raw.png> <uv.npz> <out.png>"""
import sys
import numpy as np, cv2
from scipy import ndimage
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from v2lib import PAL, NAMES

raw, uvnpz, out = sys.argv[1:4]
N = 4096


def lin(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


im = lin(cv2.imread(raw, cv2.IMREAD_COLOR)[..., ::-1].astype(np.float32)).reshape(-1, 3).astype(np.float32)
UV = np.load(uvnpz)['UV']
cov = np.zeros((N, N), np.uint8)
P = np.round(np.c_[UV[..., 0].ravel(), 1 - UV[..., 1].ravel()] * N * 16 - 8).astype(np.int32).reshape(-1, 3, 2)
for t in P:                                                              # texel centres inside each triangle
    cv2.fillConvexPoly(cov, t, 1, lineType=cv2.LINE_8, shift=4)
cov = cov.reshape(-1) > 0

C = np.vstack([lin(PAL.astype(np.float32)), np.zeros((1, 3), np.float32)])   # 0..3 palette, 4 black (miss)
x = im[cov]
best = np.full(len(x), np.inf, np.float32); lab = np.zeros(len(x), np.uint8)
for i in range(5):
    for j in range(i, 5):
        d = C[i] - C[j]
        a = np.clip(((x - C[j]) @ d) / max(float(d @ d), 1e-12), 0, 1) if i != j else np.ones(len(x), np.float32)
        r = ((x - (C[j] + a[:, None] * d)) ** 2).sum(1)
        win = r < best
        best[win] = r[win]; lab[win] = np.where(a[win] >= 0.5, i, j)
miss = lab == 4
full = np.full(N * N, 255, np.uint8); full[np.nonzero(cov)[0][~miss]] = lab[~miss]
full = full.reshape(N, N)
_, idx = ndimage.distance_transform_edt(full == 255, return_indices=True)
full = full[idx[0], idx[1]]
cv2.imwrite(out, PAL[full][..., ::-1], [cv2.IMWRITE_PNG_COMPRESSION, 9])
c2 = cov.reshape(N, N)
share = np.bincount(full[c2], minlength=4) / c2.sum() * 100
print(f'SNAP {out.rsplit("/", 1)[-1]} island texels {c2.sum()} missed {miss.sum()} ({miss.sum() / c2.sum() * 100:.3f}%)'
      f' worst fit {np.sqrt(best.max()):.3f} share ' + ' '.join(f'{n} {s:.1f}%' for n, s in zip(NAMES, share)))
