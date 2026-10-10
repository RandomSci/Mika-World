class_name RuneReactive
extends ReactiveElement
## A carved rune target on the training grounds (its sigil material is the visible state).
##   arcane: the rune lights up and stays lit ~20 s (brighter with power)
##   wind  : the disc rocks on its post
##   fire  : the sigil scorches orange for a few seconds
##   water : the sigil dims, dripping, for a few seconds

var sigil: ShaderMaterial
var disc: Node3D
var _parts: Array[Node3D] = []
var _bases: Array[Basis] = []
var _base_color := Color(0.45, 0.7, 1.0)
var _rock := 0.0
var _rock_now := 0.0


func setup(p_id: String, p_label: String, p_sigil: ShaderMaterial, p_disc: Node3D, p_parts: Array = []) -> void:
	for n in p_parts:
		_parts.append(n)
		_bases.append((n as Node3D).basis)
	id = p_id
	kind = "rune"
	label = p_label
	sigil = p_sigil
	disc = p_disc
	aim_radius = 0.55
	supports = ["arcane", "wind", "fire", "water"]
	state = {"glow": "dormant"}


func _react_arcane(power: float, _p: Vector3) -> Dictionary:
	var tw := create_tween()
	tw.tween_method(func(v: float): sigil.set_shader_parameter("intensity", v), 0.3, 3.0 + power * 2.0, 0.15)
	tw.tween_method(func(v: float): sigil.set_shader_parameter("intensity", v), 3.0 + power * 2.0, 1.0 + power, 1.0)
	schedule("dim", 20.0)
	state = {"glow": "lit"}
	return {"effect": "lit", "detail": "the rune blazed and stays lit"}


func _react_wind(power: float, _p: Vector3) -> Dictionary:
	_rock = 0.25 * power + 0.1
	schedule("still", 2.5)
	return {"effect": "rocked", "detail": "the target rocked on its post"}


func _react_fire(_power: float, _p: Vector3) -> Dictionary:
	sigil.set_shader_parameter("color", Color(1.0, 0.5, 0.15))
	schedule("color", 5.0)
	state = {"glow": "scorched"}
	return {"effect": "scorched", "detail": "the sigil glowed scorched orange"}


func _react_water(_power: float, _p: Vector3) -> Dictionary:
	sigil.set_shader_parameter("intensity", 0.08)
	FX.burst(self, global_position, 18, 1.0, FX.pm_motes("water", "splash"), FX.mote_mesh(0.035))
	schedule("dim", 6.0)
	state = {"glow": "drenched"}
	return {"effect": "drenched", "detail": "water ran down the disc and the sigil dimmed"}


func _recover(key: String) -> void:
	match key:
		"dim":
			sigil.set_shader_parameter("intensity", 0.3)
			state = {"glow": "dormant"}
		"color":
			sigil.set_shader_parameter("color", _base_color)
			state = {"glow": "dormant"}
		"still":
			_rock = 0.0


func _process(delta: float) -> void:
	super._process(delta)
	var target := sin(Time.get_ticks_msec() / 1000.0 * 9.0) * _rock
	_rock_now = lerpf(_rock_now, target, 1.0 - exp(-10.0 * delta))
	for i in _parts.size():
		_parts[i].basis = Basis(Vector3.UP, 0.0).rotated(global_transform.basis.x.normalized(), _rock_now) * _bases[i]
