class_name PoseSkel
extends RefCounted
## A skeleton as plain data (names, parents, rests, local poses) with its own forward kinematics: the calls JointAudit
## and MotionMatch use (find_bone, get_bone_global_pose, set_bone_global_pose ...), so clips can be posed, audited and
## fixed anywhere - also while characters are being built (a Skeleton3D outside the scene tree never updates its global
## poses, and the tree refuses new children while it is busy).

var names := PackedStringArray()
var parent := PackedInt32Array()
var rest: Array[Transform3D] = []
var pos: Array[Vector3] = []
var rot: Array[Quaternion] = []
var _global: Array[Transform3D] = []
var _rest_global: Array[Transform3D] = []
var _dirty := true
var _index := {}


static func from(src: Skeleton3D) -> PoseSkel:
	var p := PoseSkel.new()
	for i in src.get_bone_count():
		p.names.append(src.get_bone_name(i))
		p.parent.append(src.get_bone_parent(i))
		var r := src.get_bone_rest(i)
		p.rest.append(r)
		p.pos.append(r.origin)
		p.rot.append(r.basis.get_rotation_quaternion())
		p._index[src.get_bone_name(i)] = i
	p._global.resize(p.names.size())
	p._rest_global.resize(p.names.size())
	for i in p.names.size():
		var pr := p.parent[i]
		p._rest_global[i] = (p._rest_global[pr] * p.rest[i]) if pr >= 0 else p.rest[i]
	return p


func get_bone_count() -> int:
	return names.size()


func find_bone(n: String) -> int:
	return int(_index.get(n, -1))


func get_bone_name(i: int) -> String:
	return names[i]


func get_bone_parent(i: int) -> int:
	return parent[i]


func get_bone_rest(i: int) -> Transform3D:
	return rest[i]


func get_bone_global_rest(i: int) -> Transform3D:
	return _rest_global[i]


func get_bone_pose_rotation(i: int) -> Quaternion:
	return rot[i]


func set_bone_pose_rotation(i: int, q: Quaternion) -> void:
	rot[i] = q.normalized()
	_dirty = true


func set_bone_pose_position(i: int, v: Vector3) -> void:
	pos[i] = v
	_dirty = true


func set_bone_pose(i: int, t: Transform3D) -> void:
	pos[i] = t.origin
	rot[i] = t.basis.get_rotation_quaternion()
	_dirty = true


func _update() -> void:
	# bones are listed parents first in a VRM skeleton (Skeleton3D keeps that order)
	for i in names.size():
		var local := Transform3D(Basis(rot[i]), pos[i])
		var pr := parent[i]
		_global[i] = (_global[pr] * local) if pr >= 0 else local
	_dirty = false


func get_bone_global_pose(i: int) -> Transform3D:
	if _dirty:
		_update()
	return _global[i]


func set_bone_global_pose(i: int, t: Transform3D) -> void:
	if _dirty:
		_update()
	var pr := parent[i]
	var local := (_global[pr].affine_inverse() * t) if pr >= 0 else t
	pos[i] = local.origin
	rot[i] = local.basis.orthonormalized().get_rotation_quaternion()
	_dirty = true


## (Skeleton3D API parity for callers that force an update)
func force_update_all_bone_transforms() -> void:
	_update()


func force_update_bone_child_transform(_i: int) -> void:
	_update()


func free() -> void:
	pass
