# usage: blender -b X.blend --python render_head.py -- <out_prefix> [hair=1]
import bpy, sys, math
from mathutils import Vector
args = sys.argv[sys.argv.index('--') + 1:]
pref = args[0]; hair = len(args) < 2 or args[1] != '0'
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
sc.render.resolution_x = 900; sc.render.resolution_y = 1000
sc.render.film_transparent = False
for ob in bpy.data.objects:
    if ob.type == 'MESH':
        keep = ob.name in ('Face', 'Face_Blush', 'Body') or (hair and (ob.name.startswith('L1_Hair') or ob.name == 'Hairs' or 'Earring' in ob.name))
        ob.hide_render = not keep
for o in [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT')]:
    bpy.data.objects.remove(o)
w = bpy.data.worlds.new('w') if not sc.world else sc.world
sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes.get('Background'); bg.inputs[0].default_value = (0.55, 0.55, 0.6, 1); bg.inputs[1].default_value = 1.0
ld = bpy.data.lights.new('key', 'SUN'); ld.energy = 2.5
lo = bpy.data.objects.new('key', ld); sc.collection.objects.link(lo); lo.rotation_euler = (math.radians(60), 0, math.radians(-20))
cd = bpy.data.cameras.new('cam'); cd.type = 'ORTHO'; cd.ortho_scale = 0.3
cam = bpy.data.objects.new('cam', cd); sc.collection.objects.link(cam); sc.camera = cam
target = Vector((0, -0.03, 1.555))
for name, d in [('front', Vector((0, -1, 0))), ('side', Vector((1, 0, 0))), ('three', Vector((0.6, -1, 0.05)).normalized())]:
    cam.location = target + d * 1.0
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = '%s_%s.png' % (pref, name)
    bpy.ops.render.render(write_still=True)
print('RENDER OK')
