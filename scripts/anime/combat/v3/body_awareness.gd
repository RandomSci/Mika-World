class_name BodyAwareness
extends RefCounted
## Combat v3 body awareness: capsules on the real bones (the FINAL pose each frame, from TraceFight), so a blow only
## lands where a limb really touches a body.
##   hurtboxes - every main bone of a fighter, always on: head, chest, stomach, hips, upper arms, forearms, thighs, shins
##   hitboxes  - the striking limb only, only in its active frames: forearm + fist, shin + foot (knee / elbow strikes
##               use the upper bone)
## A contact is the first hurtbox the hitbox overlaps (closest overlap wins): its zone (head / chest / stomach / left /
## right / legs) drives the hit reaction, a forearm hurtbox on a guard is a block. Pure geometry, no physics server.

## name -> [bone from, bone to (or "" + offset up), radius m at k = 1, zone]
const HURT := {
	"head": ["Neck", "Head+", 0.10, "head"],
	"chest": ["UpperChest", "Neck", 0.13, "chest"],
	"stomach": ["Spine", "UpperChest", 0.13, "stomach"],
	"hips": ["Hips", "Spine", 0.14, "stomach"],
	"upperarm_l": ["LeftUpperArm", "LeftLowerArm", 0.05, "left"],
	"forearm_l": ["LeftLowerArm", "LeftHand", 0.045, "left"],
	"upperarm_r": ["RightUpperArm", "RightLowerArm", 0.05, "right"],
	"forearm_r": ["RightLowerArm", "RightHand", 0.045, "right"],
	"thigh_l": ["LeftUpperLeg", "LeftLowerLeg", 0.08, "legs"],
	"shin_l": ["LeftLowerLeg", "LeftFoot", 0.06, "legs"],
	"thigh_r": ["RightUpperLeg", "RightLowerLeg", 0.08, "legs"],
	"shin_r": ["RightLowerLeg", "RightFoot", 0.06, "legs"],
}

## striking limb -> the hitbox segments [from, to, radius]: "fist_*" / "ball_*" are TraceFight's surface points
const HIT := {
	"lh": [["LeftLowerArm", "fist_Left", 0.05]],
	"rh": [["RightLowerArm", "fist_Right", 0.05]],
	"lf": [["LeftLowerLeg", "ball_Left", 0.06]],
	"rf": [["RightLowerLeg", "ball_Right", 0.06]],
	"le": [["LeftUpperArm", "LeftLowerArm", 0.055]],      # elbow strike
	"re": [["RightUpperArm", "RightLowerArm", 0.055]],
	"lk": [["LeftUpperLeg", "LeftLowerLeg", 0.07]],       # knee strike
	"rk": [["RightUpperLeg", "RightLowerLeg", 0.07]],
}


## A fighter's hurt capsules now: name -> [a, b, r] (world).
static func hurtboxes(f: MeleeFighter) -> Dictionary:
	var out := {}
	var tr: Dictionary = f.trace
	if not tr.has("Head"):
		return out
	for n in HURT:
		var h: Array = HURT[n]
		var a: Vector3 = tr.get(h[0], Vector3.ZERO)
		var b: Vector3
		if String(h[1]).ends_with("+"):
			var base: Vector3 = tr.get(String(h[1]).trim_suffix("+"), a)
			b = base + (base - a).normalized() * 0.14 * f.k          # (the head capsule runs up past the head bone)
		else:
			b = tr.get(h[1], a)
		out[n] = [a, b, float(h[2]) * f.k]
	return out


## The striking limb's capsules now (world).
static func hitboxes(f: MeleeFighter, limb: String) -> Array:
	var out := []
	var tr: Dictionary = f.trace
	for h in HIT.get(limb, []):
		if tr.has(h[0]) and tr.has(h[1]):
			out.append([tr[h[0]], tr[h[1]], float(h[2]) * f.k])
	return out


## Does `att`'s `limb` touch `vic`? -> {} or {part, zone, point, depth}. The deepest overlap wins; a guard's forearm in
## front of the body is found first because it is nearer to the strike.
static func contact(att: MeleeFighter, limb: String, vic: MeleeFighter) -> Dictionary:
	var best := {}
	var hb := hitboxes(att, limb)
	var hurt := hurtboxes(vic)
	for h in hb:
		for n in hurt:
			var c: Array = hurt[n]
			var cp := closest(h[0], h[1], c[0], c[1])
			var dist := (cp[0] as Vector3).distance_to(cp[1])
			var depth: float = float(h[2]) + float(c[2]) - dist
			if depth > 0.0 and (best.is_empty() or depth > float(best.depth)):
				best = {"part": n, "zone": HURT[n][3], "point": ((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5, "depth": depth}
	if not best.is_empty() and String(best.zone) in ["chest", "stomach"]:
		# a torso blow off to one side is a side hit (the ribs): which side of HER body
		var bs: Basis = vic.trace.get("basis", vic.sk.global_transform.basis)
		var left := (bs * Vector3(1, 0, 0)).normalized()
		var mid: Vector3 = vic.trace.get("Chest", best.point)
		var side := ((best.point as Vector3) - mid).dot(left)
		if absf(side) > 0.07 * vic.k:
			best.zone = "left" if side > 0.0 else "right"
	return best


## Closest points between segments p1-q1 and p2-q2 -> [point on 1, point on 2] (Ericson, Real-Time Collision Detection).
static func closest(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-8 and e <= 1e-8:
		return [p1, p2]
	if a <= 1e-8:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-8:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-8 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]


## Where the strike will land if nothing changes, as the defender reads it during the windup: the striking end's
## position + velocity (from the last frames) carried to the hit time, pulled onto her body. -> {point, height, side}
## height: high (head / neck), mid (chest / stomach), low (hips down); side: L / C / R from HER point of view.
static func predict(att: MeleeFighter, limb: String, vic: MeleeFighter, t_left: float, vel: Vector3) -> Dictionary:
	var end_b := ("Left" if limb in ["lh", "lf"] else "Right") + ("Hand" if limb in ["lh", "rh"] else "Foot")
	var p: Vector3 = att.trace.get(end_b, Vector3.ZERO)
	var guess := p + vel * clampf(t_left, 0.0, 0.4)
	var tr: Dictionary = vic.trace
	var head: Vector3 = tr.get("Head", guess)
	var chest: Vector3 = tr.get("Chest", guess)
	var hips: Vector3 = tr.get("Hips", guess)
	var height := "mid"
	if guess.y > (head.y + chest.y) * 0.5:
		height = "high"
	elif guess.y < hips.y - 0.05 * vic.k:
		height = "low"
	var bs: Basis = tr.get("basis", vic.sk.global_transform.basis)
	var left := (bs * Vector3(1, 0, 0)).normalized()
	var off := (guess - chest).dot(left)
	var side := "C"
	if off > 0.12 * vic.k:
		side = "L"
	elif off < -0.12 * vic.k:
		side = "R"
	return {"point": guess, "height": height, "side": side}
