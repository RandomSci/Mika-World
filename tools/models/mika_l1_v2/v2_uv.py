"""Mika L1 v2 parts, face budget (Selwyn 2026-10-20): fresh non overlapping UVs for a low poly part with xatlas,
packed for a 4K texture with a padding gap between islands. Blender's smart project cut the noisy Meshy shapes into
2.5k islands and used a quarter of the texture, xatlas makes fewer, larger charts.
Triangle order is kept, so <out npz> holds one uv per triangle corner for v2_bake.py to put back in Blender.
  .venv/bin/python -I tools/v2_uv.py <part_uv.npz from v2_lowpoly> <out npz> [padding px] [--split-z Z]
--split-z gives the part two 4K pages (Selwyn: twice the texel density on the underskirt's gold hem): triangles whose
centre lies below Z go on page 1, the rest on page 0, each packed on its own. <out npz> then also holds PAGE per
triangle, and <out>_p0.npz and <out>_p1.npz hold each page's triangles alone for the bake, snap and checks.
--split-mask <npy> puts the triangles marked True on page 1 instead (v2_hemmask.py: the gold hem and one ring round it)."""
import sys
import numpy as np, xatlas

args = [x for x in sys.argv[1:]]
split = float(args[args.index('--split-z') + 1]) if '--split-z' in args else None
if split is not None:
    i = args.index('--split-z'); del args[i:i + 2]
mask = np.load(args[args.index('--split-mask') + 1]) if '--split-mask' in args else None
if mask is not None:
    i = args.index('--split-mask'); del args[i:i + 2]; split = 0.0
d = np.load(args[0]); out = args[1]
pad = int(args[2]) if len(args) > 2 else 8
V_all, F_all = d['V'], d['F']


def pack(V, F):
    tpu = 0.0
    for it in range(30):                     # xatlas only estimates the scale, shrink it until one 4K page holds all
        at = xatlas.Atlas()
        at.add_mesh(V.astype(np.float32), F.astype(np.uint32))
        po = xatlas.PackOptions()
        po.resolution = 4096; po.padding = pad; po.bilinear = True; po.rotate_charts = True; po.texels_per_unit = tpu
        co = xatlas.ChartOptions(); co.max_cost = 8.0          # a little more stretch allowed, fewer charts
        at.generate(chart_options=co, pack_options=po)
        if at.atlas_count == 1 and max(at.width, at.height) <= 4096:
            break
        tpu = (tpu or at.texels_per_unit * 4096 / max(at.width, at.height)) * 0.99
    vmap, idx, uv = at[0]
    assert idx.shape == F.shape and (vmap[idx] == F).all(), 'xatlas changed the triangle order'
    print(f'XATLAS texels_per_unit {at.texels_per_unit:.1f} charts {at.chart_count} size {at.width}x{at.height} utilization {float(np.ravel(at.utilization)[0]) * 100:.1f}%')
    return uv[idx].astype(np.float64)


if split is None:
    np.savez(out, UV=pack(V_all, F_all), V=V_all, F=F_all)
else:
    page = (mask if mask is not None else V_all[F_all].mean(1)[:, 2] < split).astype(np.int8)
    UV = np.zeros((len(F_all), 3, 2))
    for k in (0, 1):
        m = page == k
        used = np.unique(F_all[m]); remap = np.full(len(V_all), -1); remap[used] = np.arange(len(used))
        UV[m] = pack(V_all[used], remap[F_all[m]])
        np.savez(out[:-4] + '_p%d.npz' % k, UV=UV[m], V=V_all, F=F_all[m])
    np.savez(out, UV=UV, V=V_all, F=F_all, PAGE=page)
    print('PAGES', np.bincount(page))
