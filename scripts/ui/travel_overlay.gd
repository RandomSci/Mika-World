class_name TravelOverlay
extends CanvasLayer
## Masked travel card: fades to a dark vignette, shows region / destination / route and preload progress.

var rect: ColorRect
var title: Label
var subtitle: Label
var route: Label
var bar: ProgressBar
var fade_time := 0.55


func _ready() -> void:
	layer = 50
	rect = ColorRect.new()
	rect.color = Color(0.02, 0.025, 0.035, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-400, -60)
	box.custom_minimum_size = Vector2(800, 120)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	rect.add_child(box)
	title = _label(34, Color(0.92, 0.88, 0.78))
	subtitle = _label(19, Color(0.75, 0.8, 0.9))
	route = _label(15, Color(0.6, 0.65, 0.72))
	for l in [title, subtitle, route]:
		box.add_child(l)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(800, 6)
	bar.show_percentage = false
	box.add_child(bar)
	rect.visible = false


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func fade_out(region: String, dest: String, via: String) -> void:
	title.text = region
	subtitle.text = dest
	route.text = ("via " + via) if via != "" else ""
	bar.value = 0
	rect.visible = true
	for n in [title, subtitle, route, bar]:
		n.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 1.0, fade_time)
	tw.parallel().tween_property(title, "modulate:a", 1.0, fade_time)
	tw.parallel().tween_property(subtitle, "modulate:a", 1.0, fade_time)
	tw.parallel().tween_property(route, "modulate:a", 1.0, fade_time)
	tw.parallel().tween_property(bar, "modulate:a", 0.6, fade_time)
	await tw.finished


func set_progress(p: float) -> void:
	bar.value = p * 100.0


func fade_in() -> void:
	bar.value = 100
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(rect, "color:a", 0.0, fade_time)
	tw.parallel().tween_property(title, "modulate:a", 0.0, fade_time * 0.6)
	tw.parallel().tween_property(subtitle, "modulate:a", 0.0, fade_time * 0.6)
	tw.parallel().tween_property(route, "modulate:a", 0.0, fade_time * 0.6)
	tw.parallel().tween_property(bar, "modulate:a", 0.0, fade_time * 0.6)
	await tw.finished
	rect.visible = false
