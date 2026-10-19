class_name GestureBook
extends RefCounted
## Combat v3: the timing of every spell gesture and ultimate clip of the Move Library (v2 part 1, 18 gestures; v2 part 2,
## 20 ultimates), read off the source videos at 10 fps and checked against the mocap (the casting hand's speed peak and
## full reach). A cast plays the clip (MoveCatalog "ml_<clip>") and these times drive its magic:
##   from / to   s of the clip that are played (the actor's idle lead-in and settle are cut)
##   speed       playback rate in a fight (small spells a little quicker; ultimates at 1, their slow motion is the camera's)
##   gather      [a, b] s: the energy gathers at the hand(s) from a to b (a sign, a held palm, a raised finger ...)
##   release     s (or several, a combo): the moment the effect leaves the hand - full reach right after the speed peak
##   hand        where it gathers and leaves from: "rh" / "lh" / "both" (her own right / left)
##   emit        the hand it flies from when that is another (the bow: gathered at the drawing hand, shot from the bow)
##   use         "body" (the clip plays full body) / "upper" (arms, torso and head from the clip, legs from the fight rig)
##   aim         deg: where the releasing hand points at the release, from her facing (+ = to her left). She turns by
##               -aim through the gesture so her hand points at the target (the bow arm is held out to her left)
##   extra       other moments of the clip the effect uses (an array that appears when her palm meets the ground ...)
## Clip times are in seconds of the 30 fps source; "eye" notes say what the source shows at the release.

const G := {
	# ------------------------------------------------------------------------------------------- spell gestures (18)
	"finger_snap_point": {"from": 0.4, "to": 2.5, "speed": 1.2, "gather": [0.6, 1.2], "release": [1.8], "hand": "rh", "use": "upper", "aim": 0.0,
		"eye": "index finger raised and a snap at 1.1, then she points at the target"},
	"sign_weave_fast": {"from": 0.5, "to": 3.3, "speed": 1.25, "gather": [0.6, 2.3], "release": [2.6], "hand": "rh", "use": "upper", "aim": 0.0,
		"eye": "fast hand signs at her chest, the right palm thrust out at 2.6"},
	"orb_gather": {"from": 0.2, "to": 3.6, "speed": 1.3, "gather": [0.4, 2.6], "release": [3.1], "hand": "both", "use": "upper", "aim": 38.0,
		"eye": "an orb held and turned between the palms, both palms pushed out at 3.0"},
	"stomp_cast": {"from": 0.7, "to": 2.2, "speed": 1.15, "gather": [0.8, 1.4], "release": [1.55], "hand": "both", "emit": "rf", "use": "body", "aim": 0.0,
		"eye": "fists out, the right knee drawn up, the stomp lands at 1.5"},
	"iaido_draw_slash": {"from": 0.6, "to": 2.5, "speed": 1.1, "gather": [0.8, 1.25], "release": [1.45], "hand": "rh", "use": "body", "aim": -60.0,
		"eye": "right hand on the hilt at her left hip, the draw cut out to her right at 1.45"},
	"spear_conjure_throw": {"from": 0.5, "to": 3.1, "speed": 1.15, "gather": [0.7, 1.6], "release": [2.5], "hand": "rh", "use": "body", "aim": -21.0,
		"eye": "right hand raised high (the spear forms), drawn back behind her head, thrown at 2.5"},
	"sword_combo_invisible": {"from": 0.5, "to": 3.3, "speed": 1.1, "gather": [0.5, 0.75], "release": [0.9, 1.3, 1.9, 2.5, 2.95], "hand": "rh", "use": "body", "aim": 0.0,
		"eye": "five cuts: overhead down 0.9, low 1.3, rising 1.9, across 2.5, overhead 2.95"},
	"arm_sweep_wave": {"from": 0.6, "to": 2.0, "speed": 1.1, "gather": [0.7, 1.0], "release": [1.15], "hand": "lh", "use": "body", "aim": 47.0,
		"eye": "the left arm sweeps out and the open palm lunges at 1.15"},
	"vortex_spin_cast": {"from": 0.8, "to": 2.4, "speed": 1.1, "gather": [0.9, 1.5], "release": [1.65], "hand": "both", "use": "body", "aim": 0.0,
		"eye": "a full spin with the arms out, both palms pushed forward at 1.65"},
	"array_ground_summon": {"from": 0.4, "to": 3.4, "speed": 1.15, "gather": [1.0, 2.3], "release": [2.6], "hand": "rh", "use": "body", "aim": 0.0,
		"extra": {"array": 1.05}, "eye": "drops to a kneel, right palm on the ground at 1.05 (the array), rises with the hand thrown up at 2.6"},
	"array_air_draw": {"from": 0.5, "to": 3.3, "speed": 1.15, "gather": [0.7, 2.3], "release": [2.55], "hand": "rh", "use": "upper", "aim": 0.0,
		"extra": {"draw": [0.7, 1.6], "line": [1.6, 2.0]}, "eye": "the right fingertip draws a circle and a line in the air, the palm pushes through it at 2.55"},
	"barrier_raise": {"from": 0.4, "to": 2.4, "speed": 1.2, "gather": [0.5, 0.7], "release": [0.75], "hand": "both", "use": "body", "aim": 0.0,
		"extra": {"widen": 1.6}, "eye": "both palms forward at 0.75 (the wall forms), arms spread wide at 1.6 (it widens)"},
	"meteor_call": {"from": 0.4, "to": 3.2, "speed": 1.15, "gather": [0.8, 2.1], "release": [2.55], "hand": "both", "use": "body", "aim": 0.0,
		"eye": "arms rise wide to the sky, crossed and pulled down at 2.4, lands in a wide stance at 2.6"},
	"sky_call_point": {"from": 0.5, "to": 3.4, "speed": 1.15, "gather": [0.8, 2.4], "release": [2.85], "hand": "rh", "use": "body", "aim": 0.0,
		"eye": "right index finger held to the sky, then pointed at the target at 2.85"},
	"pillar_raise": {"from": 0.0, "to": 2.6, "speed": 1.15, "gather": [0.0, 0.9], "release": [1.9], "hand": "both", "use": "upper", "aim": 0.0,
		"eye": "crouched, palms low to the ground, rising with both arms thrown up at 1.9"},
	"bow_draw_release": {"from": 0.5, "to": 4.0, "speed": 1.2, "gather": [1.6, 3.6], "release": [3.8], "hand": "rh", "emit": "lh", "use": "body", "aim": 86.0,
		"eye": "bow arm out to her left, the right hand draws to her cheek, looses at 3.8"},
	"seal_finish": {"from": 0.4, "to": 2.6, "speed": 1.15, "gather": [0.6, 1.7], "release": [2.0], "hand": "both", "use": "upper", "aim": 0.0,
		"eye": "palms together, then the seal sign locks at 2.0"},
	"domain_expand": {"from": 0.3, "to": 4.4, "speed": 1.2, "gather": [0.3, 2.2], "release": [3.6], "hand": "both", "use": "body", "aim": 0.0,
		"eye": "prayer hands, one arm sweeps up and round, both arms open wide at 3.6"},
	# ------------------------------------------------------------------------------------------- ultimates (20)
	"ult_starfall_conductor": {"from": 0.0, "to": 5.0, "speed": 1.0, "gather": [0.4, 2.4], "release": [3.55], "hand": "both", "use": "upper", "aim": 0.0,
		"eye": "arms rise to the sky, conduct down, drop into a deep squat with palms out at 3.55"},
	"ult_moon_crescent_cleave": {"from": 0.3, "to": 5.0, "speed": 1.0, "gather": [0.9, 2.1], "release": [2.75], "hand": "rh", "use": "body", "aim": 90.0,
		"eye": "right arm raised (the scythe forms), a sweeping turn, the cleave lunge at 2.75"},
	"ult_frozen_spike_field": {"from": 0.2, "to": 5.0, "speed": 1.0, "gather": [0.5, 2.8], "release": [3.4], "hand": "both", "use": "upper", "aim": 0.0,
		"eye": "palms flat on the ground (frost spreads), hands swept up at 3.4"},
	"ult_twin_hand_sigil": {"from": 0.4, "to": 5.0, "speed": 1.0, "gather": [0.8, 3.2], "release": [3.9], "hand": "both", "use": "upper", "aim": 37.0,
		"eye": "a twin hand sign held at her chest, both hands thrust out at 3.9"},
	"ult_spiral_ascension": {"from": 0.2, "to": 5.0, "speed": 1.0, "gather": [0.4, 3.3], "release": [3.5], "hand": "rh", "use": "body", "aim": 0.0,
		"eye": "spins with the arms overhead, ends pointing to the sky at 3.5"},
	"ult_heaven_spear": {"from": 0.4, "to": 5.0, "speed": 1.0, "gather": [0.6, 1.3], "release": [3.85], "hand": "rh", "use": "body", "aim": -10.0,
		"extra": {"spear": 1.3}, "eye": "leaps reaching up (the spear forms at 1.3), holds it overhead, the throw at 3.85"},
	"ult_blooming_domain": {"from": 0.0, "to": 5.0, "speed": 1.0, "gather": [0.0, 1.0], "release": [3.7], "hand": "both", "use": "body", "aim": 0.0,
		"eye": "kneeling with clasped hands, rises opening them, arms wide at 3.7"},
	"ult_thousand_palms": {"from": 0.0, "to": 5.0, "speed": 1.0, "gather": [0.0, 0.4], "release": [0.6, 0.9, 1.2, 1.5, 1.8, 2.1, 2.4, 3.9], "hand": "both", "use": "body", "aim": 49.0,
		"eye": "a palm flurry from a side stance, the final double palm at 3.9"},
	"ult_eclipse_ring": {"from": 0.3, "to": 5.0, "speed": 1.0, "gather": [0.5, 3.4], "release": [3.7], "hand": "both", "use": "upper", "aim": -28.0,
		"eye": "the arms draw a ring overhead, hands gather at her chest, thrust out at 3.7"},
	"ult_comet_dive_kick": {"from": 0.8, "to": 5.0, "speed": 1.0, "gather": [1.0, 1.6], "release": [2.4, 3.45], "hand": "both", "emit": "rf", "use": "upper", "aim": 0.0,
		"eye": "run-up, a leap, the flying kick at 2.4, lands crouched with a palm on the ground at 3.45"},
	"ult_mirror_afterimage": {"from": 0.0, "to": 4.0, "speed": 1.0, "gather": [0.0, 0.3], "release": [0.5, 1.55, 2.45, 3.3], "hand": "rh", "use": "body", "aim": 0.0,
		"eye": "a punch 0.5, a side kick 1.55, a palm 2.45, a spin kick 3.3"},
	"ult_gravity_press": {"from": 0.0, "to": 5.0, "speed": 1.0, "gather": [0.4, 2.0], "release": [2.6], "hand": "rh", "use": "body", "aim": 0.0,
		"extra": {"impact": 4.0}, "eye": "right palm raised high, pressed slowly down from 2.6, the well lands at 4.0"},
	"ult_lunar_waltz": {"from": 0.3, "to": 5.0, "speed": 1.0, "gather": [0.5, 3.2], "release": [3.6], "hand": "rh", "use": "upper", "aim": 0.0,
		"eye": "waltz turns with flowing arms, ends with her hand reaching out at 3.6"},
	"ult_sky_rending_slash": {"from": 0.3, "to": 5.0, "speed": 1.0, "gather": [0.5, 2.2], "release": [2.6], "hand": "both", "use": "body", "aim": 0.0,
		"eye": "both hands overhead on the hilt, the cut down to a kneel at 2.6"},
	"ult_crossed_arms_burst": {"from": 0.2, "to": 5.0, "speed": 1.0, "gather": [0.5, 2.5], "release": [2.75], "hand": "both", "use": "body", "aim": 0.0,
		"eye": "forearms crossed at her chest, thrown open at 2.75"},
	"ult_final_seal_bow": {"from": 0.3, "to": 5.0, "speed": 1.0, "gather": [0.5, 2.2], "release": [2.4], "hand": "both", "use": "body", "aim": 0.0,
		"extra": {"bow": 3.0}, "eye": "signs at her chest, the seal locks at 2.4, then she bows"},
	"ult_storm_rider_flip": {"from": 0.8, "to": 5.0, "speed": 1.0, "gather": [1.0, 1.6], "release": [3.5], "hand": "both", "use": "upper", "aim": 0.0,
		"eye": "run-up, a twisting flip from 2.2, lands in a low wide stance at 3.5"},
	"ult_star_archer": {"from": 0.0, "to": 5.0, "speed": 1.0, "gather": [1.5, 3.7], "release": [3.95], "hand": "rh", "emit": "lh", "use": "body", "aim": 87.0,
		"eye": "the bow raised and drawn to her cheek, looses at 3.95"},
	"ult_duo_back_to_back_left": {"from": 0.3, "to": 5.0, "speed": 1.0, "gather": [0.5, 2.8], "release": [3.1], "hand": "both", "use": "body", "aim": 75.0,
		"eye": "back to back with the partner (mirrored for her), the arm thrown out at 3.1"},
	"ult_duo_hand_join_push": {"from": 0.3, "to": 5.0, "speed": 1.0, "gather": [0.5, 3.0], "release": [3.4], "hand": "both", "use": "body", "aim": -76.0,
		"eye": "hands joined with the partner (mirrored for her), the push out at 3.4"},
}


static func of(clip: String) -> Dictionary:
	return G.get(clip, {})


## Fight seconds from the start of the cast to clip time `ct` (the clip plays from `from` at `speed`).
static func at(g: Dictionary, ct: float) -> float:
	return maxf(ct - float(g.from), 0.0) / maxf(float(g.speed), 0.01)


## How long the cast holds her body.
static func length(g: Dictionary) -> float:
	return at(g, float(g.to))
