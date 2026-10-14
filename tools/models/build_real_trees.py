"""Photoreal forest trees for the Whispering Woods (realism pass): tall straight trunks with photoscanned bark
UVs, shallow root flare, limbs that start high, and canopies of photoreal leaf-twig cards
(tools/textures/leaf_twigs.py, ambientCG CC0 leaf scans). Each variant also gets a FAR version (6-sided trunk,
a third of the cards, larger) for distance.

  blender -b --python tools/models/build_real_trees.py -- <out_dir>

Writes <out_dir>/real_trees.glb with objects <Variant>_Bark, <Variant>_Leaves, <Variant>_FarBark,
<Variant>_FarLeaves, and real_trees.json (canopy extents per variant). Leaves: vertex colour R = ambient
occlusion inside the crown, G = height in the crown; normals are bent away from the crown centre (soft
volume lighting) but keep half of each card's own normal (detail).
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "."
bpy.ops.wm.read_factory_settings(use_empty=True)


def frame(fwd, up_hint=Vector((0, 0, 1))):
    f = Vector(fwd).normalized()
    r = f.cross(up_hint)
    if r.length < 1e-4:
        r = f.cross(Vector((1, 0, 0)))
    r.normalize()
    return f, r, r.cross(f).normalized()


class Buf:
    def __init__(self):
        self.v, self.f, self.uv, self.c, self.n = [], [], [], [], []

    def add(self, verts, faces, uvs, cols, normals=None):
        b = len(self.v)
        self.v += [tuple(p) for p in verts]
        self.f += [tuple(b + i for i in fc) for fc in faces]
        self.uv += uvs
        self.c += cols
        self.n += normals if normals else [None] * len(verts)

    def build(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        me.update()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        ca = me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='POINT')
        for i, c in enumerate(self.c):
            ca.data[i].color = (c[0], c[1], c[2], 1.0)
        uv = me.uv_layers.new(name="UV")
        for poly in me.polygons:
            poly.use_smooth = True
            for li in poly.loop_indices:
                uv.data[li].uv = self.uv[me.loops[li].vertex_index]
        if any(n is not None for n in self.n):
            me.normals_split_custom_set([tuple(self.n[lp.vertex_index]) if self.n[lp.vertex_index] is not None else (0, 0, 1) for lp in me.loops])
        return ob


def tube(buf, pts, radii, sides, around=2.0, tex_len=1.6, v0=0.0):
    prev_r = None
    vlen = v0
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if prev_r is None:
            f, r, u = frame(d)
        else:
            r = (prev_r - d * prev_r.dot(d)).normalized()
            u = d.cross(r).normalized()
        prev_r = r
        rings.append((p, r, u, radii[i]))
    verts, faces, uvs, cols = [], [], [], []
    for i, (p, r, u, rad) in enumerate(rings):
        if i > 0:
            vlen += (p - rings[i - 1][0]).length
        for s in range(sides + 1):
            a = 2 * math.pi * s / sides
            # bark ridges and a little irregularity, so trunks are not perfect cylinders
            wob = 1.0 + 0.05 * noise.noise(p * 2.3 + Vector((math.cos(a), math.sin(a), 0)) * 1.3) + 0.02 * math.sin(a * 7 + p.z)
            verts.append(p + (r * math.cos(a) + u * math.sin(a)) * rad * wob)
            uvs.append((around * s / sides, vlen / tex_len))
            cols.append((1.0, 1.0, 1.0))
    n = sides + 1
    for i in range(len(rings) - 1):
        for s in range(sides):
            a = i * n + s
            faces.append((a, a + 1, a + 1 + n, a + n))
    buf.add(verts, faces, uvs, cols)


def curve(p0, d0, length, steps, bend, rnd, up_pull=0.0, gravity=0.0):
    pts = [p0.copy()]
    d = d0.normalized()
    seg = length / steps
    for i in range(steps):
        d = (d + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.5, 0.5))) * bend + Vector((0, 0, up_pull - gravity * i / steps))).normalized()
        pts.append(pts[-1] + d * seg)
    return pts


CELLS = [(0.0, 0.5), (0.5, 0.5), (0.0, 0.0), (0.5, 0.0)]   # Blender UV origins (v up) of the 4 twig cells


def card(buf, at, direction, size, rnd, cell, crown_c, crown_r, bottom, top):
    """One leaf-twig card hanging from `at` along `direction`, turned randomly about it."""
    d = direction.normalized()
    f, r, u = frame(d)
    rot = rnd.uniform(0, math.tau)
    side = (r * math.cos(rot) + u * math.sin(rot)).normalized()
    nrm = d.cross(side).normalized()
    w, h = size * 0.9, size
    ox, oy = CELLS[cell]
    corners = [(-0.5, 0.0), (0.5, 0.0), (0.5, 1.0), (-0.5, 1.0)]
    verts, uvs, cols, nrms = [], [], [], []
    for cx, cy in corners:
        p = at + side * (cx * w) + d * (cy * h)
        verts.append(p)
        uvs.append((ox + (cx + 0.5) * 0.5, oy + cy * 0.5))
        radial = min(1.0, (p - crown_c).length / max(crown_r, 0.1))
        hgt = min(1.0, max(0.0, (p.z - bottom) / max(top - bottom, 0.1)))
        ao = 0.28 + 0.52 * radial ** 1.3 + 0.25 * hgt
        cols.append((min(ao, 1.0), hgt, rnd.random()))
        bent = (p - crown_c).normalized()
        if nrm.dot(bent) < 0:
            nrm_use = -nrm
        else:
            nrm_use = nrm
        nrms.append((bent * 0.6 + nrm_use * 0.4).normalized())
    buf.add(verts, [(0, 1, 2, 3)], uvs, cols, nrms)


def tree(name, seed, trunk_h, trunk_r, limbs, limb_len, card_size, cards_per_twig, cells, lean=0.03, crown_start=0.55, gravity=0.0):
    rnd = random.Random(seed)
    bark, leaves = Buf(), Buf()
    far_bark, far_leaves = Buf(), Buf()
    base = Vector((0, 0, -0.4))
    tp = curve(base, Vector((rnd.uniform(-lean, lean), rnd.uniform(-lean, lean), 1)), trunk_h, 16, 0.025, rnd)
    tr = [trunk_r * (1.0 + 0.55 * max(0.0, 1 - i / 1.6) ** 2) * (1 - 0.55 * i / (len(tp) - 1)) for i in range(len(tp))]
    tube(bark, tp, tr, 12)
    tube(far_bark, tp[::2] + ([tp[-1]] if len(tp) % 2 == 0 else []), tr[::2] + ([tr[-1]] if len(tr) % 2 == 0 else []), 6)
    # shallow root flare: humps that sink into the soil a metre out
    for k in range(5):
        a = math.tau * (k + rnd.uniform(-0.2, 0.2)) / 5
        st = base + Vector((0, 0, 0.75)) + Vector((math.cos(a), math.sin(a), 0)) * trunk_r * 0.5
        pts = [st + Vector((math.cos(a), math.sin(a), 0)) * (trunk_r * 2.4 * t) + Vector((0, 0, -0.95 * t ** 0.7)) for t in [j / 5 for j in range(6)]]
        tube(bark, pts, [trunk_r * 0.45 * (1 - j / 6) + 0.03 for j in range(6)], 8)
    twig_ends = []
    z0 = trunk_h * crown_start
    for k in range(limbs):
        a = math.tau * (k + rnd.uniform(-0.35, 0.35)) / limbs
        t = rnd.uniform(crown_start, 0.96)
        i0 = min(int(t * (len(tp) - 1)), len(tp) - 2)
        start = tp[i0]
        out = Vector((math.cos(a), math.sin(a), 0))
        d = (out * rnd.uniform(0.6, 1.0) + Vector((0, 0, rnd.uniform(0.9, 1.6)))).normalized()
        L = limb_len * rnd.uniform(0.7, 1.15) * (1.15 - 0.4 * (t - crown_start))
        pts = curve(start, d, L, 8, 0.1, rnd, up_pull=0.0, gravity=gravity)
        r0 = tr[i0] * rnd.uniform(0.38, 0.5)
        rr = [r0 * (1 - 0.8 * j / (len(pts) - 1)) + 0.015 for j in range(len(pts))]
        tube(bark, pts, rr, 6, around=1.0)
        tube(far_bark, [pts[0], pts[len(pts) // 2], pts[-1]], [rr[0], rr[len(rr) // 2], rr[-1]], 4, around=1.0)
        for j in range(3, len(pts)):
            nb = 2 if j < len(pts) - 1 else 3
            for b2 in range(nb):
                d2 = ((pts[j] - pts[j - 1]).normalized() + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.6, 0.5))) * 1.1).normalized()
                p2 = curve(pts[j], d2, L * rnd.uniform(0.25, 0.42), 4, 0.25, rnd, gravity=0.35 + gravity)
                tube(bark, p2, [rr[j] * 0.55 * (1 - q / 5) + 0.008 for q in range(len(p2))], 4, around=0.5)
                twig_ends.append((p2[2], (p2[3] - p2[1]).normalized()))
                twig_ends.append((p2[-1], (p2[-1] - p2[-2]).normalized()))
    top_pt = tp[-1]
    cps = [p for p, _ in twig_ends]
    crown_c = sum(cps, Vector()) / max(len(cps), 1)
    crown_r = max((p - crown_c).length for p in cps) if cps else 4.0
    bottom = min(p.z for p in cps) - card_size
    top = max(p.z for p in cps) + card_size
    for idx, (p, d) in enumerate(twig_ends):
        for c in range(cards_per_twig):
            dd = (d + Vector((rnd.uniform(-0.9, 0.9), rnd.uniform(-0.9, 0.9), rnd.uniform(-0.7, 0.4)))).normalized()
            at = p + Vector((rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), rnd.uniform(-0.3, 0.3))) - dd * card_size * 0.15
            sz = card_size * rnd.uniform(0.8, 1.2)
            cell = cells[rnd.randrange(len(cells))]
            card(leaves, at, dd, sz, rnd, cell, crown_c, crown_r, bottom, top)
            if (idx * cards_per_twig + c) % 3 == 0:
                card(far_leaves, at, dd, sz * 1.55, rnd, cell, crown_c, crown_r, bottom, top)
    for nm, b in ((name + "_Bark", bark), (name + "_Leaves", leaves), (name + "_FarBark", far_bark), (name + "_FarLeaves", far_leaves)):
        b.build(nm)
    print(name, "cards", len(leaves.f), "far cards", len(far_leaves.f), "bark tris", len(bark.f) * 2)
    # Godot space: x, y(up)=z, z=-y
    return {"canopy_center": [crown_c.x, crown_c.z, -crown_c.y], "canopy_radius": crown_r, "canopy_bottom": bottom, "canopy_top": top, "height": top}


info = {}
info["RealBeech_A"] = tree("RealBeech_A", 3, 21.0, 0.36, 7, 7.5, 1.5, 4, [0, 1, 2], lean=0.03, crown_start=0.5)
info["RealBeech_B"] = tree("RealBeech_B", 7, 17.0, 0.31, 6, 6.5, 1.4, 4, [0, 1, 2], lean=0.05, crown_start=0.48)
info["RealMaple"] = tree("RealMaple", 13, 14.0, 0.33, 7, 6.0, 1.4, 4, [3, 3, 0], lean=0.06, crown_start=0.42, gravity=0.1)
info["RealOak"] = tree("RealOak", 29, 12.0, 0.5, 8, 7.5, 1.5, 4, [1, 2, 0], lean=0.08, crown_start=0.38, gravity=0.18)
info["RealYoung"] = tree("RealYoung", 41, 7.0, 0.11, 5, 2.6, 1.0, 3, [2, 0], lean=0.08, crown_start=0.35)
with open(os.path.join(OUT_DIR, "real_trees.json"), "w") as f:
    json.dump(info, f, indent=1)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "real_trees.glb"), export_format='GLB', use_selection=True, export_apply=True,
                          export_yup=True, export_materials='NONE', export_normals=True, export_texcoords=True, export_vertex_color='ACTIVE')
print("exported")
