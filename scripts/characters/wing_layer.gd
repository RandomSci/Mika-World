class_name WingLayer
extends SkeletonModifier3D
## Feathered wings with their own bones (appearance profile "wings": {"bones": {"L": [root, arch, tip], "R": [...]},
## "flap_deg": 5, "flap_hz": 0.22, "sit": "fold" | "hide"}). Procedural, after the animation, before the VRM springs
## read the pose (the hair and cape collide with capsules on these bones):
##   idle   - a slow, gentle flap (the whole wing rises and settles about its root; the tip lags a little)
##   spread - while she casts, attacks or transforms: opened wider and lifted
##   fold   - seated or lying down: swept back along her back and lowered, the outer bone tucked in
##   hidden - profile sit = "hide": the wing meshes are hidden while seated
## Skeleton space: the VRM faces +Z, her left is +X, up is +Y.

var bones := {"L": [], "R": []}
var flap_deg := 5.0
var flap_hz := 0.22
var sit_mode := "fold"
var seated := false              # set by the character each frame (seated, lying, knocked down)
var spread := false              # set by the character each frame (casting, sword, transformation)
var meshes: Array = []
var _fold := 0.0
var _spread := 0.0
var _t := 0.0


static func attach(sk: Skeleton3D, avatar: Node, cfg: Dictionary) -> WingLayer:
	var w := WingLayer.new()
	w.name = "WingLayer"
	var b: Dictionary = cfg.get("bones", {})
	for side in ["L", "R"]:
		for n in b.get(side, ["J_Sec_Wing%s_0" % side, "J_Sec_Wing%s_1" % side, "J_Sec_Wing%s_2" % side]):
			var i := sk.find_bone(String(n))
			if i >= 0:
				w.bones[side].append(i)
	w.flap_deg = float(cfg.get("flap_deg", 5.0))
	w.flap_hz = float(cfg.get("flap_hz", 0.22))
	w.sit_mode = String(cfg.get("sit", "fold"))
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		if "Wing" in String(mi.name):
			w.meshes.append(mi)
	if w.bones.L.is_empty() and w.bones.R.is_empty():
		push_warning("[wings] no wing bones found")
	sk.add_child(w)
	return w


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	_t += dt
	_fold = lerpf(_fold, 1.0 if seated else 0.0, 1.0 - exp(-3.0 * dt))
	_spread = lerpf(_spread, 1.0 if spread and not seated else 0.0, 1.0 - exp(-4.0 * dt))
	var hide := seated and sit_mode == "hide"
	for m in meshes:
		(m as MeshInstance3D).visible = not hide
	var ph := _t * TAU * flap_hz
	for side in ["L", "R"]:
		var bl: Array = bones[side]
		if bl.size() < 2:
			continue
		var s := 1.0 if side == "L" else -1.0
		var flap := sin(ph) * flap_deg * (1.0 - _fold) * (1.0 - 0.5 * _spread)
		# root: flap (about forward +Z), spread (lift + open forward a little), fold (swing back about +Y, lower)
		var lift := flap + _spread * 12.0 - _fold * 18.0
		var swing := -_spread * 8.0 + _fold * 62.0
		_rotate(sk, bl[0], Basis(Vector3.UP, deg_to_rad(s * swing)) * Basis(Vector3.BACK, deg_to_rad(-s * lift)))
		# arch: the outer wing lags the flap and tucks in when folded
		var lag := sin(ph - 0.9) * flap_deg * 0.6 * (1.0 - _fold)
		_rotate(sk, bl[1], Basis(Vector3.UP, deg_to_rad(s * _fold * 35.0)) * Basis(Vector3.BACK, deg_to_rad(-s * (lag - _fold * 10.0))))
		if bl.size() > 2:
			_rotate(sk, bl[2], Basis(Vector3.UP, deg_to_rad(s * _fold * 20.0)))


## Turns a bone by r (skeleton space) about its own head, keeping its animated pose otherwise.
func _rotate(sk: Skeleton3D, idx: int, r: Basis) -> void:
	var g := sk.get_bone_global_pose(idx)
	var parent := sk.get_bone_parent(idx)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var local := (pg.basis.inverse() * (r * g.basis)).orthonormalized()
	sk.set_bone_pose_rotation(idx, local.get_rotation_quaternion())
