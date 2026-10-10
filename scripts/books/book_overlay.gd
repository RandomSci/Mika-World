class_name BookOverlay
extends CanvasLayer
## Readable page card for viewers while Mika reads (the same page the 3D book shows). Fades in and out;
## sized for a 1600x900 stream (scales with the window).

var view: BookPageView
var holder: Control
var _alpha := 0.0
var _target := 0.0


func _ready() -> void:
	layer = 5
	holder = Control.new()
	holder.anchor_left = 1.0
	holder.anchor_right = 1.0
	holder.anchor_top = 0.08
	holder.offset_left = -560
	holder.offset_right = -36
	holder.offset_top = 0
	holder.offset_bottom = 640
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	view = BookPageView.new()
	view.scale_text = 0.86
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(view)
	holder.modulate.a = 0.0


func show_page(style: String, title: String, page: Dictionary, no: int, count: int) -> void:
	view.show_page(style, title, page, no, count)
	_target = 1.0


func hide_page() -> void:
	_target = 0.0


func _process(delta: float) -> void:
	_alpha = move_toward(_alpha, _target, delta * 2.5)
	holder.modulate.a = _alpha
	holder.visible = _alpha > 0.01
