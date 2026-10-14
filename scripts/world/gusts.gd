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
	# the runner must exist for the bodies parting the plants (not only once a gust is emitted)
	var ml := Engine.get_main_loop() as SceneTree
	if ml and ml.root:
		_ensure(ml.root)


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
	if _node != null and is_instance_valid(_node) and not _node.is_queued_for_deletion():
		return                       # in the tree, or being added this frame
	if host == null or host.get_tree() == null:
		return
	_node = Gusts.new()
	_node.name = "Gusts"
	_node.process_mode = Node.PROCESS_MODE_ALWAYS
	host.get_tree().root.add_child.call_deferred(_node)


## Bodies part the plants (V3 continuation): every visible mage and creature, nearest the camera first, up to six,
## uploaded to every registered plant material each frame.
const BODIES := 6
var _bodies_last := PackedVector4Array()


func _bodies() -> void:
	var cam := get_viewport().get_camera_3d()
	var list := []
	for n in get_tree().get_nodes_in_group("avoid"):
		var b := n as Node3D
		if b == null or not b.is_visible_in_tree():
			continue
		var r := 0.42
		if n is WorldCharacter:
			r = 0.42 if (n as WorldCharacter).ground_pose == "" else 0.7
		elif n.get("def") is Dictionary:
			r = float(n.get("def").get("radius", 0.5)) + 0.25
		var d := cam.global_position.distance_to(b.global_position) if cam else 0.0
		list.append([d, Vector4(b.global_position.x, b.global_position.y, b.global_position.z, r)])
	list.sort_custom(func(a, c): return float(a[0]) < float(c[0]))
	var arr := PackedVector4Array()
	for i in BODIES:
		arr.append(list[i][1] if i < list.size() else Vector4(0, -9999, 0, 0))
	if arr == _bodies_last:
		return
	_bodies_last = arr
	var on := 1.0 if not list.is_empty() else 0.0
	for w in _mats:
		var m: ShaderMaterial = w.get_ref()
		if m:
			m.set_shader_parameter("body_pos", arr)
			m.set_shader_parameter("body_on", on)


func _process(delta: float) -> void:
	_bodies()
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
