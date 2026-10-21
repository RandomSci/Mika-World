class_name FollowCompanion
extends Node
## Walking WITH someone (Milestone K): the follower keeps a companion's place beside and slightly behind the
## leader — on the side she is already on. She steers CONTINUOUSLY along a navmesh path to that place (re-planned
## a few times a second; never teleported), at a pace matched to the leader: a little faster while catching up,
## a little slower when ahead, never a run (the leader waits when she falls behind). When the leader stops and she is close she
## stops too and turns toward her. Local avoidance (WorldCharacter._steer_around) keeps them from bumping.

var leader: WorldCharacter
var follower: WorldCharacter
var side := 0.0                       # +1 right of the leader, -1 left (chosen once, from where she stands)
var released := false                 # she was called away (the show): no more steering; the shared walk ends
var _t := 0.0
var _path := PackedVector3Array()
var _pi := 0
var _slot := Vector3.ZERO
var _fwd := Vector3.FORWARD


func gap() -> float:
	if leader == null or follower == null:
		return 0.0
	return Vector2(leader.global_position.x - follower.global_position.x, leader.global_position.z - follower.global_position.z).length()


func _ready() -> void:
	if follower and follower.current_action == "navigate_to":
		follower.stop_action()


func _physics_process(delta: float) -> void:
	if released or leader == null or follower == null or not is_instance_valid(leader) or not is_instance_valid(follower):
		return
	var hv := Vector3(leader.velocity.x, 0, leader.velocity.z)
	var moving := hv.length() > 0.3
	_t -= delta
	if _t <= 0.0:
		_t = 0.3
		var fwd := -leader.global_transform.basis.z
		if moving:
			fwd = hv.normalized()
		fwd.y = 0
		_fwd = fwd.normalized()
		var right := Vector3(-_fwd.z, 0, _fwd.x)
		if side == 0.0:
			side = 1.0 if (follower.global_position - leader.global_position).dot(right) >= 0.0 else -1.0
		# her place: beside the leader, a little behind while walking, level with her when stopped
		_slot = leader.global_position + right * side * 1.05 - _fwd * (0.5 if moving else 0.0)
		var map := follower.get_world_3d().navigation_map
		_path = NavQuery.path(map, follower.global_position, NavigationServer3D.map_get_closest_point(map, _slot), true)
		_pi = 1
	var d := gap()
	var to_slot := Vector2(_slot.x - follower.global_position.x, _slot.z - follower.global_position.z).length()
	if (not moving and d < 2.0) or to_slot < 0.35:
		follower.set_move_input(Vector3.ZERO, false)
		follower.pace = 1.0
		if not moving:
			var face := leader.global_position - follower.global_position
			face.y = 0
			if face.length() > 0.1 and absf(angle_difference(follower.rotation.y, atan2(-face.x, -face.z))) > 0.5:
				follower.rotation.y = lerp_angle(follower.rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-4.0 * delta))
		return
	# next path corner
	while _pi < _path.size() and Vector2(_path[_pi].x - follower.global_position.x, _path[_pi].z - follower.global_position.z).length() < 0.4:
		_pi += 1
	var aim: Vector3 = _path[_pi] if _pi < _path.size() else _slot
	var dir := Vector3(aim.x - follower.global_position.x, 0, aim.z - follower.global_position.z)
	if dir.length() < 0.05:
		follower.set_move_input(Vector3.ZERO, false)
		return
	# pace: catch up to her place, never overtake her
	var ahead := (follower.global_position - leader.global_position).dot(_fwd)
	# (never a run, never more than a brisk walk: up to 1.45 x a RUN, 5.9 m/s, zipped her after her friend on stream,
	# 2026-10-17. Far behind, the leader waits for her - walk_together.)
	follower.pace = clampf(0.95 + (to_slot - 0.5) * 0.28 - maxf(ahead + 0.2, 0.0) * 0.6, 0.6, 1.12)
	follower.set_move_input(follower._steer_around(dir.normalized()), false)


func _exit_tree() -> void:
	if follower and is_instance_valid(follower):
		follower.pace = 1.0
		follower.set_move_input(Vector3.ZERO, false)
