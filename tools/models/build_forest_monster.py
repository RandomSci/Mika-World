"""The MOSSBACK (Mika World's Whispering Woods brute) from OpenGameArt's "Forest Monster" by Cestmir Dammer (CDmir),
CC0 (https://opengameart.org/content/forest-monster; the archive's Licenses.txt: "License: Creative Commons (CC0)").
A rigged, animated, textured stone-and-moss troll with a tree growing from its back.

The 2015 .blend uses Blender Internal materials (no nodes) and a scene full of rig helpers; this rebuilds PBR
materials from its own textures (skin with its baked AO multiplied in, normal maps, the tree's leaf cards alpha-
clipped), drops the helpers, splits the authored animation into the game's clip set as NLA tracks (Attack's own
charge / strike / cooldown sub-ranges, per the author's notes) and exports one GLB.

  blender -b <forest-monster-final.blend> --python tools/models/build_forest_monster.py -- <out.glb>
"""
import os
import sys

import bpy
import numpy as np

OUT = sys.argv[sys.argv.index("--") + 1]
D = os.path.dirname(bpy.data.filepath)
TX = os.path.join(D, "texture")
WORK = os.path.join(os.path.expanduser("~/.cache"), "mika_mossback_tex")
os.makedirs(WORK, exist_ok=True)

# skin x AO (the glTF exporter has no AO input from plain nodes; the occlusion is baked into the colour)
def px(path, colour=True):
	im = bpy.data.images.load(path)
	if not colour:
		im.colorspace_settings.name = "Non-Color"
	a = np.array(im.pixels[:], dtype=np.float32).reshape(im.size[1], im.size[0], 4)
	return im, a


def save(a, name, colour=True):
	h, w = a.shape[:2]
	im = bpy.data.images.new(name, w, h, alpha=True)
	if not colour:
		im.colorspace_settings.name = "Non-Color"
	im.pixels[:] = a.ravel()
	im.filepath_raw = os.path.join(WORK, name)
	im.file_format = "PNG"
	im.save()


_, sk = px(os.path.join(TX, "forest-monster-skin.png"))
_, ao = px(os.path.join(TX, "forest-monster-AO.png"), False)
out = sk.copy()
out[..., :3] = sk[..., :3] * (0.31 + 0.69 * ao[..., :3])          # soften: AO 0 -> 31 % (not black)
out[..., 3] = 1.0
save(out, "mossback_albedo.png")
_, nrm = px(os.path.join(TX, "forest-monster-norm.png"), False)
nrm[..., 3] = 1.0
save(nrm, "mossback_normal.png", False)
_, spec = px(os.path.join(TX, "forest-monster-spec.png"), False)
r = 1.0 - spec[..., :1] * 0.6
rough = np.concatenate([r, r, r, np.ones_like(r)], axis=2)
save(rough, "mossback_rough.png", False)
_, lv = px(os.path.join(TX, "tree.png"))
save(lv, "mossback_leaves.png")
_, ln = px(os.path.join(TX, "tree-norm.png"), False)
ln[..., 3] = 1.0
save(ln, "mossback_leaves_normal.png", False)


def mat(name, albedo, normal, rough=None, alpha=False):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	b = nt.nodes["Principled BSDF"]
	t = nt.nodes.new("ShaderNodeTexImage")
	t.image = bpy.data.images.load(os.path.join(WORK, albedo))
	nt.links.new(t.outputs[0], b.inputs["Base Color"])
	if alpha:
		nt.links.new(t.outputs[1], b.inputs["Alpha"])
		m.blend_method = 'CLIP'
		m.alpha_threshold = 0.5
	n = nt.nodes.new("ShaderNodeTexImage")
	n.image = bpy.data.images.load(os.path.join(WORK, normal))
	n.image.colorspace_settings.name = "Non-Color"
	nm = nt.nodes.new("ShaderNodeNormalMap")
	nt.links.new(n.outputs[0], nm.inputs[1])
	nt.links.new(nm.outputs[0], b.inputs["Normal"])
	if rough:
		r = nt.nodes.new("ShaderNodeTexImage")
		r.image = bpy.data.images.load(os.path.join(WORK, rough))
		r.image.colorspace_settings.name = "Non-Color"
		nt.links.new(r.outputs[0], b.inputs["Roughness"])
	else:
		b.inputs["Roughness"].default_value = 0.8
	return m


keep = {"Armature", "Monster", "Tree"}
for o in list(bpy.data.objects):
	if o.name not in keep:
		bpy.data.objects.remove(o, do_unlink=True)
mon = bpy.data.objects["Monster"]
tree = bpy.data.objects["Tree"]
mon.data.materials.clear()
mon.data.materials.append(mat("Mossback_Skin", "mossback_albedo.png", "mossback_normal.png", "mossback_rough.png"))
tree.data.materials.clear()
tree.data.materials.append(mat("Mossback_Leaves", "mossback_leaves.png", "mossback_leaves_normal.png", alpha=True))
arm = bpy.data.objects["Armature"]

# the game's clips: name -> (action, first frame, last frame)
CLIPS = {
	"idle": ("Idle", 0, 190), "walk": ("Walk", 0, 40), "alert": ("Melee_Hold", 0, 50),
	"windup": ("Attack", 0, 10), "strike": ("Attack", 10, 16), "recover": ("Attack", 16, 30),
	"hit": ("Attack", 20, 30), "death": ("Dying", 0, 35),
}
arm.animation_data_create()
arm.animation_data.action = None
for tr in list(arm.animation_data.nla_tracks):
	arm.animation_data.nla_tracks.remove(tr)
for name, (act, a, b) in CLIPS.items():
	tr = arm.animation_data.nla_tracks.new()
	tr.name = name
	st = tr.strips.new(name, a, bpy.data.actions[act])
	st.action_frame_start = a
	st.action_frame_end = b
	st.frame_start = a
	st.frame_end = b
	tr.mute = True
for o in bpy.context.view_layer.objects:
	o.select_set(o in (arm, mon, tree))
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_animations=True,
	export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_materials='EXPORT', export_image_format='AUTO',
	export_yup=True, export_skins=True)
h = max(v.co.z for v in mon.data.vertices) - min(v.co.z for v in mon.data.vertices)
print("exported", OUT, "mesh height (local units)", round(h, 3), "object scale", tuple(round(x, 4) for x in arm.scale), tuple(round(x, 4) for x in mon.scale))
