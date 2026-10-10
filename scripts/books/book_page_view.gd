class_name BookPageView
extends Control
## One readable page (heading, text, Latin with translation, ink diagram), laid out for either a 3D
## book page (rendered in a SubViewport onto the open book on the lectern) or the viewer overlay.
## Styles: book (parchment), scroll (pale parchment), inscription (weathered stone, carved letters).

static var _serif: SystemFont
static var _serif_italic: SystemFont

var style := "book"
var page := {}
var page_no := 0
var page_count := 1
var title := ""
var scale_text := 1.0


static func serif(italic := false) -> SystemFont:
	if _serif == null:
		_serif = SystemFont.new()
		_serif.font_names = PackedStringArray(["Noto Serif", "DejaVu Serif", "Liberation Serif", "Georgia", "serif"])
		_serif_italic = SystemFont.new()
		_serif_italic.font_names = _serif.font_names
		_serif_italic.font_italic = true
	return _serif_italic if italic else _serif


func show_page(p_style: String, p_title: String, p: Dictionary, no: int, count: int) -> void:
	style = p_style
	title = p_title
	page = p
	page_no = no
	page_count = count
	_rebuild()


func _colors() -> Dictionary:
	match style:
		"inscription":
			return {"bg": Color(0.42, 0.42, 0.4), "edge": Color(0.28, 0.28, 0.27), "ink": Color(0.93, 0.92, 0.88), "latin": Color(1.0, 0.9, 0.6), "dim": Color(0.82, 0.82, 0.78)}
		"scroll":
			return {"bg": Color(0.95, 0.9, 0.78), "edge": Color(0.72, 0.6, 0.42), "ink": Color(0.24, 0.15, 0.08), "latin": Color(0.5, 0.3, 0.05), "dim": Color(0.42, 0.32, 0.22)}
		_:
			return {"bg": Color(0.92, 0.86, 0.71), "edge": Color(0.6, 0.47, 0.3), "ink": Color(0.2, 0.13, 0.07), "latin": Color(0.48, 0.28, 0.04), "dim": Color(0.38, 0.28, 0.18)}


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var col := _colors()
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.bg
	sb.border_color = col.edge
	sb.set_border_width_all(int(6 * scale_text))
	sb.set_corner_radius_all(int(10 * scale_text) if style != "inscription" else 2)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = int(8 * scale_text)
	bg.add_theme_stylebox_override("panel", sb)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(26 * scale_text))
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(10 * scale_text))
	margin.add_child(vb)
	var head := Label.new()
	head.text = String(page.get("heading", title))
	head.add_theme_font_override("font", serif())
	head.add_theme_font_size_override("font_size", int(30 * scale_text))
	head.add_theme_color_override("font_color", col.ink)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(head)
	var body := Label.new()
	body.text = String(page.get("text", ""))
	body.add_theme_font_override("font", serif())
	body.add_theme_font_size_override("font_size", int(21 * scale_text))
	body.add_theme_color_override("font_color", col.ink)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(body)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8 * scale_text)
	vb.add_child(gap)
	for l in page.get("latin", []):
		var lat := Label.new()
		lat.text = String(l.text)
		lat.add_theme_font_override("font", serif(true))
		lat.add_theme_font_size_override("font_size", int(26 * scale_text))
		lat.add_theme_color_override("font_color", col.latin)
		lat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(lat)
		var tr := Label.new()
		tr.text = String(l.translation)
		tr.add_theme_font_override("font", serif(true))
		tr.add_theme_font_size_override("font_size", int(17 * scale_text))
		tr.add_theme_color_override("font_color", col.dim)
		tr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(tr)
	var dg: Dictionary = page.get("diagram", {})
	if not dg.is_empty():
		var tex := TextureRect.new()
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		tex.texture = ImageTexture.create_from_image(img)
		tex.custom_minimum_size = Vector2(150, 150) * scale_text
		tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/diagram_2d.gdshader")
		var kind := String(dg.get("kind", "sigil"))
		m.set_shader_parameter("mode", {"sigil": 0, "arcs": 1, "rings": 2, "recipe": 3}.get(kind, 0))
		m.set_shader_parameter("sides", int(dg.get("sides", dg.get("count", 6))))
		m.set_shader_parameter("ink", col.ink if style != "inscription" else col.latin)
		var gc: Array = dg.get("color", [0.45, 0.7, 1.0])
		m.set_shader_parameter("glow", Color(gc[0], gc[1], gc[2]))
		tex.material = m
		vb.add_child(tex)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)
	var foot := Label.new()
	foot.text = "%s  ·  %d / %d" % [title, page_no + 1, page_count] if page_count > 1 else title
	foot.add_theme_font_override("font", serif(true))
	foot.add_theme_font_size_override("font_size", int(14 * scale_text))
	foot.add_theme_color_override("font_color", col.dim)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(foot)
