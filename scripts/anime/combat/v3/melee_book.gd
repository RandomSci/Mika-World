class_name MeleeBook
extends RefCounted
## Combat v3: the close-combat move book. Every move is a few KEY POSES of the procedural fight rig (MeleeFighter),
## timed in seconds, never a clip: the mocapped Move Library strikes barely leave the body (MediaPipe loses depth: the
## hands of three_hit_combo never get 0.2 m in front of the hips), so a strike here is the hips and shoulders turning
## over and the fist or foot driven by two-bone IK onto the other girl's real bone. (After Overgrowth's key-pose +
## IK approach, David Rosen, GDC 2014, and fighting-game frame data: startup / active / recovery, Dustloop.)
##
## Pose space = her skeleton space: +Z toward the opponent, +X her left, +Y up, the origin on the ground under her
## hips; metres for Mika (scaled by her height for Luna), degrees for angles.
##   hip       offset of the hips from standing          hip_rot   pitch (+ = lean forward), yaw (+ = turn to her left), roll
##   spine     the turn of the spine above the hips      head      added to the head's aim at the opponent
##   lh / rh   left / right wrist                        lp / rp   which way the elbow points
##   lf / rf   left / right ankle (y > 0: off the ground) lfy / rfy foot yaw, lfp / rfp foot pitch (+ = heel up)
##   lsh / rsh shoulder pushed forward                   lfist / rfist  1 = a fist, 0 = an open hand
## A key that names a limb in "dyn" drives it at a live world point instead (the contact point, set by MeleeSim).

## The fighting stance, orthodox (left side forward): chin down, hands at the cheekbones, rear heel a little up; feet
## a natural stance apart (0.33 m front to back, 0.23 m wide for Mika) with BOTH knees softly bent (10 - 15 deg) -
## never a rear leg stretched out behind her (that locks or flips the knee).
const GUARD := {
	"hip": Vector3(0.0, -0.014, -0.01), "hip_rot": Vector3(5.0, -24.0, 0.0), "spine": Vector3(6.0, 15.0, 0.0), "head": Vector3(6.0, 0.0, 0.0),
	"lh": Vector3(0.08, 1.31, 0.29), "rh": Vector3(-0.09, 1.33, 0.16), "lp": Vector3(0.55, -1.0, -0.25), "rp": Vector3(-0.55, -1.0, -0.3),
	"lf": Vector3(0.11, 0.0, 0.18), "rf": Vector3(-0.12, 0.0, -0.18), "lfy": -10.0, "rfy": -45.0, "lfp": 0.0, "rfp": 8.0,
	"lsh": 4.0, "rsh": 0.0, "lfist": 1.0, "rfist": 1.0,
}

## Attacks. wind / active / recover in seconds at speed 1 (the brain plays them 0.9 - 1.1x); `reach` = the distance
## between the two of them the attacker closes to by the hit (she steps in during the windup); `aim` = the point on
## the defender; `height` / `weight` / `from` (the side of HER body it arrives at: L / R / C) drive the defence.
const MOVES := {
	"jab": {"limb": "lh", "aim": "face", "height": "high", "weight": "light", "from": "C", "reach": 0.80, "range": [0.6, 1.4],
		"wind": 0.12, "active": 0.06, "recover": 0.13, "palm": "down", "dmg": 4.0,
		"keys": [
			{"hip": Vector3(0.0, -0.085, -0.02), "hip_rot": Vector3(5.0, -28.0, 0.0), "spine": Vector3(6.0, 10.0, 0.0), "lh": Vector3(0.10, 1.29, 0.24)},
			{"hip": Vector3(0.0, -0.08, 0.07), "hip_rot": Vector3(7.0, -34.0, 0.0), "spine": Vector3(8.0, -6.0, -2.0), "lsh": 20.0,
				"lp": Vector3(0.35, -1.0, 0.0), "lf": Vector3(0.12, 0.0, 0.33), "rh": Vector3(-0.08, 1.35, 0.15)},
		]},
	"cross": {"limb": "rh", "aim": "face", "height": "high", "weight": "light", "from": "C", "reach": 0.84, "range": [0.75, 1.5],
		"wind": 0.14, "active": 0.07, "recover": 0.16, "palm": "down", "dmg": 6.0,
		"keys": [
			{"hip": Vector3(0.0, -0.09, -0.04), "hip_rot": Vector3(5.0, -32.0, 0.0), "spine": Vector3(5.0, 6.0, 0.0), "rh": Vector3(-0.12, 1.30, 0.10)},
			{"hip": Vector3(0.0, -0.09, 0.10), "hip_rot": Vector3(9.0, 14.0, 0.0), "spine": Vector3(9.0, 30.0, 2.0), "rsh": 24.0,
				"rp": Vector3(-0.35, -1.0, 0.0), "rfy": -10.0, "rfp": 32.0, "rf": Vector3(-0.12, 0.0, -0.16), "lh": Vector3(0.06, 1.36, 0.20)},
		]},
	"hook": {"limb": "lh", "aim": "temple_r", "height": "high", "weight": "medium", "from": "R", "reach": 0.70, "range": [0.7, 1.3],
		"wind": 0.16, "active": 0.08, "recover": 0.17, "palm": "down", "dmg": 7.0, "arc": {"lh": Vector3(0.32, 0.03, -0.05)},
		"keys": [
			{"hip": Vector3(0.02, -0.11, -0.01), "hip_rot": Vector3(6.0, -10.0, 4.0), "spine": Vector3(6.0, 20.0, 4.0), "lh": Vector3(0.22, 1.30, 0.18),
				"lp": Vector3(1.0, 0.1, -0.3)},
			{"hip": Vector3(-0.02, -0.10, 0.05), "hip_rot": Vector3(7.0, -48.0, -2.0), "spine": Vector3(8.0, -30.0, -6.0), "lsh": 16.0,
				"lp": Vector3(1.0, 0.65, 0.0), "lfy": 20.0, "lfp": 18.0, "rh": Vector3(-0.07, 1.36, 0.16)},
		]},
	"uppercut": {"limb": "rh", "aim": "chin", "height": "high", "weight": "medium", "from": "C", "reach": 0.64, "range": [0.6, 1.2],
		"wind": 0.17, "active": 0.08, "recover": 0.18, "palm": "back", "dmg": 8.0,
		"keys": [
			{"hip": Vector3(0.0, -0.19, 0.0), "hip_rot": Vector3(10.0, -26.0, -6.0), "spine": Vector3(14.0, -6.0, -10.0), "rh": Vector3(-0.15, 1.02, 0.14),
				"rp": Vector3(-0.2, -1.0, 0.4)},
			{"hip": Vector3(0.0, -0.03, 0.07), "hip_rot": Vector3(2.0, 16.0, 4.0), "spine": Vector3(-4.0, 24.0, 6.0), "rsh": 12.0,
				"rp": Vector3(-0.3, -1.0, 0.6), "rfp": 30.0, "rfy": -15.0},
		]},
	"body_hook": {"limb": "rh", "aim": "ribs_l", "height": "mid", "weight": "medium", "from": "L", "reach": 0.68, "range": [0.65, 1.25],
		"wind": 0.16, "active": 0.08, "recover": 0.17, "palm": "in", "dmg": 7.0, "arc": {"rh": Vector3(-0.28, -0.04, -0.04)},
		"keys": [
			{"hip": Vector3(0.0, -0.17, 0.0), "hip_rot": Vector3(12.0, -32.0, 0.0), "spine": Vector3(14.0, -8.0, -12.0), "rh": Vector3(-0.22, 1.12, 0.10),
				"rp": Vector3(-1.0, -0.2, -0.3)},
			{"hip": Vector3(0.0, -0.17, 0.06), "hip_rot": Vector3(12.0, 18.0, -4.0), "spine": Vector3(16.0, 26.0, -12.0), "rsh": 14.0,
				"rp": Vector3(-1.0, 0.25, 0.0), "rfp": 30.0, "rfy": -12.0},
		]},
	"front_kick": {"limb": "rf", "aim": "stomach", "height": "mid", "weight": "heavy", "from": "C", "reach": 1.06, "range": [1.0, 1.75],
		"wind": 0.19, "active": 0.08, "recover": 0.2, "dmg": 9.0, "knock": 2.2, "separator": true,
		"keys": [
			{"hip": Vector3(0.0, -0.05, -0.05), "hip_rot": Vector3(-6.0, -14.0, 0.0), "spine": Vector3(-4.0, 10.0, 0.0), "rf": Vector3(-0.07, 0.52, 0.16),
				"rfy": 0.0, "lfp": 0.0, "lh": Vector3(0.10, 1.30, 0.24), "rh": Vector3(-0.10, 1.30, 0.12)},
			{"hip": Vector3(0.0, -0.04, 0.06), "hip_rot": Vector3(-14.0, -4.0, 0.0), "spine": Vector3(-8.0, 6.0, 0.0), "rfy": 0.0,
				"lh": Vector3(0.14, 1.28, 0.20), "rh": Vector3(-0.20, 1.20, -0.02)},
		]},
	"roundhouse": {"limb": "rf", "aim": "ribs_l", "height": "mid", "weight": "heavy", "from": "L", "reach": 0.98, "range": [0.95, 1.6],
		"wind": 0.22, "active": 0.09, "recover": 0.22, "dmg": 11.0, "knock": 2.6, "separator": true, "arc": {"rf": Vector3(-0.45, 0.05, -0.1)},
		"keys": [
			{"hip": Vector3(0.0, -0.05, -0.02), "hip_rot": Vector3(0.0, -40.0, -6.0), "spine": Vector3(2.0, 6.0, 6.0), "rf": Vector3(-0.22, 0.55, 0.02),
				"lfy": 10.0, "rfy": -30.0, "rh": Vector3(-0.30, 1.05, -0.08)},
			{"hip": Vector3(0.0, -0.03, 0.04), "hip_rot": Vector3(-6.0, 62.0, -30.0), "spine": Vector3(-2.0, 18.0, -8.0), "lfy": 100.0, "lfp": 14.0,
				"rfy": 40.0, "lh": Vector3(0.14, 1.34, 0.18), "rh": Vector3(-0.38, 1.10, -0.28)},
		]},
	"low_sweep": {"limb": "rf", "aim": "ankle_l", "height": "low", "weight": "heavy", "from": "L", "reach": 0.98, "range": [0.9, 1.5],
		"wind": 0.20, "active": 0.1, "recover": 0.22, "dmg": 8.0, "down": true, "arc": {"rf": Vector3(-0.5, 0.0, -0.15)},
		"keys": [
			{"hip": Vector3(0.0, -0.38, -0.02), "hip_rot": Vector3(20.0, -30.0, 0.0), "spine": Vector3(22.0, 0.0, 0.0), "rf": Vector3(-0.30, 0.04, 0.0),
				"lf": Vector3(0.16, 0.0, 0.20), "lfy": -10.0, "lh": Vector3(0.14, 1.24, 0.30)},
			{"hip": Vector3(0.0, -0.40, 0.02), "hip_rot": Vector3(22.0, 68.0, 0.0), "spine": Vector3(24.0, 20.0, 0.0), "rfy": 70.0, "lfy": 75.0},
		]},
	# outside crescent: the rear leg rises across her body and sweeps out through the side of the head
	"crescent_kick": {"limb": "rf", "aim": "temple_l", "height": "high", "weight": "heavy", "from": "L", "reach": 0.95, "range": [0.8, 1.4],
		"wind": 0.18, "active": 0.10, "recover": 0.22, "dmg": 10.0, "knock": 1.2, "arc": {"rf": Vector3(0.35, 0.35, 0.05)},
		"recover_arc": {"rf": Vector3(-0.32, 0.05, 0.22)},        # (the leg carries on across and drops outside, never folds back through her hip)
		"keys": [
			{"hip": Vector3(0.0, -0.03, -0.04), "hip_rot": Vector3(-8.0, -10.0, -10.0), "spine": Vector3(-10.0, 8.0, 6.0), "rf": Vector3(0.12, 0.55, 0.32),
				"rfy": 20.0, "lfy": -30.0, "lh": Vector3(0.12, 1.32, 0.22), "rh": Vector3(-0.18, 1.18, 0.05)},
			{"hip": Vector3(0.0, -0.02, 0.02), "hip_rot": Vector3(-14.0, -30.0, -16.0), "spine": Vector3(-14.0, 14.0, 8.0), "lfy": -55.0, "lfp": 10.0,
				"rfy": -20.0, "rh": Vector3(-0.32, 1.12, -0.10)},
		]},
	# axe: the straight rear leg goes up above her head, then chops down onto the crown / collarbone
	"axe_kick": {"limb": "rf", "aim": "crown", "height": "high", "weight": "heavy", "from": "C", "reach": 0.9, "range": [0.75, 1.35],
		"wind": 0.22, "active": 0.09, "recover": 0.22, "dmg": 12.0, "knock": 0.6, "arc": {"rf": Vector3(0.0, 0.25, -0.15)},
		"recover_arc": {"rf": Vector3(0.0, -0.25, 0.22)},         # (the chop carries the foot down in front, then it steps back)
		"wind_arc": {"rf": Vector3(0.0, -0.3, 0.38)},             # (the leg swings up in front of her, never through her hip)
		"keys": [
			{"hip": Vector3(0.0, -0.02, -0.06), "hip_rot": Vector3(-16.0, -8.0, -6.0), "spine": Vector3(-12.0, 6.0, 0.0), "rf": Vector3(-0.05, 1.6, 0.42),
				"rfy": 0.0, "lfp": 0.0, "lh": Vector3(0.16, 1.25, 0.25), "rh": Vector3(-0.20, 1.15, 0.05)},
			{"hip": Vector3(0.0, -0.12, 0.06), "hip_rot": Vector3(10.0, -12.0, 0.0), "spine": Vector3(12.0, 8.0, 0.0), "lh": Vector3(0.14, 1.20, 0.20),
				"rh": Vector3(-0.22, 1.05, -0.05)},
		]},
	# hook: the LEAD leg goes out past the head on her left and whips the heel back across it
	"hook_kick": {"limb": "lf", "aim": "temple_r", "height": "high", "weight": "heavy", "from": "R", "reach": 1.0, "range": [0.85, 1.45],
		"wind": 0.18, "active": 0.10, "recover": 0.22, "dmg": 10.0, "knock": 1.0, "surf": "heel", "arc": {"lf": Vector3(0.5, 0.1, 0.05)},
		"keys": [
			{"hip": Vector3(0.0, -0.04, -0.04), "hip_rot": Vector3(-6.0, -70.0, 28.0), "spine": Vector3(-6.0, 30.0, 10.0), "lf": Vector3(0.30, 0.75, 0.25),
				"lfy": -80.0, "rfy": -90.0, "rfp": 10.0, "lh": Vector3(0.05, 1.33, 0.22), "rh": Vector3(-0.12, 1.30, 0.12)},
			{"hip": Vector3(0.0, -0.03, 0.0), "hip_rot": Vector3(-10.0, -85.0, 32.0), "spine": Vector3(-10.0, 40.0, 12.0), "lfy": -60.0, "rfy": -110.0},
		]},
	# spinning back kick: she turns her back (the support foot pivots), the rear heel drives straight back into the
	# stomach, and she keeps turning the same way to face her again (never unwinds)
	"spin_back_kick": {"limb": "rf", "aim": "stomach", "height": "mid", "weight": "heavy", "from": "C", "reach": 1.05, "range": [0.9, 1.5],
		"wind": 0.2, "active": 0.09, "recover": 0.24, "dmg": 12.0, "knock": 2.4, "separator": true, "surf": "heel",
		"keys": [
			{"hip": Vector3(0.0, -0.08, -0.02), "hip_rot": Vector3(10.0, -165.0, 0.0), "spine": Vector3(8.0, -15.0, 0.0), "rf": Vector3(0.10, 0.45, 0.05),
				"lfy": -170.0, "rfy": -170.0, "lh": Vector3(0.10, 1.30, 0.22), "rh": Vector3(-0.08, 1.32, 0.12)},
			{"hip": Vector3(0.0, -0.06, -0.02), "hip_rot": Vector3(28.0, -178.0, 0.0), "spine": Vector3(20.0, -20.0, 0.0), "lfy": -175.0,
				"lh": Vector3(0.12, 1.28, 0.20), "rh": Vector3(-0.15, 1.25, 0.10)},
		],
		"recover_pose": {"hip_rot": Vector3(5.0, -384.0, 0.0), "lfy": -370.0, "rfy": -408.0}},
	# the rush-in finish: the dash is its windup (MeleeSim.rush), an open palm driven into her chest
	"palm_strike": {"limb": "rh", "aim": "chest", "height": "mid", "weight": "medium", "from": "C", "reach": 0.80, "range": [0.7, 1.5],
		"wind": 0.08, "active": 0.07, "recover": 0.18, "palm": "fwd", "dmg": 8.0, "open": true, "knock": 0.9,
		"keys": [
			{"hip": Vector3(0.0, -0.16, -0.02), "hip_rot": Vector3(14.0, -30.0, 0.0), "spine": Vector3(14.0, 4.0, 0.0), "rh": Vector3(-0.12, 1.18, 0.06), "rfist": 0.0},
			{"hip": Vector3(0.0, -0.15, 0.10), "hip_rot": Vector3(12.0, 18.0, 0.0), "spine": Vector3(12.0, 26.0, 0.0), "rsh": 22.0, "rfist": 0.0,
				"rp": Vector3(-0.3, -1.0, 0.0), "rfp": 34.0, "rfy": -8.0, "lf": Vector3(0.12, 0.0, 0.36)},
		]},
}

## Defences: the pose she holds while the strike arrives (blend in over `rise` s). `vs` = what it answers.
const GUARDS := {
	# a forearm up beside the head on side s (+1 her left / -1 her right): the strike lands on it
	"block_high": {"rise": 0.07, "arm": "side", "vs": ["high"],
		"pose": {"hip": Vector3(0.0, -0.11, -0.04), "hip_rot": Vector3(9.0, -22.0, 0.0), "spine": Vector3(10.0, 15.0, 0.0), "head": Vector3(14.0, 0.0, 0.0)},
		"arm_at": Vector3(0.07, 1.50, 0.17), "arm_pole": Vector3(1.0, -0.35, 0.3), "other_at": Vector3(0.06, 1.38, 0.20)},
	# both forearms in front of the face against a straight: the fist meets the nearer forearm
	"cover": {"rise": 0.06, "arm": "both", "vs": ["high"],
		"pose": {"hip": Vector3(0.0, -0.12, -0.05), "hip_rot": Vector3(10.0, -14.0, 0.0), "spine": Vector3(12.0, 10.0, 0.0), "head": Vector3(16.0, 0.0, 0.0),
			"lh": Vector3(0.045, 1.47, 0.20), "rh": Vector3(-0.045, 1.46, 0.19), "lp": Vector3(0.45, -1.0, 0.25), "rp": Vector3(-0.45, -1.0, 0.25)}},
	# a forearm down along the ribs on side s
	"block_mid": {"rise": 0.07, "arm": "side", "vs": ["mid"],
		"pose": {"hip": Vector3(0.0, -0.14, -0.04), "hip_rot": Vector3(12.0, -20.0, 0.0), "spine": Vector3(14.0, 12.0, 0.0), "head": Vector3(12.0, 0.0, 0.0)},
		"arm_at": Vector3(0.11, 1.22, 0.17), "arm_pole": Vector3(0.45, -1.0, 0.1), "other_at": Vector3(0.05, 1.36, 0.20)},
	# the lead shin lifted: a low kick lands on it (a kickboxer's check)
	"check": {"rise": 0.08, "arm": "", "vs": ["low"],
		"pose": {"hip": Vector3(0.0, -0.06, -0.06), "hip_rot": Vector3(4.0, -30.0, 0.0), "spine": Vector3(6.0, 18.0, 0.0),
			"lf": Vector3(0.16, 0.30, 0.20), "lfy": -40.0}},
	# off the line: the head and shoulders dip to side s, the strike passes by
	"slip": {"rise": 0.08, "evade": true, "vs": ["high"], "side_pose": true,
		"pose": {"hip": Vector3(0.12, -0.15, -0.02), "hip_rot": Vector3(10.0, -30.0, 12.0), "spine": Vector3(10.0, 6.0, 16.0), "head": Vector3(6.0, 0.0, 8.0)}},
	"duck": {"rise": 0.09, "evade": true, "vs": ["high"],
		"pose": {"hip": Vector3(0.0, -0.34, -0.06), "hip_rot": Vector3(26.0, -24.0, 0.0), "spine": Vector3(26.0, 14.0, 0.0), "head": Vector3(-14.0, 0.0, 0.0)}},
	# a fast step back out of reach (the root moves; the strike falls short)
	"backstep": {"rise": 0.08, "evade": true, "vs": ["high", "mid", "low"], "travel": -0.75,
		"pose": {"hip": Vector3(0.0, -0.10, -0.08), "hip_rot": Vector3(-4.0, -26.0, 0.0), "spine": Vector3(-8.0, 14.0, 0.0), "head": Vector3(4.0, 0.0, 0.0)}},
	# over a sweep
	"jump": {"rise": 0.07, "evade": true, "vs": ["low"], "lift": 0.5,
		"pose": {"hip": Vector3(0.0, -0.02, 0.0), "hip_rot": Vector3(8.0, -20.0, 0.0), "spine": Vector3(8.0, 12.0, 0.0),
			"lf": Vector3(0.12, 0.34, 0.12), "rf": Vector3(-0.12, 0.40, -0.10), "lfp": -10.0, "rfp": 30.0}},
	# the lead hand slaps the incoming arm aside at the last moment (needs an early read)
	"parry": {"rise": 0.05, "arm": "lead", "vs": ["high"], "parry": true,
		"pose": {"hip": Vector3(0.0, -0.10, -0.02), "hip_rot": Vector3(6.0, -30.0, 0.0), "spine": Vector3(8.0, 6.0, 0.0)}},
}
