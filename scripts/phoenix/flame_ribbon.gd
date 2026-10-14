class_name FlameRibbon
extends MeshInstance3D
## A ribbon of flame that winds around a segment (a limb, her waist, her head) like a bandage of fire, its
## burning head travelling along the segment while its tail fades - the visible "making" of each garment in
## Oriel's transformation (and the unmaking on the way back). World-space geometry, rebuilt each frame.

var a := Vector3.ZERO          # segment start (world)
var b := Vector3.UP            # segment end (world)
var head := 0.0                # 0..1: how far the burning head has travelled along the segment
var span := 0.6                # how much of the segment the ribbon covers behind its head
var radius := 0.12
var turns := 2.5
var width := 0.07
var phase := 0.0
var fade := 1.0
var _im: ImmediateMesh
var _mat: ShaderMaterial


func _init() -> void:
	_im = ImmediateMesh.new()
	mesh = _im
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/phoenix/ribbon.gdshader")
	_mat.set_shader_parameter("noise_tex", FX.noise())
	_mat.set_shader_parameter("strength", 3.2)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	visible = false


func set_colors(head_col: Color, tail_col: Color, strength := 2.4) -> void:
	_mat.set_shader_parameter("col_head", head_col)
	_mat.set_shader_parameter("col_tail", tail_col)
	_mat.set_shader_parameter("strength", strength)


func rebuild() -> void:
	_im.clear_surfaces()
	if fade <= 0.01 or head <= 0.001:
		visible = false
		return
	visible = true
	global_transform = Transform3D.IDENTITY
	_mat.set_shader_parameter("fade", fade)
	var axis := b - a
	var L := axis.length()
	if L < 1e-3:
		return
	var dir := axis / L
	var u := dir.cross(Vector3.UP)
	if u.length() < 0.1:
		u = dir.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := dir.cross(u).normalized()
	var s1 := clampf(head, 0.0, 1.0)
	var s0 := maxf(0.0, s1 - span)
	var n := 56
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n + 1:
		var k := float(i) / n
		var s := lerpf(s0, s1, k)
		var ang := phase + s * turns * TAU
		var rr := radius * (0.88 + 0.12 * sin(s * 9.0 + phase * 2.0))
		var c := a + dir * (L * s)
		var off := (u * cos(ang) + v * sin(ang)) * rr
		_im.surface_set_uv(Vector2(k, 0.0))
		_im.surface_add_vertex(c + off - dir * width * 0.5)
		_im.surface_set_uv(Vector2(k, 1.0))
		_im.surface_add_vertex(c + off + dir * width * 0.5)
	_im.surface_end()
