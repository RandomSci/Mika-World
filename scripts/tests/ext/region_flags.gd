extends RefCounted
## --mktest=region_flags (2026-10-20 go live, Selwyn: "make sure Mika and Luna's brain never picks or travels to a
## flagged-off region, and that chat suggestions can't send them there either"): with StreamFlags "regions" closing
## the library, the tower and the woods, every way there is tried and must be refused, then they live 3 minutes
## (chat asking for the closed places included) and must never be anywhere but the open areas. Marks "[regions] ...".

const CLOSED := {"arcane_library": "ancient_spell_library", "mentor_tower": "mentors_tower", "whispering_woods": "whispering_woods"}


static func run(t) -> void:
	var main = t.main
	main.director.enabled = true
	print("[regions] open: %s" % str(WorldState.areas.keys().filter(func(a): return StreamFlags.area_allowed(a))))
	# 1. their minds: nothing in a closed area is on offer
	for w in main.mage_brains:
		var opts: Array = main.mage_brains[w].options()
		var bad := opts.filter(func(o): return not main.mage_brains[w]._option_open(o))
		var visits := opts.filter(func(o): return String(o.kind) == "visit").map(func(o): return String(o.key))
		print("[regions] %s: %d options, visits %s, closed ones %d" % [w, opts.size(), str(visits), bad.size()])
		t._check(bad.is_empty(), "%s is offered nothing in a closed area" % w)
		t._check(not visits.any(func(k): return k.contains("library") or k.contains("tower") or k.contains("woods")), "%s has no visit to a closed place" % w)
	# 2. every way of travelling there is refused
	for area in CLOSED:
		var loc: String = CLOSED[area]
		var a: Dictionary = main.travel.travel_to(loc, "walk")
		var j: Dictionary = main.journeys.start(area, "test") if main.get("journeys") else {"ok": false, "error": "no journeys"}
		var s: Dictionary = await main.streaming.travel(area, main.characters["mika"])
		print("[regions] %s: travel_to %s (%s), journey %s (%s), loader %s (%s)" % [area, str(a.get("ok")), String(a.get("error", "")),
			str(j.get("ok")), String(j.get("error", "")), str(s.get("ok")), String(s.get("reason", ""))])
		t._check(not a.get("ok", false) and not j.get("ok", false) and not s.get("ok", false), "%s refused on every path" % area)
		t._check(main.streaming.current_id == "sanctuary", "still in the sanctuary after asking for %s" % area)
	# an open place still works (the lake's route is allowed)
	var lake_ok: Dictionary = main.travel.travel_to("lantern_lake", "walk")
	t._check(lake_ok.get("ok", false), "the lake can still be walked to (%s)" % String(lake_ok.get("error", "")))
	main.travel.cancel("test")
	# 3. three minutes of life, chat asking for the closed places
	var chat := [["Kai", "Mika go to the library please!"], ["Rin", "Luna can you visit the mentor's tower?"], ["Mo", "go explore the whispering woods"],
		["Ana", "take us to the ancient spell library"]]
	var t0: float = t._game_t
	var next_chat := 5.0
	var ci := 0
	var areas := {}
	while t._game_t - t0 < 180.0:
		await t.get_tree().process_frame
		var el: float = t._game_t - t0
		if el >= next_chat and ci < chat.size() and main.live_link:
			main.live_link._on_message({"type": "youtube-live-selected-message", "active": true, "author": chat[ci][0], "message": chat[ci][1]})
			print("[regions] %3.0fs chat %s: %s" % [el, chat[ci][0], chat[ci][1]])
			ci += 1
			next_chat += 20.0
		var here := String(main.streaming.current_id)
		areas[here] = int(areas.get(here, 0)) + 1
		for w in ["mika", "luna"]:
			var la := String(WorldState.mind(w).location.get("area", ""))
			if la != "" and not StreamFlags.area_allowed(la):
				areas["%s_mind_in_%s" % [w, la]] = 1
	print("[regions] areas seen %s" % JSON.stringify(areas.keys()))
	t._check(areas.keys().all(func(a): return StreamFlags.area_allowed(String(a))), "only open areas in 3 minutes (%s)" % str(areas.keys()))
