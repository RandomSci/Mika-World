class_name StarlitHarp
extends Node3D
## The Starlit Harp set pieces (proof of reference video 4, 2026-10-19): the light harp (strings that flare when
## plucked), the slat fan, the sun-cloud orb with its spoke rings, cloud banks, the crystal light-lance. Built from
## the reference frames in ~/Downloads/Anime_Reference_Breakdown.md; palettes "blue" (the reference) and "luna"
## (violet and gold).

const PALETTES := {
	"blue": {"glow": Color(0.43, 0.7, 1.0), "core": Color(0.92, 0.97, 1.0), "orb_core": Color(1.0, 0.86, 0.63),
		"orb_edge": Color(0.25, 0.45, 0.95), "cloud": Color(0.08, 0.14, 0.34), "cloud_lit": Color(0.45, 0.62, 1.0),
		"lance": Color(0.35, 0.6, 1.0), "wash": Color(0.2, 0.42, 1.0)},
	"luna": {"glow": Color(0.66, 0.42, 1.0), "core": Color(1.0, 0.95, 0.88), "orb_core": Color(1.0, 0.8, 0.45),
		"orb_edge": Color(0.45, 0.28, 0.9), "cloud": Color(0.13, 0.08, 0.3), "cloud_lit": Color(0.72, 0.55, 1.0),
		"lance": Color(0.62, 0.42, 1.0), "wash": Color(0.48, 0.28, 1.0)},
}

var pal: Dictionary
var strings: Array[MeshInstance3D] = []
var harp: Node3D
var slats: MeshInstance3D
var orb: MeshInstance3D
var spokes: MeshInstance3D
var spokes2: MeshInstance3D
var lance: MeshInstance3D
var clouds: Array[MeshInstance3D] = []
var billboards: Array[Node3D] = []           # turned to face the camera every frame
var _noise: NoiseTexture2D


func setup(palette: String) -> void:
	pal = PALETTES.get(palette, PALETTES.blue)
	_noise = NoiseTexture2D.new()
	_noise.seamless = true
	_noise.width = 512
	_noise.height = 512
	var fn := FastNoiseLite.new()
	fn.frequency = 0.012
	fn.fractal_octaves = 5
	_noise.noise = fn


func _mat(shader: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/harp/%s.gdshader" % shader)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


func _quad(size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## The harp: 7 strings of light across a gold arc, the slat fan behind; `at` the centre, `facing` toward the camera.
func build_harp(at: Vector3, facing: Vector3, tilt_deg := 35.0) -> void:
	harp = Node3D.new()
	harp.name = "Harp"
	add_child(harp)
	harp.global_transform = Transform3D(Basis.looking_at(-facing, Vector3.UP), at)
	harp.rotate_object_local(Vector3.FORWARD, deg_to_rad(tilt_deg))
	for i in 9:
		var s := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.009, 1.0 - abs(i - 4) * 0.06)
		s.mesh = q
		s.material_override = _mat("light_beam", {"core_color": pal.core, "glow_color": pal.glow, "intensity": 1.7, "flare": 0.0})
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		harp.add_child(s)
		s.position = Vector3((i - 4) * 0.042, 0, 0)
		strings.append(s)
	# the arc frame: short gold beam segments along a curve over the strings
	for k in 14:
		var t := k / 13.0
		var seg := MeshInstance3D.new()
		var q2 := QuadMesh.new()
		q2.size = Vector2(0.022, 0.07)
		seg.mesh = q2
		seg.material_override = _mat("light_beam", {"core_color": Color(1, 0.95, 0.8), "glow_color": pal.orb_core, "intensity": 1.6})
		harp.add_child(seg)
		var ang := lerpf(-1.1, 1.1, t)
		seg.position = Vector3(sin(ang) * 0.24, 0.42 + cos(ang) * 0.08, 0)
		seg.rotation.z = -ang
	slats = _quad(Vector2(2.4, 2.4), _mat("spoke_ring", {"color": pal.glow, "intensity": 1.6, "count": 44.0, "inner": 0.55, "outer": 0.95, "bar_width": 0.5, "spin": 0.02, "seed": 3.0}))
	slats.global_transform = Transform3D(harp.global_basis, at - facing * 0.25)


## Pluck string i: a travelling flare that decays, and the string shivers sideways (a vibrating afterimage).
func pluck(i: int, at := 0.45) -> void:
	if i < 0 or i >= strings.size():
		return
	var s := strings[i]
	var m := s.material_override as ShaderMaterial
	m.set_shader_parameter("flare_pos", at)
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("flare", v), 1.0, 0.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	var x0 := s.position.x
	var tv := create_tween()
	for k in 6:
		tv.tween_property(s, "position:x", x0 + (0.006 if k % 2 == 0 else -0.006) * (1.0 - k / 6.0), 0.035)
	tv.tween_property(s, "position:x", x0, 0.03)


## A spark point where a finger touches a string.
func spark(at: Vector3, size := 0.05) -> void:
	var sp := _quad(Vector2(size, size) * 1.6, _mat("spoke_ring", {"color": pal.core, "intensity": 4.0, "count": 8.0, "inner": 0.0, "outer": 1.0, "bar_width": 0.18, "spin": 0.0, "seed": 9.0}))
	sp.global_position = at
	billboards.append(sp)
	var tw := create_tween()
	sp.scale = Vector3.ONE * 0.4
	tw.tween_property(sp, "scale", Vector3.ONE * 1.4, 0.12)
	tw.parallel().tween_method(func(v): (sp.material_override as ShaderMaterial).set_shader_parameter("intensity", v), 5.0, 0.0, 0.45)
	tw.tween_callback(sp.queue_free)


## The orb and its two spoke rings at `at`, radius r.
func build_orb(at: Vector3, r: float) -> void:
	orb = _quad(Vector2(r, r) * 2.0, _mat("sun_orb", {"noise_tex": _noise, "core_color": pal.orb_core, "edge_color": pal.orb_edge, "bloom": 0.0}))
	orb.global_position = at
	spokes = _quad(Vector2(r, r) * 3.3, _mat("spoke_ring", {"color": pal.glow, "intensity": 2.2, "count": 72.0, "inner": 0.64, "outer": 0.93, "bar_width": 0.22, "spin": 0.035, "seed": 1.0}))
	spokes.global_position = at + Vector3(0, 0, 0.01)
	spokes2 = _quad(Vector2(r, r) * 4.4, _mat("spoke_ring", {"color": pal.core, "intensity": 1.1, "count": 140.0, "inner": 0.82, "outer": 0.9, "bar_width": 0.3, "spin": -0.02, "seed": 5.0}))
	spokes2.global_position = at + Vector3(0, 0, 0.02)
	billboards.append_array([orb, spokes, spokes2])


func orb_bloom(v: float) -> void:
	if orb:
		(orb.material_override as ShaderMaterial).set_shader_parameter("bloom", v)


## Cloud banks around `center` (a ring of big soft quads facing the camera).
func build_clouds(center: Vector3, radius: float, n := 9) -> void:
	for i in n:
		var a := TAU * i / n + randf() * 0.3
		var c := _quad(Vector2(randf_range(14.0, 22.0), randf_range(6.0, 10.0)), _mat("soft_cloud", {"noise_tex": _noise, "color": pal.cloud, "lit_color": pal.cloud_lit, "drift": randf_range(0.004, 0.012), "opacity": 0.8}))
		c.global_position = center + Vector3(cos(a) * radius, randf_range(-6.0, 3.0), sin(a) * radius)
		clouds.append(c)
		billboards.append(c)


## The lance: a 6-sided crystal blade, `length` m, pointing along -Z of its node; form 0 -> 1 builds it.
func build_lance(length: float, radius: float) -> void:
	lance = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 6
	cm.rings = 1
	lance.mesh = cm
	lance.material_override = _mat("crystal_lance", {"body_color": pal.lance, "line_color": pal.core, "intensity": 1.6, "form": 0.0})
	lance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lance)


## A flat shockwave on the ground: a spoke ring that grows and fades.
func shockwave(at: Vector3, max_r := 14.0, seconds := 1.2) -> void:
	var w := _quad(Vector2(2.0, 2.0), _mat("spoke_ring", {"color": pal.core, "intensity": 4.0, "count": 96.0, "inner": 0.82, "outer": 1.0, "bar_width": 0.7, "spin": 0.0, "seed": 7.0}))
	w.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at + Vector3(0, 0.15, 0))
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(w, "scale", Vector3.ONE * max_r, seconds).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v): (w.material_override as ShaderMaterial).set_shader_parameter("intensity", v), 5.0, 0.0, seconds * 1.4)
	tw.tween_callback(w.queue_free)
	var l := OmniLight3D.new()
	add_child(l)
	l.global_position = at + Vector3(0, 2.0, 0)
	l.light_color = pal.glow
	l.omni_range = max_r * 1.4
	l.light_energy = 12.0
	var tl := create_tween()
	tl.set_ignore_time_scale(true)
	tl.tween_property(l, "light_energy", 0.0, seconds * 1.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tl.tween_callback(l.queue_free)


func lance_form(v: float) -> void:
	(lance.material_override as ShaderMaterial).set_shader_parameter("form", v)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for b in billboards:
		if is_instance_valid(b):
			var to := cam.global_position - b.global_position
			if to.length() > 0.01:
				b.global_basis = Basis.looking_at(-to, cam.global_basis.y)
