"""Mika L1 v2 parts, face budget (Selwyn 2026-10-20): low poly bake target for one part.
Takes the original Meshy shape, welds it, decimates to the target triangle count, gives it fresh non overlapping UVs
(smart project, then packed with a 16 px gap at 4K) and saves <out>/<part>.blend for v2_bake.py.
Also writes <out>/<part>_uv.npz (loop uvs per triangle) so the UV layout can be checked without Blender.
  blender -b -P tools/v2_lowpoly.py -- <meshy glb> <out dir> <target tris>"""
import sys, os, math
import numpy as np
import bpy, bmesh

TEX = 4096
GAP_PX = 18                      # packing gap, checked afterwards to be at least 16 px

argv = sys.argv[sys.argv.index('--') + 1:]
src, out, target = argv[0], argv[1], int(argv[2])
part = os.path.basename(src)[:-4]
os.makedirs(out, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
ob.name = part
me = ob.data
me.materials.clear()
while me.uv_layers:
    me.uv_layers.remove(me.uv_layers[0])
bpy.context.view_layer.objects.active = ob; ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

bm = bmesh.new(); bm.from_mesh(me)
ext = max(ob.dimensions)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=ext * 5e-6)      # Meshy splits vertices at its UV seams
bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=ext * 1e-6)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.to_mesh(me); bm.free()
n0 = len(me.polygons)

if n0 > target:
    mod = ob.modifiers.new('dec', 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'; mod.ratio = target / n0; mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier='dec')
for p in me.polygons:
    p.use_smooth = True
me.set_sharp_from_angle(angle=math.radians(50))
n1 = len(me.polygons)

me.uv_layers.new(name='UVMap')
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66), margin_method='FRACTION', island_margin=GAP_PX / TEX,
                         area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
bpy.ops.uv.select_all(action='SELECT')
bpy.ops.uv.pack_islands(rotate=True, margin_method='FRACTION', margin=GAP_PX / TEX, shape_method='CONCAVE')
bpy.ops.object.mode_set(mode='OBJECT')

uv = np.zeros(len(me.loops) * 2); me.uv_layers[0].data.foreach_get('uv', uv)
co = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get('co', co)
tri = np.zeros(len(me.polygons) * 3, np.int64); me.polygons.foreach_get('vertices', tri)
np.savez(f'{out}/{part}_uv.npz', UV=uv.reshape(-1, 3, 2), V=co.reshape(-1, 3), F=tri.reshape(-1, 3))
bpy.ops.wm.save_as_mainfile(filepath=f'{out}/{part}.blend')
print(f'LOWPOLY {part} meshy {n0} -> {n1} tris')
