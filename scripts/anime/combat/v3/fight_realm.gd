class_name FightRealm
extends Node
## The duel's realm (2026-10-20, Selwyn: "I want a worldly effect during fights not simple things"; his references
## change the whole world in a domain: the sky, the light, the ground). The world around the duel turns into the realm
## of whoever is pushing the fight, and grows with every big spell:
##   Mika, a frozen starfield   the sky becomes the ice blue Milky Way with aurora curtains (realm_sky), the light goes
##                              cold and bright, the ground frosts over from her feet outward, ice spires burst up round
##                              the arena, a snowstorm spirals round them
##   Luna, an eclipse           a violet nebula sky with a huge moon above Mika going dark in a burning corona, the light
##                              goes violet, glowing cracks spread across the ground, rocks tear loose and float upward,
##                              violet embers and fog rise
## push(who, amount) grows her realm (a big spell 0.2 to 0.35, an ultimate 1.0); the other girl's push first drives it
## back, and past zero her own realm takes the sky. pulse() is a release's light on the whole dome. teardown() gives the
## world back exactly as it was.

const SPIRES := 14
const ROCKS := 18

var d: FightDirector
var who := ""                             # whose realm holds the world now ("" none)
var k := 0.0                              # how far (0..1)
var _k_want := 0.0
var env: Environment
var _env_saved := {}
var _sky_saved: Sky
var _sky: Sky
var _mat: ShaderMaterial
var _root: Node3D
var _ground: Decal
var _props: Array = []                    # [node, kind, base transform, phase]
var _storm: GPUParticles3D
var _embers: GPUParticles3D
var _light: OmniLight3D
var _dn_was := true
var _flash := 0.0
var eclipse := 0.0
const GROUND_LAYER := 1 << 10             # (the terrain is lit by the realm's ground on this layer only: never the girls)
var _terrain: Array = []                  # [MeshInstance3D, its layers before]
var _sun: DirectionalLight3D
var _sun_energy := 1.0
var _base_mix := 0.0


static func make(director: FightDirector) -> FightRealm:
	var r := FightRealm.new()
	r.name = "FightRealm"
	r.d = director
	director.add_child(r)
	r._setup()
	return r


func _setup() -> void:
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		env = (n as WorldEnvironment).environment
		break
	_root = Node3D.new()
	_root.name = "RealmProps"
	d.main.add_child(_root)
	if env == null:
		return
	for p in ["adjustment_enabled", "adjustment_brightness", "adjustment_contrast", "adjustment_saturation", "fog_enabled", "fog_light_color",
			"fog_density", "ambient_light_color", "ambient_light_energy", "glow_enabled", "glow_intensity", "glow_bloom"]:
		_env_saved[p] = env.get(p)
	_sky_saved = env.sky
	if d.main.get("day_night") and d.main.day_night:
		_dn_was = d.main.day_night.is_processing()
		d.main.day_night.set_process(false)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/sky/realm_sky.gdshader")
	_copy_base_sky(_sky_saved)
	if ResourceLoader.exists("res://assets/sky/eso_milky_way/eso0932a_6000x3000.jpg"):
		_mat.set_shader_parameter("galaxy", load("res://assets/sky/eso_milky_way/eso0932a_6000x3000.jpg"))
		# (the band arched across the sky, as Starfall Hill does)
		_mat.set_shader_parameter("galaxy_rot", Basis(Vector3(1, 0, 0), deg_to_rad(-62.0)) * Basis(Vector3(0, 1, 0), deg_to_rad(35.0)))
	_sky = Sky.new()
	_sky.sky_material = _mat
	_sky.radiance_size = Sky.RADIANCE_SIZE_256
	if _sky_saved:
		_sky.process_mode = _sky_saved.process_mode
	env.sky = _sky
	for b in get_tree().get_nodes_in_group("cat_terrain"):
		for mi in (b as Node).find_children("*", "MeshInstance3D", true, false):
			_terrain.append([mi, (mi as MeshInstance3D).layers])
			(mi as MeshInstance3D).layers |= GROUND_LAYER
	var w = d.main.get("world")
	if w and w.get("sun"):
		_sun = w.sun
		_sun_energy = _sun.light_energy
	var mk = _mat.get_shader_parameter("mixk")
	_base_mix = float(mk) if mk != null else 0.0
	_build_ground()
	_build_props()
	_build_air()


## The area's own sky, whatever it is now (a panorama, the day / night blend, Starfall's Milky Way): the realm is drawn
## over it.
func _copy_base_sky(s: Sky) -> void:
	if s == null:
		return
	var m := s.sky_material
	if m is PanoramaSkyMaterial:
		_mat.set_shader_parameter("day_pano", (m as PanoramaSkyMaterial).panorama)
		_mat.set_shader_parameter("night_pano", (m as PanoramaSkyMaterial).panorama)
		_mat.set_shader_parameter("day_energy", (m as PanoramaSkyMaterial).energy_multiplier)
		_mat.set_shader_parameter("night_energy", (m as PanoramaSkyMaterial).energy_multiplier)
		_mat.set_shader_parameter("mixk", 0.0)
	elif m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var dp = sm.get_shader_parameter("day_pano")
		var np = sm.get_shader_parameter("night_pano")
		if np == null:
			np = sm.get_shader_parameter("pano")
		_mat.set_shader_parameter("day_pano", dp if dp else np)
		_mat.set_shader_parameter("night_pano", np if np else dp)
		var mk = sm.get_shader_parameter("mixk")
		_mat.set_shader_parameter("mixk", float(mk) if mk != null else 0.0)
		for e in ["day_energy", "night_energy"]:
			var v = sm.get_shader_parameter(e)
			if v != null:
				_mat.set_shader_parameter(e, float(v))


func _build_ground() -> void:
	_ground = Decal.new()
	_ground.name = "RealmGround"
	_ground.size = Vector3(26.0, 3.0, 26.0)
	_ground.cull_mask = GROUND_LAYER
	_ground.modulate = Color(1, 1, 1, 0)
	_ground.emission_energy = 0.0
	_ground.upper_fade = 0.3
	_ground.lower_fade = 0.3
	_root.add_child(_ground)


func _ground_tex(kind: String) -> Array:
	var n := FastNoiseLite.new()
	n.seed = 7 if kind == "mika" else 13
	var em := FastNoiseLite.new()
	em.seed = n.seed + 1
	if kind == "mika":
		# frost: fine branching crystals (cellular distance edges, fractal)
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		n.frequency = 0.035
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
	else:
		# cracks: the borders of large cells, sharp
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
		n.frequency = 0.012
		n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		n.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 1024
	tex.height = 1024
	tex.noise = n
	tex.seamless = true
	var ramp := Gradient.new()
	if kind == "mika":
		ramp.set_color(0, Color(0.55, 0.8, 1.0, 0.0))
		ramp.set_color(1, Color(0.85, 0.95, 1.0, 0.6))
		ramp.add_point(0.6, Color(0.45, 0.75, 1.0, 0.25))
	else:
		ramp.set_color(0, Color(0.85, 0.5, 1.0, 1.0))
		ramp.set_color(1, Color(0.05, 0.0, 0.08, 0.0))
		ramp.add_point(0.12, Color(0.5, 0.15, 0.9, 0.6))
	tex.color_ramp = ramp
	return [tex, tex]


func _build_props() -> void:
	var crystal: Shader = load("res://shaders/crystal.gdshader")
	for i in SPIRES:
		# a cluster of slender ice crystals, tilted outward from a common root
		var root := Node3D.new()
		root.visible = false
		_root.add_child(root)
		var n := randi_range(3, 6)
		var tall := randf_range(1.6, 4.4)
		for j in n:
			var mi := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			var h := tall * randf_range(0.4, 1.0)
			pm.top_radius = 0.0
			pm.bottom_radius = h * randf_range(0.07, 0.11)
			pm.height = h
			pm.radial_segments = 6
			pm.rings = 1
			var mat := ShaderMaterial.new()
			mat.shader = crystal
			mat.set_shader_parameter("tint", Vector3(0.45, 0.82, 1.0))
			mat.set_shader_parameter("glow", 1.6)
			pm.material = mat
			mi.mesh = pm
			var tilt := Vector3(randf_range(-0.45, 0.45), 0, randf_range(-0.45, 0.45)) * (0.0 if j == 0 else 1.0)
			mi.rotation = tilt + Vector3(0, randf() * TAU, 0)
			mi.position = Vector3(randf_range(-0.25, 0.25), h * 0.45, randf_range(-0.25, 0.25))
			root.add_child(mi)
		_props.append([root, "spire", tall, randf() * TAU])
	var rock_scenes: Array = []
	for rp in ["res://assets/nature/snm/Rock_Medium_1.gltf", "res://assets/nature/snm/Rock_Medium_2.gltf", "res://assets/nature/snm/Rock_Medium_3.gltf"]:
		if ResourceLoader.exists(rp):
			rock_scenes.append(load(rp))
	var rim := ShaderMaterial.new()
	rim.shader = Shader.new()
	rim.shader.code = """shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back;
uniform vec3 col : source_color = vec3(0.6, 0.25, 1.0);
uniform float energy = 1.5;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col * f * energy;
}"""
	for i in ROCKS:
		if rock_scenes.is_empty():
			break
		var r: Node3D = (rock_scenes[i % rock_scenes.size()] as PackedScene).instantiate()
		r.visible = false
		r.scale = Vector3.ONE * randf_range(0.5, 1.3)
		for m in r.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_overlay = rim
		_root.add_child(r)
		_props.append([r, "rock", 1.0, randf() * TAU])
	_rim = rim


var _rim: ShaderMaterial


func _build_air() -> void:
	_storm = _particles(Color(0.85, 0.95, 1.0, 0.8), 1600, 4.0, 0.04)
	_embers = _particles(Color(0.75, 0.4, 1.0, 0.9), 900, 5.0, 0.05)
	_light = OmniLight3D.new()
	_light.omni_range = 24.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_root.add_child(_light)


func _particles(col: Color, n: int, life: float, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 22, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_radius = 10.0
	pm.emission_ring_inner_radius = 2.0
	pm.emission_ring_height = 6.0
	pm.emission_ring_axis = Vector3.UP
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = Color(col.r, col.g, col.b)
	m.emission_energy_multiplier = 2.0
	q.material = m
	p.draw_pass_1 = q
	_root.add_child(p)
	return p


## Grow `girl`'s realm by `amount` (a big spell 0.2 to 0.35, an ultimate 1.0); against the other girl's realm the
## push first drives hers back.
func push(girl: String, amount: float) -> void:
	if who == "" or who == girl:
		if who != girl:
			_switch(girl)
		_k_want = clampf(_k_want + amount, 0.0, 1.0)
	else:
		_k_want -= amount
		if _k_want <= 0.0:
			_switch(girl)
			_k_want = clampf(-_k_want, 0.15, 1.0)


func _switch(girl: String) -> void:
	who = girl
	k = 0.0
	_mat.set_shader_parameter("realm", 0 if girl == "mika" else 1)
	var tex := _ground_tex(girl)
	_ground.texture_albedo = tex[0]
	_ground.texture_emission = tex[1]
	_ground.emission_energy = 0.0
	var mika := girl == "mika"
	_storm.emitting = mika
	_embers.emitting = not mika
	var pm: ParticleProcessMaterial = (_storm if mika else _embers).process_material
	if mika:
		pm.orbit_velocity_min = 0.25
		pm.orbit_velocity_max = 0.45
		pm.radial_velocity_min = -0.5
		pm.radial_velocity_max = 0.5
		pm.tangential_accel_min = 2.0
		pm.tangential_accel_max = 4.0
		pm.gravity = Vector3(0, -0.6, 0)
	else:
		pm.gravity = Vector3(0, 0.9, 0)
		pm.radial_velocity_min = -0.2
		pm.radial_velocity_max = 0.2
	for pr in _props:
		(pr[0] as Node3D).visible = false
	eclipse = 0.0


## A release's light across the whole dome (and on the ground through the realm light).
func pulse(power := 1.0) -> void:
	_flash = maxf(_flash, power)


func _process(delta: float) -> void:
	if env == null:
		return
	var dt := maxf(delta, 0.0001)
	k = move_toward(k, _k_want, dt / 1.6)
	_flash = move_toward(_flash, 0.0, dt / 0.45)
	if who == "":
		return
	var c0: Vector3 = d.center
	var mika := who == "mika"
	var caster: Vector3 = d.pos(who) if d.F.has(who) else c0
	var other := String(d.F[who].other) if d.F.has(who) else ""
	var op: Vector3 = d.pos(other) if other != "" else c0
	_mat.set_shader_parameter("realm_k", k)
	_mat.set_shader_parameter("flash", _flash * 0.6)
	_mat.set_shader_parameter("origin_dir", ((caster - op).normalized() * 0.8 + Vector3.UP * 0.5).normalized())
	if not mika:
		eclipse = move_toward(eclipse, clampf((k - 0.35) / 0.55, 0.0, 1.0), dt / 2.5)
		_mat.set_shader_parameter("eclipse", eclipse)
		_mat.set_shader_parameter("moon_dir", ((op - caster).normalized() * 0.55 + Vector3.UP * 0.85).normalized())
	# the light and the air
	var col := Color(0.5, 0.8, 1.0) if mika else Color(0.65, 0.35, 1.0)
	env.adjustment_enabled = true
	env.adjustment_brightness = lerpf(float(_env_saved.adjustment_brightness), 0.95, k) + _flash * 0.18
	env.adjustment_saturation = lerpf(float(_env_saved.adjustment_saturation), 1.2, k)
	env.adjustment_contrast = lerpf(float(_env_saved.adjustment_contrast), 1.1, k)
	# the realm brings its night: the sun fades, the sky leans to the area's night panorama under the realm
	if _sun:
		_sun.light_energy = lerpf(_sun_energy, _sun_energy * 0.15, k)
	_mat.set_shader_parameter("mixk", lerpf(_base_mix, 1.0, k))
	env.fog_enabled = true
	env.fog_light_color = (_env_saved.fog_light_color as Color).lerp(col.darkened(0.45), k)
	env.fog_density = lerpf(float(_env_saved.fog_density) if bool(_env_saved.fog_enabled) else 0.0, 0.008, k)
	env.ambient_light_color = (_env_saved.ambient_light_color as Color).lerp(col.lerp(Color.WHITE, 0.25), k)
	env.ambient_light_energy = lerpf(float(_env_saved.ambient_light_energy), 0.55, k)
	env.glow_enabled = true
	env.glow_intensity = lerpf(float(_env_saved.glow_intensity), 0.9, k)
	_light.global_position = c0 + Vector3(0, 6.0, 0)
	_light.light_color = col
	_light.light_energy = k * 1.0 + _flash * 4.0
	# the ground spreads from the caster
	_ground.global_position = Vector3(caster.x, c0.y + 0.6, caster.z).lerp(Vector3(c0.x, c0.y + 0.6, c0.z), k)
	var sz := lerpf(2.0, 30.0, smoothstep(0.0, 1.0, k))
	_ground.size = Vector3(sz, 4.0, sz)
	_ground.modulate = Color(1, 1, 1, clampf(k * 1.2, 0.0, 0.85))
	_ground.emission_energy = (0.5 if mika else 2.5) * k + _flash * 1.0
	# the air
	_storm.global_position = c0
	_embers.global_position = c0
	_storm.amount_ratio = clampf(k * 1.2, 0.0, 1.0)
	_embers.amount_ratio = clampf(k * 1.2, 0.0, 1.0)
	# spires burst up (Mika), rocks tear loose and float (Luna), round the edge of the duel
	var n_show := int(round(k * float(SPIRES if mika else ROCKS)))
	var i := 0
	for pr in _props:
		var node: Node3D = pr[0]
		if String(pr[1]) != ("spire" if mika else "rock"):
			continue
		var ph: float = pr[3]
		var on := i < n_show
		var ang := ph + float(i) * 0.37
		var rr := (7.5 if mika else 9.0) + fmod(float(i) * 1.7, 4.5)
		var at := c0 + Vector3(cos(ang) * rr, 0, sin(ang) * rr)
		at.y = FightDirector.ground_y(d.F.values()[0].c, at)
		if on and not node.visible:
			node.visible = true
			node.set_meta("born", Time.get_ticks_msec())
		elif not on:
			node.visible = false
		if node.visible:
			var age := (Time.get_ticks_msec() - int(node.get_meta("born", 0))) / 1000.0
			var grow := clampf(age / 0.35, 0.0, 1.0)
			if mika:
				var h: float = pr[2]
				node.global_position = at - Vector3(0, h * (1.0 - grow), 0)
				node.rotation = Vector3(sin(ph) * 0.2, ph, cos(ph) * 0.2)
			else:
				var lift := 1.5 + fmod(ph * 3.0, 5.0) + sin(Time.get_ticks_msec() / 1000.0 * 0.6 + ph) * 0.35
				node.global_position = at + Vector3(0, lift * grow, 0)
				node.rotation += Vector3(0.11, 0.17, 0.07) * dt
				_rim.set_shader_parameter("energy", 1.2 + _flash * 3.0)
		i += 1


func teardown() -> void:
	for tr in _terrain:
		if is_instance_valid(tr[0]):
			(tr[0] as MeshInstance3D).layers = int(tr[1])
	if _sun and is_instance_valid(_sun):
		_sun.light_energy = _sun_energy
	if env:
		for p in _env_saved:
			env.set(p, _env_saved[p])
		env.sky = _sky_saved
	if d.main.get("day_night") and d.main.day_night:
		d.main.day_night.set_process(_dn_was)
	if is_instance_valid(_root):
		_root.queue_free()
	queue_free()
