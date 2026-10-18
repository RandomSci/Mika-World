extends RefCounted
## --mktest=lake_ritual (2026-10-19): Lantern Lake live-ready, in normal play (headless is fine).
## Their planner walks them down at night (the longing for the lake and viewers' lanterns waiting pull), takes the
## boat out (LakeRitual "lakeboat"), lights lanterns for their wishes; viewer events from the live link (a subscriber
## while still at home, then a member, a Super Chat and a chat wish all at once mid-ritual) rise one at a time with
## names and thanks; the clock turns to day mid-ritual (the ritual finishes as a night ritual); they row back and
## stand on the pier. Also: the boat stays on open water (never through the pier), the story step stays reachable.


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	main.spawner.enabled = false
	main.day_night.clear_override()
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 21.5 * 60.0
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 12.0)
	if main.performance and main.performance.busy():
		main.performance.interrupt("lake ritual test")          # (a dance at the start: the thank-you would wait for its end)
	var lr: LakeRitual = LakeRitual.instance
	t._check(lr != null, "LakeRitual is part of the world")
	if lr == null:
		return
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var map: RID = mika.get_world_3d().navigation_map
	for c in [mika, luna]:
		if main.teleport_guard:
			main.teleport_guard.allow(c)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(-30, 0, 30)) + Vector3(0, 0.05, 0)
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(-28, 0, 31)) + Vector3(0, 0.05, 0)
	await t._wait(4.0)
	main.director.enabled = true
	main.director.set_subject(mika)
	await t._wait(0.5)
	var nid := SanctuaryBrain.night_id()
	print("[lakeritual-test] clock day %d %.2f h night_id %d real_clock %s" % [WorldState.day(), WorldState.hour_f(), nid, str(WorldState.real_clock)])
	# 1. the longing: grows with the nights they have missed the lake
	mb.mind.knowledge["lake_night"] = nid - 1
	mb.mind.knowledge.erase("lake_boat_night")
	var l1: float = lr.longing(mb)
	mb.mind.knowledge["lake_night"] = nid - 4
	var l4: float = lr.longing(mb)
	t._check(l1 == 0.0 and l4 > 0.3, "the pull of the lake grows with the nights away (1 night %.2f, 4 nights %.2f)" % [l1, l4])
	# 2. a new subscriber while they are still at home: thanked now, the lantern waits for the lake
	var link = main.get("live_link")
	t._check(link != null, "the live link (dummy server) is up")
	if link == null:
		return
	if main.performance:
		if main.performance.busy():
			main.performance.interrupt("lake ritual test")
		main.performance.set_process(false)          # (no celebration dance in the middle of the at-home check)
	await t._wait(2.0)
	var lines0: int = main.voice.log.size()
	link._on_message({"type": "youtube-live-subscriber", "author": "Aiko"})
	link._on_message({"type": "youtube-live-subscriber", "author": "Aiko"})          # (the same event twice: once)
	var tw: float = t._game_t
	while t._game_t - tw < 40.0 and (lr.pending.is_empty() or lr._busy_event or not lr._thank_due.is_empty()):
		await t.get_tree().process_frame
	print("[lakeritual-test] gates %s" % JSON.stringify(lr.debug_state()))
	print("[lakeritual-test] at home: pending %s queue %d log %s" % [str(lr.pending), lr.queue.size(), JSON.stringify(lr.log)])
	t._check(lr.pending.size() == 1 and String(lr.pending[0][0]) == "Aiko", "at home the subscriber's lantern waits for the lake (%s)" % str(lr.pending))
	var said: Array = (main.voice.log as Array).slice(lines0).map(func(r): return String(r.get("text", "")))
	t._check(said.any(func(s): return s.contains("Aiko")), "Mika thanked Aiko by name at once", said)
	var mem: Dictionary = WorldState.mind("mika").knowledge.get(LakeRitual.MEM_KEY, {})
	t._check((mem.get("pending", []) as Array).size() == 1, "the waiting lantern is saved with Mika's mind", mem)
	if main.performance:
		main.performance.set_process(true)
	var pull: Dictionary = lr.visit_pull(mb, 0.5)
	t._check(float(pull.u) > 0.5 + l4, "the waiting lantern and the longing pull them to the lake (%s)" % str(pull))
	# 3. their own choice: the walk down at night
	var opts: Array = mb.options()
	var lake_opt: Array = opts.filter(func(o): return o.kind == "visit" and String(o.area) == "lantern_lake")
	t._check(not lake_opt.is_empty(), "at night the walk down to Lantern Lake is offered")
	if lake_opt.is_empty():
		return
	print("[lakeritual-test] visit score %s" % str(mb.score(lake_opt[0])))
	var res := {}
	var job := func(): res["r"] = await mb.run_activity(lake_opt[0])
	job.call()
	var t0: float = t._game_t
	while not res.has("r") and t._game_t - t0 < 200.0:
		await t.get_tree().process_frame
	t._check(main.streaming.current_id == "lantern_lake" and luna.visible, "they walked down to Lantern Lake together (%s)" % str(res.get("r", {})).left(120))
	if main.streaming.current_id != "lantern_lake":
		return
	await t._wait(2.5)
	# the story's next step stays reachable from here (home is one walk away, the books there are on offer)
	var opts2: Array = mb.options()
	var home: Array = opts2.filter(func(o): return o.kind == "visit" and String(o.area) == "sanctuary")
	t._check(not home.is_empty(), "from the lake the way home (and the story there) is offered", opts2.map(func(o): return o.key))
	var leads: Array = main.story.next_leads()
	print("[lakeritual-test] story objective: %s | leads %s" % [main.story.objective(), str(leads.map(func(l): return l.lead))])
	t._check(main.story.objective() != "", "the story has a current step: %s" % main.story.objective())
	for l in leads:
		if String(l.get("activity", "")) == "research":
			t._check(opts2.any(func(o): return o.kind == "research" and String(o.get("book", "")) == String(l.book)) or String(lr.main.get("streaming").current_id) != "sanctuary",
				"the story's book lead '%s' is on offer (or a walk home away)" % String(l.book))
	# 4. the boat
	var bo: Array = opts2.filter(func(o): return o.kind == "lakeboat")
	t._check(not bo.is_empty(), "the boat ritual is offered at the lake at night", opts2.map(func(o): return o.key))
	if bo.is_empty():
		return
	print("[lakeritual-test] boat score %s" % str(mb.score(bo[0])))
	var res2 := {}
	var job2 := func(): res2["r"] = await mb.run_activity(bo[0])
	job2.call()
	var t1: float = t._game_t
	var steps := []
	var fired := false
	var day_set := false
	var worst_shore := -99.0
	var pier_hits := 0
	var snap_mid := {}
	var launches := []
	var lk: Node3D = lr._lake()
	if lk:
		lk.viewer_launched.connect(func(v, k, _n): if v != "": launches.append([v, k, t._game_t]))
	var samp := 0.0
	while not res2.has("r") and t._game_t - t1 < 420.0:
		await t.get_tree().process_frame
		if steps.is_empty() or steps[-1] != lr.running:
			steps.append(lr.running)
			print("[lakeritual-test] %.1f step %s" % [t._game_t - t1, lr.running])
		if lr.running == "lanterns" and not fired and lr.boat and lr.boat._floaters.size() >= 1:
			fired = true
			snap_mid = lr.snapshot()
			# three events at once (a member, a Super Chat as the show's selected message, a chat wish)
			link._on_message({"type": "youtube-live-member", "author": "Kenji"})
			link._on_message({"type": "youtube-live-selected-message", "active": true, "id": "sc1", "author": "Sora", "message": "(sent $5.00)", "paid": true, "amount": "$5.00", "to": ["mika"]})
			link._on_message({"type": "youtube-live-selected-message", "active": true, "id": "c1", "author": "Mei", "message": "I wish for a calm night", "paid": false, "to": ["mika"]})
		if fired and not day_set and t._game_t - t1 > 0.0 and launches.size() >= 1:
			day_set = true
			main.day_night.set_override(false)          # dawn comes mid-ritual: the ritual finishes as it began
			print("[lakeritual-test] the clock turns to day mid-ritual")
		samp += t.get_process_delta_time()
		if samp > 0.5 and lr.boat and is_instance_valid(lr.boat):
			samp = 0.0
			var bx: Transform3D = lr.boat.global_transform
			var ax := bx.basis.x.normalized()
			for k in 5:
				var p: Vector3 = lk.to_local(bx.origin + ax * lerpf(-2.1, 2.1, k / 4.0) * 1.0)
				worst_shore = maxf(worst_shore, float(lk.call("shore_e", p.x, p.z)))
				for sd in [-0.6, 0.6]:
					var q: Vector3 = lk.to_local(bx.origin + ax * lerpf(-2.1, 2.1, k / 4.0) + bx.basis.z.normalized() * sd)
					if absf(q.x - 4.0) < 1.05 and q.z > -3.5 and q.z < 9.0:
						pier_hits += 1
	print("[lakeritual-test] ritual: %s after %.0f s, steps %s" % [str(res2.get("r", {})).left(200), t._game_t - t1, str(steps)])
	print("[lakeritual-test] launches %s" % str(launches))
	print("[lakeritual-test] log %s" % JSON.stringify(lr.log))
	t._check(res2.has("r") and bool(res2.r.get("ok", false)), "the boat ritual ran to its end", res2.get("r", "timeout"))
	t._check(steps.has("lanterns") and steps.has("stars") and steps.has("back") and steps.has("ashore"), "lanterns, stars, rowing back, ashore (%s)" % str(steps))
	t._check(day_set and steps.has("stars"), "the clock turned to day mid-ritual and they still finished the night ritual (stars)")
	t._check(not snap_mid.is_empty() and String(snap_mid.get("step", "")) == "lanterns" and (snap_mid.get("participants", []) as Array).size() == 2,
		"the ritual's step is persistent (ScenePersist contract) %s" % str(snap_mid))
	var names := lr.log.filter(func(e): return e.has("lantern_at")).map(func(e): return "%s@%s" % [e.name, e.where])
	t._check(names.has("Aiko@pier") and names.has("Kenji@boat") and names.has("Sora@boat") and names.has("Mei@boat"),
		"every viewer's lantern rose with its name: Aiko's (waiting) on arrival at the pier, the others beside the boat (%s)" % str(names))
	var gaps := []
	for i in range(1, launches.size()):
		gaps.append(snappedf(float(launches[i][2]) - float(launches[i - 1][2]), 0.1))
	t._check(not gaps.is_empty() and gaps.all(func(g): return g >= 6.0), "one at a time, no collisions (gaps %s s)" % str(gaps))
	var thanked := lr.log.filter(func(e): return String(e.where) == "boat")
	var by_name := thanked.all(func(e): return (e.lines as Array).any(func(l): return String(l).contains(String(e.name))))
	t._check(thanked.size() >= 3 and by_name, "each one thanked by name from the boat (%d)" % thanked.size(), JSON.stringify(thanked))
	t._check(lr.boat._floaters.size() >= 2, "their wish lanterns float on the water (%d)" % lr.boat._floaters.size())
	t._check(worst_shore < -1.0, "the boat stayed on open water (shore margin %.2f m)" % -worst_shore)
	t._check(pier_hits == 0, "the boat never went through the pier (%d samples)" % pier_hits)
	await t._wait(1.5)
	for c in [mika, luna]:
		var lp: Vector3 = lk.to_local(c.global_position)
		t._check(not c.seated and c.is_physics_processing() and absf(lp.x - 4.0) < 1.0 and absf(lp.y - 0.62) < 0.25,
			"%s stands on the pier again (%s, physics %s)" % [c.character_id, str(lp.snappedf(0.01)), c.is_physics_processing()])
	t._check(lr.snapshot().is_empty() and lr.running == "", "no ritual left running")
	t._check(int(mb.mind.knowledge.get("lake_boat_night", -1)) == nid, "tonight's boat ritual is remembered")
	t._check(lr.pending.is_empty() and lr.queue.is_empty(), "no lantern left waiting")
	t._check(mb.options().filter(func(o): return o.kind == "lakeboat").is_empty(), "the boat is not offered again tonight")
	t.report["lake_ritual"] = {"result": str(res2.get("r", {})).left(200), "steps": steps, "launches": launches, "gaps": gaps,
		"log": lr.log, "shore_margin": -worst_shore, "pier_hits": pier_hits}
