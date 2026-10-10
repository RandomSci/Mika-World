class_name PondReactive
extends ReactiveElement
## The garden pond's surface. Ripples are real shader state centred where the spell landed.
##   water : ripple rings; power >= 0.7 also lifts a short column of water that falls back with a splash
##   wind  : the surface ruffles (two wide, shallow ripples) and a fine spray lifts
##   fire  : steam where it touches; the water itself is unchanged
##   arcane: a ring of light spreads across the water
## Fish and birds listen to MagicEvents and react to these disturbances themselves.

var water: MeshInstance3D
var mat: ShaderMaterial
var radius := 3.2
var _ages := [-1.0, -1.0]
var _strength := [0.0, 0.0]
var _next := 0
var _spout: MeshInstance3D
var _spout_t := -1.0
var _spout_h := 1.0
var _calm_timer := 0.0


func setup(p_id: String, p_label: String, p_water: MeshInstance3D, p_radius: float) -> void:
	id = p_id
	kind = "water"
	label = p_label
	water = p_water
	radius = p_radius
	mat = (water.material_override as ShaderMaterial).duplicate()
	water.material_override = mat
	aim_offset = Vector3.ZERO
	aim_radius = radius
	supports = ["water", "wind", "fire", "arcane"]
	_spout = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.28
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 6
	_spout.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.55, 0.8, 0.95, 0.55)
	sm.roughness = 0.05
	sm.metallic_specular = 0.9
	sm.rim_enabled = true
	sm.rim = 0.6
	sm.emission_enabled = true
	sm.emission = Color(0.25, 0.45, 0.6)
	sm.emission_energy_multiplier = 0.4
	_spout.material_override = sm
	_spout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spout.visible = false
	add_child(_spout)
	state = {"surface": "still"}


func _ripple(point: Vector3, strength: float, glow := 0.0, col := Color(0.6, 0.85, 1.0)) -> void:
	var i := _next
	_next = (_next + 1) % 2
	_ages[i] = 0.0
	_strength[i] = strength
	mat.set_shader_parameter("ripple_a" if i == 0 else "ripple_b", Vector4(point.x, point.z, 0.0, strength))
	mat.set_shader_parameter("ripple_color", col)
	mat.set_shader_parameter("ripple_glow", glow)
	_calm_timer = 6.0
	state = {"surface": "rippling"}


func _on_surface(point: Vector3) -> Vector3:
	var local := Vector2(point.x - global_position.x, point.z - global_position.z)
	if local.length() > radius - 0.3:
		local = local.normalized() * (radius - 0.3)
	return Vector3(global_position.x + local.x, global_position.y, global_position.z + local.y)


func _react_water(power: float, point: Vector3) -> Dictionary:
	var p := _on_surface(point)
	_ripple(p, 0.6 + 0.6 * power)
	FX.burst(self, p, int(20 + 30 * power), 1.2, FX.pm_motes("water", "splash"), FX.mote_mesh(0.05))
	if power >= 0.7:
		_spout.global_position = p
		_spout_h = 0.6 + 1.2 * power
		_spout_t = 0.0
		_spout.visible = true
		return {"effect": "surge", "detail": "the water rose in a column about %.1f m high, then fell back with a splash" % _spout_h, "height_m": snappedf(_spout_h, 0.1)}
	return {"effect": "ripple", "detail": "rings spread across the pond from where the spell touched it"}


func _react_wind(power: float, point: Vector3) -> Dictionary:
	var p := _on_surface(point)
	_ripple(p, 0.35 + 0.4 * power)
	_ripple(p + MagicSystem.last_cast_dir * 0.8, 0.25 + 0.3 * power)
	FX.burst(self, p, int(10 + 20 * power), 1.0, FX.pm_motes("water", "splash"), FX.mote_mesh(0.03))
	return {"effect": "ruffled", "detail": "the surface ruffled under the gust and a fine spray lifted"}


func _react_fire(power: float, point: Vector3) -> Dictionary:
	var p := _on_surface(point)
	FX.burst(self, p + Vector3(0, 0.1, 0), int(14 + 14 * power), 2.0, FX.pm_puff("steam"), FX.puff_mesh(0.5))
	_ripple(p, 0.15)
	return {"effect": "steam", "detail": "the fire hissed into steam on the water; the pond is unchanged"}


func _react_arcane(power: float, point: Vector3) -> Dictionary:
	var p := _on_surface(point)
	var pal := FX.palette("arcane")
	_ripple(p, 0.4 + 0.4 * power, 1.2 + 1.5 * power, pal[0])
	return {"effect": "glow_ring", "detail": "a ring of arcane light spread across the water and faded"}


func _process(delta: float) -> void:
	super._process(delta)
	for i in 2:
		if _ages[i] >= 0.0:
			_ages[i] += delta
			if _ages[i] > 6.0:
				_ages[i] = -1.0
			mat.set_shader_parameter("ripple_a" if i == 0 else "ripple_b", Vector4(
				(mat.get_shader_parameter("ripple_a" if i == 0 else "ripple_b") as Vector4).x,
				(mat.get_shader_parameter("ripple_a" if i == 0 else "ripple_b") as Vector4).y, _ages[i], _strength[i]))
	if _spout_t >= 0.0:
		_spout_t += delta
		var up := clampf(_spout_t / 0.45, 0.0, 1.0)
		var down := clampf((_spout_t - 0.75) / 0.7, 0.0, 1.0)
		var h := _spout_h * (sin(up * PI * 0.5)) * (1.0 - down * down)
		_spout.scale = Vector3(1.0 - 0.4 * down, maxf(h, 0.01), 1.0 - 0.4 * down)
		_spout.position.y = h * 0.5
		if _spout_t > 1.45:
			_spout_t = -1.0
			_spout.visible = false
			FX.burst(self, _spout.global_position, 30, 1.0, FX.pm_motes("water", "splash"), FX.mote_mesh(0.05))
			_ripple(_spout.global_position, 0.7)
	if _calm_timer > 0.0:
		_calm_timer -= delta
		if _calm_timer <= 0.0:
			state = {"surface": "still"}
