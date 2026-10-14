"""Extract chosen clips of Quaternius's Universal Animation Library (CC0; packs 1 + 2, Unreal-Godot exports) into
one small GLB for the game (armature + the clips as NLA tracks, no mannequin mesh). WorldCharacter retargets them
onto the VRM skeletons through assets/animations/ual_bonemap.tres.

  blender -b --factory-startup --python tools/models/ual_extract.py -- <UAL1.glb> <UAL2.glb> <out.glb> Clip,Clip,...
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
UAL1, UAL2, OUT = argv[:3]
keep = set(argv[3].split(","))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=UAL1)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
bpy.ops.import_scene.gltf(filepath=UAL2)
for o in list(bpy.data.objects):
    if o.type == 'MESH' or (o.type == 'ARMATURE' and o != arm):
        bpy.data.objects.remove(o, do_unlink=True)
names = {}
for a in list(bpy.data.actions):
    base_name = a.name.split("|")[-1]
    for k in keep:
        if base_name == k or base_name.startswith(k + "_Armature") or base_name.startswith(k + "."):
            base_name = k
    if base_name not in keep or base_name in names:
        bpy.data.actions.remove(a)
        continue
    a.name = base_name
    a.use_fake_user = True
    names[base_name] = a
print("kept", sorted(names), "missing", sorted(keep - set(names)))
arm.animation_data_create()
arm.animation_data.action = None
for tr in list(arm.animation_data.nla_tracks):
    arm.animation_data.nla_tracks.remove(tr)
for n, a in names.items():
    tr = arm.animation_data.nla_tracks.new()
    tr.name = n
    tr.strips.new(n, int(a.frame_range[0]), a)
    tr.mute = True
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=True,
                          export_animation_mode='NLA_TRACKS', export_yup=True, export_skins=True)
print("exported", OUT)
