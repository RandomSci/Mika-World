extends RefCounted
## --mktest=persist_dance: the kill / resume proof for a dance in progress (DanceSession round the DanceDecks).
## Needs --persist --game-clock and a test_regress_* save. Phase 1: the lake duet (the MV routine, both girls on the
## water at night) runs from the song's 38.33 s; once a save made after the routine's 59.26 s step change is on disk:
## READY_FOR_KILL (the shell sends SIGKILL). Phase 2 (same save): the dance must come back on the same clip at the
## same clip time and song position, both girls on their marks, and dance on. See persist_common.gd.

const C := preload("res://scripts/tests/ext/persist_common.gd")
const KEY := "dance:lake_duet"


static func run(t) -> void:
	print("[persist_dance] phase %s, save %s (%s), persistent %s" % [C.phase(), WorldState.save_path, WorldState.load_report.get("result", "new"), WorldState.persistent])
	if not WorldState.persistent:
		t._check(false, "the kill/resume test needs --persist (a persistent test_regress_* save)")
		return
	if C.phase() == "1":
		await _phase1(t)
	else:
		await _phase2(t)


static func _spot(lake: Node3D) -> Vector3:
	var s := lake.to_global(Vector3(-1.5, 0.0, -9.0))
	s.y = lake.global_position.y
	return s


static func _aim(pin: CameraPin, spot: Vector3) -> void:
	pin.pos = spot + Vector3(0, 1.1, 5.4)
	pin.look = spot + Vector3(0, 0.95, 0)


static func _truth(main: Node, s: DanceSession, d: Dictionary) -> Dictionary:
	var ds := {}
	for who in s.dancers:
		var c: WorldCharacter = s.dancers[who].c
		var cur: Dictionary = (s.dancers[who].deck as DanceDeck).get("_cur")
		ds[who] = {"clip": String(cur.get("clip", "")), "t": float(cur.get("t", 0.0)), "pos": [c.global_position.x, c.global_position.y, c.global_position.z],
			"yaw": c.global_rotation.y, "avatar": c.avatar_path}
	return {"seq": int(d.seq), "unix": int(d.unix), "area": main.streaming.current_id, "world_min": WorldState.world_min,
		"song_t": s.song_t, "dancers": ds, "mages": {"mika": C.level_xp("mika"), "luna": C.level_xp("luna")}}


static func _phase1(t) -> void:
	var main: Node = t.main
	var set: Dictionary = await t._lake_setup({"luna": -0.75, "mika": 0.75})
	if set.is_empty():
		return
	var pin: CameraPin = set.pin
	_aim(pin, set.spot)
	var chars: Dictionary = set.chars
	var s := DanceSession.begin(main.world, [chars.luna, chars.mika], MilestoneKTest.MV_ROUTINE, MilestoneKTest.MV_FROM, 92.0, "lake_duet")
	t._check(s.is_in_group("persistent_activity") and s.persist_key() == KEY, "the dance is a persistent activity (%s)" % s.persist_key())
	var truth := {}
	var cap := {"song": -1.0}
	main.scene_persist.captured.connect(func(d: Dictionary):
		if is_instance_valid(s):
			cap.song = s.song_t
			C.add_truth(truth, _truth(main, s, d)))
	print("[persist_dance] dancing from song %.2f: %s" % [s.song_t, s.persist_step()])
	var t0: float = t._game_t
	# until a snapshot taken after the 59.26 s step (Luna's new phrase) has been written
	while true:
		await t._wait(0.25)
		if float(cap.song) >= 60.0:
			await t._wait(1.0)
			if bool(WorldState.last_save.get("ok", false)):
				break
		if t._game_t - t0 > 80.0:
			t._check(false, "no save after the 59.26 s step", WorldState.last_save)
			return
	var ks := truth.keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	var last: Dictionary = truth[ks.back()]
	t._check(true, "saved mid-dance: snapshot #%d at song %.2f, %s (now song %.2f)" % [int(last.seq), float(last.song_t), s.persist_step(), s.song_t])
	print("[persist_dance] truth #%d: %s" % [int(last.seq), JSON.stringify(last)])
	C.still(t, "before_kill")
	await C.await_kill(t)


static func _phase2(t) -> void:
	var main: Node = t.main
	var sp: ScenePersist = main.scene_persist
	var w0: float = t._game_t
	while not sp.resumed_done and t._game_t - w0 < 30.0:
		await t.get_tree().process_frame
	var rep: Dictionary = sp.report
	print("[persist_dance] resume report: %s" % JSON.stringify(rep).left(1500))
	var seq := int(WorldState.scene.get("seq", -1))
	var truths := C.read_truth()
	var tr: Dictionary = truths.get(str(seq), {})
	t._check(not tr.is_empty(), "the truth of the loaded snapshot #%d (phase 1 recorded %s)" % [seq, str(truths.keys())])
	if tr.is_empty():
		return
	t._check(main.streaming.current_id == String(tr.area), "same area: %s (saved %s)" % [main.streaming.current_id, tr.area])
	var ar: Dictionary = rep.get("activities", {}).get(KEY, {})
	t._check(bool(ar.get("ok", false)), "the dance resumed (%s)" % str(ar).left(160))
	var s: DanceSession = null
	for n in t.get_tree().get_nodes_in_group("persistent_activity"):
		if n is DanceSession:
			s = n
	t._check(s != null and s.playing, "the dance is playing again")
	if s == null:
		return
	var after: Dictionary = ar.get("after", {})
	t._check(absf(float(after.get("song_t", -99.0)) - float(tr.song_t)) < 0.05, "song position restored: %.3f s (saved %.3f s)" % [float(after.get("song_t", -99.0)), float(tr.song_t)])
	for who in tr.dancers:
		var e: Dictionary = tr.dancers[who]
		var a: Dictionary = after.get("dancers", {}).get(who, {})
		t._check(String(a.get("clip", "")) == String(e.clip), "%s on the same clip: %s (saved %s)" % [who, a.get("clip", "?"), e.clip])
		t._check(absf(float(a.get("t", -99.0)) - float(e.t)) < 0.05, "%s at the same clip time: %.3f s (saved %.3f s)" % [who, float(a.get("t", -99.0)), float(e.t)])
		var c: WorldCharacter = main.characters[who]
		var dp := c.global_position.distance_to(ScenePersist.v3(e.pos))
		t._check(dp < 0.03, "%s on her mark on the water: %.3f m off" % [who, dp])
		t._check(absf(angle_difference(c.global_rotation.y, float(e.yaw))) < 0.02, "%s facing the same way (%.3f vs %.3f rad)" % [who, c.global_rotation.y, float(e.yaw)])
		t._check(c.avatar_path == String(e.avatar), "%s in the same look (%s)" % [who, c.avatar_path.get_file()])
	# the dressing of the scene (the stage lights and moon are test set dressing, rebuilt for the stills) + the camera
	var lake := C.find_lake(main)
	var spot := _spot(lake)
	var cams := []
	for k in 5:
		var ang := deg_to_rad(lerpf(-12.0, 12.0, k / 4.0))
		cams.append(spot + Vector3(sin(ang), 0, cos(ang)) * 3.9 + Vector3(0, 0.9, 0))
	# the night look must come back by itself (DanceSession.restore rebuilds the stage)
	var stages := t.get_tree().root.find_children("*", "DanceStage", true, false)
	t._check(stages.size() == 1, "the dance's night look restored (%d stage)" % stages.size())
	var pin := C.pin_camera(t)
	_aim(pin, spot)
	var song0 := s.song_t
	var clip0 := {}
	for who in s.dancers:
		clip0[who] = float((s.deck_of(who) as DanceDeck).get("_cur").get("t", 0.0))
	await t._wait(1.0)
	C.still(t, "after_resume")
	await t._wait(2.0)
	t._check(s.song_t - song0 > 2.5, "the song goes on: %.2f -> %.2f s" % [song0, s.song_t])
	for who in s.dancers:
		var d: DanceDeck = s.deck_of(who)
		var ex := s.expected(who, s.song_t)
		var tt := float(d.get("_cur").get("t", 0.0))
		t._check(not ex.is_empty() and d.current() == String(ex[0]) and absf(tt - float(ex[1])) < 0.3,
			"%s dances on in step with the song: %s at %.2f s (routine says %s at %.2f s)" % [who, d.current(), tt, ex[0] if not ex.is_empty() else "?", float(ex[1]) if not ex.is_empty() else -1.0])
	C.still(t, "after_resume_3s")
	var ck := C.clock_ok(float(tr.world_min))
	t._check(bool(ck.ok), "time of day carried on (%s)" % JSON.stringify(ck))
	for who in tr.mages:
		var now := C.level_xp(who)
		t._check(int(now.level) == int(tr.mages[who].level) and absf(float(now.xp) - float(tr.mages[who].xp)) < 0.05,
			"%s: Level %d, %.1f XP (saved Level %d, %.1f XP)" % [who, int(now.level), float(now.xp), int(tr.mages[who].level), float(tr.mages[who].xp)])
	var tv: Array = main.teleport_guard.violations if main.teleport_guard else []
	t._check(tv.is_empty(), "no teleport-guard violations (%s)" % str(tv).left(200))
	t.report["persist"] = {"truth": tr, "resume": rep}
