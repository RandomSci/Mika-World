"""Hero trees for the Woods viewpoint (visual quality pass): real branching trunks with buttress roots and
leaf-clump canopies with broken silhouettes, instead of the kit's rounded blob crowns.

  blender -b --python tools/models/build_hero_trees.py -- <out_dir> [preview.png]

Writes <out_dir>/hero_trees.glb (objects <Name>_Bark, <Name>_Leaves for each variant) and hero_trees.json
(per variant: canopy centre / radius / bottom / top in model space, for the foliage shader). The leaf clumps use
<out_dir>/leaf_clumps.png, composed here from the CC0 nature kit's painted leaf sprites (assets/nature/snm/
Leaves.png) - many leaves per card, so a crown reads as hundreds of leaves with ~300 cards.
Leaves carry vertex colour (R,G = AO/sun exposure, B = per-clump variation) and normals bent toward each clump's
centre (soft, painterly shading). Bark UVs are cylindrical (u around, v along the length).
"""
import json
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "."
PREVIEW = argv[1] if len(argv) > 1 else ""
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
os.makedirs(OUT_DIR, exist_ok=True)


# the leaf clump atlas is painted by tools/textures/leaf_clumps.py (system Python: Blender has no PIL)
if not os.path.exists(os.path.join(OUT_DIR, "leaf_clumps.png")):
    raise SystemExit("run tools/textures/leaf_clumps.py first")

# ----------------------------------------------------------------------------------------- geometry helpers
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def frame(fwd, up_hint=Vector((0, 0, 1))):
    f = Vector(fwd).normalized()
    r = f.cross(up_hint)
    if r.length < 1e-4:
        r = f.cross(Vector((1, 0, 0)))
    r.normalize()
    u = r.cross(f).normalized()
    return f, r, u


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

    def build(self, name, smooth=True):
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
            poly.use_smooth = smooth
            for li in poly.loop_indices:
                uv.data[li].uv = self.uv[me.loops[li].vertex_index]
        if any(n is not None for n in self.n):
            loop_normals = []
            for lp in me.loops:
                n = self.n[lp.vertex_index]
                loop_normals.append(tuple(n) if n is not None else (0, 0, 1))
            try:
                me.normals_split_custom_set(loop_normals)
            except Exception as e:
                print("custom normals failed:", e)
        return ob


def tube(buf, pts, radii, sides, u_scale=1.0, v_scale=0.5, v0=0.0):
    """A tapered tube along pts (Vectors) with per-point radii; bark UVs (u around, v along)."""
    rings = []
    prev_r = None
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if prev_r is None:
            f, r, u = frame(d)
        else:
            # parallel transport the frame (no twisting)
            r = (prev_r - d * prev_r.dot(d)).normalized()
            u = d.cross(r).normalized()
        prev_r = r
        rings.append((p, r, u, radii[i]))
    verts, faces, uvs, cols = [], [], [], []
    vlen = v0
    for i, (p, r, u, rad) in enumerate(rings):
        if i > 0:
            vlen += (p - rings[i - 1][0]).length
        for s in range(sides + 1):
            a = 2 * math.pi * s / sides
            wob = 1.0 + 0.08 * noise.noise(p * 1.7 + Vector((math.cos(a), math.sin(a), 0)) * 0.8)
            verts.append(p + (r * math.cos(a) + u * math.sin(a)) * rad * wob)
            uvs.append((u_scale * s / sides, vlen * v_scale))
            cols.append((1.0, 1.0, 1.0))
    n = sides + 1
    for i in range(len(rings) - 1):
        for s in range(sides):
            a = i * n + s
            faces.append((a, a + 1, a + 1 + n, a + n))
    buf.add(verts, faces, uvs, cols)
    return vlen


def curve(p0, d0, length, steps, bend, rnd, up_pull=0.0):
    pts = [p0.copy()]
    d = d0.normalized()
    seg = length / steps
    for i in range(steps):
        jitter = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.4, 0.6))) * bend
        d = (d + jitter + Vector((0, 0, up_pull))).normalized()
        pts.append(pts[-1] + d * seg)
    return pts


CELLS = [(0.0, 0.5), (0.5, 0.5), (0.0, 0.0), (0.5, 0.0)]   # Blender UV origins of the 4 clump cells (v up)


def clump(buf, center, crown_c, crown_r, size, count, rnd, cell, bottom, top, variation):
    """A puffy mass of leaf cards around `center`; normals bent toward the clump and the crown."""
    verts, faces, uvs, cols, nrms = [], [], [], [], []
    for k in range(count):
        dvec = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 0.8))).normalized()
        c = center + dvec * size * rnd.uniform(0.15, 0.5)
        out = (c - center).normalized() * 0.6 + (c - crown_c).normalized() * 0.4
        if out.length < 1e-3:
            out = Vector((0, 0, 1))
        out.normalize()
        # cards face roughly outward but tilt randomly so the clump has depth from every side
        f, r, u = frame(out + Vector((rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6), rnd.uniform(-0.3, 0.5))))
        rot = rnd.uniform(0, math.tau)
        rr = r * math.cos(rot) + u * math.sin(rot)
        uu = f.cross(rr).normalized()
        s = size * rnd.uniform(0.75, 1.15)
        corners = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
        base = len(verts)
        ox, oy = CELLS[cell if cell >= 0 else rnd.randrange(4)]
        for cx, cy in corners:
            p = c + rr * (cx * s) + uu * (cy * s)
            verts.append(p)
            uvs.append((ox + (cx + 0.5) * 0.5, oy + (cy + 0.5) * 0.5))
            # exposure: outside and top of the crown bright, the inside and underside dark (AO)
            radial = min(1.0, (p - crown_c).length / max(crown_r, 0.1))
            hgt = min(1.0, max(0.0, (p.z - bottom) / max(top - bottom, 0.1)))
            ao = 0.35 + 0.45 * radial + 0.3 * hgt
            cols.append((min(ao, 1.0), hgt, variation))
            nb = (p - center).normalized() * 0.55 + (p - crown_c).normalized() * 0.45
            nrms.append(nb.normalized())
        faces.append((base, base + 1, base + 2, base + 3))
    buf.add(verts, faces, uvs, cols, nrms)


# ----------------------------------------------------------------------------------------- one tree
def tree(name, seed, height, spread, limbs, trunk_r, clump_size, lean=0.05, cell=-1, clump_count=11, roots=6):
    rnd = random.Random(seed)
    bark, leaves = Buf(), Buf()
    base = Vector((0, 0, -0.3))
    # trunk: a gently curved column, flared at the base
    tp = curve(base, Vector((rnd.uniform(-lean, lean), rnd.uniform(-lean, lean), 1)), height * 0.62, 10, 0.06, rnd)
    tr = [trunk_r * (1.0 + 1.1 * max(0.0, 1 - i / 2.2) ** 2) * (1 - 0.4 * i / (len(tp) - 1)) for i in range(len(tp))]
    vlen = tube(bark, tp, tr, 14, u_scale=2.0, v_scale=0.4)
    # buttress roots spreading over the ground
    for k in range(roots):
        a = math.tau * (k + rnd.uniform(-0.25, 0.25)) / roots
        start = base + Vector((0, 0, rnd.uniform(0.9, 1.4))) + Vector((math.cos(a), math.sin(a), 0)) * trunk_r * 0.45
        pts = [start]
        L = rnd.uniform(1.3, 2.2) * trunk_r / 0.4
        for j in range(1, 8):
            t = j / 7
            # a buttress: leaves the trunk steeply, flattens over the ground, dives in at the end
            pts.append(start + Vector((math.cos(a), math.sin(a), 0)) * (L * t) + Vector((0, 0, -start.z * (1 - (1 - t) ** 2.2) - 0.25 * t * t)))
        rr = [trunk_r * 0.62 * (1 - j / len(pts)) ** 1.1 + 0.04 for j in range(len(pts))]
        tube(bark, pts, rr, 9, u_scale=1.0, v_scale=0.5)
    top = tp[-1]
    crown_c = top + Vector((0, 0, height * 0.12))
    crown_r = spread
    clumps = []
    # main limbs: from the upper trunk outward and up, each forking twice
    for k in range(limbs):
        a = math.tau * (k + rnd.uniform(-0.3, 0.3)) / limbs
        i0 = int(len(tp) * rnd.uniform(0.55, 0.95))
        start = tp[min(i0, len(tp) - 1)]
        out = Vector((math.cos(a), math.sin(a), 0))
        d = (out * rnd.uniform(0.7, 1.1) + Vector((0, 0, rnd.uniform(0.6, 1.2)))).normalized()
        L = spread * rnd.uniform(0.85, 1.2)
        pts = curve(start, d, L, 7, 0.14, rnd, up_pull=0.02)
        r0 = tr[min(i0, len(tr) - 1)] * rnd.uniform(0.45, 0.6)
        tube(bark, pts, [r0 * (1 - 0.75 * j / (len(pts) - 1)) + 0.02 for j in range(len(pts))], 9, u_scale=1.0, v_scale=0.5)
        for j in (3, 5, 7):
            if j >= len(pts):
                continue
            for b2 in range(2):
                d2 = ((pts[j] - pts[j - 1]).normalized() + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.2, 0.9))) * 0.9).normalized()
                p2 = curve(pts[j], d2, L * rnd.uniform(0.3, 0.5), 4, 0.2, rnd)
                rj = r0 * (1 - 0.75 * j / 7) * 0.55
                tube(bark, p2, [rj * (1 - 0.8 * q / 4) + 0.012 for q in range(len(p2))], 6, u_scale=0.6, v_scale=0.6)
                clumps.append(p2[-1] + Vector((0, 0, clump_size * 0.2)))
                clumps.append(p2[len(p2) // 2] + Vector((0, 0, clump_size * 0.35)))
        clumps.append(pts[-1] + Vector((0, 0, clump_size * 0.25)))
    # fill the crown: extra clumps on the shell so the canopy reads as one mass with a broken edge
    for k in range(int(limbs * 3)):
        dvec = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), abs(rnd.gauss(0.3, 0.6)))).normalized()
        clumps.append(crown_c + Vector((dvec.x * crown_r, dvec.y * crown_r, dvec.z * crown_r * 0.6)) * rnd.uniform(0.55, 0.95))
    zs = [c.z for c in clumps]
    bottom, ctop = min(zs) - clump_size, max(zs) + clump_size
    for c in clumps:
        clump(leaves, c, crown_c, crown_r, clump_size * rnd.uniform(0.85, 1.2), clump_count, rnd, cell, bottom, ctop, rnd.random())
    bo = bark.build(name + "_Bark", smooth=True)
    lo = leaves.build(name + "_Leaves", smooth=True)
    return {"canopy_center": [crown_c.x, crown_c.z, -crown_c.y], "canopy_radius": crown_r, "canopy_bottom": bottom, "canopy_top": ctop,
            "height": ctop, "cards": len(leaves.f), "bark_tris": len(bark.f) * 2}


info = {}
info["HeroOak_A"] = tree("HeroOak_A", 11, 11.0, 4.8, 7, 0.55, 1.75, lean=0.07, cell=-1, clump_count=12)
info["HeroOak_B"] = tree("HeroOak_B", 23, 13.0, 5.4, 8, 0.62, 1.9, lean=0.09, cell=-1, clump_count=12)
info["HeroBeech"] = tree("HeroBeech", 37, 14.5, 4.0, 6, 0.44, 1.65, lean=0.04, cell=1, clump_count=11)
info["HeroWillow"] = tree("HeroWillow", 51, 9.5, 4.3, 7, 0.48, 1.55, lean=0.14, cell=2, roots=6, clump_count=12)
info["HeroShrub"] = None
# shrubs: just clumps on short stems
for nm, seed in (("HeroShrub_A", 61), ("HeroShrub_B", 67)):
    rnd = random.Random(seed)
    bark, leaves = Buf(), Buf()
    cc = Vector((0, 0, 0.8))
    for k in range(7):
        a = math.tau * k / 7 + rnd.uniform(-0.3, 0.3)
        c = Vector((math.cos(a) * rnd.uniform(0.4, 0.9), math.sin(a) * rnd.uniform(0.4, 0.9), rnd.uniform(0.5, 1.2)))
        tube(bark, [Vector((0, 0, -0.1)), c * 0.5, c], [0.05, 0.035, 0.015], 5)
        clump(leaves, c, cc, 1.1, 0.9, 9, rnd, 3, 0.0, 1.9, rnd.random())
    clump(leaves, Vector((0, 0, 1.25)), cc, 1.1, 1.0, 10, rnd, 0, 0.0, 1.9, rnd.random())
    bark.build(nm + "_Bark")
    leaves.build(nm + "_Leaves")
    info[nm] = {"canopy_center": [0, 0.8, 0], "canopy_radius": 1.1, "canopy_bottom": 0.0, "canopy_top": 1.9, "height": 1.9}
del info["HeroShrub"]
for k, v in info.items():
    print(k, v)
with open(os.path.join(OUT_DIR, "hero_trees.json"), "w") as f:
    json.dump(info, f, indent=1)

if PREVIEW:
    atlas = bpy.data.images.load(os.path.join(OUT_DIR, "leaf_clumps.png"))
    barkimg = bpy.data.images.load(os.path.join(ROOT, "assets/nature/snm/Bark_NormalTree.png"))
    ml = bpy.data.materials.new("L")
    ml.use_nodes = True
    nt = ml.node_tree
    bs = nt.nodes["Principled BSDF"]
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = atlas
    nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"])
    nt.links.new(tx.outputs["Alpha"], bs.inputs["Alpha"])
    mb = bpy.data.materials.new("B")
    mb.use_nodes = True
    tb = mb.node_tree.nodes.new("ShaderNodeTexImage")
    tb.image = barkimg
    mb.node_tree.links.new(tb.outputs["Color"], mb.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    x = -14.0
    for ob in list(bpy.data.objects):
        if ob.type != 'MESH':
            continue
        ob.data.materials.append(ml if ob.name.endswith("Leaves") else mb)
    for k in info:
        for suffix in ("_Bark", "_Leaves"):
            ob = bpy.data.objects.get(k + suffix)
            if ob:
                ob.location.x = x
        x += 9.0 if not k.startswith("HeroShrub") else 4.0
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 700
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.7, 0.9, 1)
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.5
    sun.rotation_euler = Euler((math.radians(50), 0, math.radians(30)))
    bpy.context.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 28
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    cam.location = Vector((4, -34, 8))
    cam.rotation_euler = (Vector((4, 0, 6)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            ob.data.materials.clear()
            ob.location.x = 0.0
    bpy.data.objects.remove(sun)
    bpy.data.objects.remove(cam)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "hero_trees.glb"), export_format='GLB', use_selection=True, export_apply=True,
                          export_yup=True, export_materials='NONE', export_normals=True, export_texcoords=True, export_vertex_color='ACTIVE')
print("exported", os.path.join(OUT_DIR, "hero_trees.glb"))
