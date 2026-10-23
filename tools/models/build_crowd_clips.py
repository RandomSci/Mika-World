"""Crowd reactions for the townsfolk (Selwyn 23 Oct: about 40 light townsfolk per busy place, an audience for the
glade festival). The Universal Animation Library has no clapping, cheering or waving, so they are made here on the
same UAL skeleton every resident uses: the idle clip for the body, the arms steered by IK to hand targets (two hands
meeting in front of the chest for a clap, both raised and shaking for a cheer, one raised and swaying for a wave),
baked to plain bone rotations. One GLB with just the armature and the three clips; at runtime FolkCrowd adds its
AnimationLibrary to every townsfolk's AnimationPlayer (the bone names are the same).
  blender -b --factory-startup --python tools/models/build_crowd_clips.py -- <resident.glb> <UAL1.glb> <out.glb>
"""
import bpy, sys, math
from mathutils import Vector, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
RES, UAL1, OUT = argv[:3]
FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS


def imp(path):
	before = set(bpy.data.objects)
	acts0 = set(bpy.data.actions)
	bpy.ops.import_scene.gltf(filepath=path)
	return [o for o in bpy.data.objects if o not in before], [a for a in bpy.data.actions if a not in acts0]


objs, _ = imp(RES)
arm = next(o for o in objs if o.type == 'ARMATURE')
for o in objs:
	if o != arm and o.type == 'MESH':
		pass
# the idle body from the library
o2, acts = imp(UAL1)
idle = next(a for a in acts if a.name.split("|")[-1].startswith("Idle_Loop"))
for o in o2:
	bpy.data.objects.remove(o, do_unlink=True)
for a in list(bpy.data.actions):
	if a != idle:
		bpy.data.actions.remove(a)
arm.animation_data_create()
for tr in list(arm.animation_data.nla_tracks):
	arm.animation_data.nla_tracks.remove(tr)

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
pb = arm.pose.bones


def world(bone_name):
	return arm.matrix_world @ pb[bone_name].head


def empty(name):
	e = bpy.data.objects.new(name, None)
	bpy.context.scene.collection.objects.link(e)
	return e


def ik(side, target, pole):
	c = pb["lowerarm_" + side].constraints.new('IK')
	c.target = target
	c.pole_target = pole
	c.pole_angle = math.radians(-90 if side == "l" else -90)
	c.chain_count = 2
	return c


def make(name, frames, hand_path, pole_off, hands=("l", "r"), palm_roll=None):
	"""hand_path(side, t 0..1) -> world position of that hand; arms baked by IK over the idle body."""
	arm.animation_data.action = idle
	bpy.context.scene.frame_set(0)
	tg = {s: empty("tgt_%s_%s" % (name, s)) for s in hands}
	po = {s: empty("pole_%s_%s" % (name, s)) for s in hands}
	cons = []
	for s in hands:
		cons.append(ik(s, tg[s], po[s]))
	sh = {s: world("upperarm_" + s) for s in hands}
	for f in range(frames + 1):
		bpy.context.scene.frame_set(f % int(idle.frame_range[1] + 1))
		t = f / frames
		for s in hands:
			tg[s].location = hand_path(s, t)
			tg[s].keyframe_insert("location", frame=f)
			sign = 1 if s == "l" else -1
			po[s].location = sh[s] + Vector((sign * pole_off[0], pole_off[1], pole_off[2]))
			po[s].keyframe_insert("location", frame=f)
	bpy.context.scene.frame_start = 0
	bpy.context.scene.frame_end = frames
	for b in pb:
		b.bone.select = True
	bpy.ops.nla.bake(frame_start=0, frame_end=frames, only_selected=False, visual_keying=True, clear_constraints=False,
		use_current_action=False, bake_types={'POSE'})
	baked = arm.animation_data.action
	baked.name = name
	for c in cons:
		c.id_data.pose.bones[c.owner.name if hasattr(c, "owner") else ""] if False else None
	for s in hands:
		for c in list(pb["lowerarm_" + s].constraints):
			pb["lowerarm_" + s].constraints.remove(c)
		bpy.data.objects.remove(tg[s], do_unlink=True)
		bpy.data.objects.remove(po[s], do_unlink=True)
	# open hands, palms turned (the idle's fists made the clap a boxing guard and the wave a raised fist)
	if palm_roll is not None:
		for fc in list(baked.fcurves):
			bn = fc.data_path.split('"')[1] if '"' in fc.data_path else ""
			if any(bn.startswith(f) for f in ("index_", "middle_", "ring_", "pinky_", "thumb_")) and bn[-1] in hands:
				baked.fcurves.remove(fc)
		for s in hands:
			for b in pb:
				if any(b.name.startswith(f) for f in ("index_", "middle_", "ring_", "pinky_", "thumb_")) and b.name.endswith("_" + s):
					b.rotation_mode = 'QUATERNION'
					b.rotation_quaternion = (1, 0, 0, 0) if not b.name.startswith("thumb_") else Quaternion(Vector((1, 0, 0)), math.radians(-12))
					for f in (0, frames):
						b.keyframe_insert("rotation_quaternion", frame=f, group=b.name)
			# the palm turned about the forearm (roll on the hand bone's own Y axis), on top of the baked hand rotation
			hb = pb["hand_" + s]
			hb.rotation_mode = 'QUATERNION'
			roll = Quaternion(Vector((0, 1, 0)), math.radians(palm_roll * (1 if s == "l" else -1)))
			for f in range(frames + 1):
				bpy.context.scene.frame_set(f)
				hb.rotation_quaternion = hb.rotation_quaternion @ roll
				hb.keyframe_insert("rotation_quaternion", frame=f, group=hb.name)
	# only rotations (as the library's clips: no bone stretching, the pelvis keeps the idle's own motion)
	for fc in list(baked.fcurves):
		dp = fc.data_path
		if dp.endswith(".scale") or (dp.endswith(".location") and '"pelvis"' not in dp and '"root"' not in dp):
			baked.fcurves.remove(fc)
	tr = arm.animation_data.nla_tracks.new()
	tr.name = name
	tr.strips.new(name, 0, baked)
	tr.mute = True
	arm.animation_data.action = None
	return baked


chest = world("spine_03")
fwd = Vector((0, -1, 0))        # glTF import: the character faces -Y in Blender
up = Vector((0, 0, 1))
right = Vector((-1, 0, 0))


def clap(side, t):
	# 6 claps in 2 s: hands meet 30 cm in front of the chest, part to 24 cm apart
	sign = 1 if side == "l" else -1
	k = 0.5 - 0.5 * math.cos(t * 6 * 2 * math.pi)
	gap = 0.015 + 0.11 * k
	return chest + fwd * 0.3 + up * (0.02 + 0.02 * k) + right * (-sign) * gap


def cheer(side, t):
	sign = 1 if side == "l" else -1
	shake = math.sin(t * 4 * 2 * math.pi)
	return chest + up * (0.62 + 0.05 * shake) + right * (-sign) * (0.32 + 0.04 * shake) + fwd * 0.08


def wave(side, t):
	sway = math.sin(t * 3 * 2 * math.pi)
	return chest + up * 0.45 + right * (0.42 + 0.12 * sway) + fwd * 0.12


make("clap", 2 * FPS, clap, (0.15, 0.35, -0.2), palm_roll=float(__import__("os").environ.get("CLAP_ROLL", "90")))
make("cheer", 2 * FPS, cheer, (0.25, 0.2, -0.3))
make("wave", 2 * FPS, wave, (0.25, 0.25, -0.3), hands=("r",), palm_roll=float(__import__("os").environ.get("WAVE_ROLL", "0")))

bpy.ops.object.mode_set(mode='OBJECT')
for o in bpy.context.view_layer.objects:
	o.select_set(o == arm or (o.type == 'MESH' and o.parent == arm))
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_animations=True,
	export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_materials='EXPORT', export_yup=True)
print("exported", OUT)
