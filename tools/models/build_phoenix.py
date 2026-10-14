"""Builds ORIEL, the female Phoenix of Mika World - her TRUE FORM - as an original rigged, skinned and animated
model, and exports a GLB with every clip the game plays.

  blender -b --python tools/models/build_phoenix.py -- <out.glb> [preview_dir] [atlas.png]

Design (original; no reference imagery, no third-party meshes or textures)
  * A large, long-necked fire-bird: ~2.7 m tall standing, ~7.6 m wingspan, two tail streamers ending in a
    sun-eye. Weight sits over the legs; deep keeled chest; an S-curved neck; hooked golden beak; radiant eyes;
    a crown of five plumes and two ear tufts.
  * LAYERED FEATHER GEOMETRY: contour feathers shingled in offset rows over body, neck, head and thighs; each
    wing carries 10 primaries, 12 secondaries, 5 tertials, three rows of upper coverts, under-coverts and an
    alula; a 7-feather tail fan with coverts; the streamers. Feathers are card strips with UVs into the feather
    atlas (tools/models/phoenix_textures.py); colour is per-vertex (deep crimson -> ember -> gold -> white-gold).
  * ARMATURE (~120 bones): body chain, S-neck, head, lower beak, crest, eyes; wing arm chains (Shoulder,
    Humerus, Radius, Hand); ONE BONE PER FLIGHT FEATHER (Prim0-9, Sec0-11, Ter0-4 per wing) and per tail
    feather (TailF0-6), so the wing really FOLDS: each feather turns about its own root to lie along the flank,
    the fan closes and opens, primaries twist apart on the upstroke. Coverts ride on the flight feather beside
    them. Legs: Hip, Tibia, Tarsus, Foot, four toes with talons. Rest pose = wings spread.
  * POSES are solved, not guessed: a small forward-kinematics solver aims bones at directions given in the
    chest's frame (the folded wing) and blends with authored joint angles (flapping), per key.
  * CLIPS (30 fps): idle, breathe, look, wing_spread, wing_fold, walk, turn_left, turn_right, takeoff, fly,
    glide, bank_left, bank_right, hover, land, cast_fire, defend, attack, react, recover, preen, call, bow,
    stretch, perch_settle. In place (the game moves her); Root carries only small bobs and crouches.
Axes: Blender Z up, she faces -Y (Godot +Z after export). Joint-angle conventions (left side; right mirrors as
(x, -y, -z)): wing bones X+ raises, Z+ sweeps back, Y+ pronates (leading edge down); body/head/tail bones
X+ lifts the bone's tip; neck bones X+ bends forward/down; Root: X+ pitches nose-down, Y+ yaws left,
Z+ rolls right (left wing up).
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "phoenix_true.glb"
PREVIEW = argv[1] if len(argv) > 1 else ""
ATLAS = argv[2] if len(argv) > 2 else ""

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30
random.seed(11)

# ----------------------------------------------------------------------------------------- palette
# v3 (visual pass 2, after the developer's references): a body of red fire, wings that burn from molten gold at
# the shoulder through orange and scarlet to crimson-magenta tips, gold filigree coverts, and a long violet-
# crimson train of tail plumes. Emission (the fire) is added in the shader; these are the feathers' own colours.
DEEP = (0.36, 0.02, 0.05)
CRIMSON = (0.72, 0.04, 0.06)
SCARLET = (0.93, 0.13, 0.04)
EMBER = (1.0, 0.36, 0.05)
AMBER = (1.0, 0.58, 0.12)
GOLD = (1.0, 0.78, 0.26)
BRIGHT = (1.0, 0.92, 0.6)
WHITEGOLD = (1.0, 0.97, 0.84)
MAGENTA = (0.86, 0.07, 0.34)
VIOLET = (0.46, 0.05, 0.42)
ROSE = (1.0, 0.5, 0.62)


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def grad(s, stops):
    if s <= stops[0][0]:
        return stops[0][1]
    for (s0, c0), (s1, c1) in zip(stops, stops[1:]):
        if s <= s1:
            return lerp(c0, c1, (s - s0) / max(s1 - s0, 1e-6))
    return stops[-1][1]


PRIM_GRAD = [(0.0, DEEP), (0.28, CRIMSON), (0.58, SCARLET), (0.84, EMBER), (1.0, AMBER)]   # dark roots, burning tips
SEC_GRAD = [(0.0, DEEP), (0.3, CRIMSON), (0.62, SCARLET), (0.88, EMBER), (1.0, AMBER)]
COVERT_GRAD = [(0.0, CRIMSON), (0.55, SCARLET), (1.0, EMBER)]
TAIL_GRAD = [(0.0, SCARLET), (0.4, CRIMSON), (0.78, MAGENTA), (1.0, VIOLET)]
CREST_GRAD = [(0.0, CRIMSON), (0.35, EMBER), (0.7, GOLD), (1.0, WHITEGOLD)]
STREAM_GRAD = [(0.0, SCARLET), (0.3, CRIMSON), (0.62, MAGENTA), (0.88, VIOLET), (1.0, ROSE)]
FLAME_GRAD = [(0.0, BRIGHT), (0.35, AMBER), (0.7, EMBER), (1.0, SCARLET)]

# ----------------------------------------------------------------------------------------- armature
arm_data = bpy.data.armatures.new("PhoenixArmature")
arm = bpy.data.objects.new("Armature", arm_data)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
EB = {}
KIND = {}
FEATHER = {}       # feather bone -> {"parent", "dir" (rest, armature space), "group", "i", "n"}


def mir(v):
    return Vector((-v[0], v[1], v[2]))


def bone(name, head, tail, parent=None, up=(0, 0, 1), kind="body"):
    eb = arm_data.edit_bones.new(name)
    eb.head = Vector(head)
    eb.tail = Vector(tail)
    if parent:
        eb.parent = EB[parent]
    eb.align_roll(Vector(up))
    EB[name] = eb
    KIND[name] = kind
    return eb


def pair(name, head, tail, parent, up=(0, 0, 1), kind="body"):
    for sfx, sx in (("_L", 1), ("_R", -1)):
        p = parent if (parent is None or parent in EB) else parent + sfx
        h, t, u = Vector(head), Vector(tail), Vector(up)
        if sx < 0:
            h, t, u = mir(h), mir(t), mir(u)
        bone(name + sfx, h, t, p, u, kind)


bone("Root", (0, 0, 0), (0, 0, 0.4), None, up=(0, -1, 0), kind="root")
bone("Hips", (0, 0.30, 1.32), (0, -0.05, 1.48), "Root")
bone("Spine", (0, -0.05, 1.48), (0, -0.45, 1.62), "Hips")
bone("Chest", (0, -0.45, 1.62), (0, -0.88, 1.78), "Spine")
HZ = 0.08   # v4 (the developer: "slightly shorten the neck"): 14 cm lower than v3 (0.22)
bone("Neck1", (0, -0.88, 1.78), (0, -1.06, 2.05), "Chest", up=(0, -1, 0))
bone("Neck2", (0, -1.06, 2.05), (0, -1.14, 2.33), "Neck1", up=(0, -1, 0))
bone("Neck3", (0, -1.14, 2.33), (0, -1.17, 2.6 + HZ), "Neck2", up=(0, -1, 0))
bone("Head", (0, -1.17, 2.6 + HZ), (0, -1.46, 2.68 + HZ), "Neck3")
bone("Beak_Lower", (0, -1.42, 2.58 + HZ), (0, -1.72, 2.5 + HZ), "Head")
bone("Crest1", (0, -1.26, 2.76 + HZ), (0, -1.02, 3.02 + HZ), "Head")
bone("Crest2", (0, -1.02, 3.02 + HZ), (0, -0.74, 3.18 + HZ), "Crest1")
bone("Crest3", (0, -0.74, 3.18 + HZ), (0, -0.4, 3.24 + HZ), "Crest2")
pair("Eye", (0.084, -1.385, 2.675 + HZ), (0.084, -1.445, 2.675 + HZ), "Head")   # v4: the eye sat inside the head surface
bone("TailBase", (0, 0.30, 1.32), (0, 0.82, 1.24), "Hips")
bone("Tail1", (0, 0.82, 1.24), (0, 1.32, 1.12), "TailBase")
bone("Tail2", (0, 1.32, 1.12), (0, 1.8, 0.98), "Tail1")
pair("Stream1", (0.06, 1.8, 0.98), (0.16, 2.46, 0.8), "Tail2")
pair("Stream2", (0.16, 2.46, 0.8), (0.27, 3.12, 0.58), "Stream1")
pair("Stream3", (0.27, 3.12, 0.58), (0.37, 3.76, 0.42), "Stream2")
pair("Shoulder", (0.18, -0.5, 1.72), (0.48, -0.52, 1.8), "Chest", kind="arm")
pair("Humerus", (0.48, -0.52, 1.8), (1.2, -0.46, 1.87), "Shoulder", kind="arm")
pair("Radius", (1.2, -0.46, 1.87), (2.1, -0.56, 1.87), "Humerus", kind="arm")
pair("Hand", (2.1, -0.56, 1.87), (2.96, -0.8, 1.8), "Radius", kind="arm")
pair("Hip", (0.2, 0.22, 1.2), (0.25, 0.02, 0.86), "Hips", up=(0, -1, 0), kind="leg")
pair("Tibia", (0.25, 0.02, 0.86), (0.27, 0.3, 0.46), "Hip", up=(0, -1, 0), kind="leg")
pair("Tarsus", (0.27, 0.3, 0.46), (0.27, 0.06, 0.1), "Tibia", up=(0, -1, 0), kind="leg")
pair("Foot", (0.27, 0.06, 0.1), (0.27, -0.14, 0.04), "Tarsus", up=(0, 0, 1), kind="leg")
pair("Toe_B", (0.27, 0.08, 0.06), (0.27, 0.3, 0.02), "Foot", up=(0, 0, 1), kind="leg")
TOES = ((-0.14, -0.3), (0.0, -0.36), (0.15, -0.28))
for k, (dx, dy) in enumerate(TOES):
    pair("Toe_%d" % k, (0.27, -0.12, 0.05), (0.27 + dx, -0.12 + dy, 0.01), "Foot", up=(0, 0, 1), kind="leg")

UP = Vector((0, 0, 1))
BACK = Vector((0, 1, 0))


def _row(a, b, count, angs, lens, t0, t1):
    ax = (b - a).normalized()
    side = ax.cross(UP).normalized()
    if side.dot(BACK) < 0:
        side = -side
    out = []
    for i in range(count):
        u = i / max(count - 1, 1)
        t = t0 + (t1 - t0) * u
        ang = math.radians(angs[i] if len(angs) == count else angs[0] + (angs[1] - angs[0]) * u)
        L = lens[i] if len(lens) == count else lens[0] + (lens[1] - lens[0]) * u
        d = (ax * math.cos(ang) + side * math.sin(ang)).normalized()
        out.append({"root": a.lerp(b, t), "dir": d, "len": L, "t": t})
    return out


def _seg(name):
    # edit bones are only valid in edit mode: after it, read the armature's rest data (BONES)
    if "BONES" in globals():
        return BONES[name + "_L"][0].copy(), BONES[name + "_L"][1].copy()
    return EB[name + "_L"].head.copy(), EB[name + "_L"].tail.copy()


PRIM_LEN = [1.48, 1.54, 1.62, 1.72, 1.84, 1.96, 2.04, 2.06, 1.98, 1.8]   # v3c: a soaring bird's wing (the condor reference)
# the inner primaries continue the secondaries' straight trailing edge; the outer five spread as FINGERS
PRIM_ANG = [84, 78, 71, 63, 55, 45, 35, 26, 17, 9]
LAYOUT = {
    "Prim": ("Hand", _row(*_seg("Hand"), 10, PRIM_ANG, PRIM_LEN, 0.02, 0.98), 0.46, PRIM_GRAD),
    "Sec": ("Radius", _row(*_seg("Radius"), 12, (90, 84), (1.32, 1.45), 0.0, 0.98), 0.44, SEC_GRAD),
    "Ter": ("Humerus", _row(*_seg("Humerus"), 5, (100, 92), (1.12, 1.26), 0.1, 0.95), 0.42, SEC_GRAD),
}
for grp, (parent, rows, _w, _g) in LAYOUT.items():
    for i, r in enumerate(rows):
        for sfx, sx in (("_L", 1), ("_R", -1)):
            root, d = (r["root"], r["dir"]) if sx > 0 else (mir(r["root"]), mir(r["dir"]))
            n = "%s%d%s" % (grp, i, sfx)
            bone(n, root, root + d * 0.3, parent + sfx, up=(0, 0, 1), kind="feather")
            FEATHER[n] = {"parent": parent + sfx, "dir": d.copy(), "group": grp, "i": i, "n": len(rows)}

T0, T1 = EB["Tail2"].head.copy(), EB["Tail2"].tail.copy()
TAX = (T1 - T0).normalized()
TAIL_ROWS = []
NTAIL = 9
for i in range(NTAIL):
    k = (i - 4) / 4.0
    ang = math.radians(k * 40)
    d = (TAX * math.cos(ang) + Vector((1, 0, 0)) * math.sin(ang)).normalized()
    root = T0 + TAX * 0.12 + Vector((0, 0, 0.03 * (1 - abs(k))))
    TAIL_ROWS.append({"root": root, "dir": d, "len": 1.9 - 0.36 * abs(k), "k": k})
    n = "TailF%d" % i
    bone(n, root, root + d * 0.3, "Tail2", up=(0, 0, 1), kind="tailfan")
    FEATHER[n] = {"parent": "Tail2", "dir": d.copy(), "group": "Tail", "i": i, "n": NTAIL}

bpy.ops.object.mode_set(mode='OBJECT')
for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'

REST = {b.name: b.matrix_local.copy() for b in arm.data.bones}
PARENT = {b.name: (b.parent.name if b.parent else None) for b in arm.data.bones}
BONES = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm.data.bones}


def _depth(n):
    d = 0
    while PARENT[n]:
        n = PARENT[n]
        d += 1
    return d


ORDER = sorted(REST.keys(), key=_depth)


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def nearest_weights(p, names, k=2, power=2.5, snap=0.45):
    ds = sorted(((seg_dist(p, *BONES[n]), n) for n in names))[:k]
    if len(ds) == 1 or ds[0][0] < snap * ds[1][0]:
        return [(ds[0][1], 1.0)]
    ws = [(n, 1.0 / max(d, 0.02) ** power) for d, n in ds]
    s = sum(w for _, w in ws)
    return [(n, w / s) for n, w in ws]


# ----------------------------------------------------------------------------------------- mesh helpers
class MeshBuf:
    def __init__(self, name):
        self.name = name
        self.v, self.f, self.uv, self.c, self.w, self.n, self.uv2 = [], [], [], [], [], [], []

    def add(self, verts, faces, uvs, cols, weights, normals=None, uv2=None):
        base = len(self.v)
        self.v += [tuple(p) for p in verts]
        self.f += [tuple(base + i for i in face) for face in faces]
        self.uv += list(uvs)
        self.c += list(cols)
        self.w += list(weights)
        self.n += list(normals) if normals else [None] * len(verts)
        self.uv2 += list(uv2) if uv2 else [(0.5, 0.0)] * len(verts)

    def build(self, solid=True, subdiv=0):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.v, [], self.f)
        me.update()
        if solid:
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            bm.to_mesh(me)
            bm.free()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(ob)
        ca = me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='POINT')
        for i, c in enumerate(self.c):
            # the palette is written in display (sRGB) terms; vertex colours travel linear (glTF), so convert
            ca.data[i].color = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)
        try:
            me.color_attributes.active_color = ca
            me.color_attributes.render_color_index = 0
        except Exception:
            pass
        uv = me.uv_layers.new(name="UV")
        uvb = me.uv_layers.new(name="UV2")
        has_n = any(n is not None for n in self.n)
        for poly in me.polygons:
            poly.use_smooth = solid or has_n
            for li in poly.loop_indices:
                vi = me.loops[li].vertex_index
                uv.data[li].uv = self.uv[vi]
                uvb.data[li].uv = self.uv2[vi]
        if has_n:
            # feathers shade like the surface they lie on (plumage), not like a thousand separate scales
            ln = []
            for lp in me.loops:
                nn = self.n[lp.vertex_index]
                ln.append(tuple(nn) if nn is not None else (0.0, 0.0, 1.0))
            me.normals_split_custom_set(ln)
        groups = {}
        for i, ws in enumerate(self.w):
            for b, w in ws:
                groups.setdefault(b, []).append((i, w))
        for b, lst in groups.items():
            vg = ob.vertex_groups.new(name=b)
            for i, w in lst:
                vg.add([i], w, 'REPLACE')
        ob.parent = arm
        if subdiv:
            sd = ob.modifiers.new("Subdiv", 'SUBSURF')
            sd.levels = subdiv
            sd.render_levels = subdiv
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
        return ob


def frame(fwd, up_hint=Vector((0, 0, 1))):
    f = Vector(fwd).normalized()
    r = f.cross(Vector(up_hint))
    if r.length < 1e-4:
        r = f.cross(Vector((1, 0, 0)))
    r.normalize()
    u = r.cross(f).normalized()
    return f, r, u


def loft(buf, rings, n=22, color=lambda p, ang, k: CRIMSON, bones=None, cap=True, rigid=None):
    """rings: (center, forward, rx, rz, keel); keel deepens the lower half (a breast keel)."""
    idx = []
    for c, fwd, rx, rz, keel in rings:
        f, r, u = frame(fwd)
        ring = []
        for i in range(n):
            ang = 2 * math.pi * i / n
            s, co = math.sin(ang), math.cos(ang)
            zs = rz * (1 + keel) if s < 0 else rz
            ring.append(Vector(c) + r * (rx * co) + u * (zs * s))
        idx.append(ring)
    verts, faces, uvs, cols, ws = [], [], [], [], []
    for k, ring in enumerate(idx):
        for i, p in enumerate(ring):
            verts.append(p)
            uvs.append((0.62 + 0.3 * i / n, 0.62 + 0.3 * k / max(len(idx) - 1, 1)))
            cols.append(color(p, 2 * math.pi * i / n, k))
            ws.append(rigid if rigid else nearest_weights(p, bones))
    for k in range(len(idx) - 1):
        for i in range(n):
            a = k * n + i
            b = k * n + (i + 1) % n
            faces.append((a, b, b + n, a + n))
    if cap:
        for k, rev in ((0, True), (len(idx) - 1, False)):
            c = sum(idx[k], Vector()) / n
            ci = len(verts)
            verts.append(c)
            uvs.append((0.75, 0.75))
            cols.append(color(c, 0.0, k))
            ws.append(rigid if rigid else nearest_weights(c, bones))
            for i in range(n):
                a = k * n + i
                b = k * n + (i + 1) % n
                faces.append((ci, b, a) if rev else (ci, a, b))
    buf.add(verts, faces, uvs, cols, ws)


def tube(buf, a, b, r0, r1, color, rigid, n=10, steps=3):
    a, b = Vector(a), Vector(b)
    rings = [(a.lerp(b, k / steps), b - a, r0 + (r1 - r0) * k / steps, r0 + (r1 - r0) * k / steps, 0.0) for k in range(steps + 1)]
    loft(buf, rings, n, lambda p, ang, k: color, None, True, rigid)


CELL = {"flight": (0, 0), "contour": (1, 0), "gold": (2, 0), "flame": (3, 0),
        "plume": (0, 1), "streamer": (1, 1), "down": (2, 1), "spark": (3, 1)}
ACOLS, AROWS = 4, 2
_SEED = [0]


def feather(buf, root, direction, up, length, width, cell, gradient, weights, curve=0.08, segs=5, twist=0.0, lift=0.0, raise_=0.0, wave=None, nrm=None, tint=1.0,
            glow=1.0, curl=0.0, curl_from=0.7, taper=0.0):
    """One feather card strip from `root` along `direction`; `up` is its normal. It droops by `curve` x length
    (negative curls up), its tip rises by `lift` x length, it sits `raise_` above its root along the normal
    (shingle stacking) and may wave sideways (amp, cycles). `curl` (radians) rolls the end of the strip
    sideways into a spiral after `curl_from` (the tail plumes' curled ends); `taper` narrows the card toward
    the tip. `weights`: list or s -> list. UV2 = (s + seed, glow): the shaders read the position along the
    feather, a per-feather seed (flicker phases) and how strongly this feather burns."""
    d, side, n = frame(direction, up)
    cx, cy = CELL[cell]
    _SEED[0] = (_SEED[0] + 7) % 16
    seed = float(_SEED[0])
    verts, faces, uvs, cols, ws, uv2 = [], [], [], [], [], []
    # march along the strip: the direction droops and (after curl_from) rolls around the normal
    p = Vector(root) + n * raise_
    dirv = d.copy()
    ds = length / segs
    pts = []
    for k in range(segs + 1):
        s = k / segs
        q = p + n * (lift * length * s) - n * (curve * length * s * s)
        if wave:
            q = q + side * (wave[0] * math.sin(s * 2 * math.pi * wave[1]))
        pts.append((q, dirv.copy()))
        if curl and s >= curl_from:
            dirv = Matrix.Rotation(curl / max(1, round(segs * (1 - curl_from))), 3, n) @ dirv
        p = p + dirv * ds
    for k, (q, dk) in enumerate(pts):
        s = k / segs
        sk = dk.cross(n).normalized() if curl else side
        if sk.dot(side) < 0:
            sk = -sk
        tw = twist * s
        sd = sk * math.cos(tw) + n * math.sin(tw)
        wk = width * (1.0 - taper * s)
        for u in (-1.0, 1.0):
            verts.append(q + sd * (wk * 0.5 * u))
            uvs.append(((cx + (u * 0.5 + 0.5)) / ACOLS, (cy + s) / AROWS))
            gc = grad(s, gradient)
            cols.append((min(1.0, gc[0] * tint), min(1.0, gc[1] * tint), min(1.0, gc[2] * tint)))
            ws.append(weights(s) if callable(weights) else weights)
            uv2.append((min(s, 0.999) + seed, glow))
    for k in range(segs):
        a = k * 2
        faces.append((a, a + 1, a + 3, a + 2))
    buf.add(verts, faces, uvs, cols, ws, [Vector(nrm).normalized()] * len(verts) if nrm is not None else None, uv2)


# ----------------------------------------------------------------------------------------- body
SPINE_BONES = ["Hips", "Spine", "Chest", "Neck1", "Neck2", "Neck3", "Head", "TailBase", "Tail1"]


BODY_STOPS = [(0.0, CRIMSON), (0.35, SCARLET), (0.62, EMBER), (0.82, AMBER), (1.0, GOLD)]


def body_color(p, ang, k):
    return grad((1 - math.sin(ang)) * 0.5, BODY_STOPS)


skin = MeshBuf("Body")
# v3: a slimmer, more upright body (a raptor's waist under a deep breast), the same bones
body_rings = [
    (Vector((0, 0.72, 1.24)), Vector((0, -1, 0.1)), 0.16, 0.14, 0.0),
    (Vector((0, 0.42, 1.3)), Vector((0, -1, 0.15)), 0.26, 0.24, 0.1),
    (Vector((0, 0.1, 1.4)), Vector((0, -1, 0.2)), 0.34, 0.33, 0.25),
    (Vector((0, -0.25, 1.52)), Vector((0, -1, 0.25)), 0.39, 0.42, 0.44),
    (Vector((0, -0.58, 1.64)), Vector((0, -1, 0.3)), 0.37, 0.43, 0.5),      # v4: a deeper breast, broader shoulders
    (Vector((0, -0.82, 1.76)), Vector((0, -0.6, 0.6)), 0.25, 0.27, 0.26),
    (Vector((0, -0.94, 1.9)), Vector((0, -0.4, 1)), 0.15, 0.15, 0.0),
]
loft(skin, body_rings, 24, body_color, SPINE_BONES)
neck_path = [Vector((0, -0.94, 1.9)), Vector((0, -1.06, 2.05)), Vector((0, -1.14, 2.33)), Vector((0, -1.17, 2.6 + HZ)), Vector((0, -1.23, 2.68 + HZ))]
neck_rings = []
for k in range(len(neck_path) - 1):
    r = 0.128 - 0.019 * k          # v4: a stronger neck root flowing from the fuller breast
    neck_rings.append((neck_path[k], neck_path[k + 1] - neck_path[k], r, r, 0.05))
neck_rings.append((neck_path[-1], Vector((0, -0.4, 0.3)), 0.07, 0.07, 0.0))
NECK_COL = lambda p, ang, k: grad((1 - math.sin(ang)) * 0.5, [(0, CRIMSON), (0.6, EMBER), (1, GOLD)])
loft(skin, neck_rings, 18, NECK_COL, ["Neck1", "Neck2", "Neck3", "Head"])
HEAD_C = Vector((0, -1.31, 2.66 + HZ))
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=1.0)
hv, hf, huv, hc, hw = [], [], [], [], []
for v in bm.verts:
    x, y, z = v.co.x, v.co.y, v.co.z
    # a falcon's head, smaller and sleeker than v2: long, narrow toward the beak, a flat crown, a strong brow
    taper = 1.0 - 0.34 * max(0.0, -y)
    p = HEAD_C + Vector((x * 0.104 * taper, y * 0.215 - (0.02 if y < 0 else 0), z * 0.112 * (0.86 if z > 0 else 1.0) + 0.01 * (1 - abs(y))))
    if y < -0.15 and abs(x) > 0.3 and z > 0.1:
        p += Vector((x * 0.016, -0.01, 0.02))             # brow ridge over the eye
    hv.append(p)
    huv.append((0.7, 0.7))
    hc.append(DEEP if (y < -0.15 and abs(x) > 0.3 and z > 0.15) else grad((1 - z) * 0.5, [(0, DEEP), (0.5, CRIMSON), (1, SCARLET)]))
    hw.append([("Head", 1.0)])
for f in bm.faces:
    hf.append(tuple(v.index for v in f.verts))
bm.free()
skin.add(hv, hf, huv, hc, hw)
for sfx, sx in (("_L", 1), ("_R", -1)):
    tube(skin, (0.2 * sx, 0.2, 1.22), (0.26 * sx, 0.04, 0.84), 0.13, 0.09, SCARLET, [("Hip" + sfx, 1.0)], n=12, steps=3)
HEADZ = Vector((0, 0, HZ))
skin.build(solid=True, subdiv=1)

legs = MeshBuf("Legs")
LEG = (0.42, 0.1, 0.06)          # dark red scaled legs (no orange tubes)
LEG_SCALE = (0.7, 0.36, 0.12)
TALON = (0.07, 0.035, 0.03)


def leg_tube(a, b, r0, r1, bone, n=10, steps=4):
    a, b = Vector(a), Vector(b)
    rings = [(a.lerp(b, k / steps), b - a, r0 + (r1 - r0) * k / steps, r0 + (r1 - r0) * k / steps, 0.0) for k in range(steps + 1)]
    loft(legs, rings, n, lambda p, ang, k: LEG_SCALE if (k % 2 == 0 and math.sin(ang) < -0.2) else LEG, None, True, [(bone, 1.0)])


for sfx, sx in (("_L", 1), ("_R", -1)):
    leg_tube((0.26 * sx, 0.04, 0.86), (0.27 * sx, 0.3, 0.46), 0.06, 0.042, "Tibia" + sfx, steps=3)
    leg_tube((0.27 * sx, 0.3, 0.46), (0.27 * sx, 0.06, 0.1), 0.042, 0.036, "Tarsus" + sfx, steps=6)
    leg_tube((0.27 * sx, 0.1, 0.09), (0.27 * sx, -0.14, 0.05), 0.048, 0.04, "Foot" + sfx, steps=2)
    for k, (dx, dy) in enumerate(TOES):
        a = Vector((0.27 * sx, -0.12, 0.05))
        b = Vector(((0.27 + dx) * sx, -0.12 + dy, 0.015))
        leg_tube(a, b, 0.028, 0.02, "Toe_%d%s" % (k, sfx), n=8, steps=3)
        tube(legs, b, b + (b - a).normalized() * 0.11 - Vector((0, 0, 0.03)), 0.02, 0.003, TALON, [("Toe_%d%s" % (k, sfx), 1.0)], n=6, steps=2)
    a = Vector((0.27 * sx, 0.08, 0.06))
    b = Vector((0.27 * sx, 0.3, 0.02))
    leg_tube(a, b, 0.024, 0.018, "Toe_B" + sfx, n=8, steps=2)
    tube(legs, b, b + Vector((0, 0.09, -0.03)), 0.017, 0.003, TALON, [("Toe_B" + sfx, 1.0)], n=6, steps=2)
legs.build(solid=True)

beak = MeshBuf("Beak")
BEAK_UP = (0.8, 0.55, 0.2)          # bronze-gold, not a toy's yellow
BEAK_LO = (0.62, 0.36, 0.12)
BEAK_TIP = (0.18, 0.07, 0.04)
upper = [(HEADZ + Vector((0, -1.43, 2.655)), Vector((0, -1, -0.1)), 0.056, 0.056, 0.0),
         (HEADZ + Vector((0, -1.55, 2.645)), Vector((0, -1, -0.12)), 0.043, 0.046, 0.0),
         (HEADZ + Vector((0, -1.66, 2.625)), Vector((0, -1, -0.25)), 0.031, 0.037, 0.0),
         (HEADZ + Vector((0, -1.75, 2.59)), Vector((0, -1, -0.55)), 0.02, 0.026, 0.0),
         (HEADZ + Vector((0, -1.8, 2.54)), Vector((0, -0.5, -1)), 0.011, 0.013, 0.0),
         (HEADZ + Vector((0, -1.795, 2.49)), Vector((0, 0.3, -1)), 0.003, 0.003, 0.0)]
loft(beak, upper, 14, lambda p, ang, k: BEAK_TIP if k >= 4 else (BEAK_UP if math.sin(ang) > -0.3 else BEAK_LO), None, True, [("Head", 1.0)])
lower = [(HEADZ + Vector((0, -1.43, 2.6)), Vector((0, -1, -0.15)), 0.046, 0.028, 0.0),
         (HEADZ + Vector((0, -1.56, 2.585)), Vector((0, -1, -0.15)), 0.033, 0.022, 0.0),
         (HEADZ + Vector((0, -1.67, 2.57)), Vector((0, -1, -0.2)), 0.015, 0.013, 0.0)]
loft(beak, lower, 10, lambda p, ang, k: BEAK_LO, None, True, [("Beak_Lower", 1.0)])
beak.build(solid=True)

EYE_R = 0.031          # v4: a larger eye (appeal; a raptor's eye is big for its head)
eyes = MeshBuf("Eyes")
for sfx, sx in (("_L", 1), ("_R", -1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=18, v_segments=12, radius=EYE_R)
    c = Vector((0.084 * sx, -1.385, 2.675 + HZ))
    g = Vector((0.78 * sx, -0.62, 0.06)).normalized()
    f_, r_, u_ = frame(g)
    ev, ef, euv, ec, ew = [], [], [], [], []
    for v in bm.verts:
        q = v.co.normalized()
        ev.append(c + v.co)
        euv.append((0.5 + q.dot(r_) * 0.4, 0.5 + q.dot(u_) * 0.4))   # a bird's eye shows almost all iris
        ec.append((1.0, 1.0, 1.0))
        ew.append([("Eye" + sfx, 1.0)])
    for f in bm.faces:
        ef.append(tuple(v.index for v in f.verts))
    bm.free()
    eyes.add(ev, ef, euv, ec, ew)
eyes.build(solid=True)
ring = MeshBuf("Beak_EyeRing")
for sfx, sx in (("_L", 1), ("_R", -1)):
    c = Vector((0.084 * sx, -1.385, 2.675 + HZ))
    g = Vector((0.85 * sx, -0.5, 0.05)).normalized()
    f_, r_, u_ = frame(g)
    rv, rf, ruv, rc, rw = [], [], [], [], []
    n = 20
    for i in range(n):
        a = 2 * math.pi * i / n
        for k, (rad, out) in enumerate(((EYE_R + 0.001, 0.004), (EYE_R + 0.009, -0.003))):
            # the gold eye ring sweeps back into a flame-shaped mark behind the eye
            stretch = 1.0 + 0.9 * max(0.0, math.cos(a - math.pi)) ** 3 * k
            rv.append(c + (r_ * math.cos(a) * stretch + u_ * math.sin(a)) * rad + g * out)
            ruv.append((0.7, 0.7))
            rc.append((0.22, 0.04, 0.03) if k == 0 else (0.12, 0.02, 0.02))   # a dark lid ring (a raptor's stare)
            rw.append([("Head", 1.0)])
    for i in range(n):
        a0, a1 = i * 2, ((i + 1) % n) * 2
        rf.append((a0, a1, a1 + 1, a0 + 1))
    ring.add(rv, rf, ruv, rc, rw)
ring.build(solid=False)

# ----------------------------------------------------------------------------------------- contour feathers
contour = MeshBuf("Feathers_Contour")
gold = MeshBuf("Gold_Ornaments")          # ornate gold filigree feathers (metallic in the shader)
flames = MeshBuf("Flames")                # flame tongues licking from her feathers (additive, animated)


def shingle(rings_spec, n_around, length, width, bones, gradient_for, tilt=0.22, droop=0.4, jitter=0.03, skip=None, buf=None, cell="contour", glow=0.35):
    for k, (c, fwd, rx, rz, keel) in enumerate(rings_spec):
        f, r, u = frame(fwd)
        off = 0.5 if k % 2 else 0.0
        for i in range(n_around):
            ang = 2 * math.pi * (i + off) / n_around
            s, co = math.sin(ang), math.cos(ang)
            zs = rz * (1 + keel) if s < 0 else rz
            p = Vector(c) + r * (rx * co) + u * (zs * s)
            if skip and skip(p):
                continue
            nrm = (r * (co / max(rx, 1e-3)) + u * (s / max(zs, 1e-3))).normalized()
            back = (-f + nrm * tilt).normalized()
            jit = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))) * jitter
            root = p + nrm * 0.01 - back * (length * 0.15) + jit
            w = nearest_weights(p, bones)
            g = gradient_for(ang)
            if g is None:
                continue
            feather(buf or contour, root, back, nrm, length * random.uniform(0.9, 1.1), width, cell,
                    g, w, curve=droop, segs=2, nrm=nrm, tint=random.uniform(0.92, 1.08), glow=glow)


def body_grad(ang):
    t = (1 - math.sin(ang)) * 0.5
    base = grad(t, BODY_STOPS)
    tip = lerp(base, AMBER, 0.25) if t < 0.6 else lerp(base, BRIGHT, 0.35)
    return [(0.0, lerp(base, DEEP, 0.5)), (0.55, base), (1.0, tip)]


def densify(rings, per):
    out = []
    for k in range(len(rings) - 1):
        for j in range(per):
            t = j / per
            c0, f0, rx0, rz0, k0 = rings[k]
            c1, f1, rx1, rz1, k1 = rings[k + 1]
            out.append((c0.lerp(c1, t), f0.lerp(f1, t), rx0 + (rx1 - rx0) * t, rz0 + (rz1 - rz0) * t, k0 + (k1 - k0) * t))
    out.append(rings[-1])
    return out


shingle(densify(body_rings, 4), 38, 0.25, 0.1, SPINE_BONES, body_grad, tilt=0.12, droop=0.5, glow=0.3)
shingle(densify(neck_rings, 4), 20, 0.24, 0.07, ["Neck1", "Neck2", "Neck3", "Head"],
        lambda ang: [(0, CRIMSON), (0.6, grad((1 - math.sin(ang)) * 0.5, [(0, SCARLET), (0.6, EMBER), (1, GOLD)])), (1, GOLD)],
        tilt=0.22, droop=0.42, jitter=0.012, glow=0.3)
HEAD_RINGS = [(HEAD_C + Vector((0, 0.15, 0.03)), Vector((0, -1, -0.15)), 0.092, 0.098, 0.0),
              (HEAD_C + Vector((0, 0.08, 0.044)), Vector((0, -1, -0.25)), 0.098, 0.097, 0.0),
              (HEAD_C + Vector((0, 0.0, 0.052)), Vector((0, -1, -0.35)), 0.1, 0.088, 0.0),
              (HEAD_C + Vector((0, -0.07, 0.05)), Vector((0, -1, -0.45)), 0.092, 0.078, 0.0),
              (HEAD_C + Vector((0, -0.12, 0.04)), Vector((0, -1, -0.6)), 0.078, 0.066, 0.0)]
eye_clear = lambda p: abs(p.x) > 0.045 and abs(p.z - 2.675 - HZ) < 0.06 and -1.43 < p.y < -1.33
# head plumage: a scarlet crown under a circlet of gold, a dark crimson mask through the eye (a falcon's
# stripe), gold cheeks and throat
# v4: the rings sat INSIDE the skull (radii 0.09-0.1 under a 0.104 x 0.112 head): lift them onto its surface
HEAD_RINGS = [(c, f, rx * 1.22 + 0.006, rz * 1.22 + 0.006, kl) for c, f, rx, rz, kl in HEAD_RINGS]
shingle(densify(HEAD_RINGS, 2), 34, 0.078, 0.046, ["Head"], lambda ang: ([(0, DEEP), (1, DEEP)] if abs(math.cos(ang)) > 0.78 and math.sin(ang) > -0.4 else
        ([(0, CRIMSON), (1, AMBER)] if math.sin(ang) < -0.2 else [(0, DEEP), (0.6, CRIMSON), (1, SCARLET)])),
        tilt=0.1, droop=0.55, jitter=0.004, skip=eye_clear, glow=0.25)
for sfx, sx in (("_L", 1), ("_R", -1)):
    th = [(Vector((0.21 * sx, 0.18, 1.18)), Vector((0.05 * sx, -0.35, -1)), 0.15, 0.13, 0.0),
          (Vector((0.235 * sx, 0.1, 1.0)), Vector((0.05 * sx, -0.35, -1)), 0.125, 0.115, 0.0),
          (Vector((0.26 * sx, 0.04, 0.86)), Vector((0.05 * sx, -0.3, -1)), 0.095, 0.09, 0.0),
          (Vector((0.265 * sx, 0.12, 0.7)), Vector((0.0, 0.5, -1)), 0.075, 0.07, 0.0)]
    shingle(th, 12, 0.16, 0.09, ["Hip" + sfx], lambda ang: [(0, CRIMSON), (0.5, SCARLET), (1, EMBER)], tilt=0.3, droop=0.3, glow=0.25)
# v4 SCAPULARS: a mantle of broad feathers over each shoulder, laid back over the upper back (mass at the shoulder)
for sfx, sx in (("_L", 1), ("_R", -1)):
    sc = [(Vector((0.2 * sx, -0.66, 1.84)), Vector((0.15 * sx, -1, 0.1)), 0.17, 0.12, 0.0),
          (Vector((0.24 * sx, -0.5, 1.84)), Vector((0.1 * sx, -1, 0.05)), 0.19, 0.12, 0.0),
          (Vector((0.22 * sx, -0.3, 1.8)), Vector((0.05 * sx, -1, -0.05)), 0.17, 0.11, 0.0)]
    shingle(sc, 14, 0.3, 0.13, ["Shoulder" + sfx, "Chest", "Spine"],
            lambda ang: [(0, CRIMSON), (0.55, SCARLET), (1, EMBER)] if math.sin(ang) > -0.15 else None,
            tilt=0.18, droop=0.35, jitter=0.01, glow=0.35)
# the GORGET: two rows of gold filigree scales where the neck meets the breast (her collar of office)
GORGET = [(Vector((0, -0.84, 1.8)), Vector((0, -0.55, 0.7)), 0.255, 0.28, 0.14),
          (Vector((0, -0.9, 1.88)), Vector((0, -0.45, 0.85)), 0.19, 0.2, 0.06)]
shingle(GORGET, 16, 0.2, 0.12, ["Chest", "Neck1"], lambda ang: [(0, AMBER), (0.6, GOLD), (1, BRIGHT)] if math.sin(ang) < 0.55 else None,
        tilt=0.35, droop=0.25, jitter=0.004, buf=gold, cell="gold", glow=0.6)
# the CROWN: a circlet of small gold scales over the brow and around the crest's root
CROWN = [(HEAD_C + Vector((0, 0.02, 0.085)), Vector((0, -0.6, 0.8)), 0.085, 0.05, 0.0)]
shingle(CROWN, 12, 0.07, 0.05, ["Head"], lambda ang: [(0, GOLD), (1, BRIGHT)] if math.sin(ang) > -0.3 else None,
        tilt=0.6, droop=0.15, jitter=0.002, buf=gold, cell="gold", glow=0.7)
contour.build(solid=False)

# the HACKLES: a mane of long lanceolate plumes flowing from the nape and the sides of the neck down over the
# shoulders and the back - gold at the root, ember, scarlet tips (the silhouette of a legendary bird)
hackles = MeshBuf("Feathers_Hackles")
HACKLE_GRAD = [(0.0, GOLD), (0.4, AMBER), (0.75, EMBER), (1.0, SCARLET)]
for k in range(5):
    t = k / 4.0
    c = neck_path[3].lerp(neck_path[0], t * 0.9)
    rad = 0.075 + 0.055 * t
    for i in range(16):
        ang = math.radians(-115 + 230 * (i + 0.5 * (k % 2)) / 15.0)   # around the back and sides of the neck
        out = Vector((math.sin(ang), math.cos(ang), 0.0))
        root = c + out * rad + Vector((0, 0, 0.02))
        down = (out * 0.35 + Vector((0, 0.55, -1.0))).normalized()
        L = (0.42 + 0.5 * t) * random.uniform(0.85, 1.12)
        hw = lambda s, root=root, down=down, L=L: nearest_weights(root + down * (L * s), ["Neck1", "Neck2", "Neck3", "Chest"], k=2, power=2.5, snap=0.4)
        feather(hackles, root, down, out, L, 0.075 + 0.02 * t, "plume", HACKLE_GRAD, hw, curve=0.18, segs=5,
                twist=random.uniform(-0.25, 0.25), raise_=0.004 * k, nrm=(out + Vector((0, 0, 0.4))), tint=random.uniform(0.9, 1.1), glow=0.55)
hackles.build(solid=False)

# ----------------------------------------------------------------------------------------- wings
wings = MeshBuf("Feathers_Wings")
blade = MeshBuf("Wing_Blade")


def rows_i(r, a, b, count):
    return int(round(r["t"] * max(count - 1, 1)))


def nearest_feather(grp, t, sfx):
    rows = LAYOUT[grp][1]
    best = min(range(len(rows)), key=lambda i: abs(rows[i]["t"] - t))
    return "%s%d%s" % (grp, best, sfx)


def flame_card(root, direction, up, length, width, weights, glow=1.0, curve=0.0, segs=4):
    """A flame tongue (atlas flame cell) - the fire licking off a feather; animated in its shader."""
    feather(flames, root, direction, up, length, width, "flame", FLAME_GRAD, weights, curve=curve, segs=segs, glow=glow)


CASCADE_GRAD = [(0.0, SCARLET), (0.35, EMBER), (0.72, CRIMSON), (1.0, MAGENTA)]


def wing(sx):
    """v3b (the developer: "too spread ... more and more feathers under it"): a FULL wing - every flight feather
    has in-between feathers that share its neighbours' bones (so the fan still folds and opens, but densely
    overlapped, never gappy), wider vanes, five covert rows, two under-covert rows, and a CASCADE of long flowing
    plumes in two layers hanging beneath the wing (in her display they fall below it like flames)."""
    sfx = "_L" if sx > 0 else "_R"
    M = (lambda v: Vector(v)) if sx > 0 else mir
    H0, H1 = _seg("Humerus")
    R0, R1 = _seg("Radius")
    W0, W1 = _seg("Hand")
    # the arm "blade" (wing leading edge); feathers hide it
    def ax(a, b):
        return (b - a).normalized()
    rings = [(H0.lerp(H1, 0.0) + BACK * 0.07, ax(H0, H1), 0.1, 0.04, 0.0),
             (H0.lerp(H1, 0.6) + BACK * 0.07, ax(H0, H1), 0.09, 0.032, 0.0),
             (R0.lerp(R1, 0.0) + BACK * 0.07, ax(R0, R1), 0.085, 0.027, 0.0),
             (R0.lerp(R1, 0.55) + BACK * 0.07, ax(R0, R1), 0.075, 0.022, 0.0),
             (W0.lerp(W1, 0.0) + BACK * 0.07, ax(W0, W1), 0.065, 0.02, 0.0),
             (W0.lerp(W1, 0.6) + BACK * 0.07, ax(W0, W1), 0.06, 0.018, 0.0),
             (W1 + BACK * 0.04, ax(W0, W1), 0.03, 0.012, 0.0)]
    rings = [(M(c), M(f), rx, rz, kl) for c, f, rx, rz, kl in rings]
    loft(blade, rings, 12, lambda p, ang, k: CRIMSON if math.sin(ang) > 0 else SCARLET, ["Humerus" + sfx, "Radius" + sfx, "Hand" + sfx])
    up = Vector((0, 0, 1))
    # flight feathers: one bone each, plus in-between feathers on the two neighbouring bones
    for grp, (parent, rows, width, gradient) in LAYOUT.items():
        n = len(rows)
        fill = {"Prim": (1.0 / 3.0, 2.0 / 3.0), "Sec": (0.5,), "Ter": (0.5,)}[grp]
        FINGER0 = 5           # primaries from here out are separate, tapered, upturned fingers
        side = ax(*_seg(parent)).cross(UP).normalized()
        if side.dot(BACK) < 0:
            side = -side
        for i, r in enumerate(rows):
            curve = 0.1 if grp == "Prim" else 0.08
            bw = [("%s%d%s" % (grp, i, sfx), 1.0)]
            finger = grp == "Prim" and i >= FINGER0
            feather(wings, M(r["root"]), M(r["dir"]), up, r["len"], width * (0.82 if finger else 1.0), "flight", gradient,
                    bw, curve=(-0.02 if finger else curve), lift=(0.07 if finger else 0.0), taper=(0.35 if finger else 0.0),
                    segs=7, twist=0.08 if grp == "Prim" else 0.0, raise_=0.004 * i, glow=1.0, nrm=up)
            fl = r["len"] * (0.55 if grp == "Prim" else 0.42)
            froot = r["root"] + r["dir"] * (r["len"] * 0.78) + up * 0.03 + side * 0.03
            flame_card(M(froot), M(r["dir"]), up, fl, width * 1.15, bw, glow=1.0 if grp == "Prim" else 0.75, curve=curve * 0.7)
            if i < n - 1 and not (grp == "Prim" and i >= FINGER0 - 1):
                r2 = rows[i + 1]
                for f in fill:
                    root = r["root"].lerp(r2["root"], f)
                    d = r["dir"].lerp(r2["dir"], f).normalized()
                    L = (r["len"] * (1.0 - f) + r2["len"] * f) * random.uniform(0.94, 1.0)
                    w2 = [("%s%d%s" % (grp, i, sfx), 1.0 - f), ("%s%d%s" % (grp, i + 1, sfx), f)]
                    feather(wings, M(root - up * 0.012), M(d), up, L, width * 0.96, "flight", gradient, w2, curve=curve, segs=6,
                            raise_=0.004 * i - 0.006, glow=0.9, tint=random.uniform(0.94, 1.03), nrm=up)
    # upper coverts: five shingled rows, crimson at the greater coverts warming to gold filigree at the leading edge
    segs = (("Prim", W0, W1, 16, (84, 32), (1.3, 1.55)), ("Sec", R0, R1, 19, (90, 84), (1.25, 1.35)), ("Ter", H0, H1, 8, (100, 92), (1.05, 1.15)))
    rows5 = ((0.6, 0.04, 0.045, COVERT_GRAD, "contour"), (0.47, 0.1, 0.065, [(0, SCARLET), (0.6, EMBER), (1, AMBER)], "contour"),
             (0.36, 0.15, 0.085, [(0, SCARLET), (0.6, EMBER), (1, AMBER)], "contour"), (0.26, 0.2, 0.1, [(0, EMBER), (0.6, AMBER), (1, GOLD)], "gold"),
             (0.17, 0.25, 0.115, [(0, AMBER), (1, GOLD)], "gold"),
             (0.11, 0.29, 0.125, [(0, EMBER), (0.5, AMBER), (1, GOLD)], "gold"))     # v4: marginal coverts on the leading edge
    for row_i, (frac, fwd, zz, grad_, cell) in enumerate(rows5):
        for grp, a, b, count, angs, lens in segs:
            for r in _row(a, b, count, angs, (lens[0] * frac, lens[1] * frac), 0.0, 0.98):
                side = ax(a, b).cross(UP).normalized()
                if side.dot(BACK) < 0:
                    side = -side
                root = r["root"] + up * zz - side * fwd
                feather(gold if cell == "gold" else wings, M(root), M(r["dir"]), up, r["len"], 0.3 if row_i < 3 else 0.22, cell, grad_,
                        [(nearest_feather(grp, r["t"], sfx), 1.0)], curve=0.08, segs=3, raise_=0.002 * (count - 1 - rows_i(r, a, b, count)),
                        glow=0.75 if cell == "gold" else 0.5, tint=random.uniform(0.92, 1.05), nrm=up)
    # under-coverts: two rows (the warm underside seen when she raises her wings)
    for grp, a, b, count, angs, lens in (("Prim", W0, W1, 15, (84, 32), (0.75, 0.9)), ("Sec", R0, R1, 18, (90, 84), (0.72, 0.8)), ("Ter", H0, H1, 7, (100, 92), (0.62, 0.68))):
        for k, (lf, dz, grad_) in enumerate(((1.0, 0.018, [(0, SCARLET), (0.6, EMBER), (1, AMBER)]), (0.62, 0.03, [(0, EMBER), (0.6, AMBER), (1, GOLD)]))):
            for r in _row(a, b, count, angs, (lens[0] * lf, lens[1] * lf), 0.02, 0.98):
                side = ax(a, b).cross(UP).normalized()
                if side.dot(BACK) < 0:
                    side = -side
                feather(wings, M(r["root"] - up * dz - side * 0.05), M(r["dir"]), -up, r["len"], 0.28, "contour",
                        grad_, [(nearest_feather(grp, r["t"], sfx), 1.0)], curve=-0.06, segs=3, glow=0.8, tint=random.uniform(0.92, 1.04), nrm=-up)
    # alula
    a_ax = ax(W0, W1)
    side = a_ax.cross(UP).normalized()
    if side.dot(BACK) < 0:
        side = -side
    for i in range(3):
        ang = math.radians(-25 + i * 8)
        d = (a_ax * math.cos(ang) + side * math.sin(ang)).normalized()
        feather(gold, M(W0 + a_ax * (0.04 + i * 0.05) - side * 0.1 + up * 0.03), M(d), up, 0.36 - i * 0.05, 0.13, "gold",
                [(0, AMBER), (1, GOLD)], [("Hand" + sfx, 1.0)], curve=0.05, segs=3, glow=0.7)


wing(1)
wing(-1)
wings.build(solid=False)
blade.build(solid=True)

# ----------------------------------------------------------------------------------------- tail and crest
tailm = MeshBuf("Feathers_Tail")
for i, r in enumerate(TAIL_ROWS):
    tw = [("TailF%d" % i, 1.0)]
    feather(tailm, r["root"], r["dir"], UP, r["len"], 0.36, "flight", TAIL_GRAD, tw, curve=0.24, segs=7, raise_=0.004 * (NTAIL - 1 - abs(i - 4)), glow=0.8)
    flame_card(r["root"] + r["dir"] * (r["len"] * 0.55) + UP * 0.03, r["dir"], UP, r["len"] * 0.7, 0.5, tw, glow=0.8, curve=0.16)
for i in range(6):
    k = (i - 2.5) / 2.5
    ang = math.radians(k * 30)
    d = (TAX * math.cos(ang) + Vector((1, 0, 0)) * math.sin(ang)).normalized()
    near = min(range(NTAIL), key=lambda j: abs(TAIL_ROWS[j]["k"] - k))
    feather(tailm, T0 + Vector((0, 0, 0.06)), d, UP, 0.75, 0.24, "contour", [(0, SCARLET), (0.6, EMBER), (1, AMBER)], [("TailF%d" % near, 1.0)], curve=0.26, segs=3, glow=0.4)
# v4: upper-tail coverts - a second, longer layer over the fan's root (the tail reads layered, not a flat fan)
for i in range(8):
    k = (i - 3.5) / 3.5
    ang = math.radians(k * 34)
    d = (TAX * math.cos(ang) + Vector((1, 0, 0)) * math.sin(ang)).normalized()
    near = min(range(NTAIL), key=lambda j: abs(TAIL_ROWS[j]["k"] - k))
    feather(tailm, T0 + TAX * 0.05 + Vector((0, 0, 0.045)), d, UP, 1.15 - 0.2 * abs(k), 0.3, "flight",
            [(0, CRIMSON), (0.5, SCARLET), (0.85, EMBER), (1, AMBER)], [("TailF%d" % near, 1.0)], curve=0.22, segs=5,
            raise_=0.003 * (4 - abs(i - 3.5)), glow=0.6, tint=random.uniform(0.93, 1.05))
# the TRAIN: two side plumes on the streamer bones and three central plumes, each ending in a curl
for sfx, sg in (("_L", 1), ("_R", -1)):
    S1a = BONES["Stream1" + sfx][0]
    S3b = BONES["Stream3" + sfx][1]
    total = (S3b - S1a).length
    d = (S3b - S1a).normalized()
    sw = lambda s, S1a=S1a, d=d, total=total, sfx=sfx: nearest_weights(S1a + d * (total * min(s, 1.0)), ["Stream1" + sfx, "Stream2" + sfx, "Stream3" + sfx], k=2, power=3, snap=0.3)
    L = total * 1.45
    feather(tailm, S1a, d, UP, L, 0.44, "streamer", STREAM_GRAD, sw, curve=0.02, segs=26, twist=0.6 * sg, wave=(0.05, 1.5), glow=0.9,
            curl=2.8 * sg, curl_from=0.72, taper=0.25)
    flame_card(S1a + d * (total * 0.75) + UP * 0.02, d, UP, total * 0.6, 0.5, lambda s, sw=sw: sw(0.75 + 0.25 * s), glow=0.7)
for j, sx in enumerate((1, -1, 0)):
    T2a, T2b = BONES["Tail2"]
    d = ((T2b - T2a).normalized() + Vector((0.07 * sx, 0, 0.1))).normalized()
    side_bone = "Stream1_L" if sx > 0 else "Stream1_R"
    tw = (lambda s, side_bone=side_bone: [("TailF4", 1.0 - 0.5 * s), (side_bone, 0.5 * s)] if s > 0 else [("TailF4", 1.0)]) if sx != 0 else [("TailF4", 1.0)]
    L = 3.6 if sx != 0 else 4.1
    feather(tailm, T2a + Vector((0.03 * sx, 0.1, 0.07 + 0.02 * (sx == 0))), d, UP, L, 0.32 if sx != 0 else 0.36, "streamer", STREAM_GRAD, tw, curve=0.08, segs=24,
            twist=0.5 * sx, wave=(0.06, 1.2), glow=0.9, curl=(2.3 * sx if sx != 0 else 1.6), curl_from=0.74, taper=0.2)
tailm.build(solid=False)

crest = MeshBuf("Feathers_Crest")
C1a = BONES["Crest1"][0]
C3b = BONES["Crest3"][1]
cd = (C3b - C1a).normalized()
ctotal = (C3b - C1a).length
for i in range(7):
    k = (i - 3) / 3.0
    side = Vector((1, 0, 0))
    long_ = i in (1, 3, 5)
    d = (cd * math.cos(math.radians(k * 26)) + side * math.sin(math.radians(k * 26)) + Vector((0, 0, 0.3 * (1 - abs(k))))).normalized()
    L = ctotal * ((2.15 if i == 3 else 1.8) if long_ else 0.95)     # v4: longer, finer plumes
    root = C1a + side * (k * 0.035) - cd * 0.04
    cw = lambda s, L=L, root=root, d=d: nearest_weights(root + d * (L * s), ["Crest1", "Crest2", "Crest3", "Head"], k=2, power=3, snap=0.35)
    if long_:
        feather(crest, root, d, Vector((0, -0.3, 1)).normalized(), L, 0.105, "streamer", CREST_GRAD, cw, curve=-0.36, segs=12, twist=0.3 * k, glow=1.0)
        flame_card(root + d * (L * 0.55), d, Vector((0, -0.3, 1)).normalized(), L * 0.6, 0.2, lambda s, cw=cw: cw(0.55 + 0.45 * s), glow=0.9, curve=-0.25)
    else:
        feather(crest, root, d, Vector((0, -0.3, 1)).normalized(), L, 0.15, "plume", CREST_GRAD, cw, curve=-0.25, segs=6, glow=0.8)
# two flame-horns: gold plumes sweeping up and back from the brow (a crowned head)
for sx in (1, -1):
    hr = HEAD_C + Vector((0.07 * sx, -0.06, 0.09))
    hd = Vector((0.35 * sx, 0.55, 1.0)).normalized()
    feather(crest, hr, hd, Vector((sx, 0, 0)), 0.42, 0.07, "plume", [(0, AMBER), (0.5, GOLD), (1, WHITEGOLD)], [("Head", 1.0)], curve=-0.45, segs=6, twist=0.2 * sx, glow=1.0)
    feather(crest, Vector((0.12 * sx, -1.24, 2.7 + HZ)), Vector((0.5 * sx, 0.8, 0.4)).normalized(), UP, 0.3, 0.1, "plume",
            CREST_GRAD, [("Head", 1.0)], curve=0.1, segs=3, glow=0.6)
crest.build(solid=False)
gold.build(solid=False)
flames.build(solid=False)

# ----------------------------------------------------------------------------------------- pose solver
CHEST3 = REST["Chest"].to_3x3()


def aim3(y, z):
    y = Vector(y).normalized()
    x = y.cross(Vector(z))
    if x.length < 1e-6:
        x = y.cross(Vector((1, 0, 0)))
    x.normalize()
    z2 = x.cross(y).normalized()
    return Matrix((x, y, z2)).transposed()


def slerp3(a, b, t):
    if t <= 0.0:
        return a
    if t >= 1.0:
        return b
    return a.to_quaternion().slerp(b.to_quaternion(), t).to_matrix()


def rad3(v):
    return Euler([math.radians(a) for a in v], 'XYZ')


# The folded wing, in the chest's frame (left side): arm bones fold in a Z; every flight feather lies back along
# the flank, primaries outermost, the upper surface facing out and a little up.
# folded (world directions, left side): humerus back along the chest, radius forward hugging the flank so the
# wrist tucks high at the front of the breast, hand back along the upper flank; primaries trail past the hips
FOLD_ARM = {"Humerus": (Vector((0.16, 0.95, -0.2)), Vector((0.9, 0.0, 0.44))),
            "Radius": (Vector((-0.08, -0.95, -0.3)), Vector((0.96, 0.0, 0.28))),
            "Hand": (Vector((0.05, 0.99, -0.08)), Vector((0.95, 0.0, 0.3)))}


def fold_target(grp, i, n):
    u = i / max(n - 1, 1)
    if grp == "Prim":
        return Vector((-0.02 + 0.016 * u, 0.98, -0.16 + 0.05 * u)), Vector((0.9, 0.0, 0.44))
    if grp == "Sec":
        return Vector((-0.1 + 0.03 * u, 0.97, -0.17 + 0.03 * u)), Vector((0.86, 0.0, 0.5))
    return Vector((-0.28 + 0.03 * u, 0.95, 0.08 + 0.02 * u)), Vector((0.4, 0.0, 0.92))   # tertials lie over the back


# DISPLAY (v3): the heraldic display of the references - each wing segment aimed up-and-out (`raise` degrees above
# the horizon, `sweep` degrees back (+) or forward (-)) and rolled so the feather fans hang in the frontal plane:
# seen from the front, the open wing faces the viewer (its golden underside), the primaries sweep up at the top.
DISPLAY_SEG = {"Humerus": 0.0, "Radius": 3.0, "Hand": 8.0}


def display_target(seg, raise_, sweep, roll=90.0):
    r = math.radians(raise_ + DISPLAY_SEG[seg])
    w = math.radians(sweep)
    d = Vector((math.cos(r) * math.cos(w), math.cos(r) * math.sin(w), math.sin(r)))
    ro = math.radians(roll)
    nz = Vector((0.0, 0.0, 1.0)) * math.cos(ro) + Vector((-math.sin(w), math.cos(w), 0.0)) * math.sin(ro)
    return d, nz


def sym(e):
    out = dict(e)
    for k, v in e.items():
        if k.endswith("_L") and k[:-2] + "_R" not in e:
            out[k[:-2] + "_R"] = (v[0], -v[1], -v[2])
    return out


WING_DEFAULT = {"fold": 1.0, "fan": 0.3, "twist": 0.0, "sec_twist": 0.0, "display": 0.0, "raise": 50.0, "sweep": 0.0}


def solve(spec):
    e = sym(spec.get("e", {}))
    loc = Vector(spec.get("loc", (0, 0, 0)))
    wings_ = {"L": dict(WING_DEFAULT, **spec.get("wing", {})), "R": dict(WING_DEFAULT, **spec.get("wing", {}))}
    wings_["L"].update(spec.get("wingL", {}))
    wings_["R"].update(spec.get("wingR", {}))
    tailfan = spec.get("tailfan", 0.35)
    posed, out = {}, {}
    for n in ORDER:
        p = PARENT[n]
        base = (posed[p] @ (REST[p].inverted() @ REST[n])) if p else REST[n].copy()
        b3 = base.to_3x3()
        q = rad3(e.get(n, (0, 0, 0))).to_quaternion()
        k = KIND[n]
        side = n[-1]
        if k == "arm" and n[:-2] in DISPLAY_SEG and wings_[side].get("display", 0.0) > 0.0:
            f = wings_[side]["display"]
            d, nz = display_target(n[:-2], wings_[side].get("raise", 50.0), wings_[side].get("sweep", 0.0), wings_[side].get("roll", 90.0))
            if side == "R":
                d, nz = mir(d), mir(nz)
            cdelta = posed["Chest"].to_3x3() @ CHEST3.inverted()
            R = slerp3(b3 @ q.to_matrix(), aim3(cdelta @ d, cdelta @ nz), f)
            q = (b3.inverted() @ R).to_quaternion()
        elif k == "arm" and n[:-2] in FOLD_ARM and wings_[side]["fold"] > 0.0:
            f = wings_[side]["fold"]
            d, nz = FOLD_ARM[n[:-2]]
            if side == "R":
                d, nz = mir(d), mir(nz)
            cdelta = posed["Chest"].to_3x3() @ CHEST3.inverted()
            R = slerp3(b3 @ q.to_matrix(), aim3(cdelta @ d, cdelta @ nz), f)
            q = (b3.inverted() @ R).to_quaternion()
        elif k in ("feather", "tailfan"):
            info = FEATHER[n]
            p3 = posed[p].to_3x3()
            pr3 = REST[p].to_3x3()
            d_bone = pr3.inverted() @ info["dir"]
            ref = Vector((0, 1, 0)) if k == "feather" else Vector((1.0 if info["dir"].x >= 0 else -1.0, 0, 0))
            bb = pr3.inverted() @ ref
            back_bone = Vector((1.0 if bb.x >= 0 else -1.0, 0.0, 0.0))
            ya = Vector((0, 1, 0))
            a_rest = math.atan2(d_bone.dot(back_bone), d_bone.dot(ya))
            zc = d_bone.z
            if k == "feather":
                w = wings_[side]
                grp, i, cnt = info["group"], info["i"], info["n"]
                if grp == "Prim":
                    a_tip = math.radians(18)
                    a_closed = a_tip + (a_rest - a_tip) * 0.1 + math.radians(1.2 * (cnt - 1 - i))
                    a = a_closed + (a_rest - a_closed) * w["fan"]
                    tw = math.radians(w["twist"]) * (0.4 + 0.6 * i / (cnt - 1))
                else:
                    a = a_rest
                    tw = math.radians(w["sec_twist"])
                d_b = (ya * math.cos(a) + back_bone * math.sin(a))
                d_b.z += zc
                R_s = aim3(p3 @ d_b, p3 @ Vector((0, 0, 1)))
                if side == "R":
                    tw = -tw
                R_s = R_s @ Matrix.Rotation(tw, 3, 'Y')
                f = w["fold"]
                if f > 0.0:
                    fd, fn = fold_target(grp, i, cnt)
                    if side == "R":
                        fd, fn = mir(fd), mir(fn)
                    cdelta = posed["Chest"].to_3x3() @ CHEST3.inverted()
                    R = slerp3(R_s, aim3(cdelta @ fd, cdelta @ fn), f)
                else:
                    R = R_s
            else:
                a_closed = a_rest * 0.12
                a = a_closed + (a_rest - a_closed) * tailfan
                d_b = ya * math.cos(a) + back_bone * math.sin(a)
                d_b.z += zc
                R = aim3(p3 @ d_b, p3 @ Vector((0, 0, 1)))
            q = (b3.inverted() @ R).to_quaternion()
        out[n] = q
        lm = Matrix.Translation(loc) if n == "Root" else Matrix.Identity(4)
        posed[n] = base @ lm @ q.to_matrix().to_4x4()
    return out, loc, posed


def apply_pose(spec):
    out, loc, _ = solve(spec)
    for n, q in out.items():
        pb = arm.pose.bones[n]
        pb.rotation_quaternion = q
        pb.location = loc if n == "Root" else Vector((0, 0, 0))


# ----------------------------------------------------------------------------------------- pose vocabulary
def M(*dicts):
    out = {}
    for d in dicts:
        for k, v in d.items():
            if k == "e":
                out.setdefault("e", {}).update(v)
            elif k in ("wing", "wingL", "wingR"):
                out.setdefault(k, {}).update(v)
            else:
                out[k] = v
    return out


def E(**bones):
    return {"e": bones}


def legs_stand(bend=0.0):
    return E(Hip_L=(10 + 8 * bend, 0, 0), Tibia_L=(-22 - 14 * bend, 0, 0), Tarsus_L=(18 + 10 * bend, 0, 0), Foot_L=(-6 - 4 * bend, 0, 0))


def legs_tucked():
    return E(Hip_L=(-70, 0, 0), Tibia_L=(-110, 0, 0), Tarsus_L=(120, 0, 0), Foot_L=(-20, 0, 0),
             Toe_0_L=(30, 0, 0), Toe_1_L=(30, 0, 0), Toe_2_L=(30, 0, 0), Toe_B_L=(-20, 0, 0))


def legs_hanging(reach=0.0):
    return E(Hip_L=(-20 + 30 * reach, 0, 0), Tibia_L=(-40 + 10 * reach, 0, 0), Tarsus_L=(40 - 10 * reach, 0, 0), Foot_L=(-10, 0, 0),
             Toe_0_L=(-15 * reach, 0, 0), Toe_1_L=(-15 * reach, 0, 0), Toe_2_L=(-15 * reach, 0, 0))


def neck(pitch=0.0, yaw=0.0, s_curve=1.0):
    """pitch > 0 lowers the head (bends the neck forward); yaw > 0 turns it to her left."""
    return E(Neck1=(-6 * s_curve + pitch * 0.35, 0, yaw * 0.3), Neck2=(4 * s_curve + pitch * 0.35, 0, yaw * 0.35),
             Neck3=(6 * s_curve + pitch * 0.3, 0, yaw * 0.35), Head=(4 * s_curve + pitch * 0.55, 0, 0))


def tail(lift=0.0, spread=0.35, whip=0.0):
    return M(E(TailBase=(lift * 0.4, 0, 0), Tail1=(lift * 0.3, 0, 0), Tail2=(lift * 0.3, 0, 0),
               Stream1_L=(lift * 0.2 + whip, 0, 4 * spread), Stream2_L=(whip * 0.8, 0, 2 * spread), Stream3_L=(whip * 0.6, 0, 0)),
             {"tailfan": spread})


def crest(lift=0.0):
    return E(Crest1=(lift * 0.5, 0, 0), Crest2=(lift * 0.3, 0, 0), Crest3=(lift * 0.2, 0, 0))


def body(pitch=0.0, roll=0.0, rise=0.0, forward=0.0, yaw=0.0):
    return M(E(Root=(pitch, yaw, roll)), {"loc": (0, rise, forward)})


def spine(pitch=0.0, yaw=0.0):
    return E(Hips=(pitch * 0.4, 0, yaw * 0.4), Spine=(pitch * 0.3, 0, yaw * 0.3), Chest=(pitch * 0.3, 0, yaw * 0.3))


def beak(open_=0.0):
    return E(Beak_Lower=(-open_, 0, 0))


FOLDED = {"wing": {"fold": 1.0, "fan": 0.2, "twist": 0.0}}
SPREAD_W = {"wing": {"fold": 0.0, "fan": 1.0, "twist": 0.0}}


def wing_arm(h=(0, 0, 0), r=(0, 0, 0), w=(0, 0, 0), s=(0, 0, 0)):
    return E(Shoulder_L=s, Humerus_L=h, Radius_L=r, Hand_L=w)


def half(f=0.5, fan=0.6):
    return {"wing": {"fold": f, "fan": fan}}


STAND = M(legs_stand(), neck(), tail(0, 0.3), crest(), FOLDED)


def flap(phase, depth=1.0, sweep=0.0, stroke_fwd=0.0):
    """One instant of the flight stroke. phase 0 = top of the upstroke, 0.5 = bottom of the downstroke."""
    c = math.cos(2 * math.pi * phase)
    down = max(0.0, math.sin(2 * math.pi * phase))
    up = max(0.0, -math.sin(2 * math.pi * phase))
    hx = 5 + 40 * c * depth
    return M(wing_arm(h=(hx, 9 * down - 6 * up, -10 * down + 6 * up - stroke_fwd * down + sweep),
                      r=(10 * math.cos(2 * math.pi * (phase - 0.06)) * depth, -6 * down, -16 * up),
                      w=(16 * math.cos(2 * math.pi * (phase - 0.12)) * depth, -8 * down, 30 * up - 4 * down),
                      s=(8 * c * depth, 0, 0)),
             {"wing": {"fold": 0.0, "fan": 0.78 + 0.22 * down, "twist": 34 * up, "sec_twist": 8 * up}})


def walk_pose(ph):
    sw = math.sin(ph * 2 * math.pi)
    lift = max(0.0, math.sin(ph * 2 * math.pi + 0.5))
    lift_r = max(0.0, math.sin(ph * 2 * math.pi + math.pi + 0.5))
    head = math.sin(ph * 4 * math.pi - 0.8) * 5
    return M(STAND, E(Hip_L=(10 + 26 * sw, 0, 0), Tibia_L=(-22 - 30 * lift, 0, 0), Tarsus_L=(18 + 36 * lift, 0, 0), Foot_L=(-6 - 22 * lift, 0, 0),
                      Hip_R=(10 - 26 * sw, 0, 0), Tibia_R=(-22 - 30 * lift_r, 0, 0), Tarsus_R=(18 + 36 * lift_r, 0, 0), Foot_R=(-6 - 22 * lift_r, 0, 0)),
             neck(head, 0), tail(0, 0.3, 2 * sw), body(0, 2.5 * sw, 0.02 * abs(sw)), spine(0, 3 * sw))


def turn_pose(ph, sg):
    sw = math.sin(ph * 2 * math.pi)
    lift = max(0.0, math.sin(ph * 2 * math.pi + 0.5))
    lift_r = max(0.0, math.sin(ph * 2 * math.pi + math.pi + 0.5))
    return M(STAND, E(Hip_L=(10 + 10 * sw, 0, 12 * sg * lift), Tibia_L=(-22 - 24 * lift, 0, 0), Tarsus_L=(18 + 28 * lift, 0, 0), Foot_L=(-6 - 10 * lift, 0, 0),
                      Hip_R=(10 - 10 * sw, 0, 12 * sg * lift_r), Tibia_R=(-22 - 24 * lift_r, 0, 0), Tarsus_R=(18 + 28 * lift_r, 0, 0), Foot_R=(-6 - 10 * lift_r, 0, 0)),
             neck(0, 18 * sg), tail(0, 0.3, 1.5 * sw), body(0, 2 * sg, 0.012 * abs(sw)), spine(0, 8 * sg))


# ----------------------------------------------------------------------------------------- clips
FPS = 30
arm.animation_data_create()
CLIPS = []


def clip(name, keys, loop=False):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    prev = {}
    for t, spec in keys:
        out, loc, _ = solve(spec)
        f = round(t * FPS)
        for n, q in out.items():
            pb = arm.pose.bones[n]
            if n in prev and prev[n].dot(q) < 0.0:
                q = -q
            prev[n] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if n == "Root":
                pb.location = loc
                pb.keyframe_insert("location", frame=f)
    act.frame_range = (0, round(keys[-1][0] * FPS))
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.handle_left_type = 'AUTO_CLAMPED'
            kp.handle_right_type = 'AUTO_CLAMPED'
        if loop:
            fc.modifiers.new('CYCLES')
    tr = arm.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, 0, act)
    tr.mute = True
    arm.animation_data.action = None
    CLIPS.append(name)
    return act


def cyc(name, n, period, fn):
    """A looping clip sampled from a phase function (the last key equals the first)."""
    clip(name, [(period * k / n, fn(k / n)) for k in range(n)] + [(period, fn(0.0))], loop=True)


# ---- ground
clip("idle", [(0.0, M(STAND)), (1.3, M(STAND, neck(2, 6), body(0.5, 0, -0.006), tail(0, 0.3, 1.5), crest(3))),
              (2.4, M(STAND, neck(-3, -8), body(0, 0, 0.004), tail(1, 0.3, -1))), (3.4, M(STAND, neck(1, 2), body(0.3, 0, -0.003), tail(0, 0.3, 0.5))),
              (4.6, M(STAND))], loop=True)
clip("breathe", [(0.0, M(STAND)), (1.5, M(STAND, spine(-1.5), body(0, 0, 0.01), neck(1.5))), (3.0, M(STAND))], loop=True)
clip("look", [(0.0, STAND), (0.7, M(STAND, neck(-6, 38), crest(4))), (1.5, M(STAND, neck(-8, 40), crest(2))),
              (2.3, M(STAND, neck(-4, -36), crest(4))), (3.0, M(STAND, neck(-6, -38))), (3.6, STAND)])
OPEN_HIGH = wing_arm(h=(14, 0, 0), r=(4, 0, -4), w=(4, 0, -4))
clip("wing_spread", [(0.0, STAND), (0.3, M(STAND, half(0.65, 0.4), neck(-4), crest(4))),
                     (0.6, M(STAND, half(0.25, 0.85), wing_arm(h=(10, 0, 0)), neck(-8), crest(8), body(-2), tail(0, 0.7))),
                     (0.85, M(STAND, SPREAD_W, OPEN_HIGH, neck(-8), crest(8), body(-2), tail(0, 1.0))),
                     (1.2, M(STAND, SPREAD_W, wing_arm(h=(6, 0, 0)), neck(-6), crest(6), body(-1), tail(0, 1.0)))])
clip("wing_fold", [(0.0, M(STAND, SPREAD_W, wing_arm(h=(6, 0, 0)), neck(-6), crest(6), body(-1), tail(0, 1.0))),
                   (0.35, M(STAND, half(0.3, 0.8), neck(-3), crest(3), tail(0, 0.7))),
                   (0.7, M(STAND, half(0.7, 0.4), tail(0, 0.4))),
                   (1.0, M(STAND, {"wing": {"fold": 1.0, "fan": 0.2}}, E(Humerus_L=(-3, 0, 0)))), (1.25, STAND)])
clip("walk", [(k * 0.325, walk_pose(k / 4)) for k in range(4)] + [(1.3, walk_pose(0))], loop=True)
for nm, sg in (("turn_left", 1), ("turn_right", -1)):
    clip(nm, [(k * 0.25, turn_pose(k / 4, sg)) for k in range(4)] + [(1.0, turn_pose(0, sg))], loop=True)

# ---- flight
FLY_BASE = M(legs_tucked(), neck(-10, 0, 0.3), tail(-4, 0.55), crest(4))
cyc("fly", 8, 0.9, lambda ph: M(FLY_BASE, flap(ph), body(-4 + 2 * math.sin(2 * math.pi * ph), 0, 0.05 * math.sin(2 * math.pi * (ph - 0.3))),
                                 spine(2 * math.cos(2 * math.pi * ph))))
GLIDE = M(FLY_BASE, SPREAD_W, wing_arm(s=(6, 0, 0), h=(12, -4, -4), r=(4, -5, -6), w=(2, -8, -10)), tail(-2, 0.85))
clip("glide", [(0.0, M(GLIDE, body(-3))), (1.5, M(GLIDE, wing_arm(s=(6, 0, 0), h=(15, -4, -4), r=(4, -5, -6), w=(5, -8, -10)), body(-2, 0, 0.02), tail(-1, 0.85, 1))),
               (3.0, M(GLIDE, body(-3)))], loop=True)
for nm, sg in (("bank_left", 1), ("bank_right", -1)):
    inner = {"Shoulder": (-6, 0, 2), "Humerus": (-4, -2, 6), "Radius": (0, -4, -2), "Hand": (-4, -8, -4)}
    outer = {"Shoulder": (16, 0, 0), "Humerus": (26, 4, 0), "Radius": (8, 6, 8), "Hand": (6, 10, 12)}
    ins, outs = ("_L", "_R") if sg > 0 else ("_R", "_L")
    eb = {}
    for b, v in inner.items():
        eb[b + ins] = v if ins == "_L" else (v[0], -v[1], -v[2])
    for b, v in outer.items():
        eb[b + outs] = v if outs == "_L" else (v[0], -v[1], -v[2])
    bank = M(FLY_BASE, SPREAD_W, {"e": eb}, tail(-3, 0.8), E(Tail1=(-2, 0, 12 * sg), Tail2=(-2, 0, 10 * sg)), neck(-10, 12 * sg, 0.3))
    clip(nm, [(0.0, M(bank, body(-3, -6 * sg))), (1.0, M(bank, body(-2, -6 * sg, 0.01))), (2.0, M(bank, body(-3, -6 * sg)))], loop=True)
HOVER = M(legs_hanging(0.2), neck(16, 0, 0.6), tail(-26, 1.0), crest(6))
cyc("hover", 8, 0.8, lambda ph: M(HOVER, flap(ph, 1.2, -6, 30), body(-40 + 3 * math.sin(2 * math.pi * ph), 0, 0.06 * math.sin(2 * math.pi * (ph - 0.3)))))
clip("takeoff", [(0.0, STAND),
                 (0.35, M(STAND, legs_stand(1.0), half(0.55, 0.5), wing_arm(h=(25, 0, 0)), neck(6), body(4, 0, -0.1), tail(8, 0.5), crest(4))),
                 (0.6, M(legs_stand(-0.4), flap(0.08, 1.15), neck(-10), body(-14, 0, 0.08), tail(-4, 1.0), crest(8))),
                 (0.9, M(legs_hanging(), flap(0.45, 1.15), neck(-8), body(-16, 0, 0.12), tail(-6, 1.0), crest(8))),
                 (1.2, M(legs_tucked(), flap(0.8, 1.1), neck(-6), body(-12, 0, 0.1), tail(-4, 0.7), crest(6))),
                 (1.55, M(legs_tucked(), flap(0.1, 1.0), neck(-8, 0, 0.4), body(-8, 0, 0.05), tail(-3, 0.6), crest(4)))])
clip("land", [(0.0, M(GLIDE, body(-6))),
              (0.4, M(legs_hanging(0.6), neck(10, 0, 0.7), tail(-20, 1.0), flap(0.15, 1.1, -10, 20), body(-34, 0, 0.05))),
              (0.75, M(legs_hanging(1.0), neck(8, 0, 0.7), tail(-16, 1.0), flap(0.5, 1.1, -10, 20), body(-28, 0, 0.0))),
              (1.05, M(legs_stand(1.0), neck(10), tail(-4, 0.8), {"wing": {"fold": 0.0, "fan": 1.0}}, wing_arm(h=(28, 0, -6), w=(10, 0, -4)), body(-4, 0, -0.12))),
              (1.4, M(legs_stand(0.6), neck(5), tail(2, 0.5), half(0.45, 0.6), body(1, 0, -0.06))),
              (1.75, M(STAND, half(0.85, 0.3), legs_stand(0.2))), (2.0, STAND)])
clip("perch_settle", [(0.0, M(STAND, half(0.4, 0.6))), (0.3, M(STAND, half(0.55, 0.5), body(0, 0, 0.01))),
                      (0.55, M(STAND, half(0.75, 0.35), body(0, 0, -0.01), tail(0, 0.4, 3))), (0.8, M(STAND, half(0.92, 0.25), tail(0, 0.3, -2))), (1.1, STAND)])

# ---- magic and combat
MANTLE = M(SPREAD_W, wing_arm(s=(22, 0, 0), h=(40, 0, -8), r=(16, 0, -10), w=(10, 0, -8)))
clip("cast_fire", [(0.0, STAND),
                   (0.5, M(STAND, half(0.45, 0.6), neck(-14, 0, 0.4), crest(10), body(-6, 0, -0.04), tail(-6, 0.7), spine(-6))),
                   (0.95, M(STAND, MANTLE, neck(-26, 0, 0.1), crest(16), body(-14, 0, 0.05), tail(-14, 1.0), spine(-12), beak(14))),
                   (1.15, M(STAND, MANTLE, wing_arm(s=(18, 0, 0), h=(34, 0, -8)), neck(12, 0, 0.1), crest(14), body(-8, 0, 0.03), tail(-10, 1.0), spine(-8), beak(24))),
                   (1.5, M(STAND, SPREAD_W, wing_arm(s=(8, 0, 0), h=(16, 0, -4), r=(8, 0, -8), w=(4, 0, -6)), neck(6, 0, 0.6), crest(8), body(-3), tail(-4, 0.7), beak(8))),
                   (1.9, M(STAND, half(0.5, 0.5), neck(0), crest(3), tail(0, 0.4))), (2.3, STAND)])
SHIELD = M({"wing": {"fold": 0.0, "fan": 0.9}}, wing_arm(s=(-6, 0, -10), h=(-14, 10, -52), r=(0, 14, -60), w=(-8, 12, -30)))
clip("defend", [(0.0, STAND), (0.3, M(STAND, SHIELD, neck(22, 0, 0.6), crest(-4), body(5, 0, -0.08), legs_stand(0.8), tail(6, 0.5))),
                (1.0, M(STAND, SHIELD, wing_arm(s=(-8, 0, -12), h=(-16, 12, -56), r=(0, 16, -62), w=(-10, 12, -32)), neck(24, 0, 0.6), crest(-4), body(6, 0, -0.09), legs_stand(0.9), tail(6, 0.5))),
                (1.6, STAND)])
clip("attack", [(0.0, STAND),
                (0.3, M(STAND, half(0.4, 0.6), neck(-20, 0, 0.3), crest(10), body(-4, 0, -0.06), legs_stand(1.0), tail(-6, 0.6), spine(-8))),
                (0.55, M(STAND, SPREAD_W, wing_arm(h=(30, 0, -20), r=(10, 0, -10), w=(6, 0, -10)), neck(30, 0, 0.0), crest(12), body(10, 0, 0.1, 0.45), legs_stand(-0.3), tail(-10, 1.0), spine(10), beak(18))),
                (0.8, M(STAND, SPREAD_W, wing_arm(h=(-10, 0, 10), r=(0, 0, -8), w=(0, 0, -8)), neck(24, 0, 0.0), crest(8), body(6, 0, 0.05, 0.35), legs_stand(0.4), tail(-6, 0.7), spine(6))),
                (1.3, STAND)])
clip("react", [(0.0, STAND), (0.12, M(STAND, half(0.45, 0.7), neck(-18, 10, 0.5), crest(12), body(-8, 3, 0.02, -0.18), legs_stand(0.6), tail(-8, 0.8), spine(-6))),
               (0.45, M(STAND, half(0.7, 0.5), neck(-10, 6, 0.6), crest(8), body(-4, 2, 0.0, -0.1), legs_stand(0.4), tail(-4, 0.5), spine(-3))), (0.85, STAND)])
clip("recover", [(0.0, M(STAND, neck(14, 0, 0.6), body(3, 0, -0.05), legs_stand(0.6))),
                 (0.45, M(STAND, half(0.55, 0.7), neck(6, -10), body(1, 2, -0.02), legs_stand(0.3), tail(2, 0.5, 3))),
                 (0.7, M(STAND, half(0.4, 0.9), neck(2, 10), body(0, -2, 0.0), tail(0, 0.6, -3))),
                 (0.95, M(STAND, half(0.6, 0.6), neck(0, -6), body(0, 1.5), tail(0, 0.4, 2))), (1.5, STAND)])

# ---- her gestures
PREEN_W = {"wingL": {"fold": 0.55, "fan": 0.7}}
clip("preen", [(0.0, STAND), (0.8, M(STAND, PREEN_W, neck(26, 42, 0.5), crest(2), spine(0, 6))),
               (1.3, M(STAND, PREEN_W, neck(34, 46, 0.5), spine(0, 8), beak(8))), (1.7, M(STAND, PREEN_W, neck(28, 44, 0.5), crest(2), spine(0, 8))),
               (2.2, M(STAND, PREEN_W, neck(36, 48, 0.5), spine(0, 8), beak(6))), (2.7, M(STAND, neck(6, 12), crest(4), tail(0, 0.3, 2))), (3.2, STAND)])
clip("call", [(0.0, STAND), (0.5, M(STAND, half(0.5, 0.6), neck(-30, 0, 0.2), crest(14), body(-4, 0, 0.02), tail(-6, 0.8), spine(-6), beak(10))),
              (0.8, M(STAND, half(0.35, 0.8), wing_arm(h=(20, 0, 0)), neck(-38, 0, 0.1), crest(18), body(-6, 0, 0.03), tail(-8, 1.0), spine(-8), beak(26))),
              (1.4, M(STAND, half(0.4, 0.7), wing_arm(h=(16, 0, 0)), neck(-34, 0, 0.1), crest(16), body(-5, 0, 0.03), tail(-8, 1.0), spine(-7), beak(20))),
              (2.0, STAND)])
clip("bow", [(0.0, STAND), (0.8, M(STAND, half(0.5, 0.6), wing_arm(h=(-12, 0, -10)), neck(30, 0, 0.3), crest(-2), body(10, 0, -0.12), legs_stand(0.9), tail(10, 0.6), spine(14))),
             (1.6, M(STAND, half(0.45, 0.65), wing_arm(h=(-14, 0, -12)), neck(34, 0, 0.3), crest(-2), body(11, 0, -0.13), legs_stand(1.0), tail(10, 0.6), spine(15))),
             (2.4, STAND)])
STRETCH_W = {"wingL": {"fold": 0.0, "fan": 0.9}}
clip("stretch", [(0.0, STAND),
                 (0.7, M(STAND, STRETCH_W, E(Shoulder_L=(4, 0, 20), Humerus_L=(-30, 0, 40), Radius_L=(0, 0, -6), Hand_L=(0, 0, -4), Hip_L=(-18, 0, 0), Tibia_L=(-10, 0, 0), Tarsus_L=(26, 0, 0)),
                         neck(4, -10), tail(0, 0.7), E(Tail1=(0, 0, 10), Tail2=(0, 0, 10)), body(0, -4))),
                 (1.6, M(STAND, STRETCH_W, E(Shoulder_L=(6, 0, 22), Humerus_L=(-34, 0, 44), Radius_L=(0, 0, -6), Hand_L=(0, 0, -4), Hip_L=(-22, 0, 0), Tibia_L=(-12, 0, 0), Tarsus_L=(30, 0, 0)),
                         neck(5, -12), tail(0, 0.8), E(Tail1=(0, 0, 12), Tail2=(0, 0, 12)), body(0, -5))),
                 (2.6, STAND)])

# ---- v3: her display, her cocoon of wings, and the power attack (visual pass 2)
def DISP(raise_, sweep=0.0, fan=1.0, amount=1.0, roll=90.0):
    return {"wing": {"fold": 0.0, "fan": fan, "display": amount, "raise": raise_, "sweep": sweep, "roll": roll}}


# MAJESTIC: the regal display of the references - wings raised high and open toward the viewer, primaries
# fanned and sweeping up, the body upright, the neck proud, crest lifted, the train spread below her.
MAJESTIC = M(STAND, DISP(7, -4, 0.95, 1.0, 40), wing_arm(s=(4, 0, 0)), neck(-12, 0, 1.0), crest(12), body(-7, 0, 0.04), tail(12, 1.0), spine(-6))
MAJESTIC_B = M(STAND, DISP(10, -2, 1.0, 1.0, 44), wing_arm(s=(5, 0, 0)), neck(-14, 4, 1.0), crest(15), body(-8, 0, 0.06), tail(14, 1.0, 2), spine(-7))
clip("majestic", [(0.0, MAJESTIC), (1.6, MAJESTIC_B), (3.2, M(MAJESTIC, DISP(5, -6, 0.92, 1.0, 37), neck(-11, -4, 1.0), tail(11, 1.0, -2))), (4.8, MAJESTIC)], loop=True)
clip("majestic_enter", [(0.0, STAND), (0.35, M(STAND, half(0.55, 0.5), neck(-6), crest(6), body(-3), tail(0, 0.6))),
                        (0.75, M(STAND, DISP(20, 10, 0.9, 0.8), neck(-10), crest(10), body(-6, 0, 0.02), tail(-2, 0.9))),
                        (1.1, M(MAJESTIC_B, DISP(14, -2, 1.0, 1.0, 46))), (1.5, MAJESTIC)])
# WRAP: the cocoon - both wings swung forward and closed around her body like a cloak, head bowed inside them
WRAP = M(STAND, DISP(-14, -80, 0.85), wing_arm(s=(-6, 0, 0)), neck(26, 0, 0.6), crest(-4), body(4, 0, -0.06), legs_stand(0.7), tail(4, 0.5), spine(10))
clip("wing_wrap", [(0.0, MAJESTIC), (0.5, M(MAJESTIC_B, DISP(58, 10))), (1.1, M(STAND, DISP(10, -50, 0.9), neck(12, 0, 0.8), body(0, 0, -0.02))),
                   (1.6, WRAP), (2.4, M(WRAP, DISP(-16, -84, 0.85), body(5, 0, -0.07), neck(28, 0, 0.6)))])
clip("wing_burst", [(0.0, WRAP), (0.22, M(STAND, DISP(24, 2, 1.0, 1.0, 55), wing_arm(s=(10, 0, 0)), neck(-24, 0, 1.0), crest(18), body(-12, 0, 0.1), tail(-8, 1.0), spine(-10), beak(18))),
                    (0.5, M(MAJESTIC_B, beak(10))), (1.0, MAJESTIC)])
# the POWER ATTACK ("solar nova"): she rears, wings flung high and back while the fire gathers at her breast,
# then a full downstroke drives the nova forward as her neck strikes, and the wings recover
CHARGE_A = M(STAND, DISP(48, 16, 0.85), wing_arm(s=(12, 0, 0)), neck(-28, 0, 1.2), crest(18), body(-16, 0, 0.12), legs_stand(0.6), tail(-10, 1.0), spine(-12), beak(10))
CHARGE_B = M(STAND, DISP(54, 24, 0.8), wing_arm(s=(14, 0, 0)), neck(-34, 0, 1.3), crest(22), body(-20, 0, 0.16, -0.08), legs_stand(0.8), tail(-12, 1.0), spine(-15), beak(16))
RELEASE = M(STAND, DISP(-6, -36, 0.95), wing_arm(s=(-4, 0, 0)), neck(26, 0, 0.1), crest(-6), body(12, 0, 0.06, 0.45), legs_stand(0.2), tail(10, 0.9), spine(10), beak(30))
FOLLOW = M(STAND, DISP(-16, -46, 0.9), wing_arm(s=(-6, 0, 0)), neck(20, 0, 0.3), crest(-2), body(14, 0, 0.03, 0.5), legs_stand(0.5), tail(8, 0.8), spine(12), beak(22))
clip("attack_charge", [(0.0, STAND), (0.45, M(STAND, half(0.35, 0.7), body(-6, 0, 0.03), neck(-12), crest(8), tail(-4, 0.7))),
                       (0.95, CHARGE_A), (1.4, CHARGE_B)])
clip("attack_hold", [(0.0, CHARGE_B), (0.12, M(CHARGE_B, body(-21, 1, 0.17, -0.08))), (0.24, M(CHARGE_B, body(-19, -1, 0.15, -0.08))), (0.36, CHARGE_B)], loop=True)
clip("attack_release", [(0.0, CHARGE_B), (0.16, RELEASE), (0.38, FOLLOW), (0.6, M(FOLLOW, body(10, 0, 0.0, 0.4)))])
clip("attack_recover", [(0.0, M(FOLLOW, body(10, 0, 0.0, 0.4))),
                        (0.45, M(STAND, DISP(36, 4), body(-3, 0, 0.02, 0.2), neck(-6, 0, 0.8), crest(8), tail(0, 1.0))),
                        (0.9, M(STAND, half(0.35, 0.75), neck(-2), crest(4), tail(0, 0.6), body(0, 0, 0.0, 0.08))),
                        (1.35, M(STAND, half(0.8, 0.35))), (1.6, STAND)])

# ----------------------------------------------------------------------------------------- preview renders
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    mat = bpy.data.materials.new("PreviewFeather")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mixc = nt.nodes.new("ShaderNodeMix")
    mixc.data_type = 'RGBA'
    mixc.blend_type = 'MULTIPLY'
    mixc.inputs[0].default_value = 1.0
    nt.links.new(vc.outputs["Color"], mixc.inputs[6])
    if ATLAS and os.path.exists(ATLAS):
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(ATLAS)
        tex.image.colorspace_settings.name = 'Non-Color'
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(tex.outputs["Color"], sep.inputs[0])
        nt.links.new(sep.outputs[0], mixc.inputs[7])
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    nt.links.new(mixc.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.6
    solid = bpy.data.materials.new("PreviewSolid")
    solid.use_nodes = True
    vc2 = solid.node_tree.nodes.new("ShaderNodeVertexColor")
    vc2.layer_name = "Col"
    solid.node_tree.links.new(vc2.outputs["Color"], solid.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    goldm = mat.copy()
    goldm.name = "PreviewGold"
    goldm.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.85
    goldm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.3
    flm = bpy.data.materials.new("PreviewFlame")
    flm.use_nodes = True
    fnt = flm.node_tree
    for nd in list(fnt.nodes):
        if nd.type == 'BSDF_PRINCIPLED':
            fnt.nodes.remove(nd)
    em = fnt.nodes.new("ShaderNodeEmission")
    tr = fnt.nodes.new("ShaderNodeBsdfTransparent")
    mix = fnt.nodes.new("ShaderNodeMixShader")
    vcf = fnt.nodes.new("ShaderNodeVertexColor")
    vcf.layer_name = "Col"
    fnt.links.new(vcf.outputs["Color"], em.inputs["Color"])
    em.inputs["Strength"].default_value = 6.0
    if ATLAS and os.path.exists(ATLAS):
        ftex = fnt.nodes.new("ShaderNodeTexImage")
        ftex.image = bpy.data.images.load(ATLAS)
        ftex.image.colorspace_settings.name = 'Non-Color'
        fnt.links.new(ftex.outputs["Alpha"], mix.inputs[0])
    fnt.links.new(tr.outputs[0], mix.inputs[1])
    fnt.links.new(em.outputs[0], mix.inputs[2])
    fnt.links.new(mix.outputs[0], fnt.nodes["Material Output"].inputs["Surface"])
    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            ob.data.materials.append(flm if ob.name.startswith("Flames") else (goldm if ob.name.startswith("Gold") else (mat if ob.name.startswith("Feathers") else solid)))
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 800
    scene.render.resolution_y = 600
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.32, 0.36, 0.42, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.5
    sun.rotation_euler = Euler((math.radians(50), math.radians(10), math.radians(-30)))
    bpy.context.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 35
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    ground = bpy.data.meshes.new("G")
    ground.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
    gob = bpy.data.objects.new("Ground", ground)
    bpy.context.collection.objects.link(gob)

    def look(cam_pos, target):
        cam.location = Vector(cam_pos)
        d = Vector(target) - Vector(cam_pos)
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()

    poses = {"stand": M(STAND), "spread": M(STAND, SPREAD_W, OPEN_HIGH, tail(0, 1.0), crest(8)),
             "fly_down": M(FLY_BASE, flap(0.25), body(-4, 0, 0)), "fly_up": M(FLY_BASE, flap(0.75), body(-4, 0, 0)),
             "hover": M(HOVER, flap(0.3, 1.2, -6, 30), body(-40)), "cast": M(STAND, MANTLE, neck(-26, 0, 0.1), crest(16), body(-14), tail(-14, 1.0), spine(-12), beak(14)),
             "defend": M(STAND, SHIELD, neck(22, 0, 0.6), body(5), legs_stand(0.8)), "half": M(STAND, half(0.5, 0.6)),
             "majestic": MAJESTIC, "charge": CHARGE_B, "release": RELEASE, "wrap": WRAP}
    views = {"front": ((0.0, -11.0, 2.6), (0, 0.0, 2.6)), "front34": ((5.5, -8.5, 3.0), (0, -0.4, 2.0)), "side": ((7.5, 0.3, 1.9), (0, 0.3, 1.5)), "back34": ((-4.5, 6.0, 3.4), (0, 0.2, 1.5)),
             "head": ((1.6, -2.9, 2.85), (0, -1.35, 2.62)), "top": ((0.01, 0.4, 9.0), (0, 0.4, 1.4))}
    which = os.environ.get("PHX_PREVIEW", "stand:front34,stand:side,stand:back34,stand:head,spread:front34,fly_down:front34,fly_up:back34,hover:side,cast:front34,defend:front34,half:side,stand:top")
    for item in which.split(","):
        pn, vn = item.split(":")
        apply_pose(poses[pn])
        bpy.context.view_layer.update()
        look(*views[vn])
        scene.render.filepath = os.path.join(PREVIEW, "%s_%s.png" % (pn, vn))
        bpy.ops.render.render(write_still=True)
        print("preview", pn, vn)
    for ob in bpy.data.objects:
        if ob.type == 'MESH' and ob.name not in ("Ground",):
            ob.data.materials.clear()
    bpy.data.objects.remove(gob)
    bpy.data.objects.remove(sun)
    bpy.data.objects.remove(cam)
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()

# ----------------------------------------------------------------------------------------- export
if OUT and not os.environ.get("PHX_NO_EXPORT"):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in bpy.data.objects:
        ob.select_set(True)
    kw = dict(filepath=OUT, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
              export_animations=True, export_force_sampling=True, export_skins=True, export_materials='NONE',
              export_texcoords=True, export_normals=True, export_morph=False, export_optimize_animation_size=False,
              export_anim_single_armature=True, export_rest_position_armature=True, export_def_bones=False)
    try:
        bpy.ops.export_scene.gltf(**kw, export_animation_mode='ACTIONS', export_vertex_color='ACTIVE')
    except TypeError as e:
        print("exporter fallback:", e)
        bpy.ops.export_scene.gltf(**kw, export_nla_strips=True, export_colors=True)
    print("exported", OUT, "clips:", CLIPS)
