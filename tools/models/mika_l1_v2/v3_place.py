"""Mika L1 outfit v2 rework (Selwyn 2026-10-20, Mika_Trim_Kit_v1), stage 1: build and place the outfit on Mika (rest
T-pose). Like v2_place.py it starts from l1_outfit/blend/o10_placed.blend (her hair, shoes, bracelets and hair flower as
they ship). The Meshy parts stay only for the bodice, the front bow and the brooch (baked, placed as v2); everything
else is clean geometry built here, like the rebuilt panel:
  sash, collar     closed bands wrapped on the surface under them, trim_sheet band 2 (star row) all round
  underskirt       flared, softly pleated: navy waistband, white with panel_pattern_tile, filigree hem (band 1)
  panels           6 long panels to mid calf round the waist, a gap at the front, overlapping a little: white front
                   with the pattern, flat navy back, filigree strips on both long edges and the slanted bottom, front
                   and back; a filigree corner decal on each tip
  sleeves          long, flowing, hanging from the upper arm: a fitted top that opens into a hanging drape, white
                   outside with the pattern, navy lining 0.4 mm inside on the same grid (same weights, so the two can
                   never cross; each is one sided), filigree on the outer hem, cloud embroidery (band 4) on the inner hem, an
                   engraved gold cuff at the top, a star decal near the hem
  back bow         replaces the Meshy back bow: knot, two loops and two long tails of band 4 ribbon on her hair
  bodice           engraved gold band (band 3) strips along its gold trims (v3_engrave.py centre lines)
  decals           opaque meshes cut to each ornament's outline (decals.json), laid on the cloth
Materials: L1_v2_Trim (trim sheet; its flat navy and gold spots colour plain navy and gold faces), L1_v2_Pattern,
L1_v2_Decal, L1_v2_Bodice, L1_v2_Bow, L1_v2_Brooch.
  blender -b -t 2 --python l1_v2/tools/v3_place.py
Output: l1_v2/fit3/v3_placed.blend, l1_v2/fit3/placement.json"""
import bpy, bmesh, os, sys, json, math
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.geometry import tessellate_polygon
LAB = '/home/selwyn/Downloads/Mika-Transformation-Lab'
sys.path.insert(0, LAB + '/tools/lib')
import outfit_fit as F

V2 = LAB + '/l1_v2'
TEX = V2 + '/tex3'
OUT = V2 + '/fit3'
os.makedirs(OUT, exist_ok=True)
SPEC = json.load(open(V2 + '/tools/v3_spec.json'))
BANDS = json.load(open(TEX + '/trim_bands.json'))
DEC = json.load(open(TEX + '/decals.json'))
TILE = SPEC['pattern_tile_m']

bpy.ops.wm.open_mainfile(filepath=LAB + '/l1_outfit/blend/o10_placed.blend')
A = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
bone = lambda n: np.array(A.matrix_world @ A.data.bones[n].head_local)
GONE = ['L1_Bodice', 'L1_Collar', 'L1_Skirt', 'L1_Sleeve_L', 'L1_Sleeve_R', 'L1_WaistBrooch', 'L1_StarPendant_L',
        'L1_StarPendant_R', 'L1_OrbPendant_L', 'L1_OrbPendant_R', 'L1_BackBow']
for n in GONE:
    bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
coll = bpy.data.collections['L1_Outfit']
body = bpy.data.objects['Body']; hair = bpy.data.objects['L1_Hair']
BV = F.verts(body)
S_body = F.Surface([body])
rep = {'removed_v1': GONE}


# ---------------------------------------------------------------- materials
def image_mat(name, path, interp='Linear'):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in [n for n in nt.nodes if n.type == 'TEX_IMAGE']: nt.nodes.remove(n)
    img = bpy.data.images.load(path, check_existing=True); img.name = name + '_img'; img.pack()
    tn = nt.nodes.new('ShaderNodeTexImage'); tn.image = img; tn.interpolation = interp
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Metallic'].default_value = 0.0; bsdf.inputs['Roughness'].default_value = 1.0
    nt.links.new(tn.outputs['Color'], bsdf.inputs['Base Color'])
    nt.nodes.active = tn
    m.use_backface_culling = False
    return m


M_TRIM = image_mat('L1_v2_Trim', TEX + '/trim.png')
M_PAT = image_mat('L1_v2_Pattern', TEX + '/pattern.png')
M_DEC = image_mat('L1_v2_Decal', TEX + '/decals.png')
# single sided layers of the two layer parts (sleeves, panels): the outside only faces out, the lining only faces in,
# so even where a hard bend makes them cross, the wrong layer is never seen from that side
M_PATOUT = image_mat('L1_v2_PatternOut', TEX + '/pattern.png')
M_TRIMOUT = image_mat('L1_v2_TrimOut', TEX + '/trim.png')
M_LINING = image_mat('L1_v2_Lining', TEX + '/trim.png')
LAYERED = [M_TRIM, M_PAT, M_PATOUT, M_TRIMOUT, M_LINING]


def orient(ob, outward_fn):
    """single sided faces: material 2, 3 (outside) face away from the part's axis, 4 (lining) toward it"""
    bm = bmesh.new(); bm.from_mesh(ob.data)
    flip = []
    for f in bm.faces:
        if f.material_index < 2: continue
        c = np.array(f.calc_center_median()); r = outward_fn(c)
        want = 1 if f.material_index in (2, 3) else -1
        if np.dot(np.array(f.normal), r) * want < 0: flip.append(f)
    bmesh.ops.reverse_faces(bm, faces=flip, flip_multires=False)
    bm.to_mesh(ob.data); bm.free(); ob.data.update()
    return len(flip)
NAVY_UV = BANDS['navy']; GOLD_UV = BANDS['gold']


class Builder:
    """faces with per corner uvs and a material per face, then one object"""
    def __init__(self):
        self.V = []; self.F = []; self.UV = []; self.M = []

    def vert(self, p):
        self.V.append(tuple(p)); return len(self.V) - 1

    def face(self, idx, uvs, mat):
        self.F.append(tuple(idx)); self.UV.append([tuple(u) for u in uvs]); self.M.append(mat)

    def grid(self, P, U, mat, flip=False, closed_u=False):
        """P: (rows, cols, 3) positions, U: (rows, cols, 2) uvs; quads as two triangles"""
        r, c = P.shape[:2]
        ids = np.array([[self.vert(P[i, j]) for j in range(c)] for i in range(r)])
        cols = c if closed_u else c - 1
        for i in range(r - 1):
            for j in range(cols):
                j1 = (j + 1) % c
                a, b, cc, d = ids[i, j], ids[i, j1], ids[i + 1, j1], ids[i + 1, j]
                ua, ub, uc, ud = U[i, j], U[i, j1], U[i + 1, j1], U[i + 1, j]
                if closed_u and j1 == 0:                                 # the seam keeps counting along u
                    ub = U[i, j] + (U[i, j] - U[i, j - 1]); uc = U[i + 1, j] + (U[i + 1, j] - U[i + 1, j - 1])
                t1, t2 = ((a, b, cc), (a, cc, d)), ((ua, ub, uc), (ua, uc, ud))
                if flip:
                    t1 = ((a, cc, b), (a, d, cc)); t2 = ((ua, uc, ub), (ua, ud, uc))
                for f, u in zip(t1, t2): self.face(f, u, mat)
        return ids

    def build(self, name, mats):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.V, [], self.F)
        uvl = me.uv_layers.new(name='UVMap')
        flat = [u for f in self.UV for u in f]
        uvl.data.foreach_set('uv', np.array(flat, np.float64).ravel())
        for m in mats: me.materials.append(m)
        me.polygons.foreach_set('material_index', np.array(self.M, np.int32))
        ob = bpy.data.objects.new(name, me); coll.objects.link(ob)
        for p in me.polygons: p.use_smooth = True
        me.set_sharp_from_angle(angle=math.radians(60))
        return ob


def band_v(name, frac):
    """v inside a trim band: frac 0 = band bottom row, 1 = top row"""
    b = BANDS['bands'][name]
    return b['v0'] + (b['v1'] - b['v0']) * frac


def strip_uv(arclen, width, name, frac_lo=0.0, frac_hi=1.0, closed_total=None):
    """u along a strip: one band image width per (strip width x band aspect); a closed strip gets a whole number"""
    rep = width * BANDS['bands'][name]['aspect'] * (frac_hi - frac_lo)
    if closed_total is not None:
        rep = closed_total / max(1, round(closed_total / rep))
    return arclen / rep


def bvh_of(objs):
    vs, ps = [], []
    for ob in objs:
        me = ob.data; mw = ob.matrix_world; base = len(vs)
        vs += [mw @ v.co for v in me.vertices]
        ps += [[base + i for i in p.vertices] for p in me.polygons]
    return BVHTree.FromPolygons(vs, ps)


def outer_radius(bvh, centre_xy, z, theta, r0=0.7):
    d = np.array([math.sin(theta), -math.cos(theta), 0.0])             # theta 0 = front (-Y), + toward her left (+X)
    o = np.array([centre_xy[0], centre_xy[1], z]) + d * r0
    loc, _n, _i, dist = bvh.ray_cast(Vector(o), Vector(-d), r0)
    return None if loc is None else r0 - dist


def body_slice(z, xmax=0.16, h=0.006):
    s = BV[(np.abs(BV[:, 2] - z) < h) & (np.abs(BV[:, 0]) < xmax)]
    return s.min(0), s.max(0)


def smooth_circ(a, k=3, it=3):
    for _ in range(it):
        a = sum(np.roll(a, i, axis=-1) for i in range(-k, k + 1)) / (2 * k + 1)
    return a


def load(path, name, matname):
    o = F.import_glb(path, name)
    for c in list(o.users_collection): c.objects.unlink(o)
    coll.objects.link(o)
    for m in o.data.materials: m.name = matname
    return o


FINAL = V2 + '/final/MIKA_L1_%s.glb'

# ---------------------------------------------------------------- bodice (v2 placement) + engraved strips on its trims
b = SPEC['bodice']
bod = load(FINAL % 'bodice_core', 'L1_v2_Bodice', 'L1_v2_Bodice')
BD = F.verts(bod)
# strips first, in the part's own space, so they take the same scale and fit as the bodice
tp = json.load(open(V2 + '/bake/bodice_trim_paths.json'))
bvh0 = bvh_of([bod])
bs = Builder()
for path in tp['paths']:
    P = np.array(path['pts']); n = len(P)
    hw = path['half_width'] * b['strip_width_mul']
    N_ = []; Q = []
    for p in P:
        loc, nrm, _i, _d = bvh0.find_nearest(Vector(p))
        Q.append(np.array(loc)); N_.append(np.array(nrm))
    Q = np.array(Q); N_ = np.array(N_)
    T = np.gradient(Q, axis=0); T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
    X = np.cross(T, N_); X /= np.maximum(np.linalg.norm(X, axis=1, keepdims=True), 1e-9)
    lift = b['strip_lift_mm'] * tp['mm']
    ac = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(Q, axis=0), axis=1))])
    u = strip_uv(ac, 2 * hw, 'engraved')
    G = np.stack([Q - X * hw + N_ * lift, Q + X * hw + N_ * lift], 0)
    U = np.stack([np.c_[u, np.full(n, band_v('engraved', 0))], np.c_[u, np.full(n, band_v('engraved', 1))]], 0)
    bs.grid(G, U, 0)
strips = bs.build('bodice_strips', [M_TRIM])
# join into the bodice so the placement below treats them as one
bpy.ops.object.select_all(action='DESELECT')
strips.select_set(True); bod.select_set(True); bpy.context.view_layer.objects.active = bod
bpy.ops.object.join()
BD = F.verts(bod)
core = np.array([bod.data.materials[p.material_index].name.startswith('L1_v2_Bodice') for p in bod.data.polygons])
cv = np.zeros(len(BD), bool)
for p in bod.data.polygons:
    if core[p.index]: cv[list(p.vertices)] = True
zt_m, zb_m = BD[cv, 2].max(), BD[cv, 2].min()
sz = (b['top_z'] - b['bottom_z']) / (zt_m - zb_m)
bz_m = zb_m + (b['bust_z'] - b['bottom_z']) / sz
sl = BD[cv][np.abs(BD[cv, 2] - bz_m) < 0.03]
blo, bhi = body_slice(b['bust_z'])
sx = (bhi[0] + b['gap']) / max(sl[:, 0].max(), -sl[:, 0].min())
sy = ((bhi[1] - blo[1]) / 2 + b['gap']) / ((sl[:, 1].max() - sl[:, 1].min()) / 2)
cym = (sl[:, 1].max() + sl[:, 1].min()) / 2
W = np.c_[BD[:, 0] * sx, (BD[:, 1] - cym) * sy + (blo[1] + bhi[1]) / 2, b['bottom_z'] + (BD[:, 2] - zb_m) * sz]
F.set_verts(bod, W)
rep['bodice'] = dict(sx=sx, sy=sy, sz=sz, trim_strips=len(tp['paths']))

# ---------------------------------------------------------------- underskirt: flared, softly pleated
u_ = SPEC['under']
NS, NR = u_['segments'], u_['rows']
lo, hi = body_slice(u_['top_z'])
uc = np.array([0.0, (lo[1] + hi[1]) / 2])
env_b = bvh_of([body])
TH = np.linspace(-math.pi, math.pi, NS, endpoint=False)
zs = np.linspace(u_['top_z'], u_['hem_z'], NR)
R = np.array([[outer_radius(env_b, uc, z, t) or 0.0 for t in TH] for z in zs])
R[R == 0] = R[R > 0].mean()
R = np.maximum.accumulate(R, axis=0) + u_['gap']                          # hangs: never narrower than above
R = smooth_circ(R)
fl = np.clip((u_['flare_from_z'] - zs) / (u_['flare_from_z'] - u_['hem_z']), 0, 1)
R = R + (fl ** 1.2)[:, None] * u_['flare']
tri = 1 - np.abs(((TH[None, :] * u_['pleats'] / (2 * math.pi)) % 1) * 2 - 1)   # triangle wave, the pleat folds
R = R + (fl ** 1.5)[:, None] * u_['pleat_depth'] * (tri - 0.5)
P = np.stack([uc[0] + np.sin(TH)[None] * R, np.broadcast_to(uc[1], R.shape) - np.cos(TH)[None] * R,
              np.broadcast_to(zs[:, None], R.shape)], -1)
# arc lengths: around (per row) and down (per column)
dn = np.concatenate([np.zeros((1, NS)), np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=2), axis=0)], 0)
ar = np.concatenate([np.zeros((NR, 1)), np.cumsum(np.linalg.norm(np.diff(P, axis=1), axis=2), axis=1)], 1)
ub = Builder()
wb = u_['waistband']; hm = u_['hem']
zband = zs[0] - wb; zhem = zs[-1] + hm
# rows: waistband (navy), pattern body, hem strip (filigree); split rows at the two borders
cut_top = np.searchsorted(-zs, -zband); cut_hem = np.searchsorted(-zs, -zhem)
def rows_between(i0, i1): return slice(i0, i1 + 1)
Pw = P[rows_between(0, cut_top)]; Uw = np.broadcast_to(np.array(NAVY_UV), Pw.shape[:2] + (2,)).copy()
ub.grid(Pw, Uw, 0, closed_u=True)
Pp = P[rows_between(cut_top, cut_hem)]
Up = np.stack([ar[rows_between(cut_top, cut_hem)] / TILE, -dn[rows_between(cut_top, cut_hem)] / TILE], -1)
ub.grid(Pp, Up, 1, closed_u=True)
# hem: its own strip over the bottom rows, lifted a little, filigree band, navy at the bottom edge
Ph = P[rows_between(cut_hem, NR - 1)].copy()
nrm = np.stack([np.sin(TH), -np.cos(TH), np.zeros(NS)], -1)
Ph = Ph + nrm[None] * u_['hem_lift']
circ = ar[-1, -1] + np.linalg.norm(P[-1, 0] - P[-1, -1])
uu = strip_uv(ar[rows_between(cut_hem, NR - 1)], hm, 'filigree', closed_total=circ)
hh = (Ph[:, :, 2] - Ph[-1:, :, 2]) / max(Ph[0, 0, 2] - Ph[-1, 0, 2], 1e-6)
Uh = np.stack([uu, band_v('filigree', 0) + hh * (band_v('filigree', 1) - band_v('filigree', 0))], -1)
ub.grid(Ph, Uh, 0, closed_u=True)
und = ub.build('L1_v2_Under', [M_TRIM, M_PAT])
rep['under'] = dict(top_z=u_['top_z'], hem_z=u_['hem_z'], tris=len(und.data.polygons))
rep['conform_bodice'] = F.conform(bod, F.Surface([body, und]), margin=b['margin'], reach=0.03)


# ---------------------------------------------------------------- sash and collar: closed star bands
def ring_band(name, z, height, gap, under_objs, centre, rows=9, segs=128, band='stars'):
    env = bvh_of(under_objs)
    TH = np.linspace(-math.pi, math.pi, segs, endpoint=False)
    zs = np.linspace(z + height / 2, z - height / 2, rows)
    Rr = np.array([[outer_radius(env, centre, zz, t) or 0.0 for t in TH] for zz in zs])
    Rr[Rr == 0] = Rr[Rr > 0].mean()
    Rr = smooth_circ(Rr) + gap
    Rr = np.maximum(Rr, Rr.max(0, keepdims=True) - 0.004)              # a band, not a corset: near vertical
    Pq = np.stack([centre[0] + np.sin(TH)[None] * Rr, centre[1] - np.cos(TH)[None] * Rr,
                   np.broadcast_to(zs[:, None], Rr.shape)], -1)
    arc = np.concatenate([np.zeros((rows, 1)), np.cumsum(np.linalg.norm(np.diff(Pq, axis=1), axis=2), axis=1)], 1)
    circ = arc[rows // 2, -1] + np.linalg.norm(Pq[rows // 2, 0] - Pq[rows // 2, -1])
    uq = strip_uv(arc, height, band, closed_total=circ)
    vq = band_v(band, 0) + ((zs - zs[-1]) / height)[:, None] * (band_v(band, 1) - band_v(band, 0))
    bb = Builder()
    bb.grid(Pq, np.stack([uq, np.broadcast_to(vq, uq.shape)], -1), 0, closed_u=True)
    return bb.build(name, [M_TRIM]), Pq


# ---------------------------------------------------------------- panels: 6 round the waist, gap at the front
pp = SPEC['panel']
env = bvh_of([body, bod, und])
gap = math.radians(pp['front_gap_deg'])
span = (2 * math.pi - 2 * gap) / 6
zz = np.linspace(pp['top_z'] + 0.005, pp['top_z'] - 0.9, 120)
PANELS = []
for k in range(6):
    th0 = gap + (k + 0.5) * span                                         # her left first, round the back
    th0 = th0 if th0 <= math.pi else th0 - 2 * math.pi
    side = 1 if th0 > 0 else -1
    half = (span + math.radians(pp['overlap_deg'])) / 2
    layer = pp['gap'] + (pp['layer_step'] if k % 2 else 0.0)            # neighbours overlap, odd ones on top
    thw = np.linspace(th0 - half - 0.1, th0 + half + 0.1, 25)
    Rz = np.array([max([outer_radius(env, (0.0, pp['cy']), z, t) or 0 for t in thw]) for z in zz])
    Rz = np.maximum.accumulate(Rz) + layer
    arc = np.concatenate([[0], np.cumsum(np.hypot(np.diff(Rz), np.diff(zz)))])
    C, Rw = pp['cols'], pp['rows']
    L_in, L_out = pp['length_inner'], pp['length_outer']                 # slanted bottom: the tip on the back side
    cu = np.linspace(-1, 1, C + 1)                                       # across, -1 = front edge, +1 = back edge
    Lu = L_in + (L_out - L_in) * (cu + 1) / 2
    sv = np.linspace(0, 1, Rw + 1)
    Sg = sv[:, None] * Lu[None, :]                                       # arc length down
    Zg = np.interp(Sg, arc, zz); Rg = np.interp(Sg, arc, Rz)
    # front edge toward the front gap: for her left panels the front edge is at smaller theta
    sgn = 1 if th0 > 0 else -1
    THg = np.broadcast_to(th0 + sgn * cu[None, :] * half, Sg.shape).copy()
    def pos(Rr, TT, ZZ): return np.stack([np.sin(TT) * Rr, pp['cy'] - np.cos(TT) * Rr, ZZ], -1)
    Pf = pos(Rg, THg, Zg)
    t_ = pp['thick']
    Pb = pos(Rg - t_, THg, Zg)
    across = cu[None, :] * half * Rg                                     # metres across, for the pattern
    Uf = np.stack([across / TILE + k * 0.37, -Sg / TILE], -1)
    pb = Builder()
    flip = sgn < 0
    pb.grid(Pf, Uf, 2, flip=flip)                                        # white pattern front (outward)
    pb.grid(Pb, np.broadcast_to(np.array(NAVY_UV), Pb.shape[:2] + (2,)).copy(), 4, flip=not flip)   # navy back
    # rim round the edge (gold)
    edge = [(i, 0) for i in range(Rw + 1)] + [(Rw, j) for j in range(1, C + 1)] + [(i, C) for i in range(Rw - 1, -1, -1)] + [(0, j) for j in range(C - 1, 0, -1)]
    ring = [pb.vert(Pf[i, j]) for i, j in edge]; ringb = [pb.vert(Pb[i, j]) for i, j in edge]
    for e in range(len(edge)):
        e1 = (e + 1) % len(edge)
        q = (ring[e], ring[e1], ringb[e1], ringb[e])
        uvg = [GOLD_UV] * 4
        if flip: pb.face((q[0], q[2], q[1]), uvg[:3], 0); pb.face((q[0], q[3], q[2]), uvg[:3], 0)
        else: pb.face((q[0], q[1], q[2]), uvg[:3], 0); pb.face((q[0], q[2], q[3]), uvg[:3], 0)
    # filigree strips on both long edges and the bottom, front and back
    tw = pp['trim_w']; lift = pp['trim_lift']
    def edge_strip(Pline, Nout, inward, name='filigree', lift_=lift):
        n = len(Pline)
        acl = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(Pline, axis=0), axis=1))])
        uu = strip_uv(acl, tw, name)
        Gs = np.stack([Pline + Nout * lift_, Pline + inward * tw + Nout * lift_], 0)
        Us = np.stack([np.c_[uu, np.full(n, band_v(name, 0))], np.c_[uu, np.full(n, band_v(name, 1))]], 0)
        return Gs, Us
    nf = np.stack([np.sin(THg), -np.cos(THg), np.zeros_like(THg)], -1)  # outward
    for face_P, out_sign, fl, mi in ((Pf, 1, flip, 3), (Pb, -1, not flip, 4)):
        lines = []
        for j, inw in ((0, 1), (C, -1)):                                 # long edges, inward = toward the other edge
            Pl = face_P[:, j]
            dirv = face_P[:, j + inw] - Pl; dirv /= np.linalg.norm(dirv, axis=1, keepdims=True)
            lines.append((Pl, nf[:, j] * out_sign, dirv))
        Pl = face_P[Rw]                                                  # bottom edge
        dirv = face_P[Rw - 1] - Pl; dirv /= np.linalg.norm(dirv, axis=1, keepdims=True)
        lines.append((Pl, nf[Rw] * out_sign, dirv))
        for li, (Pl, No, dv) in enumerate(lines):
            Gs, Us = edge_strip(Pl, No, dv, lift_=lift * (1.3 if li == 2 else 1.0))
            pb.grid(Gs, Us, mi, flip=fl if li != 1 else not fl)
    o = pb.build('L1_v2_Panel_%d' % k, LAYERED)
    rep.setdefault('panel_faces_turned', []).append(orient(o, lambda c: np.array([c[0], c[1] - pp['cy'], 0.0])))
    # the tip: the bottom corner of the back edge
    tip_i, tip_j = Rw, C
    PANELS.append(dict(obj=o, th0=th0, tip=Pf[tip_i, tip_j], tip_n=nf[tip_i, tip_j], up=Pf[tip_i - 3, tip_j] - Pf[tip_i, tip_j],
                       inward=Pf[tip_i, tip_j - 2] - Pf[tip_i, tip_j], sgn=sgn))
rep['panels'] = dict(centres_deg=[round(math.degrees(p['th0']), 1) for p in PANELS])

# the sash goes on after the panels and wraps over their tops
s = SPEC['sash']
lo, hi = body_slice(s['z'])
centre = np.array([0.0, (lo[1] + hi[1]) / 2])
sash, SP = ring_band('L1_v2_Sash', s['z'], s['height'], s['gap'], [body, bod, und] + [p['obj'] for p in PANELS], centre)   # over the panel tops
c = SPEC['collar']
lo, hi = body_slice(c['z'], xmax=0.08)
collar, _ = ring_band('L1_v2_Collar', c['z'], c['height'], c['gap'], [body, bod], np.array([0.0, (lo[1] + hi[1]) / 2]),
                      segs=96)

# ---------------------------------------------------------------- front bow + brooch (Meshy, v2 placement)
w = SPEC['bow']
bow = load(FINAL % 'bow', 'L1_v2_Bow', 'L1_v2_Bow')
WV = F.verts(bow)
mid = WV[np.abs(WV[:, 0]) < 0.06]
knot_m = np.array([0.0, mid[:, 1].min(), mid[np.argmin(mid[:, 1]), 2]])
back_m = WV[:, 1].max()
fy = SP[:, np.argmin(np.abs(np.linspace(-math.pi, math.pi, 128, endpoint=False))), 1].min()
F.place(bow, S=(w['s'],) * 3, anchor_model=[0, back_m, knot_m[2]], anchor_world=[0, fy - w['gap'], s['z']])
knot_w = (knot_m - [0, back_m, knot_m[2]]) * w['s'] + [0, fy - w['gap'], s['z']]
r_ = SPEC['brooch']
bro = load(FINAL % 'brooch', 'L1_v2_Brooch', 'L1_v2_Brooch')
RV = F.verts(bro)
F.place(bro, S=(r_['s'],) * 3, anchor_model=[0, RV[:, 1].max(), 0], anchor_world=knot_w + [0, -r_['gap'], 0])
rep['bow'] = dict(knot=knot_w.tolist())

# the bow is the outermost layer: below the knot its tails bend outward over the front panels and the skirt, one
# smooth outward shift per spot of the tail measured at the bow's back face, so front and back move together (v2)
from mathutils.kdtree import KDTree
outer = bvh_of([p['obj'] for p in PANELS] + [und, bod, sash])
BW = F.verts(bow)
kd = KDTree(len(BW))
for i, q in enumerate(BW): kd.insert(Vector((q[0], 0, q[2])), i)
kd.balance()
low = np.where(BW[:, 2] < knot_w[2] - 0.005)[0]
delta = np.zeros(len(BW))
for i in low:
    x, _y, z = BW[i]
    yb = max(BW[j, 1] for _c, j, _d in kd.find_range(Vector((x, 0, z)), 0.006))
    th = math.atan2(x, -(yb - centre[1])); r = math.hypot(x, yb - centre[1])
    Re = max([outer_radius(outer, centre, z, th + dt) or 0 for dt in (-0.03, 0, 0.03)])
    delta[i] = max(0.0, Re + w['margin'] - r)
sm = delta.copy()
for i in low:
    nb = [j for _c, j, _d in kd.find_range(Vector((BW[i, 0], 0, BW[i, 2])), 0.012)]
    sm[i] = max(delta[i], float(np.mean(delta[nb])))
th = np.arctan2(BW[:, 0], -(BW[:, 1] - centre[1]))
BW[:, 0] += np.sin(th) * sm; BW[:, 1] -= np.cos(th) * sm
F.set_verts(bow, BW)
rep['bow_tail_shift_max_mm'] = float(sm.max() * 1000)

# ---------------------------------------------------------------- sleeves: long, flowing, hanging from the upper arm
lp = SPEC['sleeve']
SLEEVES = {}
for sd, sg in (('L', 1), ('R', -1)):
    a0 = bone('J_Bip_%s_UpperArm' % sd); a1 = bone('J_Bip_%s_Hand' % sd); el = bone('J_Bip_%s_LowerArm' % sd)
    ax = (a1 - a0) / np.linalg.norm(a1 - a0); Lr = np.linalg.norm(a1 - a0)
    up = np.array([0, 0, 1.0]); up -= (up @ ax) * ax; up /= np.linalg.norm(up)
    fw = np.cross(up, ax) * sg                                           # toward her front (-Y) on both sides
    if fw[1] > 0: fw = -fw
    t0 = lp['top_from_shoulder'] / Lr; t1 = 1 - lp['end_before_wrist'] / Lr
    NT, NP = lp['rows'], lp['segs']
    ts = np.linspace(t0, t1, NT)
    phis = np.linspace(0, 2 * math.pi, NP, endpoint=False)                 # 0 = up, pi = hanging side (down)
    # limb radius along the arm (body slab), plus the clearance
    def limb_r(t):
        c = a0 + (a1 - a0) * t
        rel = BV - c; along = rel @ ax
        sl = BV[np.abs(along) < 0.008]
        rr = np.linalg.norm((sl - c) - np.outer((sl - c) @ ax, ax), axis=1); rr = rr[rr < 0.09]
        return float(np.percentile(rr, 97)) if len(rr) else 0.03
    lr = np.array([limb_r(t) for t in ts])
    # one smooth line from the upper arm to the wrist, never inside the arm (row by row radii made ridged rings)
    lin = np.interp(ts, [ts[0], ts[-1]], [lr[0], lr[-1]])
    lr = np.maximum(lin, lr)
    for _ in range(40):
        lr[1:-1] = np.maximum(lr[1:-1], (lr[:-2] + lr[1:-1] + lr[2:]) / 3 * 0 + (lr[:-2] + 2 * lr[1:-1] + lr[2:]) / 4)
    lr = np.convolve(np.pad(lr, 6, mode='edge'), np.ones(13) / 13, mode='valid')
    f = (ts - t0) / (t1 - t0)
    a = lr + lp['clear'] + lp['flare'] * f ** 1.5                         # round part, opening a little
    d = lp['drop'] * f ** 1.6                                             # the hanging drape below the arm
    hang = ((1 - np.cos(phis)) / 2) ** 2                                  # 0 on top, 1 straight down
    # also stretch the hanging side along the arm toward the hand (flowing): extra length at the bottom
    ext = lp['tail'] * hang
    Rg = a[:, None] + d[:, None] * hang[None, :]
    dirs = np.cos(phis)[:, None] * up[None, :] + np.sin(phis)[:, None] * fw[None, :] * -1
    # positions: centre on the arm axis, the bottom side reaches further along (tail) at the hem only
    along = (ts[:, None] * Lr) + ext[None, :] * f[:, None] ** 3
    Po = a0[None, None, :] + along[..., None] * ax[None, None, :] + Rg[..., None] * dirs[None, :, :]
    Pi = a0[None, None, :] + along[..., None] * ax[None, None, :] + (Rg - lp['lining'])[..., None] * dirs[None, :, :]
    # pattern uvs: metres around and along
    circ = np.concatenate([np.zeros((NT, 1)), np.cumsum(np.linalg.norm(np.diff(Po, axis=1), axis=2), axis=1)], 1)
    alg = np.concatenate([np.zeros((1, NP)), np.cumsum(np.linalg.norm(np.diff(Po, axis=0), axis=2), axis=0)], 0)
    sb = Builder()
    flipo = sg < 0
    # outer white, up to the hem strip
    hem = lp['hem_w']
    hem_i = int(np.searchsorted(alg[:, 0], alg[-1, 0] - hem * 1.0))
    sb.grid(Po[:hem_i + 1], np.stack([circ[:hem_i + 1] / TILE, alg[:hem_i + 1] / TILE], -1), 2, flip=flipo, closed_u=True)
    sb.grid(Pi, np.broadcast_to(np.array(NAVY_UV), Pi.shape[:2] + (2,)).copy(), 4, flip=not flipo, closed_u=True)
    # outer hem: filigree over the last rows, lifted; inner hem: cloud embroidery on the lining
    def hem_strip(Prow_last, Prow_from, outward, name, lift_):
        n = Prow_last.shape[0]
        acl = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(Prow_last, axis=0), axis=1))])
        tot = acl[-1] + np.linalg.norm(Prow_last[0] - Prow_last[-1])
        uu = strip_uv(acl, hem, name, closed_total=tot)
        back = Prow_from - Prow_last; back /= np.linalg.norm(back, axis=1, keepdims=True)
        Gs = np.stack([Prow_last + outward * lift_, Prow_last + back * hem + outward * lift_], 0)
        Us = np.stack([np.c_[uu, np.full(n, band_v(name, 0))], np.c_[uu, np.full(n, band_v(name, 1))]], 0)
        return Gs, Us
    Gs, Us = hem_strip(Po[-1], Po[-4], dirs, 'filigree', lp['trim_lift'])
    sb.grid(Gs, Us, 3, flip=not flipo, closed_u=True)
    Gs, Us = hem_strip(Pi[-1], Pi[-4], -dirs, 'clouds', lp['trim_lift'])
    sb.grid(Gs, Us, 4, flip=flipo, closed_u=True)
    # rim at the opening and at the top (gold)
    for row in (0, NT - 1):
        ro = [sb.vert(p) for p in Po[row]]; ri = [sb.vert(p) for p in Pi[row]]
        for j in range(NP):
            j1 = (j + 1) % NP
            q = (ro[j], ro[j1], ri[j1], ri[j]); uvg = [GOLD_UV] * 3
            sb.face((q[0], q[1], q[2]), uvg, 0); sb.face((q[0], q[2], q[3]), uvg, 0)
    # engraved gold cuff at the top
    cw = lp['cuff_w']
    ci = int(np.searchsorted(alg[:, 0], cw))
    Gs, Us = hem_strip(Po[0], Po[max(ci, 2)], dirs, 'engraved', lp['trim_lift'])
    sb.grid(Gs, Us, 3, flip=not flipo, closed_u=True)
    o = sb.build('L1_v2_Sleeve_' + sd, LAYERED)
    def out_arm(c, a0=a0, ax=ax):
        r = c - a0; return r - (r @ ax) * ax
    rep.setdefault('sleeve_faces_turned', {})[sd] = orient(o, out_arm)
    star_i = int(np.searchsorted(alg[:, 0], alg[-1, 0] - hem - lp['star_above_hem']))
    jf = int(np.argmax([np.dot(dd, -fw) * -1 for dd in dirs]))         # the front of the sleeve
    SLEEVES[sd] = dict(obj=o, star=Po[star_i, jf], star_n=dirs[jf], ax=ax)
rep['sleeves'] = {k: dict(tris=len(v['obj'].data.polygons)) for k, v in SLEEVES.items()}

# ---------------------------------------------------------------- back bow of band 4 ribbon, on her hair
bb_ = SPEC['back_bow']
hb = bvh_of([hair])
def hair_back(x, z):
    loc, _n, _i, _d = hb.ray_cast(Vector((x, 0.6, z)), Vector((0, -1, 0)), 1.0)
    return None if loc is None else loc.y
kz = bb_['knot_z']; ky = (hair_back(0, kz) or 0.14) + bb_['off']
rw = bb_['ribbon_w']
bwb = Builder()
def ribbon(path, normal_fn, name='clouds'):
    P_ = np.array(path); n = len(P_)
    T = np.gradient(P_, axis=0); T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
    Nn = np.array([normal_fn(p) for p in P_])
    X = np.cross(T, Nn); X /= np.maximum(np.linalg.norm(X, axis=1, keepdims=True), 1e-9)
    acl = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P_, axis=0), axis=1))])
    uu = strip_uv(acl, rw, name)
    G = np.stack([P_ - X * rw / 2, P_ + X * rw / 2], 0)
    U = np.stack([np.c_[uu, np.full(n, band_v(name, 0))], np.c_[uu, np.full(n, band_v(name, 1))]], 0)
    bwb.grid(G, U, 0)
back_n = lambda p: np.array([0, 1.0, 0])
# loops: a teardrop each side, out from the knot and back
for sg in (1, -1):
    tt = np.linspace(0, 2 * math.pi, 40)
    Lx = bb_['loop_len'] * (1 - np.cos(tt)) / 2
    Lz = bb_['loop_h'] * np.sin(tt) / 2 * (0.4 + 0.6 * (1 - np.cos(tt)) / 2)
    path = [(sg * (0.008 + lx), ky + 0.004 + 0.006 * math.sin(t_ / 2), kz + lz + 0.01 * (lx / bb_['loop_len'])) for lx, lz, t_ in zip(Lx, Lz, tt)]
    ribbon(path, back_n)
# knot: a short band round the middle
ribbon([(0.0, ky + 0.013, kz + 0.016), (0.0, ky + 0.014, kz), (0.0, ky + 0.013, kz - 0.016)], back_n)
bow_back = bwb.build('L1_v2_BackBow', [M_TRIM])
TAILS = {}
for sg, sd in ((1, 'L'), (-1, 'R')):
    tb = Builder(); bwb = tb
    zs_ = np.linspace(kz - 0.01, bb_['tail_end_z'], 40)
    xs_ = sg * (0.01 + (bb_['tail_spread'] - 0.01) * ((kz - zs_) / (kz - bb_['tail_end_z'])) ** 1.2)
    path = [(x, (hair_back(x, z) or ky) + bb_['off'], z) for x, z in zip(xs_, zs_)]
    path = np.array(path)
    for _ in range(4):
        path[1:-1, 1] = (path[:-2, 1] + 2 * path[1:-1, 1] + path[2:, 1]) / 4
    ribbon(path, back_n)
    TAILS[sd] = tb.build('L1_v2_BackRibbon_' + sd, [M_TRIM])
rep['back_bow'] = dict(knot=[0, ky, kz])


# ---------------------------------------------------------------- decals: opaque meshes cut to the ornament outlines
def decal(name, kind, centre, normal, up_dir, size, host=None, lift=0.0015, corner_to=None):
    dd = DEC[kind]
    cu_, cv_ = dd['centre_uv']; wu, wv = dd['wh_uv']
    pxw, pxh = dd['size_px']; aspect = pxh / pxw
    n = np.array(normal, float); n /= np.linalg.norm(n)
    upv = np.array(up_dir, float); upv -= n * (upv @ n); upv /= np.linalg.norm(upv)
    rt = np.cross(upv, n)
    mx = my = 1.0
    if corner_to is not None:                                            # the ornament's corner (image top right) into a tip
        dv = np.array(corner_to) - np.array(centre)
        mx = 1.0 if dv @ rt > 0 else -1.0; my = 1.0 if dv @ upv > 0 else -1.0
    polys = [[Vector(((u - cu_) / wu * mx, (v - cv_) / wv * aspect * my, 0.0)) for u, v in p['uv']] for p in dd['polys']]
    tris = tessellate_polygon(polys)
    flat = [p for poly in polys for p in poly]
    uvs = [(u, v) for p in dd['polys'] for u, v in p['uv']]
    hb_ = bvh_of([host]) if host is not None else None
    db = Builder()
    ids = []
    for p in flat:
        q = np.array(centre) + rt * p.x * size + upv * p.y * size
        if hb_ is not None:                                              # onto the cloth's outer face: a ray from outside
            loc, nrm, _i, _d = hb_.ray_cast(Vector(q + n * 0.03), Vector(-n), 0.06)
            if loc is not None:
                q = np.array(loc) + n * lift
        else:
            q = q + n * lift
        ids.append(db.vert(q))
    for t in tris:
        a_, b_, c_ = t
        if (Vector(flat[b_]) - Vector(flat[a_])).cross(Vector(flat[c_]) - Vector(flat[a_])).z < 0: a_, b_ = b_, a_
        db.face((ids[a_], ids[b_], ids[c_]), (uvs[a_], uvs[b_], uvs[c_]), 0)
    return db.build(name, [M_DEC])


DS = SPEC['decals']
decals = []
for k, p in enumerate(PANELS):
    o = p['obj']
    # tip corner: the ornament's corner points into the tip (its outer corner is top right in the image)
    c_ = p['tip'] + p['up'] / np.linalg.norm(p['up']) * DS['corner'] * 0.62 + p['inward'] / np.linalg.norm(p['inward']) * DS['corner'] * 0.45
    decals.append(decal('L1_v2_Decal_Corner_%d' % k, 'corner', c_, p['tip_n'], p['up'], DS['corner'], host=o, lift=pp['trim_lift'] * 2.2,
                        corner_to=p['tip']))
for sd, sv in SLEEVES.items():
    decals.append(decal('L1_v2_Decal_Star_' + sd, 'star4', sv['star'], sv['star_n'], sv['ax'], DS['sleeve_star'], host=sv['obj'],
                        lift=lp['trim_lift'] * 1.5))
# crest on the back of the sash
bi = int(np.argmin(np.abs(np.linspace(-math.pi, math.pi, 128, endpoint=False) - math.pi)))
cb = SP[2, bi]
decals.append(decal('L1_v2_Decal_Crest', 'crest', cb, (0, 1, 0), (0, 0, 1), DS['crest'], host=sash, lift=0.0015))
rep['decals'] = [d.name for d in decals]

# ---------------------------------------------------------------- report
tris, v2tris = {}, 0
for o in coll.objects:
    o.data.calc_loop_triangles(); tris[o.name] = len(o.data.loop_triangles)
    if o.name.startswith('L1_v2_'): v2tris += tris[o.name]
allt = 0
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.data.calc_loop_triangles(); allt += len(o.data.loop_triangles)
rep['tris'] = tris; rep['tris_v2_outfit'] = v2tris; rep['tris_everything'] = allt
json.dump(rep, open(OUT + '/placement.json', 'w'), indent=1, default=float)
bpy.ops.wm.save_as_mainfile(filepath=OUT + '/v3_placed.blend')
print('PLACED v3 outfit tris', v2tris, 'everything', allt)
