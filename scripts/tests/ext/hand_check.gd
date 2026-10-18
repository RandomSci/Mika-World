## Hands never inside a face or a body (Selwyn, 2026-10-19): every hand pose that comes near the face or body, held
## still and filmed from the front, both sides and close on each girl's hands - idle, the dance's hand-near-face
## moments (only his six clips), and the boat (Mika's chin on her hand, Luna at the oars). Prints the deepest a hand
## went into a body before the HandGuard pushed it out, per scenario. GPU run: frames are marked
## "[handcheck] <scenario> <view> at frame N".

const POSES := [
	["idle", "", 0.0],
	["dance_frame_face", "dancing_a", 3.0],
	["dance_frame_face2", "dancing_a", 5.0],
	["dance_arms_up", "belly_dance", 3.5],
	["dance_arms_up2", "belly_dance", 14.5],
	["dance_arm_raised", "bellydancing", 1.0],
	["dance_hands_chest", "samba", 8.0],
]
const VIEWS := ["front", "left", "right", "luna_hands", "mika_hands"]
const HOLD := 0.5


static func run(t) -> void:
	var set: Dictionary = await t._lake_setup({"luna": -0.8, "mika": 0.8})
	if set.is_empty():
		return
	var pin: CameraPin = set.pin
	var spot: Vector3 = set.spot
	var chars: Dictionary = set.chars
	var decks := {}
	for id in chars:
		decks[id] = t._dance_stack(chars[id])
	# the residual: after EVERY modifier (the springs included), how deep is any hand or fingertip still inside a body
	var residual := {"worst": 0.0, "where": "", "samples": 0}
	var cur := {"pose": ""}
	for id in chars:
		var c: WorldCharacter = chars[id]
		var guard: HandGuard = null
		for n in c.skeleton.get_children():
			if n is HandGuard:
				guard = n
		var last: SkeletonModifier3D = null
		for n in c.skeleton.get_children(true):
			if n is SkeletonModifier3D:
				last = n
		if guard and last:
			last.modification_processed.connect(func():
				var sk := c.skeleton
				residual.samples = int(residual.samples) + 1
				for side in ["Left", "Right"]:
					var shapes: Array = guard._shapes(sk, side) + guard._others_shapes(sk)
					for b in [side + "Hand", side + "MiddleDistal", side + "IndexDistal", side + "ThumbDistal"]:
						var bi := sk.find_bone(b)
						if bi < 0:
							continue
						var d: float = (guard._push(sk.get_bone_global_pose(bi).origin, shapes)).length() - HandGuard.MARGIN
						if d > float(residual.worst):
							residual.worst = d
							residual.where = "%s %s %s" % [cur.pose, id, b])
	print("[handcheck] start frame %d" % Engine.get_frames_drawn())
	for p in POSES:
		cur.pose = String(p[0])
		for id in decks:
			var d: DanceDeck = decks[id]
			if String(p[1]) == "":
				d.influence = 0.0
			else:
				d.influence = 1.0
				d.play(String(p[1]), float(p[2]), 0.0, 0.01)
		await t._wait(0.6)
		for v in VIEWS:
			_aim(pin, String(v), spot, chars)
			await t._wait(HOLD * 0.5)
			var depth := {}
			for id in chars:
				for n in (chars[id] as WorldCharacter).skeleton.get_children():
					if n is HandGuard:
						depth[id] = snappedf((n as HandGuard).last_depth, 0.001)
			print("[handcheck] %s %s at frame %d  guard push depth %s" % [p[0], v, Engine.get_frames_drawn(), str(depth)])
			await t._wait(HOLD * 0.5)
	pin.active = false
	print("[handcheck] worst residual hand depth %.3f m (%s) over %d final-pose samples" % [float(residual.worst), String(residual.where), int(residual.samples)])
	t._check(int(residual.samples) > 100, "the residual was really measured (%d samples)" % int(residual.samples))
	t._check(float(residual.worst) <= 0.005, "no hand inside a face or body after the full pose stack (worst %.1f mm, %s)" % [float(residual.worst) * 1000.0, String(residual.where)])


static func _hand_mid(c: WorldCharacter) -> Vector3:
	var sk := c.skeleton
	var a := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin
	var b := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
	var h := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
	return (a + b + h) / 3.0


static func _aim(pin: CameraPin, v: String, spot: Vector3, chars: Dictionary) -> void:
	var mid := spot + Vector3(0, 1.25, 0)
	match v:
		"front":
			pin.fov = 40.0
			pin.pos = mid + Vector3(0, 0.0, 3.4)
			pin.look = mid
		"left":
			pin.fov = 40.0
			pin.pos = mid + Vector3(-3.2, 0.1, 0.6)
			pin.look = mid
		"right":
			pin.fov = 40.0
			pin.pos = mid + Vector3(3.2, 0.1, 0.6)
			pin.look = mid
		"luna_hands", "mika_hands":
			var c: WorldCharacter = chars["luna" if v == "luna_hands" else "mika"]
			var hm := _hand_mid(c)
			pin.fov = 34.0
			pin.pos = hm + Vector3(0.35, 0.05, 0.85)
			pin.look = hm
