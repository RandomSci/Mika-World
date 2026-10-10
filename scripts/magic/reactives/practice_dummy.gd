class_name PracticeDummy
extends ReactiveElement
## A straw practice dummy. wind: sways on its post; fire: scorches dark and smokes briefly;
## water: soaked darker for ~15 s; arcane: jolts. Nothing burns away (bounded, reversible).

var body: Node3D
var sack_mat: StandardMaterial3D
var _base := Color(0.72, 0.6, 0.38)
var _sway := 0.0
var _t := 0.0


func setup(p_id: String, p_label: String, p_body: Node3D, p_mat: StandardMaterial3D) -> void:
	id = p_id
	kind = "dummy"
	label = p_label
	body = p_body
	sack_mat = p_mat
	_base = p_mat.albedo_color
	aim_offset = Vector3(0, 1.25, 0)
	aim_radius = 0.45
	supports = ["wind", "fire", "water", "arcane"]
	state = {"condition": "dry"}


func _react_wind(power: float, _p: Vector3) -> Dictionary:
	_sway = 0.12 + 0.3 * power
	schedule("still", 3.0)
	return {"effect": "swayed", "detail": "the dummy swayed on its post"}


func _react_fire(_power: float, _p: Vector3) -> Dictionary:
	sack_mat.albedo_color = Color(0.25, 0.18, 0.12)
	FX.burst(self, global_position + aim_offset, 12, 2.2, FX.pm_puff("smoke"), FX.puff_mesh(0.35))
	schedule("dry", 12.0)
	state = {"condition": "scorched"}
	return {"effect": "scorched", "detail": "the straw scorched dark and smoked, but did not catch"}


func _react_water(_power: float, _p: Vector3) -> Dictionary:
	sack_mat.albedo_color = _base.darkened(0.45)
	FX.burst(self, global_position + aim_offset, 20, 1.0, FX.pm_motes("water", "splash"), FX.mote_mesh(0.035))
	schedule("dry", 15.0)
	state = {"condition": "soaked"}
	return {"effect": "soaked", "detail": "the dummy is soaked through"}


func _react_arcane(power: float, _p: Vector3) -> Dictionary:
	_sway = 0.2 + 0.2 * power
	schedule("still", 1.2)
	return {"effect": "jolted", "detail": "the dummy jolted back on its post"}


func _recover(key: String) -> void:
	match key:
		"still":
			_sway = 0.0
		"dry":
			sack_mat.albedo_color = _base
			state = {"condition": "dry"}


func _process(delta: float) -> void:
	super._process(delta)
	_t += delta
	var target := sin(_t * 6.0) * _sway
	body.rotation.z = lerpf(body.rotation.z, target, 1.0 - exp(-8.0 * delta))
