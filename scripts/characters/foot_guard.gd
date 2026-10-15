class_name FootGuard
extends SkeletonModifier3D
## Feet never sink into the floor. Some clips (the Mixamo dances above all) carry the hips away from where her body
## stands, or lower them further than her legs allow: a foot then lands inside a raised floor (the ritual circle's
## stone) or under the ground. After the animation and the other pose modifiers, the real ground under each foot is
## found (a ray against the world) and the hips are lifted just enough that neither foot goes below it - never
## lowered, eased so it does not pop. Off while she sits / lies (PoseAdjust lowers her on purpose) or is airborne.
## Skeleton space: the VRM faces +Z, her left is +X; the character's origin is at her feet.

var enabled := true
var lift := 0.0                 # metres the hips are currently raised (tests)
var worst_before := 0.0         # deepest a foot was below the ground before this frame's correction (tests)
var _idx := {}
var _sole := {}                 # foot bone -> its rest height above the floor (ankle / toe)


func _bone(n: String) -> int:
	if not _idx.has(n):
		_idx[n] = get_skeleton().find_bone(n) if get_skeleton() else -1
	return _idx[n]


func _process_modification() -> void:
	var sk := get_skeleton()
	var c := get_parent()
	while c != null and not (c is WorldCharacter):
		c = c.get_parent()
	if sk == null or c == null or not enabled or not sk.is_inside_tree():
		return
	var wc := c as WorldCharacter
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	var hips := _bone("Hips")
	if hips < 0 or (wc.pose_adjust and wc.pose_adjust.influence > 0.05) or wc.lifted or not wc.is_on_floor():
		lift = lerpf(lift, 0.0, 1.0 - exp(-10.0 * dt))
		_apply(sk, hips)
		return
	var space := sk.get_world_3d().direct_space_state
	var need := 0.0
	worst_before = 0.0
	for b in ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]:
		var bi := _bone(b)
		if bi < 0:
			continue
		if not _sole.has(b):
			_sole[b] = maxf(sk.get_bone_global_rest(bi).origin.y, 0.02)
		var p := sk.global_transform * sk.get_bone_global_pose(bi).origin
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p - Vector3(0, 0.6, 0), 1)
		q.exclude = [wc.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var below: float = ((hit.position as Vector3).y + float(_sole[b]) * 0.85) - p.y
		worst_before = maxf(worst_before, below)
		need = maxf(need, below)                 # the animation re-poses the hips every frame: this is the whole deficit
	need = clampf(need, 0.0, 0.45)
	# up at once (a foot must not be seen inside the floor), down gently
	lift = need if need > lift else lerpf(lift, need, 1.0 - exp(-6.0 * dt))
	_apply(sk, hips)


func _apply(sk: Skeleton3D, hips: int) -> void:
	if hips < 0 or lift < 0.001:
		return
	sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) + Vector3(0, lift, 0))
