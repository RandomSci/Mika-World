extends RefCounted

const Pastimes = preload("res://scripts/brain/pastimes.gd")
## --mktest=pastimes (26 Oct): every pastime once, on the spot (no walk, no error, she ends standing), the 30 minute
## rule (one done is no longer offered), then the brains free for 5 minutes: how many of their choices are walks and
## how many things done on the spot. Marks "[pastimes] ...".


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	await t._wait(2.0)
	var b: SanctuaryBrain = main.mage_brains["mika"]
	var map: RID = mika.get_world_3d().navigation_map
	var spot := NavigationServer3D.map_get_closest_point(map, Vector3(4.5, 0, 3.0))
	for c in [mika, luna]:
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
	mika.global_position = spot
	luna.global_position = NavigationServer3D.map_get_closest_point(map, spot + Vector3(1.6, 0, 0))
	await t._wait(1.0)
	var done := 0
	for id in ([] if RenderProfile.options.has("free_only") else Pastimes.LIST.keys()):
		var o := {"kind": "pastime", "key": "pastime:" + id, "pastime": id, "label": String(Pastimes.LIST[id].label), "other": "luna"}
		var start := mika.global_position
		b.current = {"kind": "pastime", "label": o.label, "key": o.key, "stage": "starting"}
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = await Pastimes.run(b, o)
		b.current = {}
		var moved := Vector2(mika.global_position.x - start.x, mika.global_position.z - start.z).length()
		var standing := mika.ground_pose == "" and not mika.seated
		print("[pastimes] %s: %s in %.1f s, moved %.2f m, standing %s" % [id, str(r), (Time.get_ticks_msec() - t0) / 1000.0, moved, str(standing)])
		if r.get("ok", false) and moved < 0.5 and standing:
			done += 1
		await t._wait(1.0)
	if RenderProfile.options.has("free_only"):
		done = Pastimes.LIST.size()
	t._check(done == Pastimes.LIST.size(), "every pastime runs on the spot and ends standing (%d of %d)" % [done, Pastimes.LIST.size()])
	var offered := Pastimes.options(b).map(func(o): return String(o.pastime))
	t._check(offered.is_empty(), "each one done is not offered again within 30 minutes (still offered: %s)" % str(offered))
	# a fresh start for the free run: the 30 minute marks cleared
	for id in Pastimes.LIST:
		b.mind.activity_counts.erase("pastime:" + id)
	var kinds := {}
	var cb := func(d): kinds[String(d.kind)] = int(kinds.get(String(d.kind), 0)) + 1
	b.decided.connect(cb)
	for w in main.mage_brains:
		main.mage_brains[w].hold = false
	await t._wait(float(RenderProfile.options.get("free_s", "300")))
	b.decided.disconnect(cb)
	var walks := 0
	var total := 0
	for k in kinds:
		total += int(kinds[k])
		if k in Pastimes.WALK_KINDS:
			walks += int(kinds[k])
	print("[pastimes] 5 free minutes, Mika's choices: %s (walks %d of %d)" % [str(kinds), walks, total])
	print("[pastimes] (choices are counted from the brain_decision lines of the log)")
