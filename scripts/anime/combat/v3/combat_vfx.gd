class_name CombatVFX
extends Node3D
## Combat v3 effects: layered and shaped, never a flat quad, ring or blob. Each comes out of the body part doing the
## move and follows it:
##   trail   a ribbon swept by the forearm or shin along the strike's own arc (noise-eroded, bright at the fist)
##   impact  at the contact point: velocity-stretched spark streaks (mesh particles), a few hot glint needles in the
##           plane of the blow, a short light, and on a clean hit an open air-burst cone thrown along the blow
##   dust    grit kicked off the ground by a dash or a landing (small mesh pebbles)
## Colours: Mika ice (white core, blue edge), Luna moon (pale lilac core, violet edge).

const PAL := {
	"mika": {"core": Color(0.93, 0.98, 1.0), "edge": Color(0.32, 0.62, 1.0)},
	"luna": {"core": Color(0.97, 0.9, 1.0), "edge": Color(0.62, 0.3, 1.0)},
}

var noise: NoiseTexture2D
var trails: Array = []
var _spark_mesh: CylinderMesh
var _spark_mat := {}
var _pebble_mesh: BoxMesh
var _trail_sh: Shader
var _burst_sh: Shader
var _glint_sh: Shader
var stats := {"trails": 0, "impacts": 0, "sparks": 0}


static func make(host: Node) -> CombatVFX:
	var v := CombatVFX.new()
	v.name = "CombatVFX"
	host.add_child(v)
	v._init_res()
	return v


static func pal(who: String) -> Dictionary:
	return PAL.get(who, PAL.mika)


func _init_res() -> void:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.035
	fn.fractal_octaves = 3
	noise = NoiseTexture2D.new()
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	noise.noise = fn
	_trail_sh = load("res://shaders/anime/combat/v3/limb_trail.gdshader")
	_burst_sh = load("res://shaders/anime/combat/v3/burst.gdshader")
	_glint_sh = load("res://shaders/anime/combat/v3/glint.gdshader")
	_spark_mesh = CylinderMesh.new()
	_spark_mesh.top_radius = 0.0025
	_spark_mesh.bottom_radius = 0.005
	_spark_mesh.height = 0.11
	_spark_mesh.radial_segments = 4
	_spark_mesh.rings = 0
	_pebble_mesh = BoxMesh.new()
	_pebble_mesh.size = Vector3(0.018, 0.012, 0.016)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.22, 0.19, 0.15)
	pm.roughness = 0.95
	_pebble_mesh.material = pm


# ------------------------------------------------------------------------------------------------ trails
## A ribbon between two points of a limb (src() -> [base, tip], world), for `dur` s of fight time, then it fades.
func trail(src: Callable, who: String, dur: float, energy := 2.2, width_k := 1.0) -> Dictionary:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _trail_sh
	mat.set_shader_parameter("core", pal(who).core)
	mat.set_shader_parameter("edge", pal(who).edge)
	mat.set_shader_parameter("energy", energy)
	mat.set_shader_parameter("noise", noise)
	mi.material_override = mat
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	var h := {"mi": mi, "im": im, "mat": mat, "src": src, "hist": [], "left": dur, "fade": 1.0, "w": width_k}
	trails.append(h)
	stats.trails += 1
	return h


func _draw_trail(h: Dictionary) -> void:
	var im: ImmediateMesh = h.im
	im.clear_surfaces()
	var hist: Array = h.hist
	if hist.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := hist.size()
	for i in n:
		var e: Array = hist[n - 1 - i]               # newest first
		var age := float(i) / float(n - 1)
		var base: Vector3 = e[0]
		var tip: Vector3 = e[1]
		var b2 := tip.lerp(base, float(h.w))
		im.surface_set_uv(Vector2(age, 0.0))
		im.surface_add_vertex(b2)
		im.surface_set_uv(Vector2(age, 1.0))
		im.surface_add_vertex(tip)
	im.surface_end()


# ------------------------------------------------------------------------------------------------ contact
## A blow landing at `at` travelling along `dir`. kind: hit / block / parry. power 0..1.
func impact(at: Vector3, dir: Vector3, who: String, power: float, kind := "hit") -> void:
	stats.impacts += 1
	var p := pal(who)
	var d := dir.normalized()
	match kind:
		"hit":
			_sparks(at, -d.lerp(Vector3.UP, 0.25).normalized(), who, int(18 + power * 22), 75.0, 2.5 + power * 4.0)
			_sparks(at, d, who, int(8 + power * 10), 35.0, 3.0 + power * 4.0)
			_glints(at, d, who, 6 + int(power * 4), 0.16 + power * 0.26)
			_burst(at, d, who, 0.55 + power * 0.7)
			_light(at, p.core, 0.25 + power * 0.35, 0.07)
		"block":
			_sparks(at, (-d + Vector3.UP * 0.4).normalized(), who, int(26 + power * 24), 85.0, 2.5 + power * 3.5)
			_glints(at, -d, who, 5, 0.14 + power * 0.18)
			_burst(at, -d, who, 0.35 + power * 0.35)
			_light(at, p.core, 0.2 + power * 0.3, 0.06)
		"parry":
			_sparks(at, (-d).lerp(Vector3.UP, 0.5).normalized(), who, 30, 70.0, 4.5)
			_glints(at, d.cross(Vector3.UP).normalized(), who, 7, 0.32)
			_light(at, p.core, 0.9, 0.08)


func _sparks(at: Vector3, dir: Vector3, who: String, n: int, spread: float, speed: float) -> void:
	stats.sparks += n
	var ps := GPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.amount = maxi(n, 1)
	ps.lifetime = 0.32
	ps.local_coords = false
	ps.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed * 1.25
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.particle_flag_align_y = true
	var g := Gradient.new()
	var p := pal(who)
	g.set_color(0, Color(p.core.r * 3.2, p.core.g * 3.2, p.core.b * 3.2, 1.0))
	g.set_color(1, Color(p.edge.r, p.edge.g, p.edge.b, 0.0))
	g.add_point(0.35, Color(p.edge.r * 2.2, p.edge.g * 2.2, p.edge.b * 2.2, 0.9))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.25))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	ps.process_material = pm
	ps.draw_pass_1 = _spark_mesh
	ps.material_override = _spark_material(who)
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)
	ps.global_position = at
	ps.emitting = true
	get_tree().create_timer(0.8, true, false, false).timeout.connect(ps.queue_free)


func _spark_material(who: String) -> StandardMaterial3D:
	if _spark_mat.has(who):
		return _spark_mat[who]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	m.disable_receive_shadows = true
	_spark_mat[who] = m
	return m


## Hot needles radiating from the contact in the plane across the blow (2-3 frames, then gone).
func _glints(at: Vector3, dir: Vector3, who: String, n: int, length: float) -> void:
	var d := dir.normalized()
	var a := d.cross(Vector3.UP)
	if a.length() < 0.1:
		a = d.cross(Vector3.RIGHT)
	a = a.normalized()
	var b := d.cross(a).normalized()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in n:
		var ang := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		var ray := (a * cos(ang) + b * sin(ang) + d * rng.randf_range(-0.35, 0.5)).normalized()
		var len_ := length * rng.randf_range(0.45, 1.0)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006 + length * 0.012
		cm.bottom_radius = 0.0
		cm.height = len_
		cm.radial_segments = 4
		cm.rings = 0
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		var mat := ShaderMaterial.new()
		mat.shader = _glint_sh
		mat.set_shader_parameter("col", pal(who).core if i % 2 == 0 else pal(who).edge.lightened(0.3))
		mat.set_shader_parameter("energy", 3.2)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var y := -ray
		var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		mi.global_transform = Transform3D(Basis(x, y, z), at + ray * len_ * 0.5)
		mi.scale = Vector3(1, 0.35, 1)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(1, 1.0, 1), 0.035)
		tw.parallel().tween_method(func(v: float): mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.11)
		tw.tween_callback(mi.queue_free)


## An open cone of streaked air thrown from the contact along the blow.
func _burst(at: Vector3, dir: Vector3, who: String, size: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.015
	cm.bottom_radius = 0.26 * size
	cm.height = 0.42 * size
	cm.radial_segments = 28
	cm.rings = 2
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var mat := ShaderMaterial.new()
	mat.shader = _burst_sh
	mat.set_shader_parameter("core", pal(who).core)
	mat.set_shader_parameter("edge", pal(who).edge)
	mat.set_shader_parameter("noise", noise)
	mat.set_shader_parameter("energy", 2.4)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var y := -dir.normalized()
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x, y, z).rotated(dir.normalized(), randf() * TAU), at + dir.normalized() * cm.height * 0.5)
	mi.scale = Vector3.ONE * 0.55
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.35, 0.17).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float): mat.set_shader_parameter("life", v), 0.0, 1.0, 0.2)
	tw.tween_callback(mi.queue_free)


func _light(at: Vector3, col: Color, energy: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 1.3
	l.light_specular = 0.3
	l.shadow_enabled = false
	add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


## Grit off the ground (a dash start, a hard landing): small pebbles, real gravity.
func dust(at: Vector3, dir: Vector3, n := 14, power := 1.0) -> void:
	var ps := GPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 0.9
	ps.amount = n
	ps.lifetime = 0.7
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = (dir.normalized() * 0.6 + Vector3.UP).normalized()
	pm.spread = 40.0
	pm.initial_velocity_min = 1.0 * power
	pm.initial_velocity_max = 2.8 * power
	pm.gravity = Vector3(0, -9.8, 0)
	pm.angular_velocity_min = -400.0
	pm.angular_velocity_max = 400.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	ps.process_material = pm
	ps.draw_pass_1 = _pebble_mesh
	add_child(ps)
	ps.global_position = at + Vector3(0, 0.03, 0)
	ps.emitting = true
	get_tree().create_timer(1.2, true, false, false).timeout.connect(ps.queue_free)


func _process(delta: float) -> void:
	var keep: Array = []
	for h in trails:
		var mi: MeshInstance3D = h.mi
		if not is_instance_valid(mi):
			continue
		if delta > 0.0005:
			if float(h.left) > 0.0:
				var pts: Array = (h.src as Callable).call()
				(h.hist as Array).append(pts)
				if (h.hist as Array).size() > 7:
					(h.hist as Array).pop_front()
			else:
				h.fade = float(h.fade) - delta / 0.09
				if (h.hist as Array).size() > 2:
					(h.hist as Array).pop_front()
			h.left = float(h.left) - delta
		(h.mat as ShaderMaterial).set_shader_parameter("fade", clampf(float(h.fade), 0.0, 1.0))
		_draw_trail(h)
		if float(h.fade) <= 0.0:
			mi.queue_free()
			continue
		keep.append(h)
	trails = keep
