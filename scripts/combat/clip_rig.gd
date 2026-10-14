class_name ClipRig
extends CreatureBody
## A creature body driven by its own animation clips (an imported, rigged GLB), with procedural flight on
## top: hover bob, banking into turns, rearing back while it charges, and a dive pitch. Used by the
## Emberwing (Quaternius "Dragon", CC0, recoloured for Mika World - see docs/ASSET_SOURCES.md).
## spec (data/monsters.json -> "body"): {glb, scale, yaw_offset, clips: {state: [clip, speed, loop]},
##   recolor: {material_name: [r, g, b, emission]}, mouth: [x, y, z], ground: true for a walking creature (no hover
##   bob, banking or rearing - its clips carry the body), keep_materials: true to keep the model's own PBR materials}

var spec := {}
var model: Node3D
var player: AnimationPlayer
var _pivot: Node3D                # procedural layer between this node and the model
var _mats := {}                   # material name -> StandardMaterial3D (recoloured copies)
var _hurt := 0.0
var _t := 0.0
var _bank := 0.0
var _prev_yaw := 0.0
var hover := 0.0                  # extra height (m) the monster asks for (rising away, diving)
var pitch := 0.0                  # radians, nose down > 0
var mouth_glow: OmniLight3D
var _own_emission := {}           # material name -> [enabled, colour, energy] as imported (restored after a hurt flash)


func build(p_spec: Dictionary, eye: Color) -> void:
	spec = p_spec
	glow_color = eye
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	model = (load(String(spec.glb)) as PackedScene).instantiate()
	model.scale = Vector3.ONE * float(spec.get("scale", 1.0))
	model.rotation.y = deg_to_rad(float(spec.get("yaw_offset", 0.0)))
	_pivot.add_child(model)
	player = model.find_child("AnimationPlayer", true, false)
	var rc: Dictionary = spec.get("recolor", {})
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			var nm := String(src.resource_name) if src else ""
			var key := ""
			for k in rc:
				if nm.begins_with(k):
					key = k
			var mat := StandardMaterial3D.new()
			if src is BaseMaterial3D:
				mat = (src as BaseMaterial3D).duplicate()
			if key != "":
				var c: Array = rc[key]
				mat.albedo_color = Color(c[0], c[1], c[2])
				if c.size() > 3 and float(c[3]) > 0.0:
					mat.emission_enabled = true
					mat.emission = Color(c[0], c[1], c[2])
					mat.emission_energy_multiplier = float(c[3])
			if not bool(spec.get("keep_materials", false)):
				mat.roughness = 0.75
			_own_emission[nm] = [mat.emission_enabled, mat.emission, mat.emission_energy_multiplier]
			_mats[nm] = mat
			m.set_surface_override_material(si, mat)
	mouth_glow = FX.light(eye, 0.0, 3.0)
	var mp: Array = spec.get("mouth", [0, 1.2, 0.6])
	mouth_glow.position = Vector3(mp[0], mp[1], mp[2])
	_pivot.add_child(mouth_glow)
	_prev_yaw = global_rotation.y
	_entered("idle")


func clip_length(st: String) -> float:
	var c: Array = spec.get("clips", {}).get(st, [])
	if c.is_empty() or player == null or not player.has_animation(String(c[0])):
		return 0.0
	return player.get_animation(String(c[0])).length / maxf(float(c[1]), 0.05)


func _entered(s: String) -> void:
	if player == null:
		return
	var clips: Dictionary = spec.get("clips", {})
	var c: Array = clips.get(s, clips.get("idle", []))
	if c.is_empty() or not player.has_animation(String(c[0])):
		return
	var a := player.get_animation(String(c[0]))
	a.loop_mode = Animation.LOOP_LINEAR if (c.size() > 2 and bool(c[2])) else Animation.LOOP_NONE
	player.play(String(c[0]), 0.18, float(c[1]))


func aim_point() -> Vector3:
	return _pivot.global_position + Vector3(0, float(spec.get("aim_y", 1.0)), 0)


func mouth_point() -> Vector3:
	return mouth_glow.global_position if mouth_glow else aim_point()


func flash(strength := 1.0) -> void:
	_hurt = clampf(strength, 0.3, 1.0)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	state_t += delta
	# banking: roll into the turn (yaw rate), like a flyer, never more than ~35 degrees
	var yaw := global_rotation.y
	var rate := angle_difference(_prev_yaw, yaw) / maxf(delta, 1e-4)
	_prev_yaw = yaw
	_bank = lerpf(_bank, clampf(-rate * 0.25 - move_speed * 0.0, -0.6, 0.6), 1.0 - exp(-4.0 * delta))
	var ground := bool(spec.get("ground", false))
	if ground:
		_bank = 0.0
	var bob := 0.12 * sin(_t * 3.1) if (state != "defeat" and not ground) else 0.0
	var rear := 0.0
	if state == "windup" and not ground:
		rear = -0.45 * clampf(state_t / 0.4, 0.0, 1.0)      # rears back, chest out, before it breathes / dives
	elif state == "strike" and not ground:
		rear = 0.25
	_pivot.position.y = lerpf(_pivot.position.y, hover + bob, 1.0 - exp(-5.0 * delta))
	_pivot.rotation = Vector3(lerpf(_pivot.rotation.x, rear + pitch, 1.0 - exp(-8.0 * delta)), 0, _bank)
	if mouth_glow:
		var want := 2.4 * clampf(state_t / 0.5, 0.0, 1.0) if state == "windup" else 0.0
		mouth_glow.light_energy = lerpf(mouth_glow.light_energy, want * float(RenderProfile.get_setting("magic_light_scale")), 1.0 - exp(-12.0 * delta))
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	for nm in _mats:
		var m: StandardMaterial3D = _mats[nm]
		if _hurt > 0.0:
			m.emission_enabled = true
			m.emission = Color(1.0, 0.85, 0.6)
			m.emission_energy_multiplier = _hurt * 1.4
		elif m.emission == Color(1.0, 0.85, 0.6):
			var rc: Dictionary = spec.get("recolor", {})
			var restored := false
			for k in rc:
				if nm.begins_with(k) and (rc[k] as Array).size() > 3 and float(rc[k][3]) > 0.0:
					m.emission = Color(rc[k][0], rc[k][1], rc[k][2])
					m.emission_energy_multiplier = float(rc[k][3])
					restored = true
			if not restored:
				var own: Array = _own_emission.get(nm, [false, Color.BLACK, 1.0])
				m.emission_enabled = bool(own[0])
				m.emission = own[1]
				m.emission_energy_multiplier = float(own[2])


func collapse() -> void:
	play("defeat")
	hover = 0.0 if bool(spec.get("ground", false)) else -0.4
	await get_tree().create_timer(maxf(0.6, clip_length("defeat"))).timeout
