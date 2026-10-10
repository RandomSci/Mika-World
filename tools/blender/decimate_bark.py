"""Decimate non-leaf materials of a glTF tree and export GLB.
blender --background --factory-startup --python decimate_bark.py -- in.gltf out.glb ratio_branches ratio_trunk"""
import bpy, sys
args = sys.argv[sys.argv.index("--") + 1:]
src, dst, r_br, r_tr = args[0], args[1], float(args[2]), float(args[3])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in meshes:
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.separate(type="MATERIAL"); bpy.ops.object.mode_set(mode="OBJECT")
for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
    mname = o.data.materials[0].name.lower() if o.data.materials else ""
    if "lea" in mname or "twig" in mname or "needle" in mname:
        continue
    ratio = r_tr if "trunk" in mname or "bark" in mname else r_br
    m = o.modifiers.new("dec", "DECIMATE"); m.ratio = ratio; m.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="dec")
tot = 0
for o in bpy.context.scene.objects:
    if o.type == "MESH":
        o.data.calc_loop_triangles(); tot += len(o.data.loop_triangles)
        print("OBJ", o.name, o.data.materials[0].name if o.data.materials else "", len(o.data.loop_triangles))
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_yup=True, export_apply=True)
print("TOTAL", tot)
