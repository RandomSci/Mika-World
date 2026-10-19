## Part A: the Move Library activity clips (mocapped, MocapBake) on both girls at the lake, a fixed medium-wide lens
## from the front-left. Marks a still at 25 / 50 / 75 % of each clip ("[movelib] <clip> <pct> at frame N").

const CLIPS := ["ml_release_lantern", "ml_stargaze_point", "ml_sit_gaze", "ml_rowing"]


static func run(t) -> void:
	var set: Dictionary = await t._lake_setup({"luna": -0.8, "mika": 0.8})
	if set.is_empty():
		return
	var chars: Dictionary = set.chars
	var pin: CameraPin = set.pin
	var mid: Vector3 = (set.spot as Vector3) + Vector3(0, 0.9, 0)
	var fwd: Vector3 = (chars.luna as WorldCharacter).global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	pin.fov = 45.0
	pin.pos = mid - fwd * 4.2 - fwd.cross(Vector3.UP) * 1.4 + Vector3(0, 0.4, 0)      # (her node basis z points behind her)
	pin.look = mid
	pin.active = true
	for clip in CLIPS:
		var ok := true
		for id in chars:
			var c: WorldCharacter = chars[id]
			ok = ok and c.has_clip(clip)
			c.play_gesture(clip, 0.3, 1.0)
		t._check(ok, "%s baked for both girls" % clip)
		var len: float = (chars.mika as WorldCharacter).animation_length(clip) if ok else 2.0
		for pct in [25, 50, 75]:
			await t._wait(len * 0.25)
			print("[movelib] %s %d at frame %d" % [clip, pct, Engine.get_frames_drawn()])
			for id in chars:
				var c: WorldCharacter = chars[id]
				var cp := InvCommon.capture(c)
				await t.get_tree().process_frame
				var sk := c.skeleton
				var ps: Array = cp.poses
				if ps.is_empty():
					continue
				var hd: Vector3 = sk.global_transform * (ps[sk.find_bone("Head")] as Transform3D).origin
				var lh: Vector3 = sk.global_transform * (ps[sk.find_bone("LeftHand")] as Transform3D).origin
				var le: Vector3 = sk.global_transform * (ps[sk.find_bone("LeftLowerArm")] as Transform3D).origin
				var ls: Vector3 = sk.global_transform * (ps[sk.find_bone("LeftUpperArm")] as Transform3D).origin
				print("[movelib]   %s %s: left hand - head %.2f m, elbow - shoulder %s" % [id, clip, lh.y - hd.y, str((le - ls).snappedf(0.01))])
		await t._wait(len * 0.25 + 0.3)
		for id in chars:
			(chars[id] as WorldCharacter).end_gesture()
		await t._wait(0.8)
