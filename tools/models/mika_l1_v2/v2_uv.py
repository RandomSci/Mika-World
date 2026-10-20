"""Mika L1 v2 parts, face budget (Selwyn 2026-10-20): fresh non overlapping UVs for a low poly part with xatlas,
packed for a 4K texture with a padding gap between islands. Blender's smart project cut the noisy Meshy shapes into
2.5k islands and used a quarter of the texture, xatlas makes fewer, larger charts.
Triangle order is kept, so <out npz> holds one uv per triangle corner for v2_bake.py to put back in Blender.
  .venv/bin/python -I tools/v2_uv.py <part_uv.npz from v2_lowpoly> <out npz> [padding px]"""
import sys
import numpy as np, xatlas

d = np.load(sys.argv[1]); out = sys.argv[2]
pad = int(sys.argv[3]) if len(sys.argv) > 3 else 8
V, F = d['V'].astype(np.float32), d['F'].astype(np.uint32)
tpu = 0.0
for it in range(30):                     # xatlas only estimates the scale, shrink it until one 4K page holds all
    at = xatlas.Atlas()
    at.add_mesh(V, F)
    po = xatlas.PackOptions()
    po.resolution = 4096; po.padding = pad; po.bilinear = True; po.rotate_charts = True; po.texels_per_unit = tpu
    co = xatlas.ChartOptions(); co.max_cost = 8.0          # a little more stretch allowed, fewer charts
    at.generate(chart_options=co, pack_options=po)
    if at.atlas_count == 1 and max(at.width, at.height) <= 4096:
        break
    tpu = (tpu or at.texels_per_unit * 4096 / max(at.width, at.height)) * 0.99
vmap, idx, uv = at[0]
assert idx.shape == F.shape and (vmap[idx] == F).all(), 'xatlas changed the triangle order'
np.savez(out, UV=uv[idx].astype(np.float64), V=d['V'], F=d['F'])
print(f'XATLAS texels_per_unit {at.texels_per_unit:.1f} charts {at.chart_count} size {at.width}x{at.height} utilization {float(np.ravel(at.utilization)[0]) * 100:.1f}%')
