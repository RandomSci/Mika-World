class_name FX
extends RefCounted
## Shared, cached building blocks for spell and reaction effects: draw materials, particle process
## materials and meshes are created once per (element, kind) and reused by every cast, so effects
## never recompile shaders or rebuild resources mid-spell (no hitches, low allocation).

static var _cache := {}
static var _noise: NoiseTexture2D

const PALETTES := {
	"arcane": [Color(0.42, 0.66, 1.0), Color(0.74, 0.46, 1.0)],
	"wind": [Color(0.75, 1.0, 0.88), Color(0.55, 0.9, 0.75)],
	"water": [Color(0.4, 0.78, 1.0), Color(0.75, 0.95, 1.0)],
	"fire": [Color(1.0, 0.55, 0.15), Color(1.0, 0.85, 0.4)],
	"rune": [Color(0.55, 0.85, 1.0), Color(0.95, 0.85, 0.5)],
	"self": [Color(0.95, 0.85, 0.55), Color(0.6, 0.8, 1.0)],
	"mist": [Color(0.8, 0.92, 1.0), Color(0.6, 0.85, 0.95)],
	"umbral": [Color(1.0, 0.76, 0.3), Color(0.55, 0.25, 0.95)],
	"eclipse": [Color(1.0, 0.86, 0.5), Color(0.62, 0.42, 1.0)],
	"bloom": [Color(1.0, 0.82, 0.93), Color(0.72, 0.9, 1.0)],
}


static func noise() -> NoiseTexture2D:
	if _noise == null:
		_noise = NoiseTexture2D.new()
		_noise.seamless = true
		_noise.width = 256
		_noise.height = 256
		var fn := FastNoiseLite.new()
		fn.frequency = 0.03
		fn.fractal_octaves = 3
		_noise.noise = fn
	return _noise


static func palette(element: String) -> Array:
	return PALETTES.get(element, PALETTES.arcane)


## Additive glowing mote quad (energy_mote shader); colour comes from the particle colour ramp.
static func mote_mesh(size: float, trail := false) -> QuadMesh:
	var key := "mote:%s:%s" % [size, trail]
	if not _cache.has(key):
		var q := QuadMesh.new()
		q.size = Vector2(size, size * (4.0 if trail else 1.0))
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/magic/energy_mote.gdshader")
		sm.set_shader_parameter("hdr_boost", 4.0)
		sm.set_shader_parameter("trail_mode", trail)
		q.material = sm
		_cache[key] = q
	return _cache[key]


static func puff_mesh(size: float) -> QuadMesh:
	var key := "puff:%s" % size
	if not _cache.has(key):
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/magic/smoke_puff.gdshader")
		sm.set_shader_parameter("noise_tex", noise())
		q.material = sm
		_cache[key] = q
	return _cache[key]


static func ramp(colors: Array, offsets: Array = []) -> GradientTexture1D:
	var key := "ramp:%s:%s" % [str(colors), str(offsets)]
	if not _cache.has(key):
		var g := Gradient.new()
		if offsets.is_empty():
			for i in colors.size():
				offsets.append(float(i) / maxf(colors.size() - 1, 1))
		g.offsets = PackedFloat32Array(offsets)
		g.colors = PackedColorArray(colors)
		var t := GradientTexture1D.new()
		t.gradient = g
		_cache[key] = t
	return _cache[key]


## Particle process material: shape, direction, velocities, gravity, radial pull, colour ramp.
static func process(key: String, build: Callable) -> ParticleProcessMaterial:
	if not _cache.has("pm:" + key):
		var pm := ParticleProcessMaterial.new()
		build.call(pm)
		_cache["pm:" + key] = pm
	return _cache["pm:" + key]


static func particles(amount: int, lifetime: float, pm: ParticleProcessMaterial, mesh: Mesh, local := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var scale: float = RenderProfile.get_setting("particle_scale")
	p.amount = maxi(4, int(amount * scale))
	p.lifetime = lifetime
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.local_coords = local
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-5, -3, -5), Vector3(10, 8, 10))
	return p


## A one-shot burst at a point; frees itself.
static func burst(parent: Node, pos: Vector3, amount: int, lifetime: float, pm: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var p := particles(amount, lifetime, pm, mesh)
	p.one_shot = true
	p.explosiveness = 0.92
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func light(col: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 1.0
	l.light_specular = 0.4
	return l


## Shader-material quad lying flat (ground sigils) or upright (rune glyph).
static func quad(shader: String, size: float, params: Dictionary, flat := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if flat:
		var pm := PlaneMesh.new()
		pm.size = Vector2(size, size)
		mi.mesh = pm
	else:
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load(shader)
	for k in params:
		m.set_shader_parameter(k, params[k])
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Common process-material presets -----------------------------------------------------------
static func pm_motes(element: String, kind: String) -> ParticleProcessMaterial:
	var pal := palette(element)
	return process("%s:%s" % [element, kind], func(pm: ParticleProcessMaterial):
		pm.gravity = Vector3.ZERO
		pm.damping_min = 0.5
		pm.damping_max = 1.5
		pm.scale_min = 0.5
		pm.scale_max = 1.3
		pm.color_ramp = ramp([Color(pal[1], 0.0), Color(pal[0].lerp(Color.WHITE, 0.3), 1.0), Color(pal[1], 0.6), Color(pal[0], 0.0)], [0.0, 0.2, 0.7, 1.0])
		match kind:
			"gather":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
				pm.emission_sphere_radius = 1.2
				pm.radial_accel_min = -6.0
				pm.radial_accel_max = -8.0
			"swirl":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				pm.emission_ring_radius = 0.35
				pm.emission_ring_inner_radius = 0.25
				pm.emission_ring_height = 0.05
				pm.emission_ring_axis = Vector3.UP
				pm.tangential_accel_min = 6.0
				pm.tangential_accel_max = 9.0
				pm.direction = Vector3.UP
				pm.spread = 15.0
				pm.initial_velocity_min = 0.3
				pm.initial_velocity_max = 0.8
			"trail":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 0.06
				pm.spread = 180.0
				pm.initial_velocity_min = 0.0
				pm.initial_velocity_max = 0.25
			"burst":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 0.15
				pm.spread = 180.0
				pm.initial_velocity_min = 2.0
				pm.initial_velocity_max = 5.5
				pm.gravity = Vector3(0, -2.0, 0)
				pm.damping_min = 2.0
				pm.damping_max = 3.5
			"rise":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				pm.emission_ring_radius = 1.2
				pm.emission_ring_inner_radius = 0.9
				pm.emission_ring_height = 0.05
				pm.emission_ring_axis = Vector3.UP
				pm.direction = Vector3.UP
				pm.spread = 10.0
				pm.initial_velocity_min = 0.4
				pm.initial_velocity_max = 1.0
			"splash":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = 0.2
				pm.direction = Vector3.UP
				pm.spread = 40.0
				pm.initial_velocity_min = 2.0
				pm.initial_velocity_max = 4.0
				pm.gravity = Vector3(0, -9.0, 0)
	)


static func pm_puff(kind: String) -> ParticleProcessMaterial:
	return process("puff:" + kind, func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.2
		pm.direction = Vector3.UP
		pm.spread = 25.0
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 1.1
		pm.gravity = Vector3(0, 0.25, 0)
		pm.damping_min = 0.4
		pm.damping_max = 0.9
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		var sc := CurveTexture.new()
		var c := Curve.new()
		c.add_point(Vector2(0, 0.4)); c.add_point(Vector2(1, 1.6))
		sc.curve = c
		pm.scale_curve = sc
		match kind:
			"steam":
				pm.color_ramp = ramp([Color(0.95, 0.97, 1.0, 0.0), Color(0.97, 0.98, 1.0, 0.75), Color(0.9, 0.93, 0.97, 0.0)], [0.0, 0.12, 1.0])
				pm.initial_velocity_max = 1.6
			"smoke":
				pm.color_ramp = ramp([Color(0.25, 0.24, 0.23, 0.0), Color(0.3, 0.29, 0.28, 0.5), Color(0.35, 0.34, 0.33, 0.0)], [0.0, 0.2, 1.0])
			"mist":
				pm.color_ramp = ramp([Color(0.85, 0.92, 1.0, 0.0), Color(0.88, 0.94, 1.0, 0.5), Color(0.85, 0.9, 0.97, 0.0)], [0.0, 0.25, 1.0])
				pm.emission_sphere_radius = 0.8
				pm.initial_velocity_max = 0.5
				pm.gravity = Vector3(0, 0.05, 0)
			"dust":
				pm.color_ramp = ramp([Color(0.6, 0.55, 0.45, 0.0), Color(0.62, 0.58, 0.5, 0.35), Color(0.6, 0.56, 0.5, 0.0)], [0.0, 0.2, 1.0])
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				pm.emission_ring_radius = 0.6
				pm.emission_ring_inner_radius = 0.2
				pm.emission_ring_height = 0.05
				pm.emission_ring_axis = Vector3.UP
				pm.radial_accel_min = 2.0
				pm.radial_accel_max = 3.0
	)


static func clear() -> void:
	_cache.clear()
