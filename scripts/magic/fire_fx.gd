class_name FireFX
extends RefCounted
## REAL FIRE (the cinematic pass, 2026-10-14 - the developer: "the attack looks so simple ... MAKE IT CINEMATIC, NOT
## CARTOONISH"). Building blocks over the simulated flipbooks (tools/vfx/fire_flipbooks.py: Mantaflow gas sims
## rendered volumetrically; shaders/vfx/flipbook.gdshader): a detonation (fireball, flung fire, rising smoke,
## dust ring, shock ring, debris on ballistic arcs that land, a scorch that glows and cools, fires left burning,
## heat haze, a flash that lights the forest, a gust that bends it), a fire burst, a fire trail, burning ground, a
## fire tornado. Materials and meshes are cached (no shader compiles mid-effect); every effect frees itself.

const DIR := "res://assets/vfx/fire/"
const SHADER := "res://shaders/vfx/flipbook.gdshader"
const HAZE := "res://shaders/vfx/heat_haze.gdshader"
static var _meta := {}
static var _cache := {}


static func meta(kind: String) -> Dictionary:
	if _meta.is_empty():
		var p := DIR + "flipbooks.json"
		if FileAccess.file_exists(p):
			_meta = JSON.parse_string(FileAccess.get_file_as_string(p))
	return _meta.get(kind, {})


static func available() -> bool:
	return has("explosion")


## Is this flipbook packed and imported? (a missing one draws nothing rather than a blank card)
static func has(kind: String) -> bool:
	return not meta(kind).is_empty() and ResourceLoader.exists(DIR + kind + "_smoke.png")


static func _black() -> Texture2D:
	if not _cache.has("black"):
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color.BLACK)
		_cache["black"] = ImageTexture.create_from_image(img)
	return _cache["black"]


## The flipbook material for `kind`. opts: particles (true), upright, loop_fps, fire_gain, fire_tint, smoke_gain,
## smoke_tint, smoke_alpha, soft, billboard.
static func mat(kind: String, opts := {}) -> ShaderMaterial:
	var key := "mat:%s:%s" % [kind, str(opts)]
	if _cache.has(key):
		return _cache[key]
	var md := meta(kind)
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("smoke_tex", load(DIR + kind + "_smoke.png"))
	m.set_shader_parameter("fire_tex", load(DIR + kind + "_fire.png") if bool(md.get("fire", false)) else _black())
	m.set_shader_parameter("grid", Vector2(float(md.get("cols", 8)), float(md.get("rows", 8))))
	m.set_shader_parameter("frames", float(md.get("frames", 64)))
	m.set_shader_parameter("fire_scale", float(md.get("fire_scale", 4.0)))
	m.set_shader_parameter("particles", bool(opts.get("particles", true)))
	m.set_shader_parameter("upright", bool(opts.get("upright", false)))
	m.set_shader_parameter("billboard", bool(opts.get("billboard", true)))
	m.set_shader_parameter("loop_fps", float(opts.get("loop_fps", 0.0)))
	m.set_shader_parameter("fire_gain", float(opts.get("fire_gain", 1.6)))
	m.set_shader_parameter("fire_tint", opts.get("fire_tint", Color(1, 1, 1)))
	m.set_shader_parameter("smoke_gain", float(opts.get("smoke_gain", 1.0)))
	m.set_shader_parameter("smoke_tint", opts.get("smoke_tint", Color(1, 1, 1)))
	m.set_shader_parameter("smoke_alpha", float(opts.get("smoke_alpha", 1.0)))
	m.set_shader_parameter("soft", float(opts.get("soft", 0.8)))
	_cache[key] = m
	return m


## A card of `kind` at `scale` (its simulated size in metres x scale), its pivot (the sim's emitter) at the origin.
static func quad(kind: String, scale: float, opts := {}) -> QuadMesh:
	if not has(kind):
		return null
	var key := "quad:%s:%s:%s" % [kind, snappedf(scale, 0.01), str(opts)]
	if _cache.has(key):
		return _cache[key]
	var md := meta(kind)
	var sz: Array = md.get("size_m", [4.0, 4.0])
	var pv: Array = md.get("pivot", [0.5, 0.5])
	var q := QuadMesh.new()
	q.size = Vector2(float(sz[0]), float(sz[1])) * scale
	q.center_offset = Vector3((0.5 - float(pv[0])) * q.size.x, (float(pv[1]) - 0.5) * q.size.y, 0.0)
	q.material = mat(kind, opts)
	_cache[key] = q
	return q


static func _ground(host: Node, at: Vector3) -> float:
	if host != null and host.has_method("ground_at"):
		return float(host.ground_at(at.x, at.z))
	return at.y - 1.0


## One flipbook played once on a card (not particles): frame_t runs 0..1 over `seconds` (eased: a blast is fast
## then slow), then it frees itself. delay: seconds before it appears.
static func card(host: Node, kind: String, at: Vector3, scale: float, seconds: float, opts := {}, delay := 0.0, spin := 0.0) -> MeshInstance3D:
	var o := opts.duplicate()
	o["particles"] = false
	var mi := MeshInstance3D.new()
	mi.mesh = quad(kind, scale, o)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 8.0 * scale
	host.add_child(mi)
	mi.global_position = at
	mi.set_instance_shader_parameter("frame_t", 0.0)
	mi.set_instance_shader_parameter("spin", spin)
	mi.set_instance_shader_parameter("fade", 0.0 if delay > 0.0 else 1.0)
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func(): mi.set_instance_shader_parameter("fade", 1.0))
	var ease_out := bool(opts.get("ease_out", true))
	var t := tw.tween_method(func(v: float): mi.set_instance_shader_parameter("frame_t", v), 0.0, 1.0, seconds)
	if ease_out:
		t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)
	return mi


## Particles of `kind` (each particle plays the flipbook over its life).
static func particles(kind: String, amount: int, life: float, scale: float, pm: ParticleProcessMaterial, opts := {}) -> GPUParticles3D:
	var o := opts.duplicate()
	o["particles"] = true
	var p := GPUParticles3D.new()
	p.amount = maxi(2, int(amount * float(RenderProfile.get_setting("particle_scale"))))
	p.lifetime = life
	p.process_material = pm
	p.draw_pass_1 = quad(kind, scale, o)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 40, 60))
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	return p


static func _pm(key: String, build: Callable) -> ParticleProcessMaterial:
	return FX.process("firefx:" + key, build)


static func light(host: Node, at: Vector3, col: Color, energy: float, rng: float, seconds: float, shadows := false) -> OmniLight3D:
	var l := FX.light(col, energy * float(RenderProfile.get_setting("magic_light_scale")), rng)
	l.shadow_enabled = shadows
	host.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, seconds).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)
	return l


## Heat shimmer over fire (mode 0) or a ring of shocked air racing out (mode 1). Frees itself.
static func haze(host: Node, at: Vector3, size: float, strength: float, seconds: float, ring := false) -> MeshInstance3D:
	var key := "haze:%s" % ring
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(HAZE)
		m.set_shader_parameter("noise_tex", FX.noise())
		m.set_shader_parameter("mode", 1 if ring else 0)
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		q.material = m
		_cache[key] = q
	var mi := MeshInstance3D.new()
	mi.mesh = _cache[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = size
	host.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * size
	mi.set_instance_shader_parameter("strength", strength)
	var tw := mi.create_tween().set_parallel(true)
	if ring:
		mi.set_instance_shader_parameter("ring", 0.05)
		tw.tween_method(func(v: float): mi.set_instance_shader_parameter("ring", v), 0.05, 0.95, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: float): mi.set_instance_shader_parameter("strength", v), strength, 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		tw.tween_method(func(v: float): mi.set_instance_shader_parameter("strength", v), strength, 0.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)
	return mi


# ------------------------------------------------------------------ the detonation
## A great fiery detonation at `at` (s = 1: a fireball ~7 m across). Lights, shakes and bends the world.
static func explosion(host: Node, at: Vector3, s := 1.0, opts := {}) -> void:
	if host == null or not host.is_inside_tree():
		return
	var gy := _ground(host, at)
	var low := at.y - gy < 3.0 * s
	# the flash: the forest lit by it for an instant, shadows thrown
	light(host, at + Vector3(0, 0.8, 0), Color(1.0, 0.62, 0.3), 18.0 * s, 30.0 * s, 1.1, true)
	light(host, at + Vector3(0, 2.5, 0), Color(1.0, 0.45, 0.16), 9.0 * s, 18.0 * s, 3.2)
	# the fireball: three simulated blasts layered at different sizes, spins and beats (it reads as a volume)
	if available():
		card(host, "explosion", at + Vector3(0, -0.3, 0) * s, 1.6 * s, 2.7, {"fire_gain": 1.3, "fire_tint": Color(1.0, 0.7, 0.42), "smoke_gain": 2.4, "smoke_alpha": 0.8, "soft": 2.2}, 0.0, 0.0)
		card(host, "explosion", at + Vector3(0.5, 0.15, 0.3) * s, 1.25 * s, 2.4, {"fire_gain": 1.4, "fire_tint": Color(1.0, 0.7, 0.42), "smoke_gain": 2.2, "smoke_alpha": 0.75, "soft": 2.2}, 0.05, 2.4)
		card(host, "explosion", at + Vector3(-0.45, 0.35, -0.2) * s, 1.0 * s, 2.1, {"fire_gain": 1.5, "fire_tint": Color(1.0, 0.7, 0.42), "smoke_gain": 2.0, "smoke_alpha": 0.7, "soft": 2.2}, 0.1, -2.0)
		# tongues of fire flung outward
		var flung := particles("burst", 18, 1.1, 1.05 * s, _pm("flung", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.6
			pm.direction = Vector3.UP
			pm.spread = 180.0
			pm.initial_velocity_min = 7.0
			pm.initial_velocity_max = 13.0
			pm.damping_min = 5.0
			pm.damping_max = 9.0
			pm.gravity = Vector3(0, 1.5, 0)
			pm.angle_min = -40.0
			pm.angle_max = 40.0
			pm.scale_min = 0.7
			pm.scale_max = 1.3), {"fire_gain": 1.4, "fire_tint": Color(1.0, 0.7, 0.42)})
		_one_shot(host, flung, at)
		# the smoke that rises after it
		var smoke := particles("smoke", 9, 4.6, 1.5 * s, _pm("rising_smoke", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 1.4
			pm.direction = Vector3.UP
			pm.spread = 25.0
			pm.initial_velocity_min = 1.2
			pm.initial_velocity_max = 2.6
			pm.gravity = Vector3(0, 0.6, 0)
			pm.damping_min = 0.3
			pm.damping_max = 0.6
			pm.angle_min = -30.0
			pm.angle_max = 30.0
			pm.scale_min = 0.8
			pm.scale_max = 1.4), {"smoke_tint": Color(0.56, 0.53, 0.5), "smoke_alpha": 0.42})
		_one_shot(host, smoke, at + Vector3(0, 0.6, 0), 0.4)
	else:
		PhoenixNova.explode_simple(host, at, s)
	haze(host, at + Vector3(0, 1.8, 0), 13.0 * s, 1.0, 3.4)
	if low:
		var g := Vector3(at.x, gy, at.z)
		haze(host, g + Vector3(0, 0.6, 0), 26.0 * s, 1.4, 0.9, true)
		dust_ring(host, g, 1.4 * s, 1.0 * s)
		scorch(host, g, 3.4 * s)
		debris(host, g, s)
		var n := int(opts.get("fires", 5))
		for i in n:
			var ang := TAU * (float(i) + randf() * 0.6) / float(n)
			var r := randf_range(1.0, 3.2) * s
			var p := g + Vector3(cos(ang) * r, 0, sin(ang) * r)
			p.y = _ground(host, p)
			ground_fire(host, p, randf_range(0.45, 0.8) * s, randf_range(4.5, 7.5), i == 0)
	sparks(host, at, s)
	Gusts.emit(host, Vector3(at.x, gy, at.z), 34.0 * s, 1.5 * s, 0.5, 1.05, {"leaves": int(70 * s), "litter": int(90 * s) if low else 0, "dust": false, "ground_y": gy})
	ImpactFX.shake(host, 0.16 * s, 0.9)


static func _one_shot(host: Node, p: GPUParticles3D, at: Vector3, explosiveness := 0.9) -> void:
	p.one_shot = true
	p.explosiveness = explosiveness
	host.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


## Embers and sparks flung out on ballistic arcs, bouncing where they land.
static func sparks(host: Node, at: Vector3, s := 1.0) -> void:
	var pm := _pm("sparks", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.7
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 5.0
		pm.initial_velocity_max = 16.0
		pm.gravity = Vector3(0, -9.0, 0)
		pm.damping_min = 0.3
		pm.damping_max = 1.0
		pm.scale_min = 0.4
		pm.scale_max = 1.2
		pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		pm.collision_bounce = 0.35
		pm.collision_friction = 0.4
		pm.color_ramp = FX.ramp([Color(1, 0.95, 0.75, 1), Color(1, 0.6, 0.18, 1), Color(0.9, 0.25, 0.04, 0.9), Color(0.4, 0.06, 0.0, 0)], [0.0, 0.3, 0.75, 1.0]))
	var p := FX.particles(int(160 * s), 2.2, pm, FX.mote_mesh(0.07, true))
	p.collision_base_size = 0.05
	_ground_collider(host, at, 24.0 * s)
	_one_shot(host, p, at)


static func _ground_collider(host: Node, at: Vector3, size: float) -> void:
	var gy := _ground(host, at)
	var c := GPUParticlesCollisionBox3D.new()
	c.size = Vector3(size, 2.0, size)
	host.add_child(c)
	c.global_position = Vector3(at.x, gy - 1.0, at.z)
	var tw := c.create_tween()
	tw.tween_interval(6.0)
	tw.tween_callback(c.queue_free)


## Clods of earth and stone thrown up, tumbling on real arcs and landing (they bounce and roll a little).
static func debris(host: Node, g: Vector3, s := 1.0) -> void:
	if not _cache.has("debris_mesh"):
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 0.8
		sm.radial_segments = 6
		sm.rings = 3
		var m := StandardMaterial3D.new()
		m.albedo_texture = RealKit.ph_tex("rock_pitted_mossy", "diff") if RealKit.enabled() else null
		m.albedo_color = Color(0.62, 0.55, 0.47)
		m.roughness = 0.95
		m.vertex_color_use_as_albedo = false
		sm.material = m
		_cache["debris_mesh"] = sm
	var pm := _pm("debris", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 1.2
		pm.direction = Vector3.UP
		pm.spread = 55.0
		pm.initial_velocity_min = 5.0
		pm.initial_velocity_max = 12.0
		pm.gravity = Vector3(0, -12.0, 0)
		pm.scale_min = 0.05
		pm.scale_max = 0.2
		pm.angular_velocity_min = -540.0
		pm.angular_velocity_max = 540.0
		pm.particle_flag_rotate_y = true
		pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		pm.collision_bounce = 0.22
		pm.collision_friction = 0.75
		pm.collision_use_scale = true)
	var p := GPUParticles3D.new()
	p.amount = int(34 * s)
	p.lifetime = 3.4
	p.process_material = pm
	p.draw_pass_1 = _cache["debris_mesh"]
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	p.visibility_aabb = AABB(Vector3(-20, -4, -20), Vector3(40, 24, 40))
	p.collision_base_size = 0.2
	_ground_collider(host, g, 30.0 * s)
	_one_shot(host, p, g + Vector3(0, 0.4, 0), 0.96)


## Dust and grit driven out along the ground in a ring (the blast's skirt).
static func dust_ring(host: Node, g: Vector3, s := 1.0, power := 1.0) -> void:
	if not available():
		return
	var p := particles("smoke", int(22 * s), 2.6, 0.55 * s, _pm("dust_ring", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = 1.6
		pm.emission_ring_inner_radius = 0.8
		pm.emission_ring_height = 0.1
		pm.direction = Vector3(1, 0, 0)
		pm.spread = 180.0
		pm.flatness = 1.0
		pm.initial_velocity_min = 0.0
		pm.initial_velocity_max = 0.0
		pm.radial_velocity_min = 7.0
		pm.radial_velocity_max = 12.0
		pm.damping_min = 3.5
		pm.damping_max = 5.5
		pm.gravity = Vector3(0, 0.35, 0)
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.scale_min = 0.7
		pm.scale_max = 1.3), {"smoke_tint": Color(0.78, 0.68, 0.55), "smoke_gain": 1.05, "smoke_alpha": 0.55 * clampf(power, 0.3, 1.0)})
	_one_shot(host, p, g + Vector3(0, 0.25, 0), 0.95)


## The scorched ground: a burnt patch whose cracks glow and cool, then fades.
static func scorch(host: Node, g: Vector3, radius: float) -> void:
	if not _cache.has("scorch"):
		var n := FastNoiseLite.new()
		n.frequency = 0.045
		n.fractal_octaves = 4
		var cell := FastNoiseLite.new()
		cell.noise_type = FastNoiseLite.TYPE_CELLULAR
		cell.frequency = 0.06
		cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
		var alb := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		var emi := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				var d := Vector2(x - 128, y - 128).length() / 128.0
				var nn := n.get_noise_2d(x, y) * 0.5 + 0.5
				var a := clampf((1.0 - d * (0.85 + 0.3 * nn)) * 1.6, 0.0, 1.0)
				alb.set_pixel(x, y, Color(0.035, 0.028, 0.022, a * 0.92))
				var crack := 1.0 - clampf(absf(cell.get_noise_2d(x, y)) * 4.0, 0.0, 1.0)
				var glow := pow(crack, 3.0) * clampf(1.0 - d * 1.15, 0.0, 1.0) * (0.6 + 0.8 * nn)
				emi.set_pixel(x, y, Color(1.0, 0.36, 0.06) * glow)
		alb.generate_mipmaps()
		emi.generate_mipmaps()
		_cache["scorch"] = [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(emi)]
	var d := Decal.new()
	d.texture_albedo = _cache["scorch"][0]
	d.texture_emission = _cache["scorch"][1]
	d.emission_energy = 6.0
	d.size = Vector3(radius * 2.0, 3.0, radius * 2.0)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	host.add_child(d)
	d.global_position = g
	d.rotation.y = randf() * TAU
	var tw := d.create_tween()
	tw.tween_property(d, "emission_energy", 0.0, 7.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(6.0)
	tw.tween_property(d, "modulate:a", 0.0, 5.0)
	tw.tween_callback(d.queue_free)


## Fire left burning on the ground: real looping flames (two cards), its light flickering, smoke rising off it; it
## burns `seconds` then dies down. `sound`: the crackle of it.
static func ground_fire(host: Node, g: Vector3, s: float, seconds: float, sound := false) -> Node3D:
	var root := Node3D.new()
	root.name = "GroundFire"
	host.add_child(root)
	root.global_position = g
	if available():
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = quad("flame", s * (1.0 if k == 0 else 0.8), {"particles": false, "upright": true, "loop_fps": 30.0, "fire_gain": 1.25, "fire_tint": Color(1.0, 0.7, 0.42), "soft": 0.4})
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(randf_range(-0.2, 0.2), -0.05, randf_range(-0.2, 0.2)) * s
			mi.set_instance_shader_parameter("phase", randf())
			mi.set_instance_shader_parameter("fade", 0.0)
			root.add_child(mi)
		var smoke := particles("smoke", 5, 3.6, 0.45 * s, _pm("fire_smoke", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.3
			pm.direction = Vector3.UP
			pm.spread = 12.0
			pm.initial_velocity_min = 0.9
			pm.initial_velocity_max = 1.6
			pm.gravity = Vector3(0.25, 0.4, 0.1)
			pm.angle_min = -40.0
			pm.angle_max = 40.0
			pm.scale_min = 0.8
			pm.scale_max = 1.3), {"smoke_tint": Color(0.4, 0.38, 0.36), "smoke_alpha": 0.4})
		smoke.position = Vector3(0, 1.2 * s, 0)
		root.add_child(smoke)
		smoke.emitting = true
	var l := FX.light(Color(1.0, 0.55, 0.2), 0.0, 6.0 * maxf(s, 0.5))
	l.position = Vector3(0, 0.8 * s, 0)
	root.add_child(l)
	var player: AudioStreamPlayer3D = null
	if sound and ResourceLoader.exists("res://assets/audio/synth/phoenix_fire_burn_loop.ogg"):
		player = AudioStreamPlayer3D.new()
		var st := (load("res://assets/audio/synth/phoenix_fire_burn_loop.ogg") as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		st.loop = true
		player.stream = st
		player.bus = "SFX"
		player.unit_size = 8.0
		player.volume_db = -4.0
		root.add_child(player)
		player.play()
	var mls := float(RenderProfile.get_setting("magic_light_scale"))
	var burn := func(v: float) -> void:
		var life := clampf(minf(v / 0.4, (seconds - v) / 1.6), 0.0, 1.0)
		for c in root.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).set_instance_shader_parameter("fade", life)
				(c as MeshInstance3D).scale = Vector3.ONE * (0.55 + 0.45 * life)
		l.light_energy = (2.2 + 0.7 * sin(v * 23.0) + 0.5 * sin(v * 37.0 + 1.3)) * life * mls * s
		if player:
			player.volume_db = -4.0 + linear_to_db(maxf(life, 0.001))
	var stop_smoke := func() -> void:
		for c in root.get_children():
			if c is GPUParticles3D:
				(c as GPUParticles3D).emitting = false
	var tw := root.create_tween()
	tw.tween_method(burn, 0.0, seconds, seconds)
	tw.tween_callback(stop_smoke)
	tw.tween_interval(3.8)
	tw.tween_callback(root.queue_free)
	return root


## A trail of fire behind something moving (world space): rolling fire puffs, then smoke. Returns the emitters
## (set emitting = false to stop; they free themselves via `free_after`).
static func trail(host: Node, s := 1.0) -> Array:
	var out := []
	if not available():
		return out
	var fire := particles("burst", 110, 0.9, 0.75 * s, _pm("trail_fire", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.35
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 0.3
		pm.initial_velocity_max = 1.4
		pm.gravity = Vector3(0, 2.2, 0)
		pm.damping_min = 0.8
		pm.damping_max = 1.6
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.scale_min = 0.7
		pm.scale_max = 1.25), {"fire_gain": 1.5, "fire_tint": Color(1.0, 0.7, 0.42)})
	var smoke := particles("smoke", 40, 2.4, 0.42 * s, _pm("trail_smoke", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.3
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.8
		pm.gravity = Vector3(0, 0.9, 0)
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.scale_min = 0.6
		pm.scale_max = 1.1), {"smoke_tint": Color(0.5, 0.47, 0.45), "smoke_alpha": 0.4})
	for p in [fire, smoke]:
		host.add_child(p)
		p.emitting = false
		out.append(p)
	return out


static func free_after(p: Node, seconds: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	var tw := p.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(p.queue_free)


## A fire tornado: real simulated fire vortices (upright cards, each its own phase) wound round a column, flames
## climbing it, a light inside. strength 0..1 is set by the caller (grow, roar, collapse); free it when done.
static func vortex(host: Node, at: Vector3, s := 1.0) -> FireVortex:
	var v := FireVortex.new()
	host.add_child(v)
	v.global_position = at
	v.build(s)
	return v


## A ring of fire on the ground round `g` (the transformation's circle): real flames catch one after another round
## it over `ignite` seconds and burn until free_ring() / `seconds`. Returns the root (free it to put it out early).
static func ring_of_fire(host: Node, g: Vector3, radius: float, seconds: float, ignite := 0.8, s := 0.55) -> Node3D:
	var root := Node3D.new()
	root.name = "RingOfFire"
	host.add_child(root)
	root.global_position = g
	var n := int(clampf(radius * 3.2, 8.0, 22.0))
	for i in n:
		var a := TAU * float(i) / float(n)
		var p := g + Vector3(cos(a), 0.0, sin(a)) * radius
		p.y = _ground(host, p)
		var f := ground_fire(root, p, s * randf_range(0.85, 1.15), seconds - ignite * float(i) / float(n), i % 4 == 0)
		f.visible = false
		var tw := f.create_tween()
		tw.tween_interval(ignite * float(i) / float(n))
		tw.tween_callback(func(): f.visible = true)
	light(host, g + Vector3(0, 1.2, 0), Color(1.0, 0.55, 0.2), 3.5, radius * 3.0, seconds)
	return root


## Phantom WINGS OF FIRE unfolding behind her (her final pose; the Phoenix within the woman): simulated flames laid
## along two wing-shaped arcs that open upward and out from her shoulders, blaze, and burn away. yaw: her facing.
static func fire_wings(host: Node, at: Vector3, yaw: float, span := 3.4, seconds := 2.4) -> Node3D:
	var root := Node3D.new()
	root.name = "FireWings"
	host.add_child(root)
	root.global_position = at
	root.rotation.y = yaw
	if not available():
		return root
	var cards: Array[MeshInstance3D] = []
	for sd in [-1.0, 1.0]:
		var side := float(sd)
		for i in 9:
			var u := float(i) / 8.0
			# an arc rising from the shoulder blade out to the tip, swept back
			var x := side * (0.25 + span * u)
			var y := 0.2 + 1.5 * sin(u * PI * 0.62) - 0.35 * u * u
			var z := -0.35 - 0.5 * u
			var mi := MeshInstance3D.new()
			mi.mesh = quad("flame", 0.42 + 0.22 * (1.0 - u), {"particles": false, "upright": false, "loop_fps": 34.0, "fire_gain": 1.4, "fire_tint": Color(1.0, 0.7, 0.42), "smoke_alpha": 0.15, "soft": 0.3})
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(x, y, z)
			mi.set_instance_shader_parameter("phase", randf())
			mi.set_instance_shader_parameter("spin", -side * (0.5 + 0.7 * u))
			mi.set_instance_shader_parameter("fade", 0.0)
			mi.set_meta("u", u)
			root.add_child(mi)
			cards.append(mi)
	var l := FX.light(Color(1.0, 0.55, 0.22), 0.0, 9.0)
	l.position = Vector3(0, 1.0, -0.6)
	root.add_child(l)
	var mls := float(RenderProfile.get_setting("magic_light_scale"))
	var unfold := func(v: float) -> void:
		for c in cards:
			var u := float(c.get_meta("u"))
			var open := clampf((v * 1.6 - u * 0.6) / 0.6, 0.0, 1.0)       # they open from the shoulder outward
			var life := open * clampf((seconds - v * seconds) / 0.8, 0.0, 1.0)
			c.set_instance_shader_parameter("fade", life)
			c.scale = Vector3.ONE * (0.4 + 0.6 * open)
		l.light_energy = 3.5 * mls * clampf(v * 3.0, 0.0, 1.0) * clampf((1.0 - v) * 3.0, 0.0, 1.0)
	var tw := root.create_tween()
	tw.tween_method(unfold, 0.0, 1.0, seconds)
	tw.tween_callback(root.queue_free)
	return root
