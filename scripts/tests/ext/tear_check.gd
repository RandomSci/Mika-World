## v1 item 8 (part): no torn cloth or hair - no triangle of the skirt, sleeves, bows or hair stretched past 1.5x its
## rest size, in the final pose (after the springs), while both girls dance (his clips) and while they sit in the boat.

const LIMIT := 1.5
const PARTS := ["Skirt", "Sleeve", "BackBow", "Hair"]


static func run(t) -> void:
	var set: Dictionary = await t._lake_setup({"luna": -0.8, "mika": 0.8})
	if set.is_empty():
		return
	var chars: Dictionary = set.chars
	var caps := {}
	for id in chars:
		caps[id] = InvCommon.capture(chars[id])
	var worst := {}
	# 1. dancing: two of his clips, sampled every 0.5 s
	var decks := {}
	for id in chars:
		decks[id] = t._dance_stack(chars[id])
		(decks[id] as DanceDeck).influence = 1.0
		(decks[id] as DanceDeck).play("belly_dance" if id == "luna" else "dancing_a", 2.0, 1.0, 0.01)
	await _sample(t, chars, caps, worst, "dance", 8.0)
	print("[tear] dance done: %s" % str(worst))
	# 2. seated in the boat
	for id in decks:
		(decks[id] as DanceDeck).influence = 0.0
	var lake: Node3D = set.lake
	var boat := MoonBoat.spawn(t.main.world, lake.to_global(Vector3(-1.5, 0.0, -14.0)), -PI * 0.5 + lake.global_rotation.y, float(set.water_y))
	boat.lake = lake
	boat.day_night = t.main.day_night
	boat.seat(chars.luna, "bow")
	boat.seat(chars.mika, "stern")
	await t._wait(1.5)
	boat.row(true)
	boat.trail_hand("stern", "Left", true)
	await _sample(t, chars, caps, worst, "boat", 8.0)
	var ok := true
	for k in worst:
		var w: float = worst[k]
		print("[tear] %s worst stretch %.2f" % [k, w])
		if w > LIMIT:
			ok = false
	t._check(ok, "no cloth or hair triangle stretched past %.1fx (worst %s)" % [LIMIT, str(worst)])


static func _sample(t, chars: Dictionary, caps: Dictionary, worst: Dictionary, phase: String, secs: float) -> void:
	var t0: float = t._game_t
	var next := 1.0
	while t._game_t - t0 < secs:
		await t.get_tree().process_frame
		if t._game_t - t0 < next:
			continue
		next += 0.5
		for id in chars:
			var c: WorldCharacter = chars[id]
			var poses: Array = caps[id].poses
			for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				var part := ""
				for p in PARTS:
					if String(m.name).contains(p):
						part = p
				if part == "" or m.mesh == null:
					continue
				for si in m.mesh.get_surface_count():
					var sk_r := InvCommon.skin(m, c.skeleton, poses, si)
					var s := InvCommon.stretch(m, sk_r[0], sk_r[1], si)
					var key := "%s_%s_%s" % [id, phase, part]
					worst[key] = snappedf(maxf(float(worst.get(key, 1.0)), s), 0.01)
