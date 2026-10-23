extends RefCounted
## --mktest=spots (23 Oct, Selwyn's checklist: "Detailed 6 regions, more places to explore each region", "More
## stories/plots"): every area builds its small named places (PlaceSpots) on open ground, none in another, none on a
## trail; the brain offers them; the Heartstone chapter being done starts "The Lamplighter's Trail", whose first lead
## sends them to the woods' wayshrine, where the mark now stands; the closer look gives the clue, the girls remember it
## and the trail moves on. Marks "[spots] ...". --spots-areas=a,b limits the areas (default: every area with spots).

const ORDER := ["sanctuary", "mentor_tower", "arcane_library", "lantern_lake", "whispering_woods", "ancient_grove", "river_valley",
	"village", "observatory_hill", "crystal_caverns", "deep_caverns", "highland_path", "celestial_summit", "academy", "great_library"]


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("spots test")
	await t._hold_all()
	await t._wait(2.0)
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	var mc: WorldCharacter = main.characters["mika"]
	var only := String(RenderProfile.options.get("spots-areas", ""))
	var areas: Array = ORDER if only == "" else Array(only.split(",")).filter(func(x): return x != "story")
	var total := 0
	var want := 0
	for a in areas:
		want += PlaceSpots.specs(a).filter(func(s): return PlaceSpots.active(s)).size()
		if main.streaming.current_id != a:
			var r: Dictionary = await main.streaming.travel(a, mc, false)
			if not r.get("ok", false) and main.streaming.current_id != a:
				t._check(false, "%s loads" % a, str(r))
				continue
		await t._wait(1.0)
		var area = main.streaming.current
		var spots: Array = area.interactables.keys().filter(func(k): return String(k).begins_with("spot:"))
		total += spots.size()
		var pos: Array = spots.map(func(k): return (area.interactables[k] as Node3D).global_position)
		var close := 0
		for i in pos.size():
			for j in range(i + 1, pos.size()):
				if (pos[i] as Vector3).distance_to(pos[j]) < PlaceSpots.MIN_SPACING - 0.01:
					close += 1
		var on_trail := 0
		if area.has_method("trail_at"):
			on_trail = pos.filter(func(p): return float(area.trail_at(p.x, p.z)) > 0.12).size()
		# each one reachable: the navmesh comes within 2.5 m of its approach
		var map := mc.get_world_3d().navigation_map
		var unreachable := []
		for k in spots:
			var it: Interactable = area.interactables[k]
			var near := NavigationServer3D.map_get_closest_point(map, it.global_position)
			if Vector2(near.x - it.global_position.x, near.z - it.global_position.z).length() > 2.5:
				unreachable.append(String(k))
		var rep: Dictionary = main.streaming.last_report
		print("[spots] %s: %d of %d places, worst build step %s ms, too close %d, on a trail %d, unreachable %s | %s" % [a, spots.size(),
			PlaceSpots.specs(a).filter(func(s): return PlaceSpots.active(s)).size(), str(rep.get("worst_build_step_ms", -1)), close, on_trail,
			str(unreachable), ", ".join(spots.map(func(k): return "%s %s" % [String(k).trim_prefix("spot:"), str(Vector3i((area.interactables[k] as Node3D).global_position))]))])
		t._check(close == 0 and on_trail == 0, "%s: no place on another or on a trail" % a)
		t._check(unreachable.is_empty(), "%s: every place can be walked to" % a, str(unreachable))
		var brain = main.mage_brains["mika"]
		brain.hold = false
		var offered: Array = brain.options().filter(func(o): return String(o.kind) == "spot")
		brain.hold = true
		t._check(offered.size() == spots.size(), "%s: the brain offers its %d places (%d)" % [a, spots.size(), offered.size()])
	print("[spots] built %d places of %d in %d areas" % [total, want, areas.size()])
	t._check(total >= want - 2, "nearly every place found ground (%d of %d)" % [total, want])
	if only != "" and not only.contains("story"):
		return
	# ---- the story: the Heartstone done, the next chapter begins
	var st = main.story
	print("[spots] story chapter %d %s stage %s complete %s" % [st.chapter + 1, st.data.title, st.stage, str(st.complete())])
	if st.chapter == 0:
		for c in st.data.clues:
			for k in st.data.clues[c].any_knowledge:
				WorldState.knowledge[k] = 1
		st.evaluate(true)
		WorldState.knowledge["chapter_done:heartstone"] = Time.get_unix_time_from_system() - 700.0
		st.evaluate()
	t._check(st.chapter == 1 and st.chapter_id() == "lamplighter", "the next chapter has begun: %s" % st.data.title)
	t._check(WorldState.knowledge.has("chapter_started:lamplighter"), "the chapter's start is saved")
	var leads: Array = st.next_leads()
	print("[spots] objective: %s | leads %s" % [st.objective(), str(leads.map(func(l): return "%s (%s)" % [l.lead, l.area]))])
	t._check(leads.size() == 1 and String(leads[0].spot) == "woods_shrine", "the first lead is the woods' wayshrine")
	# Mika's brain sets out for the woods (a story visit)
	if main.streaming.current_id != "sanctuary":
		await main.streaming.travel("sanctuary", mc, false)
		await t._wait(1.0)
	var b = main.mage_brains["mika"]
	b.hold = false
	var sv: Array = b.options().filter(func(o): return String(o.kind) == "visit" and bool(o.get("story", false)))
	print("[spots] story visits %s" % str(sv.map(func(o): return "%s %.2f" % [o.label, float(b.score(o).get("utility", b.score(o).get("u", 0.0)))])))
	t._check(sv.any(func(o): return String(o.area) == "whispering_woods"), "Mika's brain can set out on the trail to the woods")
	b.hold = true
	await main.streaming.travel("whispering_woods", mc, false)
	await t._wait(1.0)
	var area2 = main.streaming.current
	t._check(area2.interactables.has("spot:woods_shrine"), "the mark stands at the wayshrine now")
	b.hold = false
	var so: Array = b.options().filter(func(o): return String(o.get("spot", "")) == "woods_shrine")
	t._check(not so.is_empty() and String(so[0].lead) != "", "the wayshrine is offered as the trail's next step")
	if so.is_empty():
		return
	var top: Array = b.ranked().slice(0, 4).map(func(x): return "%s %.2f" % [x.label, float(x.utility)])
	print("[spots] Mika's top four in the woods %s" % str(top))
	t._check(String(b.ranked()[0].get("spot", "")) == "woods_shrine", "the trail is what she wants most here")
	var lc: WorldCharacter = main.characters["luna"]
	if main.teleport_guard:
		main.teleport_guard.allow(lc)
	lc.global_position = NavigationServer3D.map_get_closest_point(lc.get_world_3d().navigation_map, mc.global_position + Vector3(1.5, 0, 0))
	# (a paused brain's _cancel stops every walk at once; the arrival walk into the woods must be over too)
	var tw := Time.get_ticks_msec()
	while mc.current_action == "navigate_to" and Time.get_ticks_msec() - tw < 15000:
		await t.get_tree().process_frame
	await t._wait(1.0)
	b._cancel = false
	var res: Dictionary = await PlaceSpots.visit(b, so[0])
	print("[spots] visit %s" % str(res))
	t._check(bool(res.get("ok", false)), "Mika walked over and looked closer", str(res))
	t._check(WorldState.knowledge.has("clue:ash_mark_woods"), "she found the clue")
	t._check(st.found.has("ash_woods"), "the story counts it")
	t._check(WorldState.mind("mika").knowledge.has("spot:woods_shrine"), "she remembers the place")
	var leads2: Array = st.next_leads()
	print("[spots] next leads %s" % str(leads2.map(func(l): return "%s (%s)" % [l.lead, l.area])))
	t._check(leads2.size() == 2, "the trail moves on to the grove and the village")
	b.hold = true
