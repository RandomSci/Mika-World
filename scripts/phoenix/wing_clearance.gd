class_name WingClearance
extends SkeletonModifier3D
## Runs after the clip and the gaze (the cinematic pass, 2026-10-14 - the developer: "the body of it is going through
## the other things"): a wing or the train may never pass into the ground, the terrace stones or a wall. Each frame
## the tips of her outer primaries (Prim3/6/9) and of her train (Stream3, the tail fan) are tested against what is
## really under them (a ray down onto the world's collision, else the area's terrain); where one would sink below
## it (plus a margin), the whole wing is lifted at the shoulder - or the train at its base - by just enough, eased in
## and out so the clip's motion stays alive. The bird's own body is never tested (world layer only).

const MARGIN := 0.14
const WING_TIPS := {"Prim9": 1.8, "Prim6": 2.04, "Prim3": 1.72, "Sec8": 1.4}
const TAIL_TIPS := {"Stream3_L": 0.9, "Stream3_R": 0.9, "TailF0": 1.0, "TailF3": 1.1, "TailF6": 1.0}

var area: Node = null                 # has ground_at(x, z)
var lifted := {"L": 0.0, "R": 0.0, "T": 0.0}   # current lift angles (radians), for tests
var max_lift := deg_to_rad(55.0)
var measure := false                  # tests: after correcting, record how far the lowest tip stands above the ground
var min_clearance := INF              # lowest tip - ground seen while measuring (metres; negative = it sank in)
var min_where := ""                   # which tip, and what the rig was doing
var _axis := {}


func _ground(sk: Skeleton3D, p: Vector3) -> float:
	var g := -1e9
	if area != null and is_instance_valid(area) and area.has_method("ground_at"):
		g = float(area.ground_at(p.x, p.z))
	var w := sk.get_world_3d()
	if w:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.5, 0), p + Vector3(0, -3.0, 0), 1)
		var hit := w.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			g = maxf(g, (hit.position as Vector3).y)
	return g


## The swing (skeleton space) that lifts the worst-sunk of `tips` clear: [angle, axis]. The axis is horizontal and
## perpendicular to the pivot->tip direction, so the tip rises straight up whatever way the wing reaches.
func _needed(sk: Skeleton3D, pivot_bone: String, tips: Dictionary, sfx: String) -> Array:
	var pi_ := sk.find_bone(pivot_bone)
	if pi_ < 0:
		return [0.0, Vector3.RIGHT]
	var xf := sk.global_transform
	var sc := xf.basis.get_scale().y
	var pivot := sk.get_bone_global_pose(pi_).origin
	var best := 0.0
	var axis := Vector3.RIGHT
	for bn in tips:
		var bi := sk.find_bone(String(bn) + sfx)
		if bi < 0:
			continue
		var gp := sk.get_bone_global_pose(bi)
		var tip := gp.origin + gp.basis.y.normalized() * float(tips[bn])
		var wt := xf * tip
		var deficit := (_ground(sk, wt) + MARGIN) - wt.y
		if deficit <= 0.0:
			continue
		var v := tip - pivot
		var hl2 := v.x * v.x + v.z * v.z
		if hl2 < 0.01:
			continue
		var ang := (deficit / sc) * v.length() / hl2
		if ang > best:
			best = ang
			axis = v.cross(Vector3.UP).normalized()
	return [minf(best * 1.1, max_lift), axis]


func _swing(sk: Skeleton3D, bone: String, axis: Vector3, ang: float) -> void:
	var bi := sk.find_bone(bone)
	if bi < 0 or absf(ang) < 1e-4:
		return
	var gp := sk.get_bone_global_pose(bi)
	var nb := Basis(axis.normalized(), ang) * gp.basis
	var parent := sk.get_bone_parent(bi)
	var pb := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bi, (pb.inverse() * nb).get_rotation_quaternion())
	sk.force_update_bone_child_transform(bi)


func _ease(key: String, need: float) -> float:
	# rise at once to what is needed; relax back slowly (no flicker as tips graze the ground)
	var cur := float(lifted[key])
	var v := need if need > cur else lerpf(cur, need, 0.18)
	lifted[key] = v
	return v


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or not sk.is_visible_in_tree():
		return        # her bird body is hidden (the woman stands here): nothing to keep out of the ground
	var jobs := [["L", "Shoulder_L", WING_TIPS, "_L"], ["R", "Shoulder_R", WING_TIPS, "_R"], ["T", "TailBase", TAIL_TIPS, ""]]
	for j in jobs:
		var key: String = j[0]
		var r: Array = _needed(sk, String(j[1]), j[2], String(j[3]))
		var want := _ease(key, float(r[0]))
		if want > 1e-4:
			var ax: Vector3 = r[1] if float(r[0]) > 1e-4 else _axis.get(key, Vector3.RIGHT)
			_axis[key] = ax
			_swing(sk, String(j[1]), ax, want)
			# a second look: big swings are not linear
			var r2: Array = _needed(sk, String(j[1]), j[2], String(j[3]))
			if float(r2[0]) > 1e-3:
				_swing(sk, String(j[1]), r2[1], float(r2[0]))
	if measure:
		for side in ["L", "R"]:
			min_clearance = minf(min_clearance, _lowest(sk, WING_TIPS, "_" + side))
		min_clearance = minf(min_clearance, _lowest(sk, TAIL_TIPS, ""))


func _lowest(sk: Skeleton3D, tips: Dictionary, sfx: String) -> float:
	var lo := INF
	for bn in tips:
		var bi := sk.find_bone(String(bn) + sfx)
		if bi < 0:
			continue
		var gp := sk.get_bone_global_pose(bi)
		var wt := sk.global_transform * (gp.origin + gp.basis.y.normalized() * float(tips[bn]))
		var c := wt.y - _ground(sk, wt)
		if c < min_clearance:
			var rig := sk.get_parent()
			while rig != null and not (rig is PhoenixTrueRig):
				rig = rig.get_parent()
			min_where = "%s%s in %s" % [bn, sfx, (rig as PhoenixTrueRig).state if rig else "?"]
		lo = minf(lo, c)
	return lo
