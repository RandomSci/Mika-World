extends RefCounted
## Do two characters share one clip library, and whose proportions is a Move Library clip baked for? Mika plays the
## clips first (as she does in a fight), then each library's ml_ clip is compared with a fresh bake for each girl's
## own skeleton: the hips height and the arm rotations at three moments. Marks "[bakeshare] ...".
## --held films Luna holding orb_gather moments with her own bake, Mika's bake, then her own again (the final hand
## positions logged); --frozen writes the clip straight onto the bones with every other modifier off, so the film shows
## the bake alone (lab_render.sh bake_share_probe <dir> --held --frozen).

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	var m: WorldCharacter = main.characters.mika
	var l: WorldCharacter = main.characters.luna
	print("[bakeshare] mika signature %s rest %s avatar %s" % [m.skeleton_signature(), MocapBake.rest_key(m.skeleton), m.avatar_path.get_file()])
	print("[bakeshare] luna signature %s rest %s avatar %s" % [l.skeleton_signature(), MocapBake.rest_key(l.skeleton), l.avatar_path.get_file()])
	var lm := m.body_player.get_animation_library("mx")
	var ll := l.body_player.get_animation_library("mx")
	print("[bakeshare] same library object: %s" % str(lm == ll))
	var worst := 0.0
	for n in String(RenderProfile.options.get("clips", "orb_gather,domain_expand,ult_heaven_spear")).split(",", false):
		m.has_clip("ml_" + n)                  # Mika first, as in a fight
		l.has_clip("ml_" + n)
		var a: Animation = l.body_player.get_animation("mx/ml_" + n)
		var own := MocapBake.bake(l.skeleton, WorldCharacter.MOCAP_DIR + n + ".json")
		var hers := MocapBake.bake(m.skeleton, WorldCharacter.MOCAP_DIR + n + ".json")
		for tt in [0.5, 1.5, 2.5]:
			var d_own := _diff(a, own, tt)
			var d_mika := _diff(a, hers, tt)
			worst = maxf(worst, d_own)
			print("[bakeshare] luna plays %s at %.1fs: %.1f deg / %.1f cm from a bake for HER skeleton, %.1f deg / %.1f cm from one for MIKA's" % [
				n, tt, d_own, _hdiff(a, own, tt) * 100.0, d_mika, _hdiff(a, hers, tt) * 100.0])
	t._check(worst < 0.5, "Luna's library clips are baked for her own skeleton (worst %.1f deg off)" % worst)
	if RenderProfile.options.has("held"):
		await _held(t, m, l)


static func _held(t, m: WorldCharacter, l: WorldCharacter) -> void:
	var main = t.main
	var tap := HandTap.new()
	tap.name = "TraceBakeShare"
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 3, "axis_deg": 0.0, "bare": true})
	d.set_process(true)
	var c0: Vector3 = d.center
	d.F.luna.pos = c0
	d.F.mika.pos = c0 + Vector3(9.0, 0, 0)
	await t._wait(0.6)
	(d.F.mika.c as Node3D).visible = false
	for n2 in MeleeFighter.RAW_CLIP_HOLD:
		var mm := l.skeleton.get_node_or_null(n2) as SkeletonModifier3D
		if mm:
			mm.active = false
	l.skeleton.add_child(tap)
	PosePipeline.of(l).arrange()
	var gy := FightDirector.ground_y(l, c0)
	d.cut(d.ft + 0.001, "fixed", "luna", {"pos": Vector3(c0.x + 2.3, gy + 1.15, c0.z), "look": Vector3(c0.x, gy + 1.0, c0.z), "fov": 40.0})
	await t._wait(0.8)
	var n := "orb_gather"
	var clip := "ml_" + n
	l.has_clip(clip)
	var mine: Animation = l.body_player.get_animation("mx/" + clip)
	var foreign := MocapBake.bake(m.skeleton, WorldCharacter.MOCAP_DIR + n + ".json")
	l._retarget_paths(foreign, String(l.avatar.get_path_to(l.skeleton)), true)
	var lib := l.body_player.get_animation_library("mx")
	# every track of the two bakes compared (not only the arms)
	for tt2 in [0.7, 1.3, 1.9, 2.5]:
		var worst2 := 0.0
		var wb := ""
		for i in mine.get_track_count():
			var path := String(mine.track_get_path(i))
			var j := foreign.find_track(NodePath(path), mine.track_get_type(i))
			if j < 0:
				continue
			var dv := 0.0
			if mine.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				dv = rad_to_deg(mine.rotation_track_interpolate(i, tt2).angle_to(foreign.rotation_track_interpolate(j, tt2)))
			elif mine.track_get_type(i) == Animation.TYPE_POSITION_3D:
				dv = (mine.position_track_interpolate(i, tt2) as Vector3).distance_to(foreign.position_track_interpolate(j, tt2)) * 100.0
			if dv > worst2:
				worst2 = dv
				wb = path.get_slice(":", 1)
		print("[bakeshare] all tracks at %.1fs: worst %.1f (deg, or cm for the hips) on %s; tracks own %d foreign %d" % [tt2, worst2, wb, mine.get_track_count(), foreign.get_track_count()])
	# Frozen: every other modifier off, the clip written straight onto the bones (rest first), so the frame shown is the
	# bake and nothing else (the live layers move a held frame by up to 20 cm between two identical holds).
	# --layers: a tap after every modifier, so the stage that makes two identical holds differ is named
	var layer_taps := []
	if RenderProfile.options.has("layers"):
		var mods := []
		for c in l.skeleton.get_children():
			if c is SkeletonModifier3D and c != tap:
				mods.append(c)
		for m2 in mods:
			var lt := HandTap.new()
			lt.name = "LayerTap_" + String(m2.name)
			l.skeleton.add_child(lt)
			l.skeleton.move_child(lt, (m2 as Node).get_index() + 1)
			layer_taps.append(lt)
		var order := PackedStringArray()
		for c in l.skeleton.get_children():
			if c is SkeletonModifier3D:
				order.append("%s%s" % [c.name, "" if (c as SkeletonModifier3D).active else " (off)"])
		print("[bakeshare] layer order %s" % ", ".join(order))
	var frozen := RenderProfile.options.has("frozen")
	if frozen:
		for c in l.skeleton.get_children():
			if c is SkeletonModifier3D and c != tap:
				(c as SkeletonModifier3D).active = false
		tap.active = true
	for which in ["own", "mika", "own2"]:
		var use: Animation = foreign if which == "mika" else mine
		lib.remove_animation(clip)
		lib.add_animation(clip, use)
		var tt := 0.7
		while tt <= 3.61:
			if frozen:
				tap.anim = use
				tap.t = tt
			else:
				d.anim("luna", clip, tt, tt + 0.001, 0.01, 0.01)
			await t._wait(0.5)
			print("[bakeshare] held %s %.1f at frame %d  right hand %s left hand %s (skeleton space, final pose)" % [which, tt, Engine.get_frames_drawn(),
				str(tap.pos.get("RightHand", Vector3.ZERO).snapped(Vector3.ONE * 0.001)), str(tap.pos.get("LeftHand", Vector3.ZERO).snapped(Vector3.ONE * 0.001))])
			for lt in layer_taps:
				print("[bakeshare] layer %s %.1f %s R %s L %s" % [which, tt, String(lt.name).trim_prefix("LayerTap_"),
					str(lt.pos.get("RightHand", Vector3.ZERO)), str(lt.pos.get("LeftHand", Vector3.ZERO))])
			await t._wait(0.5)
			tt += 0.3
	tap.anim = null
	lib.remove_animation(clip)
	lib.add_animation(clip, mine)
	d.teardown()


static func _track(a: Animation, bone: String, ty: int) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == ty and String(a.track_get_path(i)).ends_with(":" + bone):
			return i
	return -1


## The largest arm / spine rotation difference between two bakes at time tt (deg).
static func _diff(a: Animation, b: Animation, tt: float) -> float:
	var w := 0.0
	for bone in ["RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand", "Spine", "Chest"]:
		var ia := _track(a, bone, Animation.TYPE_ROTATION_3D)
		var ib := _track(b, bone, Animation.TYPE_ROTATION_3D)
		if ia < 0 or ib < 0:
			continue
		w = maxf(w, rad_to_deg(a.rotation_track_interpolate(ia, tt).angle_to(b.rotation_track_interpolate(ib, tt))))
	return w


## The hips height difference (m).
static func _hdiff(a: Animation, b: Animation, tt: float) -> float:
	var ia := _track(a, "Hips", Animation.TYPE_POSITION_3D)
	var ib := _track(b, "Hips", Animation.TYPE_POSITION_3D)
	if ia < 0 or ib < 0:
		return 0.0
	return absf((a.position_track_interpolate(ia, tt) as Vector3).y - (b.position_track_interpolate(ib, tt) as Vector3).y)



class HandTap extends SkeletonModifier3D:
	var pos := {}
	var anim: Animation = null     ## (frozen mode) written onto the bones at time t, from rest
	var t := 0.0

	func _process_modification() -> void:
		var sk := get_skeleton()
		if anim:
			sk.reset_bone_poses()
			for i in anim.get_track_count():
				var bi := sk.find_bone(String(anim.track_get_path(i).get_concatenated_subnames()))
				if bi < 0:
					continue
				if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
					sk.set_bone_pose_rotation(bi, anim.rotation_track_interpolate(i, t))
				elif anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
					sk.set_bone_pose_position(bi, anim.position_track_interpolate(i, t))
		for b in ["LeftHand", "RightHand"]:
			pos[b] = sk.get_bone_global_pose(sk.find_bone(b)).origin
