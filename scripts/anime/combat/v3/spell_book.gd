class_name SpellBook
extends RefCounted
## Combat v3 magic with a body: every spell is a gesture first (key poses on the fight rig), the energy gathering AT
## her hand bone (it stays there until the release), then the release FROM the hand. Small spells: one hand. Big ones:
## both arms, a deeper wider stance, the hair blown by the gathering wind. Mika: star and ice. Luna: moon and violet.
##   kind     bolt (a shard / crescent thrown) / orb (a bigger, slower one) / beam / spikes (a line from the ground) /
##            wave (a crescent skimming the ground) / barrier (defence) / weapon (conjured, then used, then gone)
##   gesture  one_hand / two_hand / stomp / sweep / overhead (MeleeBook-style key poses below)
##   hand     the hand it gathers at and leaves from ("rh" / "lh" / "both")
##   gather   s at the hand; speed m/s (bolts / orbs / waves); dur s (beams); dmg, weight; height read by the defender
##   tool     the tool type for the variety rule (magic / weapon)

const SPELLS := {
	# ---------------------------------------------------------------------------------------------- Mika
	"star_bolt": {"who": "mika", "kind": "bolt", "gesture": "one_hand", "hand": "rh", "gather": 0.22, "hold": 0.3, "speed": 15.0, "size": 0.8,
		"dmg": 6.0, "weight": "light", "aim": "chest", "height": "mid", "range": [2.2, 9.0], "energy": 8.0, "tool": "magic"},
	"frost_orb": {"who": "mika", "kind": "orb", "gesture": "two_hand", "hand": "both", "gather": 0.8, "speed": 9.0, "size": 1.35,
		"dmg": 10.0, "weight": "heavy", "aim": "chest", "height": "mid", "range": [2.5, 9.0], "energy": 16.0, "tool": "magic", "knock": 0.7},
	"ice_spikes": {"who": "mika", "kind": "spikes", "gesture": "stomp", "hand": "rh", "gather": 0.25, "dmg": 9.0, "weight": "heavy",
		"aim": "ankle_l", "height": "low", "range": [2.0, 7.0], "energy": 14.0, "tool": "magic", "launch": true},
	"star_beam": {"who": "mika", "kind": "beam", "gesture": "overhead", "hand": "both", "gather": 0.9, "dur": 0.55, "dmg": 13.0,
		"weight": "heavy", "aim": "chest", "height": "mid", "range": [3.0, 10.0], "energy": 26.0, "tool": "magic", "knock": 0.9},
	"ice_blade": {"who": "mika", "kind": "weapon", "gesture": "draw", "hand": "rh", "gather": 0.2, "weapon": "ice_blade",
		"dmg": 8.0, "weight": "medium", "aim": "chest", "height": "mid", "range": [0.8, 1.6], "energy": 12.0, "tool": "weapon", "slashes": 3},
	"star_spear": {"who": "mika", "kind": "weapon", "gesture": "draw", "hand": "rh", "gather": 0.25, "weapon": "star_spear",
		"dmg": 11.0, "weight": "heavy", "aim": "chest", "height": "mid", "range": [3.0, 9.0], "energy": 18.0, "tool": "weapon", "throw": true, "speed": 18.0},
	# ---------------------------------------------------------------------------------------------- Luna
	"moon_crescent": {"who": "luna", "kind": "bolt", "gesture": "sweep", "hand": "rh", "gather": 0.22, "speed": 13.0, "size": 1.0,
		"dmg": 7.0, "weight": "light", "aim": "chest", "height": "mid", "range": [2.2, 9.0], "energy": 8.0, "tool": "magic"},
	"violet_orb": {"who": "luna", "kind": "orb", "gesture": "two_hand", "hand": "both", "gather": 0.85, "speed": 8.5, "size": 1.3,
		"dmg": 10.0, "weight": "heavy", "aim": "chest", "height": "mid", "range": [2.5, 9.0], "energy": 16.0, "tool": "magic", "knock": 0.7},
	"moon_thorns": {"who": "luna", "kind": "spikes", "gesture": "stomp", "hand": "lh", "gather": 0.28, "dmg": 9.0, "weight": "heavy",
		"aim": "ankle_r", "height": "low", "range": [2.0, 7.0], "energy": 14.0, "tool": "magic", "launch": true},
	"violet_wave": {"who": "luna", "kind": "wave", "gesture": "sweep", "hand": "rh", "gather": 0.25, "speed": 8.0, "size": 1.0,
		"dmg": 8.0, "weight": "medium", "aim": "stomach", "height": "low", "range": [2.0, 8.0], "energy": 10.0, "tool": "magic"},
	"lunar_beam": {"who": "luna", "kind": "beam", "gesture": "overhead", "hand": "both", "gather": 0.9, "dur": 0.55, "dmg": 13.0,
		"weight": "heavy", "aim": "chest", "height": "mid", "range": [3.0, 10.0], "energy": 26.0, "tool": "magic", "knock": 0.9},
	"violet_scythe": {"who": "luna", "kind": "weapon", "gesture": "draw", "hand": "rh", "gather": 0.22, "weapon": "violet_scythe",
		"dmg": 9.0, "weight": "heavy", "aim": "chest", "height": "mid", "range": [1.0, 2.0], "energy": 14.0, "tool": "weapon", "slashes": 2},
	"moon_whip": {"who": "luna", "kind": "weapon", "gesture": "draw", "hand": "rh", "gather": 0.2, "weapon": "moon_whip",
		"dmg": 7.0, "weight": "medium", "aim": "chest", "height": "mid", "range": [1.6, 2.8], "energy": 10.0, "tool": "weapon", "slashes": 2},
	# ---------------------------------------------------------------------------------------------- both
	"barrier": {"who": "both", "kind": "barrier", "gesture": "two_hand_block", "hand": "both", "gather": 0.1, "dmg": 0.0,
		"weight": "light", "energy": 6.0, "tool": "magic"},
}

## gesture -> [windup / gather pose, release pose] (MeleeBook GUARD offsets, skeleton space: x her left, y up, z toward
## the opponent). "dyn" marks the hand that is aimed at the target on the release.
const GESTURES := {
	"one_hand": [
		{"hip": Vector3(0.0, -0.05, -0.03), "hip_rot": Vector3(2.0, -38.0, 0.0), "spine": Vector3(2.0, 34.0, 0.0), "rh": Vector3(-0.22, 1.0, -0.04),
			"lh": Vector3(0.12, 1.28, 0.3), "rp": Vector3(-0.6, -1.0, -0.4), "rfist": 0.25, "head": Vector3(4, -18, 0)},
		{"hip": Vector3(0.0, -0.04, 0.06), "hip_rot": Vector3(4.0, 8.0, 0.0), "spine": Vector3(6.0, -26.0, 0.0), "lh": Vector3(0.18, 1.12, 0.12),
			"rsh": 14.0, "rfist": 0.0, "rfp": 20.0},
	],
	"two_hand": [
		{"hip": Vector3(0.0, -0.13, -0.05), "hip_rot": Vector3(6.0, -20.0, 0.0), "spine": Vector3(-4.0, 18.0, 0.0), "lh": Vector3(0.07, 1.16, 0.22),
			"rh": Vector3(-0.07, 1.14, 0.22), "lf": Vector3(0.16, 0.0, 0.2), "rf": Vector3(-0.17, 0.0, -0.2), "lfist": 0.2, "rfist": 0.2,
			"lp": Vector3(0.8, -1.0, -0.3), "rp": Vector3(-0.8, -1.0, -0.3)},
		{"hip": Vector3(0.0, -0.1, 0.07), "hip_rot": Vector3(8.0, -6.0, 0.0), "spine": Vector3(10.0, 2.0, 0.0), "lsh": 10.0, "rsh": 10.0,
			"lfist": 0.0, "rfist": 0.0, "lf": Vector3(0.16, 0.0, 0.2), "rf": Vector3(-0.17, 0.0, -0.2)},
	],
	"overhead": [
		{"hip": Vector3(0.0, -0.16, -0.06), "hip_rot": Vector3(-6.0, -12.0, 0.0), "spine": Vector3(-14.0, 8.0, 0.0), "head": Vector3(-14, 0, 0),
			"lh": Vector3(0.1, 1.72, 0.08), "rh": Vector3(-0.1, 1.72, 0.08), "lf": Vector3(0.18, 0.0, 0.2), "rf": Vector3(-0.18, 0.0, -0.22),
			"lfist": 0.15, "rfist": 0.15, "lp": Vector3(1.0, 0.2, -0.3), "rp": Vector3(-1.0, 0.2, -0.3), "hands": "root"},
		{"hip": Vector3(0.0, -0.12, 0.08), "hip_rot": Vector3(10.0, -4.0, 0.0), "spine": Vector3(12.0, 2.0, 0.0), "lsh": 12.0, "rsh": 12.0,
			"lfist": 0.0, "rfist": 0.0, "lf": Vector3(0.18, 0.0, 0.2), "rf": Vector3(-0.18, 0.0, -0.22)},
	],
	"stomp": [
		{"hip": Vector3(0.0, 0.02, -0.02), "hip_rot": Vector3(-2.0, -18.0, 0.0), "spine": Vector3(-4.0, 10.0, 0.0), "rf": Vector3(-0.1, 0.38, 0.06),
			"rfp": 10.0, "rh": Vector3(-0.2, 1.42, 0.12), "lh": Vector3(0.16, 1.2, 0.2), "rfist": 0.1},
		{"hip": Vector3(0.0, -0.17, 0.04), "hip_rot": Vector3(14.0, -14.0, 0.0), "spine": Vector3(18.0, 6.0, 0.0), "rf": Vector3(-0.13, 0.0, -0.02),
			"rh": Vector3(-0.16, 0.62, 0.3), "lh": Vector3(0.22, 1.1, 0.0), "rfist": 0.0, "hands": "root"},
	],
	"sweep": [
		{"hip": Vector3(0.0, -0.06, -0.03), "hip_rot": Vector3(0.0, -40.0, 0.0), "spine": Vector3(0.0, 36.0, 0.0), "rh": Vector3(-0.42, 1.12, -0.06),
			"lh": Vector3(0.14, 1.26, 0.26), "rp": Vector3(-0.4, -1.0, -0.6), "rfist": 0.0},
		{"hip": Vector3(0.0, -0.08, 0.05), "hip_rot": Vector3(2.0, 18.0, 0.0), "spine": Vector3(4.0, -36.0, 0.0), "lh": Vector3(0.2, 1.16, 0.12),
			"rsh": 16.0, "rfist": 0.0, "lfy": 10.0},
	],
	"draw": [
		{"hip": Vector3(0.0, -0.08, -0.03), "hip_rot": Vector3(4.0, -30.0, 0.0), "spine": Vector3(4.0, 22.0, 0.0), "rh": Vector3(0.12, 1.02, 0.16),
			"lh": Vector3(0.14, 1.08, 0.2), "rfist": 0.9, "lfist": 0.4, "rp": Vector3(-0.5, -1.0, 0.2)},
		{"hip": Vector3(0.0, -0.06, 0.03), "hip_rot": Vector3(2.0, 10.0, 0.0), "spine": Vector3(2.0, -16.0, 0.0), "rh": Vector3(-0.42, 1.18, 0.22),
			"lh": Vector3(0.16, 1.24, 0.22), "rfist": 1.0, "rp": Vector3(-0.8, -1.0, 0.0)},
	],
	"two_hand_block": [
		{"hip": Vector3(0.0, -0.08, -0.04), "hip_rot": Vector3(4.0, -16.0, 0.0), "spine": Vector3(-2.0, 12.0, 0.0), "lh": Vector3(0.16, 1.3, 0.34),
			"rh": Vector3(-0.16, 1.28, 0.34), "lfist": 0.0, "rfist": 0.0},
		{"hip": Vector3(0.0, -0.1, -0.05), "hip_rot": Vector3(4.0, -16.0, 0.0), "spine": Vector3(-4.0, 12.0, 0.0), "lh": Vector3(0.2, 1.32, 0.38),
			"rh": Vector3(-0.2, 1.3, 0.38), "lfist": 0.0, "rfist": 0.0},
	],
}


static func spells_of(who: String) -> Array:
	var out := []
	for n in SPELLS:
		if String(SPELLS[n].who) in [who, "both"]:
			out.append(n)
	return out
