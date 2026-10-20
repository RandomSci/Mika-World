extends RefCounted
## The Effekseer effect gallery (2026-10-20, Selwyn: "spells or effects are still so simple. Search the tools for better
## ones"): every imported CC0 effect (assets/vfx/effekseer) played in turn at the duel spot in the fight's light, Mika
## standing beside it for scale, a fixed three quarter camera. Marks "[gallery] <pack>/<name> dur D from frame A to
## frame B" for the contact sheets. Options --packs=a,b (folder names), --per=s (seconds shown, default the effect's own
## length, at most 3.2), --scale=x.

const ROOT := "res://assets/vfx/effekseer"


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
		if not (id in ["mika"]):
			(main.characters[id] as Node3D).visible = false
	FightDirector.set_hour(main, 19.6)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.0)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 3, "axis_deg": 0.0, "bare": true})
	d.set_process(true)
	var c0: Vector3 = d.center
	d.F.mika.pos = c0 + Vector3(-2.2, 0, 0)
	d.F.luna.pos = c0 + Vector3(12.0, 0, 0)
	await t._wait(0.6)
	(d.F.luna.c as Node3D).visible = false
	var gy := FightDirector.ground_y(d.F.mika.c, c0)
	var spot := Vector3(c0.x, gy, c0.z)
	d.cut(d.ft + 0.001, "fixed", "mika", {"pos": spot + Vector3(1.5, 2.4, 7.5), "look": spot + Vector3(0, 1.2, 0), "fov": 50.0})
	await t._wait(0.8)
	var files: Array = []
	var only := String(RenderProfile.options.get("packs", "")).split(",", false)
	_walk(ROOT, files)
	files.sort()
	var shown := 0
	for p in files:
		var rel := String(p).trim_prefix(ROOT + "/")
		if not only.is_empty() and not (rel.get_slice("/", 0) in only):
			continue
		var eff = load(p)
		if eff == null:
			print("[gallery] %s LOAD FAILED" % rel)
			continue
		if RenderProfile.options.has("scale"):
			eff.scale = float(RenderProfile.options.scale)
		var em = ClassDB.instantiate("EffekseerEmitter3D")
		main.add_child(em)
		em.global_position = spot + Vector3(0, 0.05, 0)
		em.effect = eff
		var dur := 2.0
		if eff.has_method("calculate_duration"):
			dur = clampf(float(eff.calculate_duration()) / 60.0, 0.6, 3.2)
		if RenderProfile.options.has("per"):
			dur = float(RenderProfile.options.per)
		var a0 := Engine.get_frames_drawn()
		em.play()
		await t._wait(dur)
		print("[gallery] %s dur %.2f from frame %d to frame %d" % [rel.trim_suffix(".efkefc"), dur, a0, Engine.get_frames_drawn()])
		em.stop()
		em.queue_free()
		await t._wait(0.15)
		shown += 1
	t._check(shown > 0, "%d effects shown" % shown)
	d.teardown()


static func _walk(dir: String, out: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		if f.ends_with(".efkefc"):
			out.append(dir.path_join(f))
	for sd in da.get_directories():
		_walk(dir.path_join(sd), out)
