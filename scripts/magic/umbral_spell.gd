class_name UmbralSpell
extends FamilySpell
## Luna's family (V3 Part XIII): precise shadow edged in gold. Angles, not curves; snaps, not sweeps. Her
## lance (CombatSpell) is the first word of this language; these are the next two.
##   ground  UMBRAL RIFT - a six-sided sigil wakes under her; shadow is drawn INTO her palm (a dark core with
##           a gold rim) with three crystal shards circling it; on the thrust the shards fly to the mark, a gold
##           line snaps to it along the ground, a hexagonal rift opens there and dark crystal spikes erupt
##           through it - damage and a daze to whatever stands inside (Monster.daze through the data "daze_s").
##           Judged when it erupts. The rift cools into a scar that stays a while.
##   ward    GILDED MIRROR - a hexagonal pane of dark glass with a gold rim held before her (Ward "mirror")

const ERUPT_DELAY := 0.42

var core: MeshInstance3D
var _core_mat: ShaderMaterial
var shards: Array[MeshInstance3D] = []
var rift: Rift
var _line: MeshInstance3D
var _line_mat: ShaderMaterial
var _rift_at := Vector3.ZERO
var _erupt_t := -1.0
var _erupted := false


func _build() -> void:
	var pal := FX.palette(element)
	match style:
		"ground":
			ground = FX.quad("res://shaders/magic/sigil.gdshader", 2.2, {"color": pal[0], "sides": 6, "intensity": 0.0, "draw_progress": 0.0, "spin": -0.3, "seed": 17.0})
			add_child(ground)
			var gather := FX.particles(70 + 20 * tier, 0.7, FX.pm_motes("umbral", "gather"), FX.mote_mesh(0.045), true)
			gather.name = "Gather"
			gather.emitting = false
			hand_fx.add_child(gather)
			_core_mat = ShaderMaterial.new()
			_core_mat.shader = load("res://shaders/magic/umbral_core.gdshader")
			_core_mat.set_shader_parameter("rim_color", pal[0])
			_core_mat.set_shader_parameter("vein_color", pal[1])
			_core_mat.set_shader_parameter("intensity", 0.0)
			core = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.085
			sm.height = 0.17
			sm.radial_segments = 16
			sm.rings = 8
			core.mesh = sm
			core.material_override = _core_mat
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			core.scale = Vector3.ONE * 0.01
			hand_fx.add_child(core)
			for i in 3:
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0
				cm.bottom_radius = 0.028
				cm.height = 0.17
				cm.radial_segments = 6
				cm.rings = 1
				var mi := MeshInstance3D.new()
				mi.mesh = cm
				mi.material_override = _core_mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.scale = Vector3.ONE * 0.01
				hand_fx.add_child(mi)
				shards.append(mi)
		"ward":
			var gather2 := FX.particles(44, 0.6, FX.pm_motes("umbral", "gather"), FX.mote_mesh(0.035), true)
			gather2.name = "Gather"
			gather2.emitting = false
			hand_fx.add_child(gather2)


func _update(awaken: float, build: float, fade: float, hand: Vector3, fwd: Vector3, _delta: float) -> void:
	var released := _fired.has("release")
	if ground:
		var gm: ShaderMaterial = ground.material_override
		gm.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, awaken))
		gm.set_shader_parameter("intensity", (1.0 + 0.7 * build) * awaken * fade * (0.85 + 0.15 * tier))
	if core and not released:
		core.global_position = hand + fwd * 0.12
		core.scale = Vector3.ONE * maxf(0.01, smoothstep(0.0, 1.0, build)) * (1.0 + 0.1 * sin(t * 11.0))
		_core_mat.set_shader_parameter("intensity", 0.3 + 1.1 * build)
		for i in shards.size():
			var a := t * 7.0 + TAU * i / 3.0
			var off := Vector3(cos(a), 0.35 * sin(t * 3.0 + i), sin(a)) * 0.17 * build
			shards[i].global_position = core.global_position + off
			shards[i].scale = Vector3.ONE * maxf(0.01, build)
			shards[i].global_basis = Basis.looking_at(off.normalized() if off.length() > 0.01 else fwd, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
	if style == "ground" and released and not _erupted and t >= _erupt_t:
		_erupt()


func _release(hand: Vector3, dir: Vector3) -> void:
	_announce("release", hand)
	_stop_hand_particles()
	match style:
		"ground":
			_rift_at = _ground(aim) + Vector3(0, 0.04, 0)
			# the shards fly to the mark, fast and straight
			for s in shards:
				var tw := s.create_tween()
				tw.tween_property(s, "global_position", _rift_at + Vector3(0, 0.2, 0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_callback(func(): s.visible = false)
			if core:
				var ct := core.create_tween()
				ct.tween_property(core, "scale", Vector3.ONE * 0.01, 0.15)
			# the gold line snaps along the ground
			var from := _ground(caster.global_position + Vector3(dir.x, 0, dir.z).normalized() * 0.35) + Vector3(0, 0.05, 0)
			var length := maxf(from.distance_to(_rift_at), 0.5)
			var q := QuadMesh.new()
			q.size = Vector2(length, 0.22)
			_line = MeshInstance3D.new()
			_line.mesh = q
			_line_mat = ShaderMaterial.new()
			_line_mat.shader = load("res://shaders/magic/root_seam.gdshader")
			_line_mat.set_shader_parameter("color", FX.palette("umbral")[0])
			_line_mat.set_shader_parameter("tip_color", Color(1.0, 0.95, 0.8))
			_line_mat.set_shader_parameter("intensity", 1.8)
			_line_mat.set_shader_parameter("reach", 0.0)
			_line_mat.set_shader_parameter("wobble", 0.0)
			_line.material_override = _line_mat
			_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			get_parent().add_child(_line)
			var along := (_rift_at - from).normalized()
			var side := Vector3.UP.cross(along).normalized()
			_line.global_transform = Transform3D(Basis(along, side, Vector3.UP).orthonormalized(), (from + _rift_at) * 0.5)
			var lm := _line_mat
			var lt := _line.create_tween()
			lt.tween_method(func(v: float): lm.set_shader_parameter("reach", v), 0.0, 1.0, 0.1)
			rift = Rift.new()
			get_parent().add_child(rift)
			rift.global_position = _rift_at
			rift.open(tier, power, _light_scale)
			_erupt_t = t + ERUPT_DELAY
			_sfx("rift_open", _rift_at, -5.0)
		"ward":
			var w := Ward.new()
			get_parent().add_child(w)
			var charges := 1 + (1 if mastery >= 1.5 else 0)
			var seconds := float(def.get("ward_s", 3.0)) + 1.0 * minf(mastery, 3.0)
			var reflects := mastery >= 1.5
			w.setup(caster, "mirror", spell_id, charges, seconds, reflects)
			_resolve({"outcome": "self", "point": _v(caster.global_position), "ward": "mirror", "charges": charges, "seconds": snappedf(seconds, 0.1), "reflects": reflects})


func _travel_time(_p: Vector3) -> float:
	return ERUPT_DELAY + 0.1


func _pending() -> bool:
	return style == "ground" and _fired.has("release") and not _erupted


func _erupt() -> void:
	_erupted = true
	var gy := _rift_at.y - 0.04
	var radius := 1.6 + 0.2 * tier
	var outcome := "missed"
	var point := Vector3(_rift_at.x, gy + 0.6, _rift_at.z)
	var dist := -1.0
	if target and is_instance_valid(target):
		var tp := target.aim_point()
		var flat := Vector2(tp.x - _rift_at.x, tp.z - _rift_at.z).length()
		dist = flat
		var reachable := tp.y - gy < 3.2       # the spikes and the burst of shadow reach a hovering creature, not one high up
		if flat <= radius + target.aim_radius and reachable:
			outcome = "hit"
			point = Vector3(tp.x, minf(tp.y, gy + 1.2), tp.z)
	rift.erupt()
	_announce("impact" if outcome == "hit" else "missed", point)
	_sfx("rift_erupt", point, -2.0)
	if _line:
		var lm := _line_mat
		var tw := _line.create_tween()
		tw.tween_method(func(v: float): lm.set_shader_parameter("intensity", v), 1.8, 0.0, 0.4)
		tw.tween_callback(_line.queue_free)
	_resolve({"outcome": outcome, "point": _v(point), "distance_from_target_m": snappedf(dist, 0.01), "radius": radius})


## The rift on the ground: opens (cracks spread), erupts (dark crystal spikes rise through it with a gold
## pulse and splinters), the spikes sink back, and the pane cools into a scar that fades after a while.
class Rift extends Node3D:
	const SCAR_S := 25.0
	var quad: MeshInstance3D
	var mat: ShaderMaterial
	var spikes: Array[MeshInstance3D] = []
	var spike_h: Array[float] = []
	var light: OmniLight3D
	var smoke: GPUParticles3D
	var _phase := "open"
	var _t := 0.0
	var _light_scale := 1.0

	func open(tier: int, power: float, light_scale: float) -> void:
		_light_scale = light_scale
		var pal := FX.palette("umbral")
		quad = FX.quad("res://shaders/magic/umbral_rift.gdshader", 3.1 + 0.3 * tier, {"gold": pal[0], "violet": pal[1], "intensity": 1.3, "draw_progress": 0.0, "scorch": 0.0, "seed": float(randi() % 50)})
		add_child(quad)
		light = FX.light(pal[0], 0.0, 4.5)
		add_child(light)
		light.position.y = 0.6
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/magic/umbral_core.gdshader")
		sm.set_shader_parameter("rim_color", pal[0])
		sm.set_shader_parameter("vein_color", pal[1])
		sm.set_shader_parameter("intensity", 1.3 + 0.3 * power)
		var n := 7
		for i in n:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.12 if i > 0 else 0.17
			var h := (1.7 if i > 0 else 2.2) + 0.15 * tier + randf_range(-0.12, 0.12)
			cm.height = h
			cm.radial_segments = 6
			cm.rings = 1
			var mi := MeshInstance3D.new()
			mi.mesh = cm
			mi.material_override = sm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ang := TAU * i / (n - 1)
			var r := 0.0 if i == 0 else 0.85
			mi.position = Vector3(cos(ang) * r, -h, sin(ang) * r)
			if i > 0:
				mi.rotation = Vector3(sin(ang) * 0.22, 0.0, -cos(ang) * 0.22)
			mi.visible = false
			add_child(mi)
			spikes.append(mi)
			spike_h.append(h)

	func erupt() -> void:
		_phase = "erupt"
		_t = 0.0
		for i in spikes.size():
			var s := spikes[i]
			s.visible = true
			var tw := s.create_tween()
			tw.tween_property(s, "position:y", spike_h[i] * 0.5 - 0.1, 0.12 + 0.02 * i).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ImpactFX.shockwave(get_parent(), global_position + Vector3(0, 0.06, 0), FX.palette("umbral")[0], 1.4)
		FX.burst(get_parent(), global_position + Vector3(0, 0.5, 0), 40, 0.9, FX.pm_motes("umbral", "burst"), FX.mote_mesh(0.05, true))
		light.light_energy = 3.2 * _light_scale
		ImpactFX.shake(get_parent(), 0.02, 0.18)

	func _process(delta: float) -> void:
		_t += delta
		match _phase:
			"open":
				mat = quad.material_override
				mat.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, _t / 0.38))
				light.light_energy = 0.8 * _light_scale * clampf(_t / 0.38, 0.0, 1.0)
			"erupt":
				light.light_energy = lerpf(light.light_energy, 1.2 * _light_scale, 1.0 - exp(-6.0 * delta))
				if _t > 0.65:
					_phase = "retract"
					_t = 0.0
					for i in spikes.size():
						var s := spikes[i]
						var tw := s.create_tween()
						tw.tween_property(s, "position:y", -spike_h[i], 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			"retract":
				light.light_energy = lerpf(light.light_energy, 0.0, 1.0 - exp(-5.0 * delta))
				if _t > 0.35:
					_phase = "scar"
					_t = 0.0
					for s in spikes:
						s.visible = false
					smoke = FX.particles(10, 2.6, FX.pm_puff("smoke"), FX.puff_mesh(0.55), false)
					smoke.emitting = true
					add_child(smoke)
					smoke.position.y = 0.1
			"scar":
				var m: ShaderMaterial = quad.material_override
				m.set_shader_parameter("scorch", clampf(_t / 1.2, 0.0, 1.0))
				if smoke and _t > 10.0:
					smoke.emitting = false
				if _t > SCAR_S:
					m.set_shader_parameter("intensity", maxf(0.0, 1.2 * (1.0 - (_t - SCAR_S) / 3.0)))
				if _t > SCAR_S + 3.0:
					queue_free()
