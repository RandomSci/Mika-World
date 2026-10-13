class_name ImpactFX
extends RefCounted
## Combat impacts that read at a distance: a ground-hugging shockwave ring, a hot core flash, sparks thrown
## outward, a puff of dust, a short light pulse and a small camera shake scaled by power. Shared by every
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
	shockwave(host, at, pal[0], 1.6 * big)
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
	shake(host, 0.06 * big, 0.25)
	if AudioDirector.instance:
		AudioDirector.instance.play3d("impact_heavy" if lethal or power > 0.9 else "impact_light", at, "SFX", -2.0 if lethal else -4.0, "combat_impact", 0.9 + randf() * 0.2)


## An expanding ring hugging the ground (and a thinner upright one), fading as it grows.
static func shockwave(host: Node, at: Vector3, col: Color, radius: float) -> void:
	for k in 2:
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
