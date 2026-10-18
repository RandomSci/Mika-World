extends RefCounted
## --mktest=persist_boat: the kill / resume proof for the Moon Lantern Boat (ScenePersist + MoonBoat.snapshot/restore).
## Needs --persist --game-clock and a test_regress_* save. Phase 1: night on Lantern Lake by the clock, the boat
## mid-lake, Luna on the bow seat, Mika on the stern; Mika lights the bow lantern and sets a floating lantern on the
## water, a viewer's named lantern goes up; Luna rows, Mika trails her hand in the water; once a periodic save of the
## ride is on disk: READY_FOR_KILL (the shell sends SIGKILL). Phase 2 (same save): everything compared with the truth
## of the snapshot that was loaded. See persist_common.gd.

const C := preload("res://scripts/tests/ext/persist_common.gd")
const CAM := Vector3(0.35, 1.7, 4.2)       # boat space (x1.3): a wide side view of both girls
const LOOK := Vector3(0.3, 0.55, 0.0)


static func run(t) -> void:
	print("[persist_boat] phase %s, save %s (%s), persistent %s" % [C.phase(), WorldState.save_path, WorldState.load_report.get("result", "new"), WorldState.persistent])
	if not WorldState.persistent:
		t._check(false, "the kill/resume test needs --persist (a persistent test_regress_* save)")
		return
	if C.phase() == "1":
		await _phase1(t)
	else:
		await _phase2(t)


static func _truth(main: Node, boat: MoonBoat, d: Dictionary, lake: Node3D) -> Dictionary:
	var inv := boat.global_transform.affine_inverse()
	var rs := {}
	for s in boat.riders:
		var c: WorldCharacter = boat.riders[s].c
		var lp := inv * c.global_position
		rs[s] = {"who": c.character_id, "mode": String(boat.riders[s].mode), "local": [lp.x, lp.y, lp.z], "yaw": c.global_rotation.y}
	var names := []
	for L in (lake.get("free_lanterns") as Array):
		if String(L.get("name", "")) != "":
			names.append(String(L.name))
	return {"seq": int(d.seq), "unix": int(d.unix), "area": main.streaming.current_id, "world_min": WorldState.world_min,
		"boat": {"base": [boat._base.x, boat._base.y, boat._base.z], "yaw": boat._yaw, "speed": boat.speed, "rowing": boat.rowing,
			"lit": {"bow": float(boat.lanterns.bow.lit), "stern": float(boat.lanterns.stern.lit)}, "floaters": boat._floaters.size()},
		"riders": rs, "mages": {"mika": C.level_xp("mika"), "luna": C.level_xp("luna")},
		"lanterns": {"count": (lake.get("free_lanterns") as Array).size(), "names": names}}


static func _phase1(t) -> void:
	var main: Node = t.main
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
	t._check(main.streaming.current_id == "lantern_lake", "at Lantern Lake")
	# night by the clock (the game clock is saved and restored; no test override)
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 22.5 * 60.0
	await t._wait(4.0)
	var lake := C.find_lake(main)
	t._check(lake != null, "the lake node")
	if lake == null:
		return
	var water_y: float = lake.global_position.y
	var boat := MoonBoat.spawn(main.world, lake.to_global(Vector3(-1.5, 0.0, -9.0)), -PI * 0.5 + lake.global_rotation.y + 0.5, water_y)
	boat.lake = lake
	boat.day_night = main.day_night
	t._check(boat.is_in_group("persistent_activity"), "the boat is a persistent activity (%s)" % boat.persist_key())
	t._check(boat.night(), "night by the clock (%s, night k %.2f)" % [WorldState.clock_text(), float(main.day_night.k)])
	for c in [luna, mika]:
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.visible = true
		c.set_physics_process(false)
		c.set_hair_frame("")
	boat.seat(luna, "bow")
	boat.seat(mika, "stern")
	var pin := C.pin_camera(t)
	var cam_loop := func():
		while is_instance_valid(boat) and pin.active:
			var b := boat.global_transform
			pin.pos = b * CAM
			pin.look = b * LOOK
			await t.get_tree().process_frame
	cam_loop.call()
	await t._wait(1.2)
	await boat.light_lantern("stern", "bow", "Right")
	await boat.place_lantern("stern", "Left")
	lake.call("viewer_lantern", "PersistTester", "chat")      # a viewer's named lantern goes up from the pier
	await t._wait(2.0)
	boat.row(true)
	boat.trail_hand("stern", "Left", true)
	# the truth at every snapshot
	var truth := {}
	main.scene_persist.captured.connect(func(d: Dictionary):
		if is_instance_valid(boat) and boat.is_inside_tree():
			C.add_truth(truth, _truth(main, boat, d, lake)))
	var ride_unix := int(Time.get_unix_time_from_system())
	var t0: float = t._game_t
	print("[persist_boat] riding: %s" % boat.persist_step())
	# at least 15 s of rowing, then until a save of the ride has reached the disk (WorldState writes every 30 s at the
	# latest, 2 s after any change, at once on an activity step); the reasons of the saves on the way are logged
	var reasons := {}
	var last_seen := -1
	while true:
		await t._wait(0.25)
		var ls: Dictionary = WorldState.last_save
		if int(ls.get("unix", 0)) != last_seen:
			last_seen = int(ls.get("unix", 0))
			reasons[String(ls.get("reason", "?"))] = int(reasons.get(String(ls.get("reason", "?")), 0)) + 1
		if t._game_t - t0 > 15.0 and bool(ls.get("ok", false)) and int(ls.get("unix", 0)) > ride_unix + 10 and not truth.is_empty():
			break
		if t._game_t - t0 > 90.0:
			t._check(false, "no save during the ride", ls)
			return
	print("[persist_boat] saves during the ride (by reason): %s" % JSON.stringify(reasons))
	var ks := truth.keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	var last: Dictionary = truth[ks.back()]
	t._check(true, "saved mid-ride: snapshot #%d, boat at %s speed %.2f, %s" % [int(last.seq), str(last.boat.base), float(last.boat.speed), boat.persist_step()])
	print("[persist_boat] truth #%d: %s" % [int(last.seq), JSON.stringify(last)])
	C.still(t, "before_kill")
	await C.await_kill(t)


static func _phase2(t) -> void:
	var main: Node = t.main
	var sp: ScenePersist = main.scene_persist
	var w0: float = t._game_t
	while not sp.resumed_done and t._game_t - w0 < 30.0:
		await t.get_tree().process_frame
	var rep: Dictionary = sp.report
	print("[persist_boat] resume report: %s" % JSON.stringify(rep).left(1500))
	var seq := int(WorldState.scene.get("seq", -1))
	var truths := C.read_truth()
	var tr: Dictionary = truths.get(str(seq), {})
	t._check(not tr.is_empty(), "the truth of the loaded snapshot #%d (phase 1 recorded %s)" % [seq, str(truths.keys())])
	if tr.is_empty():
		return
	t._check(main.streaming.current_id == String(tr.area), "same area: %s (saved %s)" % [main.streaming.current_id, tr.area])
	var key := "moon_boat:MoonBoat"
	var ar: Dictionary = rep.get("activities", {}).get(key, {})
	t._check(bool(ar.get("ok", false)), "the boat ride resumed (%s)" % str(ar).left(200))
	var boat: MoonBoat = null
	for n in t.get_tree().get_nodes_in_group("persistent_activity"):
		if n is MoonBoat and (n as MoonBoat).persist_key() == key:
			boat = n                      # (the ritual's own boat, moored at the pier, is another one)
	t._check(boat != null, "the boat is back on the lake")
	if boat == null:
		return
	# at the moment of the restore: exactly the saved boat
	var after: Dictionary = ar.get("after", {})
	var tb := ScenePersist.v3(tr.boat.base)
	var ab := ScenePersist.v3(boat.get_meta("persist_restored_at", []))
	t._check(ab.distance_to(tb) < 0.05, "boat restored at the saved spot: %.3f m off (saved %s)" % [ab.distance_to(tb), str(tb.snappedf(0.01))])
	var ab2 := ScenePersist.v3(after.get("base", []))
	var fwd0 := -(Basis(Vector3.UP, float(tr.boat.yaw)) * Vector3.RIGHT)
	t._check((ab2 - tb).dot(fwd0) >= -0.01 and (ab2 - tb).length() < 2.0, "0.75 s later (seats settled) it has rowed on %.2f m bow-first" % (ab2 - tb).length())
	t._check(absf(angle_difference(float(after.get("yaw", 0.0)), float(tr.boat.yaw))) < 0.01, "boat heading restored (%.3f vs %.3f rad)" % [float(after.get("yaw", 0.0)), float(tr.boat.yaw)])
	var sp0 := float(boat.get_meta("persist_restored_speed", -1.0))
	t._check(absf(sp0 - float(tr.boat.speed)) < 0.01, "boat speed restored (%.3f vs %.3f m/s)" % [sp0, float(tr.boat.speed)])
	t._check(absf(float(after.get("row_phase", -1.0)) - float(tr.get("boat", {}).get("row_phase", after.get("row_phase", 0.0)))) < 0.5, "the stroke carries on")
	# same seats, same doing, rowing on
	for s in tr.riders:
		var r: Dictionary = boat.rider(s)
		var who := String(tr.riders[s].who)
		t._check(not r.is_empty() and (r.c as WorldCharacter).character_id == who, "%s back on the %s seat" % [who, s])
		t._check(not r.is_empty() and String(r.mode) == String(tr.riders[s].mode), "%s still %s (%s)" % [who, tr.riders[s].mode, r.get("mode", "?")])
	t._check(boat.rowing == bool(tr.boat.rowing) and boat.rowing, "Luna is rowing again (rowing %s)" % boat.rowing)
	t._check(float(boat.lanterns.bow.lit) > 0.9 and absf(float(boat.lanterns.bow.lit) - float(tr.boat.lit.bow)) < 0.05, "the bow lantern still burns (%.2f)" % float(boat.lanterns.bow.lit))
	t._check(boat._floaters.size() == int(tr.boat.floaters), "floating lanterns on the water: %d (saved %d)" % [boat._floaters.size(), int(tr.boat.floaters)])
	# the camera as in phase 1, then the seats settle (hips on the cushion) and the girls are compared in the boat
	var pin := C.pin_camera(t)
	var cam_loop := func():
		while is_instance_valid(boat) and pin.active:
			var b := boat.global_transform
			pin.pos = b * CAM
			pin.look = b * LOOK
			await t.get_tree().process_frame
	cam_loop.call()
	await t._wait(1.0)
	var inv := boat.global_transform.affine_inverse()
	for s in tr.riders:
		var r: Dictionary = boat.rider(s)
		if r.is_empty():
			continue
		var c: WorldCharacter = r.c
		var lp := inv * c.global_position
		var tl := ScenePersist.v3(tr.riders[s].local)
		var dw := (boat.global_transform.basis * (lp - tl)).length()
		t._check(dw < 0.05, "%s in the boat within a few cm of where she sat: %.3f m" % [c.character_id, dw])
		t._check(not c.is_physics_processing() and c.visible, "%s seated (no physics, visible)" % c.character_id)
	var base0 := boat._base
	C.still(t, "after_resume")
	await t._wait(3.0)
	var moved := boat._base.distance_to(base0)
	var fwd := -(Basis(Vector3.UP, boat._yaw) * Vector3.RIGHT)
	t._check(moved > 0.2 and (boat._base - base0).dot(fwd) > 0.0, "the boat keeps moving bow-first under the oars: %.2f m in 3 s" % moved)
	t._check(boat._base.distance_to(tb) < 8.0, "the boat is near where it was saved: %.2f m (resumed, not reset)" % boat._base.distance_to(tb))
	C.still(t, "after_resume_4s")
	# the world around it
	var ck := C.clock_ok(float(tr.world_min))
	t._check(bool(ck.ok), "time of day carried on (%s)" % JSON.stringify(ck))
	for who in tr.mages:
		var now := C.level_xp(who)
		t._check(int(now.level) == int(tr.mages[who].level) and absf(float(now.xp) - float(tr.mages[who].xp)) < 0.05,
			"%s: Level %d, %.1f XP (saved Level %d, %.1f XP)" % [who, int(now.level), float(now.xp), int(tr.mages[who].level), float(tr.mages[who].xp)])
	var lake := C.find_lake(main)
	var names := []
	for L in (lake.get("free_lanterns") as Array):
		if String(L.get("name", "")) != "":
			names.append(String(L.name))
	t._check("PersistTester" in names and names.size() == (tr.lanterns.names as Array).size(), "viewer lantern names back in the sky: %s (saved %s)" % [str(names), str(tr.lanterns.names)])
	t._check(absf((lake.get("free_lanterns") as Array).size() - int(tr.lanterns.count)) <= 1, "released lanterns back: %d (saved %d)" % [(lake.get("free_lanterns") as Array).size(), int(tr.lanterns.count)])
	for who in ["mika", "luna"]:
		var b = main.mage_brains[who]
		t._check(b.hold or not b.enabled, "%s's planner waits while the ride goes on (hold %s, enabled %s)" % [who, b.hold, b.enabled])
	var tv: Array = main.teleport_guard.violations if main.teleport_guard else []
	t._check(tv.is_empty(), "no teleport-guard violations (%s)" % str(tv).left(200))
	t.report["persist"] = {"truth": tr, "resume": rep}
