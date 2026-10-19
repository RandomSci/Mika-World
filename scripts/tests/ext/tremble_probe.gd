extends RefCounted
## Root cause of the trembling (Selwyn, 2026-10-20): plays Move Library clips on a girl exactly as movelib_show does,
## and every rendered frame records, for the arm, hand, finger, spine and head bones, (a) the raw baked rotation (the
## clip's Animation sampled at the deck's own time, before any other system) and (b) the final local rotation after
## every modifier and the springs (a tap at the end of her stack), plus the frame and process tick it was read on.
## If (a) jitters the noise is in the mocap / bake; if (a) is smooth and (b) is not, something else writes those
## bones too. Options --clips=a,b,c --girl=mika --dump=<abs path json>. Marks "[tremble] <clip> from frame A to B".

const BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"RightIndexProximal", "RightIndexIntermediate", "RightMiddleProximal", "RightThumbProximal", "LeftShoulder", "LeftUpperArm",
	"LeftLowerArm", "LeftHand", "LeftIndexProximal", "LeftMiddleProximal", "LeftThumbProximal"]


class Tap extends SkeletonModifier3D:
	var rows: Array = []
	var ids := {}
	var on := false
	var anim: Animation = null
	var t_of: Callable
	var map := {}

	func _process_modification() -> void:
		if not on:
			return
		var sk := get_skeleton()
		var t: float = t_of.call()
		var raw := {}
		var fin := {}
		for b in ids:
			var bi: int = ids[b]
			var q := sk.get_bone_pose_rotation(bi)
			fin[b] = [q.x, q.y, q.z, q.w]
			if anim and map.has(b):
				var r := anim.rotation_track_interpolate(int(map[b]), clampf(t, 0.0, anim.length))
				raw[b] = [r.x, r.y, r.z, r.w]
		rows.append({"f": Engine.get_frames_drawn(), "pr": Engine.get_process_frames(), "pf": Engine.get_physics_frames(),
			"us": Time.get_ticks_usec(), "t": t, "raw": raw, "fin": fin})


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
	for id in main.characters:
		if not (id in ["mika", "luna"]):
			(main.characters[id] as Node3D).visible = false
	FightDirector.set_hour(main, 13.0)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.5)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 3, "axis_deg": 0.0, "bare": true})
	d.set_process(true)
	var c0: Vector3 = d.center
	var who := String(RenderProfile.options.get("girl", "mika"))
	var other := "luna" if who == "mika" else "mika"
	d.F[who].pos = c0
	d.F[other].pos = c0 + Vector3(9.0, 0, 0)
	await t._wait(0.6)
	(d.F[other].c as Node3D).visible = false
	var mc: WorldCharacter = d.F[who].c
	for n in MeleeFighter.OFF_WHILE_FIGHTING:
		var m := mc.skeleton.get_node_or_null(n) as SkeletonModifier3D
		if m:
			m.active = false
	if mc.head_look:
		mc.head_look.influence = 0.0
	# the tap: last of all her modifiers (after the springs' own stage too)
	var tap := Tap.new()
	tap.name = "TraceTremble"
	mc.skeleton.add_child(tap)
	PosePipeline.of(mc).arrange()
	for b in BONES:
		var bi := mc.skeleton.find_bone(b)
		if bi >= 0:
			tap.ids[b] = bi
	var deck: FightDeck = d.F[who].deck
	tap.t_of = func() -> float: return float(deck._cur.get("t", 0.0))
	var order := []
	for n in mc.skeleton.get_children():
		if n is SkeletonModifier3D:
			order.append("%s%s" % [n.name, "" if (n as SkeletonModifier3D).active else " (off)"])
	print("[tremble] modifier stack: %s" % ", ".join(order))
	var gy := FightDirector.ground_y(d.F[who].c, c0)
	d.cut(d.ft + 0.001, "fixed", who, {"pos": Vector3(c0.x + 2.3, gy + 1.15, c0.z), "look": Vector3(c0.x, gy + 1.0, c0.z), "fov": 40.0})
	await t._wait(0.8)
	var out := {}
	for n in String(RenderProfile.options.get("clips", "orb_gather")).split(",", false):
		var clip := "ml_" + n
		if not mc.has_clip(clip):
			print("[tremble] %s MISSING" % n)
			continue
		var a: Animation = FightDeck.anim_for(mc, clip)
		tap.anim = a
		tap.map = {}
		for ti in a.get_track_count():
			if a.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
				tap.map[String(a.track_get_path(ti)).get_slice(":", 1)] = ti
		d.F[who].pos = c0
		tap.rows = []
		var a0 := Engine.get_frames_drawn()
		var dur: float = d.anim(who, clip, 0.0, -1.0, 1.0, 0.05)
		tap.on = true
		await t._wait(dur)
		tap.on = false
		print("[tremble] %s from frame %d to frame %d" % [n, a0, Engine.get_frames_drawn()])
		out[n] = {"a0": a0, "rows": tap.rows.duplicate(), "fps": Engine.physics_ticks_per_second}
		d.anim(who, "combat_idle", 0.0, -1.0, 1.0, 0.1, true)
		await t._wait(0.35)
	var dump := String(RenderProfile.options.get("dump", ""))
	if dump != "":
		var fh := FileAccess.open(dump, FileAccess.WRITE)
		fh.store_string(JSON.stringify(out))
		fh.close()
		# Selwyn: one CSV row per rendered frame - the frame delta, the physics tick count and the hips, chest, right
		# forearm and right hand rotations (final pose, and the raw bake beside it), to judge with the recording
		var csv := FileAccess.open(dump.get_basename() + ".csv", FileAccess.WRITE)
		var cols := ["clip", "frame", "process_frame", "physics_frame", "physics_ticks_this_frame", "usec", "delta_ms", "clip_t"]
		for b in ["Hips", "Chest", "RightLowerArm", "RightHand"]:
			for kind in ["fin", "raw"]:
				for c in ["x", "y", "z", "w"]:
					cols.append("%s_%s_%s" % [b, kind, c])
		csv.store_line(",".join(cols))
		for clip in out:
			var rows: Array = out[clip].rows
			for i in rows.size():
				var r: Dictionary = rows[i]
				var vals := [clip, r.f, r.pr, r.pf, (int(r.pf) - int(rows[i - 1].pf)) if i > 0 else 0, r.us,
					("%.3f" % ((int(r.us) - int(rows[i - 1].us)) / 1000.0)) if i > 0 else "0", "%.4f" % float(r.t)]
				for b in ["Hips", "Chest", "RightLowerArm", "RightHand"]:
					for kind in ["fin", "raw"]:
						var q: Array = (r[kind] as Dictionary).get(b, [0, 0, 0, 1])
						for c in q:
							vals.append("%.6f" % float(c))
				csv.store_line(",".join(vals.map(func(v): return str(v))))
		csv.close()
	t._check(not out.is_empty(), "%d clips probed" % out.size())
	d.teardown()
