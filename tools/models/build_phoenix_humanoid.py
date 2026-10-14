"""Builds ORIEL's HUMANOID FORM - the same character as the Phoenix (tools/models/build_phoenix.py) - as an
adult woman: an original rigged, skinned model on a Mixamo-named humanoid skeleton, so the game's shared
animation library (walk, run, sit, gestures, spellcasting, dodges, ground rest) retargets onto her exactly as it
does onto Mika and Luna.

  blender -b --python tools/models/build_phoenix_humanoid.py -- <out.glb> [preview_dir] [atlas.png] [eyes.png] [mouth.png]

What carries her identity across the two forms (V3 Part X, 47): the same molten-gold eyes with a crimson ring
(tools/models/phoenix_face.py draws them from the same palette as iris.png), the crimson -> ember -> gold ->
white-gold feather language in her hair, the crest plumes at her right temple, feather ornaments (mantle,
earrings, hem, sash tassel), the sun-disc pendant, and her ember glow (Godot).
  * BODY: one smooth skin built with Blender's Skin modifier over a stick figure (so shoulders, hips and
    joints flow into each other), subdivided, then shaped (bust, waist); 1.78 m, ~7.2 heads, long neck.
  * FACE: a smooth head (chin, jaw, cheekbones, small nose, ears) with the PAINTED face of the world's style:
    eye cards and a mouth card conform to the head and show frames of face_eyes.png / face_mouth.png
    (open, half, closed, happy, surprised, angry; closed, smile, aa, oh, ee) - Godot switches frames for
    blinking, emotion and speech.
  * HAIR: a hair cap plus ~28 broad flowing strips (plume cell of the feather atlas) to mid-back, side locks
    over the shoulders, a swept fringe that leaves the eyes clear, three crest plumes, feather earrings.
  * GARMENTS: fitted crimson bodice with a gold neckline and sash; a long, slim skirt slit high on her right,
    with a short train and a feather hem; a feathered half-mantle over her left shoulder and a gold cuff on
    her right; torc + sun-disc pendant; arm/wrist cuffs; anklets; sandal straps.
  * SKELETON: mixamorig_* (Hips, Spine, Spine1, Spine2, Neck, Head, HeadTop_End, Shoulder/Arm/ForeArm/Hand,
    fingers x3 joints, UpLeg/Leg/Foot/ToeBase/Toe_End), T-pose, palms down. No animations in the file.
Axes: Blender Z up, she faces -Y (= +Z in Godot; WorldCharacter turns the avatar to face -Z).
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "phoenix_humanoid.glb"
PREVIEW = argv[1] if len(argv) > 1 else ""
ATLAS = argv[2] if len(argv) > 2 else ""
EYES_PNG = argv[3] if len(argv) > 3 else ""
MOUTH_PNG = argv[4] if len(argv) > 4 else ""

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
random.seed(23)

# ----------------------------------------------------------------------------------------- palette (sRGB)
DEEP = (0.40, 0.025, 0.03)
CRIMSON = (0.66, 0.05, 0.035)
EMBER = (0.93, 0.30, 0.06)
AMBER = (1.0, 0.56, 0.12)
GOLD = (1.0, 0.76, 0.22)
BRIGHT = (1.0, 0.90, 0.56)
WHITEGOLD = (1.0, 0.97, 0.80)
SKIN = (0.95, 0.80, 0.70)
SKIN_WARM = (0.93, 0.72, 0.62)
METAL = (0.95, 0.74, 0.28)
METAL_DARK = (0.72, 0.52, 0.17)
CLOTH = (0.6, 0.05, 0.04)
CLOTH_DARK = (0.42, 0.03, 0.03)
UP = Vector((0, 0, 1))
FWD = Vector((0, -1, 0))


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def grad(s, stops):
    if s <= stops[0][0]:
        return stops[0][1]
    for (s0, c0), (s1, c1) in zip(stops, stops[1:]):
        if s <= s1:
            return lerp(c0, c1, (s - s0) / max(s1 - s0, 1e-6))
    return stops[-1][1]


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0 + 1e-9)))
    return t * t * (3 - 2 * t)


HAIR_GRAD = [(0.0, DEEP), (0.3, CRIMSON), (0.62, EMBER), (0.86, GOLD), (1.0, WHITEGOLD)]
MANTLE_GRAD = [(0.0, DEEP), (0.3, CRIMSON), (0.65, EMBER), (0.88, GOLD), (1.0, BRIGHT)]
HEM_GRAD = [(0.0, EMBER), (0.6, GOLD), (1.0, WHITEGOLD)]

# ----------------------------------------------------------------------------------------- armature
arm_data = bpy.data.armatures.new("PhoenixHumanArmature")
arm = bpy.data.objects.new("Armature", arm_data)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
EB = {}


def bone(name, head, tail, parent=None, up=(0, -1, 0)):
    eb = arm_data.edit_bones.new("mixamorig_" + name)
    eb.head = Vector(head)
    eb.tail = Vector(tail)
    if parent:
        eb.parent = EB[parent]
    eb.align_roll(Vector(up))
    EB[name] = eb
    return eb


def pair(name, head, tail, parent, up=(0, -1, 0)):
    for sfx, sx in (("Left", 1), ("Right", -1)):
        p = parent if parent in EB else sfx + parent
        bone(sfx + name, (head[0] * sx, head[1], head[2]), (tail[0] * sx, tail[1], tail[2]), p, (up[0] * sx, up[1], up[2]))


bone("Hips", (0, 0, 0.99), (0, 0, 1.08))
bone("Spine", (0, 0, 1.08), (0, 0, 1.18), "Hips")
bone("Spine1", (0, 0, 1.18), (0, 0, 1.3), "Spine")
bone("Spine2", (0, 0, 1.3), (0, 0, 1.47), "Spine1")
bone("Neck", (0, 0, 1.47), (0, 0, 1.585), "Spine2")
bone("Head", (0, 0, 1.585), (0, 0, 1.72), "Neck")
bone("HeadTop_End", (0, 0, 1.72), (0, 0, 1.8), "Head")
pair("Shoulder", (0.03, 0, 1.455), (0.165, 0, 1.452), "Spine2", up=(0, 0, 1))
pair("Arm", (0.165, 0, 1.452), (0.455, 0, 1.45), "Shoulder", up=(0, 0, 1))
pair("ForeArm", (0.455, 0, 1.45), (0.715, 0, 1.45), "Arm", up=(0, 0, 1))
pair("Hand", (0.715, 0, 1.45), (0.79, 0, 1.45), "ForeArm", up=(0, 0, 1))
FINGERS = {"Thumb": ((0.5, -0.8, -0.3), 0.027, (0.735, -0.03, 1.443)),
           "Index": ((1, 0, 0), 0.029, (0.795, -0.026, 1.45)), "Middle": ((1, 0, 0), 0.031, (0.8, -0.009, 1.45)),
           "Ring": ((1, 0, 0), 0.028, (0.795, 0.009, 1.45)), "Pinky": ((1, 0, 0), 0.022, (0.785, 0.026, 1.45))}
for fname, (d, seg, start) in FINGERS.items():
    dv = Vector(d).normalized()
    prev = "Hand"
    p0 = Vector(start)
    for k in range(1, 4):
        p1 = p0 + dv * seg
        pair("Hand%s%d" % (fname, k), tuple(p0), tuple(p1), prev, up=(0, 0, 1))
        prev = "Hand%s%d" % (fname, k)
        p0 = p1
pair("UpLeg", (0.09, 0, 0.94), (0.088, 0, 0.5), "Hips")
pair("Leg", (0.088, 0, 0.5), (0.086, 0, 0.085), "UpLeg")
pair("Foot", (0.086, 0, 0.085), (0.086, -0.1, 0.022), "Leg", up=(0, 0, 1))
pair("ToeBase", (0.086, -0.1, 0.022), (0.086, -0.19, 0.012), "Foot", up=(0, 0, 1))
pair("Toe_End", (0.086, -0.19, 0.012), (0.086, -0.225, 0.01), "ToeBase", up=(0, 0, 1))
bpy.ops.object.mode_set(mode='OBJECT')
BONES = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm.data.bones}


def B(n):
    return "mixamorig_" + n


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def nearest_weights(p, names, k=2, power=2.5, snap=0.45, floor=0.015):
    names = [B(n) for n in names]
    ds = sorted(((seg_dist(p, *BONES[n]), n) for n in names))[:k]
    if len(ds) == 1 or ds[0][0] < snap * ds[1][0]:
        return [(ds[0][1], 1.0)]
    ws = [(n, 1.0 / max(d, floor) ** power) for d, n in ds]
    s = sum(w for _, w in ws)
    return [(n, w / s) for n, w in ws]


BODY_CHAIN = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]
ARM = {"Left": ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand"], "Right": ["RightShoulder", "RightArm", "RightForeArm", "RightHand"]}
LEG = {"Left": ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase"], "Right": ["RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]}
ALL_LIMBS = BODY_CHAIN + ARM["Left"] + ARM["Right"] + LEG["Left"] + LEG["Right"]
FINGER_BONES = {s: [s + "Hand%s%d" % (f, k) for f in FINGERS for k in (1, 2, 3)] for s in ("Left", "Right")}


# ----------------------------------------------------------------------------------------- mesh helpers
def to_linear(c):
    return (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)


class MeshBuf:
    def __init__(self, name):
        self.name = name
        self.v, self.f, self.uv, self.c, self.w = [], [], [], [], []
        self.ob = None

    def add(self, verts, faces, uvs, cols, weights):
        base = len(self.v)
        self.v += [tuple(p) for p in verts]
        self.f += [tuple(base + i for i in face) for face in faces]
        self.uv += list(uvs)
        self.c += list(cols)
        self.w += list(weights)
        return base

    def build(self, solid=True, subdiv=0, shade_smooth=None):
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
            ca.data[i].color = to_linear(c)
        uv = me.uv_layers.new(name="UV")
        for poly in me.polygons:
            poly.use_smooth = solid if shade_smooth is None else shade_smooth
            for li in poly.loop_indices:
                uv.data[li].uv = self.uv[me.loops[li].vertex_index]
        set_groups(ob, self.w)
        ob.parent = arm
        if subdiv:
            sd = ob.modifiers.new("Subdiv", 'SUBSURF')
            sd.levels = subdiv
            sd.render_levels = subdiv
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
        self.ob = ob
        return ob


def set_groups(ob, weights):
    groups = {}
    for i, ws in enumerate(weights):
        for b, w in ws:
            groups.setdefault(b, []).append((i, w))
    for b, lst in groups.items():
        vg = ob.vertex_groups.get(b) or ob.vertex_groups.new(name=b)
        for i, w in lst:
            vg.add([i], w, 'REPLACE')


def frame(fwd, up_hint=Vector((0, 0, 1))):
    f = Vector(fwd).normalized()
    r = f.cross(Vector(up_hint))
    if r.length < 1e-4:
        r = f.cross(Vector((1, 0, 0)))
    r.normalize()
    u = r.cross(f).normalized()
    return f, r, u


def loft(buf, rings, n=24, color=lambda p, ang, k: SKIN, weights=None, cap=True):
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
            uvs.append((i / n, k / max(len(idx) - 1, 1)))
            cols.append(color(p, 2 * math.pi * i / n, k))
            ws.append(weights(p) if callable(weights) else weights)
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
            uvs.append((0.5, 0.5))
            cols.append(color(c, 0.0, k))
            ws.append(weights(c) if callable(weights) else weights)
            for i in range(n):
                a = k * n + i
                b = k * n + (i + 1) % n
                faces.append((ci, b, a) if rev else (ci, a, b))
    return buf.add(verts, faces, uvs, cols, ws)


def tube(buf, a, b, r0, r1, color, weights, n=12, steps=3, cap=True):
    a, b = Vector(a), Vector(b)
    rings = [(a.lerp(b, k / steps), b - a, r0 + (r1 - r0) * k / steps, r0 + (r1 - r0) * k / steps, 0.0) for k in range(steps + 1)]
    return loft(buf, rings, n, lambda p, ang, k: color, weights, cap)


def torus(buf, center, axis, R, r, color, weights, n=24, m=8):
    f, a, b = frame(axis)
    verts, faces, uvs, cols, ws = [], [], [], [], []
    for i in range(n):
        t = 2 * math.pi * i / n
        radial = a * math.cos(t) + b * math.sin(t)
        ring_c = Vector(center) + radial * R
        for j in range(m):
            u = 2 * math.pi * j / m
            verts.append(ring_c + radial * (r * math.cos(u)) + f * (r * math.sin(u)))
            uvs.append((i / n, j / m))
            cols.append(color)
            ws.append(weights)
    for i in range(n):
        for j in range(m):
            faces.append((i * m + j, i * m + (j + 1) % m, ((i + 1) % n) * m + (j + 1) % m, ((i + 1) % n) * m + j))
    return buf.add(verts, faces, uvs, cols, ws)


def sphere(buf, center, radii, color, weights, u=16, v=10, displace=None, uvfn=None, keep=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    verts, faces, uvs, cols, ws = [], [], [], [], []
    remap = {}
    for vt in bm.verts:
        q = vt.co.copy()
        p = Vector(center) + Vector((q.x * radii[0], q.y * radii[1], q.z * radii[2]))
        if displace:
            p = displace(p, q)
        remap[vt.index] = len(verts)
        verts.append(p)
        uvs.append(uvfn(q) if uvfn else (0.5 + q.x * 0.4, 0.5 + q.z * 0.4))
        cols.append(color(p, q) if callable(color) else color)
        ws.append(weights(p) if callable(weights) else weights)
    for f in bm.faces:
        if keep and not all(keep(v.co) for v in f.verts):
            continue
        faces.append(tuple(remap[v.index] for v in f.verts))
    bm.free()
    return buf.add(verts, faces, uvs, cols, ws)


CELL = {"flight": (0, 0), "contour": (1, 0), "plume": (0, 1), "streamer": (1, 1)}


def feather(buf, root, direction, up, length, width, cell, gradient, weights, curve=0.08, segs=5, twist=0.0, raise_=0.0, wave=None):
    d, side, n = frame(direction, up)
    cx, cy = CELL[cell]
    verts, faces, uvs, cols, ws = [], [], [], [], []
    for k in range(segs + 1):
        s = k / segs
        p = Vector(root) + d * (length * s) - n * (curve * length * s * s) + n * raise_
        if wave:
            p += side * (wave[0] * math.sin(s * 2 * math.pi * wave[1]))
        tw = twist * s
        sd = side * math.cos(tw) + n * math.sin(tw)
        for uu in (-1.0, 1.0):
            verts.append(p + sd * (width * 0.5 * uu))
            uvs.append((cx * 0.5 + (uu * 0.5 + 0.5) * 0.5, cy * 0.5 + s * 0.5))
            cols.append(grad(s, gradient))
            ws.append(weights(s) if callable(weights) else weights)
    for k in range(segs):
        a = k * 2
        faces.append((a, a + 1, a + 3, a + 2))
    return buf.add(verts, faces, uvs, cols, ws)


def strip(buf, points, widths, up_fn, cell, gradient, weights, tip_fringe=True):
    """A ribbon through `points` (list of Vector) with per-point widths; UVs along the atlas cell."""
    cx, cy = CELL[cell]
    verts, faces, uvs, cols, ws = [], [], [], [], []
    n = len(points)
    for k, p in enumerate(points):
        s = k / (n - 1)
        d = (points[min(k + 1, n - 1)] - points[max(k - 1, 0)]).normalized()
        up = up_fn(k, p)
        side = d.cross(up).normalized()
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        for uu in (-1.0, 1.0):
            verts.append(p + side * (widths[k] * 0.5 * uu))
            uvs.append((cx * 0.5 + (uu * 0.5 + 0.5) * 0.5, cy * 0.5 + s * 0.5))
            cols.append(grad(s, gradient))
            ws.append(weights(s, p) if callable(weights) else weights)
    for k in range(n - 1):
        a = k * 2
        faces.append((a, a + 1, a + 3, a + 2))
    return buf.add(verts, faces, uvs, cols, ws)


def catmull(pts, samples):
    out = []
    P = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(P) - 2):
        for j in range(samples):
            t = j / samples
            p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    out.append(pts[-1])
    return out


# ----------------------------------------------------------------------------------------- the body (skin modifier)
SK_V, SK_E, SK_R = [], [], []


def sv(p, r, ry=None):
    SK_V.append(Vector(p))
    SK_R.append((r, r if ry is None else ry))
    return len(SK_V) - 1


def se(a, b):
    SK_E.append((a, b))


hips = sv((0, 0, 0.99), 0.158, 0.118)
s1 = sv((0, 0, 1.09), 0.146, 0.108)
s2 = sv((0, 0.004, 1.19), 0.138, 0.104)
ch = sv((0, -0.004, 1.29), 0.158, 0.128)
ch2 = sv((0, 0, 1.38), 0.165, 0.112)
nb = sv((0, 0, 1.455), 0.085, 0.075)
n1 = sv((0, 0.004, 1.525), 0.054, 0.052)
n2 = sv((0, 0.004, 1.59), 0.05, 0.05)
for a, b in ((hips, s1), (s1, s2), (s2, ch), (ch, ch2), (ch2, nb), (nb, n1), (n1, n2)):
    se(a, b)
for sx in (1, -1):
    sh = sv((0.165 * sx, 0, 1.452), 0.062)
    ua = sv((0.31 * sx, 0, 1.45), 0.05)
    el = sv((0.455 * sx, 0, 1.45), 0.041)
    fa = sv((0.585 * sx, 0, 1.45), 0.037)
    wr = sv((0.715 * sx, 0, 1.45), 0.03, 0.024)
    pa = sv((0.77 * sx, 0, 1.45), 0.042, 0.015)
    for a, b in ((ch2, sh), (sh, ua), (ua, el), (el, fa), (fa, wr), (wr, pa)):
        se(a, b)
    for fname, (d, seg, start) in FINGERS.items():
        dv = Vector(d).normalized()
        dvs = Vector((dv.x * sx, dv.y, dv.z))
        p0 = Vector((start[0] * sx, start[1], start[2]))
        prev = pa
        for k in range(3):
            pk = p0 + dvs * (seg * (k + 1))
            vi = sv(pk, 0.0105 if fname == "Thumb" else 0.0092 - 0.0012 * k)
            se(prev, vi)
            prev = vi
    hp = sv((0.09 * sx, 0, 0.95), 0.088)
    th = sv((0.088 * sx, 0.005, 0.72), 0.078)
    kn = sv((0.087 * sx, 0, 0.5), 0.058)
    ca = sv((0.086 * sx, 0.012, 0.3), 0.052)
    an = sv((0.086 * sx, 0, 0.095), 0.034)
    he = sv((0.086 * sx, 0.035, 0.04), 0.036, 0.03)
    mf = sv((0.086 * sx, -0.08, 0.03), 0.042, 0.024)
    to = sv((0.086 * sx, -0.195, 0.018), 0.042, 0.015)
    for a, b in ((hips, hp), (hp, th), (th, kn), (kn, ca), (ca, an), (an, he), (he, mf), (mf, to)):
        se(a, b)
me = bpy.data.meshes.new("Body")
me.from_pydata([tuple(v) for v in SK_V], SK_E, [])
me.update()
body_ob = bpy.data.objects.new("Body", me)
bpy.context.collection.objects.link(body_ob)
bpy.context.view_layer.objects.active = body_ob
body_ob.select_set(True)
skin_mod = body_ob.modifiers.new("Skin", 'SKIN')
skin_mod.use_smooth_shade = True
for i, (rx, ry) in enumerate(SK_R):
    me.skin_vertices[0].data[i].radius = (rx, ry)
me.skin_vertices[0].data[hips].use_root = True
bpy.ops.object.modifier_apply(modifier="Skin")
sub = body_ob.modifiers.new("Subdiv", 'SUBSURF')
sub.levels = 2
bpy.ops.object.modifier_apply(modifier="Subdiv")
# shaping: bust, waist, a little shoulder slope; colours; weights
me = body_ob.data
ca = me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='POINT')
uvl = me.uv_layers.new(name="UV")
body_w = []
for v in me.vertices:
    p = v.co
    for sx in (1, -1):
        d2 = ((p.x - 0.068 * sx) ** 2 + (p.z - 1.285) ** 2)
        if p.y < -0.02:
            p.y -= 0.032 * math.exp(-d2 / 0.0022)
    if 1.1 < p.z < 1.22:
        k = math.exp(-((p.z - 1.165) ** 2) / 0.0012)
        p.x *= 1 - 0.07 * k
        p.y *= 1 - 0.05 * k
    if 1.4 < p.z < 1.5 and 0.13 < abs(p.x) < 0.24:
        p.z -= 0.012 * smooth(0.13, 0.2, abs(p.x))
    v.co = p
    col = SKIN
    if p.z < 1.0 and abs(p.x) < 0.2:
        col = lerp(SKIN, SKIN_WARM, 0.25)
    ca.data[v.index].color = to_linear(col)
    chain = ALL_LIMBS
    if abs(p.x) > 0.74:
        chain = FINGER_BONES["Left" if p.x > 0 else "Right"] + [("Left" if p.x > 0 else "Right") + "Hand"]
    body_w.append(nearest_weights(p, chain, k=2, power=2.5, snap=0.5))
for poly in me.polygons:
    poly.use_smooth = True
    for li in poly.loop_indices:
        uvl.data[li].uv = (0.7, 0.7)
set_groups(body_ob, body_w)
body_ob.parent = arm
amod = body_ob.modifiers.new("Armature", 'ARMATURE')
amod.object = arm

# ----------------------------------------------------------------------------------------- the head
HC = Vector((0, 0.004, 1.672))
HR = (0.097, 0.108, 0.122)
EYE_L = Vector((0.04, 0, 1.676))
EYE_R = Vector((-0.04, 0, 1.676))


def head_surface_y(x, z):
    """Front-surface y of the head ellipsoid at (x, z) (None when outside)."""
    q = 1 - ((x - HC.x) / HR[0]) ** 2 - ((z - HC.z) / HR[2]) ** 2
    if q <= 0:
        return None
    return HC.y - HR[1] * math.sqrt(q)


def head_disp(p, q):
    z = p.z - HC.z
    x, y = p.x, p.y - HC.y
    if z < 0:
        t = min(1.0, -z / HR[2])
        x *= (1 - 0.38 * t ** 1.7)
        if y < 0:
            y -= 0.012 * t ** 3                       # the chin comes forward a little
        if y > 0:
            y *= (1 - 0.28 * t ** 2)                  # the back of the jaw tucks in
    if y < 0 and abs(x) > 0.035 and -0.075 < z < -0.01:
        y -= 0.007 * smooth(0.035, 0.065, abs(x)) * smooth(-0.075, -0.035, z) * smooth(-0.005, -0.03, z)   # cheekbones
    if y < 0 and abs(x) < 0.03 and -0.02 < z < 0.03:
        y += 0.004 * (1 - abs(x) / 0.03)                                   # a slight recess between the eyes
    return Vector((x, y + HC.y, p.z))


head = MeshBuf("Head")
def head_col(p, q):
    blush = smooth(0.045, 0.0, math.sqrt((abs(p.x) - 0.062) ** 2 + (p.z - 1.652) ** 2)) * (1.0 if p.y < HC.y - 0.03 else 0.0)
    c = SKIN if p.y < HC.y + 0.03 else lerp(SKIN, SKIN_WARM, 0.3)
    return lerp(c, (0.96, 0.62, 0.58), 0.35 * blush)


sphere(head, HC, HR, head_col, [(B("Head"), 1.0)], u=40, v=26, displace=head_disp)
nose_rings = [(Vector((0, -0.1, 1.678)), Vector((0, -0.3, -1)), 0.006, 0.004, 0.0), (Vector((0, -0.106, 1.665)), Vector((0, -0.45, -1)), 0.0085, 0.006, 0.0),
              (Vector((0, -0.112, 1.654)), Vector((0, -0.2, -1)), 0.0095, 0.007, 0.0), (Vector((0, -0.107, 1.647)), Vector((0, 0.6, -1)), 0.0085, 0.004, 0.0)]
loft(head, nose_rings, 10, lambda p, ang, k: SKIN, lambda p: [(B("Head"), 1.0)])
for sx in (1, -1):
    sphere(head, (0.096 * sx, 0.006, 1.676), (0.011, 0.019, 0.03), SKIN, [(B("Head"), 1.0)], u=10, v=7)
head_ob = head.build(solid=True)

# painted face: cards that conform to the head (eyes, mouth); Godot picks the frame
face = MeshBuf("Face")


def face_card(buf, center, w, h, n=10, m=6, mirror=False, offset=0.0015):
    verts, faces, uvs, cols, ws = [], [], [], [], []
    for j in range(m + 1):
        v = j / m
        for i in range(n + 1):
            u = i / n
            x = center.x + (u - 0.5) * w
            z = center.z + (v - 0.5) * h
            y = head_surface_y(x, z)
            if y is None:
                y = HC.y - HR[1] * 0.2
            # a card point sits just in front of the (displaced) surface
            verts.append(Vector((x, y - offset - 0.004 * (1 - 4 * (v - 0.5) ** 2) * 0.0, z)))
            uvs.append((1 - u if mirror else u, v))
            cols.append((1.0, 1.0, 1.0))
            ws.append([(B("Head"), 1.0)])
    for j in range(m):
        for i in range(n):
            a = j * (n + 1) + i
            faces.append((a, a + 1, a + n + 2, a + n + 1))
    return buf.add(verts, faces, uvs, cols, ws)


face_card(face, EYE_L, 0.08, 0.06, mirror=False)
face_eye_r_base = face_card(face, EYE_R, 0.08, 0.06, mirror=True)
face_ob = face.build(solid=False, shade_smooth=True)
mouth = MeshBuf("Mouth")
face_card(mouth, Vector((0, 0, 1.629)), 0.044, 0.021, n=10, m=4)
mouth_ob = mouth.build(solid=False, shade_smooth=True)

# ----------------------------------------------------------------------------------------- hair
hair = MeshBuf("Hair")
hair_cap = MeshBuf("HairCap")


def head_pt(az, el, out=0.0):
    d = Vector((math.cos(el) * math.sin(az), math.cos(el) * math.cos(az), math.sin(el)))
    p = HC + Vector((d.x * HR[0], d.y * HR[1], d.z * HR[2]))
    return p + d * out


def hair_w(s, p):
    t = smooth(1.42, 1.1, p.z)
    return [(B("Head"), 1.0 - 0.8 * t), (B("Spine2"), 0.8 * t)] if t > 0.01 else [(B("Head"), 1.0)]


# the cap: the upper head shell, slightly larger, minus the face
sphere(hair_cap, HC, (HR[0] * 1.045, HR[1] * 1.045, HR[2] * 1.04), lambda p, q: DEEP if q.z > 0.4 else CRIMSON, [(B("Head"), 1.0)], u=32, v=20,
       keep=lambda q: (q.z > 0.1 and not (q.y < -0.22 and q.z < 0.84)) or (q.y > 0.3 and q.z > -0.55))
hair_cap.build(solid=True)
# flowing strips
strips = []
for i in range(44):
    az = math.radians(-175 + 350 * (i + 0.5) / 44)
    front = abs(az) < math.radians(60)
    if front:
        continue
    el0 = random.uniform(0.95, 1.3)
    p0 = head_pt(az, el0, 0.004)
    p1 = head_pt(az, 0.35, 0.02)
    side_amt = abs(math.sin(az))
    p2 = Vector((p1.x * 0.75 + 0.03 * math.copysign(1, p1.x) * side_amt, max(p1.y * 0.6, 0.02) + 0.1 * (1 - side_amt), 1.33 + random.uniform(-0.03, 0.03)))
    p3 = Vector((p2.x * 0.55, p2.y + 0.03, 1.02 + random.uniform(-0.06, 0.06) + 0.18 * side_amt))
    pts = catmull([p0, p1, p2, p3], 6)
    wmax = random.uniform(0.045, 0.06)
    widths = [wmax * (1 - 0.55 * (k / (len(pts) - 1)) ** 1.5) for k in range(len(pts))]
    strips.append((pts, widths, HAIR_GRAD if random.random() > 0.25 else [(0.0, DEEP), (0.55, CRIMSON), (0.86, AMBER), (1.0, GOLD)]))
# side locks over the shoulders (in front of the ears)
for sx in (1, -1):
    for k in range(2):
        az = math.radians(sx * (70 + 12 * k))
        p0 = head_pt(az, 0.7 + 0.1 * k, 0.004)
        p1 = head_pt(az, 0.05, 0.015)
        p2 = Vector((0.085 * sx + 0.02 * k * sx, -0.045 - 0.02 * k, 1.42))
        p3 = Vector((0.1 * sx, -0.09, 1.2 - 0.08 * k))
        pts = catmull([p0, p1, p2, p3], 6)
        widths = [0.06 * (1 - 0.5 * (j / (len(pts) - 1)) ** 1.5) for j in range(len(pts))]
        strips.append((pts, widths, HAIR_GRAD))
for pts, widths, g in strips:
    strip(hair, pts, widths, lambda k, p: (Vector((p.x, p.y - HC.y, 0)).normalized() if abs(p.x) + abs(p.y - HC.y) > 0.02 else Vector((0, 1, 0))), "plume", g, hair_w)
# the fringe: swept across the brow to her left, ending above the eyebrows
for i in range(10):
    t = (i + 0.5) / 10
    az = math.radians(-58 + 116 * t)
    p0 = head_pt(az, 0.95, 0.004)
    p1 = head_pt(az - 0.14, 0.78, 0.01)
    p2 = head_pt(az - 0.26, 0.64, 0.012)
    pts = catmull([p0, p1, p2], 5)
    widths = [0.034 * (1 - 0.45 * (k / (len(pts) - 1))) for k in range(len(pts))]
    strip(hair, pts, widths, lambda k, p: Vector((p.x, p.y - HC.y, (p.z - HC.z) * 0.5)).normalized(), "plume", HAIR_GRAD, lambda s, p: [(B("Head"), 1.0)])
# crest plumes at her right temple, feather earrings
for i in range(3):
    root = Vector((-0.078 - i * 0.004, -0.035 + i * 0.02, 1.748 + i * 0.004))
    d = Vector((-0.42, 0.5 + 0.12 * i, 0.9 - 0.1 * i)).normalized()
    feather(hair, root, d, Vector((-0.5, -0.2, 0.6)).normalized(), 0.25 - i * 0.03, 0.05, "plume",
            [(0, CRIMSON), (0.4, AMBER), (0.75, GOLD), (1, WHITEGOLD)], [(B("Head"), 1.0)], curve=-0.22, segs=5)
for sx in (1, -1):
    feather(hair, Vector((0.099 * sx, 0.004, 1.655)), Vector((0.12 * sx, 0.1, -1)).normalized(), Vector((sx, 0, 0)), 0.095, 0.028, "plume",
            [(0, GOLD), (0.6, AMBER), (1, CRIMSON)], [(B("Head"), 1.0)], curve=0.05, segs=3)
hair.build(solid=False)

# ----------------------------------------------------------------------------------------- garments
dress = MeshBuf("Dress")
RINGS = [(1.455, 0.182, 0.108, 0.0), (1.41, 0.184, 0.115, 0.0), (1.34, 0.176, 0.133, -0.004), (1.28, 0.176, 0.146, -0.006), (1.21, 0.164, 0.124, 0.0),
         (1.14, 0.154, 0.113, 0.004), (1.065, 0.156, 0.113, 0.004), (0.99, 0.188, 0.128, 0.0), (0.92, 0.2, 0.142, 0.0), (0.8, 0.206, 0.15, 0.0),
         (0.65, 0.214, 0.162, 0.0), (0.48, 0.232, 0.182, 0.0), (0.3, 0.262, 0.212, 0.0), (0.14, 0.3, 0.246, 0.0), (0.035, 0.325, 0.27, 0.0)]
DN = 44
dverts, dfaces, duv, dcol, dw = [], [], [], [], []
exists = {}


def slit_half(z):
    return math.radians(10 + 24 * smooth(0.95, 0.1, z))


SLIT_CENTER = math.radians(232)      # her right-front


def in_slit(ang, z):
    if z > 0.93:
        return False
    d = math.atan2(math.sin(ang - SLIT_CENTER), math.cos(ang - SLIT_CENTER))
    return abs(d) < slit_half(z)


for k, (z, rx, ry, yo) in enumerate(RINGS):
    v = k / (len(RINGS) - 1)
    for i in range(DN):
        ang = 2 * math.pi * i / DN
        back = max(0.0, math.sin(ang))
        train = smooth(0.4, 0.9, back) * smooth(0.6, 0.03, z)
        p = Vector(((rx + 0.1 * train) * math.cos(ang), (ry + 0.14 * train) * math.sin(ang) + yo, z - 0.02 * train))
        dverts.append(p)
        duv.append((0.62 + 0.3 * i / DN, 0.62 + 0.3 * v))
        if z > 1.43:
            c = METAL
        elif 1.03 < z < 1.08:
            c = METAL
        elif z > 1.0:
            c = CLOTH if math.sin(ang) > -0.4 else lerp(CLOTH, CLOTH_DARK, 0.5)
        else:
            c = grad(1 - z / 1.0, [(0.0, CLOTH), (0.45, CRIMSON), (0.75, EMBER), (0.92, GOLD), (1.0, WHITEGOLD)])
        dcol.append(c)
        side = "Left" if p.x > 0 else "Right"
        leg_w = 0.9 * smooth(0.95, 0.55, z) * smooth(0.0, 0.1, abs(p.x))
        wl = [(B("Hips"), 1.0 - leg_w)] if z < 1.1 else [(B("Spine" if z < 1.25 else "Spine1" if z < 1.36 else "Spine2"), 1.0)]
        if leg_w > 0.01:
            wl.append((B(side + "UpLeg"), leg_w * (1 - 0.5 * smooth(0.5, 0.1, z))))
            if z < 0.5:
                wl.append((B(side + "Leg"), leg_w * 0.5 * smooth(0.5, 0.1, z)))
        dw.append(wl)
        exists[(k, i)] = not in_slit(ang, z)
for k in range(len(RINGS) - 1):
    for i in range(DN):
        i2 = (i + 1) % DN
        if exists[(k, i)] and exists[(k, i2)] and exists[(k + 1, i)] and exists[(k + 1, i2)]:
            a = k * DN + i
            b = k * DN + i2
            dfaces.append((a, b, b + DN, a + DN))
dress.add(dverts, dfaces, duv, dcol, dw)
dress_ob = dress.build(solid=False, shade_smooth=True)

orn = MeshBuf("Feathers_Ornament")
# feather hem: the back half of the hem and the two slit edges
for i in range(DN):
    ang = 2 * math.pi * (i + 0.5) / DN
    z, rx, ry, yo = RINGS[-1]
    if in_slit(ang, z) or math.sin(ang) < -0.75:
        continue
    back = max(0.0, math.sin(ang))
    train = smooth(0.4, 0.9, back)
    p = Vector(((rx + 0.1 * train) * math.cos(ang), (ry + 0.14 * train) * math.sin(ang), z - 0.02 * train + 0.05))
    out = Vector((math.cos(ang), math.sin(ang), 0)).normalized()
    side = "Left" if p.x > 0 else "Right"
    wl = [(B("Hips"), 0.3), (B(side + "UpLeg"), 0.3), (B(side + "Leg"), 0.4)]
    feather(orn, p, (out * 0.4 + Vector((0, 0, -1))).normalized(), out, 0.13, 0.05, "contour", HEM_GRAD, wl, curve=0.12, segs=3)
for z in [0.85, 0.72, 0.6, 0.48, 0.36, 0.24, 0.12]:
    for sgn in (-1, 1):
        ang = SLIT_CENTER + sgn * (slit_half(z) + math.radians(2))
        rx = 0.2 + 0.125 * (0.92 - z)
        ry = 0.142 + 0.125 * (0.92 - z)
        p = Vector((rx * math.cos(ang), ry * math.sin(ang), z))
        out = Vector((math.cos(ang), math.sin(ang), 0)).normalized()
        wl = [(B("Hips"), 0.4), (B("RightUpLeg"), 0.6 * (1 - smooth(0.5, 0.1, z))), (B("RightLeg"), 0.6 * smooth(0.5, 0.1, z))]
        feather(orn, p, (out * 0.5 + Vector((0, 0, -1)) + Vector((math.cos(ang + sgn * 1.57), math.sin(ang + sgn * 1.57), 0)) * 0.3).normalized(), out, 0.11, 0.045, "contour", HEM_GRAD, wl, curve=0.1, segs=3)
# the half-mantle over her left shoulder: three shingled rows
for row, (L, w, cell, g, rz, cnt) in enumerate(((0.36, 0.08, "flight", MANTLE_GRAD, 0.0, 9), (0.26, 0.07, "flight", MANTLE_GRAD, 0.012, 9), (0.17, 0.06, "contour", [(0, DEEP), (0.6, CRIMSON), (1, EMBER)], 0.024, 9))):
    for i in range(cnt):
        t = (i + 0.5) / cnt
        a = t * math.pi * 0.62
        root = Vector((0.02 + 0.2 * math.sin(a), 0.075 * math.cos(a) - 0.015, 1.52 - 0.06 * math.sin(a)))
        out = Vector((math.sin(a) * 0.95, 0.55 * math.cos(a) + 0.2, -0.8)).normalized()
        up = Vector((math.sin(a), math.cos(a) * 0.5, 0.75)).normalized()
        wl = [(B("LeftShoulder"), 0.6), (B("Spine2"), 0.4)] if a > 0.5 else [(B("Spine2"), 0.8), (B("Neck"), 0.2)]
        feather(orn, root, out, up, L * (1 + 0.2 * math.sin(a)), w, cell, g, wl, curve=0.22, segs=4, raise_=rz + 0.004 * i)
# sash tassel on her right hip
for i in range(4):
    root = Vector((-0.165 + 0.008 * i, -0.04 + 0.022 * i, 1.03))
    feather(orn, root, Vector((-0.2, 0.08 * i, -1)).normalized(), Vector((-1, 0, 0)), 0.22 - 0.025 * i, 0.04, "plume",
            [(0, GOLD), (0.5, AMBER), (1, CRIMSON)], [(B("Hips"), 1.0)], curve=0.12, segs=4)
orn.build(solid=False)

metal = MeshBuf("Gold")
torus(metal, (0, 0.004, 1.515), (0, 0, 1), 0.084, 0.007, METAL, [(B("Neck"), 0.6), (B("Spine2"), 0.4)])
torus(metal, (0, 0.004, 1.055), (0, 0, 1), 0.163, 0.012, METAL, [(B("Spine"), 0.7), (B("Hips"), 0.3)], n=30, m=8)
torus(metal, (-0.2, 0, 1.445), (1, 0, 0), 0.07, 0.012, METAL, [(B("RightShoulder"), 0.5), (B("RightArm"), 0.5)], n=20, m=8)   # right shoulder cuff
for sx, sfx in ((1, "Left"), (-1, "Right")):
    torus(metal, (0.3 * sx, 0, 1.45), (1, 0, 0), 0.053, 0.008, METAL, [(B(sfx + "Arm"), 1.0)], n=18, m=7)
    torus(metal, (0.69 * sx, 0, 1.45), (1, 0, 0), 0.034, 0.007, METAL, [(B(sfx + "ForeArm"), 1.0)], n=16, m=7)
    torus(metal, (0.086 * sx, 0.0, 0.115), (0, 0, 1), 0.044, 0.006, METAL, [(B(sfx + "Leg"), 1.0)], n=16, m=7)
    torus(metal, (0.086 * sx, -0.075, 0.038), (0, -1, 0), 0.046, 0.004, METAL_DARK, [(B(sfx + "Foot"), 1.0)], n=14, m=6)
    torus(metal, (0.086 * sx, -0.16, 0.025), (0, -1, 0), 0.046, 0.004, METAL_DARK, [(B(sfx + "ToeBase"), 1.0)], n=14, m=6)
metal.build(solid=True)
pend = MeshBuf("Pendant")
tube(pend, (0, -0.094, 1.4), (0, -0.101, 1.4), 0.028, 0.028, WHITEGOLD, [(B("Spine2"), 1.0)], n=20, steps=1)
tube(pend, (0, -0.092, 1.4), (0, -0.103, 1.4), 0.034, 0.034, METAL, [(B("Spine2"), 1.0)], n=20, steps=1)
for i in range(8):
    a = 2 * math.pi * i / 8
    tube(pend, (0.034 * math.cos(a), -0.098, 1.4 + 0.034 * math.sin(a)), (0.05 * math.cos(a), -0.098, 1.4 + 0.05 * math.sin(a)), 0.004, 0.001, METAL, [(B("Spine2"), 1.0)], n=6, steps=1)
pend.build(solid=True)

# ----------------------------------------------------------------------------------------- preview renders
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)

    def mat_vc(name, atlas=None, frame_img=None, cols=1, rows=1, frame=(0, 0)):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = 0.55
        if frame_img:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(frame_img)
            mapping = nt.nodes.new("ShaderNodeMapping")
            uvn = nt.nodes.new("ShaderNodeUVMap")
            mapping.inputs["Scale"].default_value = (1.0 / cols, 1.0 / rows, 1)
            mapping.inputs["Location"].default_value = (frame[0] / cols, (rows - 1 - frame[1]) / rows, 0)
            nt.links.new(uvn.outputs["UV"], mapping.inputs["Vector"])
            nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            mat.blend_method = 'CLIP'
            return mat
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        if atlas:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(atlas)
            tex.image.colorspace_settings.name = 'Non-Color'
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(tex.outputs["Color"], sep.inputs[0])
            mixc = nt.nodes.new("ShaderNodeMix")
            mixc.data_type = 'RGBA'
            mixc.blend_type = 'MULTIPLY'
            mixc.inputs[0].default_value = 1.0
            nt.links.new(vc.outputs["Color"], mixc.inputs[6])
            nt.links.new(sep.outputs[0], mixc.inputs[7])
            nt.links.new(mixc.outputs[2], bsdf.inputs["Base Color"])
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            mat.blend_method = 'CLIP'
        else:
            nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
        return mat

    m_feather = mat_vc("Feather", atlas=ATLAS if ATLAS and os.path.exists(ATLAS) else None)
    m_solid = mat_vc("Solid")
    m_eyes = mat_vc("EyesTex", frame_img=EYES_PNG, cols=3, rows=2, frame=(0, 0)) if EYES_PNG and os.path.exists(EYES_PNG) else m_solid
    m_mouth = mat_vc("MouthTex", frame_img=MOUTH_PNG, cols=5, rows=1, frame=(1, 0)) if MOUTH_PNG and os.path.exists(MOUTH_PNG) else m_solid
    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            ob.data.materials.append({"Hair": m_feather, "Feathers_Ornament": m_feather, "Face": m_eyes, "Mouth": m_mouth}.get(ob.name, m_solid))
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = False
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.33, 0.4, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = Euler((math.radians(55), math.radians(15), math.radians(-35)))
    bpy.context.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 50
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    ground = bpy.data.meshes.new("G")
    ground.from_pydata([(-10, -10, 0), (10, -10, 0), (10, 10, 0), (-10, 10, 0)], [], [(0, 1, 2, 3)])
    gob = bpy.data.objects.new("Ground", ground)
    bpy.context.collection.objects.link(gob)

    def look(cam_pos, target):
        cam.location = Vector(cam_pos)
        d = Vector(target) - Vector(cam_pos)
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()

    views = {"front": ((0.7, -4.2, 1.2), (0, 0, 0.95)), "side": ((4.0, -0.7, 1.1), (0, 0, 0.95)), "back": ((-1.3, 4.0, 1.3), (0, 0, 0.95)),
             "face": ((0.22, -0.8, 1.7), (0, 0, 1.665)), "face34": ((0.55, -0.62, 1.74), (0, -0.02, 1.665)), "front34": ((2.4, -3.4, 1.4), (0, 0, 0.95))}
    which = os.environ.get("PHXH_PREVIEW", "front,side,back,face,face34,front34")
    for vn in which.split(","):
        look(*views[vn])
        scene.render.resolution_x = 700
        scene.render.resolution_y = 700 if vn.startswith("face") else 900
        scene.render.filepath = os.path.join(PREVIEW, "human_%s.png" % vn)
        bpy.ops.render.render(write_still=True)
        print("preview", vn)
    for ob in bpy.data.objects:
        if ob.type == 'MESH' and ob.name != "Ground":
            ob.data.materials.clear()
    bpy.data.objects.remove(gob)
    bpy.data.objects.remove(sun)
    bpy.data.objects.remove(cam)

# ----------------------------------------------------------------------------------------- export
if OUT and not os.environ.get("PHX_NO_EXPORT"):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in bpy.data.objects:
        ob.select_set(True)
    kw = dict(filepath=OUT, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
              export_animations=False, export_skins=True, export_materials='NONE', export_texcoords=True, export_normals=True,
              export_morph=False, export_def_bones=False, export_rest_position_armature=True)
    try:
        bpy.ops.export_scene.gltf(**kw, export_vertex_color='ACTIVE')
    except TypeError as e:
        print("exporter fallback:", e)
        bpy.ops.export_scene.gltf(**kw, export_colors=True)
    print("exported", OUT)
