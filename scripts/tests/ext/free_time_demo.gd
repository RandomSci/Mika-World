extends RefCounted
## The action player in free time (Selwyn: "show me one 60 second free time clip ... using the same action player,
## plus 10 fps frames of 5 contact moments"). Mika and Luna in the sanctuary near a real tree and real flowers, every
## action an ActionPlayer.play of a catalog entry (only entries with status pass play; a refused one is logged with
## its reason): a greeting, a hand on the tree's bark, a kick that shakes its leaves down, a flower smelled, a flower
## picked and tucked behind her ear, a spell that grows plants, lights scattered, a dance step, a tickle that makes
## the other one laugh. The camera follows them both. Marks "[action] contact ..." with the engine frame of each
## contact, and "[freetime] ..." for the sequence. Option --seconds (default 60).

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
	FightDirector.set_hour(main, 16.5)
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	var m: WorldCharacter = main.characters.mika
	var l: WorldCharacter = main.characters.luna
	m.visible = true
	l.visible = true
	await t._wait(1.0)
	t._check(ActionPlayer.entries().size() >= 160, "the action catalog is loaded (%d entries)" % ActionPlayer.entries().size())
	# a tree with flowers near it, on the navmesh
	var tree := WorldTargets.tree(m)
	t._check(not tree.is_empty(), "a real tree near her")
	if tree.is_empty():
		return
	var tn: Node3D = tree.node
	var map: RID = m.get_world_3d().navigation_map
	var base: Vector3 = NavigationServer3D.map_get_closest_point(map, tn.global_position + Vector3(3.5, 0, 2.0))
	if main.teleport_guard:
		main.teleport_guard.allow(m)
		main.teleport_guard.allow(l)
	m.stop_action()
	l.stop_action()
	m.global_position = base
	l.global_position = NavigationServer3D.map_get_closest_point(map, base + Vector3(1.6, 0, 0.8))
	await t._wait(1.0)
	var pin := CameraPin.new()
	main.add_child(pin)
	pin.active = true
	pin.fov = 44.0
	var follow := true
	var cam_tick := func():
		var mid := (m.global_position + l.global_position) * 0.5
		var span := m.global_position.distance_to(l.global_position)
		var off := Vector3(4.2 + span * 0.6, 1.9, 4.2 + span * 0.6)
		pin.pos = pin.pos.lerp(mid + off, 0.08) if pin.pos != Vector3.ZERO else mid + off
		pin.look = pin.look.lerp(mid + Vector3(0, 1.0, 0), 0.12) if pin.look != Vector3.ZERO else mid + Vector3(0, 1.0, 0)
	var cam_loop := func():
		while follow:
			cam_tick.call()
			await t.get_tree().process_frame
	cam_loop.call()
	var pm := ActionPlayer.of(m)
	var pl := ActionPlayer.of(l)
	var t0: float = t._game_t
	print("[freetime] start frame %d" % Engine.get_frames_drawn())
	# Mika's afternoon and Luna's, played together (each girl's player runs her own list)
	var mika_list := ["wave_hello_far", "touch_tree_bark", "kick_tree_shake", "smell_flower", "cast_grow_plants", "tickle_magic_poke", "dance_sway_step"]
	var luna_list := ["bow_greeting", "pick_flower_tuck_hair", "stargaze_point", "cast_light_orbs_scatter", "poke_tree_laugh", "dance_arm_wave_flow"]
	var done := {"mika": false, "luna": false}
	var runner := func(p: ActionPlayer, list: Array, who: String):
		for id in list:
			if t._game_t - t0 > float(RenderProfile.options.get("seconds", 60.0)) - 4.0:
				break
			var r: Dictionary = await p.play(String(id))
			print("[freetime] %s %s %s" % [who, id, JSON.stringify({"ok": r.get("ok"), "why": r.get("why", "")})])
			await t._wait(0.6)
		done[who] = true
	runner.call(pm, mika_list, "mika")
	await t._wait(1.2)
	runner.call(pl, luna_list, "luna")
	var limit := float(RenderProfile.options.get("seconds", 60.0))
	while t._game_t - t0 < limit and not (bool(done.mika) and bool(done.luna)):
		await t.get_tree().process_frame
	while t._game_t - t0 < limit:
		await t.get_tree().process_frame
	follow = false
	pin.active = false
	var contacts := 0
	var played := 0
	for row in pm.log + pl.log:
		if bool(row.get("ok", false)):
			played += 1
	for row in pm.log + pl.log:
		if row.has("point"):
			contacts += 1
	print("[freetime] end frame %d, %d actions played, %d with a contact" % [Engine.get_frames_drawn(), played, contacts])
	t._check(played >= 8, "%d actions played through the action player" % played)
	t._check(contacts >= 5, "%d contacts with real targets" % contacts)
