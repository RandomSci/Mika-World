extends Node3D
## REACTION LAB (V3 continuation): Mika and Luna under the Whispering Woods' daylight on a mossy floor with a 14
## degree slope and a low wall (cover), without loading the world - for honest iteration on impacts, falls and
## getting up. Every run measures each body every physics frame (snaps, sinking into the ground, floating while
## down, the time from impact to steady) and writes a JSON report plus PNG stills; record video with
## --write-movie.
##   godot --path . res://scenes/tools/reaction_lab.tscn -- --out=res://screenshots/reaction_lab --lab=suite|front|behind|blown|stagger|flinch|slope|together|cover

var characters := {}
var mage_brains := {}
var voice = null
var impacts: ImpactDirector
var cam: Camera3D
var out := "res://screenshots/reaction_lab"
var report := {"cases": []}
var _mon := {}               # who -> metrics accumulator
var _prev := {}
var trace: PackedStringArray = []
var _cam_follow: Array = []
var nav_region: NavigationRegion3D
var caption: Label
var status_lbl: Label
const TITLES := {"flinch": "Light blow - a flinch", "stagger": "Medium blow - stagger, catch balance", "front": "Heavy blast from the front - fall, recover", "behind": "Heavy blast from behind - pitched onto her knees", "blown": "Very heavy blast - thrown off her feet", "slope": "Heavy blast on a 14 degree slope", "cover": "Same blast, but a wall stands between", "luna_front": "Luna - heavy blast from the front (agile recovery)", "luna_behind": "Luna - heavy blast from behind", "together": "Both: Luna goes down, Mika runs to help her"}
var _cam_off := Vector3(5.2, 1.6, 0.0)


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := PanoramaSkyMaterial.new()
	psm.panorama = load("res://assets/polyhaven/hdris/nature_reserve_forest/nature_reserve_forest_2k.hdr")
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.9
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 140, 0)
	sun.light_energy = 2.8
	sun.light_color = Color(1, 0.92, 0.78)
	sun.shadow_enabled = true
	add_child(sun)
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80), Vector3.ZERO, "mossy_stone_wall")
	# a 14 degree slope rising towards -x at x in [-22, -10]
	_box(Vector3(-16, 0.9, 0), Vector3(14, 1.0, 14), Vector3(0, 0, -14), "mossy_stone_wall")
	# a low wall (cover) at z = 12
	_box(Vector3(0, 0.75, 12), Vector3(4, 1.5, 0.4), Vector3.ZERO, "mossy_stone_wall")
	# a navmesh over the floor and slope (helpers run to a fallen friend; the evasive one backs away)
	nav_region = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.35
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_max_slope = 30.0
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	for b in get_children():
		if b is StaticBody3D:
			b.reparent(nav_region)
	nav_region.bake_navigation_mesh(false)
	var layer := CanvasLayer.new()
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(28, 22)
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	caption.add_theme_constant_override("outline_size", 7)
	layer.add_child(caption)
	status_lbl = Label.new()
	status_lbl.position = Vector2(28, 62)
	status_lbl.add_theme_font_size_override("font_size", 19)
	status_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	status_lbl.add_theme_constant_override("outline_size", 6)
	layer.add_child(status_lbl)
	cam = Camera3D.new()
	cam.fov = 34.0
	add_child(cam)
	cam.current = true
	out = String(RenderProfile.options.get("out", out))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	Progression.load_data()
	for who in ["mika", "luna"]:
		var c := WorldCharacter.new()
		c.name = who.capitalize()
		c.character_id = who
		c.display_name = who.capitalize()
		c.avatar_path = TransformationDirector.avatar_for(who)
		add_child(c)
		characters[who] = c
	impacts = ImpactDirector.new()
	impacts.name = "Impacts"
	add_child(impacts)
	impacts.setup(self)
	_run.call_deferred()


func _box(at: Vector3, size: Vector3, rot_deg: Vector3, mat: String) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = RealKit.stone_mat(mat, false)
	body.add_child(mi)
	body.position = at
	body.rotation_degrees = rot_deg
	add_child(body)


func ground_at(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 30, z), Vector3(x, -10, z), 1)
	for c in characters.values():
		q.exclude = q.exclude + [c.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else 0.0


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


# ------------------------------------------------------------------ measuring every body every frame
const PROBE := ["Hips", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "LeftLowerLeg", "RightLowerLeg", "Spine"]


func _process(delta: float) -> void:
	for who in _mon:
		var c: WorldCharacter = characters[who]
		var m: Dictionary = _mon[who]
		var sk := c.skeleton
		var pts := {}
		for b in PROBE:
			var bi := sk.find_bone(b)
			if bi >= 0:
				pts[b] = sk.global_transform * sk.get_bone_global_pose(bi).origin
		var g := ground_at(c.global_position.x, c.global_position.z)
		var hips: Vector3 = pts.Hips
		# sinking: the lowest body point below the ground right under it
		for b in pts:
			var p: Vector3 = pts[b]
			var gy := ground_at(p.x, p.z)
			var pen := gy - p.y
			if b in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
				pen -= 0.04            # hands and feet rest ON the ground (their bone sits ~4 cm inside the skin)
			if pen > float(m.max_sink):
				m.max_sink = pen
				m.max_sink_where = "%s in %s" % [b, c.reaction.phase]
		# snaps: hips jumping in one frame (world), and bone rotation speed
		var now := Time.get_ticks_msec() / 1000.0
		var hist: Array = m.get("hist", [])
		hist.append([now, hips])
		while hist.size() > 2 and now - float(hist[1][0]) >= 0.1:
			hist.pop_front()
		m["hist"] = hist
		if _prev.has(who) and now - float(hist[0][0]) >= 0.1:
			var pv: Dictionary = _prev[who]
			# hip SPEED over the last 0.1 s window (a single frame's delta lies after a shader-compile hitch)
			var jump := hips.distance_to(hist[0][1]) / (now - float(hist[0][0]))
			if jump > float(m.max_hip_step):
				m.max_hip_step = jump
				m.max_hip_step_where = "%s/%s at %.2f s (mix %.2f)" % [c.reaction.phase, c.reaction._state, Time.get_ticks_msec() / 1000.0 - float(m.t0), float(c.anim_tree.get("parameters/react_mix/blend_amount"))]
			var body_jump := c.global_position.distance_to(pv.body)
			m.max_body_step = maxf(float(m.max_body_step), body_jump)
		_prev[who] = {"hips": hips, "body": c.global_position}
		if RenderProfile.options.has("trace"):
			var hl := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
			trace.append("%.3f %s %s state=%s mix=%.2f hips_local=(%.2f,%.2f,%.2f) body=(%.2f,%.2f,%.2f) d=%.3f" % [Time.get_ticks_msec() / 1000.0 - float(m.t0), who, c.reaction.phase, c.reaction._state,
				float(c.anim_tree.get("parameters/react_mix/blend_amount")), hl.x, hl.y, hl.z, c.global_position.x, c.global_position.y, c.global_position.z, delta])
		# floating while down: hips well above the ground when lying
		if c.reaction.phase == "down" and c.reaction._state == "rx_down_back":
			m.down_hip_max = maxf(float(m.down_hip_max), hips.y - g)
			m.down_hip_min = minf(float(m.down_hip_min), hips.y - g)
		if c.reaction.phase != "" and not m.phases.has(c.reaction.phase):
			m.phases[c.reaction.phase] = snappedf(Time.get_ticks_msec() / 1000.0 - float(m.t0), 0.01)
	if status_lbl:
		var lines := []
		for who in characters:
			var c: WorldCharacter = characters[who]
			if c.visible:
				var ph := c.reaction.phase if c.reaction.phase != "" else ("helping" if impacts._helping.has(who) else ("after: " + String(c.reaction.body.get("after", "")) if impacts._busy.has(who) else "normal"))
				lines.append("%s: %s" % [c.display_name, ph])
		status_lbl.text = "\n".join(lines)
	if not _cam_follow.is_empty():
		var mid := Vector3.ZERO
		for c in _cam_follow:
			mid += (c as Node3D).global_position
		mid /= _cam_follow.size()
		var want := mid + _cam_off
		cam.global_position = cam.global_position.lerp(want, 0.08)
		cam.look_at(mid + Vector3(0, 0.7, 0))


func _monitor(who: String) -> void:
	_mon[who] = {"t0": Time.get_ticks_msec() / 1000.0, "max_sink": -1.0, "max_sink_where": "", "max_hip_step": 0.0, "max_hip_step_where": "",
		"max_body_step": 0.0, "down_hip_max": -1.0, "down_hip_min": 9.0, "phases": {}}
	_prev.erase(who)


# ------------------------------------------------------------------ cases
func _place(who: String, at: Vector3, yaw_deg: float) -> WorldCharacter:
	var c: WorldCharacter = characters[who]
	c.visible = true
	c.set_physics_process(true)
	c.reaction.reset()
	c.global_position = at + Vector3(0, 0.05, 0)
	c.rotation.y = deg_to_rad(yaw_deg)
	c.velocity = Vector3.ZERO
	return c


func _hide(who: String) -> void:
	var c: WorldCharacter = characters[who]
	c.reaction.reset()
	c.global_position = Vector3(30, 0.1, 30 + (5 if who == "luna" else 0))
	c.visible = false


func _case(name: String, actors: Array, blast_at: Vector3, strength: float, radius: float, shots: Array) -> Dictionary:
	await _wait(0.6)
	for who in actors:
		_monitor(who)
	_cam_follow = actors.map(func(w): return characters[w])
	caption.text = String(TITLES.get(name, name))
	var t0 := Time.get_ticks_msec() / 1000.0
	ImpactFX.shockwave(self, blast_at + Vector3(0, -0.5, 0), Color(1.0, 0.6, 0.3), radius * 0.6)
	var res := impacts.blast(blast_at, strength, radius, {"source": "lab", "kind": name})
	var k := 0
	var until := t0 + 40.0
	while Time.get_ticks_msec() / 1000.0 < until:
		var tt := Time.get_ticks_msec() / 1000.0 - t0
		if tt >= k * 0.5 and not RenderProfile.options.has("noshots"):
			await _grab("%s_%02d" % [name, k])
			k += 1
		var busy := false
		for who in characters:
			if characters[who].visible and (characters[who].reaction.active or impacts._busy.has(who) or impacts._helping.has(who)):
				busy = true
		if not busy and tt > 1.0:
			break
		await get_tree().physics_frame
	var rec := {"case": name, "blast": [blast_at.x, blast_at.y, blast_at.z], "strength": strength, "radius": radius, "results": res,
		"seconds_to_resume": snappedf(Time.get_ticks_msec() / 1000.0 - t0, 0.01), "bodies": {}}
	for who in actors:
		var m: Dictionary = _mon[who]
		var c: WorldCharacter = characters[who]
		var verdict := []
		if float(m.max_sink) > 0.06:
			verdict.append("sinks %.2f m (%s)" % [m.max_sink, m.max_sink_where])
		if float(m.max_hip_step) > 8.0:
			verdict.append("hip snap %.1f m/s (%s)" % [m.max_hip_step, m.max_hip_step_where])
		if float(m.down_hip_max) > 0.45:
			verdict.append("floats while down (hips %.2f m up)" % m.down_hip_max)
		rec.bodies[who] = {"max_sink_m": snappedf(m.max_sink, 0.001), "max_sink_where": m.max_sink_where, "max_hip_speed_mps": snappedf(m.max_hip_step, 0.01),
			"max_hip_step_where": m.max_hip_step_where, "max_body_step_m": snappedf(m.max_body_step, 0.001),
			"down_hip_height_m": [snappedf(m.down_hip_min, 0.01), snappedf(m.down_hip_max, 0.01)], "phases": m.phases,
			"reaction": c.reaction.history.back() if not c.reaction.history.is_empty() else {}, "ok": verdict.is_empty(), "problems": verdict}
	_mon.clear()
	rec["aftermath"] = impacts.aftermath_log.duplicate()
	rec["said"] = impacts.said.duplicate()
	impacts.aftermath_log.clear()
	impacts.said.clear()
	report.cases.append(rec)
	print("[reaction_lab] ", name, " ", JSON.stringify(rec.bodies))
	return rec


func _run() -> void:
	if not WorldState.save_path.contains("test_"):
		push_error("[reaction_lab] run with --save-path=user://test_regress_lab.json (never the real save)")
		get_tree().quit(1)
		return
	await _wait(2.0)
	var mode := String(RenderProfile.options.get("lab", "suite"))
	var cases := ["flinch", "stagger", "front", "behind", "blown", "slope", "cover", "luna_front", "luna_behind", "together"] if mode == "suite" else [mode]
	for cs in cases:
		for who in characters:
			_hide(who)
		match cs:
			"flinch":
				_place("mika", Vector3(0, 0, 0), 0)
				_cam_off = Vector3(4.5, 1.6, 0.5)
				await _case(cs, ["mika"], Vector3(0, 0.6, -3.6), 0.8, 6.0, [0.15, 0.4])
			"stagger":
				_place("mika", Vector3(0, 0, 0), 0)
				_cam_off = Vector3(4.8, 1.5, 0.8)
				await _case(cs, ["mika"], Vector3(0, 0.6, -2.4), 0.9, 6.0, [0.2, 0.5, 0.9])
			"front":
				_place("mika", Vector3(0, 0, 0), 0)
				_cam_off = Vector3(3.6, 1.3, 1.6)
				await _case(cs, ["mika"], Vector3(0, 0.6, -1.6), 1.0, 7.0, [0.3, 0.8, 1.5, 2.6, 3.4, 4.2, 5.0])
			"behind":
				_place("mika", Vector3(0, 0, 0), 180)
				_cam_off = Vector3(3.6, 1.3, -1.2)
				await _case(cs, ["mika"], Vector3(0, 0.6, -1.6), 1.0, 7.0, [0.3, 0.8, 1.5, 2.6, 3.4, 4.2])
			"blown":
				_place("mika", Vector3(0, 0, 0), 0)
				_cam_off = Vector3(6.5, 1.8, 2.0)
				await _case(cs, ["mika"], Vector3(0, 0.6, -0.8), 1.35, 7.0, [0.2, 0.5, 1.0, 2.0, 3.5, 4.5])
			"slope":
				_place("mika", Vector3(-15, ground_at(-15, 0), 0), -90)
				_cam_off = Vector3(0.5, 1.8, 5.5)
				await _case(cs, ["mika"], Vector3(-16.6, ground_at(-16.6, 0) + 0.6, 0), 1.0, 7.0, [0.6, 1.6, 2.6, 3.6])
			"cover":
				_place("mika", Vector3(0, 0, 12.7), 0)
				_cam_off = Vector3(5.0, 1.8, 1.0)
				await _case(cs, ["mika"], Vector3(0, 0.6, 10.2), 1.0, 7.0, [0.3, 1.0])
			"luna_front":
				_place("luna", Vector3(0, 0, 0), 0)
				_cam_off = Vector3(3.6, 1.3, 1.6)
				await _case(cs, ["luna"], Vector3(0, 0.6, -1.6), 1.0, 7.0, [0.3, 0.8, 1.5, 2.4, 3.2])
			"luna_behind":
				_place("luna", Vector3(0, 0, 0), 180)
				_cam_off = Vector3(3.6, 1.3, -1.2)
				await _case(cs, ["luna"], Vector3(0, 0.6, -1.6), 0.95, 7.0, [0.3, 1.0, 2.0, 3.0])
			"together":
				# the blast lands next to Luna: she goes down, Mika (further off) staggers, then runs to help her
				_place("luna", Vector3(0, 0, 0), 0)
				_place("mika", Vector3(4.2, 0, 1.5), -60)
				_cam_off = Vector3(3.0, 2.2, 6.5)
				await _case(cs, ["mika", "luna"], Vector3(0.4, 0.6, -1.4), 1.05, 7.5, [0.4, 1.4, 2.4, 3.4, 4.4, 5.4, 6.6])
	if not trace.is_empty():
		var tf := FileAccess.open(out + "/trace.txt", FileAccess.WRITE)
		tf.store_string("\n".join(trace))
		tf.close()
	var f := FileAccess.open(out + "/reaction_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[reaction_lab] done ", report.cases.size(), " cases")
	get_tree().quit()
