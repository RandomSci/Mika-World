"""Mika L1 v2 parts, face budget (Selwyn 2026-10-20): independent check of a snapped bake. For every texel centre of
the low poly the 3D point is found and given the colour of the nearest clean high poly face (centroid search, the
high poly faces are tiny along borders). Texels that disagree with the bake are counted, split into those touching a
colour border in the reference (a texel of quantisation, expected) and the rest (real errors), and drawn into
<out.png> as red dots on the reference.
  python3 tools/v2_bakecheck.py <clean_tx npz> <uv npz> <snapped png> <out png>"""
import sys
import numpy as np, cv2
from scipy.spatial import cKDTree
from scipy import ndimage
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from v2lib import PAL, labels_of

hi_npz, uvnpz, png, out = sys.argv[1:5]
N = 4096
h = np.load(hi_npz); HV, HF, HL = h['V'], h['F'], h['lab']
l = np.load(uvnpz); UV, LV, LF = l['UV'], l['V'], l['F']
LV = np.c_[LV[:, 0], LV[:, 2], -LV[:, 1]]                                 # Blender to glTF axes

fid = np.full((N, N), -1, np.int32)
P = np.round(np.c_[UV[..., 0].ravel(), 1 - UV[..., 1].ravel()] * N * 16 - 8).astype(np.int32).reshape(-1, 3, 2)
img = np.zeros((N, N, 3), np.uint8)
for t in range(len(LF)):
    v = t + 1
    cv2.fillConvexPoly(img, P[t], (v & 255, (v >> 8) & 255, v >> 16), lineType=cv2.LINE_8, shift=4)
fid = (img[..., 0].astype(np.int32) | img[..., 1].astype(np.int32) << 8 | img[..., 2].astype(np.int32) << 16) - 1
ys, xs = np.nonzero(fid >= 0); t = fid[ys, xs]
# barycentric of the texel centre in its uv triangle
p = np.c_[(xs + 0.5) / N, 1 - (ys + 0.5) / N]
a, b, c = UV[t, 0], UV[t, 1], UV[t, 2]
v0, v1, v2 = b - a, c - a, p - a
den = v0[:, 0] * v1[:, 1] - v1[:, 0] * v0[:, 1]
den = np.where(np.abs(den) < 1e-20, 1e-20, den)
w1 = (v2[:, 0] * v1[:, 1] - v1[:, 0] * v2[:, 1]) / den
w2 = (v0[:, 0] * v2[:, 1] - v2[:, 0] * v0[:, 1]) / den
w0 = 1 - w1 - w2
X = w0[:, None] * LV[LF[t, 0]] + w1[:, None] * LV[LF[t, 1]] + w2[:, None] * LV[LF[t, 2]]
cen = HV[HF].mean(1)
# nearest high face that faces the same way as the low face, so the far side of a thin layer is never taken
hn = np.cross(HV[HF[:, 1]] - HV[HF[:, 0]], HV[HF[:, 2]] - HV[HF[:, 0]]); hn /= np.linalg.norm(hn, axis=1, keepdims=True) + 1e-20
ln = np.cross(LV[LF[:, 1]] - LV[LF[:, 0]], LV[LF[:, 2]] - LV[LF[:, 0]]); ln /= np.linalg.norm(ln, axis=1, keepdims=True) + 1e-20
dd, kk = cKDTree(cen).query(X, k=16, workers=-1)
ok = (hn[kk] * ln[t][:, None, :]).sum(-1) > 0.0
nn = kk[np.arange(len(kk)), np.argmax(ok, 1)]
ref = np.full((N, N), 255, np.uint8); ref[ys, xs] = HL[nn]
bake = labels_of(cv2.imread(png)[..., ::-1])
bad = (ref != 255) & (ref != bake)
# a reference border next to the texel means quantisation
edge = np.zeros((N, N), bool)
for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)):
    r2 = np.roll(ref, (dy, dx), (0, 1))
    edge |= (r2 != 255) & (r2 != ref)
real = bad & ~ndimage.binary_dilation(edge, iterations=1)
vis = np.where((ref == 255)[..., None], 40, PAL[np.minimum(ref, 3)]).astype(np.uint8)
vis[ndimage.binary_dilation(real, iterations=3)] = (255, 0, 0)
cv2.imwrite(out, cv2.resize(vis, (2048, 2048), interpolation=cv2.INTER_AREA)[..., ::-1])
n = (ref != 255).sum()
print(f'BAKECHECK texels {n} differ {bad.sum()} ({bad.sum() / n * 100:.3f}%) away from borders {real.sum()} ({real.sum() / n * 100:.4f}%)')
