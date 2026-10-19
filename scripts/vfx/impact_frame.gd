class_name ImpactFrame
extends CanvasLayer
## Big hits only (docs/VFX_STYLE_GUIDE.md): three one-frame passes - white flash with radial speed lines, the
## inverted negative, an element-coloured tint - with a 1-2 frame hit stop (Engine.time_scale), then the picture is
## back. At most once every 0.6 s, so a flurry never strobes.

static var instance: ImpactFrame
var rect: ColorRect
var mat: ShaderMaterial
var _last := -10.0


func _ready() -> void:
	instance = self
	layer = 39                        # under the transformation cutscene (40) and its flash (41)
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/vfx/impact_frame.gdshader")
	rect.material = mat
	rect.visible = false
	add_child(rect)


func hit(el: String, screen_pos := Vector2(0.5, 0.5), negative := true) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last < 0.6 or RenderProfile.options.has("no-impact-frames"):
		return
	_last = now
	var e: Dictionary = SpellFX.element(el)
	mat.set_shader_parameter("tint", e.body)
	mat.set_shader_parameter("center", screen_pos)
	rect.visible = true
	var ts := Engine.time_scale
	Engine.time_scale = 0.05                        # hit stop: the world nearly halts for these frames
	for st in ([1, 2, 3] if negative else [1, 3]):        # (the inverted frame reads as a glitch at some moments)
		mat.set_shader_parameter("stage", st)
		await get_tree().process_frame
		if st == 1:
			await get_tree().process_frame             # the flash holds two frames, the others one
	Engine.time_scale = ts
	mat.set_shader_parameter("stage", 0)
	rect.visible = false
