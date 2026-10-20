extends RefCounted
## Glaive hold check (2026-10-20, Selwyn: "The way Luna holds the weapon is wrong. It's not a sword, it's like a
## spear"): Luna with her Shadow Glaive (--weapon-level=20) through her stance and three swings, filmed from the side
## and the front at mid range. Marks "[glaive] <clip> from_frame=N".

const CLIPS := ["sword:great_sword_idle", "sword:great_sword_slash_4", "sword:great_sword_high_spin_attack", "sword:great_sword_blocking_2"]


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	for id in main.characters:
		if not (id in ["mika", "luna"]):
			(main.characters[id] as Node3D).visible = false
	FightDirector.set_hour(main, 16.6)
	await t._wait(1.0)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 3, "axis_deg": 0.0, "bare": true})
	var sim := MeleeSim.make(d, {"seed": 3, "length": 9999.0, "demo": true, "melee": true, "start_gap": 6.0})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	var pp := PairedPlay.make(sim)
	(d.F["mika"].c as Node3D).visible = false
	var c0: Vector3 = d.pos("luna")
	var gy := FightDirector.ground_y(d.F["luna"].c, c0)
	var fwd := sim._flat(d.pos("mika") - d.pos("luna")).normalized()
	var side := fwd.cross(Vector3.UP)
	for view in [[side * 3.2, "side"], [fwd * 3.4 + side * 0.8, "front"]]:
		d.cut(d.ft + 0.001, "fixed", "luna", {"pos": c0 + (view[0] as Vector3) + Vector3(0, gy - c0.y + 1.1, 0), "look": Vector3(c0.x, gy + 1.0, c0.z), "fov": 42.0})
		for clip in CLIPS:
			print("[glaive] %s %s from_frame=%d" % [view[1], clip, Engine.get_frames_drawn()])
			var L := pp.drive("luna", clip, 0.0, -1.0, 1.0, 0.1, fwd)
			var w0: float = sim.t
			while sim.t < w0 + L + 0.3:
				pp.update()
				d.F["luna"].pos = c0
				await t.get_tree().process_frame
	t._check(true, "glaive shown")
	pp.wp.sheathe("luna")
	pp.wp.sheathe("mika")
	pp.release()
	await t._wait(0.4)
	sim.teardown()
	d.teardown()
