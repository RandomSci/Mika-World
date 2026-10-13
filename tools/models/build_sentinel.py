"""Builds the Hollow Sentinel (original Mika World creature) as an articulated stone golem and exports a GLB.

Run:  blender -b --python tools/models/build_sentinel.py -- assets/creatures/sentinel/hollow_sentinel.glb

Design: a weathered guardian assembled from rune-cut stones held together by the Sanctuary's old ward-light.
Every limb is a separate rigid piece whose ORIGIN is its joint pivot, parented in a hierarchy, so Godot can
animate it by rotating joints (no skinning: stone does not bend). Node names are the joint names the game
animates: Hips, Torso, Head, Shoulder_L/R, Elbow_L/R, Fist_L/R, Hip_L/R, Knee_L/R. Glowing parts are named
*_Glow (the game gives them the emissive rune material); stone parts get the stone material in Godot.
Units: metres, +Y up in Godot (Blender Z up; the glTF exporter converts). Faces it -Y in Blender = +Z in Godot.
"""
import math
import sys

import bpy
import bmesh
from mathutils import Vector, noise

out = sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
SEED = 7


def rock(name, size, at, parent=None, sub=3, rough=0.18, seed=0, flat_bottom=False):
    """A boulder: subdivided cube, rounded, displaced by layered noise, flat-shaded facets."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=sub, use_grid_fill=True)
    for v in bm.verts:
        d = v.co.normalized()
        v.co = v.co.lerp(d * 0.62, 0.55)                     # round the cube
        n = noise.fractal(d * 2.3 + Vector((seed * 3.1, seed * 1.7, SEED)), 0.6, 2.0, 3)
        v.co += d * n * rough
        if flat_bottom and v.co.z < -0.3:
            v.co.z = -0.3 + (v.co.z + 0.3) * 0.2
        v.co.x *= size[0] / 0.55          # size = half-extents in metres
        v.co.y *= size[1] / 0.55
        v.co.z *= size[2] / 0.55
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.location = at
    if parent:
        ob.parent = parent
    return ob


def joint(name, at, parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(e)
    e.empty_display_size = 0.15
    e.location = at
    if parent:
        e.parent = parent
    return e


def shard(name, at, scale, rot, parent):
    bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=0.5, depth=1.0, location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.name = name
    ob.data.name = name
    ob.scale = scale
    ob.rotation_euler = rot
    ob.location = at
    ob.parent = parent
    return ob


def glow_strip(name, at, size, parent):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.name = name
    ob.data.name = name
    ob.scale = size
    ob.location = at
    ob.parent = parent
    return ob


root = joint("Sentinel", (0, 0, 0))
hips = joint("Hips", (0, 0, 0.95), root)
rock("Pelvis", (0.36, 0.26, 0.18), (0, 0.02, 0.0), hips, seed=1)
torso = joint("Torso", (0, 0, 0.12), hips)
rock("Belly", (0.34, 0.27, 0.2), (0, 0.0, 0.12), torso, seed=4)
rock("Chest", (0.56, 0.4, 0.42), (0, 0.04, 0.56), torso, seed=2, rough=0.22)
rock("Back_Slab", (0.46, 0.18, 0.36), (0, 0.32, 0.66), torso, seed=3)
rock("Hunch", (0.3, 0.22, 0.2), (0, 0.24, 0.95), torso, seed=8)
# the heart crystal (where spells are aimed) and rune seams cut into the front of the chest
shard("Heart_Glow", (0, -0.36, 0.56), (0.13, 0.13, 0.26), (math.radians(90), 0, 0), torso)
glow_strip("Seam_Glow_A", (0.0, -0.37, 0.82), (0.42, 0.03, 0.025), torso)
glow_strip("Seam_Glow_B", (0.0, -0.29, 0.22), (0.3, 0.03, 0.02), torso)
head = joint("Head", (0, -0.12, 0.98), torso)
rock("Skull", (0.2, 0.2, 0.17), (0, -0.02, 0.12), head, seed=5, rough=0.14)
rock("Brow", (0.24, 0.1, 0.06), (0, -0.15, 0.2), head, seed=6, rough=0.1)
glow_strip("Eye_Glow", (0, -0.2, 0.11), (0.2, 0.03, 0.03), head)
for side, sx in (("L", 1), ("R", -1)):
    sh = joint(f"Shoulder_{side}", (sx * 0.66, 0.02, 0.8), torso)
    rock(f"Pauldron_{side}", (0.27, 0.27, 0.22), (sx * 0.06, 0, 0.06), sh, seed=10 + sx, rough=0.22)
    rock(f"UpperArm_{side}", (0.15, 0.15, 0.24), (sx * 0.05, 0, -0.26), sh, seed=12 + sx)
    el = joint(f"Elbow_{side}", (sx * 0.05, 0, -0.5), sh)
    rock(f"Forearm_{side}", (0.17, 0.17, 0.25), (0, 0, -0.22), el, seed=14 + sx)
    glow_strip(f"Wrist_Glow_{side}", (0, 0, -0.44), (0.2, 0.2, 0.025), el)
    fist = joint(f"Fist_{side}", (0, 0, -0.48), el)
    rock(f"Hand_{side}", (0.24, 0.23, 0.22), (0, -0.02, -0.14), fist, seed=16 + sx, rough=0.2)
    hp_ = joint(f"Hip_{side}", (sx * 0.24, 0.02, -0.06), hips)
    rock(f"Thigh_{side}", (0.17, 0.17, 0.22), (0, 0, -0.2), hp_, seed=20 + sx)
    kn = joint(f"Knee_{side}", (0, 0, -0.42), hp_)
    rock(f"Shin_{side}", (0.16, 0.16, 0.2), (0, 0, -0.18), kn, seed=22 + sx)
    rock(f"Foot_{side}", (0.21, 0.27, 0.09), (0, -0.07, -0.4), kn, seed=24 + sx, flat_bottom=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                          export_animations=False, export_materials="NONE")
print("exported", out)
