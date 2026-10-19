class_name SpellFX
extends Node
## Every spell effect as a reusable SHAPE - projectile, beam, burst, shield, aura, slash - built once and recoloured /
## re-textured by ELEMENT (data/elements.json). When Mika or Luna masters a new element her spells switch to its
## colours, particles and sounds: no new effect work. docs/VFX_STYLE_GUIDE.md: three beats (anticipation, a fast
## strike, a slower fade), a white core over the element's colour, impact frames only on big hits, pooled and
## pre-warmed (nothing is built in a fight), no extra real-time lights.
##
## Materials: ONE per (element, mask, billboard) - shared by every instance (per-instance alpha / progress / boost are
## instance uniforms), so one compiled pipeline per element. Nodes come from per-shape pools and go back after use.

const MASK_DIR := "res://assets/vfx/masks/"
const RAMP := preload("res://shaders/vfx/element_ramp.gdshader")
const FRESNEL := preload("res://shaders/vfx/element_fresnel.gdshader")
const SHAPES := ["projectile", "beam", "burst", "shield", "aura", "slash"]

static var instance: SpellFX
static var data := {}
static var _el_cache := {}
static var _mat_cache := {}
static var _mesh_cache := {}
static var _tex_cache := {}

var main: Node
var root: Node3D
var _pools := {}           # shape -> Array of idle FX nodes
var made := 0              # FX nodes built (tests: a fight builds none)


# ------------------------------------------------------------------ data
static func load_data() -> Dictionary:
	if data.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/elements.json"))
		data = j if j is Dictionary else {"elements": {}, "mages": {}}
	return data


## The element a mage's spells use now: the last one she has mastered (progress.elements), else her first.
static func element_for(who: String) -> String:
	var order: Array = load_data().get("mages", {}).get(who, {}).get("elements", ["wind"])
	var have: Array = WorldState.mind(who).progress.get("elements", []) if WorldState.minds.has(who) else []
	var pick := String(order[0]) if not order.is_empty() else "wind"
	for e in order:
		if have.has(e):
			pick = String(e)
	return pick


## Parsed element: Colors, textures and the rest of its data entry.
static func element(id: String) -> Dictionary:
	if _el_cache.has(id):
		return _el_cache[id]
	var src: Dictionary = load_data().get("elements", {}).get(id, load_data().get("elements", {}).get("wind", {}))
	var e := src.duplicate()
	e["id"] = id
	for k in ["core", "body", "edge"]:
		e[k] = Color(String(src.get(k, "#FFFFFF")))
	_el_cache[id] = e
	return e


static func mask(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load(MASK_DIR + name + ".png")
	return _tex_cache[name]


## The shared material of an element on a mask (billboard or flat); spin turns it (circles, shields).
static func ramp_material(el: String, mask_name: String, billboard := false, spin := 0.0, glow_mul := 1.0) -> ShaderMaterial:
	var key := "%s|%s|%s|%.2f|%.2f" % [el, mask_name, billboard, spin, glow_mul]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var e := element(el)
	var m := ShaderMaterial.new()
	m.shader = RAMP
	m.set_shader_parameter("mask", mask(mask_name))
	m.set_shader_parameter("core_color", e.core)
	m.set_shader_parameter("body_color", e.body)
	m.set_shader_parameter("edge_color", e.edge)
	m.set_shader_parameter("glow", float(e.get("glow", 2.4)) * glow_mul)
	m.set_shader_parameter("billboard", billboard)
	m.set_shader_parameter("spin", spin)
	_mat_cache[key] = m
	return m


static func fresnel_material(el: String, glow_mul := 1.0) -> ShaderMaterial:
	var key := "fresnel|%s|%.2f" % [el, glow_mul]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var e := element(el)
	var m := ShaderMaterial.new()
	m.shader = FRESNEL
	m.set_shader_parameter("core_color", e.core)
	m.set_shader_parameter("body_color", e.body)
	m.set_shader_parameter("edge_color", e.edge)
	m.set_shader_parameter("glow", float(e.get("glow", 2.4)) * 0.8 * glow_mul)
	m.set_shader_parameter("flow_mask", mask("flow"))
	_mat_cache[key] = m
	return m


## The element's particle sprite: billboarded, coloured over its life core -> body -> edge (vertex colour x mask).
static func particle_mesh(el: String, sprite: String, size: float) -> QuadMesh:
	var key := "pm|%s|%s|%.3f" % [el, sprite, size]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = mask(sprite)
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm.disable_receive_shadows = true
	q.material = sm
	_mesh_cache[key] = q
	return q


static func particle_process(el: String, motion: String) -> ParticleProcessMaterial:
	return FX.process("spellfx_%s_%s" % [el, motion], func(pm: ParticleProcessMaterial): _setup_process(pm, el, motion))


static func _setup_process(pm: ParticleProcessMaterial, el: String, motion: String) -> void:
	var e := element(el)
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.color_ramp = FX.ramp([Color(e.core, 0.0), Color(e.core, 1.0), Color(e.body, 0.9), Color(e.edge, 0.0)], [0.0, 0.12, 0.5, 1.0])
	match motion:
		"burst":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.15
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 180.0
			pm.initial_velocity_min = 3.0
			pm.initial_velocity_max = 7.5
			pm.damping_min = 4.0
			pm.damping_max = 7.0
		"trail":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.12
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.5
			pm.damping_min = 1.0
			pm.damping_max = 2.0
		"rise":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_radius = 0.55
			pm.emission_ring_inner_radius = 0.2
			pm.emission_ring_height = 0.1
			pm.emission_ring_axis = Vector3.UP
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 12.0
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.4
			pm.tangential_accel_min = 0.6
			pm.tangential_accel_max = 1.2
		"gather":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			pm.emission_sphere_radius = 0.9
			pm.radial_accel_min = -6.0
			pm.radial_accel_max = -4.0
			pm.tangential_accel_min = 1.0
			pm.tangential_accel_max = 2.0


static func sound(el: String, phase: String) -> String:
	var fam := String(element(el).get("sound", "arcane"))
	for p in ["res://assets/audio/synth/spell_%s_%s.ogg" % [fam, phase], "res://assets/audio/synth/spell_arcane_%s.ogg" % phase]:
		if ResourceLoader.exists(p):
			return p
	return ""


static func quad_mesh(size: Vector2) -> QuadMesh:
	var key := "quad|%s" % str(size)
	if not _mesh_cache.has(key):
		var q := QuadMesh.new()
		q.size = size
		_mesh_cache[key] = q
	return _mesh_cache[key]


# ------------------------------------------------------------------ setup, pools, pre-warm
func setup(m: Node) -> void:
	main = m
	instance = self
	root = Node3D.new()
	root.name = "SpellFX"
	main.add_child(root)


## Builds a few of every shape for these elements and draws each once (nearly invisible, in front of the lens) so
## every pipeline is compiled and every pool filled BEFORE a fight - nothing is built or compiled mid-fight.
func prewarm(elements: Array, per_shape := 3) -> void:
	var cam := get_viewport().get_camera_3d()
	var shown: Array = []
	for el in elements:
		for shape in SHAPES:
			for i in per_shape:
				var n := _build(shape, String(el))
				_release(n)
			var w := _take(shape, String(el))
			if cam:
				w.global_position = cam.global_position - cam.global_transform.basis.z * 4.0
			w.visible = true
			_set_alpha(w, 0.004)
			shown.append(w)
	for i in 3:
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		else:
			await get_tree().process_frame
	for w in shown:
		_release(w)


func _take(shape: String, el: String) -> Node3D:
	var key := "%s|%s" % [shape, el]
	var pool: Array = _pools.get(key, [])
	var n: Node3D = pool.pop_back() if not pool.is_empty() else _build(shape, el)
	_pools[key] = pool
	n.visible = true
	n.set_meta("busy", true)
	_set_alpha(n, 1.0)
	_set_progress(n, 0.0)
	return n


func _release(n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	n.visible = false
	n.set_meta("busy", false)
	if n.get_parent() != root:
		n.reparent(root, false)
	for p in n.get_meta("particles", []):
		(p as GPUParticles3D).emitting = false
	var key := "%s|%s" % [n.get_meta("shape"), n.get_meta("element")]
	var pool: Array = _pools.get(key, [])
	pool.append(n)
	_pools[key] = pool


func _set_alpha(n: Node3D, a: float) -> void:
	for g in n.get_meta("glows", []):
		(g as GeometryInstance3D).set_instance_shader_parameter("alpha", a)


func _set_progress(n: Node3D, p: float) -> void:
	for g in n.get_meta("glows", []):
		(g as GeometryInstance3D).set_instance_shader_parameter("progress", p)


func _glow_quad(parent: Node3D, mat: Material, size: Vector2, glows: Array) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = quad_mesh(size)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	glows.append(mi)
	return mi


func _particles(parent: Node3D, el: String, sprite: String, size: float, amount: int, life: float, motion: String, local := false) -> GPUParticles3D:
	var p := FX.particles(amount, life, particle_process(el, motion), particle_mesh(el, sprite, size), local)
	p.emitting = false
	parent.add_child(p)
	return p


## One shape for one element, as a node of parts (never added to the world here; _take hands it out).
func _build(shape: String, el: String) -> Node3D:
	made += 1
	var e := element(el)
	var n := Node3D.new()
	n.name = "%s_%s_%d" % [shape, el, made]
	n.set_meta("shape", shape)
	n.set_meta("element", el)
	var glows: Array = []
	var parts: Array = []
	match shape:
		"projectile":
			# a spinning element sprite with a white-hot glint at its heart, trailing the element's particles
			_glow_quad(n, ramp_material(el, String(e.particle), true, 6.0, 1.6), Vector2(1.1, 1.1), glows)
			_glow_quad(n, ramp_material(el, String(e.spark), true, 0.0, 2.4), Vector2(1.7, 1.7), glows)
			parts.append(_particles(n, el, String(e.particle), 0.18, 70, 0.9, "trail"))
			parts.append(_particles(n, el, String(e.spark), 0.12, 50, 0.5, "trail"))
		"beam":
			# two crossed strips along -Z (scaled to length), a bright source and impact glint
			var b := Node3D.new()
			b.name = "Strip"
			n.add_child(b)
			var q1 := _glow_quad(b, ramp_material(el, "beam", false, 0.0, 1.8), Vector2(1.0, 1.1), glows)
			q1.rotation = Vector3(-PI * 0.5, PI * 0.5, 0)
			var q2 := _glow_quad(b, ramp_material(el, "beam", false, 0.0, 1.8), Vector2(1.0, 1.1), glows)
			q2.rotation = Vector3(0, PI * 0.5, 0)
			_glow_quad(n, ramp_material(el, String(e.spark), true, 0.0, 2.6), Vector2(2.2, 2.2), glows)
			parts.append(_particles(n, el, String(e.spark), 0.12, 60, 0.6, "burst"))
		"burst":
			# impact: a star flash, a shockwave ring, sparks thrown outward
			_glow_quad(n, ramp_material(el, "burst_star", true, 0.0, 2.8), Vector2(3.0, 3.0), glows)
			var ring := _glow_quad(n, ramp_material(el, "ring", true, 0.0, 2.2), Vector2(1.6, 1.6), glows)
			ring.name = "Ring"
			parts.append(_particles(n, el, String(e.spark), 0.16, 90, 0.6, "burst"))
			parts.append(_particles(n, el, String(e.particle), 0.2, 50, 1.0, "burst"))
		"shield":
			# her magic circle upright before her, a glowing dome over it
			var c := _glow_quad(n, ramp_material(el, String(e.circle), false, 1.4, 2.0), Vector2(2.8, 2.8), glows)
			c.name = "Circle"
			var dome := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 1.15
			sm.height = 2.3
			sm.radial_segments = 24
			sm.rings = 12
			dome.mesh = sm
			dome.material_override = fresnel_material(el, 1.8)
			dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dome.position = Vector3(0, 0, 0.6)
			dome.scale = Vector3(1.0, 1.0, 0.45)
			n.add_child(dome)
			glows.append(dome)
		"aura":
			# a rim-lit shell round her, her magic circle turning at her feet, the element rising
			var shell := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.55
			cm.height = 2.0
			cm.radial_segments = 20
			cm.rings = 8
			shell.mesh = cm
			shell.material_override = fresnel_material(el, 1.6)
			shell.position = Vector3(0, 0.95, 0)
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(shell)
			glows.append(shell)
			var floor_c := _glow_quad(n, ramp_material(el, String(e.circle), false, 0.6, 2.2), Vector2(3.2, 3.2), glows)
			floor_c.rotation = Vector3(-PI * 0.5, 0, 0)
			floor_c.position = Vector3(0, 0.04, 0)
			parts.append(_particles(n, el, String(e.particle), 0.2, 80, 1.8, "rise"))
			parts.append(_particles(n, el, String(e.spark), 0.12, 60, 1.4, "rise"))
		"slash":
			# the element's arc (wind arc / crescent) sweeping, sparks along it
			var s := _glow_quad(n, ramp_material(el, String(e.motif), false, 0.0, 2.6), Vector2(3.6, 3.6), glows)
			s.name = "Arc"
			parts.append(_particles(n, el, String(e.spark), 0.12, 60, 0.5, "burst"))
	n.set_meta("glows", glows)
	n.set_meta("particles", parts)
	var snd := AudioStreamPlayer3D.new()
	snd.name = "Sound"
	snd.bus = "SFX"
	snd.unit_size = 6.0
	n.add_child(snd)
	n.visible = false
	root.add_child(n)
	return n


func _sound(n: Node3D, el: String, phase: String, db := -4.0) -> void:
	var path := sound(el, phase)
	if path == "":
		return
	var s := n.get_node("Sound") as AudioStreamPlayer3D
	s.stream = load(path)
	s.volume_db = db
	s.play()


func _emit(n: Node3D, on := true) -> void:
	for p in n.get_meta("particles", []):
		var gp := p as GPUParticles3D
		if on:
			gp.restart()
		gp.emitting = on


# ------------------------------------------------------------------ the six shapes
## A projectile riding on `follow` (a hazard's bolt node) until stop_projectile(); returns the FX node.
func projectile(follow: Node3D, el: String) -> Node3D:
	var n := _take("projectile", el)
	n.reparent(follow, false)
	n.position = Vector3.ZERO
	_emit(n)
	_sound(n, el, "release", -6.0)
	return n


func stop_projectile(n: Node3D, impact_at := Vector3.INF, big := false) -> void:
	if n == null or not is_instance_valid(n):
		return
	var el := String(n.get_meta("element"))
	var at: Vector3 = impact_at if impact_at != Vector3.INF else n.global_position
	_release(n)
	burst(at, el, 1.3 if big else 0.9, big)


## Impact: anticipation is the strike itself here - a star flash that snaps open, a shockwave ring, sparks;
## big hits add a brief hit stop and an impact frame (ImpactFrame).
func burst(at: Vector3, el: String, size := 1.0, big := false) -> void:
	var n := _take("burst", el)
	n.global_position = at
	n.scale = Vector3.ONE * size
	_emit(n)
	_sound(n, el, "impact", -3.0 if big else -6.0)
	var glows: Array = n.get_meta("glows")
	var ring: Node3D = n.get_node("Ring")
	var star: GeometryInstance3D = glows[0]
	star.scale = Vector3.ONE * 0.2
	ring.scale = Vector3.ONE * 0.3
	var tw := create_tween().set_parallel(true)
	tw.tween_property(star, "scale", Vector3.ONE * 1.2, 0.09).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector3.ONE * 3.2, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): _set_alpha(n, v), 1.0, 0.0, 0.5).set_delay(0.08)
	if big and ImpactFrame.instance:
		ImpactFrame.instance.hit(el)
	await get_tree().create_timer(0.95).timeout
	_release(n)


## A beam from `from` to `to` for `dur` seconds (anticipation 0.18 s of a thin flicker, then full width, then fade).
func beam(from: Vector3, to: Vector3, el: String, dur := 0.8) -> void:
	var n := _take("beam", el)
	n.global_position = from
	n.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.95 else Vector3.FORWARD)
	var len := from.distance_to(to)
	var strip: Node3D = n.get_node("Strip")
	strip.position = Vector3(0, 0, -len * 0.5)
	strip.scale = Vector3(1.0, 0.15, len)
	_sound(n, el, "release", -4.0)
	var tw := create_tween()
	tw.tween_property(strip, "scale:y", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(dur - 0.45, 0.05))
	tw.tween_property(strip, "scale:y", 0.0, 0.27).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_emit(n)
	burst(to, el, 0.8)
	await tw.finished
	_release(n)


## A shield before `c` (facing where she faces) for `dur` s: appears with a snap, holds, shatters into a burst.
func shield(c: Node3D, el: String, dur := 1.6) -> Node3D:
	var n := _take("shield", el)
	n.reparent(c, false)
	n.position = Vector3(0, 1.15, -0.75)
	n.rotation = Vector3.ZERO
	n.scale = Vector3.ONE * 0.1
	_sound(n, el, "activation", -5.0)
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(n) and bool(n.get_meta("busy", false)):
			var at := n.global_position
			_release(n)
			burst(at, el, 0.9))
	return n


## An aura round `c` (tier 1..10 scales it) until stop_aura().
func aura(c: Node3D, el: String, tier := 1) -> Node3D:
	var n := _take("aura", el)
	n.reparent(c, false)
	n.position = Vector3.ZERO
	n.rotation = Vector3.ZERO
	var k := clampf(0.7 + tier * 0.12, 0.7, 1.9)
	for g in n.get_meta("glows"):
		(g as GeometryInstance3D).set_instance_shader_parameter("boost", k)
	n.scale = Vector3.ONE * 0.6
	_emit(n)
	_sound(n, el, "charge", -8.0)
	create_tween().tween_property(n, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return n


func stop_aura(n: Node3D) -> void:
	if n == null or not is_instance_valid(n):
		return
	var tw := create_tween()
	tw.tween_method(func(v: float): _set_alpha(n, v), 1.0, 0.0, 0.5)
	_emit(n, false)
	await tw.finished
	_release(n)


## A slash: the element's arc sweeping across `xf` (origin = the blade's pivot, -Z = the swing direction).
func slash(xf: Transform3D, el: String, size := 1.0, big := false) -> void:
	var n := _take("slash", el)
	n.global_transform = xf
	n.scale = Vector3.ONE * size
	var arc: Node3D = n.get_node("Arc")
	arc.rotation = Vector3(0, 0, -0.9)
	_emit(n)
	_sound(n, el, "release", -5.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(arc, "rotation:z", 0.5, 0.14).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): _set_progress(n, v), 0.0, 1.0, 0.42).set_delay(0.1)
	if big and ImpactFrame.instance:
		ImpactFrame.instance.hit(el)
	await get_tree().create_timer(0.6).timeout
	_release(n)

## Anticipation (the beat that sells the strike): a glowing orb of her element grows at `hand` for `secs`, drawing
## its light in; then it is gone and the strike follows. Uses the projectile pool (same look, no new effect).
func charge(hand: Node3D, el: String, secs := 0.35) -> void:
	var n := _take("projectile", el)
	n.reparent(hand, false)
	n.position = Vector3.ZERO
	n.scale = Vector3.ONE * 0.15
	_emit(n)
	_sound(n, el, "charge", -6.0)
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 0.75, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	_release(n)
