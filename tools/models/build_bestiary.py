"""A Bestiary monster for Mika World's hero scenes (the developer: "stop relying on overly simple placeholder monsters
for hero scenes ... Quaternius Bestiary Dungeon Monsters Kit"). The kit's sculpted, PBR-textured creature (Quaternius
QAL licence; free Standard tier: Imp, Puglin) ships rigged on the Unreal-style skeleton of Quaternius's Universal
Animation Library but without animations; this bakes the chosen UAL clips (CC0) onto it and exports one GLB with the
model, its textures and the clips. Only rotations are transferred (plus the pelvis's own motion), so the
mannequin's bone lengths never stretch the creature.

  blender -b --factory-startup --python tools/models/build_bestiary.py -- <creature.glb> <UAL1.glb> <UAL2.glb> <out.glb> name=Source,...
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, UAL1, UAL2, OUT = argv[:4]
WANT = dict(p.split("=") for p in argv[4].split(","))

bpy.ops.wm.read_factory_settings(use_empty=True)


def imp(path):
    before = set(bpy.data.objects)
    acts = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path, bone_heuristic='BLENDER')
    return [o for o in bpy.data.objects if o not in before], [a for a in bpy.data.actions if a not in acts]


objs, _ = imp(SRC)
arm = next(o for o in objs if o.type == 'ARMATURE')
own_actions = set(bpy.data.actions)
pool = {}
for path in (UAL1, UAL2):
    o2, acts = imp(path)
    for a in acts:
        nm = a.name.split("|")[-1]
        nm = nm.split("_Armature")[0]          # the importer names them "<clip>_Armature.001"
        pool.setdefault(nm, a)
    for o in o2:
        bpy.data.objects.remove(o, do_unlink=True)
print("UAL clips available:", len(pool), sorted(pool)[:8])

arm.animation_data_create()
arm.animation_data.action = None
made = []
for name, src in WANT.items():
    if src not in pool:
        print("MISSING", src)
        continue
    a = pool[src].copy()
    a.name = name
    for fc in list(a.fcurves):
        dp = fc.data_path
        if dp.endswith(".scale") or (dp.endswith(".location") and '"pelvis"' not in dp):
            a.fcurves.remove(fc)
    tr = arm.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, int(a.frame_range[0]), a)
    tr.mute = True
    made.append(name)
# drop every other action so the exporter carries only these
for a in list(bpy.data.actions):
    if a.name not in made and a not in own_actions:
        bpy.data.actions.remove(a)
print("clips:", made)

bpy.ops.object.select_all(action='DESELECT')
for o in objs:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_animations=True,
                          export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_materials='EXPORT',
                          export_image_format='AUTO', export_yup=True)
print("exported", OUT)
