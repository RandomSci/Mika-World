extends RefCounted
## Combat v3 move book check: every Move Library clip (MoveCatalog, 164) baked for BOTH girls' skeletons (MocapBake)
## and posed on a bare copy at every frame (30 fps), the human joint rules on each pose (JointAudit: no knee / elbow
## folding against its hinge, no thigh / upper arm past a human twist, no knee pointing behind her). Per clip it also
## reads the source landmarks: how steady the actor's leg length stays (a crop or a camera move makes the legs
## guesswork) and how far the hands ever get in front of her hips (forward strikes lose depth from a front camera).
## Legs are judged on "body" clips only; "upper" clips play their arms on the fight rig's legs; "ref" clips are
## timing references for the IK strikes (audited, reported, not played as poses).
## Options: --clip=<name> (one clip), --dump=<abs path> (JSON report).

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var only := String(RenderProfile.options.get("clip", ""))
	var report := {}
	var played_faults := 0
	var ref_faults := 0
	var baked := 0
	var missing := []
	for id in ["mika", "luna"]:
		var c: WorldCharacter = main.characters[id]
		var bare := JointAudit.bare_copy(c.skeleton)
		main.add_child(bare)
		for n in MoveCatalog.CLIPS:
			if only != "" and n != only:
				continue
			var path: String = WorldCharacter.MOCAP_DIR + String(n) + ".json"
			if not FileAccess.file_exists(path):
				if id == "mika":
					missing.append(n)
				continue
			var anim: Animation = MocapBake.bake(c.skeleton, path)
			if anim == null:
				missing.append(n)
				continue
			baked += 1
			var use := String(MoveCatalog.CLIPS[n].use)
			var frames := int(anim.length * 30.0) + 1
			var bad := {}
			var bad_frames := 0
			var worst := {}
			for fi in frames:
				JointAudit.pose_at(bare, anim, float(fi) / 30.0)
				var fl := JointAudit.check(bare)
				var counted := false
				for f in fl:
					var leg: bool = String(f.limb) in ["lf", "rf"]
					if leg and use != "body" and use != "ref":
						continue                      # (an "upper" clip's legs are the rig's)
					var key: String = "%s %s" % [f.limb, String(f.why).get_slice(" (", 0).get_slice(" turned", 0)]
					bad[key] = int(bad.get(key, 0)) + 1
					if not worst.has(key):
						worst[key] = {"t": snappedf(float(fi) / 30.0, 0.01), "bend": f.bend, "twist": f.twist}
					if not counted:
						bad_frames += 1
						counted = true
			if use == "ref":
				ref_faults += bad_frames
			else:
				played_faults += bad_frames
			var r: Dictionary = report.get(n, {"lib": MoveCatalog.CLIPS[n].lib, "use": use, "frames": frames})
			r[id] = {"bad_frames": bad_frames, "faults": bad, "first": worst}
			report[n] = r
		bare.queue_free()
	# the source landmarks: leg-length steadiness and forward depth of the hands
	for n in report:
		var data = JSON.parse_string(FileAccess.get_file_as_string(WorldCharacter.MOCAP_DIR + String(n) + ".json"))
		var fr: Array = data.frames
		var legs := []
		var depth := 0.0
		for P in fr:
			var v := func(i: int) -> Vector3: return Vector3(float(P[i][0]), float(P[i][1]), float(P[i][2]))
			legs.append((v.call(23) as Vector3).distance_to(v.call(25)) + (v.call(25) as Vector3).distance_to(v.call(27)))
			var hip := ((v.call(23) as Vector3) + (v.call(24) as Vector3)) * 0.5
			depth = maxf(depth, maxf((v.call(15) as Vector3).z, (v.call(16) as Vector3).z) - hip.z)
		var mean := 0.0
		for l in legs:
			mean += float(l)
		mean /= maxf(legs.size(), 1)
		var var_ := 0.0
		for l in legs:
			var_ += pow(float(l) - mean, 2.0)
		var cv := sqrt(var_ / maxf(legs.size(), 1)) / maxf(mean, 0.01)
		report[n]["leg_cv"] = snappedf(cv, 0.001)
		report[n]["hand_depth"] = snappedf(depth, 0.01)
		report[n]["detected"] = "%d/%d" % [int(data.get("detected", 0)), int(data.get("total", 0))]
	var names := report.keys()
	names.sort()
	for n in names:
		var r: Dictionary = report[n]
		if not (r.has("mika") and r.has("luna")):
			continue                                  # (its mocap landed between the two girls' passes)
		print("[movelib] %-26s %-3s %-5s %3d f  mika %3d bad %s  luna %3d bad %s  leg_cv %.3f  hand_depth %.2f m  seen %s" % [n, r.lib, r.use, r.frames,
			int(r.mika.bad_frames), JSON.stringify(r.mika.faults), int(r.luna.bad_frames), JSON.stringify(r.luna.faults), float(r.leg_cv), float(r.hand_depth), r.detected])
	var dump := String(RenderProfile.options.get("dump", ""))
	if dump != "":
		var fh := FileAccess.open(dump, FileAccess.WRITE)
		if fh:
			fh.store_string(JSON.stringify(report, " "))
	t._check(missing.is_empty(), "every catalogued clip has its mocap (%d missing: %s)" % [missing.size(), ", ".join(missing.slice(0, 8))])
	t._check(baked >= 2 * (report.size()), "%d clip bakes (both girls)" % baked)
	t._check(played_faults == 0, "played clips: no knee / elbow folding backwards, no impossible twist, no knee behind her (%d bad frames)" % played_faults)
	print("[movelib] reference-only clips (IK strikes re-create them): %d bad frames, not played as poses" % ref_faults)
