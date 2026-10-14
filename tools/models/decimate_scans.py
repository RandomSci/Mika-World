"""Real-time versions of the Poly Haven scans used en masse in the realistic forest (realism pass): each scan is
decimated to a triangle budget (planar + collapse), keeping UVs and materials, and exported as a GLB.

  blender -b --python tools/models/decimate_scans.py -- <out_dir>
"""
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "."
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
JOBS = [("fern_02", "1k", 1400), ("nettle_plant", "1k", 1800), ("shrub_02", "1k", 3000), ("rock_moss_set_01", "2k", 6000), ("rock_moss_set_02", "2k", 6000)]
for aid, res, budget in JOBS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = os.path.join(ROOT, "assets/polyhaven/models", aid, "%s_%s.gltf" % (aid, res))
    if not os.path.exists(src):
        src = os.path.join(ROOT, "assets/polyhaven/models", aid, "%s_1k.gltf" % aid)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    total = sum(len(o.data.polygons) for o in meshes)
    for o in meshes:
        share = budget * len(o.data.polygons) / max(total, 1)
        ratio = min(1.0, share / max(len(o.data.polygons), 1))
        if ratio < 1.0:
            m = o.modifiers.new("Dec", 'DECIMATE')
            m.ratio = ratio
            m.use_collapse_triangulate = True
    bpy.ops.object.select_all(action='SELECT')
    out = os.path.join(OUT, aid + "_low.glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
                              export_image_format='JPEG', export_jpeg_quality=88)
    print("DECIMATED", aid, total, "->", sum(len(o.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.polygons) for o in meshes))
