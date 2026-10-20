class_name ScreenFX
extends CanvasLayer
## The anime screen-effect stack (2026-10-18): one full-screen pass (shaders/anime/screen_fx.gdshader) plus camera
## shake, hit freeze and slow motion. Reusable by every cinematic: ScreenFX.get_for(node).flash("burst", 2) ...
## Everything runs on real time (it keeps working while the game is frozen or slowed), and every effect returns to
## rest by itself. Built against the reference frames in ~/Downloads/Anime_Reference_Breakdown.md.

const MODES := {"white": 1, "burst": 2, "invert": 3, "burst_white": 4, "invert_bw": 5}
static var _inst: ScreenFX

var rect: ColorRect
var mat: ShaderMaterial
var _flash_frames: Array = []          # queue of [mode, frames]
var _shake_amp := 0.0
var _shake_left := 0.0
var _shake_total := 0.0
var _freeze_frames := 0
var _slow_tween: Tween
var _rng := RandomNumberGenerator.new()
var _base_scale := 1.0


static func get_for(n: Node) -> ScreenFX:
	if _inst and is_instance_valid(_inst):
		return _inst
	_inst = ScreenFX.new()
	_inst.name = "ScreenFX"
	n.get_tree().root.add_child(_inst)
	return _inst


func _ready() -> void:
	layer = 90                                  # above the world, below any HUD text that must stay readable
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/anime/screen_fx.gdshader")
	rect.material = mat
	# (an unset uniform reads back as null: give every one its rest value)
	var rest := {"speed_lines": 0.0, "zoom_blur": 0.0, "chroma": 0.0, "vignette": 0.0, "flash": 0.0, "flash_mode": 0, "burst_seed": 0.0,
			"burst_angle": 0.6, "center": Vector2(0.5, 0.5), "speed_line_color": Color(1, 1, 1), "wash": Color(1, 0.1, 0.2, 0.0),
			"wash_hi": Color(1.0, 0.92, 0.95), "wash_split": 0.0, "flare": 0.0, "flare_pos": Vector2(0.5, 0.5), "flare_col": Color(1.0, 0.8, 0.9)}
	for k in rest:
		mat.set_shader_parameter(k, rest[k])
	add_child(rect)
	rect.visible = false


func _active() -> bool:
	return float(mat.get_shader_parameter("speed_lines")) > 0.001 or float(mat.get_shader_parameter("zoom_blur")) > 0.001 \
		or float(mat.get_shader_parameter("chroma")) > 0.001 or (mat.get_shader_parameter("wash") as Color).a > 0.001 \
		or int(mat.get_shader_parameter("flash_mode")) != 0 or float(mat.get_shader_parameter("vignette")) > 0.001 \
		or float(mat.get_shader_parameter("flare")) > 0.001


func _tw() -> Tween:
	var t := create_tween()
	t.set_ignore_time_scale(true)
	return t


## Flash frames, a sequence like the references: e.g. flash_seq([["burst", 2], ["invert", 1], ["white", 2]]).
func flash_seq(seq: Array, angle := 0.6) -> void:
	mat.set_shader_parameter("burst_angle", angle)
	for s in seq:
		_flash_frames.append([String(s[0]), int(s[1])])


func flash(kind := "white", frames := 2) -> void:
	flash_seq([[kind, frames]])


func speed_lines(strength := 1.0, seconds := 0.8, center := Vector2(0.5, 0.5), color := Color(1, 1, 1)) -> void:
	mat.set_shader_parameter("center", center)
	mat.set_shader_parameter("speed_line_color", color)
	var t := _tw()
	t.tween_method(func(v): mat.set_shader_parameter("speed_lines", v), 0.0, strength, 0.08)
	t.tween_interval(maxf(0.0, seconds - 0.3))
	t.tween_method(func(v): mat.set_shader_parameter("speed_lines", v), strength, 0.0, 0.22)


func zoom_blur(strength := 1.0, seconds := 0.5, center := Vector2(0.5, 0.5)) -> void:
	mat.set_shader_parameter("center", center)
	var t := _tw()
	t.tween_method(func(v): mat.set_shader_parameter("zoom_blur", v), 0.0, strength, seconds * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v): mat.set_shader_parameter("zoom_blur", v), strength, 0.0, seconds * 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## A short chromatic-aberration pulse (impacts), or a held one (seconds > 0.5).
func chroma(strength := 1.0, seconds := 0.25) -> void:
	var t := _tw()
	mat.set_shader_parameter("chroma", strength)
	t.tween_method(func(v): mat.set_shader_parameter("chroma", v), strength, 0.0, seconds).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


## A full-frame colour wash (a phase change: the red void, the violet storm). hold < 0 keeps it until wash_off().
func wash(color: Color, strength := 0.7, fade_in := 0.15, hold := 1.5, fade_out := 0.6) -> void:
	var t := _tw()
	var from: Color = mat.get_shader_parameter("wash")
	t.tween_method(func(v: Color): mat.set_shader_parameter("wash", v), Color(color.r, color.g, color.b, from.a), Color(color.r, color.g, color.b, strength), fade_in)
	if hold >= 0.0:
		t.tween_interval(hold)
		t.tween_method(func(v: Color): mat.set_shader_parameter("wash", v), Color(color.r, color.g, color.b, strength), Color(color.r, color.g, color.b, 0.0), fade_out)


## A two-colour grade (the ultimates' colour takeover): the shadows toward `color`, the highlights toward `hi`.
func wash2(color: Color, hi: Color, strength := 0.5, fade_in := 0.3, hold := 2.0, fade_out := 0.6) -> void:
	mat.set_shader_parameter("wash_hi", hi)
	mat.set_shader_parameter("wash_split", 1.0)
	wash(color, strength, fade_in, hold, fade_out)
	var t := _tw()
	t.tween_interval(maxf(fade_in + maxf(hold, 0.0) + fade_out, 0.0) + 0.05)
	t.tween_callback(func():
		mat.set_shader_parameter("wash_hi", Color(1.0, 0.92, 0.95))
		mat.set_shader_parameter("wash_split", 0.0))


## A lens flare at a screen point (UV) that flares up fast and fades over `seconds`.
func lens_flare(at_uv: Vector2, color: Color, strength := 1.0, seconds := 0.6) -> void:
	mat.set_shader_parameter("flare_pos", at_uv)
	mat.set_shader_parameter("flare_col", color)
	var t := _tw()
	t.tween_method(func(v): mat.set_shader_parameter("flare", v), 0.0, strength, 0.05)
	t.tween_method(func(v): mat.set_shader_parameter("flare", v), strength, 0.0, maxf(seconds - 0.05, 0.05)).set_ease(Tween.EASE_IN)


## A vignette held for `seconds` (the cast), eased in and out.
func vignette_hold(strength := 0.5, fade_in := 0.3, seconds := 2.0, fade_out := 0.5) -> void:
	var t := _tw()
	t.tween_method(func(v): mat.set_shader_parameter("vignette", v), float(mat.get_shader_parameter("vignette")), strength, fade_in)
	t.tween_interval(maxf(seconds, 0.0))
	t.tween_method(func(v): mat.set_shader_parameter("vignette", v), strength, 0.0, fade_out)


func wash_off(seconds := 0.5) -> void:
	var c: Color = mat.get_shader_parameter("wash")
	_tw().tween_method(func(v: Color): mat.set_shader_parameter("wash", v), c, Color(c.r, c.g, c.b, 0.0), seconds)


func vignette(strength := 0.5, seconds := 1.0) -> void:
	var t := _tw()
	t.tween_method(func(v): mat.set_shader_parameter("vignette", v), 0.0, strength, 0.2)
	t.tween_interval(maxf(0.0, seconds - 0.6))
	t.tween_method(func(v): mat.set_shader_parameter("vignette", v), strength, 0.0, 0.4)


## Camera shake (decaying, on the live camera's h/v offset; never moves the camera node itself).
func shake(amplitude := 0.06, seconds := 0.35) -> void:
	_shake_amp = maxf(_shake_amp, amplitude)
	_shake_left = maxf(_shake_left, seconds)
	_shake_total = _shake_left


## Hit freeze: the game stops for `frames` frames (anime hit-stop, 3-6 frames at 30 fps).
func hit_freeze(frames := 4) -> void:
	if _freeze_frames <= 0:
		_base_scale = Engine.time_scale
	_freeze_frames = maxi(_freeze_frames, frames)
	Engine.time_scale = 0.001


## Slow motion: time eases to `scale` for `seconds` (real time) and back.
func slow_mo(scale := 0.3, seconds := 1.2) -> void:
	if _slow_tween and _slow_tween.is_valid():
		_slow_tween.kill()
	_slow_tween = _tw()
	_slow_tween.tween_property(Engine, "time_scale", scale, 0.12)
	_slow_tween.tween_interval(seconds)
	_slow_tween.tween_property(Engine, "time_scale", 1.0, 0.35).set_trans(Tween.TRANS_SINE)


## The standard impact (the 4-layer rule's layer 3): hit freeze, a 1-2 frame flash, a chromatic pulse and a shake.
func impact(power := 1.0) -> void:
	hit_freeze(int(round(lerpf(3.0, 6.0, clampf(power, 0.0, 1.0)))))
	flash_seq([["white", 1]] if power < 0.7 else [["burst", 2], ["invert", 1]])
	chroma(lerpf(0.5, 1.0, power), 0.3)
	shake(lerpf(0.03, 0.09, power), lerpf(0.25, 0.5, power))


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001)
	# flash frames: one entry per rendered frame
	if not _flash_frames.is_empty():
		var f: Array = _flash_frames[0]
		mat.set_shader_parameter("flash_mode", int(MODES.get(f[0], 1)))
		mat.set_shader_parameter("flash", 1.0)
		mat.set_shader_parameter("burst_seed", _rng.randf() * 100.0)
		f[1] = int(f[1]) - 1
		if int(f[1]) <= 0:
			_flash_frames.pop_front()
	else:
		mat.set_shader_parameter("flash_mode", 0)
		mat.set_shader_parameter("flash", 0.0)
	# hit freeze: counted in rendered frames
	if _freeze_frames > 0:
		_freeze_frames -= 1
		if _freeze_frames == 0:
			Engine.time_scale = _base_scale if _base_scale > 0.01 else 1.0
	# shake
	var cam := get_viewport().get_camera_3d()
	if cam:
		if _shake_left > 0.0:
			_shake_left -= real
			var k := _shake_amp * clampf(_shake_left / maxf(_shake_total, 0.001), 0.0, 1.0)
			cam.h_offset = _rng.randf_range(-k, k)
			cam.v_offset = _rng.randf_range(-k, k) * 0.7
			if _shake_left <= 0.0:
				cam.h_offset = 0.0
				cam.v_offset = 0.0
				_shake_amp = 0.0
	rect.visible = _active()
