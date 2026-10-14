class_name Gusts
extends Node
## GUSTS (the cinematic pass, 2026-10-14 - the developer: "the phoenix wings produce powerful wind so why are the
## trees not being affected"). Wind from great wingbeats, blasts and the Phoenix's transformation bends the
## vegetation: every plant material registers here (RealKit trees and scanned plants, the stylised kit's foliage,
## bark and grass) and emit() starts a gust - a wave that runs out from its source, bending each plant away from it
## and letting it swing back like a damped spring (shaders/nature/gust.gdshaderinc). Up to four live at once (the
## weakest is replaced). With `fx`, a gust also tears real leaves from the crowns and drives the leaf litter and
## dust along the ground (WindFX). One node in the tree runs it; static API, so anything can call it.

const MAX := 4
const SPEED := 17.0                  # must match GUST_SPEED in gust.gdshaderinc
const PLANT_SHADERS := ["stylized_foliage.gdshader", "stylized_bark.gdshader", "stylized_grass.gdshader", "grass_blades.gdshader",
	"real_leaf.gdshader", "real_bark.gdshader", "real_plant.gdshader"]

static var _mats: Array = []         # WeakRef(ShaderMaterial)
static var _gusts: Array = []        # {pos, radius, strength, freq, damp, age, life}
static var _node: Gusts = null
static var _uploaded_idle := true
static var history: Array = []       # recent gusts (tests)


## A plant material: gusts will move it. Non-plant shaders are ignored, so callers can pass anything.
static func register(m: Material) -> void:
	if not (m is ShaderMaterial) or (m as ShaderMaterial).shader == null:
		return
	var p := String((m as ShaderMaterial).shader.resource_path)
	if not PLANT_SHADERS.any(func(s): return p.ends_with(s)):
		return
	for w in _mats:
		if w.get_ref() == m:
			return
	_mats.append(weakref(m))


static func registered() -> int:
	return _mats.filter(func(w): return w.get_ref() != null).size()


## Start a gust at `pos` reaching `radius` metres, bending plants `strength` metres at their reference height.
## freq: how fast they swing (big trees ~0.5 Hz, plants faster); damp: how fast it dies (1/s).
## fx: {"leaves": n torn from the crowns, "litter": n blown along the ground, "dust": true, "ground_y": y}.
static func emit(host: Node, pos: Vector3, radius: float, strength: float, freq := 0.55, damp := 1.25, fx := {}) -> void:
	if host == null or not host.is_inside_tree():
		return
	_ensure(host)
	if _gusts.size() >= MAX:
		_gusts.sort_custom(func(a, b): return _level(a) > _level(b))
		_gusts.resize(MAX - 1)
	var life := radius / SPEED + 4.6 / maxf(damp, 0.2)
	_gusts.append({"pos": pos, "radius": radius, "strength": strength, "freq": freq, "damp": damp, "age": 0.0, "life": life})
	history.append({"pos": pos, "radius": radius, "strength": strength})
	if history.size() > 40:
		history.pop_front()
	if not fx.is_empty():
		WindFX.gust_fx(host, pos, radius, strength, fx)


static func active() -> int:
	return _gusts.size()


static func _level(g: Dictionary) -> float:
	return absf(float(g.strength)) * exp(-float(g.damp) * maxf(float(g.age) - float(g.radius) / SPEED, 0.0))


static func _ensure(host: Node) -> void:
	if _node != null and is_instance_valid(_node) and _node.is_inside_tree():
		return
	_node = Gusts.new()
	_node.name = "Gusts"
	_node.process_mode = Node.PROCESS_MODE_ALWAYS
	host.get_tree().root.add_child.call_deferred(_node)


func _process(delta: float) -> void:
	for g in _gusts:
		g.age = float(g.age) + delta
	_gusts = _gusts.filter(func(g): return float(g.age) < float(g.life))
	if _gusts.is_empty():
		if not _uploaded_idle:
			_upload()
			_uploaded_idle = true
		return
	_uploaded_idle = false
	_upload()


func _upload() -> void:
	var pos := PackedVector4Array()
	var wave := PackedVector4Array()
	for i in MAX:
		if i < _gusts.size():
			var g: Dictionary = _gusts[i]
			var p: Vector3 = g.pos
			pos.append(Vector4(p.x, p.y, p.z, float(g.radius)))
			wave.append(Vector4(float(g.age), float(g.strength), float(g.freq), float(g.damp)))
		else:
			pos.append(Vector4(0, -9999, 0, 0))
			wave.append(Vector4.ZERO)
	var on := 1.0 if not _gusts.is_empty() else 0.0
	var alive: Array = []
	for w in _mats:
		var m: ShaderMaterial = w.get_ref()
		if m == null:
			continue
		alive.append(w)
		m.set_shader_parameter("gust_pos", pos)
		m.set_shader_parameter("gust_wave", wave)
		m.set_shader_parameter("gust_on", on)
	_mats = alive
