class_name SpellBook
extends RefCounted
## Combat v3 magic with a body (2026-10-20): every spell is cast with one of the 18 spell gesture clips of Move Library
## v2 (GestureBook has their timing). The body performs the real gesture (the mocap, hands and fingers included); the
## energy gathers at her hand through the clip's gather window, inside a sigil (Mika a six point snow star ring, Luna a
## crescent rune ring), with a real light on her and the ground; the effect leaves the hand at the clip's release frame.
## Mika: ice blue, white and stars. Luna: violet, silver and the moon. 13 each, designed against the Battle of Mages
## quality bar (docs Combat_Progress.md): big readable shapes, lingering fields, the arena lit in her colour.
##   clip     the gesture clip (MoveCatalog / GestureBook name)
##   kind     what leaves the hand: volley / orb / rows / beam / weapon / meteor / sky / arrow / vortex / domain /
##            barrier / crescent / array / pillars / seal / eclipse / wave
##   dmg, weight, aim, height, range, energy, tool as before (weight drives hit stop and the reaction's strength)
##   size     shape scale; linger s a field stays; n count (daggers, meteors, pillars ...)

const SPELLS := {
	# ---------------------------------------------------------------------------------------------- Mika (13)
	"star_daggers": {"who": "mika", "clip": "finger_snap_point", "kind": "volley", "n": 12, "size": 1.0, "dmg": 7.0, "weight": "light",
		"aim": "chest", "height": "mid", "range": [2.5, 10.0], "energy": 10.0, "tool": "magic", "title": "Star Dagger Halo"},
	"frost_orb": {"who": "mika", "clip": "orb_gather", "kind": "orb", "size": 1.3, "speed": 9.0, "dmg": 10.0, "weight": "heavy",
		"aim": "chest", "height": "mid", "range": [2.5, 9.0], "energy": 16.0, "tool": "magic", "knock": 0.7, "title": "Frost Star Orb"},
	"glacier_rows": {"who": "mika", "clip": "stomp_cast", "kind": "rows", "n": 9, "size": 1.0, "dmg": 9.0, "weight": "heavy",
		"aim": "ankle_l", "height": "low", "range": [2.0, 8.0], "energy": 14.0, "tool": "magic", "launch": true, "linger": 2.5, "title": "Glacier Rows"},
	"starlight_lance": {"who": "mika", "clip": "sign_weave_fast", "kind": "beam", "dur": 0.6, "size": 1.0, "dmg": 12.0, "weight": "heavy",
		"aim": "chest", "height": "mid", "range": [3.0, 11.0], "energy": 22.0, "tool": "magic", "knock": 0.8, "title": "Starlight Lance"},
	"frost_iaido": {"who": "mika", "clip": "iaido_draw_slash", "kind": "weapon", "weapon": "ice_blade", "size": 1.4, "dmg": 9.0, "weight": "heavy",
		"aim": "chest", "height": "mid", "range": [1.0, 5.0], "energy": 12.0, "tool": "weapon", "wave": true, "title": "Frost Iaido"},
	"star_spear": {"who": "mika", "clip": "spear_conjure_throw", "kind": "weapon", "weapon": "star_spear", "size": 1.0, "dmg": 11.0, "weight": "heavy",
		"aim": "chest", "height": "mid", "range": [3.0, 11.0], "energy": 18.0, "tool": "weapon", "throw": true, "speed": 20.0, "title": "Star Spear"},
	"frost_blade_dance": {"who": "mika", "clip": "sword_combo_invisible", "kind": "weapon", "weapon": "ice_blade", "size": 1.0, "dmg": 6.0,
		"weight": "medium", "aim": "chest", "height": "mid", "range": [0.8, 2.2], "energy": 14.0, "tool": "weapon", "title": "Frost Blade Dance"},
	"meteor_rain": {"who": "mika", "clip": "meteor_call", "kind": "meteor", "n": 7, "size": 1.0, "dmg": 4.0, "weight": "medium",
		"aim": "chest", "height": "high", "range": [3.0, 12.0], "energy": 24.0, "tool": "magic", "linger": 2.0, "title": "Meteor Rain"},
	"polaris_fall": {"who": "mika", "clip": "sky_call_point", "kind": "sky", "size": 1.2, "dmg": 12.0, "weight": "heavy",
		"aim": "chest", "height": "high", "range": [3.0, 12.0], "energy": 22.0, "tool": "magic", "knock": 0.6, "title": "Polaris Fall"},
	"frost_arrow": {"who": "mika", "clip": "bow_draw_release", "kind": "arrow", "n": 5, "size": 1.0, "speed": 24.0, "dmg": 4.0, "weight": "light",
		"aim": "chest", "height": "mid", "range": [4.0, 14.0], "energy": 14.0, "tool": "magic", "title": "Frost Arrow"},
	"blizzard_vortex": {"who": "mika", "clip": "vortex_spin_cast", "kind": "vortex", "size": 1.2, "speed": 6.0, "dmg": 9.0, "weight": "medium",
		"aim": "stomach", "height": "low", "range": [2.5, 9.0], "energy": 14.0, "tool": "magic", "title": "Blizzard Vortex"},
	"snow_domain": {"who": "mika", "clip": "domain_expand", "kind": "domain", "size": 4.5, "dmg": 10.0, "weight": "heavy",
		"aim": "chest", "height": "mid", "range": [0.5, 4.5], "energy": 30.0, "tool": "magic", "launch": true, "linger": 4.0, "title": "Snow Domain"},
	"crystal_wall": {"who": "mika", "clip": "barrier_raise", "kind": "barrier", "dmg": 0.0, "weight": "light", "energy": 6.0, "tool": "magic",
		"title": "Crystal Wall"},
	# ---------------------------------------------------------------------------------------------- Luna (13)
	"moon_crescent": {"who": "luna", "clip": "arm_sweep_wave", "kind": "crescent", "size": 1.2, "speed": 16.0, "dmg": 7.0, "weight": "light",
		"aim": "chest", "height": "mid", "range": [2.2, 10.0], "energy": 8.0, "tool": "magic", "title": "Crescent Moon Blade"},
	"violet_moon": {"who": "luna", "clip": "orb_gather", "kind": "orb", "size": 1.3, "speed": 8.5, "dmg": 10.0, "weight": "heavy",
		"aim": "chest", "height": "mid", "range": [2.5, 9.0], "energy": 16.0, "tool": "magic", "knock": 0.7, "title": "Violet Moon"},
	"thorn_array": {"who": "luna", "clip": "array_ground_summon", "kind": "array", "n": 7, "size": 1.0, "dmg": 9.0, "weight": "heavy",
		"aim": "ankle_r", "height": "low", "range": [2.0, 8.0], "energy": 14.0, "tool": "magic", "launch": true, "linger": 2.0, "title": "Thorn Array"},
	"sigil_beam": {"who": "luna", "clip": "array_air_draw", "kind": "beam", "dur": 0.6, "size": 1.1, "dmg": 12.0, "weight": "heavy",
		"aim": "chest", "height": "mid", "range": [3.0, 11.0], "energy": 22.0, "tool": "magic", "knock": 0.8, "sigil_drawn": true, "title": "Sigil Beam"},
	"violet_scythe": {"who": "luna", "clip": "sword_combo_invisible", "kind": "weapon", "weapon": "violet_scythe", "size": 1.0, "dmg": 6.0,
		"weight": "medium", "aim": "chest", "height": "mid", "range": [1.0, 2.4], "energy": 14.0, "tool": "weapon", "title": "Violet Scythe Dance"},
	"moonlit_pillars": {"who": "luna", "clip": "pillar_raise", "kind": "pillars", "n": 10, "size": 1.2, "dmg": 9.0, "weight": "heavy",
		"aim": "chest", "height": "low", "range": [2.5, 10.0], "energy": 20.0, "tool": "magic", "launch": true, "linger": 3.0, "title": "Moonlit Pillars"},
	"moon_seal": {"who": "luna", "clip": "seal_finish", "kind": "seal", "size": 1.4, "dmg": 10.0, "weight": "heavy",
		"aim": "chest", "height": "mid", "range": [2.5, 10.0], "energy": 20.0, "tool": "magic", "linger": 1.2, "title": "Moon Seal"},
	"eclipse_orb": {"who": "luna", "clip": "meteor_call", "kind": "eclipse", "n": 6, "size": 1.6, "dmg": 4.0, "weight": "medium",
		"aim": "chest", "height": "high", "range": [3.0, 12.0], "energy": 26.0, "tool": "magic", "linger": 4.0, "title": "Eclipse Orb"},
	"moonbeam": {"who": "luna", "clip": "sky_call_point", "kind": "sky", "size": 1.2, "dmg": 12.0, "weight": "heavy",
		"aim": "chest", "height": "high", "range": [3.0, 12.0], "energy": 22.0, "tool": "magic", "knock": 0.6, "title": "Moonbeam"},
	"tide_crescent": {"who": "luna", "clip": "vortex_spin_cast", "kind": "wave", "size": 1.3, "speed": 10.0, "dmg": 8.0, "weight": "medium",
		"aim": "stomach", "height": "low", "range": [2.0, 9.0], "energy": 10.0, "tool": "magic", "title": "Tide Crescent"},
	"moon_greatsword": {"who": "luna", "clip": "iaido_draw_slash", "kind": "weapon", "weapon": "violet_scythe", "size": 2.2, "dmg": 11.0,
		"weight": "heavy", "aim": "chest", "height": "mid", "range": [1.2, 5.5], "energy": 18.0, "tool": "weapon", "wave": true, "greatsword": true,
		"title": "Moon Greatsword"},
	"lunar_domain": {"who": "luna", "clip": "domain_expand", "kind": "domain", "size": 4.5, "dmg": 10.0, "weight": "heavy",
		"aim": "chest", "height": "mid", "range": [0.5, 4.5], "energy": 30.0, "tool": "magic", "launch": true, "linger": 4.0, "title": "Lunar Domain"},
	"mirror_wall": {"who": "luna", "clip": "barrier_raise", "kind": "barrier", "dmg": 0.0, "weight": "light", "energy": 6.0, "tool": "magic",
		"title": "Mirror Wall"},
}


static func spells_of(who: String) -> Array:
	var out := []
	for n in SPELLS:
		if String(SPELLS[n].who) in [who, "both"]:
			out.append(n)
	return out


## Her barrier spell.
static func barrier_of(who: String) -> String:
	return "crystal_wall" if who == "mika" else "mirror_wall"
