class_name ClothClearance
extends SkeletonModifier3D
## Hands that never sink into her clothes (profile.clearance): an outfit with a wide hip frill swallows arms that
## hang straight down (the Mixamo idle and walk). While her hands hang beside her hips - standing or walking, not
## running, gesturing, casting, holding something or drawing a sword - they are drawn up to rest folded in front of
## her waist, above the frill (a two-bone IK per arm toward `left` / `right`, hips space, metres; the elbow keeps
## its animated direction and is eased toward `pole`). Blended in and out (no pop), applied after the animation and
## body language, before the VRM springs read the pose. Skeleton space: the VRM faces +Z, her left is +X.

var left := Vector3(0.05, 0.1, 0.19)        # hips space: x left, y up, z forward
var right := Vector3(-0.03, 0.08, 0.2)
var pole := Vector3(0.32, -0.05, -0.18)      # where the elbows point (x mirrored per side)
var weight := {"Left": 0.0, "Right": 0.0}
var allow := true                            # set by the character each frame (casting, holding, sword, running)
var seated := false                          # set by the character: on a seat, the hands rest on her lap instead
var sit_left := Vector3(0.12, 0.08, 0.27)    # hips space: on top of each thigh, above the skirt
var sit_right := Vector3(-0.12, 0.08, 0.27)
var sit_pole := Vector3(0.34, 0.05, -0.05)
var enabled := true
## A floor-length ball gown (profile clearance.knee_max, degrees): while she stands, walks, runs or casts, her thighs
## lift at most this far from her hips' down axis, so a raised knee (the lunging cast, a high running stride) stays
## inside the gown instead of coming out through its front. Off while seated (the gown drapes over her lap). 0 = off.
var knee_max := 0.0
var _knee_w := 0.0
var _idx := {}


static func attach(sk: Skeleton3D, cfg: Dictionary) -> ClothClearance:
	var cc := ClothClearance.new()
	cc.name = "ClothClearance"
	if cfg.has("left"):
		cc.left = Vector3(cfg.left[0], cfg.left[1], cfg.left[2])
	if cfg.has("right"):
		cc.right = Vector3(cfg.right[0], cfg.right[1], cfg.right[2])
	if cfg.has("pole"):
		cc.pole = Vector3(cfg.pole[0], cfg.pole[1], cfg.pole[2])
	if cfg.has("sit_left"):
		cc.sit_left = Vector3(cfg.sit_left[0], cfg.sit_left[1], cfg.sit_left[2])
	if cfg.has("knee_max"):
		cc.knee_max = float(cfg.knee_max)
	if cfg.has("sit_right"):
		cc.sit_right = Vector3(cfg.sit_right[0], cfg.sit_right[1], cfg.sit_right[2])
	sk.add_child(cc)
	return cc


func _bone(n: String) -> int:
	if not _idx.has(n):
		_idx[n] = get_skeleton().find_bone(n) if get_skeleton() else -1
	return _idx[n]


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or not enabled:
		return
	var hips := _bone("Hips")
	if hips < 0:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	var hx := sk.get_bone_global_pose(hips)
	hx.basis = hx.basis.orthonormalized()
	if knee_max > 0.0:
		_knee_w = lerpf(_knee_w, 0.0 if seated else 1.0, 1.0 - exp(-6.0 * dt))
		if _knee_w > 0.002:
			var down := -hx.basis.y
			for side in ["Left", "Right"]:
				var ul := _bone(side + "UpperLeg")
				var ll := _bone(side + "LowerLeg")
				if ul < 0 or ll < 0:
					continue
				var th := (sk.get_bone_global_pose(ll).origin - sk.get_bone_global_pose(ul).origin).normalized()
				var ax := down.cross(th)
				if rad_to_deg(th.angle_to(down)) <= knee_max or ax.length() < 1e-5:
					continue
				var lim := down.rotated(ax.normalized(), deg_to_rad(knee_max))
				_turn(sk, ul, th, th.slerp(lim, _knee_w))
	for side in ["Left", "Right"]:
		var ua := _bone(side + "UpperArm")
		var la := _bone(side + "LowerArm")
		var hd := _bone(side + "Hand")
		if ua < 0 or la < 0 or hd < 0:
			continue
		# does the animated hand hang beside the hips (where the frill is)?
		var w0 := sk.get_bone_global_pose(hd).origin
		var hp := hx.affine_inverse() * w0
		var hang := smoothstep(0.25, 0.0, hp.y) * smoothstep(-0.7, -0.45, hp.y) * smoothstep(0.45, 0.32, Vector2(hp.x, hp.z).length())
		var want := (1.0 if seated else hang) if allow else 0.0
		weight[side] = lerpf(weight[side], want, 1.0 - exp(-(5.0 if want > weight[side] else 7.0) * dt))
		var w: float = weight[side]
		if w < 0.002:
			continue
		var s := sk.get_bone_global_pose(ua).origin
		var e := sk.get_bone_global_pose(la).origin
		var tgt_local := (sit_left if side == "Left" else sit_right) if seated else (left if side == "Left" else right)
		var t := w0.lerp(hx * tgt_local, w)
		var pl := sit_pole if seated else pole
		if side == "Right":
			pl.x = -pl.x
		var pole_pt := e.lerp(hx * pl, w)
		_two_bone(sk, ua, la, hd, s, e, t, pole_pt)


## Upper arm and forearm turned (about their own heads, skeleton space) so the wrist reaches t, the elbow toward pole_pt.
func _two_bone(sk: Skeleton3D, ua: int, la: int, hd: int, s: Vector3, e: Vector3, t: Vector3, pole_pt: Vector3) -> void:
	var w := sk.get_bone_global_pose(hd).origin
	var a := s.distance_to(e)
	var b := e.distance_to(w)
	var d := clampf(s.distance_to(t), 0.05, (a + b) * 0.999)
	var dir := (t - s).normalized()
	var n := (pole_pt - s) - dir * (pole_pt - s).dot(dir)
	if n.length() < 1e-4:
		n = (e - s) - dir * (e - s).dot(dir)
	n = n.normalized()
	var ca := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var e2 := s + dir * (a * ca) + n * (a * sqrt(1.0 - ca * ca))
	_turn(sk, ua, e - s, e2 - s)
	var e_now := sk.get_bone_global_pose(la).origin
	var w_now := sk.get_bone_global_pose(hd).origin
	_turn(sk, la, w_now - e_now, (s + dir * d) - e_now)


func _turn(sk: Skeleton3D, idx: int, from: Vector3, to: Vector3) -> void:
	if from.length() < 1e-5 or to.length() < 1e-5:
		return
	var f := from.normalized()
	var t := to.normalized()
	var ax := f.cross(t)
	if ax.length() < 1e-6:
		return
	var r := Basis(ax.normalized(), f.angle_to(t))
	var g := sk.get_bone_global_pose(idx)
	var parent := sk.get_bone_parent(idx)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var local := (pg.basis.inverse() * (r * g.basis)).orthonormalized()
	sk.set_bone_pose_rotation(idx, local.get_rotation_quaternion())
