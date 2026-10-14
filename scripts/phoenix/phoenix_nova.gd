class_name PhoenixNova
extends Node3D
## Oriel's POWER ATTACK, the SOLAR NOVA (the cinematic pass, 2026-10-14 - the developer: "the attack looks so simple
## and doesn't scream anything special"). Built on real simulated fire (FireFX: Mantaflow flipbooks):
##   charge   - a sun is born before her breast: a white-hot heart inside a churning ball of real fire, fire drawn
##              in from the air in spirals, heat haze bending the world round it, a light swelling until it lights
##              the clearing (no camera-facing glare quads: they cut through her wings);
##   release  - her downstroke drives it forward: it flies at its mark trailing a river of rolling fire and smoke;
##   impact   - FireFX.explosion(): the flash that lights the forest, a fireball rolling into smoke, fire flung
##              out, a shock ring and a dust skirt, debris thrown and landing, a scorch whose cracks glow and cool,
##              fires left burning, a gust that bends the trees and tears their leaves, the camera shaken - and
##              whatever stands there answers with its own react("fire", ...) (judged, not shown).

signal resolved(outcome: Dictionary)

const SPEED := 26.0
static var main_ref: Node

var target: Node3D
var target_point := Vector3.ZERO
var power := 1.0
var phase := "idle"               # charge, fly, done
var charge_k := 0.0
var _anchor: Callable
var _t := 0.0
var _heart: MeshInstance3D
var _heart_mat: ShaderMaterial
var _churn: GPUParticles3D
var _gather: GPUParticles3D
var _haze: MeshInstance3D
var _light: OmniLight3D
var _trail: Array = []
var _sparks: GPUParticles3D


static func _sprite_mesh(size: Vector2, cell: int, strength: float) -> QuadMesh:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/phoenix/fx_sprite.gdshader")
	m.set_shader_parameter("atlas", load(PhoenixTrueRig.ATLAS))
	m.set_shader_parameter("noise_tex", FX.noise())
	m.set_shader_parameter("cell", cell)
	m.set_shader_parameter("strength", strength)
	var q := QuadMesh.new()
	q.size = size
	q.material = m
	return q


static func _core_mat(inner: Color, outer: Color, pw: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/phoenix/fire_core.gdshader")
	m.set_shader_parameter("noise_tex", FX.noise())
	m.set_shader_parameter("inner", inner)
	m.set_shader_parameter("outer", outer)
	m.set_shader_parameter("power", pw)
	m.set_shader_parameter("speed", 2.2)
	return m


static func _sphere(radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 32
	sm.rings = 18
	mi.mesh = sm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build() -> void:
	_heart_mat = _core_mat(Color(1.0, 0.97, 0.88), Color(1.0, 0.62, 0.22), 0.0)
	_heart = _sphere(0.42, _heart_mat)
	add_child(_heart)
	_light = FX.light(Color(1.0, 0.58, 0.22), 0.0, 16.0)
	_light.shadow_enabled = true
	add_child(_light)
	if FireFX.available():
		# the ball of fire round the heart: simulated fire puffs born and burning round it all the time
		_churn = FireFX.particles("burst", 26, 0.75, 0.32, FX.process("nova:churn", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.35
			pm.direction = Vector3.UP
			pm.spread = 180.0
			pm.initial_velocity_min = 0.2
			pm.initial_velocity_max = 0.8
			pm.orbit_velocity_min = 0.3
			pm.orbit_velocity_max = 0.6
			pm.gravity = Vector3(0, 0.8, 0)
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.scale_min = 0.6
			pm.scale_max = 1.1), {"fire_gain": 1.5, "fire_tint": Color(1.0, 0.7, 0.42), "smoke_alpha": 0.35})
		_churn.local_coords = true
		_churn.emitting = false
		add_child(_churn)
		# fire drawn in from the air in spirals
		_gather = FireFX.particles("burst", 34, 0.9, 0.2, FX.process("nova:gather", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			pm.emission_sphere_radius = 4.0
			pm.direction = Vector3.UP
			pm.spread = 180.0
			pm.initial_velocity_min = 0.0
			pm.initial_velocity_max = 0.3
			pm.radial_accel_min = -20.0
			pm.radial_accel_max = -14.0
			pm.tangential_accel_min = 5.0
			pm.tangential_accel_max = 9.0
			pm.gravity = Vector3.ZERO
			pm.damping_min = 0.6
			pm.damping_max = 1.0
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.scale_min = 0.5
			pm.scale_max = 1.0), {"fire_gain": 1.4, "fire_tint": Color(1.0, 0.7, 0.42), "smoke_alpha": 0.2})
		_gather.local_coords = true
		_gather.emitting = false
		add_child(_gather)
		var hm := ShaderMaterial.new()
		hm.shader = load(FireFX.HAZE)
		hm.set_shader_parameter("noise_tex", FX.noise())
		var hq := QuadMesh.new()
		hq.size = Vector2.ONE
		hq.material = hm
		_haze = MeshInstance3D.new()
		_haze.mesh = hq
		_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_haze.scale = Vector3.ONE * 4.0
		_haze.set_instance_shader_parameter("strength", 0.0)
		add_child(_haze)
	_sparks = FX.particles(40, 0.8, FX.process("nova:sparks", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.5
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 1.0
		pm.initial_velocity_max = 4.0
		pm.gravity = Vector3(0, -3.0, 0)
		pm.scale_min = 0.4
		pm.scale_max = 1.0
		pm.color_ramp = FX.ramp([Color(1, 0.95, 0.75, 1), Color(1, 0.55, 0.15, 0.9), Color(0.8, 0.15, 0.02, 0)], [0.0, 0.4, 1.0])), FX.mote_mesh(0.06, true))
	_sparks.emitting = false
	_sparks.visibility_aabb = AABB(Vector3(-20, -8, -20), Vector3(40, 16, 40))
	add_child(_sparks)


## Begin gathering the nova at anchor() (a world point, re-read every frame while charging).
func charge(anchor: Callable) -> void:
	_anchor = anchor
	_build()
	global_position = anchor.call()
	phase = "charge"
	_t = 0.0
	if _gather:
		_gather.emitting = true
	if _churn:
		_churn.emitting = true


## Release: fly at the target (a node or a point).
func launch(tgt, p_power := 1.0) -> void:
	power = p_power
	if tgt is Node3D:
		target = tgt
		target_point = PhoenixFlare._aim(tgt)
	else:
		target_point = tgt
	phase = "fly"
	_t = 0.0
	if _gather:
		_gather.emitting = false
	_sparks.emitting = true
	_trail = FireFX.trail(get_parent(), 1.3)
	for p in _trail:
		(p as GPUParticles3D).global_position = global_position
		(p as GPUParticles3D).emitting = true
	# the blast of the throw
	if FireFX.available():
		FireFX.card(get_parent(), "burst", global_position, 0.9, 0.7, {"fire_gain": 1.5, "fire_tint": Color(1.0, 0.7, 0.42)})
	FireFX.haze(get_parent(), global_position, 9.0, 1.2, 0.6, true)
	if main_ref and main_ref.get("audio"):
		main_ref.audio.play_cine("phoenix_nova_release", global_position, 0.0, "phoenix nova release")


func _process(delta: float) -> void:
	_t += delta
	var mls := float(RenderProfile.get_setting("magic_light_scale"))
	match phase:
		"charge":
			if _anchor.is_valid():
				global_position = _anchor.call()
			charge_k = clampf(_t / 1.6, 0.0, 1.0)
			var r := 0.15 + 0.85 * charge_k * charge_k + 0.04 * sin(_t * 23.0) * charge_k
			_heart.scale = Vector3.ONE * r
			_heart_mat.set_shader_parameter("power", 0.4 + 1.2 * charge_k)
			if _churn:
				_churn.scale = Vector3.ONE * (0.4 + 1.3 * charge_k)
				_churn.amount_ratio = 0.3 + 0.7 * charge_k
			if _haze:
				_haze.scale = Vector3.ONE * (2.0 + 5.0 * charge_k)
				_haze.set_instance_shader_parameter("strength", 1.2 * charge_k)
			_light.light_energy = (2.0 + 12.0 * charge_k * charge_k) * mls
			_light.omni_range = 10.0 + 12.0 * charge_k
		"fly":
			if target and is_instance_valid(target):
				target_point = PhoenixFlare._aim(target)
			var to := target_point - global_position
			var d := to.length()
			if d < 0.7 or _t > 5.0:
				_arrive()
				return
			global_position += to.normalized() * minf(SPEED * delta, d)
			for p in _trail:
				if is_instance_valid(p):
					(p as GPUParticles3D).global_position = global_position
			_heart.scale = Vector3.ONE * (0.95 + 0.06 * sin(_t * 30.0))
			if _churn:
				_churn.scale = Vector3.ONE * 1.6
			_light.light_energy = 9.0 * mls


func _arrive() -> void:
	phase = "done"
	var at := global_position
	var outcome := {"ok": true, "effect": "burst", "detail": "the solar nova burst in the air", "target": ""}
	if target and is_instance_valid(target) and target.has_method("react"):
		var r: Dictionary = target.react("fire", power * 1.35, at, "phoenix_nova")
		outcome = {"ok": true, "effect": String(r.get("effect", "")), "detail": String(r.get("detail", "")), "target": String(target.get("id") if target.get("id") != null else target.name), "reaction": r}
	explode(get_parent(), at, power)
	MagicEvents.magic_event.emit(at, "fire", power, String(outcome.effect), String(outcome.target))
	for p in _trail:
		if is_instance_valid(p):
			(p as GPUParticles3D).emitting = false
			FireFX.free_after(p, 3.0)
	_sparks.emitting = false
	_heart.visible = false
	if _churn:
		_churn.visible = false
	if _haze:
		_haze.visible = false
	resolved.emit(outcome)
	var tw := create_tween()
	tw.tween_property(_light, "light_energy", 0.0, 0.25)
	tw.tween_interval(1.0)
	tw.tween_callback(queue_free)


## The detonation (usable on its own): the simulated explosion, or the procedural one if the flipbooks are missing.
static func explode(host: Node, at: Vector3, p_power := 1.0) -> void:
	if host == null:
		return
	var s := clampf(0.9 + 0.4 * p_power, 0.9, 1.5)
	if FireFX.available():
		FireFX.explosion(host, at, s)
	else:
		explode_simple(host, at, p_power)
	if main_ref and main_ref.get("audio"):
		main_ref.audio.play_cine("phoenix_nova_impact", at, 2.0, "phoenix nova impact")


## The procedural detonation (used only if the simulated flipbooks are missing).
static func explode_simple(host: Node, at: Vector3, p_power := 1.0) -> void:
	if host == null:
		return
	var big := clampf(0.8 + 0.4 * p_power, 0.8, 1.6)
	var mls := float(RenderProfile.get_setting("magic_light_scale"))
	var flash := FX.light(Color(1.0, 0.7, 0.35), 16.0 * big * mls, 18.0)
	host.add_child(flash)
	flash.global_position = at + Vector3(0, 0.6, 0)
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ft.tween_callback(flash.queue_free)
	# the fireball swelling and burning out
	var fm := _core_mat(Color(1.0, 0.72, 0.32), Color(0.85, 0.16, 0.03), 1.25)
	fm.set_shader_parameter("speed", 3.2)
	var ball := _sphere(1.0, fm)
	host.add_child(ball)
	ball.global_position = at
	ball.scale = Vector3.ONE * 0.3
	var bt := ball.create_tween().set_parallel(true)
	bt.tween_property(ball, "scale", Vector3.ONE * 2.5 * big, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	bt.tween_method(func(v: float): fm.set_shader_parameter("power", v), 1.25, 0.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	bt.chain().tween_callback(ball.queue_free)
	# ground: a ring of shock and a scorch that fades
	var gy := at.y - 0.5
	if host.has_method("ground_at"):
		gy = float(host.ground_at(at.x, at.z))
	if at.y - gy < 2.5:
		ImpactFX.ground_ring(host, Vector3(at.x, gy + 0.05, at.z), Color(1.0, 0.5, 0.15), 4.2 * big)
		_scorch(host, Vector3(at.x, gy, at.z), 2.6 * big)
	ImpactFX.shockwave(host, at, Color(1.0, 0.62, 0.25), 8.0 * big)
	# flames thrown outward, embers raining, smoke rising
	FX.burst(host, at, int(46 * big), 1.0, FX.process("nova_burst_flames", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.5
		pm.spread = 180.0
		pm.initial_velocity_min = 4.0
		pm.initial_velocity_max = 9.0
		pm.gravity = Vector3(0, 2.5, 0)
		pm.damping_min = 4.0
		pm.damping_max = 7.0
		pm.scale_min = 1.4
		pm.scale_max = 3.0
		pm.scale_curve = PhoenixTrueRig._curve_tex([0.6, 1.0, 0.2])
		pm.color_ramp = FX.ramp([Color(1, 0.95, 0.8, 1), Color(1, 0.6, 0.15, 1), Color(0.85, 0.15, 0.03, 0.7), Color(0.1, 0.05, 0.04, 0)], [0.0, 0.2, 0.6, 1.0])), _sprite_mesh(Vector2(0.7, 1.1), 0, 2.0))
	FX.burst(host, at, int(110 * big), 1.8, FX.process("nova_ember_rain", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.6
		pm.spread = 180.0
		pm.direction = Vector3.UP
		pm.initial_velocity_min = 4.0
		pm.initial_velocity_max = 13.0
		pm.gravity = Vector3(0, -9.0, 0)
		pm.damping_min = 0.4
		pm.damping_max = 1.2
		pm.scale_min = 0.5
		pm.scale_max = 1.3
		pm.color_ramp = FX.ramp([Color(1, 0.95, 0.75, 1), Color(1, 0.55, 0.12, 1), Color(0.6, 0.1, 0.02, 0)], [0.0, 0.5, 1.0])), _sprite_mesh(Vector2(0.11, 0.11), 1, 3.0))
	FX.burst(host, at + Vector3(0, 0.4, 0), int(10 * big), 3.0, FX.pm_puff("dust"), FX.puff_mesh(1.6))
	ImpactFX.shake(host, 0.09 * big, 0.55)


static func _scorch(host: Node, at: Vector3, radius: float) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.02, 0.015, 0.85))
	g.set_color(1, Color(0.05, 0.03, 0.02, 0.0))
	g.add_point(0.55, Color(0.08, 0.04, 0.02, 0.6))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(radius * 2.0, 2.0, radius * 2.0)
	d.modulate = Color(1, 1, 1, 1)
	host.add_child(d)
	d.global_position = at
	var tw := d.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(d, "modulate:a", 0.0, 4.0)
	tw.tween_callback(d.queue_free)
