extends RefCounted
## --mktest=camlead (23 Oct, Selwyn: the follow camera behind Mika all the time on the Luminous River bridge and the
## forest path; a three-quarter front with her face visible, whole body, behind only for a reveal). Two real walks
## with Luna (the river valley over the bridge toward the village, the sanctuary into the Whispering Woods); every
## second: is the lens in front of her (her face toward it), are her head and feet both in the picture, how far.
## Marks "[camlead] <walk> <s> at frame N" for stills.


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("cam lead")
	await t._hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	if main.day_night:
		main.day_night.set_override(false)
	main.director.enabled = true            # (the hold switches the camera director off: "mode off" in the first run)
	var mc: WorldCharacter = main.characters["mika"]
	var total := {"s": 0, "front": 0, "whole": 0, "close": 0}
	var kinds := {"side": 0, "behind": 0}
	for walk in [["river_valley", "village_square", "bridge"], ["sanctuary", "whispering_woods", "forest_path"]]:
		if main.streaming.current_id != walk[0]:
			await main.streaming.travel(walk[0], mc, false)
		await t._wait(3.0)
		var r: Dictionary = main.travel.travel_to(String(walk[1]), "walk")
		print("[camlead] %s walk started %s" % [walk[2], str(r)])
		var t0 := Time.get_ticks_msec()
		var s := 0
		var front := 0
		var whole := 0
		var close := 0
		while main.travel.active() and Time.get_ticks_msec() - t0 < 100000 and main.streaming.current_id == walk[0]:
			await t._wait(1.0)
			if main.streaming.state != "idle":
				continue
			var cam: Camera3D = t.get_viewport().get_camera_3d()
			var fwd := -mc.global_transform.basis.z
			fwd.y = 0
			var to_cam := cam.global_position - mc.global_position
			to_cam.y = 0
			var dot := fwd.normalized().dot(to_cam.normalized())
			var is_front := dot > 0.5          # the lens ahead of her, looking back at her face
			var is_side := absf(dot) <= 0.5    # alongside her, her profile
			var is_behind := dot < -0.94       # straight behind: only the back of her head (within 20 degrees)
			var head := mc.global_position + Vector3(0, 1.62, 0)
			var feet := mc.global_position + Vector3(0, 0.05, 0)
			var is_whole := cam.is_position_in_frustum(head) and cam.is_position_in_frustum(feet)
			var d := cam.global_position.distance_to(mc.global_position + Vector3(0, 1.0, 0))
			s += 1
			front += int(is_front)
			kinds.side += int(is_side)
			kinds.behind += int(is_behind)
			whole += int(is_whole)
			close += int(d < 2.5)
			print("[camlead] %s %d at frame %d front %s whole %s dist %.1f mode %s" % [walk[2], s, Engine.get_frames_drawn(), is_front, is_whole, d, main.director.mode])
		print("[camlead] %s: %d s, face toward the lens %d%%, whole body %d%%, closer than 2.5 m %d" % [walk[2], s, 100 * front / maxi(s, 1), 100 * whole / maxi(s, 1), close])
		total.s += s
		total.front += front
		total.whole += whole
		total.close += close
		main.travel.cancel("cam lead next walk")
		await t._wait(2.0)
	var n := maxi(total.s, 1)
	var rear: int = int(total.s) - int(total.front) - int(kinds.side)
	print("[camlead] ALL: %d s, front %d%%, side %d%%, from behind %d%% (straight behind %d%%), whole %d%%, close %d" % [total.s,
		100 * total.front / n, 100 * kinds.side / n, 100 * rear / n, 100 * kinds.behind / n, 100 * total.whole / n, total.close])
	t._check(total.s > 30, "walked for %d s" % total.s)
	# 24 Oct live, Selwyn: always in front of them felt bad; Day 7: only the back of her head was bad too
	t._check(total.front * 100 / n <= 45, "not always in front of her (%d%%)" % (total.front * 100 / n))
	t._check(kinds.behind * 100 / n <= 25, "not only the back of her head (%d%% straight behind)" % (kinds.behind * 100 / n))
	t._check(int(total.front > 0) + int(kinds.side > 0) + int(rear > 0) >= 2, "more than one follow angle")
	t._check(total.whole * 100 / maxi(total.s, 1) >= 85, "head to feet in the picture (%d%%)" % (total.whole * 100 / maxi(total.s, 1)))
	t._check(total.close == 0, "no close-ups (%d)" % total.close)
