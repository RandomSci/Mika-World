extends RefCounted
## --mktest=stuckloop (25 Oct live): a girl who truly cannot move (her pace held at 0). The walk's recovery runs its
## two tries and then ends "stuck" (no error), and Luna's own catch-up with Mika backs off and tries other sides
## instead of the same walk every 3 s. Marks "[stuckloop] ...".


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	await t._wait(2.0)
	var map: RID = luna.get_world_3d().navigation_map
	var a := NavigationServer3D.map_get_closest_point(map, Vector3(4.5, 0, 3.0))
	var far := NavigationServer3D.map_get_closest_point(map, a + Vector3(16, 0, 6))
	for c in [luna, mika]:
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.velocity = Vector3.ZERO
	luna.global_position = a
	mika.global_position = far
	await t._wait(0.8)
	# 1. the walk itself
	luna.pace = 0.0
	var res := [null]
	var cb := func(x, okk, detail): if x == "navigate_to": res[0] = [okk, detail]
	luna.action_finished.connect(cb)
	var t0 := Time.get_ticks_msec()
	luna.navigate_to(far, false)
	while res[0] == null and Time.get_ticks_msec() - t0 < 20000:
		await t._wait(0.25)
	luna.action_finished.disconnect(cb)
	print("[stuckloop] frozen walk ends after %.1f s: %s" % [(Time.get_ticks_msec() - t0) / 1000.0, str(res[0])])
	t._check(res[0] != null and not res[0][0] and String(res[0][1]).contains("after 2 tries"), "a frozen walk tries twice to get free, then ends stuck")
	# 2. Luna's brain catching up, 40 s with her frozen (the pace is put back to 0 each frame: the follow code sets it)
	var lb: SanctuaryBrain = main.mage_brains["luna"]
	var fr := [true]
	var pin := func():
		if fr[0]:
			luna.pace = 0.0
	main.get_tree().physics_frame.connect(pin)
	lb.hold = false
	await t._wait(40.0)
	fr[0] = false
	main.get_tree().physics_frame.disconnect(pin)
	lb.hold = true
	luna.pace = 1.0
	print("[stuckloop] catch-up failures in a row after 40 s: %d" % lb._rejoin_fails)
	t._check(lb._rejoin_fails >= 1 and lb._rejoin_fails <= 4, "the catch-up backs off (%d tries in 40 s, the old loop made about 13)" % lb._rejoin_fails)
