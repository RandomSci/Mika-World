"""Human rivals for Mika World's ambushes (the developer: "adventurers or groups that tried to rob them ... assassins,
sword techniques, different kinds of black magic, fast movements, like in real anime").

Assembles one rigged, animated character from Quaternius's CC0 kits that share the Unreal-style UAL skeleton:
  * an OUTFIT (Modular Character Outfits - Fantasy: ranger / peasant, male / female),
  * the HEAD of a Universal Base Character body (the rest of that body is cut away: only verts weighted to the
    head / neck are kept, so nothing clips through the clothes),
  * HAIR / beard / eyebrows rigged to the head bone,
  * the Universal Animation Library 1 + 2 clips a fighter needs (sword combos, dashes, rolls, ninja jumps, slides,
    spell casting, throws, hits, falls, get-up, death) baked as NLA tracks (rotations + the pelvis's own motion),
and exports one GLB. Colours of the outfit can be re-tinted (a dark-mage robe, an assassin's black).

  blender -b --factory-startup --python tools/models/build_rival.py -- <outfit.gltf> <body.gltf> <hair1.gltf,hair2.gltf|-> <UAL1.glb> <UAL2.glb> <out.glb> '<json opts>'
  opts: {"tint": {"material_name_prefix": [r, g, b]}, "darken": 0.0..1.0}
"""
import json
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
OUTFIT, BODY, HAIRS, UAL1, UAL2, OUT = argv[:6]
OPTS = json.loads(argv[6]) if len(argv) > 6 else {}

CLIPS = {
	# locomotion
	"idle": "Sword_Idle", "idle_unarmed": "Idle_Loop", "idle_arms": "Idle_FoldArms_Loop", "talk": "Idle_Talking_Loop",
	"walk": "Walk_Loop", "run": "Jog_Fwd_Loop", "sprint": "Sprint_Loop", "sneak": "Crouch_Fwd_Loop", "crouch": "Crouch_Idle_Loop",
	# blade work
	"slash_a": "Sword_Regular_A", "slash_b": "Sword_Regular_B", "slash_c": "Sword_Regular_C", "combo": "Sword_Regular_Combo",
	"heavy_combo": "Sword_Heavy_Combo", "dash_strike": "Sword_Dash", "thrust": "Sword_Attack", "block": "Sword_Block",
	"hook": "Melee_Hook", "jab": "Punch_Jab", "cross": "Punch_Cross", "throw": "OverhandThrow",
	# fast movement
	"roll": "Roll", "leap_start": "NinjaJump_Start", "leap_air": "NinjaJump_Idle_Loop", "leap_land": "NinjaJump_Land",
	"slide_start": "Slide_Start", "slide": "Slide_Loop", "slide_exit": "Slide_Exit",
	# magic
	"cast_enter": "Spell_Simple_Enter", "cast_idle": "Spell_Simple_Idle_Loop", "cast": "Spell_Simple_Shoot", "cast_exit": "Spell_Simple_Exit",
	# taking it
	"hit": "Hit_Chest", "hit_head": "Hit_Head", "knockback": "Hit_Knockback", "stagger": "Idle_Shield_Break", "death": "Death01",
	"get_up": "LayToIdle", "yes": "Yes", "no": "Idle_No",
}

# TOWNSFOLK (opts {"clipset": "townsfolk"}): the same builder makes the village's and the academy's residents -
# everyday work and rest instead of blade work (TownLife, data/residents.json)
TOWNSFOLK = {
	"idle": "Idle_Loop", "idle_arms": "Idle_FoldArms_Loop", "talk": "Idle_Talking_Loop", "walk": "Walk_Loop",
	"walk_formal": "Walk_Formal_Loop", "run": "Jog_Fwd_Loop", "carry": "Walk_Carry_Loop", "push": "Push_Loop",
	"sit_enter": "Sitting_Enter", "sit": "Sitting_Idle_Loop", "sit_talk": "Sitting_Talking_Loop", "sit_exit": "Sitting_Exit",
	"interact": "Interact", "pickup": "PickUp_Table", "open": "Chest_Open", "drink": "Consume",
	"harvest": "Farm_Harvest", "plant": "Farm_PlantSeed", "water": "Farm_Watering", "chop": "TreeChopping_Loop",
	"fix": "Fixing_Kneeling", "crouch": "Crouch_Idle_Loop", "lantern": "Idle_Lantern_Loop", "torch": "Idle_Torch_Loop",
	"lean_rail": "Idle_Rail_Loop", "call_rail": "Idle_Rail_Call", "dance": "Dance_Loop",
	"cast_enter": "Spell_Simple_Enter", "cast_idle": "Spell_Simple_Idle_Loop", "cast": "Spell_Simple_Shoot", "cast_exit": "Spell_Simple_Exit",
	"yes": "Yes", "no": "Idle_No_Loop", "hit": "Hit_Chest", "death": "Death01", "get_up": "LayToIdle", "flee": "Sprint_Loop",
}
if OPTS.get("clipset") == "townsfolk":
	CLIPS = TOWNSFOLK

bpy.ops.wm.read_factory_settings(use_empty=True)


def imp(path):
	before = set(bpy.data.objects)
	acts = set(bpy.data.actions)
	bpy.ops.import_scene.gltf(filepath=path, bone_heuristic='BLENDER')
	return [o for o in bpy.data.objects if o not in before], [a for a in bpy.data.actions if a not in acts]


outfit, _ = imp(OUTFIT)
arm = next(o for o in outfit if o.type == 'ARMATURE')
keep = [o for o in outfit if o.type == 'MESH']

# the head of the base body: keep only the vertices that the head and neck move
body, _ = imp(BODY)
body_arm = next((o for o in body if o.type == 'ARMATURE'), None)
for o in body:
	if o.type != 'MESH':
		continue
	vg = {g.index: g.name for g in o.vertex_groups}
	head_ids = {i for i, n in vg.items() if n in ("Head", "neck_01", "neck_02")}
	import bmesh
	bm = bmesh.new()
	bm.from_mesh(o.data)
	deform = bm.verts.layers.deform.active
	kill = []
	for v in bm.verts:
		w = sum(wt for gi, wt in v[deform].items() if gi in head_ids) if deform else 0.0
		if w < 0.45:
			kill.append(v)
	# keep a little more below the jaw on the neck so the collar covers the cut
	bmesh.ops.delete(bm, geom=kill, context='VERTS')
	bm.to_mesh(o.data)
	bm.free()
	if len(o.data.vertices) == 0:
		bpy.data.objects.remove(o, do_unlink=True)
		continue
	for m in o.modifiers:
		if m.type == 'ARMATURE':
			m.object = arm
	o.parent = arm
	keep.append(o)
if body_arm:
	bpy.data.objects.remove(body_arm, do_unlink=True)

for hp in [h for h in HAIRS.split(",") if h and h != "-"]:
	hair, _ = imp(hp)
	harm = next((o for o in hair if o.type == 'ARMATURE'), None)
	for o in hair:
		if o.type == 'MESH':
			for m in o.modifiers:
				if m.type == 'ARMATURE':
					m.object = arm
			if o.parent and o.parent.type == 'ARMATURE':
				o.parent = arm
			keep.append(o)
	if harm:
		bpy.data.objects.remove(harm, do_unlink=True)

# tints: outfit materials re-coloured (multiplied over their own textures) by name prefix
tint = OPTS.get("tint", {})
for o in keep:
	for slot in o.material_slots:
		m = slot.material
		if m is None or not m.use_nodes:
			continue
		for pre, col in tint.items():
			if m.name.startswith(pre):
				b = m.node_tree.nodes.get("Principled BSDF")
				if b is None:
					continue
				src = b.inputs["Base Color"].links[0].from_socket if b.inputs["Base Color"].is_linked else None
				mix = m.node_tree.nodes.new("ShaderNodeMix")
				mix.data_type = 'RGBA'
				mix.blend_type = 'MULTIPLY'
				mix.inputs["Factor"].default_value = 1.0
				mix.inputs[7].default_value = (col[0], col[1], col[2], 1.0)
				if src:
					m.node_tree.links.new(src, mix.inputs[6])
				else:
					mix.inputs[6].default_value = b.inputs["Base Color"].default_value
				m.node_tree.links.new(mix.outputs[2], b.inputs["Base Color"])

# the clips
own = set(bpy.data.actions)
pool = {}
for path in (UAL1, UAL2):
	o2, acts = imp(path)
	for a in acts:
		nm = a.name.split("|")[-1].split("_Armature")[0]
		pool.setdefault(nm, a)
	for o in o2:
		bpy.data.objects.remove(o, do_unlink=True)
arm.animation_data_create()
arm.animation_data.action = None
made = []
for name, src in CLIPS.items():
	if src not in pool:
		print("MISSING", src)
		continue
	a = pool[src].copy()
	a.name = name
	for fc in list(a.fcurves):
		dp = fc.data_path
		if dp.endswith(".scale") or (dp.endswith(".location") and '"pelvis"' not in dp and '"root"' not in dp):
			a.fcurves.remove(fc)
	tr = arm.animation_data.nla_tracks.new()
	tr.name = name
	tr.strips.new(name, int(a.frame_range[0]), a)
	tr.mute = True
	made.append(name)
for a in list(bpy.data.actions):
	if a.name not in made and a not in own:
		bpy.data.actions.remove(a)
print("clips:", len(made), made)

for o in bpy.context.view_layer.objects:
	o.select_set(o == arm or o in keep)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_animations=True,
	export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_materials='EXPORT', export_image_format='AUTO', export_yup=True)
print("exported", OUT, "meshes", [o.name for o in keep])
