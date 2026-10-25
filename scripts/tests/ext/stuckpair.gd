extends RefCounted
## --mktest=stuckpair (25 Oct live, after stuckprobe: alone, every walk from the lake and waterfall stuck spots got through;
## the live targets were 1.2 m away, where the other girl stood, or 21 m up the lake hill). Replays each live walk with
## the other girl where she was. Marks "[stuckpair] ...".

# area, walker, from, to, the other girl's spot (null = away)
const CASES := [
	["lantern_lake", "luna", Vector3(-18.9, 1.6, 30.2), Vector3(-15.2, 7.4, 50.9), Vector3(-15.2, 7.4, 50.9)],
	["lantern_lake", "luna", Vector3(5.1, 3.3, 37.2), Vector3(5.1, 3.3, 38.4), Vector3(5.1, 3.3, 38.6)],
	["lantern_lake", "luna", Vector3(5.1, 3.3, 37.2), Vector3(5.1, 3.3, 38.4), null],
	["river_valley", "luna", Vector3(113.2, 3.3, 17.8), Vector3(114.4, 3.3, 18.2), Vector3(114.6, 3.3, 18.3)],
	["river_valley", "luna", Vector3(113.2, 3.3, 17.8), Vector3(114.4, 3.3, 18.2), null],
	["village", "mika", Vector3(-10.6, 0.0, 4.4), Vector3(-11.8, 0.0, 4.1), Vector3(-12.0, 0.0, 4.0)],
	["village", "mika", Vector3(-10.6, 0.0, 4.4), Vector3(-11.8, 0.0, 4.1), null],
]


static func _put(t, c: WorldCharacter, at: Vector3) -> void:
	if t.main.teleport_guard:
		t.main.teleport_guard.allow(c)
	c.stop_action()
	c.visible = true
	c.set_physics_process(true)
	c.velocity = Vector3.ZERO
	c.global_position = at + Vector3(0, 0.1, 0)


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	for cs in CASES:
		var walker: WorldCharacter = main.characters[cs[1]]
		var other: WorldCharacter = main.characters["luna" if cs[1] == "mika" else "mika"]
		if main.streaming.current_id != cs[0]:
			await main.streaming.travel(cs[0], main.characters["mika"])
		await t._wait(2.0)
		_put(t, walker, cs[2])
		_put(t, other, cs[4] if cs[4] != null else cs[2] + Vector3(0, 0, -15))
		await t._wait(0.8)
		var map: RID = walker.get_world_3d().navigation_map
		var path := NavigationServer3D.map_get_path(map, walker.global_position, cs[3], true)
		var plen := 0.0
		for i in range(1, path.size()):
			plen += path[i - 1].distance_to(path[i])
		var res := [null]
		var cb := func(_a, okk, detail): res[0] = "%s %s" % ["ok" if okk else "fail", detail]
		walker.action_finished.connect(cb, CONNECT_ONE_SHOT)
		var p0 := walker.global_position
		walker.navigate_to(cs[3])
		var t0 := Time.get_ticks_msec()
		while res[0] == null and Time.get_ticks_msec() - t0 < 40000:
			await t._wait(0.25)
		print("[stuckpair] %s %s %s -> %s, other %s: path %d points %.1f m, first turn %s; moved %.1f m, result %s, ended %s" % [cs[0], cs[1],
			str(cs[2]), str(cs[3]), "AT the target" if cs[4] != null else "away", path.size(), plen,
			str(path[1].snapped(Vector3.ONE * 0.1)) if path.size() > 1 else "-", walker.global_position.distance_to(p0), str(res[0]),
			str(walker.global_position.snapped(Vector3.ONE * 0.1))])
	t._check(true, "pair probe ran")
