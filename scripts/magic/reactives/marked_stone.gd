class_name MarkedStone
extends ReactiveElement
## A weathered stone with a mark carved too faintly to read by daylight. Only Rune Activation (the waking
## word from "Signs and Wakings") wakes the hidden glyph: a deliberate, lasting story consequence
## recorded in WorldState (the clue stays found). Weaker arcane only outlines it for a moment.

var glyph: ShaderMaterial
var clue_key := ""
var revealed := false


func setup(p_id: String, p_label: String, p_glyph: ShaderMaterial, p_clue: String) -> void:
	id = p_id
	kind = "marked_stone"
	label = p_label
	glyph = p_glyph
	clue_key = p_clue
	aim_radius = 0.6
	supports = ["arcane"]
	revealed = WorldState.knowledge.has(clue_key)
	glyph.set_shader_parameter("intensity", 0.9 if revealed else 0.0)
	glyph.set_shader_parameter("draw_progress", 1.0 if revealed else 0.0)
	state = {"glyph": "revealed" if revealed else "hidden"}


func observed_state() -> Dictionary:
	return {"surface": "a woken seven-pointed glyph" if revealed else "a faint, worn carving"}


func _react_arcane(power: float, _p: Vector3) -> Dictionary:
	if revealed:
		var tw0 := create_tween()
		tw0.tween_method(func(v: float): glyph.set_shader_parameter("intensity", v), 2.5, 0.9, 1.5)
		return {"effect": "glyph_pulse", "detail": "the revealed glyph pulses in answer"}
	if MagicSystem.last_spell != "rune_activation" or power < 0.4:
		var tw := create_tween()
		tw.tween_method(func(v: float): glyph.set_shader_parameter("draw_progress", v), 0.0, 0.45, 0.6)
		tw.parallel().tween_method(func(v: float): glyph.set_shader_parameter("intensity", v), 0.0, 0.6, 0.6)
		tw.tween_interval(2.5)
		tw.tween_method(func(v: float): glyph.set_shader_parameter("intensity", v), 0.6, 0.0, 1.5)
		return {"effect": "faint_outline", "detail": "part of a carved shape glowed for a moment, then faded (a blow of light only outlines it; it needs a thin waking line)"}
	revealed = true
	var tw2 := create_tween()
	tw2.tween_method(func(v: float): glyph.set_shader_parameter("draw_progress", v), 0.0, 1.0, 1.6)
	tw2.parallel().tween_method(func(v: float): glyph.set_shader_parameter("intensity", v), 0.0, 2.5, 1.6)
	tw2.tween_method(func(v: float): glyph.set_shader_parameter("intensity", v), 2.5, 0.9, 2.0)
	state = {"glyph": "revealed"}
	return {"effect": "revealed", "detail": "a hidden glyph woke in the stone and stays lit", "clue": clue_key}
