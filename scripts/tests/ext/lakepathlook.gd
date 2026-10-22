extends RefCounted
## --mktest=lakepathlook: the lake path at night at several glow levels, stills from the dance's wide shot (the first
## runs burnt it to plain white). Stills in ~/.cache/mika_qa/fix_tests/lakepath_<energy>.png.


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("lake path look")
	await t._hold_all()
	main.travel.cancel("lake path look")
	if main.streaming.current_id != "lantern_lake":
		await main.streaming.travel("lantern_lake", main.characters["mika"])
	if main.day_night:
		main.day_night.set_override(true)
	await t._wait(3.0)
	var lwd: LakeWaterDance = LakeWaterDance.instance
	var lake: Node3D = lwd._lake()
	var lane: Dictionary = lwd._lane(lake, main.streaming.current)
	var path := WaterPath.new()
	lake.add_child(path)
	path.build(lane.shore - lane.fwd * 0.4, LakeWaterDance.SPOT, LakeWaterDance.RADIUS)
	path.set_solid(true)
	await path.form(0.5)
	var c: Vector3 = LakeWaterDance.SPOT + Vector3(0, 0.95, 0)
	for id in ["mika", "luna"]:
		var ch: WorldCharacter = main.characters[id]
		if main.teleport_guard:
			main.teleport_guard.allow(ch)
		ch.global_position = lake.to_global(LakeWaterDance.SPOT + Vector3(0.75 if id == "mika" else -0.75, WaterPath.TOP, 0))
	main.director.begin_scene(func(_d): return {"pos": lake.to_global(c + Vector3(2.4, 1.1, 8.5)), "look": lake.to_global(c), "fov": 50.0, "rate": 9.0})
	print("[lakepathlook] materials %s" % str(path.mats.map(func(m): return [m.shader.resource_path, m.get_shader_parameter("energy"), m.get_shader_parameter("fade"), m.get_shader_parameter("grow")])))
	for e in [0.4, 0.7, 1.0, -1.0]:
		for m in path.mats:
			m.set_shader_parameter("energy", maxf(e, 0.0))
		path.visible = e >= 0.0          # -1: the path hidden (is the white even the path?)
		await t._wait(1.5)
		var img: Image = t.get_viewport().get_texture().get_image()
		img.save_png("/home/selwyn/.cache/mika_qa/fix_tests/lakepath_%.2f.png" % e)
		print("[lakepathlook] still at energy %.2f" % e)
	main.director.end_scene()
	path.queue_free()
	t._check(true, "stills taken")
