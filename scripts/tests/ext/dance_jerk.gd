## The dance glitch hunt (Selwyn 2026-10-19: "during the dance they are not moving like a human, it's like they are
## glitching"). Both girls dance his clips; every frame, for the main bones, the local rotation of the CLIP's pose
## (before any modifier) and of the FINAL pose (after the whole pipeline). A glitch = a bone that snaps and comes back:
## the path t-1 -> t -> t+1 much longer than t-1 -> t+1 (jitter), or a single-frame jump far beyond the clip's own.
## Prints the worst events with the bone, the frame and whether the clip itself does it.

const BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm",
	"LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"]
const JITTER_DEG := 8.0


class Rec extends Node:
	var chars: Dictionary
	var caps: Dictionary
	var raw := {}            # id -> Array of {bone: Quaternion} (clip pose, local)
	var fin := {}            # id -> Array of {bone: Quaternion} (final pose, local)
	var frames: Array = []
	var decks := {}
	var deck_out := {}       # id -> the DanceDeck's own output this frame {bone: Quaternion} (local)
	var where := []          # per frame: "clip@t" of mika's deck

	func grab(id: String) -> void:
		var c: WorldCharacter = chars[id]
		var sk := c.skeleton
		var r := {}
		for n in BONES:
			var bi := sk.find_bone(n)
			if bi >= 0:
				r[n] = sk.get_bone_pose_rotation(bi)
		deck_out[id] = r

	func _process(_d: float) -> void:
		frames.append(Engine.get_process_frames())
		var dm: DanceDeck = decks.get("mika")
		where.append("%s@%.2f" % [dm.current(), float(dm._cur.get("t", 0.0))] if dm else "")
		for id in chars:
			var c: WorldCharacter = chars[id]
			var sk := c.skeleton
			var ps: Array = caps[id].poses
			var r: Dictionary = deck_out.get(id, {})          # the DanceDeck's own output (local rotations)
			var f := {}
			for n in BONES:
				var bi := sk.find_bone(n)
				if bi < 0:
					continue
				var par := sk.get_bone_parent(bi)
				if ps.size() > bi:
					var fg: Basis = (ps[bi] as Transform3D).basis
					var fpg: Basis = (ps[par] as Transform3D).basis if par >= 0 else Basis.IDENTITY
					f[n] = (fpg.orthonormalized().inverse() * fg.orthonormalized()).get_rotation_quaternion()
			(raw.get_or_add(id, []) as Array).append(r)
			(fin.get_or_add(id, []) as Array).append(f)


static func run(t) -> void:
	var set: Dictionary = await t._lake_setup({"luna": -0.8, "mika": 0.8})
	if set.is_empty():
		return
	var chars: Dictionary = set.chars
	var rec := Rec.new()
	rec.chars = chars
	for id in chars:
		rec.caps[id] = InvCommon.capture(chars[id])
	var decks := {}
	for id in chars:
		decks[id] = t._dance_stack(chars[id])
		(decks[id] as DanceDeck).influence = 1.0
		(decks[id] as DanceDeck).modification_processed.connect(rec.grab.bind(id))
	rec.decks = decks
	t.add_child(rec)
	var clips: Array = DanceDeck.FILES.keys()
	for clip in clips:
		for id in chars:
			(decks[id] as DanceDeck).play(clip, 1.0, 1.0, 0.4)
		await t._wait(float(RenderProfile.options.get("dj-secs", "7")))
	rec.set_process(false)
	for id in chars:
		var ev := []
		var R: Array = rec.raw[id]
		var F: Array = rec.fin[id]
		var by_bone := {}
		for i in range(1, R.size() - 1):
			for n in BONES:
				if not (F[i].has(n) and F[i - 1].has(n) and F[i + 1].has(n)):
					continue
				var jf := _jit(F[i - 1][n], F[i][n], F[i + 1][n])
				var jr := _jit(R[i - 1][n], R[i][n], R[i + 1][n]) if (R[i].has(n) and R[i - 1].has(n) and R[i + 1].has(n)) else -1.0
				if jf > JITTER_DEG:
					by_bone[n] = int(by_bone.get(n, 0)) + 1
					ev.append([jf, n, rec.frames[i], jr, rec.where[i]])
		ev.sort_custom(func(a, b): return a[0] > b[0])
		print("[jerk] %s: %d jitter events (final pose) over %d frames; by bone %s" % [id, ev.size(), R.size(), JSON.stringify(by_bone)])
		for e in ev.slice(0, 12):
			print("[jerk]   %s %s %.1f deg at frame %d %s (deck output itself %.1f)" % [id, e[1], e[0], e[2], e[4], e[3]])
		var raw_n := 0
		for i in range(1, R.size() - 1):
			for n in BONES:
				if R[i].has(n) and R[i - 1].has(n) and R[i + 1].has(n) and _jit(R[i - 1][n], R[i][n], R[i + 1][n]) > JITTER_DEG:
					raw_n += 1
		print("[jerk] %s: the clips alone have %d such events" % [id, raw_n])
		t._check(ev.size() <= raw_n + 5, "%s dances without glitches the clips don't have (%d final vs %d clip)" % [id, ev.size(), raw_n])


## Degrees a rotation goes out and comes back over three frames (0 for a smooth path).
static func _jit(a: Quaternion, b: Quaternion, c: Quaternion) -> float:
	return rad_to_deg(a.angle_to(b) + b.angle_to(c) - a.angle_to(c))
