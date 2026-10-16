class_name FramingRule
extends RefCounted
## PERMANENT CAMERA RULE (developer, 2026-10-16, "for every scene, forever" - docs/world_look_rules.md):
## never a close-up of Mika or Luna. No face shots; no shot where a face fills more than 10% of the frame height.
## Only wide and medium-wide shots: full body or at least knees up, always with the environment around them.
## Every camera that can frame a mage goes through enforce() (the director, the transformation camera, the scene
## cameras), and FramingGuard re-checks whatever camera is live each frame as the last line of defence.

const MAX_FACE_FRAC := 0.10      # of the frame height
const HEAD_H := 0.26             # metres, chin to the top of the head (with hair / ears) - a margin over the face itself
const MAX_FOV := 72.0            # widening the lens is the last resort after pulling back


## The closest a camera may be to a head for this vertical FOV.
static func min_distance(fov_deg: float) -> float:
	return HEAD_H / (MAX_FACE_FRAC * 2.0 * tan(deg_to_rad(fov_deg) * 0.5))


## How much of the frame height a head at `head` takes from `pos` with this FOV (0..1).
static func face_frac(pos: Vector3, head: Vector3, fov_deg: float) -> float:
	var d := maxf(pos.distance_to(head), 0.01)
	return HEAD_H / (2.0 * d * tan(deg_to_rad(fov_deg) * 0.5))


## A face aim point becomes a chest aim point (medium-wide framing looks at the body, not the face).
static func body_look(look: Vector3, heads: Array) -> Vector3:
	for h in heads:
		if (look as Vector3).distance_to(h) < 0.35:
			return (h as Vector3) - Vector3(0, 0.5, 0)
	return look


## Make a shot obey the rule. heads = world positions of the mages' heads that could be in this frame.
## Pulls the camera straight back from what it looks at (along a clear line: `space` may be null), then widens the
## lens if it still cannot get far enough. Returns {pos, look, fov, changed}.
static func enforce(pos: Vector3, look: Vector3, fov: float, heads: Array, space: PhysicsDirectSpaceState3D = null, mask := 1) -> Dictionary:
	var out := {"pos": pos, "look": body_look(look, heads), "fov": fov, "changed": false}
	for h in heads:
		var head: Vector3 = h
		var view := (out.look as Vector3) - (out.pos as Vector3)
		if view.length() < 0.01:
			continue
		var to_head := head - (out.pos as Vector3)
		# only heads that are actually in (or right at the edge of) this frame
		if to_head.length() > 0.01 and rad_to_deg(view.angle_to(to_head)) > float(out.fov) * 0.5 * 1.25:
			continue
		var need := min_distance(float(out.fov))
		var d := to_head.length()
		if d >= need:
			continue
		var back := ((out.pos as Vector3) - (out.look as Vector3)).normalized()
		var want: Vector3 = (out.pos as Vector3) + back * (need - d + 0.05)
		if space:
			var q := PhysicsRayQueryParameters3D.create(out.look, want, mask)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				want = (hit.position as Vector3) - back * 0.25
		out.pos = want
		out.changed = true
		var d2 := (out.pos as Vector3).distance_to(head)
		if d2 < need:
			# could not pull back far enough (a wall behind): open the lens instead
			out.fov = minf(rad_to_deg(2.0 * atan(HEAD_H / (MAX_FACE_FRAC * 2.0 * d2))), MAX_FOV)
	return out


## Heads of the mages currently in the world (visible ones), for enforce().
static func heads_of(chars: Array) -> Array:
	var out := []
	for c in chars:
		if c == null or not is_instance_valid(c) or not (c as Node3D).is_visible_in_tree():
			continue
		var sk: Skeleton3D = c.get("skeleton")
		var hb := sk.find_bone("Head") if sk else -1
		if hb >= 0:
			out.append(sk.global_transform * sk.get_bone_global_pose(hb).origin + Vector3(0, 0.08, 0))
		else:
			out.append((c as Node3D).global_position + Vector3(0, 1.45, 0))
	return out
