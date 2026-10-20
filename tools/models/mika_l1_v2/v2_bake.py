"""Mika L1 v2 parts, face budget (Selwyn 2026-10-20): bake the clean high poly flat colours onto the low poly.
Loads the low poly .blend (v2_lowpoly.py), puts the xatlas uvs back (v2_uv.py), imports the clean high poly GLB
(built_txf) and bakes Cycles diffuse colour, selected to active. Each texel records the mix
of what lies under it, 32 samples spread over the texel with a box filter, so v2_snap.py can give each texel the
colour that covers most of it (no blending survives the snap), 16 px margin. Rays start a little outside the low poly and stop a
little inside it, along the flat face normals, so a curl or fold of the same part lying further out is never hit first.
Run through tools/gpu_blender.sh (GPU, shared lock).
  blender -b -P tools/v2_bake.py -- <low.blend> <uv.npz> <high.glb> <out.png> <size cm> [extrude mm] [ray mm]"""
import sys, os, time
import numpy as np
import bpy

argv = sys.argv[sys.argv.index('--') + 1:]
low_blend, uvnpz, high, out_png, size_cm = argv[:5]
EXT_MM = float(argv[5]) if len(argv) > 5 else 0.25
RAY_MM = float(argv[6]) if len(argv) > 6 else 0.5
N = 4096

bpy.ops.wm.open_mainfile(filepath=low_blend)
sc = bpy.context.scene
low = [o for o in sc.objects if o.type == 'MESH'][0]
me = low.data
uv = np.load(uvnpz)['UV']
assert len(uv) == len(me.polygons) and len(me.loops) == 3 * len(me.polygons)
me.uv_layers[0].data.foreach_set('uv', uv.reshape(-1))
for p in me.polygons:                    # rays along the true face normal; smooth normals bent them onto
    p.use_smooth = False                 # the next surface at creases (white combs in the gold). Bake only.

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=high)
hi = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
mm = max(low.dimensions) / (float(size_cm) * 10)

# how far the low poly strays from the high poly surface, at its vertices and triangle centres
from mathutils.bvhtree import BVHTree
dg = bpy.context.evaluated_depsgraph_get()
trees = [BVHTree.FromObject(o, dg) for o in hi]
pts = [v.co.copy() for v in me.vertices] + [p.center.copy() for p in me.polygons]
dev = np.array([min(t.find_nearest(p)[3] for t in trees) for p in pts]) / mm
print(f'DEVIATION mm p50 {np.percentile(dev, 50):.3f} p99 {np.percentile(dev, 99):.3f} max {dev.max():.3f}')

img = bpy.data.images.new('bake', N, N, alpha=False, float_buffer=False)
img.colorspace_settings.name = 'sRGB'
mat = bpy.data.materials.new('bake_target'); mat.use_nodes = True
tn = mat.node_tree.nodes.new('ShaderNodeTexImage'); tn.image = img; tn.interpolation = 'Closest'
mat.node_tree.links.new(tn.outputs['Color'], mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
mat.node_tree.nodes.active = tn
me.materials.clear(); me.materials.append(mat)

sc.render.engine = 'CYCLES'
prefs = bpy.context.preferences.addons['cycles'].preferences
dev = 'CPU'
for kind in ('OPTIX', 'CUDA'):
    try:
        prefs.compute_device_type = kind; prefs.get_devices()
        gpus = [d for d in prefs.devices if d.type == kind]
        if gpus:
            for d in prefs.devices:
                d.use = d.type == kind
            dev = kind; break
    except TypeError:
        pass
sc.cycles.device = 'GPU' if dev != 'CPU' else 'CPU'
sc.cycles.samples = 32
sc.cycles.pixel_filter_type = 'BOX'; sc.cycles.filter_width = 1.0
sc.cycles.use_denoising = False
b = sc.render.bake
b.use_selected_to_active = True; b.use_cage = False
b.cage_extrusion = EXT_MM * mm; b.max_ray_distance = (EXT_MM + RAY_MM) * mm
b.margin = 16; b.margin_type = 'ADJACENT_FACES'
b.use_pass_direct = False; b.use_pass_indirect = False; b.use_pass_color = True

bpy.ops.object.select_all(action='DESELECT')
for o in hi:
    o.select_set(True)
low.select_set(True); bpy.context.view_layer.objects.active = low
t0 = time.time()
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, use_clear=True, margin=16)
img.filepath_raw = out_png; img.file_format = 'PNG'; img.save()
print(f'BAKED {os.path.basename(out_png)} in {time.time() - t0:.0f} s device {dev} extrude {EXT_MM} mm ray {RAY_MM} mm')
