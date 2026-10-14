class_name Campfire
extends Node3D
## A real campfire in a ring of stones (V3 continuation, camping): it starts as nothing, catches from sparks,
## grows, burns down unless fed, flares when a branch is added, and dies to smoke when doused. Flames are the
## simulated flipbook flame (FireFX), with a flickering warm light that casts shadows, smoke, embers and the
## crackling loop. `heat` (0..1) is what other systems read (creatures that fear fire, warmth).

var heat := 0.0                     # 0 cold .. 1 roaring
var fuel := 0.0                     # minutes of burning left (world minutes)
var lit := false
var _flames: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _smoke: GPUParticles3D
var _embers: GPUParticles3D
var _sound: AudioStreamPlayer3D
var _t := 0.0
var _target := 0.0


func _ready() -> void:
	add_to_group("campfire")
	if FireFX.available():
		for k in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = FireFX.quad("flame", 0.55 if k == 0 else 0.42, {"particles": false, "upright": true, "loop_fps": 30.0, "fire_gain": 1.15,
				"fire_tint": Color(1.0, 0.66, 0.38), "soft": 0.35})
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(randf_range(-0.08, 0.08), -0.02, randf_range(-0.08, 0.08))
			mi.set_instance_shader_parameter("phase", randf())
			mi.set_instance_shader_parameter("fade", 0.0)
			mi.visible = false
			add_child(mi)
			_flames.append(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.56, 0.24)
	_light.omni_range = 9.0
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = true
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.55, 0)
	add_child(_light)
	_smoke = FireFX.particles("smoke", 5, 4.0, 0.3, FireFX._pm("camp_smoke", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.15
		pm.direction = Vector3.UP
		pm.spread = 10.0
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 0.9
		pm.gravity = Vector3(0.12, 0.25, 0.05)
		pm.scale_min = 0.7
		pm.scale_max = 1.3), {"smoke_tint": Color(0.42, 0.4, 0.38), "smoke_alpha": 0.35}) if FireFX.available() else null
	if _smoke:
		_smoke.position = Vector3(0, 0.9, 0)
		_smoke.emitting = false
		add_child(_smoke)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.3, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.color_ramp = FX.ramp([Color(1, 0.85, 0.5, 1), Color(1, 0.45, 0.1, 1), Color(0.6, 0.12, 0.0, 0)], [0.0, 0.5, 1.0])
	_embers = FX.particles(18, 2.2, pm, FX.mote_mesh(0.025, true))
	_embers.position = Vector3(0, 0.25, 0)
	_embers.emitting = false
	add_child(_embers)


## Sparks struck over the tinder: a small burst; the third or so catches.
func strike_spark() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3.DOWN
	pm.spread = 70.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, -6.0, 0)
	pm.color_ramp = FX.ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.1, 1), Color(0.5, 0.1, 0.0, 0)], [0.0, 0.4, 1.0])
	var p := FX.particles(26, 0.6, pm, FX.mote_mesh(0.018, true))
	p.one_shot = true
	p.explosiveness = 0.95
	p.position = Vector3(0, 0.22, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


## It catches: a curl of smoke first, then flames growing over `seconds`.
func ignite(seconds := 4.0, minutes_fuel := 90.0) -> void:
	lit = true
	fuel = minutes_fuel
	if _smoke:
		_smoke.emitting = true
	_target = 0.85
	var tw := create_tween()
	tw.tween_property(self, "heat", 0.85, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if ResourceLoader.exists("res://assets/audio/synth/phoenix_fire_burn_loop.ogg"):
		_sound = AudioStreamPlayer3D.new()
		var st := (load("res://assets/audio/synth/phoenix_fire_burn_loop.ogg") as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		st.loop = true
		_sound.stream = st
		_sound.bus = "SFX"
		_sound.unit_size = 4.0
		_sound.volume_db = -60.0
		add_child(_sound)
		_sound.play()


## A branch laid on: it flares and burns longer.
func feed(minutes := 60.0) -> void:
	fuel += minutes
	_target = 1.0
	heat = minf(heat + 0.25, 1.0)


## Water poured over it: hiss, a burst of steam-smoke, then nothing.
func douse() -> void:
	lit = false
	fuel = 0.0
	_target = 0.0
	if _smoke:
		_smoke.amount = 12
		_smoke.emitting = true
	var tw := create_tween()
	tw.tween_property(self, "heat", 0.0, 1.6)
	tw.tween_interval(4.0)
	tw.tween_callback(func(): if _smoke: _smoke.emitting = false)


func _process(delta: float) -> void:
	_t += delta
	if lit:
		# fuel burns in world minutes (the clock may run fast at night)
		fuel -= delta * WorldState.clock_rate * WorldState.clock_boost
		if fuel <= 0.0:
			_target = 0.18                      # embers: it dies down unless someone feeds it
		elif _target > 0.85:
			_target = move_toward(_target, 0.85, delta * 0.05)
		heat = move_toward(heat, _target, delta * 0.08) if absf(heat - _target) > 0.02 else heat
	var h := heat
	for i in _flames.size():
		var f := _flames[i]
		f.visible = h > 0.02
		f.set_instance_shader_parameter("fade", clampf(h * 1.2, 0.0, 1.0))
		var s := (0.35 + 0.75 * h) * (1.0 if i == 0 else 0.8)
		f.scale = Vector3(s, s * (0.9 + 0.12 * sin(_t * 7.0 + i)), s)
	var mls := float(RenderProfile.get_setting("magic_light_scale")) if RenderProfile.has_method("get_setting") else 1.0
	_light.light_energy = h * (2.4 + 0.5 * sin(_t * 23.0) + 0.35 * sin(_t * 37.0 + 1.3) + 0.25 * sin(_t * 5.0)) * mls
	_light.omni_range = 5.0 + 6.0 * h
	_embers.emitting = h > 0.25
	if _sound:
		_sound.volume_db = -60.0 if h < 0.02 else -8.0 + linear_to_db(maxf(h, 0.001)) * 0.6
