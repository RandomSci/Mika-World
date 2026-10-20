extends RefCounted
## The petal storm by eye (PetalStorm): Mika gathers petals into her hand, pours a river into Luna, engulfs her and
## scatters it; Luna answers with her own river and wraps herself in a shield. Marks "[petal] <step> at frame N".

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.performance:
		main.performance.set_process(false)
	for id in main.characters:
		if not (id in ["mika", "luna"]):
			(main.characters[id] as Node3D).visible = false
	FightDirector.set_hour(main, float(RenderProfile.options.get("hour", "19.4")))
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.0)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 4, "axis_deg": 0.0, "bare": true})
	d.set_process(true)
	var c0: Vector3 = d.center
	d.F.mika.pos = c0 + Vector3(-2.6, 0, 0)
	d.F.luna.pos = c0 + Vector3(2.6, 0, 0)
	await t._wait(1.0)
	var hand := func(id: String) -> Callable:
		return func() -> Vector3: return d.bone(id, "RightHand") + Vector3(0, 0.05, 0)
	var chest := func(id: String) -> Callable:
		return func() -> Vector3: return d.chest(id)
	d.cut(d.ft + 0.001, "hero_low", "mika", {})
	print("[petal] mika gather at frame %d" % Engine.get_frames_drawn())
	var sm := PetalStorm.make(main, "mika")
	sm.gather(hand.call("mika"), 1.4).river(hand.call("mika"), chest.call("luna"), 0.9).engulf(chest.call("luna"), 1.3, 1.6).scatter(chest.call("luna"), 1.2, 1.4)
	sm.finish()
	await t._wait(1.4)
	d.cut(d.ft + 0.001, "wide_low", "mika", {})
	print("[petal] mika river at frame %d" % Engine.get_frames_drawn())
	await t._wait(0.9)
	d.cut(d.ft + 0.001, "orbit", "luna", {"from": 20.0, "to": 80.0, "r": 6.0})
	print("[petal] mika engulf at frame %d" % Engine.get_frames_drawn())
	await t._wait(1.6)
	print("[petal] mika scatter at frame %d" % Engine.get_frames_drawn())
	await t._wait(1.6)
	d.cut(d.ft + 0.001, "hero_low", "luna", {})
	print("[petal] luna gather at frame %d" % Engine.get_frames_drawn())
	var sl := PetalStorm.make(main, "luna")
	sl.gather(hand.call("luna"), 1.2).river(hand.call("luna"), chest.call("mika"), 0.9).scatter(chest.call("mika"), 1.0, 1.0).shield(chest.call("luna"), 0.75, 2.2).scatter(chest.call("luna"), 1.4, 1.2)
	sl.finish()
	await t._wait(1.2)
	d.cut(d.ft + 0.001, "profile", "luna", {})
	print("[petal] luna river at frame %d" % Engine.get_frames_drawn())
	await t._wait(1.9)
	d.cut(d.ft + 0.001, "two_mid", "luna", {})
	print("[petal] luna shield at frame %d" % Engine.get_frames_drawn())
	await t._wait(2.4)
	print("[petal] end at frame %d" % Engine.get_frames_drawn())
	t._check(true, "petal techniques played")
	d.teardown()
