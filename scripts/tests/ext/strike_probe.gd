extends RefCounted
## Frame data for the combat clips (Combat v3): forward kinematics over each baked clip on Mika's skeleton, sampling
## every 1/60 s, so the moment each hand / foot is furthest out in front of her (the hit) and where it is (height,
## side) come from the motion itself. Writes --probe-out=<abs json> (one entry per clip: per limb the reach curve's
## peaks with time, reach, height above the hips, sideways offset).

const CLIPS := ["ml_three_hit_combo", "ml_front_kick", "ml_crescent_kick", "ml_spin_back_kick", "ml_low_sweep",
	"ml_uppercut_launcher", "ml_dash_palm_strike", "ml_parry_counter", "ml_finisher_combo", "ml_block_high",
	"ml_hit_light", "ml_hit_heavy_stagger", "ml_dodge_left", "ml_dodge_right", "ml_backstep_evade", "ml_fight_idle",
	"ml_cast_one_hand", "ml_cast_two_hand_blast", "ml_charge_up", "ml_overhead_slam", "ml_jump_spin_kick"]
const LIMBS := {"l_hand": "LeftHand", "r_hand": "RightHand", "l_foot": "LeftFoot", "r_foot": "RightFoot"}


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var c: WorldCharacter = main.characters["mika"]
	var sk := c.skeleton
	var out := {}
	for clip in CLIPS:
		if not c.has_clip(clip):
			print("[probe] no clip ", clip)
			continue
		var a: Animation = c.body_player.get_animation("mx/" + clip)
		var rot := {}
		var hips_pos := -1
		for tr in a.get_track_count():
			var bn := String(a.track_get_path(tr)).get_slice(":", 1)
			var bi := sk.find_bone(bn)
			if bi < 0:
				continue
			if a.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
				rot[bi] = tr
			elif a.track_get_type(tr) == Animation.TYPE_POSITION_3D and bn == "Hips":
				hips_pos = tr
		var curves := {}
		for l in LIMBS:
			curves[l] = []
		var hips_i := sk.find_bone("Hips")
		var n := int(a.length * 60.0)
		for k in n + 1:
			var tt := float(k) / 60.0
			var g := {}
			for bi in sk.get_bone_count():
				_fk(sk, a, rot, hips_pos, hips_i, bi, tt, g)
			var hips: Transform3D = g[hips_i]
			for l in LIMBS:
				var p: Vector3 = (g[sk.find_bone(LIMBS[l])] as Transform3D).origin - hips.origin
				# VRM faces +Z in skeleton space: reach = forward, side = +X is her left
				curves[l].append([snappedf(tt, 0.001), snappedf(p.z, 0.001), snappedf(p.y, 0.001), snappedf(p.x, 0.001)])
		var info := {"length": snappedf(a.length, 0.001), "limbs": {}}
		for l in LIMBS:
			var cv: Array = curves[l]
			var base := float(cv[0][1])
			var peaks := []
			for i in range(3, cv.size() - 3):
				var r := float(cv[i][1])
				var is_max := true
				for j in range(i - 3, i + 4):
					if float(cv[j][1]) > r:
						is_max = false
				if is_max and r - base > 0.18 and (peaks.is_empty() or float(cv[i][0]) - float(peaks[-1][0]) > 0.15):
					peaks.append(cv[i])
			info.limbs[l] = {"start": cv[0], "peaks": peaks, "curve": cv.filter(func(e): return int(round(float(e[0]) * 60.0)) % 3 == 0)}
		out[clip] = info
		var summary := []
		for l in LIMBS:
			for p in info.limbs[l].peaks:
				summary.append("%s@%.2fs r%.2f h%.2f x%.2f" % [l, p[0], p[1], p[2], p[3]])
		print("[probe] %s (%.2f s): %s" % [clip, a.length, ", ".join(summary)])
	var path := String(RenderProfile.options.get("probe-out", ""))
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out))
		f.close()
	t._check(out.size() >= 15, "%d clips probed" % out.size())


static func _fk(sk: Skeleton3D, a: Animation, rot: Dictionary, hips_pos: int, hips_i: int, bi: int, tt: float, g: Dictionary) -> Transform3D:
	if g.has(bi):
		return g[bi]
	var rest := sk.get_bone_rest(bi)
	var q: Quaternion = a.rotation_track_interpolate(int(rot[bi]), tt) if rot.has(bi) else rest.basis.get_rotation_quaternion()
	var o := rest.origin
	if bi == hips_i and hips_pos >= 0:
		o = a.position_track_interpolate(hips_pos, tt)
	var local := Transform3D(Basis(q).scaled(rest.basis.get_scale()), o)
	var par := sk.get_bone_parent(bi)
	var gt := local if par < 0 else _fk(sk, a, rot, hips_pos, hips_i, par, tt, g) * local
	g[bi] = gt
	return gt
