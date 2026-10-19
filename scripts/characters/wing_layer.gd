class_name WingLayer
extends SkeletonModifier3D
## Feathered wings, driven procedurally after the animation and before the VRM springs read the pose (the hair and
## cape collide with capsules on the shoulder and elbow bones). Appearance profile "wings": {"sit": "fold"|"hide",
## "flap_deg", "flap_hz"}.
##
## A built wing (tools/models/wing_build.py) is an anatomical bird wing modelled OPEN: shoulder J_Sec_Wing{s}_0 ->
## elbow _1 -> wrist _Wrist -> hand tip _HandTip; one bone per flight feather: primaries _P0 (inner) .. _P9 (tip) on
## the hand, secondaries _S0.._S11 on the forearm, tertials _T0.._T2 on the upper arm; coverts skinned smoothly to
## the arm. A pose is a set of angles in the plane of her back (0 = straight out to the side, + = up):
##   arm / fore / hand - the three arm segments' directions
##   fan   - the primaries' spread about the hand (1 = as modelled, open; 0 = closed along the hand)
##   sec   - the secondaries' and tertials' spread about their bone (1 = hanging as modelled; 0 = along the arm)
##   sweep - the whole wing swung back (+) or forward (-) about her vertical
## Poses: OPEN (the model; also the glide), SHEET (her design sheet: arm raised, forearm and hand hanging, fan
## closed - the wing at rest on the ground), FOLD (tucked behind her back), HALF (casting, weapon out, transforming)
## and the wingbeat, a loop TOP_OPEN -> BOTTOM (a quick, powerful downstroke sweeping slightly forward, fan wide
## open) -> MID_UP -> TOP (a slower upstroke, bent at the wrist, the outer wing partly folded, the fan closing).
## `beat` scales the beat about OPEN (1 = deep beats, ~0.5 = the small quick hover beats, 0 = glide held open).
## Which pose: flying -> the beat; casting / weapon / transforming -> HALF; walking, running, seated, lying or just
## landed -> FOLD; standing -> SHEET. Wings without the built rig get the old gentle flap and simple fold.
## Skeleton space: the VRM faces +Z, her left is +X, up is +Y.

const SHEET := {"arm": 50.0, "fore": -94.0, "hand": -98.0, "fan": 0.12, "sec": 0.08, "sweep": 0.0}
const FOLD := {"arm": 34.0, "fore": -96.0, "hand": -100.0, "fan": 0.0, "sec": 0.0, "sweep": 74.0}
const HALF := {"arm": 40.0, "fore": -20.0, "hand": -35.0, "fan": 0.6, "sec": 0.7, "sweep": 0.0}
const TOP_OPEN := {"arm": 58.0, "fore": 34.0, "hand": 24.0, "fan": 0.9, "sec": 1.0, "sweep": 0.0}
const BOTTOM := {"arm": -32.0, "fore": -36.0, "hand": -42.0, "fan": 1.18, "sec": 1.0, "sweep": -12.0}
const MID_UP := {"arm": 12.0, "fore": -12.0, "hand": -78.0, "fan": 0.42, "sec": 0.8, "sweep": 6.0}
const TOP := {"arm": 62.0, "fore": 30.0, "hand": -22.0, "fan": 0.5, "sec": 0.85, "sweep": 4.0}
const GLIDE_DIHEDRAL := 6.0      # gliding: the open wing raised a few degrees
const DOWN_SHARE := 0.4          # the downstroke takes 40 % of a beat

var bones := {"L": [], "R": []}  # legacy: [root, arch, tip]
var rig := {}                    # side -> rest angles and bone indices (see _build_rig)
var flap_deg := 5.0
var flap_hz := 0.22
var sit_mode := "fold"
var seated := false              # set by the character each frame (seated, lying, knocked down)
var spread := false              # set by the character each frame (casting, sword, transformation)
var flying := false              # set by the character each frame (WingFlight airborne)
var moving := false              # set by the character each frame (walking / running on the ground)
var beat := 1.0                  # set by WingFlight: 1 = deep beats, ~0.5 hover, 0 = glide
var beat_hz := 1.6
var override := ""               # tests: "sheet" / "open" / "fold" / "half" / "flap" / "hover" / "glide" force a pose
var stroke := 0.0                # out: -1 top of the upstroke .. +1 bottom of the downstroke (WingFlight lifts on it)
var downstroke := 0.0            # out: 0..1 while the wing is moving down
var meshes: Array = []
var _fold := 0.0
var _half := 0.0
var _air := 0.0
var _beat := 0.0
var _fph := 0.0
var _land_hold := 0.0
var _was_flying := false
var _t := 0.0
var _chest := -1
var _spread := 0.0               # legacy


static func attach(sk: Skeleton3D, avatar: Node, cfg: Dictionary) -> WingLayer:
	var w := WingLayer.new()
	w.name = "WingLayer"
	var b: Dictionary = cfg.get("bones", {})
	for side in ["L", "R"]:
		for n in b.get(side, ["J_Sec_Wing%s_0" % side, "J_Sec_Wing%s_1" % side, "J_Sec_Wing%s_2" % side]):
			var i := sk.find_bone(String(n))
			if i >= 0:
				w.bones[side].append(i)
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		if "Wing" in String(mi.name):
			w.meshes.append(mi)
	for side in ["L", "R"]:
		w._build_rig(sk, side)
	w.flap_deg = float(cfg.get("flap_deg", 5.0))
	w.flap_hz = float(cfg.get("flap_hz", 0.22))
	w.sit_mode = String(cfg.get("sit", "fold"))
	if w.bones.L.is_empty() and w.bones.R.is_empty():
		push_warning("[wings] no wing bones found")
	sk.add_child(w)
	return w


## The rig's rest (open) geometry: each segment's and each feather's angle in the plane of her back, the feather
## directions read from the mesh itself (the mean of the vertices riding each feather bone).
func _build_rig(sk: Skeleton3D, side: String) -> void:
	var f := func(n: String) -> int: return sk.find_bone("J_Sec_Wing%s_%s" % [side, n])
	var sh: int = f.call("0")
	var el: int = f.call("1")
	var wr: int = f.call("Wrist")
	var tp: int = f.call("HandTip")
	if sh < 0 or el < 0 or wr < 0 or tp < 0 or sk.find_bone("J_Sec_Wing%s_P0" % side) < 0:
		return
	var sx := signf(sk.get_bone_global_rest(sh).origin.x)
	var pos := func(b: int) -> Vector3: return sk.get_bone_global_rest(b).origin
	var r := {"shoulder": sh, "elbow": el, "wrist": wr, "sx": sx, "prim": [], "sec": [], "tert": []}
	r["arm0"] = _ang(pos.call(el) - pos.call(sh), sx)
	r["fore0"] = _ang(pos.call(wr) - pos.call(el), sx)
	r["hand0"] = _ang(pos.call(tp) - pos.call(wr), sx)
	var mean := _feather_means(sk, side)
	for group in [["P", 10, "prim"], ["S", 12, "sec"], ["T", 3, "tert"]]:
		for k in int(group[1]):
			var b: int = f.call("%s%d" % [group[0], k])
			if b < 0 or not mean.has(b):
				continue
			(r[group[2]] as Array).append([b, _ang((mean[b] as Vector3) - pos.call(b), sx)])
	_chest = sk.get_bone_parent(sh)
	rig[side] = r


## In-plane angle of v (degrees): 0 = out to her side, + = up.
static func _ang(v: Vector3, sx: float) -> float:
	return rad_to_deg(atan2(v.y, v.x * sx))


## Skeleton-space rest position of the mean of the vertices fully weighted to each wing bone.
func _feather_means(sk: Skeleton3D, side: String) -> Dictionary:
	var sums := {}
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.mesh == null or m.skin == null or not String(m.name).ends_with(side):
			continue
		var arr := m.mesh.surface_get_arrays(0)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var B: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var W: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var nw := B.size() / maxi(V.size(), 1)
		var bind := {}
		for i in m.skin.get_bind_count():
			var bb := m.skin.get_bind_bone(i)
			bind[i] = bb if bb >= 0 else sk.find_bone(m.skin.get_bind_name(i))
		for k in V.size():
			if W[k * nw] > 0.99:
				var b: int = bind.get(B[k * nw], -1)
				var e: Array = sums.get_or_add(b, [Vector3.ZERO, 0])
				e[0] = (e[0] as Vector3) + V[k]
				e[1] = int(e[1]) + 1
	var out := {}
	for b in sums:
		out[b] = (sums[b][0] as Vector3) / float(sums[b][1])
	return out


## A pose's full angle set for this wing (missing keys = the open model).
func _pose(r: Dictionary, p: Dictionary) -> Dictionary:
	return {"arm": float(p.get("arm", r.arm0)), "fore": float(p.get("fore", r.fore0)), "hand": float(p.get("hand", r.hand0)),
		"fan": float(p.get("fan", 1.0)), "sec": float(p.get("sec", 1.0)), "sweep": float(p.get("sweep", 0.0))}


static func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var o := {}
	for k in a:
		o[k] = lerpf(float(a[k]), float(b[k]), t)
	return o


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	_t += dt
	var fl := flying
	var hf := spread
	var sd := seated or moving
	var bt := beat
	var hz := beat_hz
	match override:
		"sheet":
			fl = false; hf = false; sd = false
		"open", "glide":
			fl = true; bt = 0.0
		"fold":
			fl = false; sd = true
		"half":
			fl = false; hf = true; sd = false
		"flap":
			fl = true; bt = 1.0; hz = 1.25
		"hover":
			fl = true; bt = 0.5; hz = 2.3
	if override != "":
		_land_hold = 0.0
		_was_flying = false
	elif fl:
		_was_flying = true
	elif _was_flying:
		_was_flying = false
		_land_hold = 2.5                       # touched down: tuck them neatly behind her back
	_land_hold = maxf(_land_hold - dt, 0.0)
	var want_fold := (sd or _land_hold > 0.0) and not fl
	_fold = lerpf(_fold, 1.0 if want_fold else 0.0, 1.0 - exp(-3.5 * dt))
	_half = lerpf(_half, 1.0 if hf and not want_fold and not fl else 0.0, 1.0 - exp(-3.5 * dt))
	_air = lerpf(_air, 1.0 if fl else 0.0, 1.0 - exp(-3.0 * dt))
	_beat = lerpf(_beat, bt if fl else 0.0, 1.0 - exp(-4.0 * dt))
	_fph += dt * TAU * (hz if fl else flap_hz)
	var hide := seated and sit_mode == "hide" and not fl
	for m in meshes:
		(m as MeshInstance3D).visible = not hide
	if rig.is_empty():
		_legacy(sk, dt)
		return
	var u := fposmod(_fph / TAU, 1.0)
	var down := u < DOWN_SHARE
	downstroke = (1.0 if down else 0.0) * _beat * _air
	stroke = (smoothstep(0.0, 1.0, u / DOWN_SHARE) * 2.0 - 1.0 if down else 1.0 - 2.0 * smoothstep(0.0, 1.0, (u - DOWN_SHARE) / (1.0 - DOWN_SHARE))) * _beat * _air
	var C0 := Basis.IDENTITY
	if _chest >= 0:
		C0 = (sk.get_bone_global_pose(_chest).basis * sk.get_bone_global_rest(_chest).basis.inverse()).orthonormalized()
	for side in rig:
		var r: Dictionary = rig[side]
		# on the ground: the sheet, half open, or folded
		var q := _mix(_pose(r, SHEET), _pose(r, HALF), _half)
		q = _mix(q, _pose(r, FOLD), _fold)
		q.arm += sin(_t * TAU * flap_hz) * flap_deg * (1.0 - _fold) * (1.0 - _air)        # breathing
		# in the air: the open wing, and the beat around it
		if _air > 0.001:
			var glide := _pose(r, {"arm": float(r.arm0) + GLIDE_DIHEDRAL})
			var cyc: Dictionary
			if down:
				cyc = _mix(_pose(r, TOP_OPEN), _pose(r, BOTTOM), smoothstep(0.0, 1.0, u / DOWN_SHARE))
			else:
				var v := (u - DOWN_SHARE) / (1.0 - DOWN_SHARE)
				if v < 0.45:
					cyc = _mix(_pose(r, BOTTOM), _pose(r, MID_UP), smoothstep(0.0, 1.0, v / 0.45))
				elif v < 0.85:
					cyc = _mix(_pose(r, MID_UP), _pose(r, TOP), smoothstep(0.0, 1.0, (v - 0.45) / 0.4))
				else:
					cyc = _mix(_pose(r, TOP), _pose(r, TOP_OPEN), smoothstep(0.0, 1.0, (v - 0.85) / 0.15))
			q = _mix(q, _mix(glide, cyc, clampf(_beat, 0.0, 1.0)), _air)
		_apply(sk, r, q, C0)


## Each bone turns in the plane of her back by (its target angle - its rest angle - what its parent already turned),
## expressed in the frame the chain above it has already turned (the sweep and the torso's own lean).
func _apply(sk: Skeleton3D, r: Dictionary, q: Dictionary, C0: Basis) -> void:
	var sx: float = r.sx
	var axis := Vector3.BACK                        # +Z: + turns her left wing up, her right wing down
	var d_arm := deg_to_rad(float(q.arm) - float(r.arm0)) * sx
	var d_fore := deg_to_rad(float(q.fore) - float(r.fore0)) * sx
	var d_hand := deg_to_rad(float(q.hand) - float(r.hand0)) * sx
	var sw := Basis(Vector3.UP, deg_to_rad(float(q.sweep)) * sx)
	_rotate(sk, r.shoulder, C0 * sw * Basis(axis, d_arm) * C0.inverse())
	var acc := C0 * sw                              # the plane, swept with the wing
	_rotate(sk, r.elbow, acc * Basis(axis, d_fore - d_arm) * acc.inverse())
	_rotate(sk, r.wrist, acc * Basis(axis, d_hand - d_fore) * acc.inverse())
	var hand0 := float(r.hand0)
	for e in r.prim:
		var want := float(q.hand) + (float(e[1]) - hand0) * float(q.fan)
		_rotate(sk, e[0], acc * Basis(axis, deg_to_rad(want - float(e[1])) * sx - d_hand) * acc.inverse())
	var fore0 := float(r.fore0)
	for e in r.sec:
		var want2 := float(q.fore) + (float(e[1]) - fore0) * float(q.sec)
		_rotate(sk, e[0], acc * Basis(axis, deg_to_rad(want2 - float(e[1])) * sx - d_fore) * acc.inverse())
	var arm0 := float(r.arm0)
	for e in r.tert:
		var want3 := float(q.arm) + (float(e[1]) - arm0) * float(q.sec)
		_rotate(sk, e[0], acc * Basis(axis, deg_to_rad(want3 - float(e[1])) * sx - d_arm) * acc.inverse())


## Wings without the built rig: the old gentle flap and simple fold on root / arch / tip.
func _legacy(sk: Skeleton3D, dt: float) -> void:
	_spread = lerpf(_spread, 1.0 if spread and not seated else 0.0, 1.0 - exp(-4.0 * dt))
	var ph := _t * TAU * flap_hz
	for side in ["L", "R"]:
		var bl: Array = bones[side]
		if bl.size() < 2:
			continue
		var s := 1.0 if side == "L" else -1.0
		var flap := sin(ph) * flap_deg * (1.0 - _fold) * (1.0 - 0.5 * _spread)
		var lift := flap + _spread * 12.0 - _fold * 18.0
		var swing := -_spread * 8.0 + _fold * 62.0
		_rotate(sk, bl[0], Basis(Vector3.UP, deg_to_rad(s * swing)) * Basis(Vector3.BACK, deg_to_rad(-s * lift)))
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
