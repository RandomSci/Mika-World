class_name Brazier
extends ReactiveElement
## A lit brazier that responds physically to magic. Drives the existing fire particles + light.
##   wind  : weak  (< 0.45) flame bends and flickers for a few seconds
##           medium        flame gutters low, recovers in ~8 s
##           strong (>= 0.75) flame is blown out: smoke puff, embers glow, relights itself in ~16 s
##   water : steam burst; intensity drops by ~0.6 x power; below 0.15 it goes out (relights in ~25 s)
##   fire  : lit -> flares bigger/brighter for ~9 s; out -> relit at once (Ember Control)
##   arcane: lit and power >= 0.5 -> flame turns arcane blue for ~20 s; weaker -> a brief shimmer
##   umbral: lit -> the flame sinks low and burns gold over shadow for ~14 s (Luna's lance)
## All changes are temporary and bounded (no spreading, no lasting damage).

var flame: GPUParticles3D
var light: OmniLight3D
var base_energy := 1.6
var lit := true
var intensity := 1.0           # 1 = normal fire
var arcane := false
var _tint := "arcane"           # which magic is colouring the flame while `arcane` is set
var _bend := Vector3.ZERO      # current wind push on the flame
var _bend_target := Vector3.ZERO
var _pm: ParticleProcessMaterial
var _base_ramp: Texture2D
var _embers: GPUParticles3D
var _t := 0.0


func setup(p_id: String, p_label: String, p_flame: GPUParticles3D, p_light: OmniLight3D) -> void:
	id = p_id
	kind = "brazier"
	label = p_label
	flame = p_flame
	light = p_light
	base_energy = light.light_energy
	aim_offset = Vector3(0, 0.25, 0)
	aim_radius = 0.6
	supports = ["wind", "water", "fire", "arcane", "mist", "umbral"]
	# own copy of the process material so each brazier bends independently
	_pm = (flame.process_material as ParticleProcessMaterial).duplicate()
	flame.process_material = _pm
	_base_ramp = _pm.color_ramp
	_embers = FX.particles(14, 2.2, FX.process("embers", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.18
		pm.direction = Vector3.UP
		pm.spread = 20.0
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.2
		pm.gravity = Vector3(0, 0.1, 0)
		pm.scale_min = 0.4
		pm.scale_max = 0.8
		pm.color_ramp = FX.ramp([Color(1, 0.35, 0.05, 0), Color(1, 0.4, 0.08, 0.9), Color(0.8, 0.2, 0.02, 0)], [0.0, 0.3, 1.0])), FX.mote_mesh(0.035))
	add_child(_embers)
	_embers.position = Vector3(0, 0.05, 0)
	_embers.emitting = false
	_sync_state()


func _sync_state() -> void:
	state = {"lit": lit, "intensity": snappedf(intensity, 0.01), "flame_colour": ({"arcane": "arcane blue", "gilded": "gilded shadow"}.get(_tint, "arcane blue")) if arcane else "natural",
		"recovering": pending_recoveries()}


func _react_wind(power: float, _point: Vector3) -> Dictionary:
	if not lit:
		return {"effect": "embers_stirred", "detail": "the brazier is already out; the gust only stirs the embers"}
	var dir := (global_position - get_viewport().get_camera_3d().global_position) if get_viewport().get_camera_3d() else Vector3.RIGHT
	dir = MagicSystem.last_cast_dir if MagicSystem.last_cast_dir != Vector3.ZERO else dir
	dir.y = 0
	_bend_target = dir.normalized() * (0.8 + power * 2.2)
	schedule("bend", 2.5 + power * 2.0)
	if power >= 0.75:
		lit = false
		intensity = 0.0
		cancel("relight")
		schedule("relight", 16.0)
		FX.burst(self, global_position + Vector3(0, 0.3, 0), 18, 2.5, FX.pm_puff("smoke"), FX.puff_mesh(0.45))
		_sync_state()
		return {"effect": "extinguished", "detail": "the gust blew the flame out; smoke rises and the embers glow (relights in ~16 s)", "relight_in_s": 16.0}
	if power >= 0.45:
		intensity = 0.35
		schedule("restore", 8.0)
		_sync_state()
		return {"effect": "guttered", "detail": "the flame bent hard and guttered low, but held (recovers in ~8 s)"}
	_sync_state()
	return {"effect": "flicker", "detail": "the flame leaned away and flickered, then steadied (the gust was too weak to do more)"}


func _react_water(power: float, _point: Vector3) -> Dictionary:
	FX.burst(self, global_position + Vector3(0, 0.35, 0), int(28 + power * 24), 2.4, FX.pm_puff("steam"), FX.puff_mesh(0.85))
	if not lit:
		return {"effect": "steam", "detail": "a hiss of steam from the hot coals; the brazier stays out"}
	intensity = maxf(0.0, intensity - 0.6 * power)
	if intensity < 0.15:
		lit = false
		intensity = 0.0
		cancel("restore")
		schedule("relight", 25.0)
		_sync_state()
		return {"effect": "doused", "detail": "steam burst up and the flame died (relights in ~25 s)", "relight_in_s": 25.0}
	schedule("restore", 10.0)
	_sync_state()
	return {"effect": "steam", "detail": "steam burst up and the flame shrank to %d%%" % int(intensity * 100)}


func _react_mist(power: float, point: Vector3) -> Dictionary:
	if not lit:
		return {"effect": "veiled", "detail": "mist settles over the cold brazier"}
	var r := _react_water(power * 0.6, point)
	r["effect"] = "misted_" + String(r.effect)
	r["detail"] = "mist rolled over the flame: " + String(r.detail)
	return r


func _react_fire(power: float, _point: Vector3) -> Dictionary:
	if not lit:
		lit = true
		intensity = 0.8 + 0.3 * power
		cancel("relight")
		schedule("restore", 6.0)
		_sync_state()
		return {"effect": "relit", "detail": "the coals caught and the flame came back"}
	intensity = minf(1.0 + 0.7 * power, 1.7)
	schedule("restore", 9.0)
	_sync_state()
	return {"effect": "flare", "detail": "the flame flared up to %d%% for a few seconds" % int(intensity * 100)}


func _react_arcane(power: float, _point: Vector3) -> Dictionary:
	if not lit:
		return {"effect": "none", "detail": "arcane light washes over cold coals; nothing to change"}
	if power < 0.5:
		FX.burst(self, global_position + Vector3(0, 0.4, 0), 12, 0.8, FX.pm_motes("arcane", "burst"), FX.mote_mesh(0.05))
		return {"effect": "shimmer", "detail": "the flame shimmered blue for an instant (not enough power to hold it)"}
	arcane = true
	_tint = "arcane"
	var pal := FX.palette("arcane")
	_pm.color_ramp = FX.ramp([Color(0.6, 0.8, 1.0, 1.0), Color(pal[1], 0.0)])
	light.light_color = Color(0.5, 0.65, 1.0)
	schedule("arcane", 20.0)
	_sync_state()
	return {"effect": "arcane_flame", "detail": "the flame turned arcane blue (fades back in ~20 s)"}


func _react_umbral(power: float, _point: Vector3) -> Dictionary:
	if not lit:
		return {"effect": "none", "detail": "shadow magic sinks into the cold coals"}
	arcane = true
	_tint = "gilded"
	_pm.color_ramp = FX.ramp([Color(1.0, 0.82, 0.38, 1.0), Color(0.75, 0.45, 0.2, 0.8), Color(0.3, 0.08, 0.5, 0.0)], [0.0, 0.5, 1.0])
	light.light_color = Color(0.95, 0.66, 0.28)
	intensity = maxf(0.35, intensity - 0.45 * power)
	FX.burst(self, global_position + Vector3(0, 0.45, 0), 18, 0.9, FX.pm_motes("umbral", "burst"), FX.mote_mesh(0.05))
	schedule("arcane", 14.0)
	schedule("restore", 9.0)
	_sync_state()
	return {"effect": "gilded", "detail": "the flame sank low and burned gold over shadow (recovers in ~14 s)"}


func _recover(key: String) -> void:
	match key:
		"bend":
			_bend_target = Vector3.ZERO
		"restore":
			intensity = 1.0
		"relight":
			lit = true
			intensity = 0.6
			schedule("restore", 4.0)
		"arcane":
			arcane = false
			_pm.color_ramp = _base_ramp
			light.light_color = Color(1.0, 0.55, 0.26)
	_sync_state()


func _process(delta: float) -> void:
	super._process(delta)
	_t += delta
	_bend = _bend.lerp(_bend_target, 1.0 - exp(-4.0 * delta))
	var gust := sin(_t * 9.0) * 0.35 * _bend.length()
	_pm.gravity = Vector3(_bend.x, 0.6, _bend.z) + _bend.normalized() * gust if _bend.length() > 0.01 else Vector3(0, 0.6, 0)
	var shown := intensity if lit else 0.0
	flame.amount_ratio = clampf(shown, 0.0, 1.0)
	flame.emitting = shown > 0.02
	flame.scale = Vector3.ONE * (0.75 + 0.35 * shown)
	_embers.emitting = not lit
	var night_boost := 1.7 if WorldState.night else 1.0
	var flick := 0.86 + 0.1 * sin(_t * 11.0 + position.x) + 0.06 * sin(_t * 23.0)
	if _bend.length() > 0.2:
		flick *= 0.8 + 0.25 * sin(_t * 31.0)
	light.light_energy = base_energy * night_boost * flick * (shown + (0.12 if not lit else 0.0))
	if not lit:
		light.light_color = Color(1.0, 0.3, 0.08)
	elif not arcane:
		light.light_color = Color(1.0, 0.55, 0.26)
	if Engine.get_process_frames() % 30 == 0:
		_sync_state()
