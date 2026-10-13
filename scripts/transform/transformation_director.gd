class_name TransformationDirector
extends Node
## Stages a mage's transformation (data/transformations.json) and keeps track of who is transformed.
##   full    - the first time a form is reached (~14.5 s): sigil, hands, words, rise, flash + form change,
##             the mage's own Aether Orbit forms, finishing pose, title, back to play
##   short   - later uses before a hard fight (~5 s)
##   preview - either version on demand for testing; changes no progress and reverts afterwards
## While it plays: her planner holds, creatures ignore her, the other mage may turn to watch; a dedicated
## camera follows authored beats around her (every position is checked against the world so it never
## sits inside geometry) and hands control back to the gameplay camera at the end. The form VRM is loaded
## on a worker thread during the buildup and swapped at the flash peak, where the music lands its hit.
## A reached form is PERMANENT: it becomes her saved appearance (progress.appearance) and is what she wears from
## then on, through restarts. The cinematic plays once (full) at the unlock; F7 previews replay it without
## changing anything. Separately, an "Orbit Surge" (the short sequence when she already wears her form) is a
## TEMPORARY power effect (+spell power, orbit ring) that simply expires; it never touches her outfit.

signal started(who: String, version: String)
signal finished(who: String, result: Dictionary)

const SAFE_CHECK_S := 1.0

static var data := {}

var main: Node
var playing := ""                  # mage id while a sequence runs
var seq_t := -1.0                  # seconds into the running sequence (-1 while staging / idle)
var surges := {}                   # who -> {until}: temporary Orbit Surge (power + orbit ring), never the outfit
var queue: Array = []              # pending first-time sequences {who, level}
var log: Array = []
var cam: Camera3D
var _prev_cam: Camera3D
var _overlay: CanvasLayer
var _flash: ColorRect
var _title: Label
var _check := 0.0
var _orbits := {}                  # who -> orbit ring node while a surge lasts


static func load_data() -> Dictionary:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json"))
	return data


func setup(m: Node) -> void:
	main = m
	load_data()
	cam = Camera3D.new()
	cam.name = "TransformCamera"
	cam.near = 0.05
	cam.far = 900.0
	main.add_child(cam)
	_overlay = CanvasLayer.new()
	_overlay.layer = 20
	main.add_child(_overlay)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_overlay.add_child(_flash)
	_title = Label.new()
	_title.anchor_left = 0.5
	_title.anchor_right = 0.5
	_title.anchor_top = 0.68
	_title.position = Vector2(-500, 0)
	_title.custom_minimum_size = Vector2(1000, 60)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title.add_theme_constant_override("outline_size", 8)
	_title.modulate.a = 0.0
	_overlay.add_child(_title)
	if main.progression:
		main.progression.form_unlocked.connect(func(who, level, _f): queue.append({"who": who, "level": level}))


func spec(who: String, level := 10) -> Dictionary:
	return data.mages.get(who, {}).get(str(level), {})


func form_avatar(who: String, level := 10) -> String:
	return String(Progression.mages.get(who, {}).get("forms", {}).get(str(level), {}).get("avatar", ""))


## The permanent appearance: the form she has taken ("" = base). Saved in her mind.
static func appearance(who: String) -> String:
	return String(WorldState.mind(who).progress.get("appearance", ""))


## Avatar path for her saved appearance (base avatar when none / when the form's file is missing).
static func avatar_for(who: String) -> String:
	Progression.load_data()
	var mp: Dictionary = Progression.mages.get(who, {})
	var form := appearance(who)
	for lvl in mp.get("forms", {}):
		var f: Dictionary = mp.forms[lvl]
		if String(f.id) == form and ResourceLoader.exists(String(f.avatar)):
			return String(f.avatar)
	return String(mp.get("base_avatar", "res://assets/characters/mika/Mika.vrm"))


func is_transformed(who: String) -> bool:
	return appearance(who) != ""


func has_surge(who: String) -> bool:
	return surges.has(who)


## A surge needs an unlocked form that she already wears and no surge running.
func can_surge(who: String) -> bool:
	return playing == "" and not surges.has(who) and is_transformed(who)


## Backward-compatible name (planner/bridge): "transform" before a fight now means an Orbit Surge.
func can_transform(who: String) -> bool:
	return can_surge(who)


func surge(who: String) -> Dictionary:
	return await play(who, "short", false)


func _process(delta: float) -> void:
	for who in surges.keys():
		if Time.get_ticks_msec() / 1000.0 > float(surges[who].until) and playing == "":
			end_surge(who)
	_check -= delta
	if _check > 0.0 or queue.is_empty() or playing != "":
		return
	_check = SAFE_CHECK_S
	var q: Dictionary = queue[0]
	if _safe_to_start(q.who):
		queue.pop_front()
		play(q.who, "full", false, int(q.level))


## Not mid-cast, not in a conversation, not mid-fight with a creature on her, Sanctuary loaded and idle.
func _safe_to_start(who: String) -> bool:
	var c: WorldCharacter = main.characters.get(who)
	if c == null or not c.visible or c.casting or main.streaming.state != "idle":
		return false
	if main.mage_talk and main.mage_talk.busy():
		return false
	if c.seated or c.current_action not in ["idle", "navigate_to"]:
		return false
	var b = main.mage_brains.get(who)
	# only between activities (or while writing): never mid-cast, seated, fighting or looking around
	if b and b.enabled and (b.threat != null or String(b.current.get("kind", "")) not in ["", "journal"]):
		return false
	return true


# ------------------------------------------------------------------ the sequence
func play(who: String, version := "full", preview := false, level := 10) -> Dictionary:
	if playing != "":
		return {"ok": false, "detail": "another transformation is playing"}
	var c: WorldCharacter = main.characters.get(who)
	var sp := spec(who, level)
	var v: Dictionary = data.versions.get(version, {})
	var form_path := form_avatar(who, level)
	if c == null or sp.is_empty() or v.is_empty() or form_path == "":
		return {"ok": false, "detail": "no level %d form for %s" % [level, who]}
	if not ResourceLoader.exists(form_path):
		return {"ok": false, "detail": "form avatar missing: %s" % form_path}
	playing = who
	await _step_into_open(c)
	var t_start := Time.get_ticks_msec()
	started.emit(who, version)
	var brain = main.mage_brains.get(who)
	if brain:
		brain.hold = true
		brain.interrupt("transform")
	c.stop_action()
	c.set_move_input(Vector3.ZERO, false)
	c.set_meta("transforming", true)
	var base_path := c.avatar_path
	ResourceLoader.load_threaded_request(form_path, "PackedScene", true)
	var col := Color(sp.color[0], sp.color[1], sp.color[2])
	var acc := Color(sp.accent[0], sp.accent[1], sp.accent[2])
	var fx := _build_fx(c, sp, col, acc, who)
	# the other mage notices
	for other in main.characters:
		if other != who and main.characters[other].visible and main.characters[other].global_position.distance_to(c.global_position) < 25.0:
			main.characters[other].look_head_at(c.global_position + Vector3(0, 1.3, 0))
	# camera takeover
	_prev_cam = get_viewport().get_camera_3d()
	var dir_was: bool = main.director.enabled if main.director else false
	if main.director:
		main.director.enabled = false
	cam.make_current()
	var music := "transform_%s_%s" % [who, v.music]
	if AudioDirector.instance:
		AudioDirector.instance.play2d(music, "Music", 12.0, "transform")
	var length := float(v.length)
	var swap_t := float(v.swap)
	var fired := {}
	var start_y := c.global_position.y
	var yaw0 := c.rotation.y
	c.set_physics_process(false)
	var swapped := false
	var ghost: Node3D = null
	var warm: Node3D = null
	var ghost_frames := 0
	var t := 0.0
	while t < length:
		await get_tree().process_frame
		t = (Time.get_ticks_msec() - t_start) / 1000.0
		seq_t = t
		var k := clampf(t / length, 0.0, 1.0)
		# lift off during the buildup, settle after the reveal
		var lift := smoothstep(0.15 * length, swap_t, t) * (1.0 - smoothstep(swap_t + 2.4, length * 0.8, t))
		c.global_position.y = start_y + float(v.float) * lift
		_update_fx(fx, c, t, swap_t, length, col, acc)
		if t >= float(v.gesture_at) and not fired.has("gesture"):
			fired.gesture = true
			c.play_gesture(String(sp.gesture), 0.4, 0.6)
		if t >= float(v.incantation_at) and not fired.has("words"):
			fired.words = true
			if main.voice:
				main.voice.say(String(Progression.mages.get(who, {}).get("voice", who)), String(sp.incantation), {"latin": true, "priority": 2})
		if t >= swap_t - 0.25 and not fired.has("flash_in"):
			fired.flash_in = true
			var tw := create_tween()
			tw.tween_property(_flash, "color", Color(col.lerp(Color.WHITE, 0.6), 0.85), 0.25)
		# prewarm: instantiate the form early (never adding it to the tree, so its spring bones initialise
		# normally later) and draw each of its materials on a tiny sphere in front of the camera for a few
		# frames, so the pipelines compile now instead of on the reveal frame; the instance goes to the swap
		if not fired.has("ghost") and t < swap_t - 0.3 and ResourceLoader.load_threaded_get_status(form_path) == ResourceLoader.THREAD_LOAD_LOADED:
			fired.ghost = true
			ghost = (ResourceLoader.load_threaded_get(form_path) as PackedScene).instantiate()
			warm = _material_spheres(ghost)
			ghost_frames = 0
		if warm:
			ghost_frames += 1
			if ghost_frames > 5:
				warm.queue_free()
				warm = null
		if t >= swap_t and not swapped:
			swapped = true
			if c.avatar_path == form_path:
				ghost = null            # already in her form (Orbit Surge): the flash, no costume change
			if warm:
				warm.queue_free()
				warm = null
			if c.avatar_path == form_path:
				pass
			elif ghost:
				c.swap_avatar(form_path, null, ghost)
			else:
				c.swap_avatar(form_path, ResourceLoader.load_threaded_get(form_path))
			ghost = null
			c.set_physics_process(false)        # (swap re-enables nothing, but be explicit)
			_reveal_burst(c, col, acc)
			var tw2 := create_tween()
			tw2.tween_property(_flash, "color", Color(col.lerp(Color.WHITE, 0.6), 0.0), 0.45).set_ease(Tween.EASE_OUT)
			var spin := create_tween()
			spin.tween_property(c, "rotation:y", yaw0 + TAU, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			c.set_expression(String(sp.expression), 0.7)
		if t >= float(v.pose_at) and not fired.has("pose"):
			fired.pose = true
			c.play_gesture(String(sp.pose), 0.4, 0.8)
		if float(v.title_at) >= 0.0 and t >= float(v.title_at) and not fired.has("title"):
			fired.title = true
			_show_title("%s  ·  %s" % [String(sp.title), String(Progression.mages.get(who, {}).get("orbits", {}).get(str(level / 10), {}).get("name", ""))], col)
		_frame_camera(c, v.shots, t)
	# back to play
	seq_t = -1.0
	c.rotation.y = yaw0
	c.global_position.y = start_y
	c.set_physics_process(true)
	c.set_expression(String(sp.expression), 0.0)
	c.remove_meta("transforming")
	for other in main.characters:
		main.characters[other].look_head_at(null)
	_free_fx(fx)
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	if main.director:
		main.director.enabled = dir_was
	if brain:
		brain.hold = false
	playing = ""
	var res := {"ok": swapped, "who": who, "version": version, "preview": preview, "form": sp.form, "seconds": snappedf(t, 0.01),
		"avatar": c.avatar_path.get_file()}
	if preview:
		await get_tree().create_timer(1.5).timeout
		if c.avatar_path != base_path:
			c.swap_avatar(base_path)          # back to whatever she wore before the preview (base OR her form)
		res["reverted"] = true
	elif version == "full":
		# the unlock: her new form is permanent from now on (saved appearance)
		var m := WorldState.mind(who)
		m.progress["appearance"] = String(sp.form)
		WorldState.record_activity({"id": "transform:" + String(sp.form), "verb": "transform", "label": "Became %s" % sp.title},
			{"knowledge": {"form:" + String(sp.form): 1}}, who)
		res["permanent"] = true
	else:
		# Orbit Surge: temporary power, nothing about her appearance changes
		surges[who] = {"until": Time.get_ticks_msec() / 1000.0 + float(sp.get("surge_s", 60.0))}
		c.set_meta("form_power", float(sp.power))
		_add_orbit(c, who, col, acc)
		res["surge"] = true
	log.append(res)
	finished.emit(who, res)
	return res


## An Orbit Surge has run its course: the extra power and the orbit ring fade. Her outfit stays as it is.
func end_surge(who: String) -> void:
	surges.erase(who)
	var c: WorldCharacter = main.characters.get(who)
	if c == null:
		return
	FX.burst(c.get_parent(), c.global_position + Vector3(0, 1.0, 0), 30, 1.0, FX.pm_motes("self", "burst"), FX.mote_mesh(0.04))
	c.remove_meta("form_power")
	if _orbits.has(who) and is_instance_valid(_orbits[who]):
		_orbits[who].queue_free()
	_orbits.erase(who)
	log.append({"who": who, "surge_ended": true})


## Tiny spheres in front of the transformation camera, one per material of `model` (incl. next passes).
func _material_spheres(model: Node) -> Node3D:
	var root := Node3D.new()
	main.add_child(root)
	var mats := []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for si in m3.mesh.get_surface_count():
			var mat := m3.get_active_material(si)
			while mat and not mats.has(mat):
				mats.append(mat)
				mat = mat.next_pass
	var sph := SphereMesh.new()
	sph.radius = 0.004
	sph.height = 0.008
	sph.radial_segments = 6
	sph.rings = 3
	for i in mats.size():
		var w := MeshInstance3D.new()
		w.mesh = sph
		w.material_override = mats[i]
		root.add_child(w)
		w.global_position = cam.global_position - cam.global_basis.z * 0.3 + cam.global_basis.x * (i % 8 - 4) * 0.006 + cam.global_basis.y * (i / 8) * 0.006
	return root


## A transformation needs room for the sigil and the camera: if she stands among props, she first walks to
## the nearest open spot (navmesh, clear 2.6 m around) within ~9 m.
func _step_into_open(c: WorldCharacter) -> void:
	if main.world == null or not main.world.has_method("has_space_for_magic"):
		return
	if main.world.has_space_for_magic(c.global_position, 2.6):
		return
	var map := c.get_world_3d().navigation_map
	for ring in [3.0, 5.0, 7.0, 9.0]:
		for k in 10:
			var a := TAU * k / 10.0
			var p := NavigationServer3D.map_get_closest_point(map, c.global_position + Vector3(sin(a), 0, cos(a)) * float(ring))
			if main.world.has_space_for_magic(p, 2.6):
				c.navigate_to(p, false)
				var t0 := Time.get_ticks_msec()
				while c.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 8000:
					await get_tree().process_frame
				return


# ------------------------------------------------------------------ camera
var _shot_key := -1
var _shot_yaw := 0.0


## Her VISUAL facing (some clips turn the hips away from the body's root direction): perpendicular to the
## line between her shoulders.
func visual_yaw(c: WorldCharacter) -> float:
	var sk := c.skeleton
	var l := sk.find_bone("LeftUpperArm")
	var r := sk.find_bone("RightUpperArm")
	if l < 0 or r < 0:
		return c.rotation.y
	var lp := (sk.global_transform * sk.get_bone_global_pose(l)).origin
	var rp := (sk.global_transform * sk.get_bone_global_pose(r)).origin
	var fwd := Vector3.UP.cross(Vector3(rp.x - lp.x, 0, rp.z - lp.z)).normalized()
	return atan2(-fwd.x, -fwd.z)


func _frame_camera(c: WorldCharacter, shots: Array, t: float) -> void:
	var shot: Dictionary = shots[shots.size() - 1]
	var idx := shots.size() - 1
	for i in shots.size():
		if t >= float(shots[i].from) and t < float(shots[i].to):
			shot = shots[i]
			idx = i
			break
	if idx != _shot_key:
		_shot_key = idx
		_shot_yaw = visual_yaw(c)       # each shot is framed from where she actually faces as it begins
	var yaw0 := _shot_yaw
	var k := smoothstep(0.0, 1.0, clampf((t - float(shot.from)) / maxf(float(shot.to) - float(shot.from), 0.01), 0.0, 1.0))
	var r := lerpf(float(shot.radius[0]), float(shot.radius[1]), k)
	var h := lerpf(float(shot.height[0]), float(shot.height[1]), k)
	var yaw := yaw0 + deg_to_rad(lerpf(float(shot.yaw[0]), float(shot.yaw[1]), k))
	var base := c.global_position
	var look: Vector3 = _look_point(c, String(shot.look))
	if shot.has("look_from"):
		look = _look_point(c, String(shot.look_from)).lerp(look, k)
	# her facing is -Z of the body; yaw 0 = in front of her
	var want := base + Vector3(-sin(yaw), 0, -cos(yaw)) * r + Vector3(0, h, 0)
	want = _clear(c, look, want)
	want = _clear(c, c.chest.global_position, want)     # her body must stay in view too, not only the look target
	cam.fov = lerpf(cam.fov, float(shot.get("fov", 48.0)), 0.15)
	cam.global_position = cam.global_position.lerp(want, 0.18) if cam.global_position.distance_to(want) < 3.0 else want
	if cam.global_position.distance_to(look) > 0.05:
		cam.look_at(look, Vector3.UP)


func _look_point(c: WorldCharacter, what: String) -> Vector3:
	match what:
		"face":
			var hi := c.skeleton.find_bone("Head")
			return (c.skeleton.global_transform * c.skeleton.get_bone_global_pose(hi)).origin + Vector3(0, 0.08, 0) if hi >= 0 else c.global_position + Vector3(0, 1.5, 0)
		"hands":
			return (c.left_hand.global_position + c.right_hand.global_position) * 0.5
		"feet":
			return c.global_position + Vector3(0, 0.15, 0)
	return c.chest.global_position


## Keep the camera out of walls, columns and terrain: pull it toward the subject until the line is clear.
func _clear(c: WorldCharacter, subject: Vector3, want: Vector3) -> Vector3:
	var space := c.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(subject, want)
	var ex := []
	for ch in main.characters.values():
		ex.append((ch as CollisionObject3D).get_rid())
	q.exclude = ex
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	var p := want
	if not hit.is_empty():
		p = (hit.position as Vector3) + (subject - want).normalized() * 0.25
	if main.world and main.world.has_method("ground_at"):
		p.y = maxf(p.y, float(main.world.ground_at(p.x, p.z)) + 0.15)
	return p


# ------------------------------------------------------------------ visuals (original design)
func _build_fx(c: WorldCharacter, sp: Dictionary, col: Color, acc: Color, who: String) -> Dictionary:
	var host: Node3D = c.get_parent()
	var fx := {}
	fx.sigil = FX.quad("res://shaders/magic/orbit_ring.gdshader", 4.2, {"color": col, "accent": acc, "intensity": 0.0, "glyphs": int(Progression.mages.get(who, {}).get("orbits", {}).get("1", {}).get("glyphs", 7)), "reveal": 0.0, "spin": 0.25})
	fx.inner = FX.quad("res://shaders/magic/sigil.gdshader", 2.6, {"color": acc, "sides": 7 if who == "mika" else 5, "intensity": 0.0, "draw_progress": 0.0, "spin": 0.3, "seed": 21.0})
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.95
	cyl.bottom_radius = 0.75
	cyl.height = 3.4
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 32
	fx.aura = MeshInstance3D.new()
	fx.aura.mesh = cyl
	var am := ShaderMaterial.new()
	am.shader = load("res://shaders/magic/aura_column.gdshader")
	am.set_shader_parameter("color", col)
	am.set_shader_parameter("accent", acc)
	am.set_shader_parameter("rise", 0.0)
	am.set_shader_parameter("intensity", 0.0)
	fx.aura.material_override = am
	fx.aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mote_el := String(sp.get("motes", "arcane"))
	fx.rise = FX.particles(120, 2.2, FX.process("transform_rise_" + who, func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = 1.1
		pm.emission_ring_inner_radius = 0.5
		pm.emission_ring_height = 0.1
		pm.direction = Vector3.UP
		pm.spread = 8.0
		pm.initial_velocity_min = 0.8
		pm.initial_velocity_max = 1.8
		pm.gravity = Vector3.ZERO
		pm.tangential_accel_min = 1.0
		pm.tangential_accel_max = 2.0
		pm.scale_min = 0.5
		pm.scale_max = 1.2
		pm.color_ramp = FX.ramp([Color(col, 0.0), Color(col.lerp(Color.WHITE, 0.4), 1.0), Color(acc, 0.0)], [0.0, 0.3, 1.0])), FX.mote_mesh(0.05))
	fx.hand_l = FX.particles(50, 0.8, FX.pm_motes(mote_el, "gather"), FX.mote_mesh(0.04), true)
	fx.hand_r = FX.particles(50, 0.8, FX.pm_motes(mote_el, "gather"), FX.mote_mesh(0.04), true)
	fx.light = FX.light(col, 0.0, 4.0)
	if bool(sp.get("petals", false)):
		fx.petals = FX.particles(70, 3.0, FX.process("transform_petals", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 1.6
			pm.gravity = Vector3(0, -0.25, 0)
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.5
			pm.angular_velocity_min = -120.0
			pm.angular_velocity_max = 120.0
			pm.tangential_accel_min = 0.4
			pm.tangential_accel_max = 0.9
			pm.scale_min = 0.8
			pm.scale_max = 1.5
			pm.color_ramp = FX.ramp([Color(1, 0.85, 0.93, 0.0), Color(1, 0.9, 0.95, 0.9), Color(1, 0.75, 0.88, 0.0)], [0.0, 0.2, 1.0])), FX.mote_mesh(0.06))
	else:
		fx.petals = FX.particles(60, 2.4, FX.process("transform_embers_" + who, func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 1.4
			pm.gravity = Vector3(0, 0.35, 0)
			pm.initial_velocity_min = 0.05
			pm.initial_velocity_max = 0.3
			pm.tangential_accel_min = -1.2
			pm.tangential_accel_max = -0.6
			pm.scale_min = 0.6
			pm.scale_max = 1.2
			pm.color_ramp = FX.ramp([Color(acc, 0.0), Color(col, 0.95), Color(acc, 0.0)], [0.0, 0.25, 1.0])), FX.mote_mesh(0.045))
	for key in ["sigil", "inner", "aura", "rise", "hand_l", "hand_r", "light", "petals"]:
		host.add_child(fx[key])
	(fx.rise as GPUParticles3D).emitting = true
	(fx.hand_l as GPUParticles3D).emitting = false
	(fx.hand_r as GPUParticles3D).emitting = false
	(fx.petals as GPUParticles3D).emitting = false
	return fx


func _update_fx(fx: Dictionary, c: WorldCharacter, t: float, swap_t: float, length: float, col: Color, acc: Color) -> void:
	var gy: float = main.world.ground_at(c.global_position.x, c.global_position.z) if main.world.has_method("ground_at") else c.global_position.y
	var ground := Vector3(c.global_position.x, gy, c.global_position.z)
	var open := smoothstep(0.0, 1.4, t)
	var end := 1.0 - smoothstep(length - 1.2, length, t)
	fx.sigil.global_position = ground + Vector3(0, 0.04, 0)
	(fx.sigil.material_override as ShaderMaterial).set_shader_parameter("reveal", open)
	(fx.sigil.material_override as ShaderMaterial).set_shader_parameter("intensity", (1.2 + 1.2 * smoothstep(swap_t - 2.0, swap_t, t)) * end)
	fx.inner.global_position = ground + Vector3(0, 0.045, 0)
	(fx.inner.material_override as ShaderMaterial).set_shader_parameter("draw_progress", smoothstep(0.4, 2.0, t))
	(fx.inner.material_override as ShaderMaterial).set_shader_parameter("intensity", 1.4 * open * end)
	fx.aura.global_position = ground + Vector3(0, 1.7, 0)
	var am: ShaderMaterial = fx.aura.material_override
	am.set_shader_parameter("rise", smoothstep(swap_t * 0.45, swap_t, t))
	am.set_shader_parameter("intensity", (0.3 + 0.55 * smoothstep(swap_t - 1.5, swap_t, t)) * (1.0 - smoothstep(swap_t + 0.2, swap_t + 1.6, t)) * end)
	fx.rise.global_position = ground
	(fx.rise as GPUParticles3D).emitting = t < swap_t + 0.2
	var hands_on := t > swap_t * 0.2 and t < swap_t
	fx.hand_l.global_position = c.left_hand.global_position
	fx.hand_r.global_position = c.right_hand.global_position
	(fx.hand_l as GPUParticles3D).emitting = hands_on
	(fx.hand_r as GPUParticles3D).emitting = hands_on
	fx.petals.global_position = c.global_position + Vector3(0, 1.2, 0)
	(fx.petals as GPUParticles3D).emitting = t > swap_t and t < length - 1.5
	fx.light.global_position = c.global_position + Vector3(0, 1.3, 0)
	fx.light.light_energy = (0.35 + 1.0 * smoothstep(swap_t - 1.2, swap_t, t) * (1.0 - smoothstep(swap_t, swap_t + 1.2, t))) * end * float(RenderProfile.get_setting("magic_light_scale"))


func _reveal_burst(c: WorldCharacter, col: Color, acc: Color) -> void:
	var host: Node = c.get_parent()
	ImpactFX.shockwave(host, c.global_position + Vector3(0, 0.08, 0), col, 4.5)
	ImpactFX.shockwave(host, c.global_position + Vector3(0, 1.2, 0), acc, 2.2)
	FX.burst(host, c.global_position + Vector3(0, 1.1, 0), 110, 1.4, FX.process("transform_burst", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.4
		pm.spread = 180.0
		pm.initial_velocity_min = 2.5
		pm.initial_velocity_max = 5.5
		pm.damping_min = 2.0
		pm.damping_max = 3.5
		pm.gravity = Vector3.ZERO
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		pm.color_ramp = FX.ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)], [0.0, 0.4, 1.0])), FX.mote_mesh(0.06))
	ImpactFX.shake(host, 0.05, 0.4)


func _add_orbit(c: WorldCharacter, who: String, col: Color, acc: Color) -> void:
	var ring := FX.quad("res://shaders/magic/orbit_ring.gdshader", 1.9, {"color": col, "accent": acc, "intensity": 0.9, "reveal": 1.0, "spin": 0.4,
		"glyphs": int(Progression.mages.get(who, {}).get("orbits", {}).get("1", {}).get("glyphs", 7))})
	ring.name = "AetherOrbit"
	c.add_child(ring)
	ring.position = Vector3(0, 0.95, 0)
	ring.rotation = Vector3(deg_to_rad(12.0), 0, deg_to_rad(-6.0))
	_orbits[who] = ring


func _free_fx(fx: Dictionary) -> void:
	for k in fx:
		var n = fx[k]
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = false
			get_tree().create_timer(2.5).timeout.connect(n.queue_free)
		elif is_instance_valid(n):
			n.queue_free()


func _show_title(text: String, col: Color) -> void:
	_title.text = text
	_title.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.5))
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 0.6)
	tw.tween_interval(2.0)
	tw.tween_property(_title, "modulate:a", 0.0, 0.8)


func describe() -> Dictionary:
	var tr := {}
	for who in WorldState.minds:
		if appearance(who) != "":
			tr[who] = {"form": appearance(who)}
	var su := {}
	for who in surges:
		su[who] = snappedf(float(surges[who].until) - Time.get_ticks_msec() / 1000.0, 0.1)
	return {"playing": playing, "transformed": tr, "surges": su, "queued": queue.map(func(q): return q.who), "recent": log.slice(maxi(0, log.size() - 4))}
