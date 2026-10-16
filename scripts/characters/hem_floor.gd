class_name HemFloor
extends Node
## The floor under her skirt (the clip survey: a long gown's hem sank 0-8 cm through the dais, ramps and stone floors
## in 31% of Luna's frames, Mika's in 13%). Every skirt / cape / sash chain gets a ground collider whose top follows
## the floor under her feet, so the hem rests on it instead of going through. Off while she lies down (LyingSprings
## has its own ground then).

const R := 40.0
var c: WorldCharacter
var _balls: Array = []               # [node, chain hit radius]
var _sec: Node


static func attach(ch: WorldCharacter) -> HemFloor:
	if ch == null or ch.avatar == null:
		return null
	for n in ch.get_children():
		if n is HemFloor:
			n.queue_free()
	var h := HemFloor.new()
	h.name = "HemFloor"
	h.c = ch
	ch.add_child(h)
	return h


func _ready() -> void:
	process_priority = -50            # placed before the skeleton's spring update this frame
	_sec = c.avatar.find_child("secondary", true, false)
	if _sec == null or _sec.get("spring_bones") == null:
		return
	var n := 0
	for sb in _sec.spring_bones:
		var cm := String(sb.comment)
		if not (cm.begins_with("Skirt") or cm.begins_with("Cape") or cm.begins_with("Sash")):
			continue
		var hr: PackedFloat64Array = sb.hit_radius
		var rmax := 0.0
		for v in hr:
			rmax = maxf(rmax, v)
		rmax = float(sb.hit_radius_scale) * (rmax if not hr.is_empty() else 1.0)
		var ball := Node3D.new()
		ball.name = "HemFloor_%d" % n
		c.add_child(ball)
		var col = load("res://addons/vrm/vrm_collider.gd").new()
		col.radius = R
		col.node_path = ball.get_path()
		var grp = load("res://addons/vrm/vrm_collider_group.gd").new()
		grp.colliders.append(col)
		sb.collider_groups.append(grp)
		_balls.append([ball, rmax])
		n += 1
	_place()
	if n > 0 and _sec.has_method("_on_recreate_collider"):
		_sec._on_recreate_collider()


func _process(_d: float) -> void:
	_place()


func _place() -> void:
	if _balls.is_empty() or c.skeleton == null:
		return
	# lying: LyingSprings' ground is under her; this one sinks out of the way
	var lying := c.ground_pose == "lie" or c.has_meta("lying_springs")
	var feet := c.global_position
	var nrm := Vector3.UP
	# the floor's own tilt under her (a ramp, a slope): the hem follows it, not a level plane at her feet
	var space := c.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(feet + Vector3(0, 0.6, 0), feet + Vector3(0, -0.4, 0), 1)
	q.exclude = [c.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and (hit.normal as Vector3).y > 0.6:
		feet = hit.position
		nrm = hit.normal
	var s_inv := c.skeleton.global_transform.affine_inverse()
	for b in _balls:
		var depth := (0.01 - float(b[1]) - R) - (30.0 if lying else 0.0)
		# (vrm_secondary hands node colliders S where S^-1 is meant: S^-1 * S^-1 * the point cancels it - LyingSprings)
		(b[0] as Node3D).global_transform = s_inv * s_inv * Transform3D(Basis.IDENTITY, feet + nrm * depth)
