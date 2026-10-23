extends RefCounted
## --mktest=racetest: the little race (23 Oct live, "a little fun"). Luna beside Mika, the race on Mika's list, invited
## and run to the end: both run to the finish, a winner, banter before and after, Mika remembers it.


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("race test")
	await t._hold_all()
	await t._wait(3.0)
	var a = main.mage_brains["mika"]
	var b = main.mage_brains["luna"]
	a.set_enabled(false)
	b.set_enabled(false)
	await t._wait(1.0)
	a.hold = false
	b.hold = false
	a.current = {}
	b.current = {}
	var mc: WorldCharacter = main.characters["mika"]
	var lc: WorldCharacter = main.characters["luna"]
	if main.teleport_guard:
		main.teleport_guard.allow(lc)
	lc.global_position = NavigationServer3D.map_get_closest_point(lc.get_world_3d().navigation_map, mc.global_position + Vector3(1.6, 0, 0))
	await t._wait(1.0)
	var opts: Array = a.options().filter(func(o): return String(o.get("sub", "")) == "race_together")
	t._check(not opts.is_empty(), "the race is on Mika's list")
	if opts.is_empty():
		return
	var o: Dictionary = opts[0].merged(a.score(opts[0]))
	print("[racetest] option %s utility %.2f to %s" % [o.label, float(o.utility), str(o.target.pos)])
	var top: Array = a.ranked().slice(0, 5).map(func(x): return "%s %.2f" % [x.label, float(x.utility)])
	print("[racetest] top five %s" % str(top))
	main.companionship.force_accept = true
	var p0 := mc.global_position
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await main.companionship.invite(a, "luna", "race_together", o.target)
	print("[racetest] result %s in %.1f s" % [str(r.get("detail", "")), (Time.get_ticks_msec() - t0) / 1000.0])
	t._check(bool(r.get("ok", false)), "the race ran to the end", r.get("detail", ""))
	t._check(mc.global_position.distance_to(p0) > 8.0, "Mika ran to the finish (%.1f m)" % mc.global_position.distance_to(p0))
	t._check(mc.global_position.distance_to(lc.global_position) < 4.0, "they finish together (%.1f m apart)" % mc.global_position.distance_to(lc.global_position))
	t._check(int(WorldState.mind("mika").knowledge.get("races", 0)) >= 1, "Mika remembers the race")
	t._check(mc.pace == 1.0 and lc.pace == 1.0, "their pace is back to normal")
