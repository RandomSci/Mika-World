extends RefCounted
## --mktest=storytrail (23 Oct, for Selwyn's review before the next live): the new small places and chapter 2 as
## viewers would see them. A first look at a spot in the sanctuary (the mushroom ring), then the Heartstone chapter
## done -> "The Lamplighter's Trail" begins, the walk into the Whispering Woods to the dark wayshrine (the first
## clue, each girl's own guess), on to the Ancient Grove's guardian (the second clue, their guesses tested). The camera
## director runs as on stream. Record with --write-movie and --llm-real for real lines.


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("story trail")
	await t._hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = true
	if main.day_night:
		main.day_night.set_override(false)
	var mc: WorldCharacter = main.characters["mika"]
	var b = main.mage_brains["mika"]
	await _visit(t, main, b, "sanctuary", "sanct_mushroom_ring")
	# the Heartstone chapter done -> chapter 2
	var st = main.story
	if st.chapter == 0:
		for c in st.data.clues:
			for k in st.data.clues[c].any_knowledge:
				WorldState.knowledge[k] = 1
		st.evaluate(true)
		WorldState.knowledge["chapter_done:heartstone"] = Time.get_unix_time_from_system() - 700.0
		st.evaluate()
	print("[storytrail] chapter %d %s: %s" % [st.chapter + 1, st.data.title, st.objective()])
	await t._wait(4.0)
	# walk into the woods the real way (the journey, Luna along, the camera in front of them)
	var r: Dictionary = main.travel.travel_to("whispering_woods", "walk")
	print("[storytrail] set out for the woods %s" % str(r.get("ok", false)))
	var t0 := Time.get_ticks_msec()
	while main.travel.active() and Time.get_ticks_msec() - t0 < 180000:
		await t.get_tree().process_frame
	await t._wait(3.0)
	await _visit(t, main, b, "whispering_woods", "woods_shrine")
	print("[storytrail] after the wayshrine: %s" % st.objective())
	await _visit(t, main, b, "ancient_grove", "grove_guardian_statue")
	print("[storytrail] after the guardian: %s | Mika's theories %s" % [st.objective(), str(WorldState.mind("mika").knowledge.get("theories", []))])
	print("[storytrail] Luna's theories %s" % str(WorldState.mind("luna").knowledge.get("theories", [])))
	t._check(WorldState.knowledge.has("clue:ash_mark_grove"), "the trail reached the grove")


static func _visit(t, main, b, area: String, spot: String) -> void:
	var mc: WorldCharacter = main.characters["mika"]
	var lc: WorldCharacter = main.characters.get("luna")
	if main.streaming.current_id != area:
		await main.streaming.travel(area, mc, true)
		await t._wait(3.0)
	var it: Interactable = main.world.interactables.get("spot:" + spot)
	if it == null:
		t._check(false, "%s stands in %s" % [spot, area])
		return
	var map := mc.get_world_3d().navigation_map
	# start a short walk away, Luna beside her (the walk over is part of the look)
	var start := NavigationServer3D.map_get_closest_point(map, it.approach_point() + (it.approach_point() - it.global_position).normalized() * 9.0)
	for c in [mc, lc]:
		if c and main.teleport_guard:
			main.teleport_guard.allow(c)
	mc.global_position = start
	if lc:
		lc.global_position = NavigationServer3D.map_get_closest_point(map, start + Vector3(1.2, 0, 0.8))
	await t._wait(2.0)
	b.hold = false
	b._cancel = false
	var o: Dictionary = PlaceSpots.options(b).filter(func(x): return String(x.spot) == spot).front() if not PlaceSpots.options(b).filter(func(x): return String(x.spot) == spot).is_empty() else {}
	if o.is_empty():
		o = {"kind": "spot", "key": "spot:" + spot, "interactable": "spot:" + spot, "spot": spot, "first": true, "clue": "", "lead": "", "label": spot}
	if lc and main.mage_brains.has("luna"):
		lc.navigate_to(NavigationServer3D.map_get_closest_point(map, it.approach_point() + Vector3(1.3, 0, 0.6)), false)
	print("[storytrail] %s: %s at frame %d" % [area, o.label, Engine.get_frames_drawn()])
	var res: Dictionary = await PlaceSpots.visit(b, o)
	print("[storytrail] %s done %s at frame %d" % [spot, str(res.get("detail", "")), Engine.get_frames_drawn()])
	b.hold = true
	await t._wait(2.0)
