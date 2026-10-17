extends SceneTree
## Day 3 test `discovery_rate` (headless, no world, no GPU): simulated hours of play through DiscoveryDirector's own
## decision code. Checks: about one find an hour on average for a typical day's mix of places, more where she explores
## (off-path / unexplored / new area / night / lost), less on the home dais; rarity tiers near 60/28/10/2; never the same
## kind twice in a row; no repeat inside the memory window; the minimum gap honoured; the Phoenix clues only in order.
## usage: godot --headless --path . -s res://scripts/tests/discovery_rate_test.gd

var failed := false


func _check(ok: bool, what: String) -> void:
	print("[disc_rate] %s %s" % ["  ok  " if ok else "FAIL  ", what])
	if not ok:
		failed = true


func _initialize() -> void:
	var p := DiscoveryRules.load_pool()
	_check(not p.is_empty() and (p.finds as Array).size() >= 40, "pool loaded (%d finds)" % (p.get("finds", []) as Array).size())
	var regions := ["arcane_sanctuary", "enchanted_forest", "fantasy_village", "crystal_caverns", "celestial_highlands", "grand_academy"]
	for r in regions:
		var n := (p.finds as Array).filter(func(f): return (f.regions as Array).has(r)).size()
		_check(n >= 5, "%s has its own finds (%d)" % [r, n])
	var kinds := {}
	var tiers := {}
	for f in p.finds:
		kinds[f.kind] = true
		tiers[f.tier] = true
	_check(kinds.size() >= 9, "all kinds present: %s" % str(kinds.keys()))
	_check(tiers.size() == 4, "all four tiers present: %s" % str(tiers.keys()))

	# a typical day: much of it at home (some on the dais), outings in the home region, journeys elsewhere, nights
	var typical := [
		[30.0, {"home_core": true}],
		[25.0, {}],
		[15.0, {"off_path": true}],
		[8.0, {"off_path": true, "unexplored": true}],
		[8.0, {"new_area": true}],
		[10.0, {"night": true}],
		[3.0, {"rain": true}],
		[1.0, {"lost": true, "off_path": true}],
	]
	var day := DiscoveryRules.simulate(p, typical, 600 * 60, 11, regions)
	print("[disc_rate] typical mix, 600 h: ", JSON.stringify({"per_hour": snappedf(day.per_hour, 0.01), "tiers": day.tiers, "kinds": day.kinds, "min_gap": day.min_gap, "max_gap": day.max_gap}))
	_check(day.per_hour > 0.8 and day.per_hour < 1.25, "about one find an hour on a typical day (%.2f / h)" % day.per_hour)
	_check(int(day.back_to_back) == 0, "never the same kind twice in a row (%d)" % int(day.back_to_back))
	_check(int(day.dupes_in_memory) == 0, "no find repeats within the last 10 finds (%d)" % int(day.dupes_in_memory))
	_check(float(day.min_gap) >= 14.0, "the minimum gap is honoured (shortest %.0f min)" % float(day.min_gap))
	_check(float(day.max_gap) < 200.0, "no endless dry spell (longest %.0f min)" % float(day.max_gap))
	var total := 0.0
	for t in day.tiers:
		total += float(day.tiers[t])
	var share := func(t): return float(day.tiers.get(t, 0)) / maxf(total, 1.0)
	_check(absf(share.call("common") - 0.60) < 0.07 and absf(share.call("uncommon") - 0.28) < 0.06, "tiers near 60 / 28 (%.2f / %.2f)" % [share.call("common"), share.call("uncommon")])
	_check(share.call("rare") > 0.05 and share.call("rare") < 0.15, "rare near 10 %% (%.3f)" % share.call("rare"))
	_check(int(day.tiers.get("legendary", 0)) >= 2, "legendary finds happen, rarely (%d in 600 h)" % int(day.tiers.get("legendary", 0)))

	# where she wanders matters
	var dais := DiscoveryRules.simulate(p, [[1.0, {"home_core": true}]], 300 * 60, 5, regions)
	var wild := DiscoveryRules.simulate(p, [[1.0, {"off_path": true, "unexplored": true}]], 300 * 60, 5, regions)
	var lost := DiscoveryRules.simulate(p, [[1.0, {"off_path": true, "lost": true}]], 300 * 60, 5, regions)
	print("[disc_rate] per hour: dais %.2f, off the paths %.2f, lost %.2f" % [dais.per_hour, wild.per_hour, lost.per_hour])
	_check(wild.per_hour > dais.per_hour * 1.5, "off the paths finds come more often than on the dais (%.2f vs %.2f)" % [wild.per_hour, dais.per_hour])
	_check(lost.per_hour > wild.per_hour, "getting lost finds the most (%.2f)" % lost.per_hour)

	# the Phoenix path: its clues only in order
	var order_ok := true
	var seen := {}
	for e in day.log:
		if String(e.kind) != "phoenix_clue":
			continue
		if e.id == "phoenix_feather" and not seen.has("phoenix_warm_ash"):
			order_ok = false
		if e.id == "phoenix_hearth_mark" and not seen.has("phoenix_feather"):
			order_ok = false
		seen[e.id] = true
	_check(order_ok and seen.has("phoenix_warm_ash"), "the Phoenix path stays in the pool, clues in order (%s)" % str(seen.keys()))
	print("[disc_rate] %s" % ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
