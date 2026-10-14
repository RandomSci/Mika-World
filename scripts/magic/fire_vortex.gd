class_name FireVortex
extends Node3D
## A FIRE TORNADO (the Phoenix's transformation, the cinematic pass): the 'vortex' flipbook - a simulated fire
## column spun by a vortex field - stood on upright cards round one axis, each at its own phase, speed and size, so
## from any side it reads as one roaring spiral; tongues of fire climb it (burst flipbook particles orbiting upward),
## heat shimmers over it and a light burns inside. `strength` 0..1: the caller grows it, roars it, collapses it.

var strength := 0.0
var _cards: Array[MeshInstance3D] = []
var _climb: GPUParticles3D
var _light: OmniLight3D
var _haze: MeshInstance3D
var _s := 1.0
var _spin := 0.0


func build(s := 1.0) -> void:
	_s = s
	if FireFX.available():
		var sizes := [1.15, 0.95, 1.05, 0.9, 1.1, 1.0, 0.92]
		var rates := [30.0, 34.0, 27.0, 31.0, 29.0, 33.0, 28.0]
		for i in 7:
			var mi := MeshInstance3D.new()
			mi.mesh = FireFX.quad("vortex", s * float(sizes[i]), {"particles": false, "upright": true, "loop_fps": float(rates[i]), "fire_gain": 0.85, "fire_tint": Color(1.0, 0.7, 0.42), "smoke_alpha": 0.4, "soft": 0.5})
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# one at the heart, six wound round it (they orbit: the wall of fire turns)
			mi.position = Vector3.ZERO if i == 0 else Vector3(cos(i * TAU / 6.0), 0.0, sin(i * TAU / 6.0)) * 1.75 * s
			mi.set_meta("ang", i * TAU / 6.0)
			mi.extra_cull_margin = 6.0 * s
			mi.set_instance_shader_parameter("phase", i * 0.27)
			mi.set_instance_shader_parameter("fade", 0.0)
			add_child(mi)
			_cards.append(mi)
		_climb = FireFX.particles("burst", 70, 1.3, 0.3 * s, FX.process("firefx:vortex_climb", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = 1.5
			pm.emission_ring_inner_radius = 0.9
			pm.emission_ring_height = 0.4
			pm.direction = Vector3.UP
			pm.spread = 10.0
			pm.initial_velocity_min = 4.0
			pm.initial_velocity_max = 7.0
			pm.orbit_velocity_min = 0.6
			pm.orbit_velocity_max = 0.9
			pm.radial_accel_min = -2.0
			pm.radial_accel_max = -1.0
			pm.gravity = Vector3(0, 1.0, 0)
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.scale_min = 0.6
			pm.scale_max = 1.2), {"fire_gain": 1.3, "fire_tint": Color(1.0, 0.7, 0.42)})
		_climb.local_coords = true
		_climb.emitting = false
		add_child(_climb)
		var hm := ShaderMaterial.new()
		hm.shader = load(FireFX.HAZE)
		hm.set_shader_parameter("noise_tex", FX.noise())
		var hq := QuadMesh.new()
		hq.size = Vector2.ONE
		hq.material = hm
		_haze = MeshInstance3D.new()
		_haze.mesh = hq
		_haze.position = Vector3(0, 3.2 * s, 0)
		_haze.scale = Vector3.ONE * 7.0 * s
		_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_haze.set_instance_shader_parameter("strength", 0.0)
		add_child(_haze)
	_light = FX.light(Color(1.0, 0.55, 0.2), 0.0, 16.0 * s)
	_light.position = Vector3(0, 2.6 * s, 0)
	add_child(_light)
	set_strength(0.0)


func set_strength(k: float) -> void:
	strength = clampf(k, 0.0, 1.5)
	var kk := minf(strength, 1.0)
	for i in _cards.size():
		var c := _cards[i]
		c.set_instance_shader_parameter("fade", kk)
		c.scale = Vector3((1.25 if i == 0 else 0.9) * (0.55 + 0.45 * kk), 0.35 + 0.75 * kk, 1.0) * (1.0 + 0.15 * maxf(strength - 1.0, 0.0))
	if _climb:
		_climb.emitting = kk > 0.2
		_climb.amount_ratio = kk
	if _haze:
		_haze.set_instance_shader_parameter("strength", 0.9 * kk)
	if _light:
		_light.light_energy = (4.5 * kk + 3.0 * maxf(strength - 1.0, 0.0)) * float(RenderProfile.get_setting("magic_light_scale"))


func _process(delta: float) -> void:
	# the ring of columns orbits (and draws in a little as it roars)
	_spin += delta * (0.9 + 1.4 * strength)
	for i in range(1, _cards.size()):
		var a := float(_cards[i].get_meta("ang")) + _spin
		_cards[i].position = Vector3(cos(a), 0.0, sin(a)) * (1.95 - 0.35 * minf(strength, 1.0)) * _s
	if _light and strength > 0.01:
		var t := Time.get_ticks_msec() / 1000.0
		_light.light_energy *= 0.92 + 0.08 * sin(t * 21.0) * sin(t * 13.0 + 0.7) + 0.08


## Die down over `seconds`, then free.
func collapse(seconds := 0.6) -> void:
	var tw := create_tween()
	tw.tween_method(set_strength, strength, 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.4)
	tw.tween_callback(queue_free)
