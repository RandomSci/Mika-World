extends RefCounted
## Combat v3 move book, the eye check: Mika plays every Move Library v2 / v2 ultimates / v3 clip (MoveCatalog, as baked
## for her: MocapBake + the joint fix pass) full body, filmed from the front like the source videos, a still lens, so
## each clip can be laid side by side with its source at the same moments. Luna stands on the camera's side, hidden
## (the duel keeps them facing). Marks "[movelib] <clip> show from frame A to frame B". Option --libs=v2,v2u,v3 / --clip=x.
## --girl=luna plays them on Luna instead (Mika hidden); --framing=mid films closer (knees up, the hands and fingers
## readable at 720p). Any softness pass on her fingers is held off, so the clip's own (mocapped) fingers show.

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
	FightDirector.set_hour(main, 13.0)
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.5)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 3, "axis_deg": 0.0, "bare": true})
	d.set_process(true)
	var c0: Vector3 = d.center
	var who := String(RenderProfile.options.get("girl", "mika"))
	var other := "luna" if who == "mika" else "mika"
	d.F[who].pos = c0
	d.F[other].pos = c0 + Vector3(9.0, 0, 0)        # (she keeps the shown girl facing the lens; hidden, the arena clamp brings her close)
	await t._wait(0.6)
	(d.F[other].c as Node3D).visible = false
	# her everyday helpers would fight the clip (BodyLanguage folds her arms, the foot / hand guards pull her limbs):
	# off, as the fight rig turns them off
	var mc: WorldCharacter = d.F[who].c
	for n in mc.skeleton.find_children("*", "SkeletonModifier3D", false, false):
		if n is SoftArms:
			(n as SoftArms).finger_weight = 0.0
	for n in MeleeFighter.RAW_CLIP_HOLD:
		var m := mc.skeleton.get_node_or_null(n) as SkeletonModifier3D
		if m:
			m.active = false
	if mc.head_look:
		mc.head_look.influence = 0.0
	var gy := FightDirector.ground_y(d.F[who].c, c0)
	if String(RenderProfile.options.get("framing", "")) == "mid":
		d.cut(d.ft + 0.001, "fixed", who, {"pos": Vector3(c0.x + 2.3, gy + 1.15, c0.z), "look": Vector3(c0.x, gy + 1.0, c0.z), "fov": 40.0})
	else:
		d.cut(d.ft + 0.001, "fixed", who, {"pos": Vector3(c0.x + 3.7, gy + 0.95, c0.z), "look": Vector3(c0.x, gy + 0.85, c0.z), "fov": 38.0})
	await t._wait(0.8)
	var libs := String(RenderProfile.options.get("libs", "v2,v2u,v3")).split(",")
	var only := String(RenderProfile.options.get("clip", ""))
	var some := String(RenderProfile.options.get("clips", "")).split(",", false)
	var shown := 0
	for n in MoveCatalog.CLIPS:
		if only != "" and n != only:
			continue
		if not some.is_empty() and not (String(n) in some):
			continue
		if only == "" and some.is_empty() and not (String(MoveCatalog.CLIPS[n].lib) in libs):
			continue
		var clip := "ml_" + String(n)
		var c: WorldCharacter = d.F[who].c
		if not c.has_clip(clip):
			print("[movelib] %s MISSING" % n)
			continue
		d.F[who].pos = c0
		var a0 := Engine.get_frames_drawn()
		var dur: float = d.anim(who, clip, 0.0, -1.0, 1.0, 0.05)
		await t._wait(dur)
		print("[movelib] %s show from frame %d to frame %d" % [n, a0, Engine.get_frames_drawn()])
		var bake_of := String(RenderProfile.options.get("bake-of", ""))
		if bake_of != "" and bake_of != who:
			# QA (the shared-bake check): the same clip again, as baked for the OTHER girl's skeleton
			var oc: WorldCharacter = d.F[bake_of].c
			var foreign := MocapBake.bake(oc.skeleton, WorldCharacter.MOCAP_DIR + String(n) + ".json")
			c._retarget_paths(foreign, String(c.avatar.get_path_to(c.skeleton)), true)
			var mine: Animation = c.body_player.get_animation("mx/" + clip)
			c.body_player.get_animation_library("mx").remove_animation(clip)
			c.body_player.get_animation_library("mx").add_animation(clip, foreign)
			d.anim(who, "combat_idle", 0.0, -1.0, 1.0, 0.1, true)
			await t._wait(0.35)
			var a1 := Engine.get_frames_drawn()
			d.anim(who, clip, 0.0, -1.0, 1.0, 0.05)
			await t._wait(dur)
			print("[movelib] %s as baked for %s from frame %d to frame %d" % [n, bake_of, a1, Engine.get_frames_drawn()])
			c.body_player.get_animation_library("mx").remove_animation(clip)
			c.body_player.get_animation_library("mx").add_animation(clip, mine)
		d.anim(who, "combat_idle", 0.0, -1.0, 1.0, 0.1, true)
		await t._wait(0.35)
		shown += 1
	t._check(shown > 0, "%d clips shown" % shown)
	d.teardown()
