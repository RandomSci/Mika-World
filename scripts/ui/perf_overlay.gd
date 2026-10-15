class_name PerfOverlay
extends CanvasLayer
## Developer performance panel (F6; never on the viewer overlay): what the frame costs, what limits it, and what
## Adaptive 60 is doing about it (docs/ADAPTIVE_GRAPHICS.md).

var main: Node
var label: Label
var _t := 0.0


func setup(m: Node) -> void:
	main = m
	layer = 90
	visible = false
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.06, 0.78)
	sb.set_content_margin_all(10)
	sb.corner_radius_top_left = 6
	sb.corner_radius_bottom_left = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -470
	panel.offset_top = 64
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0))
	panel.add_child(label)


func toggle() -> void:
	visible = not visible


func _process(delta: float) -> void:
	if not visible or main == null or main.get("gfx") == null:
		return
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	var g: AdaptiveQuality = main.gfx
	var d := g.describe()
	var w: Dictionary = d.stats
	var k: Dictionary = d.knobs
	var lines := []
	lines.append("GRAPHICS  %s%s" % [RenderProfile.profile, "  (adaptive on)" if d.enabled else ""])
	if not w.is_empty():
		lines.append("FPS %.0f   frame %.1f ms   p95 %.1f   p99 %.1f   1%% low %.0f" % [1000.0 / maxf(float(w.avg_ms), 0.1), w.avg_ms, w.p95_ms, w.p99_ms, w.low1_fps])
		lines.append("GPU %.1f ms   CPU %.1f ms   limit: %s" % [w.gpu_ms, w.cpu_ms, String(d.bottleneck)])
	lines.append("quality level %d / %d" % [int(d.level), int(d.of)])
	lines.append("3D scale %.2f (%s)   shadows %d %%   distant foliage %d %%" % [get_viewport().scaling_3d_scale,
		["bilinear", "FSR 1", "FSR 2"][clampi(int(get_viewport().scaling_3d_mode), 0, 2)], int(float(k.shadow) * 100), int(float(k.distant) * 100)])
	lines.append("particles %d %%   SSIL %s   SSR %s" % [int(float(k.particles) * 100), "on" if float(k.ssil) > 0.5 else "off", "on" if float(k.ssr) > 0.5 else "off"])
	lines.append("stalls skipped: shader compile %d, area load %d" % [int(d.stutters.compile), int(d.stutters.load)])
	if String(d.reason) != "":
		lines.append("last: " + String(d.reason))
	for e in g.history.slice(maxi(0, g.history.size() - 4)):
		lines.append("  %6.1fs %-4s L%-2d %s" % [float(e.t), String(e.dir), int(e.level), String(e.step)])
	label.text = "\n".join(lines)
