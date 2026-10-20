"""Checks a low poly UV layout from v2_lowpoly.py at 4K: overlapping texels, the smallest gap between islands in
pixels, texture use, island count, and texels per mm on the surface.
  python3 tools/v2_uvcheck.py <part_uv.npz> <size cm>"""
import sys
import numpy as np, cv2
from scipy import ndimage
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

N = 4096
d = np.load(sys.argv[1]); size_cm = float(sys.argv[2])
UV, V, F = d['UV'], d['V'], d['F']

# islands: triangles sharing a vertex and the same uv on that vertex
key = np.round(UV.reshape(-1, 2) * 1e6).astype(np.int64)
vid = F.reshape(-1)
k = np.unique(np.c_[vid, key], axis=0, return_inverse=True)[1].ravel()
tri = np.repeat(np.arange(len(F)), 3)
m = coo_matrix((np.ones(len(k)), (tri, k))).tocsr()
adj = m @ m.T
nis, isl = connected_components(adj, directed=False)

over = np.zeros((N, N), np.uint16); lab = np.zeros((N, N), np.int32)
P = np.round(np.c_[UV[..., 0].ravel(), 1 - UV[..., 1].ravel()] * N * 16).astype(np.int32).reshape(-1, 3, 2)
# rasterise per island, so texels covered by two islands count as overlap
for j in range(nis):
    one = np.zeros((N, N), np.uint8)
    for t in np.nonzero(isl == j)[0]:
        cv2.fillConvexPoly(one, P[t], 1, lineType=cv2.LINE_8, shift=4)
    over += one; lab[one > 0] = j + 1
cov = over > 0
dup = (over > 1).sum()
# folds inside one island: the triangles' summed uv area against the texels they cover
e1 = UV[:, 1] - UV[:, 0]; e2 = UV[:, 2] - UV[:, 0]
uvarea = 0.5 * np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]).sum() * N * N
fold = uvarea / cov.sum()
# smallest gap: distance from each island to the nearest texel of another island
gap = 1e9
dist, idx = ndimage.distance_transform_edt(lab == 0, return_indices=True)
near = lab[idx[0], idx[1]]
# two background texels next to each other whose nearest islands differ give the gap there
for ax in (0, 1):
    a = near; b = np.roll(near, 1, ax); da = dist; db = np.roll(dist, 1, ax)
    sel = (a != b) & (a > 0) & (b > 0)
    if ax == 0: sel[0, :] = False                     # np.roll wraps the last row onto the first
    else: sel[:, 0] = False
    if sel.any():
        gap = min(gap, float((da[sel] + db[sel]).min()))
area = 0.5 * np.linalg.norm(np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]), axis=1).sum()
mm = (V.max(0) - V.min(0)).max() / (size_cm * 10)
tpm = np.sqrt(cov.sum() / (area / mm ** 2))
print(f'UVCHECK islands {nis} overlap_texels {dup} uv_area_over_covered {fold:.3f} min_gap_px {gap:.1f} used {cov.mean() * 100:.1f}% texels_per_mm {tpm:.1f}')
