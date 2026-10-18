class_name TasselSway
extends SkeletonModifier3D
## Her belt cords (Luna design B: J_Sec_BeltL/R_0 -> _1, the whole floor-length strand skinned to the short second
## bone) hung straight to the water like two rods between her legs whatever she did (Selwyn, 2026-10-19: "shorten them
## or add physics so they swing"). Both: the strand is shortened along its length, and it swings - its tip is a damped
## spring that follows where the hips carry it, and the cord turns toward it.

var length_scale := 0.42
var stiffness := 55.0
var damping := 7.5
var max_swing := deg_to_rad(55.0)
var _dt := 1.0 / 30.0
var _ids: Array = []                     # [second bone]
var _tip := {}                           # bone -> [pos, vel]


static func make(sk: Skeleton3D, at := 2) -> TasselSway:
	# the VRM secondary's own spring chain hangs the cords straight down after every modifier: take them out of it
	var top := sk.get_parent()
	while top and top.find_child("secondary", true, false) == null and top.get_parent():
		top = top.get_parent()
	var sec = top.find_child("secondary", true, false) if top else null
	if sec and sec.get("spring_bones_internal") != null:
		var keep := []
		var keep_c := []
		var centers = sec.get("springs_centers")
		for i in sec.spring_bones_internal.size():
			var sb = sec.spring_bones_internal[i]
			var belt := false
			for j in sb.joint_nodes:
				if String(j).contains("Belt"):
					belt = true
			if not belt:
				keep.append(sb)
				if centers != null and i < centers.size():
					keep_c.append(centers[i])
		var n: int = sec.spring_bones_internal.size() - keep.size()
		sec.spring_bones_internal.assign(keep)
		if centers != null:
			sec.springs_centers = PackedInt32Array(keep_c)     # (parallel to the chains: index i's centre)
		print("[tassel] took %d belt chain(s) out of the VRM springs" % n)
	var t := TasselSway.new()
	t.name = "TasselSway"
	sk.add_child(t)
	PosePipeline.arrange_for(sk)
	return t


func _process(delta: float) -> void:
	_dt = delta


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		for side in ["L", "R"]:
			var b1 := sk.find_bone("J_Sec_Belt%s_1" % side)
			if b1 >= 0:
				_ids.append(b1)
		if _ids.is_empty():
			_ids.append(-1)
	for b1 in _ids:
		if b1 < 0:
			continue
		sk.set_bone_pose_scale(b1, Vector3(1.0, length_scale, 1.0))
		var g := sk.get_bone_global_pose(b1)
		var down := (g.basis * Vector3(0, -1, 0))
		if down.length() < 0.0001:
			continue
		down = down.normalized()
		var L := 0.35
		var want_tip := g.origin + down * L
		var st: Array = _tip.get(b1, [want_tip, Vector3.ZERO])
		var p: Vector3 = st[0]
		var v: Vector3 = st[1]
		v += ((want_tip - p) * stiffness - v * damping) * _dt
		p += v * _dt
		var dir := (p - g.origin)
		dir = dir.normalized() if dir.length() > 0.0001 else down
		var ang := down.angle_to(dir)
		if ang > max_swing:
			dir = down.slerp(dir, max_swing / ang)
			p = g.origin + dir * L
		_tip[b1] = [p, v]
		if down.dot(dir) < 0.9999:
			sk.set_bone_global_pose(b1, Transform3D(Basis(Quaternion(down, dir)) * g.basis, g.origin))
