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


func _react_arcane(power: float, _p: Vector3) -> Dictionary:
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
