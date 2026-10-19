class_name UltimateCast
extends RefCounted
## Combat v3 ultimates (2026-10-20): the 20 ultimate clips of Move Library v2 part 2, each with its name, owner and plan
## (MoveCatalog.ULTIMATES), its timing (GestureBook) and its shapes (SHAPES below: MagicCaster's release shapes, made
## big). The body performs the real clip through MagicCaster (hands and fingers mocapped; the energy gathers at her
## hands through the gather window; the effect leaves them at the release frame). Around it the cinematic rules:
##   0            the domain falls (the world dims into her colour), close up on her eyes
##   gather       close on her hands forming the sign
##   release-0.8  a low hero shot
##   release      slow time (0.3 for 0.7 s), an impact frame, the grand release
##   release+0.5  the camera pulled back wide by it
##   end          the aftermath: a two-shot as the light settles, the domain lifts
## The other girl is caught in it (her read is late: an ultimate is not dodged by a sidestep, a barrier may hold).

const SHAPES := {
	"ult_starfall_conductor": {"kind": "meteor", "n": 18, "size": 1.7, "dmg": 3.0},
	"ult_moon_crescent_cleave": {"kind": "weapon", "weapon": "violet_scythe", "size": 2.8, "dmg": 18.0, "wave": true, "greatsword": true},
	"ult_frozen_spike_field": {"kind": "rows", "n": 14, "lanes": 5, "size": 1.6, "dmg": 18.0, "launch": true},
	"ult_twin_hand_sigil": {"kind": "beam", "twin": true, "dur": 0.9, "size": 1.8, "dmg": 20.0},
	"ult_spiral_ascension": {"kind": "sky", "size": 2.0, "dmg": 20.0},
	"ult_heaven_spear": {"kind": "weapon", "weapon": "star_spear", "throw": true, "speed": 26.0, "size": 2.0, "dmg": 22.0},
	"ult_blooming_domain": {"kind": "domain", "size": 6.5, "dmg": 18.0, "linger": 5.0, "launch": true},
	"ult_thousand_palms": {"kind": "volley", "n": 24, "pre": "arrow", "size": 1.4, "dmg": 16.0},
	"ult_eclipse_ring": {"kind": "eclipse", "n": 10, "size": 2.2, "dmg": 5.0, "linger": 5.0},
	"ult_comet_dive_kick": {"kinds": ["crescent", "domain"], "size": 2.0, "dmg": 18.0, "launch": true},
	"ult_mirror_afterimage": {"kinds": ["crescent", "crescent", "crescent", "crescent"], "size": 1.6, "dmg": 16.0, "afterimages": true},
	"ult_gravity_press": {"kind": "eclipse", "n": 4, "size": 2.6, "dmg": 6.0, "linger": 3.0},
	"ult_lunar_waltz": {"kind": "crescent", "fan": 7, "size": 1.8, "speed": 16.0, "dmg": 18.0},
	"ult_sky_rending_slash": {"kind": "weapon", "weapon": "violet_scythe", "size": 3.2, "dmg": 20.0, "wave": true, "greatsword": true},
	"ult_crossed_arms_burst": {"kind": "domain", "size": 6.0, "dmg": 18.0, "linger": 3.0, "launch": true},
	"ult_final_seal_bow": {"kind": "seal", "size": 2.4, "dmg": 20.0, "linger": 2.0},
	"ult_storm_rider_flip": {"kind": "rows", "n": 10, "lanes": 5, "size": 1.6, "dmg": 18.0, "launch": true},
	"ult_star_archer": {"kind": "arrow", "n": 11, "speed": 30.0, "size": 1.6, "dmg": 4.0},
	"ult_duo_back_to_back_left": {"kind": "beam", "twin": true, "dur": 1.0, "size": 2.0, "dmg": 22.0},
	"ult_duo_hand_join_push": {"kind": "orb", "size": 2.6, "speed": 10.0, "dmg": 22.0},
}


## The full spell dict of an ultimate for MagicCaster.cast(..., over).
static func spell(ult: String, who: String) -> Dictionary:
	var sp: Dictionary = {"who": who, "clip": ult, "weight": "heavy", "aim": "chest", "height": "mid", "range": [0.0, 99.0],
		"energy": 0.0, "tool": "magic", "knock": 1.0, "speed": 18.0, "ultimate": true}
	sp.merge(SHAPES.get(ult, {"kind": "beam", "size": 2.0, "dmg": 18.0}), true)
	if not sp.has("kind"):
		sp.kind = (sp.kinds as Array)[(sp.kinds as Array).size() - 1] if sp.has("kinds") else "beam"   # (the last release's shape)
	sp.title = String(MoveCatalog.ULTIMATES.get(ult, {}).get("name", ult))
	return sp


## Performs ultimate `ult` by `who` on `other` in a MeleeSim, cinematics included. Returns its length (fight seconds).
static func perform(sim: MeleeSim, who: String, other: String, ult: String) -> float:
	var g := GestureBook.of(ult)
	if g.is_empty():
		push_error("[ultimate] %s has no gesture timing" % ult)
		return 0.0
	var d := sim.d
	var sp := spell(ult, who)
	var L := GestureBook.length(g)
	var t_g0 := GestureBook.at(g, float(g.gather[0]))
	var rels: Array = []
	for r in g.release:
		rels.append(GestureBook.at(g, float(r)))
	var t_rel: float = rels[rels.size() - 1] if (sp.has("kinds") or sp.has("pre")) else rels[0]
	var s: Dictionary = sim.S[who]
	var o: Dictionary = sim.S[other]
	o.p.late = 1.0                                    # (caught: no early sidestep out of an ultimate)
	sim.at(L + 0.5, func(): o.p.late = 0.0)
	var hand := String(g.hand)
	var hand_bone := "LeftHand" if hand == "lh" else "RightHand"
	var t0 := d.ft
	print("[ultimate] %s (%s, %s) from %.2f gather %.2f release %.2f end %.2f" % [sp.title, who, ult, t0, t0 + t_g0, t0 + t_rel, t0 + L])
	# the domain falls, close on her eyes
	d.domain(who, true, 0.8)
	d.cut(t0 + 0.001, "eyes", who, {})
	# her hands forming the sign
	d.cut(t0 + maxf(t_g0, 0.6), "hand", who, {"bone": hand_bone})
	# the low hero shot before the release
	d.cut(t0 + maxf(t_rel - 0.8, maxf(t_g0, 0.6) + 0.5), "hero_low", who, {})
	# slow time, an impact frame, the release, pulled back wide
	sim.at(t_rel - 0.06, func():
		d.slowmo(0.3, 0.7 * 0.3)
		d.impact(1.0, true, false))
	d.cut(t0 + t_rel - 0.02, "pullback", who, {"dist": 11.0, "high": 3.6})
	# the aftermath
	d.cut(t0 + L + 0.3, "two_mid", who, {})
	sim.at(L + 1.2, func(): d.domain(who, false, 1.2))
	if sp.get("afterimages", false):
		for r2 in rels:
			sim.at(float(r2) - 0.05, func(): d.fx.afterimages((sim.F[who] as MeleeFighter).c, who, 3, 0.04))
	sim.magic.cast(s, o, ult, sp)
	return L
