class_name Phoenix
extends Node3D
## ORIEL, the Ember Keeper (V3 Part X): one character, two bodies. This node IS her - identity, memory
## (WorldState.npc_state.phoenix, shared with DialogueService), state, position - whichever body she wears:
##   true form   - PhoenixTrueRig (a child): she flies in from the summit, circles, lands on the Woods'
##                 viewpoint, lights its cold fire bowls, regards whoever comes, preens, calls, and defends
##                 the ground with her fire;
##   human form  - PhoenixHuman (a WorldCharacter the area owns; this node follows it): she talks with Mika
##                 (DialogueService beats, her Kore voice), walks, sits at the edge to watch the valley, casts.
## The transformation (both directions) is continuous: embers wake in her feathers, the feathers lift away
## and burn from the wingtips in toward her heart, a core of fire stands where she stood, the other body is
## already posed inside it (never a T-pose) at the same place and facing, collision switches at the swap,
## the fire settles into her aura. A long cinematic variation (first meeting, camera beats) and a short
## gameplay one. Audio is composed to land its hit on the swap (tools/audio/synth_phoenix.py).

signal event(kind: String, detail: Dictionary)

static var data := {}

var main: Node
var area: Node3D
var form := "phoenix"               # "phoenix" | "human"
var phase := "away"                 # away, arrive, circle, land, perched, to_human, human, to_phoenix, takeoff, leave, gone
var state := "arriving"             # what the dialogue/brain see: arriving | idle | talking | leaving | gone
var talk_target: Node3D = null
var witnessed: Array = []
var true_rig: PhoenixTrueRig
var human: PhoenixHuman
var body: StaticBody3D
var body_shape: CollisionShape3D
var home := {}
var log: Array = []
var rng := RandomNumberGenerator.new()
var braziers: Array = []
var transformations: Array = []     # {to, variation, seconds, hit_s, start_pos, end_pos, drift_m}
var busy := false
var leaving := false
var _path: Array = []
var _path_i := 0
var _vel := Vector3.ZERO
var _speed := 11.0
var _gesture_t := 6.0
var _flap_t := 0.0
var _perch := Vector3.ZERO
var _perch_yaw := 0.0
var _core: MeshInstance3D
var _core_light: OmniLight3D
var _flash_layer: CanvasLayer
var _flash: ColorRect
var _vignette: ColorRect
var _space_saved := {}
var _space_k := 0.0
var _veil: GPUParticles3D
var _embers: GPUParticles3D
var _hover_y := 0.0
var _game_t := 0.0
var _sat_since := -1.0
var _display_left := 0.0
var last_nova := {}                 # tests: how high she rose for her last nova
var bystander_log: Array = []       # tests: how Mika and Luna reacted to her ({t, who, kind, how, dist})
var _react_cool := {}


static func load_data() -> Dictionary:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string("res://data/phoenix.json"))
	return data


func setup(m: Node, p_area: Node3D) -> void:
	main = m
	area = p_area
	load_data()
	home = data.home
	name = "Phoenix"
	rng.seed = hash("oriel") + int(Time.get_unix_time_from_system()) % 10000
	PhoenixFlare.main_ref = m
	PhoenixNova.main_ref = m
	true_rig = PhoenixTrueRig.new()
	true_rig.name = "TrueForm"
	add_child(true_rig)
	true_rig.build()
	if true_rig.clearance:
		true_rig.clearance.area = p_area
	body = StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 2
	body.collision_mask = 0
	body_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.5, 2.3, 2.4)
	body_shape.shape = bs
	body_shape.position = Vector3(0, 1.3, 0.2)
	body.add_child(body_shape)
	add_child(body)
	human = PhoenixHuman.new()
	human.name = "PhoenixHuman"
	area.add_child(human)
	human.visible = false
	human.process_mode = Node.PROCESS_MODE_DISABLED
	human.collision_layer = 0
	_build_fx()
	var p: Array = home.perch
	_perch = Vector3(p[0], area.ground_at(p[0], p[1]) + 0.12, p[1])
	_perch_yaw = deg_to_rad(float(home.get("perch_yaw_deg", 270.0)))
	MagicEvents.magic_event.connect(_on_magic)
	if main.voice:
		main.voice.register_speaker("phoenix", self)
	for br in area.find_children("viewpoint_bowl*", "", true, false):
		if br is Brazier:
			braziers.append(br)


func _build_fx() -> void:
	_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 20
	_core.mesh = sm
	var cm := ShaderMaterial.new()
	cm.shader = load("res://shaders/phoenix/fire_core.gdshader")
	cm.set_shader_parameter("noise_tex", FX.noise())
	cm.set_shader_parameter("power", 0.0)
	_core.material_override = cm
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.visible = false
	_core.position = Vector3(0, 1.5, 0.2)
	_core.scale = Vector3.ONE * 0.2
	add_child(_core)
	_core_light = FX.light(Color(1.0, 0.62, 0.22), 0.0, 14.0)
	_core_light.position = Vector3(0, 1.6, 0.2)
	add_child(_core_light)
	var veil_mesh := QuadMesh.new()
	veil_mesh.size = Vector2(0.1, 0.18)
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/phoenix/feather_card.gdshader")
	vm.set_shader_parameter("atlas", load(PhoenixTrueRig.ATLAS))
	veil_mesh.material = vm
	_veil = FX.particles(110, 2.2, FX.process("phoenix_veil", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = 2.2
		pm.emission_ring_inner_radius = 0.6
		pm.emission_ring_height = 0.4
		pm.direction = Vector3.UP
		pm.spread = 30.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.4
		pm.orbit_velocity_min = 0.35
		pm.orbit_velocity_max = 0.6
		pm.radial_velocity_min = -0.6
		pm.radial_velocity_max = -0.2
		pm.gravity = Vector3(0, 0.9, 0)
		pm.angular_velocity_min = -160.0
		pm.angular_velocity_max = 160.0
		pm.scale_min = 0.6
		pm.scale_max = 1.1
		pm.color_ramp = FX.ramp([Color(0.8, 0.12, 0.05, 0), Color(1, 0.5, 0.12, 1), Color(1, 0.85, 0.45, 0.9), Color(1, 0.98, 0.85, 0)], [0.0, 0.2, 0.7, 1.0])), veil_mesh, true)
	_veil.position = Vector3(0, 0.6, 0.2)
	_veil.emitting = false
	_veil.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 14, 16))
	add_child(_veil)
	_embers = FX.particles(90, 2.2, FX.process("phoenix_transform_embers", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(1.4, 1.0, 1.6)
		pm.direction = Vector3.UP
		pm.spread = 35.0
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 1.6
		pm.gravity = Vector3(0, 1.2, 0)
		pm.damping_min = 0.3
		pm.damping_max = 0.8
		pm.scale_min = 0.4
		pm.scale_max = 1.0
		pm.color_ramp = FX.ramp([Color(1, 0.8, 0.4, 0), Color(1, 0.6, 0.18, 1), Color(0.95, 0.3, 0.05, 0.7), Color(0.3, 0.05, 0, 0)], [0.0, 0.15, 0.6, 1.0])), FX.mote_mesh(0.05))
	_embers.position = Vector3(0, 1.3, 0.2)
	_embers.emitting = false
	_embers.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 12, 12))
	add_child(_embers)
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 19
	add_child(_flash_layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1.0, 0.92, 0.75, 0.0)
	_flash_layer.add_child(_flash)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = """shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	vec2 p = UV - 0.5;
	p.x *= 1.6;
	float v = smoothstep(0.25, 0.85, length(p));
	COLOR = vec4(0.06, 0.012, 0.0, v * amount);
}"""
	var vgm := ShaderMaterial.new()
	vgm.shader = vs
	_vignette.material = vgm
	_flash_layer.add_child(_vignette)
	_flash_layer.move_child(_vignette, 0)


# ------------------------------------------------------------------ identity shared by both bodies
func display_name() -> String:
	return String(data.name)


## VoiceService drives her mouth through this (both forms); other systems set emotion.
func set_expression(ex: String, weight: float) -> void:
	if form == "human":
		if is_instance_valid(human):
			human.set_expression(ex, weight)
	elif ex == "aa":
		true_rig.set_mouth(weight)
	elif ex == "happy" and weight > 0.5:
		true_rig.play("look")


func set_talking(_on: bool) -> void:
	pass


func head_point() -> Vector3:
	return human.head_point() if form == "human" else true_rig.head_point()


func aim_point() -> Vector3:
	return human.chest_point() if form == "human" else true_rig.aim_point()


func memory() -> Dictionary:
	return main.dialogue.state_of("phoenix")


func describe(from: Vector3) -> Dictionary:
	return {"id": "phoenix", "name": data.name, "role": data.role, "state": state, "form": form, "phase": phase,
		"distance": snappedf(from.distance_to(global_position), 0.1), "appearance": data.appearance,
		"witnessed": witnessed.slice(maxi(0, witnessed.size() - 4)), "met": memory().met, "relationship": snappedf(memory().relationship, 0.01)}


func _on_magic(pos: Vector3, element: String, power: float, effect: String, object_id: String) -> void:
	if phase in ["away", "gone"] or effect == "none" or object_id.begins_with("phoenix"):
		return
	if global_position.distance_to(pos) < 40.0:
		witnessed.append({"effect": effect, "element": element, "object": object_id, "power": snappedf(power, 0.01), "t": snappedf(_game_t, 0.1)})


func _note(kind: String, detail := {}) -> void:
	var e := {"t": snappedf(_game_t, 0.1), "event": kind}
	e.merge(detail)
	log.append(e)
	if log.size() > 200:
		log.pop_front()
	event.emit(kind, detail)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func mika() -> WorldCharacter:
	return main.characters.get("mika")


static func head_of(c: Node3D) -> Vector3:
	if c == null or not is_instance_valid(c):
		return Vector3.ZERO
	if c.has_method("head_point"):
		return c.head_point()
	return c.global_position + Vector3(0, 1.45, 0)


var shot_cb: Callable = Callable()   # tests: stills at the transformation's beats


func _still(tag: String) -> void:
	if shot_cb.is_valid():
		shot_cb.call(tag)


func facing() -> Vector3:
	return Basis(Vector3.UP, rotation.y) * Vector3(0, 0, 1)


func face_point(p: Vector3) -> void:
	var d := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
	if d.length() > 0.05:
		rotation.y = atan2(d.x, d.z)


# ------------------------------------------------------------------ presentation helpers (captures, tests)
## Put her on the perch at once (no flight): for stills and benchmarks.
func place_perched() -> void:
	phase = "perched"
	state = "arriving"
	form = "phoenix"
	visible = true
	global_position = _perch
	rotation.y = _perch_yaw
	true_rig.visible = true
	true_rig.bank = 0.0
	true_rig.pitch = 0.0
	true_rig.play("idle")
	body.collision_layer = 2


## Swap bodies instantly (no effects): for stills of each form. The real transformation is transform_to_*().
func show_form(f: String) -> void:
	var ground := Vector3(global_position.x, area.ground_at(global_position.x, global_position.z), global_position.z)
	if f == "human":
		human.global_position = ground
		human.rotation.y = rotation.y + PI
		human.process_mode = Node.PROCESS_MODE_INHERIT
		human.visible = true
		human.collision_layer = 1
		human.set_dissolve(0.0, ground)
		human.set_heat(0.0)
		true_rig.visible = false
		body.collision_layer = 0
		form = "human"
		phase = "human"
		state = "idle"
	else:
		human.visible = false
		human.collision_layer = 0
		human.process_mode = Node.PROCESS_MODE_DISABLED
		true_rig.visible = true
		true_rig.set_dissolve(0.0, ground)
		body.collision_layer = 2
		form = "phoenix"
		phase = "perched"


# ------------------------------------------------------------------ her voice
func say(text: String, mood := "", priority := 0) -> Dictionary:
	# her set lines are said in these words once; at later meetings she says the same in new words (LineMemory)
	text = await main.dialogue.fresh_line("phoenix", "phoenix", text)
	if text == "":
		return {"ok": false, "skipped": "repeat"}
	var opts := {"form": form, "mood": mood, "priority": priority}
	if form == "phoenix":
		opts["bus"] = "VoicePhoenix"
		true_rig.look_at_point(head_of(mika()) if mika() else global_position + facing() * 5.0, 1.0)
	return await main.voice.say("phoenix", text, opts)


# ------------------------------------------------------------------ arrival, circling, landing
func arrive() -> void:
	phase = "arrive"
	state = "arriving"
	form = "phoenix"
	var pts: Array = home.approach
	_path.clear()
	for p in pts:
		_path.append(Vector3(p[0], p[1], p[2]))
	var c := _perch
	var r := float(home.get("circle_radius", 15.0))
	var h := float(home.get("circle_height", 12.0))
	for k in 18:
		var a := -PI * 0.5 + 2.0 * PI * k / 18.0
		_path.append(Vector3(c.x + cos(a) * r, c.y + h - 3.0 * (k / 18.0), c.z + sin(a) * r))
	# final approach from the east, into her facing, to a point above the perch
	_path.append(c + Vector3(9.0, 18.0, 0.0))     # still above the crowns, over the clearing (radius ~15 m)
	_path.append(c + Vector3(4.0, 7.0, 0.0))
	_path.append(c + Vector3(2.0, 4.4, 0.0))
	_path_i = 0
	global_position = _path[0]
	_vel = (_path[1] - _path[0]).normalized() * _speed
	rotation.y = atan2(_vel.x, _vel.z)
	true_rig.play("fly")
	true_rig.set_embers(1.0)
	visible = true
	_note("arrive", {"from": [snappedf(_path[0].x, 0.1), snappedf(_path[0].y, 0.1), snappedf(_path[0].z, 0.1)]})
	if main.audio:
		main.audio.play_big("phoenix_cry", global_position, 0.0, "phoenix cry")


func _fly_step(delta: float) -> bool:
	if _path_i >= _path.size():
		return true
	var target: Vector3 = _path[_path_i]
	var to := target - global_position
	if to.length() < 3.2:
		_path_i += 1
		if _path_i == 4 and phase == "arrive":
			phase = "circle"
			_note("circle")
			if main.audio:
				main.audio.play_big("phoenix_cry", global_position, 0.0, "phoenix cry")
		return _path_i >= _path.size()
	var desired := to.normalized() * _speed
	_vel = _vel.lerp(desired, 1.0 - exp(-1.4 * delta))
	global_position += _vel * delta
	var want := atan2(_vel.x, _vel.z)
	var diff := angle_difference(rotation.y, want)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-2.2 * delta))
	true_rig.bank = clampf(-diff * 1.1, -0.65, 0.65)
	true_rig.pitch = clampf(-_vel.y / maxf(_vel.length(), 1.0) * 0.9, -0.55, 0.45)
	var climbing := _vel.y > -0.6
	var want_state := "fly" if (climbing or _vel.length() < _speed * 0.7) else "glide"
	if absf(diff) > 0.35:
		want_state = "bank_left" if diff > 0 else "bank_right"
	if true_rig.state != want_state:
		true_rig.play(want_state)
	_flap_t += delta
	if true_rig.state == "fly" and _flap_t >= 0.9:
		_flap_t = 0.0
		if main.audio:
			main.audio.play3d("phoenix_wing_beat", global_position, "SFX", -4.0, "phoenix wing beat")
		beat_gust(0.7, false)
	return false


func _land() -> void:
	phase = "land"
	_note("land", {"at": [snappedf(_perch.x, 0.1), snappedf(_perch.y, 0.1), snappedf(_perch.z, 0.1)]})
	true_rig.bank = 0.0
	true_rig.pitch = 0.0
	# hover above the perch, turning to her facing, then drop with the landing stroke
	var start := global_position
	var hover := _perch + Vector3(0, 3.6, 0)
	var t := 0.0
	true_rig.play("hover")
	while t < 1.6:
		var d: float = get_process_delta_time()
		t += d
		var k := clampf(t / 1.6, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		global_position = start.lerp(hover, k)
		rotation.y = lerp_angle(rotation.y, _perch_yaw, 1.0 - exp(-3.0 * d))
		if fmod(t, 0.8) < d:
			if main.audio:
				main.audio.play3d("phoenix_wing_beat", global_position, "SFX", -3.0, "phoenix wing beat")
			beat_gust(1.0)
		await get_tree().process_frame
	var land_len := true_rig.play_clip("land", 0.2, 1.0, false)
	true_rig.state = "land"
	t = 0.0
	var from := global_position
	while t < land_len:
		t += get_process_delta_time()
		var k := clampf(t / 1.05, 0.0, 1.0)
		global_position = from.lerp(_perch, k * k)
		await get_tree().process_frame
	global_position = _perch
	rotation.y = _perch_yaw
	beat_gust(1.2)
	shock(_perch, "wind", 4.0)
	if main.audio:
		main.audio.play3d("phoenix_land", _perch, "SFX", 0.0, "phoenix land")
		main.audio.play3d("phoenix_wing_fold", _perch, "SFX", -6.0, "phoenix wing fold")
	true_rig.play("idle")
	true_rig.set_embers(0.0)
	phase = "perched"
	_gesture_t = 2.5
	_note("perched")


# ------------------------------------------------------------------ perched life
func _perched_step(delta: float) -> void:
	var m := mika()
	if m and m.visible and m.global_position.distance_to(global_position) < 26.0:
		true_rig.look_at_point(head_of(m), 1.0)
	else:
		true_rig.look_at_point(global_position + facing() * 8.0 + Vector3(0, 1.0, 0), 0.4)
	_gesture_t -= delta
	# her display: wings raised high and open (the beauty of the references), held, then folded away
	if true_rig.state == "majestic_enter" and true_rig.clip_done == "majestic_enter":
		true_rig.play("majestic")
		return
	if true_rig.state == "majestic":
		_display_left -= delta
		if _display_left <= 0.0:
			true_rig.play("wing_fold")
		return
	if _gesture_t <= 0.0 and true_rig.state in ["idle", "breathe"]:
		_gesture_t = rng.randf_range(6.0, 13.0)
		var g: String = ["preen", "look", "stretch", "breathe", "call", "display", "display"][rng.randi() % 7]
		if g == "call" and rng.randf() < 0.6:
			g = "look"
		if g == "display":
			_display_left = rng.randf_range(4.0, 7.0)
			true_rig.play("majestic_enter")
			_note("gesture", {"gesture": "display"})
			return
		true_rig.play(g)
		if g == "call" and main.audio:
			main.audio.play_big("phoenix_cry", global_position + Vector3(0, 2.5, 0), 0.0, "phoenix cry")
		_note("gesture", {"gesture": g})
	elif true_rig.state not in ["idle", "breathe"] and true_rig.clip_done == true_rig.state:
		true_rig.play("idle")


# ------------------------------------------------------------------ her fire
## A sunflare at a target (a creature, a brazier, a point). True form: the chest-and-beak cast; human form: a
## one-handed cast through the shared rig. Returns the judged outcome.
func cast_flare(target, p_power := 0.9) -> Dictionary:
	if form == "phoenix" and target is Node3D and (target is Monster or p_power >= 0.95):
		return await cast_nova(target, p_power)
	busy = true
	var flare := PhoenixFlare.new()
	var box := {}
	var done := func(o): box["outcome"] = o
	flare.resolved.connect(done)
	if form == "phoenix":
		if target is Node3D:
			face_point(target.global_position)
			true_rig.look_at_point(PhoenixFlare._aim(target), 1.0)
		true_rig.play("cast_fire")
		true_rig.set_heat(1.0)
		await _wait(1.0)
		if not is_inside_tree():
			return {}
		area.add_child(flare)
		flare.launch(true_rig.beak_point(), target, p_power)
		await _wait(0.6)
		true_rig.set_heat(0.0)
		await _wait(0.9)
		true_rig.play("idle")
	else:
		human.set_meta("flare_target", target)
		human.set_meta("flare_power", p_power)
		if target is Node3D:
			human.look_at_point(target.global_position)
			human.look_head_at(PhoenixFlare._aim(target))
		human.set_heat(1.0)
		var node := human.cast_spell(PhoenixFlare, "magic_attack_1h")
		if node == null:
			busy = false
			return {"ok": false, "detail": "she could not cast"}
		flare.queue_free()
		flare = node
		flare.resolved.connect(done)
		await _wait(1.2)
		human.set_heat(0.0)
	var t0 := _game_t
	while not box.has("outcome") and _game_t - t0 < 8.0:
		await get_tree().process_frame
	busy = false
	var outcome: Dictionary = box.get("outcome", {"ok": false, "effect": "", "detail": "the flare never resolved"})
	_note("flare", outcome)
	return outcome


# ------------------------------------------------------------------ the people near her
## Her fire and her wind are felt by whoever stands near (the developer: "Mika and Luna must react to Oriel's presence
## and attacks"). Everyone within 40 m looks at once (head and face: surprised); inside `brace_r` they guard (Mika
## braces, Luna steps back from it) with a startled cry; inside the blast (hit_r) the ImpactDirector decides how hard it
## lands on each (flinch / stagger / a real fall and get-up, by distance, cover, wards, bracing) - and a short line of
## alarm follows (data/phoenix.json "bystander_lines"; a few seconds' cool-down each).
func shock(at: Vector3, kind: String, brace_r := 9.0, hit_r := 0.0) -> void:
	var lines: Dictionary = data.get("bystander_lines", {})
	# the blast itself (V3 continuation): distance, cover, wards, bracing and her balance decide how hard it lands
	var struck := {}
	if hit_r > 0.0 and main.get("impacts"):
		for r in main.impacts.blast(at + Vector3(0, 0.6, 0), 1.1, hit_r * 1.9, {"source": "oriel", "kind": kind}):
			struck[String(r.get("who", ""))] = String(r.get("tier", "notice"))
	for who in ["mika", "luna"]:
		var c = main.characters.get(who)
		if c == null or not is_instance_valid(c) or not c.visible:
			continue
		var wc := c as WorldCharacter
		var d := Vector2(wc.global_position.x - at.x, wc.global_position.z - at.z).length()
		if d > 40.0:
			continue
		var tier := String(struck.get(who, "notice"))
		if tier == "notice" and not wc.reaction.active:
			wc.look_head_at(at + Vector3(0, 1.2, 0))
			wc.set_expression("surprised", 0.9)
		var how := "look"
		if tier != "notice":
			how = "hit"
			bystander_log.append({"t": snappedf(_game_t, 0.1), "who": who, "kind": kind, "how": "struck:" + tier, "dist": snappedf(d, 0.1)})
		elif d < brace_r and not wc.reaction.active:
			wc.reaction.guard()
			how = "brace"
			if who == "luna" and not wc.casting:
				var away := Vector3(wc.global_position.x - at.x, 0, wc.global_position.z - at.z).normalized()
				wc.dodge(wc.global_position + away * 1.6, 0.45)
			else:
				wc.look_at_point(at)
				wc.play_gesture("brace", 0.08, 0.45)
		if main.affect:
			main.affect.react(who, "struck" if how == "hit" else "first_sight", 1.0 if how != "look" else 0.6)
		var clear_face := func() -> void:
			if is_instance_valid(wc):
				wc.set_expression("surprised", 0.0)
		get_tree().create_timer(1.4).timeout.connect(clear_face)
		bystander_log.append({"t": snappedf(_game_t, 0.1), "who": who, "kind": kind, "how": how, "dist": snappedf(d, 0.1)})
		if how != "look" and _game_t - float(_react_cool.get(who, -99.0)) > 4.0 and main.voice:
			_react_cool[who] = _game_t
			if how != "hit":
				main.voice.react(who, "startle")      # a struck mage's cry comes from her BodyReaction
			var pool: Array = lines.get(who, {}).get("hit" if how == "hit" else kind, [])
			if not pool.is_empty():
				var line := String(pool[rng.randi() % pool.size()])
				var speak := func() -> void:
					if main.voice:
						main.voice.say(who, line, {"mood": "surprised"})
				get_tree().create_timer(0.9).timeout.connect(speak)


## A great wingbeat's wind (the cinematic pass): the trees round her bend away and swing back, leaves are torn from
## the crowns and the litter and dust of the ground blow out from under her - stronger the closer she is to it.
func beat_gust(strength := 1.0, sound := true) -> void:
	var gy: float = area.ground_at(global_position.x, global_position.z) if area and area.has_method("ground_at") else global_position.y
	var alt := global_position.y - gy
	if alt > 22.0:
		return
	var near := clampf(1.0 - alt / 22.0, 0.0, 1.0)
	var k := strength * (0.35 + 0.65 * near)
	var fx := {"ground_y": gy, "leaves": int(28 * k), "litter": int(46 * k * near) if alt < 9.0 else 0, "dust": alt < 7.0}
	Gusts.emit(area, Vector3(global_position.x, gy, global_position.z), 18.0 + 10.0 * k, 0.85 * k, 0.6, 1.3, fx)
	if sound and main.audio:
		main.audio.play_cine("phoenix_wing_gust", global_position + Vector3(0, 1.5, 0), -2.0 + 4.0 * k, "phoenix wing gust")


## Rise (or sink) smoothly by `dy` metres over `seconds` with her wingbeats and their gusts; facing kept.
func _climb(dy: float, seconds: float, beats := 2) -> void:
	var from := global_position
	var t := 0.0
	var next_beat := 0.05
	var beat_dt := seconds / maxf(float(beats), 1.0)
	while t < seconds:
		var d: float = get_process_delta_time()
		t += d
		var k := clampf(t / seconds, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		global_position = from + Vector3(0, dy * k, 0)
		if t >= next_beat and beats > 0:
			next_beat += beat_dt
			beats -= 1
			beat_gust(1.0)
		await get_tree().process_frame


## Her POWER ATTACK (true form), the solar nova (the cinematic pass: an AERIAL attack - the developer: "the attack
## looks so simple"). She springs from the perch on two great wingbeats (the trees bend, leaves and dust fly), hangs
## in the air facing her mark with wings flung high and back while the sun is born before her breast, holds, and
## a full downstroke drives it at the target (the recoil throws her back and the air below her down); the
## detonation is judged by the target; she watches it burn, then sinks back to her perch.
func cast_nova(target: Node3D, p_power := 1.0) -> Dictionary:
	busy = true
	var box := {}
	var perch_pos := global_position
	var perch_rot := rotation.y
	face_point(target.global_position)
	true_rig.look_at_point(PhoenixFlare._aim(target), 1.0)
	_note("nova_rise")
	last_nova = {"perch_y": perch_pos.y, "peak_alt": 0.0}
	# 1. up into the air (her wings clear the ground; the forest feels each beat)
	true_rig.play_clip("takeoff", 0.15, 1.15, false)
	true_rig.state = "takeoff"
	true_rig.set_embers(1.0)
	body.collision_layer = 0
	if main.audio:
		main.audio.play_big("phoenix_takeoff", global_position, 2.0, "phoenix takeoff")
	shock(global_position, "wind", 6.0)
	await _climb(1.4, 0.55, 1)
	true_rig.play("hover")
	await _climb(3.4, 1.0, 2)
	if not is_inside_tree():
		return {}
	# 2. the charge, in the air
	var nova := PhoenixNova.new()
	area.add_child(nova)
	var on_burst := func(o: Dictionary) -> void:
		box["outcome"] = o
		var at: Vector3 = o.get("at", global_position)
		shock(at, "attack", 12.0, 5.0)        # the blast reaches whoever stands near it
	nova.resolved.connect(on_burst)
	true_rig.play_clip("attack_charge", 0.25, 1.0, false)
	true_rig.state = "attack_charge"
	true_rig.set_heat(1.0)
	true_rig.set_aura(1.0)
	true_rig.set_glow(1.6)
	if main.audio:
		main.audio.play_cine("phoenix_nova_charge", global_position + Vector3(0, 2.0, 0), 3.0, "phoenix nova charge")
	var rig := true_rig
	var me := self
	nova.charge(func() -> Vector3: return rig.chest_point() + me.facing() * 1.7 + Vector3(0, 0.3, 0))
	ImpactFX.shake(area, 0.015, 1.6)
	var t := 0.0
	var start := global_position
	while t < 1.6:
		var d: float = get_process_delta_time()
		t += d
		global_position = start + Vector3(0, 0.5 * sin(clampf(t / 1.6, 0.0, 1.0) * PI * 0.5), 0)
		face_point(target.global_position)
		await get_tree().process_frame
	if not is_inside_tree():
		return {}
	last_nova["peak_alt"] = snappedf(global_position.y - perch_pos.y, 0.01)
	true_rig.play_clip("attack_hold", 0.1, 1.0, true)
	await _wait(0.28)
	# 3. the downstroke: the sun is thrown, she is thrown back, the air below her driven down
	true_rig.play_clip("attack_release", 0.05, 1.0, false)
	true_rig.state = "attack_release"
	await _wait(0.12)
	nova.launch(target, p_power)
	beat_gust(1.5, false)
	shock(global_position - Vector3(0, global_position.y - perch_pos.y, 0), "attack", 7.0)
	if main.audio:
		main.audio.play_cine("phoenix_scream", global_position + Vector3(0, 2.5, 0), 0.0, "phoenix battle cry")
	ImpactFX.shake(area, 0.06, 0.35)
	_flash.color = Color(1.0, 0.8, 0.55, 0.0)
	_flash_now(0.2, 0.22)
	var recoil_from := global_position
	var back := -facing()
	t = 0.0
	while t < 0.5:
		var d: float = get_process_delta_time()
		t += d
		var k := 1.0 - pow(1.0 - clampf(t / 0.5, 0.0, 1.0), 3.0)
		global_position = recoil_from + back * 1.4 * k + Vector3(0, 0.6 * k, 0)
		await get_tree().process_frame
	true_rig.play_clip("attack_recover", 0.15, 1.0, false)
	true_rig.state = "attack_recover"
	true_rig.set_aura(0.0)
	var t0 := _game_t
	while not box.has("outcome") and _game_t - t0 < 6.0:
		await get_tree().process_frame
	true_rig.set_heat(0.0)
	# 4. she watches it burn, then sinks back to her perch
	true_rig.play("hover")
	await _wait(1.0)
	var hover_at := global_position
	t = 0.0
	var beat_t := 0.0
	while t < 1.4:
		var d: float = get_process_delta_time()
		t += d
		beat_t += d
		var k := clampf(t / 1.4, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		global_position = hover_at.lerp(perch_pos + Vector3(0, 2.6, 0), k)
		rotation.y = lerp_angle(rotation.y, perch_rot, 1.0 - exp(-3.0 * d))
		if beat_t > 0.7:
			beat_t = 0.0
			beat_gust(0.9)
		await get_tree().process_frame
	var land_len := true_rig.play_clip("land", 0.2, 1.0, false)
	true_rig.state = "land"
	t = 0.0
	var from := global_position
	while t < land_len:
		t += get_process_delta_time()
		var k := clampf(t / 1.0, 0.0, 1.0)
		global_position = from.lerp(perch_pos, k * k)
		await get_tree().process_frame
	global_position = perch_pos
	rotation.y = perch_rot
	beat_gust(1.1)
	if main.audio:
		main.audio.play3d("phoenix_land", perch_pos, "SFX", 0.0, "phoenix land")
	body.collision_layer = 2
	true_rig.set_embers(0.0)
	true_rig.set_glow(PhoenixTrueRig.DAY_GLOW)
	true_rig.play("idle")
	busy = false
	var outcome: Dictionary = box.get("outcome", {"ok": false, "effect": "", "detail": "the nova never resolved"})
	_note("nova", outcome)
	return outcome


## The old fire bowls at the viewpoint: she lights them one by one (an environmental interaction that stays).
func light_bowls() -> Array:
	var out := []
	for br in braziers:
		if not is_instance_valid(br):
			continue
		var o: Dictionary = await cast_flare(br, 0.8)
		out.append({"brazier": br.name, "lit": br.lit, "effect": o.get("effect", "")})
	_note("lit_bowls", {"result": out})
	return out


# ------------------------------------------------------------------ the transformation
func _set_core(power: float, scale: float) -> void:
	_core.visible = power > 0.01
	# the cinematic pass: the fire tornado carries the moment; the old core is only the white heart inside it
	(_core.material_override as ShaderMaterial).set_shader_parameter("power", power * 0.65)
	_core.scale = Vector3.ONE * maxf(scale * 0.5, 0.02)
	_core_light.light_energy = power * 7.0 * float(RenderProfile.get_setting("magic_light_scale"))


func _flash_now(seconds := 0.28, level := 0.85) -> void:
	_flash.color.a = level
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The TRANSFORMATION SPACE: while she changes, the world dims into her light (sky, ambient and sun fall away, a
## warm vignette closes in) and comes back after. Values are restored exactly.
func _space(on: bool, seconds: float) -> void:
	var we = area.get("world_env")
	if we == null:
		return
	var env: Environment = (we as WorldEnvironment).environment
	var sun = area.get("sun")
	if on and _space_saved.is_empty():
		_space_saved = {"bg": env.background_energy_multiplier, "amb": env.ambient_light_energy,
			"sun": (sun as DirectionalLight3D).light_energy if sun else 0.0, "glow": env.glow_intensity}
	if _space_saved.is_empty():
		return
	var tw := create_tween()
	tw.tween_method(_apply_space, _space_k, 1.0 if on else 0.0, maxf(seconds, 0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not on:
		tw.tween_callback(func(): _space_saved.clear())


func _apply_space(k: float) -> void:
	_space_k = k
	if _space_saved.is_empty():
		return
	var we = area.get("world_env")
	if we == null:
		return
	var env: Environment = (we as WorldEnvironment).environment
	env.background_energy_multiplier = float(_space_saved.bg) * (1.0 - 0.62 * k)
	env.ambient_light_energy = float(_space_saved.amb) * (1.0 - 0.55 * k)
	env.glow_intensity = float(_space_saved.glow) * (1.0 + 0.5 * k)
	var sun = area.get("sun")
	if sun:
		(sun as DirectionalLight3D).light_energy = float(_space_saved.sun) * (1.0 - 0.68 * k)
	if _vignette:
		(_vignette.material as ShaderMaterial).set_shader_parameter("amount", 0.75 * k)


## True form -> human form. variation: "cinematic" (the first meeting: ~10 s, a magical-girl sequence with camera
## beats) | "short" (gameplay, ~4 s). The bird displays, wraps herself in her wings, burns into a core of fire;
## at the swap the woman stands inside it as a body of light, and each part of her is made in turn (her side of
## the sequence: PhoenixHuman.tf_step). Position, facing and identity are continuous; collision switches.
func transform_to_human(variation := "short") -> Dictionary:
	if form != "phoenix" or busy:
		return {"ok": false, "detail": "not in her true form or busy"}
	busy = true
	phase = "to_human"
	state = "arriving"
	var spec: Dictionary = data.transformation
	var cine := variation == "cinematic"
	var total: float = float(spec.cinematic_s) if cine else float(spec.short_s)
	var hit: float = float(spec.cinematic_hit_s) if cine else float(spec.short_hit_s)
	var start_pos := global_position
	var yaw := rotation.y
	var ground := Vector3(global_position.x, area.ground_at(global_position.x, global_position.z), global_position.z)
	_note("transform_begin", {"to": "human", "variation": variation})
	if main.audio and cine:
		main.audio.play_cine("phoenix_tf_music", global_position + Vector3(0, 1.5, 0), 0.0, "transformation music")   # its hit lands at 3.40 s
	var prev_director := false
	if cine:
		prev_director = main.director.enabled if main.director else false
		if main.director:
			main.director.enabled = false
		_shot(Vector3(5.5, 1.2, 9.0), Vector3(0, 2.5, 0), 48.0)
	# 1. her display (cinematic) or straight into the cocoon (short); the fire rises; the world dims
	true_rig.play_clip("majestic_enter" if cine else "wing_wrap", 0.25, 1.0, false)
	true_rig.state = "majestic_enter" if cine else "wing_wrap"
	true_rig.set_embers(1.0)
	true_rig.set_aura(1.0)
	true_rig.set_glow(1.5)
	_embers.emitting = true
	var tw := create_tween()
	tw.tween_property(true_rig, "heat_target", 1.0, maxf(hit - 0.4, 0.4))
	_space(true, 1.2 if cine else 0.5)
	shock(ground, "transform", 0.0)
	# the circle of fire catches round her; later a fire tornado rises over her and engulfs her to the hit
	FireFX.ring_of_fire(area, ground, 3.1, hit + 1.6, 0.9 if cine else 0.35)
	if main.audio:
		main.audio.play_cine("phoenix_tf_ignite", ground + Vector3(0, 1.0, 0), 0.0, "ring of fire")
	var vortex: FireVortex = null
	var vortex_at := 1.2 if cine else 0.15
	var swirl_t := 0.0
	# the woman is prepared where the bird stands, drawn but not yet made (her shaders compile now, never a
	# T-pose); the bird's body stops being solid so the two never collide
	body.collision_layer = 0
	human.global_position = ground
	human.rotation.y = yaw + PI
	human.velocity = Vector3.ZERO
	human.collision_layer = 0
	human.process_mode = Node.PROCESS_MODE_INHERIT
	human.set_heat(1.0)
	human.set_expression("relaxed", 1.0)
	human.tf_prepare()
	_still("tf_bow")
	var wrap_at := 1.45 if cine else 0.0
	var veil_at := hit - (1.7 if cine else 0.9)
	var dissolve_at := hit - (1.1 if cine else 0.7)
	var core_at := hit - (1.3 if cine else 0.8)
	var t := 0.0
	var wrapped := not cine
	var veil_on := false
	var shot2 := false
	while t < hit:
		var d: float = get_process_delta_time()
		t += d
		if not wrapped and t >= wrap_at:
			wrapped = true
			true_rig.play_clip("wing_wrap", 0.3, 1.0, false)
			true_rig.state = "wing_wrap"
		if t >= veil_at and not veil_on:
			veil_on = true
			_veil.emitting = true
		if cine and t > 1.7 and not shot2:
			shot2 = true
			_shot(Vector3(2.6, 2.1, 5.0), Vector3(0, 1.9, 0.3), 40.0)
			_still("tf_close")
		if t >= dissolve_at:
			true_rig.set_dissolve(clampf((t - dissolve_at) / (hit - dissolve_at), 0.0, 1.0), global_position + Vector3(0, 1.6, 0.2))
		if t >= core_at:
			var k := clampf((t - core_at) / (hit - core_at), 0.0, 1.0)
			_set_core(0.25 + 1.15 * k, 0.3 + 1.0 * k)
		if t >= vortex_at:
			if vortex == null:
				vortex = FireFX.vortex(area, ground, 0.82)
				if main.audio:
					main.audio.play_cine("phoenix_tf_tornado", ground + Vector3(0, 2.0, 0), 2.0, "fire tornado")
			var vk := clampf((t - vortex_at) / maxf(hit - vortex_at, 0.1), 0.0, 1.0)
			vortex.set_strength(0.3 + 0.7 * vk)     # it is there at once, and roars up to the hit
			swirl_t += d
			if swirl_t > 0.9:
				swirl_t = 0.0
				Gusts.emit(area, ground, 18.0, 0.3 + 0.4 * vk, 0.9, 1.6)
		await get_tree().process_frame
	# 2. the swap, on the hit: the tornado bursts, the body of light stands in the fire
	_flash_now(0.3, 0.7)
	true_rig.visible = false
	true_rig.set_dissolve(0.0, global_position)
	true_rig.heat_target = 0.0
	true_rig.set_embers(0.0)
	true_rig.set_aura(0.0)
	true_rig.set_glow(PhoenixTrueRig.DAY_GLOW)
	_veil.emitting = false
	human.visible = true
	human.collision_layer = 1
	human.global_position = ground
	human.tf_begin(variation)
	form = "human"
	ImpactFX.shockwave(area, ground + Vector3(0, 0.05, 0), Color(1.0, 0.7, 0.3), 5.0)
	ImpactFX.ground_ring(area, ground + Vector3(0, 0.03, 0), Color(1.0, 0.55, 0.2), 2.6)
	_burst_at(ground, vortex, cine)
	_note("transform_swap", {"to": "human", "t": snappedf(t, 0.01)})
	if main.audio:
		main.audio.play_cine("phoenix_tf_shimmer", ground + Vector3(0, 1.4, 0), -2.0, "sparkles")
	_still("tf_swap")
	if cine:
		_shot(Vector3(0.9, 1.35, 3.6), Vector3(0, 1.15, 0), 38.0)
	# 3. her making (PhoenixHuman.tf_step): hair, sandals, the spin and the skirt, the arms, the bodice, the crown,
	#    the phantom wings, her final pose; camera beats on the cinematic
	var t2 := 0.0
	var m := mika()
	var looked := false
	var beats := [[1.4, Vector3(-1.4, 0.5, 2.6), Vector3(0, 0.9, 0), 42.0, "tf_spin"], [3.6, Vector3(0.8, 1.45, 2.1), Vector3(0, 1.3, 0), 36.0, "tf_arms"],
		[5.0, Vector3(0.35, 1.62, 1.15), Vector3(0, 1.55, 0), 30.0, "tf_crown"], [5.85, Vector3(-1.8, 1.4, 4.6), Vector3(0, 1.3, 0), 44.0, "tf_final"]]
	var beat_i := 0
	var wings_at := 5.3 if cine else 1.4
	var winged := false
	while t2 < total - hit:
		var d: float = get_process_delta_time()
		t2 += d
		human.tf_step(t2)
		if t2 >= wings_at and not winged:
			winged = true
			FireFX.fire_wings(area, human.global_position + Vector3(0, 1.25, 0), human.rotation.y + PI, 3.2 if cine else 2.6, 2.6 if cine else 1.6)
			Gusts.emit(area, ground, 16.0, 0.45, 0.7, 1.4, {"leaves": 30, "ground_y": ground.y})
			if main.audio:
				main.audio.play_cine("phoenix_tf_wings", ground + Vector3(0, 1.6, 0), 0.0, "wings of fire")
		var k := clampf(t2 / 0.9, 0.0, 1.0)
		_set_core(1.4 * (1.0 - k) * (1.0 - k), 1.3 - 1.0 * k)
		if cine and beat_i < beats.size() and t2 >= float(beats[beat_i][0]):
			var bt: Array = beats[beat_i]
			_shot(bt[1], bt[2], bt[3])
			_still(String(bt[4]))
			beat_i += 1
		if not cine and t2 > 1.0 and t2 - d <= 1.0:
			_still("tf_emerge")
		if t2 > total - hit - 0.9 and not looked:
			looked = true
			human.set_expression("relaxed", 0.0)
			if m:
				human.look_head_at(head_of(m))
		await get_tree().process_frame
	_set_core(0.0, 0.2)
	_embers.emitting = false
	human.tf_end()
	human.set_heat(0.0)
	if m:
		human.look_at_point(m.global_position)
	_space(false, 1.4 if cine else 0.6)
	_still("tf_done")
	if cine:
		if m:
			var mid := (human.global_position + m.global_position) * 0.5 + Vector3(0, 1.3, 0)
			var side := (m.global_position - human.global_position).cross(Vector3.UP).normalized()
			_shot_abs(mid + side * 7.2 + Vector3(0, 0.9, 0), mid, 44.0)
		await _wait(0.8)
		main.camera_rig.clear_shot()
		if main.director:
			main.director.enabled = prev_director
	phase = "human"
	state = "idle"
	busy = false
	var rec := {"to": "human", "variation": variation, "seconds": snappedf(t + t2, 0.01), "hit_s": snappedf(t, 0.01),
		"start": [snappedf(start_pos.x, 0.01), snappedf(start_pos.z, 0.01)], "end": [snappedf(human.global_position.x, 0.01), snappedf(human.global_position.z, 0.01)],
		"drift_m": snappedf(Vector2(human.global_position.x - start_pos.x, human.global_position.z - start_pos.z).length(), 0.01)}
	transformations.append(rec)
	_note("transform_done", rec)
	return {"ok": true, "record": rec}


## Human form -> true form (the way back, ~9 s): each part of her unmade into ribbons of fire (the crown first),
## she rises spinning as light while wings of flame open from her back, a pillar of fire, and the bird bursts
## out of it wings-first (wing_burst), plumage growing from her heart outward, into her display.
func transform_to_phoenix(camera := false) -> Dictionary:
	if form != "human" or busy:
		return {"ok": false, "detail": "not in her human form or busy"}
	busy = true
	phase = "to_phoenix"
	state = "arriving"
	var spec: Dictionary = data.transformation
	var total := float(spec.reform_s)
	var hit := float(spec.reform_hit_s)
	var start_pos := human.global_position
	var ground := Vector3(start_pos.x, area.ground_at(start_pos.x, start_pos.z), start_pos.z)
	var yaw := human.rotation.y - PI
	_note("transform_begin", {"to": "phoenix", "variation": "reform"})
	if main.audio:
		main.audio.play_cine("phoenix_tf_music", ground + Vector3(0, 1.4, 0), 0.0, "transformation music")
	global_position = ground
	rotation.y = yaw
	if camera:
		_shot(Vector3(1.4, 1.3, 4.2), Vector3(0, 1.3, 0), 40.0)
	human.tf_begin("reform")
	_embers.emitting = true
	_space(true, 1.0)
	true_rig.visible = false
	true_rig.set_dissolve(1.0, ground + Vector3(0, 1.6, 0.2))
	true_rig.heat_target = 1.0
	true_rig.set_aura(1.0)
	true_rig.set_glow(1.5)
	true_rig.play_clip("wing_wrap", 0.0, 1.0, false)
	true_rig.player.seek(true_rig.clip_length("wing_wrap") - 0.01, true)
	true_rig.player.pause()
	var t := 0.0
	var core_at := hit - 1.0
	var veil_on := false
	var wide := false
	FireFX.ring_of_fire(area, ground, 3.1, hit + 1.4, 0.8)
	if main.audio:
		main.audio.play_cine("phoenix_tf_ignite", ground + Vector3(0, 1.0, 0), 0.0, "ring of fire")
	var vortex: FireVortex = null
	var vortex_at := hit - 2.2
	var swirl_t := 0.0
	while t < hit:
		var d: float = get_process_delta_time()
		t += d
		human.tf_step(t)
		if camera and t > 2.0 and not wide:
			wide = true
			_shot(Vector3(3.0, 1.6, 7.5), Vector3(0, 2.0, 0), 46.0)
		if t >= core_at:
			var k := clampf((t - core_at) / (hit - core_at), 0.0, 1.0)
			_set_core(0.25 + 1.2 * k, 0.3 + 1.1 * k)
		if t >= hit - 0.8 and not veil_on:
			veil_on = true
			_veil.emitting = true
		if t >= vortex_at:
			if vortex == null:
				vortex = FireFX.vortex(area, ground, 0.9)
				if main.audio:
					main.audio.play_cine("phoenix_tf_tornado", ground + Vector3(0, 2.0, 0), 2.0, "fire tornado")
			var vk := clampf((t - vortex_at) / maxf(hit - vortex_at, 0.1), 0.0, 1.0)
			vortex.set_strength(0.3 + 0.7 * vk)     # it is there at once, and roars up to the hit
			swirl_t += d
			if swirl_t > 0.9:
				swirl_t = 0.0
				Gusts.emit(area, ground, 18.0, 0.3 + 0.4 * vk, 0.9, 1.6)
		await get_tree().process_frame
	_still("rf_core")
	_flash_now(0.3, 0.7)
	human.tf_end()
	human.visible = false
	human.collision_layer = 0
	human.process_mode = Node.PROCESS_MODE_DISABLED
	human.set_dissolve(0.0, ground)
	true_rig.visible = true
	true_rig.play_clip("wing_burst", 0.0, 1.0, false)
	true_rig.state = "wing_burst"
	true_rig.set_embers(1.0)
	body.collision_layer = 2
	form = "phoenix"
	ImpactFX.shockwave(area, ground + Vector3(0, 0.05, 0), Color(1.0, 0.75, 0.35), 6.0)
	ImpactFX.shake(area, 0.035, 0.4)
	_burst_at(ground, vortex, true)
	_note("transform_swap", {"to": "phoenix", "t": snappedf(t, 0.01)})
	var t2 := 0.0
	var displayed := false
	var called := false
	while t2 < total - hit:
		var d: float = get_process_delta_time()
		t2 += d
		true_rig.set_dissolve(clampf(1.0 - t2 / 1.1, 0.0, 1.0), ground + Vector3(0, 1.6, 0.2))
		_set_core(1.45 * clampf(1.0 - t2 / 0.8, 0.0, 1.0), 1.4 - 1.1 * clampf(t2 / 0.8, 0.0, 1.0))
		if t2 > 0.3 and not called:
			called = true
			_veil.emitting = false
			if main.audio:
				main.audio.play_big("phoenix_cry", global_position + Vector3(0, 2.5, 0), 0.0, "phoenix cry")
			_still("rf_wings")
		if t2 > 1.0 and not displayed:
			displayed = true
			true_rig.play_clip("majestic", 0.4, 1.0, true)
			true_rig.state = "majestic"
		if t2 > total - hit - 1.6:
			true_rig.heat_target = 0.0
			true_rig.set_aura(0.0)
		await get_tree().process_frame
	_set_core(0.0, 0.2)
	_embers.emitting = false
	true_rig.set_dissolve(0.0, ground)
	true_rig.set_embers(0.0)
	true_rig.set_glow(PhoenixTrueRig.DAY_GLOW)
	true_rig.play("perch_settle")
	_space(false, 1.2)
	if camera:
		main.camera_rig.clear_shot()
	phase = "perched"
	state = "arriving"
	busy = false
	var rec := {"to": "phoenix", "variation": "reform", "seconds": snappedf(t + t2, 0.01), "hit_s": snappedf(t, 0.01),
		"start": [snappedf(start_pos.x, 0.01), snappedf(start_pos.z, 0.01)], "end": [snappedf(global_position.x, 0.01), snappedf(global_position.z, 0.01)],
		"drift_m": snappedf(Vector2(global_position.x - start_pos.x, global_position.z - start_pos.z).length(), 0.01)}
	transformations.append(rec)
	_note("transform_done", rec)
	return {"ok": true, "record": rec}


## The transformation's hit: the tornado bursts outward into fire, the shocked air races out, the forest bends
## away (leaves torn from the crowns, dust driven across the stones) and the clearing is lit white-gold.
func _burst_at(ground: Vector3, vortex: FireVortex, big := true) -> void:
	shock(ground, "transform", 10.0 if big else 7.0, 2.6)
	if vortex and is_instance_valid(vortex):
		vortex.set_strength(1.45)
		vortex.collapse(0.6)
	var s := 0.62 if big else 0.45
	if FireFX.available():
		FireFX.card(area, "explosion", ground + Vector3(0, 1.5, 0), s, 1.7, {"fire_gain": 1.3, "fire_tint": Color(1.0, 0.7, 0.42), "smoke_alpha": 0.45})
		FireFX.card(area, "burst", ground + Vector3(0, 1.0, 0), 1.4 if big else 1.0, 0.9, {"fire_gain": 1.5, "fire_tint": Color(1.0, 0.7, 0.42)}, 0.0, 1.2)
	FireFX.haze(area, ground + Vector3(0, 1.0, 0), 22.0, 1.3, 0.8, true)
	FireFX.light(area, ground + Vector3(0, 1.8, 0), Color(1.0, 0.7, 0.42), 11.0 if big else 7.0, 24.0, 0.9, true)
	FireFX.dust_ring(area, ground, 0.9, 1.0)
	Gusts.emit(area, ground, 30.0 if big else 22.0, 1.3 if big else 0.9, 0.55, 1.1, {"leaves": 90 if big else 45, "litter": 80 if big else 40, "ground_y": ground.y})
	ImpactFX.shake(area, 0.05 if big else 0.03, 0.5)
	if main.audio:
		main.audio.play_cine("phoenix_tf_burst", ground + Vector3(0, 1.5, 0), 3.0, "transformation burst")


func _shot(rel: Vector3, look_rel: Vector3, fov: float) -> void:
	var b := Basis(Vector3.UP, rotation.y)
	var base := global_position
	_shot_abs(base + b * rel, base + b * look_rel, fov)


func _shot_abs(pos: Vector3, look: Vector3, fov: float) -> void:
	# never inside the ground
	var gy: float = area.ground_at(pos.x, pos.z) if area.has_method("ground_at") else pos.y
	pos.y = maxf(pos.y, gy + 0.6)
	main.camera_rig.set_shot(pos, look, fov)


# ------------------------------------------------------------------ human-form life
## Sit at the edge of the terrace and watch the valley (the K8 ground-sit set).
func sit_down() -> void:
	if form != "human" or human.ground_pose == "sit":
		return
	human.play_gesture("sit_ground_enter", 0.3, 0.3)
	await _wait(maxf(human.animation_length("sit_ground_enter") - 0.2, 0.3))
	human.play_gesture("sit_ground_loop", 0.3, 0.6)
	human.set_ground_pose("sit", 0.6)
	_sat_since = _game_t
	_note("sit")


func stand_up() -> void:
	if form != "human" or human.ground_pose != "sit":
		return
	human.play_gesture("sit_ground_exit", 0.2, 0.4)
	human.set_ground_pose("", 0.7)
	await _wait(maxf(human.animation_length("sit_ground_exit") - 0.1, 0.3))
	human.end_gesture()
	_sat_since = -1.0
	_note("stand")


func walk_to(p: Vector3) -> void:
	if form == "human":
		human.navigate_to(p)


func _human_step(delta: float) -> void:
	global_position = human.global_position
	rotation.y = human.rotation.y - PI
	var m := mika()
	if state == "talking" and talk_target and is_instance_valid(talk_target):
		human.look_head_at(head_of(talk_target))
		if human.current_action == "idle" and human.ground_pose == "":
			human.play_gesture("idle_talk", 0.4, 0.5)
	elif m and m.visible and m.global_position.distance_to(global_position) < 12.0 and human.ground_pose == "":
		human.look_head_at(head_of(m))
	_gesture_t -= delta
	if state == "idle" and _gesture_t <= 0.0 and not busy and human.ground_pose == "" and human.current_action == "idle":
		_gesture_t = rng.randf_range(7.0, 14.0)
		var g: String = ["look_around", "stretch_neck", "idle_talk"][rng.randi() % 3]
		if human.has_clip(g):
			human.play_gesture(g, 0.4, 0.5)
			_note("gesture", {"gesture": g})


# ------------------------------------------------------------------ leaving
func leave() -> void:
	if leaving:
		return
	leaving = true
	if form == "human":
		if human.ground_pose == "sit":
			await stand_up()
		var m := mika()
		if m:
			human.look_at_point(m.global_position)
		await say(String(data.lines.farewell), "tender")
		await say(String(data.lines.reform), "serious")
		await transform_to_phoenix(true)
		await _wait(0.6)
	await takeoff()


func takeoff() -> void:
	phase = "takeoff"
	state = "leaving"
	_note("takeoff")
	var len := true_rig.play_clip("takeoff", 0.2, 1.0, false)
	true_rig.state = "takeoff"
	true_rig.set_embers(1.0)
	if main.audio:
		main.audio.play3d("phoenix_takeoff", global_position, "SFX", 0.0, "phoenix takeoff")
	var t := 0.0
	var from := global_position
	var gusted := 0
	while t < len:
		var d: float = get_process_delta_time()
		t += d
		var k := clampf((t - 0.5) / maxf(len - 0.5, 0.1), 0.0, 1.0)
		global_position = from + Vector3(0, 1.6 * k * k, 0) + facing() * (1.2 * k * k)
		if (gusted == 0 and t > 0.45) or (gusted == 1 and t > 1.2):
			gusted += 1
			beat_gust(1.3)
		await get_tree().process_frame
	_path.clear()
	for p in home.leave:
		_path.append(Vector3(p[0], p[1], p[2]))
	_path_i = 0
	_vel = facing() * 5.0 + Vector3(0, 3.0, 0)
	phase = "leave"
	true_rig.play("fly")
	body.collision_layer = 0


func _process(delta: float) -> void:
	_game_t += delta
	match phase:
		"arrive", "circle":
			if _fly_step(delta):
				_land()
		"leave":
			if _fly_step(delta):
				phase = "gone"
				state = "gone"
				_note("gone")
				if is_instance_valid(human):
					human.queue_free()
				queue_free()
		"perched":
			if not busy:
				_perched_step(delta)
		"human":
			if is_instance_valid(human):
				_human_step(delta)
