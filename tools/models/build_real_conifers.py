"""Photoreal conifers for the Celestial Highlands (world-quality gate: the mountains need spruces and firs, and the
realistic tree set had only broadleaf species). Same construction and conventions as build_real_trees.py (its
helpers are reused): a straight tapering trunk to the very top with photoscanned bark, WHORLS of branches every
half metre from low on the trunk, long and drooping at the bottom, short and upturned near the top (the cone),
each branch carrying needle-spray cards (tools/textures/needle_twigs.py) lying out along it; a FAR version (fewer,
larger cards, 6-sided trunk) for distance.

  blender -b --python tools/models/build_real_conifers.py -- <out_dir>
Writes <out_dir>/real_conifers.glb (<Variant>_Bark/_Leaves/_FarBark/_FarLeaves) and real_conifers.json.
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "build_real_trees.py")).read()
exec(src[:src.index("info = {}")])           # frame, Buf, tube, curve, card, CELLS (and a factory reset)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "."


def conifer(name, seed, height, trunk_r, base_branch, crown_start, card_size, cells, droop=0.35, whorl_gap=0.55, per_whorl=6, lean=0.015):
    rnd = random.Random(seed)
    bark, leaves = Buf(), Buf()
    far_bark, far_leaves = Buf(), Buf()
    base = Vector((0, 0, -0.4))
    tp = curve(base, Vector((rnd.uniform(-lean, lean), rnd.uniform(-lean, lean), 1)), height, 20, 0.01, rnd)
    tr = [trunk_r * (1.0 + 0.45 * max(0.0, 1 - i / 1.4) ** 2) * (1 - 0.92 * i / (len(tp) - 1)) + 0.01 for i in range(len(tp))]
    tube(bark, tp, tr, 10)
    tube(far_bark, tp[::2] + ([tp[-1]] if len(tp) % 2 == 0 else []), tr[::2] + ([tr[-1]] if len(tr) % 2 == 0 else []), 6)
    sprays = []
    z = height * crown_start
    whorl = 0
    while z < height - 0.4:
        t = (z - height * crown_start) / max(height * (1 - crown_start), 0.1)     # 0 bottom of crown .. 1 top
        i0 = min(int(z / height * (len(tp) - 1)), len(tp) - 2)
        start = tp[i0]
        L = base_branch * (1.0 - t) ** 0.85 + 0.35
        n = per_whorl if t < 0.85 else max(3, per_whorl - 2)
        off = rnd.uniform(0, math.tau)
        for k in range(n):
            a = off + math.tau * (k + rnd.uniform(-0.2, 0.2)) / n
            out = Vector((math.cos(a), math.sin(a), 0))
            # low branches droop then lift at the tip; high ones point up
            up = lerp_up = (0.25 + 0.6 * t) - droop * (1 - t)
            d = (out + Vector((0, 0, up))).normalized()
            pts = curve(start, d, L, 6, 0.06, rnd, up_pull=0.06 * (1 - t), gravity=droop * (1 - t) * 0.5)
            rr = [tr[i0] * 0.32 * (1 - j / len(pts)) + 0.012 for j in range(len(pts))]
            tube(bark, pts, rr, 5, around=0.8)
            if whorl % 2 == 0:
                tube(far_bark, [pts[0], pts[-1]], [rr[0], rr[-1]], 3, around=0.8)
            for j in range(1, len(pts)):
                sprays.append((pts[j], (pts[j] - pts[j - 1]).normalized(), t))
        z += whorl_gap * rnd.uniform(0.85, 1.15)
        whorl += 1
    # the leader: a few sprays round the very top
    for k in range(5):
        sprays.append((tp[-1] - Vector((0, 0, k * 0.25)), Vector((rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), 1)).normalized(), 1.0))
    cps = [p for p, _, _ in sprays]
    crown_c = sum(cps, Vector()) / max(len(cps), 1)
    crown_r = max(Vector((p.x - crown_c.x, p.y - crown_c.y, 0)).length for p in cps) if cps else 3.0
    bottom = min(p.z for p in cps) - card_size
    top = max(p.z for p in cps) + card_size
    for idx, (p, d, t) in enumerate(sprays):
        # sprays lie out along the branch, a little up-turned, tilted about it (needles shingle downward)
        for c in range(2):
            dd = (d + Vector((rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), rnd.uniform(-0.1, 0.45)))).normalized()
            sz = card_size * rnd.uniform(0.75, 1.15) * (0.75 + 0.35 * (1 - t))
            at = p - dd * sz * 0.25
            cell = cells[0] if t > 0.75 and rnd.random() < 0.5 else cells[rnd.randrange(len(cells))]
            card(leaves, at, dd, sz, rnd, cell, crown_c, crown_r, bottom, top)
            if (idx * 2 + c) % 3 == 0:
                card(far_leaves, at, dd, sz * 1.5, rnd, cell, crown_c, crown_r, bottom, top)
    for nm, b in ((name + "_Bark", bark), (name + "_Leaves", leaves), (name + "_FarBark", far_bark), (name + "_FarLeaves", far_leaves)):
        b.build(nm)
    print(name, "cards", len(leaves.f), "far cards", len(far_leaves.f), "bark tris", len(bark.f) * 2)
    return {"canopy_center": [crown_c.x, crown_c.z, -crown_c.y], "canopy_radius": crown_r, "canopy_bottom": bottom, "canopy_top": top, "height": top}


info = {}
# cells: 0 spruce spray, 1 sunlit new growth, 2 flat fir spray, 3 sparse old spray
info["RealSpruce_A"] = conifer("RealSpruce_A", 5, 22.0, 0.34, 4.6, 0.14, 1.25, [0, 0, 1, 3], droop=0.4)
info["RealSpruce_B"] = conifer("RealSpruce_B", 9, 16.0, 0.27, 3.6, 0.18, 1.1, [0, 1, 3], droop=0.35, per_whorl=5)
info["RealFir"] = conifer("RealFir", 17, 19.0, 0.3, 3.9, 0.22, 1.2, [2, 2, 1], droop=0.15, whorl_gap=0.62)
info["RealPineYoung"] = conifer("RealPineYoung", 31, 7.5, 0.12, 2.0, 0.08, 0.9, [0, 1], droop=0.2, whorl_gap=0.45, per_whorl=5)
with open(os.path.join(OUT_DIR, "real_conifers.json"), "w") as f:
    json.dump(info, f, indent=1)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "real_conifers.glb"), export_format='GLB', use_selection=True, export_apply=True,
                          export_yup=True, export_materials='NONE', export_normals=True, export_texcoords=True, export_vertex_color='ACTIVE')
print("exported")
