"""Mika L1 v2 underskirt (Selwyn 2026-10-20, twice the texel density on the gold hem): the low poly triangles for its
own 4K page, every triangle whose colour on the clean high poly is gold, plus one ring of neighbours so the gold to
white and gold to navy borders sit on that page too. Prints the share of the surface it takes.
  python3 tools/v2_hemmask.py <low uv npz from v2_lowpoly> <clean_tx npz> <out npy> [rings]"""
import sys
import numpy as np
from scipy.spatial import cKDTree

lo, hi, out = sys.argv[1:4]
rings = int(sys.argv[4]) if len(sys.argv) > 4 else 1
l = np.load(lo); LV, LF = l['V'], l['F']
LVg = np.c_[LV[:, 0], LV[:, 2], -LV[:, 1]]                                 # Blender to glTF axes
h = np.load(hi); HV, HF, HL = h['V'], h['F'], h['lab']
tree = cKDTree(HV[HF].mean(1))
pts = np.concatenate([LVg[LF].mean(1), LVg[LF].reshape(-1, 3)])
_, nn = tree.query(pts, workers=-1)
lab = HL[nn]
gold = (lab[:len(LF)] == 2) | (lab[len(LF):].reshape(-1, 3) == 2).any(1)
m = gold.copy()
for _ in range(rings):
    vm = np.zeros(len(LV), bool); vm[LF[m].ravel()] = True
    m = vm[LF].any(1)
area = 0.5 * np.linalg.norm(np.cross(LV[LF[:, 1]] - LV[LF[:, 0]], LV[LF[:, 2]] - LV[LF[:, 0]]), axis=1)
np.save(out, m)
print(f'HEMMASK gold tris {gold.sum()} with rings {m.sum()} of {len(LF)}, area share {area[m].sum() / area.sum() * 100:.1f}%')
