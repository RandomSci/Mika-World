class_name MotionMatch
extends RefCounted
## Combat v3 motion matching (Clavet's idea, For Honor / GDC, small): the next move is the one whose START pose and
## velocity match where her body is now, so moves chain without a reset pose.
##   features: both hands and both feet relative to her hips (skeleton space: x her left, y up, z forward), her hip
##             turn, her hips' velocity in her own frame
##   key-pose moves (MeleeBook): cost = the features against the move's windup pose -> a weight factor for the brain
##   mocap clips (MoveCatalog): the best frame to START the clip from (searched in its first 35 %), so a clip cuts in
##             at the pose she is already in instead of snapping to its first frame
## Remi123/MotionMatching (the suggested addon) targets Godot 4.2 as an unfinished C++ GDExtension, so this is ours.

const W_POS := 1.0                       # per metre of hand / foot distance
const W_YAW := 0.6                       # per 90 deg of hip turn
const W_VEL := 0.25                      # per m/s of hip velocity difference
const SIGMA := 0.35                      # cost -> weight: exp(-cost / SIGMA)

static var _clip_cache := {}             # "<skeleton id>:<clip>" -> [[t, features]]


## Her features now, from the rig's current key pose (what she is doing, not where the clip put her).
static func now(f: MeleeFighter) -> Dictionary:
	var P: Dictionary = f.P
	var inv := f.sk.global_transform.affine_inverse()
	var feet := {}
	for side in ["lf", "rf"]:
		var w: Vector3 = (f.feet[side].pos as Vector3) if f.feet.has(side) else Vector3.ZERO
		var l: Vector3 = inv * w
		feet[side] = Vector3(l.x, 0.0, l.z)
	var vel: Vector3 = f.sk.global_transform.basis.inverse() * f._root_vel
	return {"lh": P.lh, "rh": P.rh, "lf": feet.lf, "rf": feet.rf, "yaw": float((P.hip_rot as Vector3).y), "vel": vel}


## The cost of starting a key-pose move from her current pose (0 = it starts exactly where she is).
static func move_cost(f: MeleeFighter, m: Dictionary) -> float:
	var a := now(f)
	var key: Dictionary = f.scaled(m.keys[0])
	var c := 0.0
	for limb in ["lh", "rh"]:
		c += W_POS * (a[limb] as Vector3).distance_to(key[limb])
	for side in ["lf", "rf"]:
		var kf: Vector3 = key[side]
		c += W_POS * 0.6 * (a[side] as Vector3).distance_to(Vector3(kf.x, 0.0, kf.z))
	c += W_YAW * absf(wrapf(float(a.yaw) - float((key.hip_rot as Vector3).y), -180.0, 180.0)) / 90.0
	# a move that steps in suits a body already moving forward; a back-foot move one drifting back
	var vz: float = (a.vel as Vector3).z
	var want := 0.6 if m.get("travel", 0.0) > 0.0 else 0.0
	c += W_VEL * absf(vz - want)
	return c


static func weight(cost: float) -> float:
	return exp(-cost / SIGMA)


## The time to start a mocap clip from: the frame in its first 35 % whose hands / feet (relative to the hips) are
## nearest to hers now. `anim` is the baked clip (tracks "...:Bone").
static func best_start(f: MeleeFighter, clip: String, anim: Animation) -> float:
	var key := str(f.sk.get_instance_id()) + ":" + clip
	if not _clip_cache.has(key):
		var bare := PoseSkel.from(f.sk)
		var rows := []
		var n := int(anim.length * 0.35 * 15.0) + 1
		for i in n:
			var t := float(i) / 15.0
			JointAudit.pose_at(bare, anim, t)
			rows.append([t, _bare_features(bare)])
		_clip_cache[key] = rows
	var cur := _bare_features_from_trace(f)
	var best := 0.0
	var bc := INF
	for r in _clip_cache[key]:
		var fe: Dictionary = r[1]
		var c := 0.0
		for p in ["lh", "rh", "lf", "rf"]:
			c += (fe[p] as Vector3).distance_to(cur[p])
		if c < bc:
			bc = c
			best = float(r[0])
	return best


static func _bare_features(sk: PoseSkel) -> Dictionary:
	var hips := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	var out := {}
	for pair in [["lh", "LeftHand"], ["rh", "RightHand"], ["lf", "LeftFoot"], ["rf", "RightFoot"]]:
		out[pair[0]] = sk.get_bone_global_pose(sk.find_bone(pair[1])).origin - hips
	return out


static func _bare_features_from_trace(f: MeleeFighter) -> Dictionary:
	var inv := f.sk.global_transform.affine_inverse()
	var hips: Vector3 = inv * (f.trace.get("Hips", f.sk.global_position) as Vector3)
	var out := {}
	for pair in [["lh", "LeftHand"], ["rh", "RightHand"], ["lf", "LeftFoot"], ["rf", "RightFoot"]]:
		out[pair[0]] = inv * (f.trace.get(pair[1], f.sk.global_position) as Vector3) - hips
	return out
