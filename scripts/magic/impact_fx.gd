class_name ImpactFX
extends RefCounted
## Combat impacts that read at a distance: an ELEMENT-SPECIFIC response (arcane light shards, umbral
## crystal splinters, fire flare, water splash, wind gust), sparks thrown outward, dust, a short light pulse
## and a very small camera jolt scaled by power. A ground ring only when the impact is near the ground
## (Milestone J: no identical camera-facing circle on every ability). Shared by every
## spell that lands on a creature, and by fusions (bigger, two-coloured). Budget-aware: particle counts
## follow the render profile (FX.particles) and lights never cast shadows.

const COLORS := {"arcane": [Color(0.5, 0.72, 1.0), Color(0.85, 0.6, 1.0)], "umbral": [Color(1.0, 0.76, 0.3), Color(0.5, 0.2, 0.95)],
	"wind": [Color(0.75, 1.0, 0.88), Color(0.9, 1.0, 0.95)], "water": [Color(0.4, 0.78, 1.0), Color(0.8, 0.95, 1.0)],
	"fire": [Color(1.0, 0.55, 0.15), Color(1.0, 0.85, 0.4)], "eclipse": [Color(1.0, 0.86, 0.5), Color(0.62, 0.42, 1.0)]}


static func play(host: Node, at: Vector3, element: String, power: float, lethal := false) -> void:
	if host == null:
		return
	var pal: Array = COLORS.get(element, COLORS.arcane)
	var big := clampf(0.7 + power * 0.5 + (0.4 if lethal else 0.0), 0.6, 1.8)
	var ground_y := at.y - 0.3
	var world := host if host.has_method("ground_at") else null
	if world:
		ground_y = float(world.ground_at(at.x, at.z))
	if at.y - ground_y < 1.6:
		ground_ring(host, Vector3(at.x, ground_y + 0.05, at.z), pal[0], 1.4 * big)
	_element_layer(host, at, element, pal, big)
	FX.burst(host, at, int(40 * big), 0.7, FX.process("impact_sparks_" + element, func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.12
		pm.spread = 180.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 7.0
		pm.gravity = Vector3(0, -6.0, 0)
		pm.damping_min = 2.0
		pm.damping_max = 4.0
		pm.particle_flag_align_y = true
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		pm.color_ramp = FX.ramp([Color(1, 1, 1, 1), Color(pal[0], 0.95), Color(pal[1], 0.0)], [0.0, 0.3, 1.0])), FX.mote_mesh(0.05, true))
	FX.burst(host, at, int(30 * big), 0.9, FX.pm_motes(element if FX.PALETTES.has(element) else "arcane", "burst"), FX.mote_mesh(0.06))
	FX.burst(host, at - Vector3(0, 0.3, 0), int(8 * big), 1.6, FX.pm_puff("dust"), FX.puff_mesh(0.7))
	var flash := FX.light(pal[1].lerp(Color.WHITE, 0.4), 3.2 * big * float(RenderProfile.get_setting("magic_light_scale")), 5.5)
	host.add_child(flash)
	flash.global_position = at + Vector3(0, 0.4, 0)
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_callback(flash.queue_free)
	shake(host, 0.025 * big, 0.2)
	if AudioDirector.instance:
		AudioDirector.instance.play3d("impact_heavy" if lethal or power > 0.9 else "impact_light", at, "SFX", -2.0 if lethal else -4.0, "combat_impact", 0.9 + randf() * 0.2)


## Element identity of an impact: shapes, motion and colour that belong to the element.
static func _element_layer(host: Node, at: Vector3, element: String, pal: Array, big: float) -> void:
	match element:
		"arcane", "eclipse":
			# light shards: fast, stretched streaks radiating out and fading (no circle)
			FX.burst(host, at, int(26 * big), 0.45, FX.process("impact_shards_" + element, func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 0.08
				pm.spread = 180.0
				pm.initial_velocity_min = 6.0
				pm.initial_velocity_max = 11.0
				pm.damping_min = 9.0
				pm.damping_max = 14.0
				pm.particle_flag_align_y = true
				pm.scale_min = 1.4
				pm.scale_max = 2.6
				pm.color_ramp = FX.ramp([Color(1, 1, 1, 1), Color(pal[0], 0.9), Color(pal[1], 0.0)], [0.0, 0.25, 1.0])), FX.mote_mesh(0.035, true))
		"umbral":
			# dark crystal splinters with a gold edge that fall with weight
			FX.burst(host, at, int(22 * big), 0.9, FX.process("impact_splinters_umbral", func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 0.1
				pm.spread = 160.0
				pm.direction = Vector3(0, 1, 0)
				pm.initial_velocity_min = 2.5
				pm.initial_velocity_max = 6.0
				pm.gravity = Vector3(0, -9.0, 0)
				pm.particle_flag_align_y = true
				pm.scale_min = 1.0
				pm.scale_max = 2.0
				pm.color_ramp = FX.ramp([Color(pal[0], 1.0), Color(pal[1], 0.9), Color(0.1, 0.05, 0.15, 0.0)], [0.0, 0.4, 1.0])), FX.mote_mesh(0.05, true))
		"fire":
			FX.burst(host, at, int(14 * big), 1.0, FX.pm_puff("flare"), FX.puff_mesh(0.5))
		"water":
			FX.burst(host, at, int(30 * big), 0.9, FX.process("impact_splash", func(pm: ParticleProcessMaterial):
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 0.15
				pm.direction = Vector3(0, 1, 0)
				pm.spread = 70.0
				pm.initial_velocity_min = 2.0
				pm.initial_velocity_max = 5.0
				pm.gravity = Vector3(0, -9.8, 0)
				pm.color_ramp = FX.ramp([Color(0.85, 0.95, 1.0, 0.9), Color(pal[0], 0.0)], [0.0, 1.0])), FX.mote_mesh(0.045))
		"wind":
			FX.burst(host, at, int(16 * big), 0.8, FX.pm_puff("dust"), FX.puff_mesh(0.45))


## An expanding ring hugging the ground, fading as it grows (only for impacts near the ground).
static func ground_ring(host: Node, at: Vector3, col: Color, radius: float) -> void:
	var q := FX.quad("res://shaders/magic/shockwave.gdshader", 1.0, {"color": col, "thickness": 0.07, "intensity": 2.4}, true)
	host.add_child(q)
	q.global_position = at
	q.scale = Vector3.ONE * 0.2
	var tw := q.create_tween().set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * radius * 2.0, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): (q.material_override as ShaderMaterial).set_shader_parameter("intensity", v), 2.4, 0.0, 0.55)
	tw.chain().tween_callback(q.queue_free)


## An expanding ring hugging the ground (and a thinner upright one), fading as it grows. (Creature slams.)
static func shockwave(host: Node, at: Vector3, col: Color, radius: float) -> void:
	for k in 1:                      # Milestone J: the ground ring only (no upright disc facing the camera)
		var q := FX.quad("res://shaders/magic/shockwave.gdshader", 1.0, {"color": col, "thickness": 0.08 if k == 0 else 0.05, "intensity": 3.0}, k == 0)
		host.add_child(q)
		q.global_position = at + (Vector3(0, -0.25, 0) if k == 0 else Vector3.ZERO)
		if k == 1:
			var cam := host.get_viewport().get_camera_3d() if host.is_inside_tree() else null
			if cam:
				q.look_at(cam.global_position, Vector3.UP)
		q.scale = Vector3.ONE * 0.2
		var tw := q.create_tween().set_parallel(true)
		tw.tween_property(q, "scale", Vector3.ONE * radius * (2.0 if k == 0 else 1.2), 0.45 if k == 0 else 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_method(func(v: float): (q.material_override as ShaderMaterial).set_shader_parameter("intensity", v), 3.0, 0.0, 0.5 if k == 0 else 0.32)
		tw.chain().tween_callback(q.queue_free)


## Brief positional jolt of the active camera rig (never the director's framing logic itself).
static func shake(host: Node, amount: float, seconds: float) -> void:
	if not host.is_inside_tree():
		return
	var cam := host.get_viewport().get_camera_3d()
	if cam == null:
		return
	var base_h := cam.h_offset
	var base_v := cam.v_offset
	var tw := cam.create_tween()
	var steps := 5
	for i in steps:
		var a := amount * (1.0 - float(i) / steps)
		tw.tween_property(cam, "h_offset", base_h + randf_range(-a, a), seconds / steps)
		tw.parallel().tween_property(cam, "v_offset", base_v + randf_range(-a, a), seconds / steps)
	tw.tween_property(cam, "h_offset", base_h, 0.05)
	tw.parallel().tween_property(cam, "v_offset", base_v, 0.05)
