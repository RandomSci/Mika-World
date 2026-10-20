"""Mika L1 v2 parts, step 1a in Blender (Selwyn 2026-10-20): turn a cleaned part (v2_clean.py npz) into one flat
material per palette colour with no texture.
  - builds the mesh with a material index per face,
  - planar dissolve (0.2 degrees, delimited by material) removes the refinement edges again, so only the
    straight colour border cuts stay, then triangulates,
  - smooth shading with sharp edges above 50 degrees,
  - exports <out>/<part>.glb and saves <out>/<part>.blend.
  blender -b -P tools/v2_build.py -- <npz> <out dir> [--extra part_fix.py] [--no-dissolve] [--target tris]"""
import sys, os, math
import numpy as np
import bpy, bmesh

PAL_HEX = {'white': 'F4F4FA', 'navy': '1C2556', 'gold': 'D8B26A', 'sky': '6FA8E8'}
NAMES = list(PAL_HEX)


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def palette_material(name):
    m = bpy.data.materials.get('MIKA_L1_' + name) or bpy.data.materials.new('MIKA_L1_' + name)
    h = PAL_HEX[name]
    rgb = [srgb_to_lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)]
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*rgb, 1)
    b.inputs['Metallic'].default_value = 0.0
    b.inputs['Roughness'].default_value = 1.0
    m.diffuse_color = (*rgb, 1)
    m.use_backface_culling = False
    return m


def build(npz, part):
    d = np.load(npz)
    V, F, lab = d['V'], d['F'], d['lab']
    me = bpy.data.meshes.new(part)
    me.from_pydata(V.tolist(), [], F.tolist())
    for n in NAMES:
        me.materials.append(palette_material(n))
    me.polygons.foreach_set('material_index', lab.astype(np.int32))
    ob = bpy.data.objects.new(part, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def tidy(ob, dissolve=True):
    me = ob.data
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    n0 = len(bm.faces)
    if dissolve:
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.2), verts=bm.verts, edges=bm.edges, delimit={'MATERIAL'})
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method='BEAUTY', ngon_method='BEAUTY')
    n1 = len(bm.faces)
    bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(50))
    return n0, n1


def decimate(ob, target):
    """plain collapse decimate to about target triangles. It already keeps material borders (checked on the
    bow at 0.35); locking the border vertices made the rest facet, so nothing is locked."""
    me = ob.data
    if len(me.polygons) <= target:
        return len(me.polygons)
    mod = ob.modifiers.new('dec', 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'; mod.ratio = target / len(me.polygons); mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier='dec')
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(50))
    return len(me.polygons)


def used_materials_only(ob):
    me = ob.data
    used = sorted({p.material_index for p in me.polygons})
    remap = {old: new for new, old in enumerate(used)}
    mats = [me.materials[i] for i in used]
    idx = [remap[p.material_index] for p in me.polygons]
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    me.polygons.foreach_set('material_index', idx)


def export(ob, out, part):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=f'{out}/{part}.glb', export_format='GLB', use_selection=True,
                              export_texcoords=False, export_normals=True, export_materials='EXPORT', export_yup=True,
                              export_apply=True)
    bpy.ops.wm.save_as_mainfile(filepath=f'{out}/{part}.blend')


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    npz, out = argv[0], argv[1]
    extra = argv[argv.index('--extra') + 1] if '--extra' in argv else None
    os.makedirs(out, exist_ok=True)
    part = os.path.basename(npz)[:-4]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ob = build(npz, part)
    # npz is in glTF space (Y up); rotate to Blender Z up so the exporter writes it back unchanged
    ob.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.view_layer.objects.active = ob; ob.select_set(True)
    bpy.ops.object.transform_apply(rotation=True)
    if extra:
        g = {'ob': ob, 'part': part, 'np': np, 'bpy': bpy, 'bmesh': bmesh, 'math': math}
        exec(open(extra).read(), g)
    n0, n1 = tidy(ob, dissolve='--no-dissolve' not in argv)
    n2 = decimate(ob, int(argv[argv.index('--target') + 1])) if '--target' in argv else n1
    used_materials_only(ob)
    export(ob, out, part)
    print(f'BUILD {part} faces {n0} -> {n1} -> {n2} materials {[m.name for m in ob.data.materials]}')


main()
