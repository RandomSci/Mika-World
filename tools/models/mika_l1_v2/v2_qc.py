"""Mika L1 outfit v2 (Selwyn 2026-10-20): quick fit check renders of a blend in Blender Workbench (texture colours,
studio light), front, three quarter, side, back and a waist close up. Run through tools/gpu_blender.sh.
  blender -b <blend> -P l1_v2/tools/v2_qc.py -- <out dir> [--hide name,name]"""
import sys, os, math
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
out = argv[0]; os.makedirs(out, exist_ok=True)
hide = argv[argv.index('--hide') + 1].split(',') if '--hide' in argv else []
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'STUDIO'; sh.color_type = 'TEXTURE'; sh.show_cavity = True; sh.cavity_type = 'WORLD'
sh.show_object_outline = False; sh.show_backface_culling = False
sc.display.render_aa = '8'
sc.world = sc.world or bpy.data.worlds.new('w'); sc.world.color = (0.36, 0.37, 0.40)
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.hide_render = any(o.name.startswith(h) for h in hide)
        for m in o.data.materials:
            if m and m.use_nodes:
                for n in m.node_tree.nodes:
                    if n.type == 'TEX_IMAGE': m.node_tree.nodes.active = n
cam_d = bpy.data.cameras.new('qc'); cam = bpy.data.objects.new('qc', cam_d); sc.collection.objects.link(cam); sc.camera = cam
cam_d.clip_start = 0.01
VIEWS = {'front': (0, 0.95, 3.2, 1.0, 28), 'q34': (35, 0.95, 3.2, 1.0, 28), 'side': (90, 0.95, 3.2, 1.0, 28),
         'back': (180, 0.95, 3.2, 1.0, 28), 'waist': (20, 1.08, 1.3, 1.08, 30), 'chest': (25, 1.25, 1.0, 1.24, 32),
         'arm': (60, 1.3, 1.5, 1.28, 32), 'waistf': (0, 1.0, 1.1, 0.98, 30), 'waistr': (-35, 1.0, 1.1, 0.98, 30)}
for name, (az, ez, dist, tz, lens) in VIEWS.items():
    a = math.radians(az)
    cam.location = Vector((math.sin(a) * dist, -math.cos(a) * dist, ez))
    cam.rotation_euler = (Vector((0, 0, tz)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam_d.lens = lens * 2
    sc.render.resolution_x, sc.render.resolution_y = (700, 1000) if name in ('front', 'q34', 'side', 'back') else (900, 700)
    sc.render.filepath = f'{out}/{name}.png'
    bpy.ops.render.render(write_still=True)
print('QC done')
