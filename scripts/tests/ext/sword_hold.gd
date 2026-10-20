extends RefCounted
## Sword hold close-up (2026-10-20, Selwyn: "Zoom in on how luna and mika holds the sword"): each girl alone with her
## weapon (--weapon-level=20), her stance, guard and swings, filmed close on her hands (the director's hand shot) and
## at mid range from the front. Marks "[hold] <girl> <view> <clip> from_frame=N".

const CLIPS := {"mika": ["ualf:Sword_Idle", "ualf:Sword_Block", "ualf:Sword_Regular_A", "ualf:Sword_Attack"],
	"luna": ["sword:great_sword_idle", "sword:great_sword_blocking", "sword:great_sword_slash", "sword:great_sword_slash_4"]}


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
	FightDirector.set_hour(main, 13.0)
	await t._wait(1.0)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 3, "axis_deg": 0.0, "bare": true})
	var sim := MeleeSim.make(d, {"seed": 3, "length": 9999.0, "demo": true, "melee": true, "start_gap": 8.0})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	var pp := PairedPlay.make(sim)
	for id in String(RenderProfile.options.get("girls", "mika,luna")).split(","):
		var other := "luna" if id == "mika" else "mika"
		(d.F[id].c as Node3D).visible = true
		(d.F[other].c as Node3D).visible = false
		var c0: Vector3 = d.pos(id)
		var fwd := sim._flat(d.pos(other) - d.pos(id)).normalized()
		var gy := FightDirector.ground_y(d.F[id].c, c0)
		for view in String(RenderProfile.options.get("views", "hand,front")).split(","):
			for clip in CLIPS[id]:
				if view == "hand":
					d.cut(d.ft + 0.001, "hand", id, {"bone": "RightHand"})
				elif view == "side":
					d.cut(d.ft + 0.001, "fixed", id, {"pos": c0 - fwd.cross(Vector3.UP) * 2.4 + fwd * 0.4 + Vector3(0, gy - c0.y + 1.15, 0),
						"look": Vector3(c0.x, gy + 1.0, c0.z) + fwd * 0.4, "fov": 44.0})
				else:
					d.cut(d.ft + 0.001, "fixed", id, {"pos": c0 + fwd * 1.7 + fwd.cross(Vector3.UP) * 0.5 + Vector3(0, gy - c0.y + 1.2, 0),
						"look": Vector3(c0.x, gy + 1.05, c0.z), "fov": 40.0})
				print("[hold] %s %s %s from_frame=%d" % [id, view, clip, Engine.get_frames_drawn()])
				var L := pp.drive(id, clip, 0.0, -1.0, 1.0, 0.1, fwd)
				var w0: float = sim.t
				while sim.t < w0 + maxf(L, 1.2) + 0.2:
					pp.update()
					d.F[id].pos = c0
					await t.get_tree().process_frame
	t._check(true, "holds shown")
	pp.wp.sheathe("luna")
	pp.wp.sheathe("mika")
	pp.release()
	await t._wait(0.4)
	sim.teardown()
	d.teardown()
