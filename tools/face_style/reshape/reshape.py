# Luna's face reshape (Blender, background). One smooth deformation field f(p), applied to the Face mesh, every one of
# its shape keys (each key's own positions, so blinks and visemes scale with the new eyes and mouth), the blush mesh,
# the front hair (curtain bangs) and the eye bones. Works on a copy; the source .blend is never saved over.
# usage: blender -b <copy>.blend --python reshape.py -- <params.json> <out.blend|-> [out.vrm]
import bpy, bmesh, sys, json, math
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:]
P = json.load(open(args[0]))
out_blend = args[1]
out_vrm = args[2] if len(args) > 2 else None

face = bpy.data.objects['Face']
A = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
me = face.data
mw = np.array(face.matrix_world)
imw = np.linalg.inv(mw)


def world(co):
    return co @ mw[:3, :3].T + mw[:3, 3]


def local(p):
    return p @ imw[:3, :3].T + imw[:3, 3]


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- landmarks from the basis
B = world(np.array([v.co for v in me.vertices]))
mat_of = np.zeros(len(B), int)
for p in me.polygons:
    for v in p.vertices:
        mat_of[v] = p.material_index
names = [m.name for m in me.materials]
def mverts(sub):
    i = [k for k, n in enumerate(names) if sub in n][0]
    return np.nonzero(mat_of == i)[0]
iris = B[mverts('EyeIris')]
eyeL = iris[iris[:, 0] > 0].mean(0); eyeR = iris[iris[:, 0] < 0].mean(0)
mouth = B[mverts('FaceMouth')].mean(0)
skin_i = mverts('_Face_00_SKIN')
S = B[skin_i]
chin_z = S[(np.abs(S[:, 0]) < 0.004) & (S[:, 1] < -0.05)][:, 2].min()
nz = S[(np.abs(S[:, 0]) < 0.003) & (S[:, 2] > mouth[2] + 0.01) & (S[:, 2] < eyeL[2] - 0.005)]
nose = nz[nz[:, 1].argmin()]
eye_z = (eyeL[2] + eyeR[2]) / 2
lm = {'eyeL': eyeL.round(4).tolist(), 'eyeR': eyeR.round(4).tolist(), 'mouth': mouth.round(4).tolist(),
      'nose_tip': nose.round(4).tolist(), 'chin_z': round(float(chin_z), 4)}
print('LANDMARKS', json.dumps(lm))

# skin boundary (the neck seam and the back edge) stays put: weight fades in over `seam_fade` metres
bm = bmesh.new(); bm.from_mesh(me)
bnd = np.array([v.index for v in bm.verts if v.is_boundary and mat_of[v.index] == mat_of[skin_i[0]]])
bm.free()
# only the real seams (neck, back of the head): not the eye and mouth openings in the skin
Bb = B[bnd]
near_feature = (np.abs(Bb[:, 2] - eye_z) < 0.03) & (Bb[:, 1] < -0.04) | (np.abs(Bb[:, 2] - mouth[2]) < 0.012) & (np.abs(Bb[:, 0]) < 0.03) & (Bb[:, 1] < -0.05)
bnd = bnd[~near_feature]
print('SEAM verts', len(bnd), 'z range', B[bnd][:, 2].min().round(4), B[bnd][:, 2].max().round(4), 'y range', B[bnd][:, 1].min().round(4), B[bnd][:, 1].max().round(4))
SB = B[bnd]
dseam = np.array([np.sqrt(((SB - b) ** 2).sum(1)).min() for b in B])
W_seam = sstep(0.0, P['seam_fade'], dseam)


def gauss(p, c, r):
    d = (p - np.asarray(c)) / np.asarray(r)
    return np.exp(-(d * d).sum(1))


def field(p, w):
    """the deformation of points p (world, Nx3) with per-vertex mask w"""
    q = p.copy()
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    # 1) shorter face: everything below the eye line comes up by a fraction of its distance to the eye line;
    #    a rounder, softer chin (the V widens toward a curve); fuller cheeks
    below = np.clip(eye_z - z, 0, None)
    t_low = np.clip((eye_z - z) / (eye_z - chin_z), 0, 1.2)
    q[:, 2] += w * below * P['shorten']
    tm = np.clip((mouth[2] - z) / (mouth[2] - chin_z), 0, 1)     # 0 at the mouth .. 1 at the chin
    v_prof = np.maximum(1 - tm, 0.08)
    round_prof = np.sqrt(np.clip(1 - tm ** 2, 0, 1))
    k = np.clip(round_prof / v_prof, 1, P['chin_round_max'])
    front = sstep(P['front_y'][0], P['front_y'][1], -y)        # the face front (Blender -Y is forward)
    q[:, 0] += w * front * x * (k - 1) * P['chin_round'] * (z < mouth[2])
    q[:, 2] += w * P['chin_lift'] * gauss(p, [0, -0.08, chin_z], [0.02, 0.05, 0.012])
    for sx in (1, -1):
        g = gauss(p, [sx * P['cheek'][0], P['cheek'][1], P['cheek'][2]], P['cheek_r'])
        q[:, 0] += w * g * sx * P['cheek_out']
        q[:, 1] -= w * g * P['cheek_fwd']
    # 2) mouth up and smaller
    gm = gauss(p, mouth + np.array([0, -0.01, 0]), P['mouth_r'])
    q[:, 2] += w * gm * P['mouth_up']
    q[:, 0] += w * gm * (mouth[0] - x) * (1 - P['mouth_scale'])
    # 3) eyes: bigger and rounder (taller), a little lower and closer together
    for e in (eyeL, eyeR):
        sgn = np.sign(e[0])
        d = (p - e) / np.asarray(P['eye_r'])
        g = sstep(1.0, 0.0, np.sqrt((d * d).sum(1)) - P['eye_core'])       # 1 in the core, fading out
        q[:, 0] += w * g * ((x - e[0]) * (P['eye_sx'] - 1) - sgn * P['eye_in'])
        q[:, 2] += w * g * ((z - e[2]) * (P['eye_sz'] - 1) - P['eye_down'])
    # 4) smaller, softer nose
    gn = gauss(p, nose, P['nose_r'])
    base = nose + np.array([0, P['nose_base_y'], 0])
    q += (w * gn * (1 - P['nose_scale']))[:, None] * (base - p)
    return q


def eye_xform(c):
    """where an eye centre ends up (eye bones follow the eyes)"""
    p = c[None, :].copy()
    return field(p, np.ones(1))[0]


# ---------------------------------------------------------------- apply to the Face mesh and all its shape keys
extra = np.zeros(len(B))
lash = mverts('FaceEyelash')
keys = me.shape_keys.key_blocks
basis_new = None
for kb in keys:
    K = world(np.array([d.co for d in kb.data]))
    Q = field(K, W_seam)
    # 5) longer, fuller upper lashes: the lash strip grows away from the eye, upward
    for e in (eyeL, eyeR):
        sel = lash[(np.sign(K[lash, 0]) == np.sign(e[0]))]
        up = np.clip(K[sel, 2] - e[2], 0, None)
        Q[sel, 2] += up * P['lash_grow']
        Q[sel, 0] += (K[sel, 0] - e[0]) * P['lash_grow'] * 0.25
    # the bigger eyes crowd the brows: lift them back clear of the lids (a calm brow, not a frown)
    brows = mverts('FaceBrow')
    Q[brows, 2] += P.get('brow_up', 0.0)
    L = local(Q)
    for i, d in enumerate(kb.data):
        d.co = L[i]
    if kb.name == keys[0].name:
        basis_new = L
for i, v in enumerate(me.vertices):
    v.co = basis_new[i]
me.update()

# the blush mesh rides the cheeks
fb = bpy.data.objects.get('Face_Blush')
if fb:
    fmw = np.array(fb.matrix_world); fimw = np.linalg.inv(fmw)
    for kb in fb.data.shape_keys.key_blocks:
        K = np.array([d.co for d in kb.data]); Kw = K @ fmw[:3, :3].T + fmw[:3, 3]
        Q = field(Kw, np.ones(len(Kw)))
        L = Q @ fimw[:3, :3].T + fimw[:3, 3]
        for i, d in enumerate(kb.data):
            d.co = L[i]
    for i, v in enumerate(fb.data.vertices):
        v.co = fb.data.shape_keys.key_blocks[0].data[i].co
    fb.data.update()

# 7) curtain bangs: the front strands either side of the parting drawn toward the middle and a little down, so the
#    forehead is framed instead of one big V (only the front of the hair, below the laurel)
hair = bpy.data.objects.get('L1_Hair') or bpy.data.objects.get('Hairs')
if hair and P.get('bangs', 0) > 0:
    hm = np.array(hair.matrix_world); him = np.linalg.inv(hm)
    H = np.array([v.co for v in hair.data.vertices]); Hw = H @ hm[:3, :3].T + hm[:3, 3]
    x, y, z = Hw[:, 0], Hw[:, 1], Hw[:, 2]
    zone = sstep(P['bang_front'], P['bang_front'] + 0.015, -y) * gauss(Hw * np.array([0, 0, 1]), [0, 0, P['bang_z']], [1, 1, P['bang_zr']])
    zone *= sstep(P['bang_xmax'], P['bang_xmax'] - 0.02, np.abs(x))
    xn = x * (1 - zone * P['bangs'])
    # keep the moved strands on the forehead's curve (the middle of the forehead stands further forward)
    R = P.get('bang_curve_r', 0.085)
    Hw[:, 1] -= zone * (np.sqrt(np.clip(R * R - xn * xn, 0, None)) - np.sqrt(np.clip(R * R - x * x, 0, None)))
    Hw[:, 0] = xn
    Hw[:, 2] -= zone * P['bang_down']
    Hn = Hw @ him[:3, :3].T + him[:3, 3]
    for i, v in enumerate(hair.data.vertices):
        v.co = Hn[i]
    hair.data.update()
    print('BANGS moved', int((zone > 0.05).sum()), 'hair verts')

# eye bones follow the eyes
bpy.context.view_layer.objects.active = A
bpy.ops.object.mode_set(mode='EDIT')
amw = np.array(A.matrix_world); aim = np.linalg.inv(amw)
for side, e in (('L', eyeL), ('R', eyeR)):
    # VRoid: J_Adj_L_FaceEye sits on the character's left (+X in Blender)
    moved = eye_xform(e) - e
    for bn in ('J_Adj_%s_FaceEyeSet' % side, 'J_Adj_%s_FaceEye' % side):
        eb = A.data.edit_bones.get(bn)
        if eb is None:
            continue
        hw = np.array(A.matrix_world @ eb.head)
        if np.sign(hw[0]) != np.sign(e[0]):
            continue
        dv = Vector((aim[:3, :3] @ moved).tolist())
        eb.head += dv; eb.tail += dv
        print('BONE', bn, 'moved', np.round(moved, 4).tolist())
bpy.ops.object.mode_set(mode='OBJECT')

new = world(np.array([v.co for v in me.vertices]))
S2 = new[skin_i]
print('RESULT chin_z %.4f -> %.4f, mouth z %.4f -> %.4f, eye z %.4f -> %.4f' % (
    chin_z, S2[(np.abs(S2[:, 0]) < 0.004) & (S2[:, 1] < -0.05)][:, 2].min(), mouth[2], new[mverts('FaceMouth')].mean(0)[2],
    eye_z, new[mverts('EyeIris')].mean(0)[2]))
if out_blend != '-':
    bpy.ops.wm.save_as_mainfile(filepath=out_blend, copy=True)
if out_vrm:
    r = bpy.ops.export_scene.vrm(filepath=out_vrm, armature_object_name=A.name)
    print('EXPORT', r, out_vrm)
print('RESHAPE OK')
