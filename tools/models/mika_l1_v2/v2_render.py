"""Mika L1 v2 parts, step 1d (Selwyn 2026-10-20): before and after close ups of one part, same cameras.
Before is the Meshy GLB with its 4K texture, after is the cleaned GLB with flat colour materials. Workbench render,
studio light, no outline, so only the colour and trim edges differ. Close up targets are picked from the cleaned
mesh: points on colour borders spread over the part (farthest point sampling), seen along the surface normal.
  blender -b -P tools/v2_render.py -- <part> <before.glb> <after.glb> <out dir> [--zooms 4] [--zoom-mm 40]
  [--targets x,y,z;x,y,z]  (extra close up targets in glTF coordinates)
  [--modes MATERIAL,TEXTURE]  (baked low poly against the clean high poly: before = high, after = baked)"""
import sys, os, math
import numpy as np
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
part, before, after, out = argv[:4]
opt = {argv[i]: argv[i + 1] for i in range(4, len(argv) - 1) if argv[i].startswith('--')}
NZ = int(opt.get('--zooms', 4))
ZOOM_MM = float(opt.get('--zoom-mm', 40))
SIZE_CM = float(opt.get('--size-cm', 40))
MODES = opt.get('--modes', 'TEXTURE,MATERIAL').split(',')          # workbench colour for before, after
os.makedirs(out, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'STUDIO'; sh.color_type = 'TEXTURE'; sh.show_cavity = False; sh.show_object_outline = False
sh.show_specular_highlight = False; sh.show_backface_culling = False
sc.display.render_aa = '16'
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new('w'); sc.world.color = (0.36, 0.37, 0.40)
sc.render.image_settings.file_format = 'PNG'


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    obs = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
    for o in obs:
        for m in o.data.materials:
            if m and m.use_nodes:                                        # crisp texels like the game's linear filter
                for n in m.node_tree.nodes:
                    if n.type == 'TEX_IMAGE':
                        n.interpolation = 'Linear'
    return obs


A = load(before); B = load(after)
# after GLB: colour comes from the material, Workbench 'TEXTURE' falls back to material colour when no image
allobs = A + B
lo = np.min([np.array(o.bound_box).min(0) + np.array(o.location) for o in A], 0)
hi = np.max([np.array(o.bound_box).max(0) + np.array(o.location) for o in A], 0)
ctr = (lo + hi) / 2; ext = (hi - lo).max()
mm = ext / (SIZE_CM * 10)

cam_d = bpy.data.cameras.new('cam'); cam = bpy.data.objects.new('cam', cam_d); sc.collection.objects.link(cam); sc.camera = cam
cam_d.type = 'ORTHO'
cam_d.clip_start = 0.0005; cam_d.clip_end = 100


def aim(eye, target, ortho):
    cam.location = Vector(eye)
    d = Vector(target) - Vector(eye)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    cam_d.ortho_scale = ortho


def shoot(name, res):
    sc.render.resolution_x = sc.render.resolution_y = res
    for tag, grp in (('before', A), ('after', B)):
        for o in allobs:
            o.hide_render = o not in grp
        sh.color_type = MODES[0] if tag == 'before' else MODES[1]
        sc.render.filepath = f'{out}/{name}_{tag}.png'
        bpy.ops.render.render(write_still=True)


# full views
for k, az in enumerate([float(x) for x in opt.get('--azimuths', '30,210').split(',')]):
    a = math.radians(az)
    d = np.array([math.sin(a), -math.cos(a), 0.25]); d /= np.linalg.norm(d)
    aim(ctr + d * ext * 3, ctr, ext * 1.15)
    shoot(f'full{k}', 1000)

# border points on the cleaned mesh, outward facing
me = B[0].data
mw = np.array(B[0].matrix_world)
V = np.array([mw[:3, :3] @ np.array(v.co) + mw[:3, 3] for v in me.vertices])
N = np.array([mw[:3, :3] @ np.array(v.normal) for v in me.vertices])
# glTF import splits vertices per material, so find borders by position
key = np.round(V / (0.01 * mm)).astype(np.int64)
_, inv = np.unique(key, axis=0, return_inverse=True); inv = inv.ravel()
pm = np.zeros((inv.max() + 1, 8), bool)
for p in me.polygons:
    for vi in p.vertices:
        pm[inv[vi], p.material_index] = True
border = np.nonzero(pm[inv].sum(1) > 1)[0]
targets = []
if len(border):
    out_dir = V[border] - ctr
    facing = (N[border] * out_dir).sum(1) > 0
    cand = border[facing] if facing.sum() > 50 else border
    pick = [cand[np.argmax(np.linalg.norm(V[cand] - ctr, axis=1) * 0 + V[cand][:, 2])]]   # highest border point first
    dmin = np.linalg.norm(V[cand] - V[pick[0]], axis=1)
    while len(pick) < NZ:
        i = int(np.argmax(dmin)); pick.append(cand[i])
        dmin = np.minimum(dmin, np.linalg.norm(V[cand] - V[cand[i]], axis=1))
    targets = [(V[i], N[i]) for i in pick]
for t in [s for s in opt.get('--targets', '').split(';') if s]:
    x, y, z = map(float, t.split(','))
    p = np.array([x, -z, y])                                             # glTF to Blender axes
    i = int(np.argmin(np.linalg.norm(V - p, axis=1)))
    targets.append((V[i], N[i]))
import json
tj = f'{out}/targets.json'
if os.path.exists(tj):                                                   # same cameras on every rerun
    targets = [(np.array(p), np.array(n)) for p, n in json.load(open(tj))]
else:
    json.dump([(list(map(float, p)), list(map(float, n))) for p, n in targets], open(tj, 'w'))
for k, (p, n) in enumerate(targets):
    n = n / max(np.linalg.norm(n), 1e-9)
    view = n + 0.35 * (p - ctr) / max(np.linalg.norm(p - ctr), 1e-9)
    view /= np.linalg.norm(view)
    aim(p + view * ext * 2, p, ZOOM_MM * mm)
    shoot(f'zoom{k}', 900)
print('RENDERED', part, len(targets), 'zooms')
