class_name WindFX
extends RefCounted
## What a great gust carries (Gusts.emit with fx, the cinematic pass): real leaves torn from the crowns round it,
## whirled up and out and drifting down; the leaf litter of the ground skittering out from it; a skirt of dust.
## One-shot bursts that free themselves. The leaves are scanned (ambientCG LeafSet009, CC0; tools/textures/
## leaf_particles.py) and tumble in 3D (shaders/nature/leaf_particle.gdshader).

const LEAF_TEX := "res://assets/nature/real/leaf_particles.png"
static var _cache := {}


static func leaf_mesh(size := 0.1) -> QuadMesh:
	var key := "leaf:%s" % size
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/nature/leaf_particle.gdshader")
		m.set_shader_parameter("leaf_tex", load(LEAF_TEX))
		var q := QuadMesh.new()
		q.size = Vector2(size, size * 1.5)
		q.material = m
		_cache[key] = q
	return _cache[key]


static func gust_fx(host: Node, pos: Vector3, radius: float, strength: float, fx: Dictionary) -> void:
	if host == null or not host.is_inside_tree() or not ResourceLoader.exists(LEAF_TEX):
		return
	var gy := float(fx.get("ground_y", pos.y))
	var k := clampf(strength, 0.2, 2.0)
	var n_torn := int(fx.get("leaves", 0))
	if n_torn > 0:
		var torn := FX.particles(n_torn, 6.5, FX.process("wind:torn", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = 13.0
			pm.emission_ring_inner_radius = 6.0
			pm.emission_ring_height = 7.0
			pm.direction = Vector3.UP
			pm.spread = 40.0
			pm.initial_velocity_min = 0.5
			pm.initial_velocity_max = 2.0
			pm.radial_velocity_min = 2.0
			pm.radial_velocity_max = 5.0
			pm.gravity = Vector3(0, -1.1, 0)
			pm.damping_min = 0.5
			pm.damping_max = 1.0
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 2.5
			pm.turbulence_noise_scale = 4.0
			pm.turbulence_influence_min = 0.05
			pm.turbulence_influence_max = 0.15
			pm.scale_min = 0.8
			pm.scale_max = 1.3
			pm.color_ramp = FX.ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.8, 1.0])
			pm.color_initial_ramp = FX.ramp([Color(0.82, 0.95, 0.7), Color(1.0, 1.0, 0.85), Color(0.9, 0.85, 0.55), Color(0.75, 0.9, 0.62)])), leaf_mesh(0.11))
		torn.one_shot = true
		torn.explosiveness = 0.75
		torn.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
		host.add_child(torn)
		torn.global_position = Vector3(pos.x, gy + 11.0, pos.z)
		torn.scale = Vector3.ONE * clampf(radius / 30.0, 0.5, 1.4)
		torn.speed_scale = 0.85 + 0.25 * k
		torn.emitting = true
		torn.finished.connect(torn.queue_free)
	var n_litter := int(fx.get("litter", 0))
	if n_litter > 0:
		var litter := FX.particles(n_litter, 2.4, FX.process("wind:litter", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = 5.0
			pm.emission_ring_inner_radius = 1.2
			pm.emission_ring_height = 0.05
			pm.direction = Vector3.UP
			pm.spread = 25.0
			pm.initial_velocity_min = 0.8
			pm.initial_velocity_max = 3.0
			pm.radial_velocity_min = 5.0
			pm.radial_velocity_max = 10.0
			pm.gravity = Vector3(0, -7.0, 0)
			pm.damping_min = 1.5
			pm.damping_max = 3.0
			pm.scale_min = 0.7
			pm.scale_max = 1.2
			pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
			pm.collision_bounce = 0.15
			pm.collision_friction = 0.6
			pm.color_ramp = FX.ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.75, 1.0])
			pm.color_initial_ramp = FX.ramp([Color(0.62, 0.45, 0.28), Color(0.85, 0.7, 0.42), Color(0.55, 0.42, 0.3), Color(0.78, 0.82, 0.5)])), leaf_mesh(0.09))
		litter.one_shot = true
		litter.explosiveness = 0.85
		litter.collision_base_size = 0.02
		litter.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 15, 60))
		var c := GPUParticlesCollisionBox3D.new()
		c.size = Vector3(radius * 1.6, 2.0, radius * 1.6)
		host.add_child(c)
		c.global_position = Vector3(pos.x, gy - 1.0, pos.z)
		host.add_child(litter)
		litter.global_position = Vector3(pos.x, gy + 0.12, pos.z)
		litter.speed_scale = 0.8 + 0.3 * k
		litter.emitting = true
		var done := func() -> void:
			litter.queue_free()
			c.queue_free()
		litter.finished.connect(done)
	if bool(fx.get("dust", false)):
		FireFX.dust_ring(host, Vector3(pos.x, gy, pos.z), clampf(radius / 22.0, 0.45, 1.3), k)
