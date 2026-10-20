"""Mika L1 outfit v2 (Selwyn 2026-10-20), stage 1: place the 9 baked v2 parts on Mika (rest T-pose), the o10_place.py
way (tools/lib/outfit_fit.py). Starts from l1_outfit/blend/o10_placed.blend, the placement the shipping L1 VRM was
rigged from, so her current hair, shoes, bracelets, hair flower and back bow stay exactly as they ship; the v1 bodice,
collar, skirt, sleeves, waist brooch and pendants come out.
  bodice      scaled to her bust and torso length, pushed out of the body
  underskirt  waistband on her hips, the hem rounder than the waist
  sash        wrapped onto the bodice at the waist: every vertex sits at the outermost surface under it plus a gap
  collar      wrapped the same way onto her neck above the bodice's halter
  bow         front centre of the sash, brooch on the bow knot
  sleeve      one detached sleeve along the left arm, mirrored for the right
  panels      6 panels wrapped around the outer envelope of skirt and peplum, front centre left open for the bow tails,
              white side out; the right side ones mirrored
  stars       small gold decals on the outside of each sleeve and each panel
Panel and star keep their flat colours through a 4 cell palette swatch texture, so every part ends up with one
textured material.
  blender -b -t 2 --python l1_v2/tools/v2_place.py
Output: l1_v2/fit/v2_placed.blend, l1_v2/fit/placement.json"""
import bpy, bmesh, os, sys, json, math
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
LAB = '/home/selwyn/Downloads/Mika-Transformation-Lab'
sys.path.insert(0, LAB + '/tools/lib')
import outfit_fit as F

V2 = LAB + '/l1_v2'
OUT = V2 + '/fit'
os.makedirs(OUT, exist_ok=True)
SPEC = json.load(open(V2 + '/tools/v2_spec.json'))
PAL = {'white': 'F4F4FA', 'navy': '1C2556', 'gold': 'D8B26A', 'sky': '6FA8E8'}

bpy.ops.wm.open_mainfile(filepath=LAB + '/l1_outfit/blend/o10_placed.blend')
A = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
bone = lambda n: np.array(A.matrix_world @ A.data.bones[n].head_local)
GONE = ['L1_Bodice', 'L1_Collar', 'L1_Skirt', 'L1_Sleeve_L', 'L1_Sleeve_R', 'L1_WaistBrooch', 'L1_StarPendant_L',
        'L1_StarPendant_R', 'L1_OrbPendant_L', 'L1_OrbPendant_R']
for n in GONE:
    bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
coll = bpy.data.collections['L1_Outfit']
body = bpy.data.objects['Body']
BV = F.verts(body) @ np.array(body.matrix_world.to_3x3()).T + np.array(body.matrix_world.translation)
S_body = F.Surface([body])
rep = {'removed_v1': GONE}


def load(path, name):
    o = F.import_glb(path, name)
    for c in list(o.users_collection): c.objects.unlink(o)
    coll.objects.link(o)
    return o


def body_slice(z, xmax=0.16, h=0.006):
    s = BV[(np.abs(BV[:, 2] - z) < h) & (np.abs(BV[:, 0]) < xmax)]
    return s.min(0), s.max(0)


def swatch(o):
    """flat colour materials -> one material with a 4 cell palette texture, every face's uvs on its colour's cell"""
    me = o.data
    img = bpy.data.images.get('L1_v2_Swatch')
    if img is None:
        img = bpy.data.images.new('L1_v2_Swatch', 64, 16, alpha=False)
        px = np.zeros((16, 64, 4))
        for k, h in enumerate(PAL.values()):
            c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]                  # a byte image stores sRGB as is
            px[:, k * 16:(k + 1) * 16, :3] = c; px[..., 3] = 1
        img.pixels.foreach_set(px.astype(np.float32).ravel()); img.pack()
    names = [m.name.split('.')[0].replace('MIKA_L1_', '') for m in me.materials]
    if not me.uv_layers: me.uv_layers.new(name='UVMap')
    uv = me.uv_layers[0].data
    for p in me.polygons:
        cell = list(PAL).index(names[p.material_index])
        for li in p.loop_indices:
            uv[li].uv = ((cell + 0.5) / 4, 0.5)
    m = bpy.data.materials.new(o.name); m.use_nodes = True
    tn = m.node_tree.nodes.new('ShaderNodeTexImage'); tn.image = img; tn.interpolation = 'Closest'
    m.node_tree.links.new(tn.outputs['Color'], m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    me.materials.clear(); me.materials.append(m)


def outer_radius(surf_objs, centre_xy, z, theta, r0=0.6):
    """outermost surface radius at (theta, z) around a vertical axis: a ray from outside toward the axis"""
    bvh = surf_objs
    d = np.array([math.sin(theta), -math.cos(theta), 0.0])             # theta 0 = front (-Y), + toward her left (+X)
    o = np.array([centre_xy[0], centre_xy[1], z]) + d * r0
    loc, _n, _i, dist = bvh.ray_cast(Vector(o), Vector(-d), r0)
    return None if loc is None else r0 - dist


def bvh_of(objs):
    vs, ps = [], []
    for ob in objs:
        me = ob.data; mw = ob.matrix_world; base = len(vs)
        vs += [mw @ v.co for v in me.vertices]
        ps += [[base + i for i in p.vertices] for p in me.polygons]
    return BVHTree.FromPolygons(vs, ps)


def wrap_ring(o, under, centre_xy, zc, sz, gap, thick_scale):
    """ring part (vertical axis, model centred): each vertex goes to the outermost surface under it plus gap plus its
    own distance from the ring's inner wall (kept as thickness)"""
    V = F.verts(o)
    th = np.arctan2(V[:, 0], -V[:, 1]); rm = np.linalg.norm(V[:, :2], axis=1)
    zw = zc + V[:, 2] * sz
    # inner wall radius of the model per angle bin
    bins = np.round((th + math.pi) / (2 * math.pi) * 72).astype(int) % 72
    rin = np.array([rm[bins == b].min() if (bins == b).any() else rm.min() for b in range(72)])
    # outermost radius under each vertex, on a grid then looked up
    zs = np.linspace(zw.min(), zw.max(), 12); ts = np.linspace(-math.pi, math.pi, 73)[:-1]
    G = np.array([[outer_radius(under, centre_xy, z, t) or 0.0 for t in ts] for z in zs])
    G[G == 0] = G[G > 0].mean()
    zi = np.clip(np.interp(zw, zs, np.arange(len(zs))), 0, len(zs) - 1)
    ti = ((th + math.pi) / (2 * math.pi) * 72) % 72
    z0 = np.floor(zi).astype(int); z1 = np.minimum(z0 + 1, len(zs) - 1); fz = zi - z0
    t0 = np.floor(ti).astype(int) % 72; t1 = (t0 + 1) % 72; ft = ti - np.floor(ti)
    R = (G[z0, t0] * (1 - fz) * (1 - ft) + G[z1, t0] * fz * (1 - ft) + G[z0, t1] * (1 - fz) * ft + G[z1, t1] * fz * ft)
    rw = R + gap + (rm - rin[bins]) * thick_scale
    W = np.c_[centre_xy[0] + np.sin(th) * rw, centre_xy[1] - np.cos(th) * rw, zw]
    F.set_verts(o, W)
    return W


FINAL = V2 + '/final/MIKA_L1_%s.glb'

# ---------------------------------------------------------------- underskirt: waistband on the hips, rounder hem
u = SPEC['under']
und = load(FINAL % 'under', 'L1_v2_Under')
UV_ = F.verts(und)
lo, hi = body_slice(u['top_z'])
cy = (lo[1] + hi[1]) / 2
ztop_m, zbot_m = UV_[:, 2].max(), UV_[:, 2].min()
r_top_m = np.percentile(np.linalg.norm(UV_[UV_[:, 2] > ztop_m - 0.02][:, :2], axis=1), 50)
sx = (hi[0] + u['gap']) / r_top_m
sy_top = ((hi[1] - lo[1]) / 2 + u['gap']) / r_top_m
t = (ztop_m - UV_[:, 2]) / (ztop_m - zbot_m)
sy = sy_top + (sx * u['hem_round'] - sy_top) * t
W = np.c_[UV_[:, 0] * sx, UV_[:, 1] * sy + cy + u.get('hem_dy', 0) * t, u['top_z'] + (UV_[:, 2] - ztop_m) * u['sz']]
F.set_verts(und, W)
rep['under'] = dict(sx=sx, sy_top=sy_top, sz=u['sz'], top_z=u['top_z'], hem_z=float(W[:, 2].min()))

# ---------------------------------------------------------------- bodice: bust width and depth, torso length
b = SPEC['bodice']
bod = load(FINAL % 'bodice_core', 'L1_v2_Bodice')
BD = F.verts(bod)
zt_m, zb_m = BD[:, 2].max(), BD[:, 2].min()
sz = (b['top_z'] - b['bottom_z']) / (zt_m - zb_m)
bz_m = zb_m + (b['bust_z'] - b['bottom_z']) / sz
sl = BD[np.abs(BD[:, 2] - bz_m) < 0.03]
blo, bhi = body_slice(b['bust_z'])
sx = (bhi[0] + b['gap']) / max(sl[:, 0].max(), -sl[:, 0].min())
sy = ((bhi[1] - blo[1]) / 2 + b['gap']) / ((sl[:, 1].max() - sl[:, 1].min()) / 2)
cym = (sl[:, 1].max() + sl[:, 1].min()) / 2
W = np.c_[BD[:, 0] * sx, (BD[:, 1] - cym) * sy + (blo[1] + bhi[1]) / 2 + b.get('dy', 0), b['bottom_z'] + (BD[:, 2] - zb_m) * sz]
F.set_verts(bod, W)
rep['bodice'] = dict(sx=sx, sy=sy, sz=sz, bust_slice_model=[float(sl[:, 0].max()), float(sl[:, 1].min()), float(sl[:, 1].max())])
rep['conform_bodice'] = F.conform(bod, S_body, margin=b['margin'], reach=0.03)
rep['conform_under'] = F.conform(und, S_body, margin=u['margin'], reach=0.04)

# ---------------------------------------------------------------- sash: wrapped onto the bodice at the waist
s = SPEC['sash']
sash = load(FINAL % 'sash', 'L1_v2_Sash')
SV = F.verts(sash)
under_bvh = bvh_of([body, bod, und])
lo, hi = body_slice(s['z'])
centre = np.array([0.0, (lo[1] + hi[1]) / 2])
szs = s['height'] / (SV[:, 2].max() - SV[:, 2].min())
SV[:, 2] -= (SV[:, 2].max() + SV[:, 2].min()) / 2; F.set_verts(sash, SV)
wrap_ring(sash, under_bvh, centre, s['z'], szs, s['gap'], szs)
rep['sash'] = dict(z=s['z'], height=s['height'], centre=centre.tolist())

# ---------------------------------------------------------------- collar: wrapped onto the neck
c = SPEC['collar']
col = load(FINAL % 'collar', 'L1_v2_Collar')
CV = F.verts(col)
lo, hi = body_slice(c['z'], xmax=0.08)
cc = np.array([0.0, (lo[1] + hi[1]) / 2])
szc = c['height'] / (CV[:, 2].max() - CV[:, 2].min())
CV[:, 2] -= (CV[:, 2].max() + CV[:, 2].min()) / 2; F.set_verts(col, CV)
wrap_ring(col, bvh_of([body, bod]), cc, c['z'], szc, c['gap'], szc)
rep['collar'] = dict(z=c['z'], height=c['height'])

# ---------------------------------------------------------------- bow at front centre of the sash, brooch on the knot
w = SPEC['bow']
bow = load(FINAL % 'bow', 'L1_v2_Bow')
WV = F.verts(bow)
mid = WV[np.abs(WV[:, 0]) < 0.06]                                        # the knot: the front most part of the centre
knot_m = np.array([0.0, mid[:, 1].min(), mid[np.argmin(mid[:, 1]), 2]])
back_m = WV[:, 1].max()
SW_ = F.verts(sash)
front = SW_[(np.abs(SW_[:, 0]) < 0.01)]
fy = front[:, 1].min()
F.place(bow, S=(w['s'],) * 3, anchor_model=[0, back_m, knot_m[2]], anchor_world=[0, fy - w['gap'], s['z'] + w.get('dz', 0)])
knot_w = (knot_m - [0, back_m, knot_m[2]]) * w['s'] + [0, fy - w['gap'], s['z'] + w.get('dz', 0)]
rep['bow'] = dict(knot=knot_w.tolist(), knot_model=knot_m.tolist())
r_ = SPEC['brooch']
bro = load(FINAL % 'brooch', 'L1_v2_Brooch')
RV = F.verts(bro)
F.place(bro, S=(r_['s'],) * 3, anchor_model=[0, RV[:, 1].max(), 0], anchor_world=knot_w + [0, -r_['gap'], r_.get('dz', 0)])
rep['brooch'] = dict(centre=(knot_w + [0, -r_['gap'], 0]).tolist())

# ---------------------------------------------------------------- sleeves: top ring on the upper arm, along the arm
lp = SPEC['sleeve']
slL = load(FINAL % 'sleeve', 'L1_v2_Sleeve_L')
SLV = F.verts(slL)
ctop = SLV[SLV[:, 2] > SLV[:, 2].max() - lp['ring_h']].mean(0)
cbot = SLV[SLV[:, 2] < SLV[:, 2].min() + lp['end_h']].mean(0)
R0 = np.array([[0, 0, -1], [-1, 0, 0], [0, 1, 0]], float)               # model top (+z) toward the shoulder, y -> up
shoulder, wrist = bone('J_Bip_L_UpperArm'), bone('J_Bip_L_Hand')
armdir = (wrist - shoulder) / np.linalg.norm(wrist - shoulder)
R1 = F.align_rotation(R0 @ (cbot - ctop), armdir) @ R0
R = F.euler_matrix((lp.get('roll', 0), 0, 0)) @ R1
p_top = shoulder + armdir * lp['top_from_shoulder']
p_end = wrist - armdir * lp['end_before_wrist']
s_len = np.linalg.norm(p_end - p_top) / np.linalg.norm(cbot - ctop)
F.place(slL, R=R, S=(1, 1, 1), anchor_model=ctop, anchor_world=[0, 0, 0])
L = F.verts(slL)                                                         # local: x along the arm from the top ring
ax = armdir
along = L @ ax; radial = L - np.outer(along, ax)
tt = np.clip(along / np.linalg.norm(cbot - ctop), 0, 1)
sc = lp['cross_top'] + (lp['cross_end'] - lp['cross_top']) * tt          # cross scale from the ring to the bell
W = p_top + np.outer(along * s_len, ax) + radial * sc[:, None]
F.set_verts(slL, W)
slR = F.duplicate(slL, 'L1_v2_Sleeve_R'); F.mirror_x(slR)
rep['conform_sleeve'] = [F.conform(o, S_body, margin=lp['margin'], reach=0.03) for o in (slL, slR)]
rep['sleeve'] = dict(len_scale=s_len, cross_top=lp['cross_top'], cross_end=lp['cross_end'])

# ---------------------------------------------------------------- panels: wrapped around skirt and peplum
pp = SPEC['panel']
pan0 = load(V2 + '/built_txf/MIKA_L1_panel.glb', 'L1_v2_Panel_0')
me = pan0.data
wn = np.array([0.0, 0, 0]);
for p in me.polygons:
    if me.materials[p.material_index].name.startswith('MIKA_L1_white'): wn += np.array(p.normal) * p.area
white_sign = 1.0 if wn[1] > 0 else -1.0                                  # model y side that carries the white front
swatch(pan0)
PV0 = F.verts(pan0)
env = bvh_of([body, bod, und])
ztop_m = PV0[:, 2].max()
zs = np.linspace(pp['top_z'] - 0.7, pp['top_z'] + 0.005, 90)[::-1]       # top down
PANELS = []
for k, ang in enumerate(pp['angles']):
    th0 = math.radians(ang)
    o = pan0 if k == 0 else F.duplicate(pan0, 'L1_v2_Panel_%d' % k)
    o.name = o.data.name = 'L1_v2_Panel_%d' % k
    V = PV0.copy()
    if ang < 0: V[:, 0] *= -1                                             # her right side: mirrored, same look
    # envelope radius down the panel's centre angle (and its width), hanging: never narrower than anything above
    thw = np.linspace(th0 - 0.7, th0 + 0.7, 41)                          # dense: the peplum's points are narrow
    Rz = np.array([max([outer_radius(env, (0.0, pp['cy']), z, t) or 0 for t in thw]) for z in zs])
    Rz = np.maximum.accumulate(Rz) + pp['gap']
    arc = np.concatenate([[0], np.cumsum(np.hypot(np.diff(Rz), np.diff(zs)))])
    a = (ztop_m - V[:, 2]) * pp['s']                                      # arc length down from the top edge
    zw = np.interp(a, arc, zs); Rw = np.interp(a, arc, Rz)
    Rw = Rw + V[:, 1] * white_sign * pp['s']                              # white side out
    th = th0 + V[:, 0] * pp['s'] / Rw
    W = np.c_[np.sin(th) * Rw, pp['cy'] - np.cos(th) * Rw, zw]
    F.set_verts(o, W)
    if ang < 0:                                                           # mirrored: faces back the right way out
        bm = bmesh.new(); bm.from_mesh(o.data); bmesh.ops.reverse_faces(bm, faces=bm.faces[:]); bm.to_mesh(o.data); bm.free()
    PANELS.append((o, th0, a.max()))
rep['panels'] = dict(angles=pp['angles'], s=pp['s'], white_sign=white_sign)

# the bow is the outermost layer: below the knot its tails bend outward over the front panels and the skirt. One
# smooth outward shift per spot of the tail, measured at the bow's back face there, so front and back move together
from mathutils.kdtree import KDTree
outer = bvh_of([o for o, _t, _a in PANELS] + [und, bod, sash])
BW = F.verts(bow)
kd = KDTree(len(BW))
for i, p in enumerate(BW): kd.insert(Vector((p[0], 0, p[2])), i)
kd.balance()
low = np.where(BW[:, 2] < knot_w[2] - 0.005)[0]
delta = np.zeros(len(BW))
for i in low:
    x, _y, z = BW[i]
    yb = max(BW[j, 1] for _c, j, _d in kd.find_range(Vector((x, 0, z)), 0.006))        # back face here
    th = math.atan2(x, -(yb - centre[1])); r = math.hypot(x, yb - centre[1])
    Re = max([outer_radius(outer, centre, z, th + dt) or 0 for dt in (-0.03, 0, 0.03)])
    delta[i] = max(0.0, Re + w['margin'] - r)
sm = delta.copy()
for i in low:                                                            # smooth, so the bend has no kinks
    nb = [j for _c, j, _d in kd.find_range(Vector((BW[i, 0], 0, BW[i, 2])), 0.012)]
    sm[i] = max(delta[i], float(np.mean(delta[nb])))
th = np.arctan2(BW[:, 0], -(BW[:, 1] - centre[1]))
BW[:, 0] += np.sin(th) * sm; BW[:, 1] -= np.cos(th) * sm
F.set_verts(bow, BW)
rep['bow_tail_shift_max_mm'] = float(sm.max() * 1000)

# ---------------------------------------------------------------- star decals
st = SPEC['star']
star0 = load(V2 + '/built_tx/MIKA_L1_star.glb', 'L1_v2_Star_0')
swatch(star0)
TV0 = F.verts(star0); TV0 -= (TV0.max(0) + TV0.min(0)) / 2
host_bvh = {}


def put_star(name, host, p_guess, up_hint):
    if host.name not in host_bvh: host_bvh[host.name] = bvh_of([host])
    loc, nrm, _i, _d = host_bvh[host.name].find_nearest(Vector(p_guess))
    n = np.array(nrm); c = np.array(loc)
    # outward: away from the body axis
    rad = c[:2] - [0, -0.02] if abs(c[0]) < 0.2 else np.array([0.0, -1.0])
    if host.name.startswith('L1_v2_Sleeve'):
        if n[1] > 0: n = -n                                               # the sleeve's front (toward -Y)
    elif np.dot(n[:2], rad) < 0: n = -n
    up = np.array(up_hint, float); up -= n * np.dot(up, n); up /= np.linalg.norm(up)
    right = np.cross(up, n)
    Rm = np.c_[right, -n, up]                                             # model x -> right, y (thin) -> -n, z -> up
    o = star0 if name == 'L1_v2_Star_0' else F.duplicate(star0, name)
    o.name = o.data.name = name
    F.set_verts(o, (TV0 * st['s']) @ Rm.T + c + n * st['lift'])
    return dict(at=c.round(4).tolist(), normal=n.round(3).tolist())


stars = {}
k = 0
for o, th0, alen in PANELS:
    V = F.verts(o); zc = V[:, 2].max() - (V[:, 2].max() - V[:, 2].min()) * st['panel_t']
    m = np.abs(V[:, 2] - zc) < 0.01
    p = V[m].mean(0)
    stars['L1_v2_Star_%d' % k] = put_star('L1_v2_Star_%d' % k, o, p, [0, 0, 1]); k += 1
for sl_ in (slL, slR):
    sg = 1 if sl_ is slL else -1
    t_ = st['sleeve_t']
    c_ = p_top * [sg, 1, 1] + (p_end - p_top) * [sg, 1, 1] * t_
    V = F.verts(sl_)
    m = np.abs((V - c_) @ (armdir * [sg, 1, 1])) < 0.012
    cand = V[m]; p = cand[np.argmin(cand[:, 1])]                          # front most point of the sleeve there
    stars['L1_v2_Star_%d' % k] = put_star('L1_v2_Star_%d' % k, sl_, p, armdir * [sg, 1, 1] * -1); k += 1
rep['stars'] = stars

# ---------------------------------------------------------------- report
tris, v2tris = {}, 0
for o in coll.objects:
    o.data.calc_loop_triangles(); tris[o.name] = len(o.data.loop_triangles)
    if o.name.startswith('L1_v2_'): v2tris += tris[o.name]
rep['tris'] = tris; rep['tris_v2_outfit'] = v2tris; rep['tris_kept'] = sum(tris.values()) - v2tris
for o in coll.objects:
    V = F.verts(o); rep.setdefault('bounds', {})[o.name] = [V.min(0).round(4).tolist(), V.max(0).round(4).tolist()]
json.dump(rep, open(OUT + '/placement.json', 'w'), indent=1, default=float)
bpy.ops.wm.save_as_mainfile(filepath=OUT + '/v2_placed.blend')
print('PLACED v2 outfit tris', v2tris, 'kept', rep['tris_kept'])
