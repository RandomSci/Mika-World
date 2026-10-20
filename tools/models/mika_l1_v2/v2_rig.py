"""Mika L1 outfit v2 (Selwyn 2026-10-20), stage 2: rig, spring bones, colliders, MToon materials, VRM export.
A fork of tools/o12_rig.py: the hair, ears, back bow, hair flower, bracelet and shoe sections are o12's own lines, so
the kept pieces rig exactly as they ship; the v1 outfit sections are replaced by the v2 parts:
  underskirt  sector chains around the hips (the v1 skirt's set-up, shorter)
  panels      one chain down each panel, springs with the leg and hand colliders
  bow         knot with the sash (torso weights), a chain down each tail
  brooch      with the bow knot
  sleeves     o12's tube on the arm weights and hanging chains in the bell
  bodice, sash, collar  the body's torso weights; stars take the weights of the cloth under them
Every v2 cloth part is two sided.
  blender -b -t 2 --python l1_v2/tools/v2_rig.py -- [--no-export] [--out=MikaCelestial_L1v2]
Input : l1_v2/fit/v2_placed.blend (v2_place.py)
Output: l1_v2/fit/<out>.blend, l1_v2/fit/export/<out>.vrm, l1_v2/fit/rig.json"""
import bpy, os, sys, json, math
import numpy as np
from mathutils import Vector, Matrix
from mathutils.kdtree import KDTree
sys.path.insert(0, '/home/selwyn/Downloads/Mika-Transformation-Lab/tools/lib')
import lab, colliders, rig, garment as G, outfit_fit as F

OUTD = lab.LAB + '/l1_v2/fit'
ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
OUT = next((a.split('=', 1)[1] for a in ARGS if a.startswith('--out=')), 'MikaCelestial_L1v2')
bpy.ops.wm.open_mainfile(filepath=OUTD + '/v2_placed.blend')
PLACE = json.load(open(OUTD + '/placement.json'))
A = lab.arm()
ob = bpy.data.objects
rep = {}
P = lambda n: np.array(A.matrix_world @ A.data.bones[n].head_local)
T = lambda n: np.array(A.matrix_world @ A.data.bones[n].tail_local)

# ---------------------------------------------------------------- 1. old outfit springs / bones out (ears + bust stay)
KEEP_SPR = ('EarL', 'EarR')
colliders.remove_springs(A, [s.vrm_name for s in A.data.vrm_addon_extension.spring_bone1.springs if s.vrm_name not in KEEP_SPR])
lab.mode(A, 'EDIT')
gone = [b.name for b in A.data.edit_bones if b.name.startswith('J_Sec_') and not b.name.startswith(('J_Sec_Ear', 'J_Sec_L_Bust', 'J_Sec_R_Bust'))]
for b in gone: A.data.edit_bones.remove(A.data.edit_bones[b])
lab.mode(A, 'OBJECT')
for o in (ob['Body'], ob['Face'], ob['Face_Blush']):
    for vg in list(o.vertex_groups):
        if vg.name in gone: o.vertex_groups.remove(vg)
rep['removed_bones'] = len(gone)

# ---------------------------------------------------------------- 2. conform (push out of the body, a few mm)
body = ob['Body']; face = ob['Face']
S_body = F.Surface([body]); S_face = F.Surface([face])
C = {}
for s in 'LR':
    C['shoe_' + s] = F.conform(ob['L1_Shoe_' + s], S_body, margin=0.0015, reach=0.025, region=lambda V: V[:, 2] > 0.012)   # never the sole
    C['bracelet_' + s] = F.conform(ob['L1_Bracelet_' + s], S_body, margin=0.002, reach=0.01)
# hair: below the head it must clear the body *and* the bodice (~1 cm), at the face only shallow fixes
C['hair_body'] = F.conform(ob['L1_Hair'], S_body, margin=0.012, reach=0.05, region=lambda V: V[:, 2] < 1.40)
C['hair_face'] = F.conform(ob['L1_Hair'], S_face, margin=0.002, reach=0.02, max_push=0.008,
                           region=lambda V: (V[:, 2] > 1.40) & (V[:, 1] < -0.03))
rep['conform'] = {k: dict(moved=v[0], worst_depth_m=round(v[1], 4)) for k, v in C.items()}
print('conform', rep['conform'])

# ---------------------------------------------------------------- 3. bones
BR = G.BodyRef()


def body_w(p, allowed):
    w = BR.weights(p, k=8)
    w = {k: v for k, v in w.items() if k in allowed}
    if not w:                                         # nearest allowed bone head
        d = {b: np.linalg.norm(P(b) - p) for b in allowed}; w = {min(d, key=d.get): 1.0}
    s = sum(w.values()); return {k: v / s for k, v in w.items()}


def apply_weights(o, Wlist):
    o.vertex_groups.clear()
    groups = {}
    for i, w in enumerate(Wlist):
        for k, v in w.items(): groups.setdefault(k, ([], []))[0].append(i); groups[k][1].append(v)
    lab.set_weights(o, groups)
    o.parent = A; o.matrix_parent_inverse = A.matrix_world.inverted()
    m = o.modifiers.get('Armature') or o.modifiers.new('Armature', 'ARMATURE'); m.object = A


def rigid(o, bone):
    apply_weights(o, [{bone: 1.0}] * len(o.data.vertices))


def resample_z(pts, n):
    pts = np.asarray(pts); s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
    t = np.linspace(0, s[-1], n); return np.stack([np.interp(t, s, pts[:, k]) for k in range(3)], 1)


CH = {}       # chain name -> dict(names, pts)


def chain(name, pts, parent):
    names = rig.add_chain(name, [tuple(p) for p in pts], parent)
    CH[name] = dict(names=names, pts=np.asarray(pts)); return names


TORSO = ['J_Bip_C_Hips', 'J_Bip_C_Spine', 'J_Bip_C_Chest', 'J_Bip_C_UpperChest', 'J_Bip_C_Neck', 'J_Bip_L_Shoulder',
         'J_Bip_R_Shoulder', 'J_Sec_L_Bust1', 'J_Sec_L_Bust2', 'J_Sec_R_Bust1', 'J_Sec_R_Bust2', 'J_Bip_L_UpperArm', 'J_Bip_R_UpperArm']
TORSO = [b for b in TORSO if b in A.data.bones]

# ---- ears: move the ear bones into the new hair's ears (base -> tip)
hair = ob['L1_Hair']; HV = F.verts(hair)
EAR = {}
lab.mode(A, 'EDIT')
for s, sg in (('L', 1), ('R', -1)):
    e = HV[(HV[:, 2] > 1.655) & (HV[:, 0] * sg > 0.035)]
    tip = e[e[:, 2].argmax()]
    base = e[e[:, 2] < 1.67].mean(0)
    mid = base + (tip - base) * 0.55
    eb0, eb1 = A.data.edit_bones['J_Sec_Ear%s_0' % s], A.data.edit_bones['J_Sec_Ear%s_1' % s]
    inv = A.matrix_world.inverted()
    eb0.head = inv @ Vector(base); eb0.tail = inv @ Vector(mid); eb1.head = inv @ Vector(mid); eb1.tail = inv @ Vector(tip)
    EAR[s] = dict(base=base, tip=tip, mid=mid, axis_r=0.04)
lab.mode(A, 'OBJECT')
rep['ears'] = {k: dict(base=v['base'].round(4).tolist(), tip=v['tip'].round(4).tolist()) for k, v in EAR.items()}

# ---- hair chains: k-means of the hanging hair in plan view, centre lines by height
ZR = 1.43                                                  # chain roots (just under the head bone)
hang = HV[HV[:, 2] < 1.36]
K = 12
rng = np.random.default_rng(3)
cen = hang[rng.choice(len(hang), K, replace=False)][:, :2]
for _ in range(40):
    lab_ = np.argmin(((hang[:, None, :2] - cen[None]) ** 2).sum(-1), 1)
    cen = np.array([hang[lab_ == k, :2].mean(0) if (lab_ == k).any() else cen[k] for k in range(K)])
HAIR_CH = []
for k in range(K):
    pts = hang[lab_ == k]
    if len(pts) < 50: continue
    zmin = np.percentile(pts[:, 2], 1.5)
    zs = np.linspace(ZR, zmin + 0.01, 8)
    path = []
    for z in zs:
        sl = pts[np.abs(pts[:, 2] - z) < 0.03]
        xy = np.median(sl[:, :2], 0) if len(sl) > 5 else (path[-1][:2] if path else np.median(pts[:, :2], 0))
        path.append([xy[0], xy[1], z])
    path = np.array(path)
    # the root sits on the head: pull the first point toward the head axis so the chain starts inside the hair mass
    path[0, :2] = path[1, :2] * 0.8
    ang = math.degrees(math.atan2(path[-1, 0], path[-1, 1] - 0.02))
    nm = ('HairSide%s%d' if abs(ang) > 115 else 'HairBack%s%d') % ('L' if path[-1, 0] > 0 else 'R', k)
    HAIR_CH.append(nm)
    chain(nm, path, 'J_Bip_C_Head')
rep['hair_chains'] = {n: len(CH[n]['names']) for n in HAIR_CH}


def chain_xy_at(c, z):
    p = CH[c]['pts']; zz = p[::-1, 2]
    return np.array([np.interp(z, zz, p[::-1, 0]), np.interp(z, zz, p[::-1, 1])])


HW = []
for p in HV:
    if p[2] > 1.655 and abs(p[0]) > 0.035:                         # ears
        s = 'L' if p[0] > 0 else 'R'; e = EAR[s]
        t = np.clip((p[2] - e['base'][2]) / (e['tip'][2] - e['base'][2]), 0, 1)
        HW.append({'J_Sec_Ear%s_0' % s: 1 - t * 0.6, 'J_Sec_Ear%s_1' % s: t * 0.6} if t > 0.15 else {'J_Bip_C_Head': 1 - t / 0.15, 'J_Sec_Ear%s_0' % s: t / 0.15})
        continue
    if p[2] >= ZR + 0.01:
        HW.append({'J_Bip_C_Head': 1.0}); continue
    d = np.array([np.linalg.norm(chain_xy_at(c, p[2]) - p[:2]) for c in HAIR_CH])
    o_ = np.argsort(d)[:2]; ww = 1 / np.maximum(d[o_], 0.01) ** 2; ww /= ww.sum()
    acc = {}
    for ci, wc in zip(o_, ww):
        c = HAIR_CH[ci]
        cw = rig.chain_weights(p, CH[c]['pts'], CH[c]['names'], {'J_Bip_C_Head': 1.0}, root_blend=0.07)
        for kk, vv in cw.items(): acc[kk] = acc.get(kk, 0) + vv * wc
    top = sorted(acc.items(), key=lambda x: -x[1])[:4]; s_ = sum(v for _, v in top)
    HW.append({kk: vv / s_ for kk, vv in top})
apply_weights(hair, HW)

# ---- underskirt: sector chains around the hips (the v1 skirt's set-up, short)
sk = ob['L1_v2_Under']; SV = F.verts(sk)
HC = np.array([0.0, -0.03])
ZS = float(SV[:, 2].max()) - 0.03
NS = 12
SK_CH = []
ang_v = np.arctan2(SV[:, 0] - HC[0], SV[:, 1] - HC[1])
for k in range(NS):
    a = -math.pi + (k + 0.5) * 2 * math.pi / NS
    da = np.abs((ang_v - a + math.pi) % (2 * math.pi) - math.pi)
    pts = SV[(da < math.pi / NS) & (SV[:, 2] < ZS)]
    if len(pts) < 30: continue
    zmin = np.percentile(pts[:, 2], 2)
    zs = np.linspace(ZS, zmin + 0.015, 4)
    path = []
    for z in zs:
        sl = pts[np.abs(pts[:, 2] - z) < 0.03]
        r = np.median(np.linalg.norm(sl[:, :2] - HC, axis=1)) if len(sl) > 5 else (path[-1][3] if path else 0.15)
        path.append([HC[0] + math.sin(a) * r, HC[1] + math.cos(a) * r, z, r])
    path = np.array(path)[:, :3]
    nm = 'Skirt%02d' % k; SK_CH.append((nm, a)); chain(nm, path, 'J_Bip_C_Hips')
rep['skirt_chains'] = [n for n, _ in SK_CH]


def skirt_w(p):
    if p[2] >= ZS + 0.005: return {'J_Bip_C_Hips': 1.0}
    a = math.atan2(p[0] - HC[0], p[1] - HC[1])
    da = np.array([abs((a - ca + math.pi) % (2 * math.pi) - math.pi) for _, ca in SK_CH])
    o_ = np.argsort(da)[:2]; ww = 1 / np.maximum(da[o_], 0.02) ** 2; ww /= ww.sum()
    acc = {}
    for ci, wc in zip(o_, ww):
        nm = SK_CH[ci][0]
        cw = rig.chain_weights(p, CH[nm]['pts'], CH[nm]['names'], {'J_Bip_C_Hips': 1.0}, root_blend=0.06)
        for kk, vv in cw.items(): acc[kk] = acc.get(kk, 0) + vv * wc
    top = sorted(acc.items(), key=lambda x: -x[1])[:4]; s_ = sum(v for _, v in top)
    return {kk: vv / s_ for kk, vv in top}


apply_weights(sk, [skirt_w(p) for p in SV])

# ---- panels: one chain down the middle of each, from under the sash
PN_CH = []
for o in sorted([x for x in ob if x.name.startswith('L1_v2_Panel_')], key=lambda x: x.name):
    V = F.verts(o); zt, zb = V[:, 2].max(), V[:, 2].min()
    path = []
    for z in np.linspace(zt - 0.015, zb + 0.01, 5):
        sl = V[np.abs(V[:, 2] - z) < 0.02]
        path.append(sl.mean(0))
    nm = o.name.replace('L1_v2_', '').replace('_', ''); PN_CH.append(nm)
    chain(nm, path, 'J_Bip_C_Hips')
    apply_weights(o, [rig.chain_weights(p, CH[nm]['pts'], CH[nm]['names'], {'J_Bip_C_Hips': 1.0}, root_blend=0.04) for p in V])
rep['panel_chains'] = PN_CH

# ---- bodice, sash, collar: the body's own torso weights
bod = ob['L1_v2_Bodice']; apply_weights(bod, [body_w(p, TORSO) for p in F.verts(bod)])
sash = ob['L1_v2_Sash']; apply_weights(sash, [body_w(p, TORSO) for p in F.verts(sash)])
col = ob['L1_v2_Collar']; apply_weights(col, [body_w(p, ['J_Bip_C_Neck', 'J_Bip_C_UpperChest']) for p in F.verts(col)])

# ---- bow: knot with the sash, a chain down each tail; the brooch with the knot
bw = ob['L1_v2_Bow']; WV = F.verts(bw)
knot = np.array(PLACE['bow']['knot'])
KW = body_w(knot, TORSO); KB = max(KW, key=KW.get)
zk = knot[2] - 0.012
for s, sg in (('L', 1), ('R', -1)):
    tl = WV[(WV[:, 2] < zk) & (WV[:, 0] * sg > 0)]
    top = tl[tl[:, 2] > zk - 0.012].mean(0); bot = tl[tl[:, 2].argmin()]
    chain('BowTail' + s, resample_z([top + [0, 0, 0.012], bot], 4), KB)
BWW = []
for p in WV:
    if p[2] >= zk: BWW.append(KW); continue
    nm = 'BowTail' + ('L' if p[0] > 0 else 'R')
    BWW.append(rig.chain_weights(p, CH[nm]['pts'], CH[nm]['names'], KW, root_blend=0.015))
apply_weights(bw, BWW)
apply_weights(ob['L1_v2_Brooch'], [KW] * len(ob['L1_v2_Brooch'].data.vertices))
rep['bow_parent'] = KB

def smooth_weights(V, W, radius):
    """each vertex takes the mean weights of everything within radius: layers of one garment a few mm apart (shell and
    lining) end up with the same weights and keep their gap through every bend"""
    kd = KDTree(len(V))
    for i, p in enumerate(V): kd.insert(Vector(p), i)
    kd.balance()
    out = []
    for p in V:
        acc = {}
        nb = kd.find_range(Vector(p), radius)
        for _c, j, _d in nb:
            for k, v in W[j].items(): acc[k] = acc.get(k, 0) + v / len(nb)
        top = sorted(acc.items(), key=lambda x: -x[1])[:4]; s_ = sum(v for _, v in top)
        out.append({k: v / s_ for k, v in top})
    return out


# ---- sleeves: tube = arm skin weights, drape = hanging chains in the bell (o12's set-up)
SL_CH = {}
for s, sg in (('L', 1), ('R', -1)):
    o = ob['L1_v2_Sleeve_' + s]; V = F.verts(o)
    a0, a1 = P('J_Bip_%s_UpperArm' % s), P('J_Bip_%s_Hand' % s)
    ax = (a1 - a0) / np.linalg.norm(a1 - a0); L = np.linalg.norm(a1 - a0)
    rel = V - a0; t = (rel @ ax) / L; radial = rel - np.outer(rel @ ax, ax)
    rr = np.linalg.norm(radial, axis=1)
    fdir = radial[rr > 0.06].mean(0); fdir -= (fdir @ ax) * ax; fdir /= np.linalg.norm(fdir)
    drop = radial @ fdir
    rep.setdefault('sleeve_flap_dir', {})[s] = fdir.round(3).tolist()
    names = []
    for j, tc in enumerate((0.6, 0.72, 0.84, 0.95)):                    # the bell hangs from the forearm
        m = np.abs(t - tc) < 0.09
        if m.sum() < 5: continue
        far = V[m][np.argmax(drop[m])]
        top = a0 + ax * L * tc + fdir * 0.035
        bot = far - fdir * 0.01
        if np.linalg.norm(bot - top) < 0.02: continue
        pts = resample_z([top, bot], 4)
        nm = 'Sleeve%s%d' % (s, j); names.append((nm, tc))
        chain(nm, pts, 'J_Bip_%s_LowerArm' % s)
    SL_CH[s] = names
    arm_b = ['J_Bip_%s_UpperArm' % s, 'J_Bip_%s_LowerArm' % s, 'J_Bip_%s_Shoulder' % s, 'J_Bip_%s_Hand' % s]
    # tube (arm weights) to bell (drape chains) by a smooth ramp on how far the point hangs off the arm, so the white
    # shell and the navy lining a few mm apart get the same weights and never cross (a hard switch let them)
    ramp = np.clip((drop - 0.03) / 0.04, 0, 1); ramp = ramp * ramp * (3 - 2 * ramp)
    # the tube: upper arm to forearm over a wide window round the elbow (the body's own weights switch within a few cm
    # there, and a wide bell folding on that line crossed its own lining)
    te = np.linalg.norm(P('J_Bip_%s_LowerArm' % s) - a0) / L
    we = np.clip((t - (te - 0.12)) / 0.24, 0, 1); we = we * we * (3 - 2 * we)
    W = []
    for i, p in enumerate(V):
        base = {'J_Bip_%s_UpperArm' % s: 1 - we[i], 'J_Bip_%s_LowerArm' % s: we[i]}
        base = {k: v for k, v in base.items() if v > 1e-4}
        if ramp[i] <= 0 or not names:
            W.append(base); continue
        dt = np.array([abs(t[i] - tc) for _, tc in names]); o_ = np.argsort(dt)[:2]
        ww = 1 / np.maximum(dt[o_], 0.03) ** 2; ww /= ww.sum(); acc = {k: v * (1 - ramp[i]) for k, v in base.items()}
        for ci, wc in zip(o_, ww):
            nm = names[ci][0]
            cw = rig.chain_weights(p, CH[nm]['pts'], CH[nm]['names'], base, root_blend=0.05)
            for kk, vv in cw.items(): acc[kk] = acc.get(kk, 0) + vv * wc * ramp[i]
        top = sorted(acc.items(), key=lambda x: -x[1])[:4]; s_ = sum(v for _, v in top)
        W.append({kk: vv / s_ for kk, vv in top})
    # neighbours along the arm and around it, at any distance out from it: the white shell and the navy lining of the
    # thick bell (up to a few cm apart at the rim) share one set of weights
    phi = np.arctan2(radial @ np.cross(ax, fdir), radial @ fdir)
    apply_weights(o, smooth_weights(np.c_[t * L, phi * 0.06, np.zeros(len(V))], W, 0.008))

# ---- stars: the weights of the cloth vertex under each star's centre
hosts = [x for x in ob if x.name.startswith(('L1_v2_Panel_', 'L1_v2_Sleeve_'))]
kd = KDTree(sum(len(h.data.vertices) for h in hosts)); ref = []
for h in hosts:
    for v in h.data.vertices:
        kd.insert(h.matrix_world @ v.co, len(ref)); ref.append((h, v.index))
kd.balance()
for o in [x for x in ob if x.name.startswith('L1_v2_Star_')]:
    c = F.verts(o).mean(0)
    _co, j, _d = kd.find(Vector(c)); h, vi = ref[j]
    w = {h.vertex_groups[g.group].name: g.weight for g in h.data.vertices[vi].groups if g.weight > 0}
    apply_weights(o, [w] * len(o.data.vertices))

# ---- back bow: knot on the head, two ribbon tails swing
bow = ob['L1_BackBow']; WV = F.verts(bow)
zk = WV[:, 2].max() - 0.075
for s, sg in (('L', 1), ('R', -1)):
    tl = WV[(WV[:, 2] < zk) & (WV[:, 0] * sg > 0)]
    top = tl[tl[:, 2] > zk - 0.01].mean(0); bot = tl[tl[:, 2].argmin()]
    chain('HairRibbon' + s, resample_z([top + [0, 0, 0.012], bot], 4), 'J_Bip_C_Head')
BWW = []
for p in WV:
    if p[2] >= zk: BWW.append({'J_Bip_C_Head': 1.0}); continue
    nm = 'HairRibbon' + ('L' if p[0] > 0 else 'R')
    BWW.append(rig.chain_weights(p, CH[nm]['pts'], CH[nm]['names'], {'J_Bip_C_Head': 1.0}, root_blend=0.02))
apply_weights(bow, BWW)

# ---- rigid accessories + shoes (shoes take the foot / toe weights so a toe bend stays inside)
rigid(ob['L1_HairFlower'], 'J_Bip_C_Head')
for s in 'LR':
    rigid(ob['L1_Bracelet_' + s], 'J_Bip_%s_LowerArm' % s)
    o = ob['L1_Shoe_' + s]
    apply_weights(o, [body_w(p, ['J_Bip_%s_Foot' % s, 'J_Bip_%s_ToeBase' % s]) for p in F.verts(o)])

# ---------------------------------------------------------------- 4. colliders + springs
bpy.context.view_layer.update()
hd = P('J_Bip_C_Head')
COLL = [
    ('Head', 'J_Bip_C_Head', (0, 0.012, 1.525), None, 0.092),
    ('Neck', 'J_Bip_C_Neck', tuple(P('J_Bip_C_Neck')), tuple(T('J_Bip_C_Neck')), 0.045),
    ('Chest', 'J_Bip_C_UpperChest', (-0.045, -0.02, 1.245), (0.045, -0.02, 1.245), 0.075),
    ('BustL', 'J_Bip_C_Chest', (0.05, -0.07, 1.215), None, 0.052),
    ('BustR', 'J_Bip_C_Chest', (-0.05, -0.07, 1.215), None, 0.052),
    ('Spine', 'J_Bip_C_Spine', (0, -0.035, 1.05), (0, -0.03, 1.17), 0.078),
    ('Hips', 'J_Bip_C_Hips', (-0.07, -0.005, 0.90), (0.07, -0.005, 0.90), 0.085),
]
for s in 'LR':
    COLL += [('UpperArm' + s, 'J_Bip_%s_UpperArm' % s, tuple(P('J_Bip_%s_UpperArm' % s)), tuple(T('J_Bip_%s_UpperArm' % s)), 0.042),
             ('LowerArm' + s, 'J_Bip_%s_LowerArm' % s, tuple(P('J_Bip_%s_LowerArm' % s)), tuple(T('J_Bip_%s_LowerArm' % s)), 0.034),
             ('UpperLeg' + s, 'J_Bip_%s_UpperLeg' % s, tuple(P('J_Bip_%s_UpperLeg' % s)), tuple(T('J_Bip_%s_UpperLeg' % s)), 0.075),
             ('LowerLeg' + s, 'J_Bip_%s_LowerLeg' % s, tuple(P('J_Bip_%s_LowerLeg' % s)), tuple(T('J_Bip_%s_LowerLeg' % s)), 0.052)]
COLL = colliders.hand_capsules(A, COLL)
for s in 'LR':                    # fuller hand + wrist capsules used only by the skirt: the frills give way around her hands
    hb, mb = P('J_Bip_%s_Hand' % s), P('J_Bip_%s_Middle1' % s)
    COLL.append(('HandSkirt' + s, 'J_Bip_%s_Hand' % s, tuple(hb - (mb - hb) * 0.6), tuple(mb + (mb - hb) * 0.8), 0.055))
GROUPS = {'head': ['Head', 'Neck'],
          'torso': ['Neck', 'Chest', 'BustL', 'BustR', 'Spine', 'Hips'],
          'arms': ['UpperArmL', 'UpperArmR', 'LowerArmL', 'LowerArmR', 'HandL', 'HandR'],
          'legs': ['Hips', 'UpperLegL', 'UpperLegR', 'LowerLegL', 'LowerLegR'],
          'hands_skirt': ['HandSkirtL', 'HandSkirtR', 'LowerArmL', 'LowerArmR']}
target, gmap = colliders.build(A, COLL, GROUPS)


def clear_joints(chain_names, hit, groups):
    """skirt and panel joints that start inside the hip or thigh colliders slide straight out from the skirt axis
    until they clear them (else the springs kick the cloth outward on the first frame)"""
    lab.mode(A, 'EDIT'); eb = A.data.edit_bones; inv = A.matrix_world.inverted(); moved = 0
    for cn in chain_names:
        names = CH[cn]['names']
        for k, bn in enumerate(names[1:], 1):
            b = eb[bn]; p = np.array(A.matrix_world @ b.head); h = hit[min(k, len(hit) - 1)] if isinstance(hit, list) else hit
            for _ in range(20):
                worst = 0.0
                for g in groups:
                    for m_ in GROUPS[g]:
                        _ci, c, t, r = target[m_]
                        d = (Vector(p) - c).length if t is None else colliders.seg_dist(Vector(p), c, t)
                        worst = max(worst, r + h - d)
                if worst <= 0.001: break
                rad = p[:2] - HC; rad = rad / max(np.linalg.norm(rad), 1e-6); p[:2] += rad * (worst + 0.002)
            if np.linalg.norm(np.array(A.matrix_world @ b.head) - p) > 1e-5:
                b.head = inv @ Vector(p)
                if b.parent and b.use_connect: b.parent.tail = b.head
                moved += 1
    lab.mode(A, 'OBJECT')
    return moved


rep['joints_cleared'] = clear_joints([n for n, _ in SK_CH], [0.015, 0.025, 0.035], ['legs']) + \
    clear_joints(PN_CH, [0.012, 0.02, 0.03, 0.04], ['legs'])
SPR = {}
for n in HAIR_CH:
    SPR[n] = (0.55, 0.38, 0.35, 0.02, ['torso', 'arms', 'legs'])
for n, _ in SK_CH:
    SPR[n] = (1.0, 0.7, 0.22, [0.015, 0.025, 0.035], ['legs', 'hands_skirt'])
for n in PN_CH:
    SPR[n] = (0.8, 0.6, 0.3, [0.012, 0.02, 0.03, 0.04], ['legs', 'hands_skirt'])
for s in 'LR':
    for n, _ in SL_CH[s]: SPR[n] = (0.25, 0.4, 0.8, 0.03, ['torso', 'legs'])
    SPR['HairRibbon' + s] = (0.55, 0.4, 0.4, 0.015, ['head', 'torso'])
    SPR['BowTail' + s] = (0.55, 0.4, 0.4, 0.012, ['legs', 'hands_skirt'])

spring_groups = {}
for n, (st, dr, gr, hr, gs) in SPR.items():
    colliders.add_spring(A, n, CH[n]['names'], st, dr, gr, hr, gs, gmap); spring_groups[n] = gs
# the kept ear springs: no colliders (as before)
pen = colliders.penetration_report(A, target, GROUPS, spring_groups)
rep['rest_penetrations_gt2mm'] = len(pen)
rep['rest_penetrations'] = pen
rep['springs'] = {n: len(CH[n]['names']) for n in SPR}
print('springs', len(SPR), 'rest penetrations', len(pen))

# ---------------------------------------------------------------- 5. MToon materials (the face's toon settings, generated textures as base colour)
fm = bpy.data.materials['Celestial_Face_00_SKIN'].vrm_addon_extension.mtoon1.extensions.vrmc_materials_mtoon
TOONY, SHIFT, GI = fm.shading_toony_factor, fm.shading_shift_factor, fm.gi_equalization_factor
DOUBLE = ('L1_Hair', 'L1_BackBow')                      # plus every v2 part (two sided cloth)
SHADE = {'L1_Hair': (0.70, 0.70, 0.88)}
done = {}
for o in [x for x in bpy.data.collections['L1_Outfit'].objects]:
    src = o.data.materials[0]
    img = next(n.image for n in src.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image and
               any(l.to_socket.name == 'Base Color' for l in n.outputs[0].links))
    dbl = o.name in DOUBLE or o.name.startswith('L1_v2_')
    base = o.name.replace('_L', '').replace('_R', '') if o.name.endswith(('_L', '_R')) else o.name
    base = base.rstrip('0123456789').rstrip('_') if base.startswith(('L1_v2_Panel', 'L1_v2_Star')) else base
    key = (base, dbl)
    if key not in done:
        if not img.name.endswith('_BaseColor'): img.name = base + '_BaseColor'
        m = lab.mtoon(base + '_MToon', base='#FFFFFF', shade=SHADE.get(base, (0.78, 0.76, 0.88)), tex=img,
                      double=dbl, toony=TOONY, shift=SHIFT, gi=GI, outline=0.0 if dbl else fm.outline_width_factor,
                      outline_col='#2A2440', rim='#1A1430', rim_power=4.0, rim_mix=0.6)
        done[key] = m
    o.data.materials.clear(); o.data.materials.append(done[key])
    for p_ in o.data.polygons: p_.use_smooth = True
rep['materials'] = sorted(m.name for m in done.values())
for m in list(bpy.data.materials):
    if m.users == 0: bpy.data.materials.remove(m)

# ---------------------------------------------------------------- 5b. hide the body skin the outfit covers in every tested pose
HIDE = OUTD + '/hide_faces.json'
if os.path.exists(HIDE) and '--no-hide' not in ARGS:
    import bmesh
    hf = set(json.load(open(HIDE))['faces'])
    bm = bmesh.new(); bm.from_mesh(body.data); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index in hf], context='FACES_ONLY')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(body.data); bm.free(); body.data.update()
    rep['body_faces_hidden'] = len(hf)
    print('body: hid %d covered faces' % len(hf))

# ---------------------------------------------------------------- 6. meta + export
meta = A.data.vrm_addon_extension.vrm1.meta
meta.vrm_name = 'Mika Celestial (L1 outfit v2)'
tris = {}
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.data.calc_loop_triangles(); tris[o.name] = len(o.data.loop_triangles)
rep['tris'] = tris; rep['tris_total'] = sum(tris.values())
json.dump(rep, open(OUTD + '/rig.json', 'w'), indent=1, default=float)
bpy.ops.wm.save_as_mainfile(filepath=OUTD + '/%s.blend' % OUT)
if '--no-export' not in ARGS:
    os.makedirs(OUTD + '/export', exist_ok=True)
    with lab.ctx(A):
        r = bpy.ops.export_scene.vrm(filepath=OUTD + '/export/%s.vrm' % OUT, armature_object_name=A.name)
    print('vrm export', r)
print('RIG DONE tris', rep['tris_total'])
