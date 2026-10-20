"""Mika L1 v2 parts, face budget (Selwyn 2026-10-20): the game part. Low poly (v2_lowpoly.py) with its xatlas uvs
(v2_uv.py) and the snapped 4K bake (v2_snap.py) as its only texture, exported as <out>/<part>.glb plus .blend.
  blender -b -P tools/v2_final.py -- <low.blend> <uv.npz> <snapped.png> <out dir>"""
import sys, os
import numpy as np
import bpy

argv = sys.argv[sys.argv.index('--') + 1:]
low_blend, uvnpz, png, out = argv[:4]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=low_blend)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
part = ob.name
me = ob.data
me.uv_layers[0].data.foreach_set('uv', np.load(uvnpz)['UV'].reshape(-1))

img = bpy.data.images.load(os.path.abspath(png)); img.name = part + '_col'
img.pack()
mat = bpy.data.materials.new(part); mat.use_nodes = True
bsdf = mat.node_tree.nodes['Principled BSDF']
bsdf.inputs['Metallic'].default_value = 0.0; bsdf.inputs['Roughness'].default_value = 1.0
tn = mat.node_tree.nodes.new('ShaderNodeTexImage'); tn.image = img
mat.node_tree.links.new(tn.outputs['Color'], bsdf.inputs['Base Color'])
mat.use_backface_culling = False
me.materials.clear(); me.materials.append(mat)

bpy.ops.object.select_all(action='DESELECT')
ob.select_set(True); bpy.context.view_layer.objects.active = ob
bpy.ops.export_scene.gltf(filepath=f'{out}/{part}.glb', export_format='GLB', use_selection=True,
                          export_texcoords=True, export_normals=True, export_materials='EXPORT', export_yup=True,
                          export_image_format='AUTO', export_apply=True)
bpy.ops.wm.save_as_mainfile(filepath=f'{out}/{part}.blend')
print(f'FINAL {part} tris {len(me.polygons)}')
