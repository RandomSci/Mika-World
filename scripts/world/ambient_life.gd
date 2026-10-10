class_name AmbientLife
extends Node3D
## Cheap ambient creatures for the Sanctuary — no AI, no physics, no skeletons:
## two flocks of birds circling high over the clearing (one MultiMesh), butterflies drifting over the
## Meditation Garden by day (one MultiMesh, wings flap in the vertex shader) and fireflies over the
## garden and the forest edge at night (GPU particles). CPU cost: ~20 transform writes per frame.

var area: AreaBase
var birds: MultiMesh
var butterflies: MultiMesh
var butterfly_node: MultiMeshInstance3D
var fireflies: Array[GPUParticles3D] = []
var _bird_params := []        # [flock, phase, radius, height, speed]
var _fly_params := []         # [center, phase, rx, rz, h]
var _night := false
var _check := 0.0


func _init(owner: AreaBase) -> void:
	area = owner
	name = "AnimatedAmbientLife"


func _ready() -> void:
	var live := RenderProfile.profile == RenderProfile.LIVE_OPTIMIZED
	var r := RandomNumberGenerator.new()
	r.seed = 515
	# Birds: a body + two wing triangles, dark silhouette against the sky
	var bird_mat := ShaderMaterial.new()
	bird_mat.shader = load("res://shaders/ambient_creature.gdshader")
	bird_mat.set_shader_parameter("flap_speed", 7.0)
	bird_mat.set_shader_parameter("flap_amount", 0.75)
	bird_mat.set_shader_parameter("body_half", 0.06)
	birds = _make_mm(_wing_mesh(0.42, 0.16, 0.06), 12, false)
	var bn := MultiMeshInstance3D.new()
	bn.multimesh = birds
	bn.material_override = bird_mat
	bn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bn)
	for i in 12:
		var flock := i / 6
		_bird_params.append([flock, r.randf() * TAU * 0.25 + i * 0.09, r.randf_range(-2.5, 2.5), r.randf_range(-1.2, 1.2), r.randf_range(0.9, 1.1)])
		birds.set_instance_custom_data(i, Color(r.randf(), r.randf_range(0.8, 1.2), 0, 0))
	# Butterflies over the garden (day)
	var fly_mat := ShaderMaterial.new()
	fly_mat.shader = load("res://shaders/ambient_creature.gdshader")
	fly_mat.set_shader_parameter("flap_speed", 16.0)
	fly_mat.set_shader_parameter("flap_amount", 1.1)
	fly_mat.set_shader_parameter("body_half", 0.008)
	fly_mat.set_shader_parameter("use_instance_color", true)
	fly_mat.set_shader_parameter("emission", 0.15)
	var nfly := 8 if live else 14
	butterflies = _make_mm(_wing_mesh(0.07, 0.07, 0.008), nfly, true)
	butterfly_node = MultiMeshInstance3D.new()
	butterfly_node.multimesh = butterflies
	butterfly_node.material_override = fly_mat
	butterfly_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	butterfly_node.visibility_range_end = 45.0
	add_child(butterfly_node)
	var cols := [Color(0.95, 0.6, 0.15), Color(0.9, 0.9, 0.95), Color(0.35, 0.55, 1.0), Color(1.0, 0.85, 0.3)]
	var centers := [SanctuaryTerrain.GARDEN, SanctuaryTerrain.GARDEN + Vector2(-3, -2), Vector2(9.5, 9.5), Vector2(-9, 4)]
	for i in nfly:
		_fly_params.append([centers[i % centers.size()], r.randf() * 100.0, r.randf_range(1.2, 3.2), r.randf_range(1.0, 2.6), r.randf_range(0.5, 1.4)])
		butterflies.set_instance_color(i, cols[i % cols.size()])
		butterflies.set_instance_custom_data(i, Color(r.randf(), r.randf_range(0.85, 1.25), 0, 0))
	# Fireflies (night)
	var g := SanctuaryTerrain.GARDEN
	for spot in [[Vector3(g.x, 0.9, g.y), Vector3(7, 0.8, 7), 50 if live else 80], [Vector3(-14, 1.2, 4), Vector3(6, 1.0, 10), 30 if live else 50],
			[Vector3(6, 1.2, -22), Vector3(9, 1.0, 4), 30 if live else 50]]:
		fireflies.append(_fireflies(spot[0], spot[1], spot[2]))
	_apply_night(area.night)


func _make_mm(mesh: Mesh, count: int, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	return mm


## Flat body strip + two wings (x = ±span) as one small mesh; the shader flaps |x| > body_half.
func _wing_mesh(span: float, chord: float, body: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [
		[Vector3(-body, 0, -chord), Vector3(body, 0, -chord), Vector3(0, 0, chord * 1.2)],
		[Vector3(-body, 0, -chord * 0.6), Vector3(-span, 0, chord * 0.1), Vector3(-body, 0, chord * 0.5)],
		[Vector3(body, 0, -chord * 0.6), Vector3(body, 0, chord * 0.5), Vector3(span, 0, chord * 0.1)],
	]
	for t in tris:
		for v in t:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


func _fireflies(center: Vector3, extents: Vector3, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 6.0
	p.preprocess = 6.0
	var gy: float = area.ground_at(center.x, center.z) if area.has_method("ground_at") else 0.0
	p.position = Vector3(center.x, gy + center.y, center.z)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.35, 0.55, 0.75, 1.0])
	grad.colors = PackedColorArray([Color(0.7, 1.0, 0.3, 0.0), Color(0.75, 1.0, 0.35, 1.0), Color(0.7, 1.0, 0.3, 0.15),
		Color(0.8, 1.0, 0.4, 1.0), Color(0.7, 1.0, 0.3, 0.1), Color(0.7, 1.0, 0.3, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/magic/energy_mote.gdshader")
	sm.set_shader_parameter("hdr_boost", 5.0)
	q.material = sm
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(-extents - Vector3.ONE * 2, extents * 2 + Vector3.ONE * 4)
	add_child(p)
	return p


func _apply_night(n: bool) -> void:
	_night = n
	for f in fireflies:
		f.visible = n
		f.emitting = n
	butterfly_node.visible = not n


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		if area.night != _night:
			_apply_night(area.night)
	var t := Time.get_ticks_msec() / 1000.0
	# birds: two flocks on slow wide circles, each bird with a small offset in the formation
	for i in _bird_params.size():
		var bp: Array = _bird_params[i]
		var flock: int = bp[0]
		var spd := 0.055 if flock == 0 else -0.04
		var ang: float = t * spd * bp[4] + bp[1] + flock * 2.4
		var rad: float = (38.0 if flock == 0 else 52.0) + bp[2]
		var c := Vector3(6.0, 0, -4.0) if flock == 0 else Vector3(-10.0, 0, 8.0)
		var pos := c + Vector3(cos(ang) * rad, (24.0 if flock == 0 else 31.0) + bp[3] + sin(t * 0.7 + i) * 0.6, sin(ang) * rad)
		var tangent := Vector3(-sin(ang), 0, cos(ang)) * signf(spd)
		var b := Basis.looking_at(-tangent, Vector3.UP).rotated(tangent.normalized(), -0.25 * signf(spd))
		birds.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * 1.6), pos))
	if _night:
		return
	# butterflies: erratic lissajous loops near flowers
	for i in _fly_params.size():
		var fp: Array = _fly_params[i]
		var c2: Vector2 = fp[0]
		var ph: float = fp[1]
		var tt: float = t * 0.35 + ph
		var x: float = c2.x + sin(tt * 1.3) * fp[2] + sin(tt * 3.7) * 0.25
		var z: float = c2.y + sin(tt * 0.9 + 1.0) * fp[3] + cos(tt * 4.1) * 0.25
		var y := 0.0
		if area.has_method("ground_at"):
			y = area.ground_at(x, z)
		y += float(fp[4]) + sin(tt * 2.3) * 0.25
		var vel := Vector3(cos(tt * 1.3) * 1.3 * fp[2], 0, cos(tt * 0.9 + 1.0) * 0.9 * fp[3])
		var b2 := Basis.looking_at(-vel.normalized() if vel.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		butterflies.set_instance_transform(i, Transform3D(b2, Vector3(x, y, z)))
