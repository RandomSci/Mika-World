class_name HeartstoneReactive
extends ReactiveElement
## The Heartstone relic. Arcane magic makes it resonate (light pulse; the pattern it answers with is
## a story clue, recorded by the story system from MagicEvents). Other elements are absorbed: the
## stone dims for a moment, unchanged.

var light: OmniLight3D
var resonances := 0


func setup(p_id: String, p_label: String, p_light: OmniLight3D) -> void:
	id = p_id
	kind = "relic"
	label = p_label
	light = p_light
	aim_radius = 0.5
	supports = ["arcane", "wind", "water", "fire"]
	state = {"resonance": "quiet"}


func setup_awake_state() -> void:
	if WorldState.knowledge.has("story:heartstone_awakened"):
		light.light_energy = 1.4
		light.omni_range = 6.0
		state = {"resonance": "awake (three beats)"}


func _react_arcane(power: float, _p: Vector3) -> Dictionary:
	var pattern_known := WorldState.knowledge.has("clue:pond_pattern")
	var awake := WorldState.knowledge.has("story:heartstone_awakened")
	if pattern_known and not awake and MagicSystem.last_spell == "rune_activation":
		# the remembered pattern completes the heartbeat: three beats, and it stays awake
		var tw0 := create_tween()
		for k in 3:
			tw0.tween_property(light, "light_energy", 2.6 + power, 0.25)
			tw0.tween_property(light, "light_energy", 0.5, 0.35)
		tw0.tween_property(light, "light_energy", 1.4, 1.5)
		tw0.parallel().tween_property(light, "omni_range", 6.0, 1.5)
		FX.burst(self, global_position, 80, 2.0, FX.pm_motes("arcane", "rise"), FX.mote_mesh(0.05))
		state = {"resonance": "awake (three beats)"}
		return {"effect": "awakened", "detail": "the Heartstone beat three times, strong and even, and its light stayed", "clue": "story:heartstone_awakened"}
	if awake:
		var tw1 := create_tween()
		for k in 3:
			tw1.tween_property(light, "light_energy", 2.2 + power, 0.25)
			tw1.tween_property(light, "light_energy", 0.9, 0.35)
		tw1.tween_property(light, "light_energy", 1.4, 1.0)
		return {"effect": "resonance", "detail": "the awakened Heartstone answered with three beats"}
	resonances += 1
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 1.6 + power, 0.3)
	tw.tween_property(light, "light_energy", 0.4, 0.4)
	tw.tween_property(light, "light_energy", 1.4 + power, 0.3)
	tw.tween_property(light, "light_energy", 0.9, 1.5)
	state = {"resonance": "answered", "times": resonances}
	schedule("quiet", 8.0)
	return {"effect": "resonance", "detail": "the Heartstone answered with two slow pulses of light, like a heartbeat"}


func _absorb() -> Dictionary:
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.25, 0.2)
	tw.tween_property(light, "light_energy", 0.9, 1.0)
	return {"effect": "absorbed", "detail": "the relic drank the spell and dimmed for a moment, unchanged"}


func _react_wind(_p: float, _x: Vector3) -> Dictionary: return _absorb()
func _react_water(_p: float, _x: Vector3) -> Dictionary: return _absorb()
func _react_fire(_p: float, _x: Vector3) -> Dictionary: return _absorb()


func _recover(key: String) -> void:
	if key == "quiet":
		state = {"resonance": "quiet", "times": resonances}
