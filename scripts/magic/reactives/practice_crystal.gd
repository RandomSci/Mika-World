class_name PracticeCrystal
extends ReactiveElement
## A floating practice crystal on the training grounds. Any element with power >= 0.6 shatters it
## (shards burst in the element's colours); it regrows on its stand after ~45 s. Weaker hits make it
## ring and glow. Bounded and reversible by design.

var crystal: MeshInstance3D
var light: OmniLight3D
var intact := true
var _grow := 1.0
var _base_y := 0.0


func setup(p_id: String, p_label: String, p_crystal: MeshInstance3D, p_light: OmniLight3D) -> void:
	id = p_id
	kind = "practice_crystal"
	label = p_label
	crystal = p_crystal
	light = p_light
	aim_radius = 0.5
	supports = ["arcane", "wind", "water", "fire"]
	_base_y = crystal.position.y
	aim_offset = Vector3(0, _base_y, 0)
	state = {"crystal": "intact"}


func _hit(element: String, power: float) -> Dictionary:
	if not intact:
		return {"effect": "none", "detail": "the stand is empty; the crystal is still regrowing"}
	if power >= 0.6:
		intact = false
		_grow = 0.0
		crystal.visible = false
		FX.burst(self, crystal.global_position, 60, 1.4, FX.pm_motes(element, "burst"), FX.mote_mesh(0.07))
		FX.burst(self, crystal.global_position, 30, 1.2, FX.pm_motes("arcane", "burst"), FX.mote_mesh(0.05))
		schedule("regrow", 45.0)
		state = {"crystal": "shattered"}
		return {"effect": "shattered", "detail": "the practice crystal shattered (it regrows in ~45 s)"}
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 3.0, 0.1)
	tw.tween_property(light, "light_energy", 0.8, 0.8)
	return {"effect": "rang", "detail": "the crystal rang and glowed but held (needs a stronger spell to break)"}


func _react_arcane(p: float, _x: Vector3) -> Dictionary: return _hit("arcane", p)
func _react_wind(p: float, _x: Vector3) -> Dictionary: return _hit("wind", p)
func _react_water(p: float, _x: Vector3) -> Dictionary: return _hit("water", p)
func _react_fire(p: float, _x: Vector3) -> Dictionary: return _hit("fire", p)


func _recover(key: String) -> void:
	if key == "regrow":
		crystal.visible = true
		_grow = 0.01


func _process(delta: float) -> void:
	super._process(delta)
	var t := Time.get_ticks_msec() / 1000.0
	if crystal.visible and _grow < 1.0:
		_grow = minf(1.0, _grow + delta / 3.0)
		if _grow >= 1.0:
			intact = true
			state = {"crystal": "intact"}
	crystal.scale = Vector3.ONE * maxf(_grow, 0.01)
	crystal.position.y = _base_y + sin(t * 1.2) * 0.05
	crystal.rotation.y = t * 0.5
