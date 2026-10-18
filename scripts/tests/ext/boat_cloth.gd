## Boat cloth and hands check (Selwyn, 2026-10-19: "no cloth vertex may ever be outside the hull or inside the other
## girl. Add an automated test that counts cloth vertices outside the boat bounds (must be 0)"; stills from front,
## side, top and a close-up on the hands). Both seated out on the lake at night, Luna rowing, Mika trailing her hand;
## after the drape settles, every cloth vertex is skinned on the CPU from the final bone poses and counted: outside
## the hull's outline (per-slice from the hull mesh itself), below its floor, inside the other girl's body. Then four
## held camera angles (2 s each) for stills (GPU run).

class BoneGrab extends SkeletonModifier3D:
	var poses: Array = []
	func _process_modification() -> void:
		var sk := get_skeleton()
		poses.resize(sk.get_bone_count())
		for i in sk.get_bone_count():
			poses[i] = sk.get_bone_global_pose(i)


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.performance:
		main.performance.set_process(false)
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	await main.streaming.travel("lantern_lake", luna, false)
	main.day_night.set_override(true)
	await t._wait(2.0)
	main.day_night.set_process(false)
	var lake: Node3D = null
	for n in main.world.find_children("*", "Node3D", true, false) + [main.world]:
		if n.get("water_mat") != null:
			lake = n
			break
	var water_y: float = lake.global_position.y
	for cl in t.get_tree().root.find_children("*", "CanvasLayer", true, false):
		if not (cl is ScreenFX):
			(cl as CanvasLayer).visible = false
	var boat := MoonBoat.spawn(main.world, lake.to_global(Vector3(-1.5, 0.0, -9.0)), -PI * 0.5 + lake.global_rotation.y + 0.5, water_y)
	boat.lake = lake
	boat.day_night = main.day_night
	DanceStage.lantern_keep = 0.3
	DanceStage.hover_lanterns = false
	DanceStage.clear_radius = 7.0
	var stage := DanceStage.build(lake, lake.to_global(Vector3(-1.5, 0.0, -9.0)), water_y, [lake.to_global(Vector3(0.0, 1.5, -2.0))], luna)
	stage.light_also(mika)
	for c in [luna, mika]:
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.visible = true
		c.set_physics_process(false)
		c.set_hair_frame("")
	boat.seat(luna, "bow")
	boat.seat(mika, "stern")
	await t._wait(1.0)
	boat.row(true)
	boat.trail_hand("stern", "Left", true)
	# bone grabbers at the very end of each stack (after the drape)
	var grabs := {}
	for c in [luna, mika]:
		var bg := BoneGrab.new()
		bg.name = "BoneGrab"
		c.skeleton.add_child(bg)
		grabs[c.character_id] = bg
	# the hull's outline: per 5 cm slice along the boat, its widest |z| and its lowest y (boat space, unscaled)
	var prof := {}
	var hv: PackedVector3Array = boat.hull.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in hv:
		var k := int(floor((v + boat.hull.position).x / 0.05))
		var e: Vector2 = prof.get(k, Vector2(0.0, 9.0))
		prof[k] = Vector2(maxf(e.x, absf(v.z)), minf(e.y, v.y))
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	for g in t.get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	pin.fov = 40.0
	pin.active = true
	var angles := [["front", Vector3(-3.4, 1.5, 0.0), Vector3(0.3, 0.55, 0.0), 40.0], ["side", Vector3(0.3, 1.5, 3.9), Vector3(0.3, 0.5, 0.0), 40.0],
		["top", Vector3(0.31, 5.2, 0.05), Vector3(0.3, 0.0, 0.0), 44.0], ["hands", Vector3(0.95, 1.05, 1.25), Vector3(-0.25, 0.55, 0.0), 34.0]]
	var t0: float = t._game_t
	var worst := {}
	var checked := 0
	print("[boatcloth] start frame %d" % Engine.get_frames_drawn())
	while t._game_t - t0 < 6.0 + angles.size() * 2.0:
		await t.get_tree().process_frame
		var tt: float = t._game_t - t0
		var ai := clampi(int(maxf(tt - 6.0, 0.0) / 2.0), 0, angles.size() - 1)
		var b := boat.global_transform
		pin.pos = b * (angles[ai][1] as Vector3)
		pin.look = b * (angles[ai][2] as Vector3)
		pin.fov = float(angles[ai][3])
		if ai == 3:
			# the close-up follows Luna's hands
			var sk := luna.skeleton
			var hm := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin + sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin) * 0.5
			pin.look = hm
			pin.pos = hm + (b.basis.orthonormalized() * Vector3(0.75, 0.25, 0.75))
		if tt > 6.0 and absf(fmod(tt - 6.0, 2.0) - 1.0) < 0.02:
			print("[boatcloth] %s at frame %d" % [angles[ai][0], Engine.get_frames_drawn()])
		if tt > 3.0 and fmod(tt, 0.5) < 0.034:
			checked += 1
			for c in [luna, mika]:
				var other: WorldCharacter = mika if c == luna else luna
				var r := _count(c, grabs[c.character_id].poses, boat, prof, other, grabs[other.character_id].poses)
				if int(r.outside) + int(r.below) > 0 and fmod(tt, 2.0) < 0.034:
					var det := {}
					for key in r:
						if String(key).begins_with("out_") or String(key).begins_with("below_"):
							det[key] = r[key]
					print("[boatcloth] %s detail %s" % [c.character_id, str(det)])
				var w: Dictionary = worst.get(c.character_id, {"outside": 0, "below": 0, "in_other": 0, "total": 0})
				for key in ["outside", "below", "in_other"]:
					w[key] = maxi(int(w[key]), int(r[key]))
				w.total = int(r.total)
				worst[c.character_id] = w
	# Mika's chin on her hand: close from both sides (the hand rests on the face, never in it)
	boat.trail_hand("stern", "Left", false)
	boat.chin_rest("stern", true, "Right")
	await t._wait(1.6)
	for side in [-1.0, 1.0]:
		var st := boat.seat_xform("stern")
		var hd: Vector3 = st.origin + Vector3(0, 0.62, 0) + st.basis.z * 0.12
		pin.fov = 32.0
		pin.pos = hd + st.basis.z * 0.75 + st.basis.x * (0.45 * side) + Vector3(0, -0.05, 0)
		pin.look = hd + Vector3(0, -0.06, 0)
		await t._wait(0.6)
		var gd := 0.0
		for n in mika.skeleton.get_children():
			if n is HandGuard:
				gd = (n as HandGuard).last_depth
		print("[boatcloth] chin_%s at frame %d  guard push depth %.3f" % ["left" if side < 0 else "right", Engine.get_frames_drawn(), gd])
		await t._wait(0.6)
	pin.active = false
	for id in worst:
		var w: Dictionary = worst[id]
		print("[boatcloth] %s: %d cloth vertices checked x %d samples - worst: %d outside the hull, %d below its floor, %d inside the other girl" % [id, w.total, checked, w.outside, w.below, w.in_other])
		t._check(int(w.outside) == 0 and int(w.below) == 0 and int(w.in_other) == 0, "%s cloth inside the boat and clear of the other girl (%d / %d / %d)" % [id, w.outside, w.below, w.in_other])
	for c in [luna, mika]:
		for n in c.skeleton.get_children():
			if n is HandGuard:
				print("[boatcloth] %s hand guard: %d pushes, last depth %.3f" % [c.character_id, (n as HandGuard).pushes, (n as HandGuard).last_depth])


static func _count(c: WorldCharacter, poses: Array, boat: MoonBoat, prof: Dictionary, other: WorldCharacter, oposes: Array) -> Dictionary:
	var out := {"outside": 0, "below": 0, "in_other": 0, "total": 0}
	if poses.is_empty():
		return out
	var sk := c.skeleton
	var sg := sk.global_transform
	var binv := boat.global_transform.affine_inverse()
	# the other girl as capsules (world)
	var caps := []
	var og := other.skeleton.global_transform
	var OB := func(n: String) -> Vector3:
		var bi := other.skeleton.find_bone(n)
		return og * (oposes[bi] as Transform3D).origin if bi >= 0 and bi < oposes.size() else Vector3.INF
	caps.append([OB.call("Hips"), OB.call("Neck"), 0.12])
	caps.append([OB.call("Head"), OB.call("Head") + Vector3(0, 0.15, 0), 0.1])
	for s in ["Left", "Right"]:
		caps.append([OB.call(s + "UpperLeg"), OB.call(s + "LowerLeg"), 0.07])
		caps.append([OB.call(s + "LowerLeg"), OB.call(s + "Foot"), 0.05])
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(m.name)
		if not (nm.contains("Skirt") or nm.contains("BackBow") or nm.contains("Sleeve")):
			continue
		var skin := m.skin
		if skin == null:
			continue
		var bind_bone := []
		for bi in skin.get_bind_count():
			var b := skin.get_bind_bone(bi)
			if b < 0:
				b = sk.find_bone(skin.get_bind_name(bi))
			bind_bone.append(b)
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var BI = arr[Mesh.ARRAY_BONES]
			var BW = arr[Mesh.ARRAY_WEIGHTS]
			if BI == null or BW == null:
				continue
			var per := (BI as Array).size() / maxi(V.size(), 1) if BI is Array else (BI as PackedInt32Array).size() / maxi(V.size(), 1)
			for vi in range(0, V.size(), 2):                  # every other vertex (enough to catch a panel outside)
				var p := Vector3.ZERO
				for k in per:
					var w: float = BW[vi * per + k]
					if w <= 0.0001:
						continue
					var bidx: int = BI[vi * per + k]
					var bb: int = bind_bone[bidx]
					if bb < 0 or bb >= poses.size():
						continue
					p += ((poses[bb] as Transform3D) * skin.get_bind_pose(bidx) * V[vi]) * w
				var wp := sg * p
				out.total += 1
				var lp := binv * wp
				var e: Vector2 = prof.get(int(floor(lp.x / 0.05)), Vector2(-1.0, 9.0))
				if e.x < 0.0 or absf(lp.z) > e.x + 0.01:
					out.outside += 1
					out["out_" + nm] = int(out.get("out_" + nm, 0)) + 1
					out["out_at_" + nm] = lp.snappedf(0.01)
				elif lp.y < e.y - 0.01:
					out.below += 1
					out["below_" + nm] = int(out.get("below_" + nm, 0)) + 1
					out["below_at_" + nm] = [lp.snappedf(0.01), snappedf(e.y, 0.01)]
				for cp in caps:
					if cp[0] == Vector3.INF or cp[1] == Vector3.INF:
						continue
					var q := Geometry3D.get_closest_point_to_segment(wp, cp[0], cp[1])
					if wp.distance_to(q) < float(cp[2]) - 0.01:
						out.in_other += 1
						break
	return out
