class_name MVPost
extends CanvasLayer
## The MV look over the live frame (shaders/anime/mv_post.gdshader): grade, vignette, white flash, and the moon's lens
## flare / light sweep - placed from the moon's screen position every frame (a sweep fires when the moon crosses the
## frame quickly, i.e. the camera passes it).

var rect: ColorRect
var mat: ShaderMaterial
var moon: Node3D
var _prev := Vector2(-9, -9)
var _sweep := -1.0
var _flash := 0.0
var _flash_len := 0.4


static func make(host: Node, moon_node: Node3D) -> MVPost:
	var p := MVPost.new()
	p.layer = 90
	p.moon = moon_node
	host.add_child(p)
	return p


func _ready() -> void:
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/anime/mv_post.gdshader")
	rect.material = mat
	add_child(rect)


func flash_white(seconds := 0.4) -> void:
	_flash = 1.0
	_flash_len = seconds


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001)
	var vs := get_viewport().get_visible_rect().size
	mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	if _flash > 0.0:
		_flash = maxf(_flash - real / _flash_len, 0.0)
		mat.set_shader_parameter("flash", pow(_flash, 1.6))
	var cam := get_viewport().get_camera_3d()
	var amt := 0.0
	var uv := Vector2(-2, -2)
	if cam and moon and is_instance_valid(moon) and not cam.is_position_behind(moon.global_position):
		uv = cam.unproject_position(moon.global_position) / vs
		var edge := minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
		amt = 0.7 * smoothstep(-0.05, 0.12, edge) * (0.55 + 0.45 * (1.0 - clampf((uv - Vector2(0.5, 0.5)).length() * 1.6, 0.0, 1.0)))
		if _prev.x > -5.0 and _sweep < 0.0 and edge > -0.05 and (uv - _prev).length() > 0.012:
			_sweep = 0.0
	_prev = uv if amt > 0.0 else Vector2(-9, -9)
	mat.set_shader_parameter("flare_pos", uv)
	mat.set_shader_parameter("flare", amt)
	if _sweep >= 0.0:
		_sweep += real / 1.1
		if _sweep > 1.0:
			_sweep = -1.0
	mat.set_shader_parameter("sweep", _sweep)
