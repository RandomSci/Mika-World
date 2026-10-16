class_name LookFX
## Per-look effects from the outfit design sheets (they are not models): glowing petals, leaves, star-flower sparks,
## swirling wind, a comet trail, shadow wisps, moon glints, a golden halo ring, shadow flames, gold sparkles, falling
## blossom petals, glowing rune rings, a wind-and-leaf tornado (round her, or round her spear: "spear_wind").
## The transformation plays a look's effects at full strength around her (data/transformations.json "effects"); the
## look's appearance profile "aura" keeps a few of them around her softly while she wears it.

const KINDS := ["petals", "leaves", "starflowers", "wind", "comet", "wisps", "moons", "halo", "flames", "sparkles", "blossoms", "runes", "tornado", "spear_wind"]

static var _petal_mesh: QuadMesh


static func petal_mesh() -> QuadMesh:
	if _petal_mesh == null:
		_petal_mesh = QuadMesh.new()
		_petal_mesh.size = Vector2(0.05, 0.065)
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/magic/petal.gdshader")
		_petal_mesh.material = sm
	return _petal_mesh


static func make(kind: String, col: Color, acc: Color, strength := 1.0) -> Node3D:
	var n: Node3D
	match kind:
		"petals":
			n = FX.particles(int(80 * strength), 3.2, FX.process("look_petals", func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 1.5
				pm.gravity = Vector3(0, -0.22, 0)
				pm.initial_velocity_min = 0.1
				pm.initial_velocity_max = 0.45
				pm.angular_velocity_min = -140.0
				pm.angular_velocity_max = 140.0
				pm.tangential_accel_min = 0.5
				pm.tangential_accel_max = 1.1
				pm.scale_min = 0.8
				pm.scale_max = 1.6
				pm.color_ramp = FX.ramp([Color(1, 0.92, 0.97, 0.0), Color(1, 0.94, 0.98, 0.95), Color(0.85, 0.85, 1.0, 0.0)], [0.0, 0.2, 1.0])), FX.mote_mesh(0.065))
		"leaves":
			n = FX.particles(int(60 * strength), 3.6, FX.process("look_leaves", func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				pm.emission_ring_axis = Vector3.UP
				pm.emission_ring_radius = 1.3
				pm.emission_ring_inner_radius = 0.6
				pm.emission_ring_height = 0.2
				pm.direction = Vector3.UP
				pm.spread = 25.0
				pm.initial_velocity_min = 0.6
				pm.initial_velocity_max = 1.4
				pm.gravity = Vector3(0, -0.35, 0)
				pm.tangential_accel_min = 1.2
				pm.tangential_accel_max = 2.2
				pm.angular_velocity_min = -220.0
				pm.angular_velocity_max = 220.0
				pm.scale_min = 0.7
				pm.scale_max = 1.3
				pm.color_ramp = FX.ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)], [0.0, 0.15, 1.0])), FX.leaf_mesh(0.08, "thin"))
		"starflowers":
			n = FX.particles(int(70 * strength), 2.6, FX.process("look_starflowers_%s" % col.to_html(), func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 1.2
				pm.gravity = Vector3(0, 0.25, 0)
				pm.initial_velocity_min = 0.05
				pm.initial_velocity_max = 0.25
				pm.tangential_accel_min = 0.3
				pm.tangential_accel_max = 0.7
				pm.scale_min = 0.5
				pm.scale_max = 1.6
				pm.color_ramp = FX.ramp([Color(acc, 0.0), Color(1, 1, 1, 1.0), Color(col, 0.6), Color(col, 0.0)], [0.0, 0.15, 0.6, 1.0])), FX.mote_mesh(0.05))
		"wind":
			n = FX.particles(int(140 * strength), 1.6, FX.process("look_wind_%s" % col.to_html(), func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				pm.emission_ring_axis = Vector3.UP
				pm.emission_ring_radius = 1.25
				pm.emission_ring_inner_radius = 0.9
				pm.emission_ring_height = 2.2
				pm.direction = Vector3.UP
				pm.spread = 10.0
				pm.initial_velocity_min = 0.6
				pm.initial_velocity_max = 1.5
				pm.gravity = Vector3.ZERO
				pm.tangential_accel_min = 7.0
				pm.tangential_accel_max = 11.0
				pm.radial_accel_min = -2.5
				pm.radial_accel_max = -1.0
				pm.scale_min = 0.7
				pm.scale_max = 1.4
				pm.color_ramp = FX.ramp([Color(1, 1, 1, 0.0), Color(col.lerp(Color.WHITE, 0.6), 0.75), Color(col, 0.0)], [0.0, 0.3, 1.0])), FX.mote_mesh(0.045))
		"comet":
			n = FX.particles(int(40 * strength), 1.2, FX.process("look_comet_%s" % col.to_html(), func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 0.15
				pm.gravity = Vector3.ZERO
				pm.initial_velocity_min = 0.0
				pm.initial_velocity_max = 0.2
				pm.scale_min = 1.0
				pm.scale_max = 2.4
				pm.color_ramp = FX.ramp([Color(1, 1, 1, 1.0), Color(acc, 0.85), Color(col, 0.0)], [0.0, 0.35, 1.0])), FX.mote_mesh(0.07))
		"wisps":
			n = FX.particles(int(60 * strength), 3.0, FX.process("look_wisps_%s" % acc.to_html(), func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				pm.emission_ring_axis = Vector3.UP
				pm.emission_ring_radius = 1.0
				pm.emission_ring_inner_radius = 0.3
				pm.emission_ring_height = 0.2
				pm.direction = Vector3.UP
				pm.spread = 20.0
				pm.initial_velocity_min = 0.3
				pm.initial_velocity_max = 0.9
				pm.gravity = Vector3(0, 0.25, 0)
				pm.tangential_accel_min = -0.8
				pm.tangential_accel_max = 0.8
				pm.scale_min = 1.0
				pm.scale_max = 2.6
				pm.color_ramp = FX.ramp([Color(0.05, 0.02, 0.08, 0.0), Color(0.12, 0.05, 0.2, 0.75), Color(acc, 0.45), Color(acc, 0.0)], [0.0, 0.2, 0.7, 1.0])), FX.puff_mesh(0.22))
		"moons":
			n = FX.particles(int(40 * strength), 2.8, FX.process("look_moons_%s" % col.to_html(), func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 1.3
				pm.gravity = Vector3(0, -0.05, 0)
				pm.initial_velocity_min = 0.02
				pm.initial_velocity_max = 0.15
				pm.tangential_accel_min = -0.6
				pm.tangential_accel_max = -0.2
				pm.scale_min = 0.6
				pm.scale_max = 1.4
				pm.color_ramp = FX.ramp([Color(col, 0.0), Color(1, 0.9, 0.6, 1.0), Color(col, 0.0)], [0.0, 0.3, 1.0])), FX.mote_mesh(0.045))
		"flames":
			n = FX.particles(int(110 * strength), 1.4, FX.process("look_flames_%s" % acc.to_html(), func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				pm.emission_ring_axis = Vector3.UP
				pm.emission_ring_radius = 0.9
				pm.emission_ring_inner_radius = 0.4
				pm.emission_ring_height = 0.05
				pm.direction = Vector3.UP
				pm.spread = 12.0
				pm.initial_velocity_min = 1.0
				pm.initial_velocity_max = 2.2
				pm.gravity = Vector3(0, 0.6, 0)
				pm.damping_min = 0.5
				pm.damping_max = 1.0
				pm.scale_min = 1.0
				pm.scale_max = 2.2
				pm.color_ramp = FX.ramp([Color(0.05, 0.0, 0.03, 0.0), Color(0.55, 0.05, 0.12, 0.85), Color(0.08, 0.02, 0.06, 0.6), Color(0, 0, 0, 0.0)], [0.0, 0.2, 0.6, 1.0])), FX.puff_mesh(0.18))
		"halo":
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.165   # a halo just behind her head, not around her shoulders
			tm.outer_radius = 0.178
			tm.rings = 48
			tm.ring_segments = 8
			ring.mesh = tm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.82, 0.4)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.78, 0.35)
			m.emission_energy_multiplier = 2.5 * strength
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring.material_override = m
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.rotation = Vector3(deg_to_rad(90.0), 0, 0)
			n = Node3D.new()
			n.add_child(ring)
		"sparkles":
			n = FX.particles(int(90 * strength), 1.1, FX.process("look_sparkles_%s" % col.to_html(), func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 1.1
				pm.gravity = Vector3(0, 0.05, 0)
				pm.initial_velocity_min = 0.0
				pm.initial_velocity_max = 0.08
				pm.scale_min = 0.25
				pm.scale_max = 0.9
				pm.color_ramp = FX.ramp([Color(col, 0.0), Color(1, 1, 1, 1.0), Color(col, 0.9), Color(acc, 0.0)], [0.0, 0.12, 0.45, 1.0])), FX.mote_mesh(0.05))
		"blossoms":
			n = FX.particles(int(70 * strength), 5.0, FX.process("look_blossoms_%s" % col.to_html(), func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
				pm.emission_box_extents = Vector3(1.3, 0.1, 1.3)
				pm.direction = Vector3(0.3, -1, 0.1)
				pm.spread = 30.0
				pm.initial_velocity_min = 0.1
				pm.initial_velocity_max = 0.3
				pm.gravity = Vector3(0.05, -0.28, 0.0)
				pm.damping_min = 0.2
				pm.damping_max = 0.5
				pm.angle_min = -180.0
				pm.angle_max = 180.0
				pm.angular_velocity_min = -120.0
				pm.angular_velocity_max = 120.0
				pm.turbulence_enabled = true
				pm.turbulence_noise_strength = 0.6
				pm.turbulence_noise_scale = 2.5
				pm.turbulence_influence_min = 0.05
				pm.turbulence_influence_max = 0.12
				pm.scale_min = 0.7
				pm.scale_max = 1.3
				pm.color_ramp = FX.ramp([Color(col, 0.0), Color(col, 1.0), Color(col.lerp(acc, 0.4), 0.9), Color(acc, 0.0)], [0.0, 0.1, 0.8, 1.0])), petal_mesh())
		"runes":
			n = Node3D.new()
			for spec in [[2.3, 0.18, 6, 3.0, 0.02], [1.45, -0.32, 8, 7.0, 0.03], [1.1, 0.5, 5, 11.0, 1.0]]:
				var q := FX.quad("res://shaders/magic/sigil.gdshader", spec[0], {"color": col, "spin": spec[1], "sides": spec[2], "seed": spec[3], "intensity": 0.9 * strength, "draw_progress": 1.0})
				q.position = Vector3(0, spec[4], 0)
				q.set_meta("base_intensity", 0.9 * strength)
				n.add_child(q)
		"tornado", "spear_wind":
			var big: bool = kind == "tornado"
			n = Node3D.new()
			var wind := FX.particles(int((160 if big else 70) * strength), 0.9 if big else 0.7, FX.process("look_%s_wind_%s" % [kind, col.to_html()], func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				pm.emission_ring_axis = Vector3.UP
				pm.emission_ring_radius = 0.75 if big else 0.16
				pm.emission_ring_inner_radius = 0.35 if big else 0.08
				pm.emission_ring_height = 0.3 if big else 1.1
				pm.direction = Vector3.UP
				pm.spread = 8.0
				pm.initial_velocity_min = 1.6 if big else 0.2
				pm.initial_velocity_max = 2.6 if big else 0.5
				pm.gravity = Vector3.ZERO
				pm.tangential_accel_min = 9.0 if big else 5.0
				pm.tangential_accel_max = 14.0 if big else 8.0
				pm.radial_accel_min = -1.5
				pm.radial_accel_max = -0.5
				pm.scale_min = 0.6
				pm.scale_max = 1.2
				pm.color_ramp = FX.ramp([Color(1, 1, 1, 0.0), Color(col.lerp(Color.WHITE, 0.6), 0.8), Color(col, 0.0)], [0.0, 0.3, 1.0])), FX.mote_mesh(0.04 if big else 0.025, true), true)
			n.add_child(wind)
			var lv := FX.particles(int((50 if big else 18) * strength), 1.1 if big else 0.8, FX.process("look_%s_leaves" % kind, func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				pm.emission_ring_axis = Vector3.UP
				pm.emission_ring_radius = 0.6 if big else 0.14
				pm.emission_ring_inner_radius = 0.3 if big else 0.06
				pm.emission_ring_height = 0.2 if big else 1.0
				pm.direction = Vector3.UP
				pm.spread = 10.0
				pm.initial_velocity_min = 1.2 if big else 0.2
				pm.initial_velocity_max = 2.0 if big else 0.4
				pm.gravity = Vector3.ZERO
				pm.tangential_accel_min = 8.0 if big else 4.0
				pm.tangential_accel_max = 12.0 if big else 7.0
				pm.radial_accel_min = -1.0
				pm.radial_accel_max = 0.0
				pm.angular_velocity_min = -300.0
				pm.angular_velocity_max = 300.0
				pm.scale_min = 0.6
				pm.scale_max = 1.1
				pm.color_ramp = FX.ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)], [0.0, 0.2, 1.0])), FX.leaf_mesh(0.07 if big else 0.045, "thin"), true)
			n.add_child(lv)
		_:
			n = Node3D.new()
	n.name = "LookFX_" + kind
	n.set_meta("look_fx", kind)
	return n


## Where each effect sits around her (from her root, world space) and when it plays in a transformation.
static func follow(n: Node3D, c: WorldCharacter, t := -1.0) -> void:
	var kind := String(n.get_meta("look_fx", ""))
	var base := c.global_position
	match kind:
		"halo":
			var head := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone("Head")).origin
			var back := c.global_transform.basis.z.normalized()
			n.global_position = head + Vector3(0, 0.13, 0) + back * 0.13
			n.global_rotation = Vector3(0, c.global_rotation.y, 0)
		"comet":
			var tt := t if t >= 0.0 else Time.get_ticks_msec() / 1000.0
			var r := 1.2
			n.global_position = base + Vector3(sin(tt * 2.6) * r, 1.0 + 0.6 * sin(tt * 0.9), cos(tt * 2.6) * r)
		"flames", "wisps", "leaves", "wind", "runes", "tornado":
			n.global_position = base + Vector3(0, 0.05, 0)
		"blossoms":
			n.global_position = base + Vector3(0, 2.4, 0)
		"spear_wind":
			pass                                        # rides the weapon (child of the hand's weapon root)
		_:
			n.global_position = base + Vector3(0, 1.15, 0)


static func set_on(n: Node3D, on: bool, fade := 1.0) -> void:
	if n is GPUParticles3D:
		(n as GPUParticles3D).emitting = on
	elif String(n.get_meta("look_fx", "")) in ["tornado", "spear_wind"]:
		for ch in n.get_children():
			(ch as GPUParticles3D).emitting = on
	elif String(n.get_meta("look_fx", "")) == "runes":
		n.visible = on and fade > 0.01
		for ch in n.get_children():
			var mi := ch as MeshInstance3D
			(mi.material_override as ShaderMaterial).set_shader_parameter("intensity", float(mi.get_meta("base_intensity", 1.0)) * clampf(fade, 0.0, 1.0))
	elif String(n.get_meta("look_fx", "")) == "halo":
		n.visible = fade > 0.01
		var ring := n.get_child(0) as MeshInstance3D
		(ring.material_override as StandardMaterial3D).albedo_color.a = clampf(fade, 0.0, 1.0)
		ring.scale = Vector3.ONE * lerpf(0.6, 1.0, clampf(fade, 0.0, 1.0))


## The look's soft ambient effects while she wears it (appearance profile "aura": {"kinds": [...], "color": [r,g,b],
## "accent": [r,g,b], "strength": 0.2}). Returns the nodes (children of the character; the caller frees them with the rig).
static func attach_aura(c: WorldCharacter, aura: Dictionary) -> Array:
	var out: Array = []
	if aura.is_empty() or RenderProfile.options.has("no-aura"):
		return out
	var cc: Array = aura.get("color", [1, 1, 1])
	var ac: Array = aura.get("accent", cc)
	var col := Color(cc[0], cc[1], cc[2])
	var acc := Color(ac[0], ac[1], ac[2])
	for kind in aura.get("kinds", []):
		var n := make(String(kind), col, acc, float(aura.get("strength", 0.2)))
		n.name = "Aura_" + String(kind)
		c.add_child(n)
		set_on(n, true, 1.0)
		out.append(n)
	return out
