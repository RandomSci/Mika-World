extends RefCounted
## --mktest=lunajoin (26 Oct live: the save had Luna in the Arcane Library and Mika at the Mentor's Tower; Luna stayed
## out of view all night): with Luna saved in another area, every area Mika arrives in shows Luna beside her.
## Marks "[lunajoin] ...".


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var ok := 0
	var stops := ["lantern_lake", "sanctuary", "mentor_tower"]
	for area in stops:
		# Luna away in another area, out of view, as the live save had her
		var away := "arcane_library" if area != "arcane_library" else "lantern_lake"
		main._park_mages()
		WorldState.mind("luna").set_location(away, Vector3(1.2, 0.0, -1.6))
		luna.visible = false
		luna.set_physics_process(false)
		await main.streaming.travel(area, mika)
		await t._wait(2.0)
		print("[lunajoin]   current %s, luna mind %s, streaming state %s" % [main.streaming.current_id, str(WorldState.mind("luna").location), main.streaming.state])
		var d := luna.global_position.distance_to(mika.global_position)
		var good: bool = luna.visible and d < 6.0 and main.sim_mode("luna") == "nearby"
		print("[lunajoin] %s: luna visible %s, %.1f m from Mika, mode %s, %s" % [area, str(luna.visible), d, main.sim_mode("luna"), "OK" if good else "FAIL"])
		if good:
			ok += 1
	t._check(ok == stops.size(), "Luna joins Mika in every area she arrives in (%d of %d)" % [ok, stops.size()])
