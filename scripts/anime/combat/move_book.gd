class_name MoveBook
extends RefCounted
## Every move a fighter can choose in a live fight (CombatSim). Nothing here is a sequence: the brain picks one move at
## a time from distance, stamina, health, the escalation phase and what the opponent just did.
##   clip / seg [from, to] (fractions of the clip) / speed  - the motion (Move Library mocap "ml_*", the Mixamo sword set,
##                                                          UAL); the body's travel is the sim's, never the clip's
##   kind     melee / ranged / dash / aerial / launcher / slam / beam / dodge / block / parry / charge / taunt / jump
##   tier     1 light, 2 heavy, 3 power (unlocked by escalation; 0 = defence / movement)
##   range    [min, max] metres to the target it is chosen at
##   stam     stamina cost; hits: fractions of the move's duration where it strikes; dmg per hit (before scaling)
##   travel   metres along the line to the target during the move (negative = away; "side" = sideways)
##   lift     metres of air at the top of the move (jumps); launch: metres the target is thrown up on a clean hit
##   knock    metres the target is driven back; down: a clean hit knocks her down
##   fx       which effect (CombatSim._fx_*)

const MOVES := {
	# ------------------------------------------------------------------ tier 1: light
	"palm_dash": {"clip": "ml_dash_palm_strike", "seg": [0.10, 0.80], "speed": 1.55, "kind": "dash", "tier": 1, "range": [2.0, 6.5], "stam": 10,
		"hits": [0.52], "dmg": 6.0, "travel": 1.0, "knock": 1.2, "fx": "palm"},
	"jab_combo": {"clip": "ml_three_hit_combo", "seg": [0.08, 0.86], "speed": 1.45, "kind": "melee", "tier": 1, "range": [0.0, 2.3], "stam": 12,
		"hits": [0.32, 0.52, 0.74], "dmg": 3.5, "travel": 0.6, "knock": 0.4, "fx": "jab"},
	"front_kick": {"clip": "ml_front_kick", "seg": [0.12, 0.80], "speed": 1.5, "kind": "melee", "tier": 1, "range": [0.0, 2.1], "stam": 9,
		"hits": [0.48], "dmg": 6.0, "travel": 0.5, "knock": 1.4, "fx": "kick"},
	"quick_cast": {"clip": "cast_quick", "seg": [0.0, 1.0], "speed": 1.0, "kind": "ranged", "tier": 1, "range": [3.0, 14.0], "stam": 8,
		"hits": [0.55], "dmg": 5.0, "travel": -0.3, "knock": 0.8, "fx": "bolt"},
	"one_hand_cast": {"clip": "ml_cast_one_hand", "seg": [0.15, 0.8], "speed": 1.5, "kind": "ranged", "tier": 1, "range": [3.5, 14.0], "stam": 9,
		"hits": [0.5], "dmg": 6.0, "travel": 0.0, "knock": 1.0, "fx": "bolt"},
	# ------------------------------------------------------------------ tier 2: heavy
	"crescent_kick": {"clip": "ml_crescent_kick", "seg": [0.12, 0.84], "speed": 1.45, "kind": "melee", "tier": 2, "range": [0.0, 2.5], "stam": 14,
		"hits": [0.5], "dmg": 9.0, "travel": 0.8, "knock": 2.0, "fx": "crescent"},
	"spin_back_kick": {"clip": "ml_spin_back_kick", "seg": [0.10, 0.84], "speed": 1.45, "kind": "melee", "tier": 2, "range": [0.0, 2.6], "stam": 15,
		"hits": [0.55], "dmg": 10.0, "travel": 0.9, "knock": 2.8, "fx": "crescent_big"},
	"low_sweep": {"clip": "ml_low_sweep", "seg": [0.10, 0.84], "speed": 1.5, "kind": "melee", "tier": 2, "range": [0.0, 2.2], "stam": 13,
		"hits": [0.5], "dmg": 8.0, "travel": 0.6, "knock": 0.8, "down": true, "fx": "sweep"},
	"uppercut": {"clip": "ml_uppercut_launcher", "seg": [0.12, 0.84], "speed": 1.5, "kind": "launcher", "tier": 2, "range": [0.0, 2.0], "stam": 16,
		"hits": [0.5], "dmg": 8.0, "travel": 0.7, "launch": 2.8, "fx": "launch"},
	"jump_spin_kick": {"clip": "ml_jump_spin_kick", "seg": [0.08, 0.86], "speed": 1.35, "kind": "aerial", "tier": 2, "range": [1.8, 5.5], "stam": 16,
		"hits": [0.6], "dmg": 10.0, "travel": 1.0, "lift": 1.5, "knock": 2.2, "fx": "crescent_big"},
	"blast": {"clip": "ml_cast_two_hand_blast", "seg": [0.12, 0.82], "speed": 1.4, "kind": "ranged", "tier": 2, "range": [3.0, 16.0], "stam": 16,
		"hits": [0.55], "dmg": 10.0, "travel": -0.4, "knock": 2.4, "fx": "blast"},
	"slide_attack": {"clip": "sword:great_sword_slide_attack", "seg": [0.05, 0.9], "speed": 1.3, "kind": "dash", "tier": 2, "range": [2.5, 7.0], "stam": 15,
		"hits": [0.55], "dmg": 9.0, "travel": 1.0, "knock": 0.6, "down": true, "fx": "slide"},
	"air_chase": {"clip": "sword:great_sword_jump_attack", "seg": [0.0, 0.9], "speed": 1.4, "kind": "aerial", "tier": 2, "range": [0.0, 6.0], "stam": 14,
		"hits": [0.62], "dmg": 9.0, "travel": 1.0, "lift": 2.6, "knock": 1.0, "down": true, "fx": "slam_small", "followup": true},
	# ------------------------------------------------------------------ tier 3: power
	"overhead_slam": {"clip": "ml_overhead_slam", "seg": [0.08, 0.86], "speed": 1.35, "kind": "slam", "tier": 3, "range": [1.5, 7.5], "stam": 22,
		"hits": [0.6], "dmg": 14.0, "travel": 1.0, "lift": 2.2, "knock": 1.5, "down": true, "fx": "eruption"},
	"beam": {"clip": "ml_beam_channel", "seg": [0.12, 0.88], "speed": 1.0, "kind": "beam", "tier": 3, "range": [4.0, 18.0], "stam": 24,
		"hits": [0.45, 0.6, 0.75], "dmg": 5.0, "travel": -0.2, "knock": 1.2, "fx": "beam"},
	"high_spin": {"clip": "sword:great_sword_high_spin_attack", "seg": [0.05, 0.9], "speed": 1.35, "kind": "melee", "tier": 3, "range": [0.0, 3.2], "stam": 20,
		"hits": [0.45, 0.62], "dmg": 7.0, "travel": 0.8, "knock": 2.6, "fx": "ring_slash"},
	"spike_line": {"clip": "ml_cast_two_hand_blast", "seg": [0.10, 0.75], "speed": 1.3, "kind": "ranged", "tier": 3, "range": [3.0, 12.0], "stam": 20,
		"hits": [0.62], "dmg": 12.0, "travel": -0.3, "launch": 1.6, "fx": "spikes"},
	# ------------------------------------------------------------------ suit mocap (2026-10-20: Mixamo and UAL are the
	# fight's body; the Move Library video clips stay for hand signs, gestures and ultimate poses)
	"rapier_thrust": {"clip": "ualf:Sword_Attack", "seg": [0.0, 1.0], "speed": 1.0, "kind": "dash", "tier": 1, "range": [1.5, 3.6], "stam": 10,
		"hits": [0.267], "dmg": 7.0, "travel": 1.5, "knock": 0.8, "fx": "jab"},
	"rapier_combo": {"clip": "ualf:Sword_Regular_Combo", "seg": [0.0, 1.0], "speed": 1.0, "kind": "melee", "tier": 1, "range": [1.2, 4.0], "stam": 14,
		"hits": [0.078, 0.244, 0.411, 0.522], "dmg": 3.5, "travel": 2.3, "knock": 0.5, "fx": "jab"},
	"rapier_dash": {"clip": "ualf:Sword_Dash", "seg": [0.0, 1.0], "speed": 1.0, "kind": "dash", "tier": 2, "range": [2.5, 5.5], "stam": 14,
		"hits": [0.216], "dmg": 9.0, "travel": 3.7, "knock": 1.2, "fx": "slide"},
	"heavy_combo": {"clip": "ualf:Sword_Heavy_Combo", "seg": [0.0, 1.0], "speed": 1.0, "kind": "melee", "tier": 3, "range": [1.2, 6.0], "stam": 22,
		"hits": [0.108, 0.269, 0.423, 0.6], "dmg": 5.0, "travel": 5.3, "knock": 2.4, "down": true, "fx": "ring_slash"},
	"glaive_cleave": {"clip": "sword:great_sword_slash_4", "seg": [0.0, 1.0], "speed": 1.0, "kind": "melee", "tier": 1, "range": [1.8, 3.6], "stam": 10,
		"hits": [0.426], "dmg": 7.0, "travel": 1.0, "knock": 1.0, "fx": "crescent"},
	"glaive_triple": {"clip": "sword:great_sword_slash_2", "seg": [0.0, 1.0], "speed": 1.0, "kind": "melee", "tier": 2, "range": [2.0, 5.5], "stam": 16,
		"hits": [0.217, 0.472, 0.745], "dmg": 5.0, "travel": 2.9, "knock": 1.6, "fx": "crescent_big"},
	"hook": {"clip": "ualf:Melee_Hook", "seg": [0.0, 1.0], "speed": 1.0, "kind": "melee", "tier": 1, "range": [0.0, 1.6], "stam": 8,
		"hits": [0.583], "dmg": 5.0, "travel": 0.3, "knock": 0.8, "fx": "jab"},
	"duck": {"clip": "sword:great_sword_crouching_4", "seg": [0.0, 1.0], "speed": 1.0, "kind": "dodge", "tier": 0, "range": [0.0, 99.0], "stam": 5,
		"travel": 0.0, "fx": ""},
	"jump_over": {"clip": "sword:great_sword_jump_2", "seg": [0.0, 1.0], "speed": 1.0, "kind": "dodge", "tier": 0, "range": [0.0, 99.0], "stam": 7,
		"travel": 0.0, "lift": 0.6, "fx": "ghosts"},
	# ------------------------------------------------------------------ defence and movement
	"dodge_left": {"clip": "ml_dodge_left", "seg": [0.12, 0.78], "speed": 1.7, "kind": "dodge", "tier": 0, "range": [0.0, 99.0], "stam": 8,
		"travel": "side_l", "dist": 2.4, "fx": "ghosts"},
	"dodge_right": {"clip": "ml_dodge_right", "seg": [0.12, 0.78], "speed": 1.7, "kind": "dodge", "tier": 0, "range": [0.0, 99.0], "stam": 8,
		"travel": "side_r", "dist": 2.4, "fx": "ghosts"},
	"backstep": {"clip": "ml_backstep_evade", "seg": [0.10, 0.80], "speed": 1.7, "kind": "dodge", "tier": 0, "range": [0.0, 99.0], "stam": 7,
		"travel": -2.6, "fx": "ghosts"},
	"roll": {"clip": "ual:Roll", "seg": [0.0, 0.95], "speed": 1.25, "kind": "dodge", "tier": 0, "range": [0.0, 99.0], "stam": 10,
		"travel": "side_r", "dist": 3.4, "fx": "ghosts"},
	"jump_away": {"clip": "lift_off", "seg": [0.25, 1.0], "speed": 1.4, "kind": "jump", "tier": 0, "range": [0.0, 99.0], "stam": 10,
		"travel": -3.6, "lift": 1.8, "fx": "ghosts"},
	"block": {"clip": "ualf:Sword_Block", "seg": [0.0, 0.8], "speed": 1.0, "kind": "block", "tier": 0, "range": [0.0, 99.0], "stam": 5, "fx": "shield"},
	"parry": {"clip": "ml_parry_counter", "seg": [0.08, 0.86], "speed": 1.45, "kind": "parry", "tier": 0, "range": [0.0, 2.6], "stam": 12,
		"hits": [0.62], "dmg": 9.0, "travel": 0.6, "knock": 2.0, "fx": "parry"},
	"charge": {"clip": "ml_charge_up", "seg": [0.1, 0.9], "speed": 1.2, "kind": "charge", "tier": 0, "range": [5.0, 99.0], "stam": -30, "fx": "aura"},
	"taunt": {"clip": "ml_taunt_beckon", "seg": [0.1, 0.9], "speed": 1.3, "kind": "taunt", "tier": 0, "range": [4.0, 99.0], "stam": -10, "fx": ""},
}

## The finisher of the climax (only the winner, only once): the cut-in, her domain, slow motion, the strike.
const ULTIMATE := {"clip": "ml_finisher_combo", "seg": [0.05, 0.95], "speed": 1.0, "charge_clip": "ml_charge_up"}

## Reactions when hit (chosen by the hit, never by the brain).
## (2026-10-20: the suit mocap's hits and knock-back)
const REACT := {"light": ["ualf:Hit_Chest", 0.0, 1.0, 1.0], "heavy": ["ualf:Idle_Shield_Break", 0.0, 1.0, 1.0],
	"down": ["ualf:Hit_Knockback", 0.0, 1.0, 1.0], "air": ["lift_off", 0.2, 0.9, 1.0], "land": ["land_soft", 0.0, 1.0, 1.2]}

## Locomotion loops between moves.
const LOCO := {"run": "run", "jog": "jog", "strafe_l": "sword:great_sword_strafe", "strafe_r": "sword:great_sword_strafe_2",
	"back": "sword:great_sword_strafe_3", "idle": "ml_fight_idle", "sprint": "dodge_dash"}
