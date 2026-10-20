#!/usr/bin/env python3
"""weapon_catalog.py <catalog.json>: adds (or refreshes) the 28 Move Library v4 weapon clips in the action catalog.

Selwyn 2026-10-20: "add them to the move book and the action catalog with tags (weapon type, attack, defend, movement,
cinematic)". Each entry follows the catalog's fields; behaviour is strike for attacks (their times are then filled
from the mocap by catalog_fill.py: lead hand, speed peak, contact), defence / footwork / cinematic otherwise. The
weapon type is in `weapon` and in `tags`. Status stays unverified until the eye check and the body scans
(catalog_merge.py). Entries already there keep their eye fields.
"""
import json
import sys

# id: (who, weapon, tags beyond the weapon, behaviour, feet, note)
CLIPS = {
	"r_salute_draw": ("mika", "rapier", ["cinematic", "draw"], "cinematic", "planted", "the rapier drawn and raised in a salute"),
	"r_lunge_thrust": ("mika", "rapier", ["attack", "thrust", "movement"], "strike", "lunge", "a long lunge, the point at her chest"),
	"r_triple_thrust": ("mika", "rapier", ["attack", "thrust", "combo"], "strike", "planted_step", "three quick thrusts"),
	"r_backstep_slash": ("mika", "rapier", ["attack", "slash", "movement"], "strike", "step_back", "steps back and cuts as she goes"),
	"r_dash_through": ("mika", "rapier", ["attack", "slash", "movement", "dash"], "strike", "dash", "dashes past her, cutting as she passes"),
	"r_flick_cut": ("mika", "rapier", ["attack", "slash", "fast"], "strike", "planted", "a fast wrist flick cut"),
	"r_parry_riposte": ("mika", "rapier", ["defend", "parry", "attack", "riposte"], "strike", "planted_step", "beats the blade aside, then thrusts"),
	"r_aerial_thrust": ("mika", "rapier", ["attack", "thrust", "aerial", "movement"], "strike_aerial", "jump", "leaps and drives down"),
	"r_throw_recall": ("mika", "rapier", ["attack", "throw", "cinematic"], "strike", "planted", "windup and catch; the flight is an effect (README)"),
	"r_sheathe_finish": ("mika", "rapier", ["cinematic", "finisher", "sheathe"], "cinematic", "planted", "the finishing cut and the sheathe"),
	"g_two_hand_spin": ("luna", "glaive", ["cinematic", "spin", "movement"], "cinematic", "planted", "the glaive spun in both hands"),
	"g_wide_sweep": ("luna", "glaive", ["attack", "sweep", "slash"], "strike", "planted_step", "a wide horizontal sweep"),
	"g_overhead_arc": ("luna", "glaive", ["attack", "slash", "heavy"], "strike", "planted_step", "an overhead arc down"),
	"g_spin_multi_slash": ("luna", "glaive", ["attack", "spin", "combo"], "strike", "planted", "spinning cuts (half a turn in the source: extended procedurally)"),
	"g_shaft_block": ("luna", "glaive", ["defend", "block"], "defence", "slide_back", "the shaft held across, sliding back"),
	"g_pole_vault_kick": ("luna", "glaive", ["attack", "kick", "aerial", "movement"], "strike_aerial", "vault", "vaults on the planted glaive and kicks"),
	"g_overhead_twirl": ("luna", "glaive", ["cinematic", "twirl"], "cinematic", "planted", "twirled overhead"),
	"g_long_thrust": ("luna", "glaive", ["attack", "thrust"], "strike", "lunge", "a long reaching thrust"),
	"g_plant_burst": ("luna", "glaive", ["attack", "area", "plant", "cinematic"], "strike", "planted", "plants the glaive, the ground bursts"),
	"g_finish_pose": ("luna", "glaive", ["cinematic", "finisher"], "cinematic", "planted", "the finishing pose"),
	"s_iaido_draw": ("both", "sword", ["attack", "draw", "slash", "cinematic"], "strike", "planted_step", "the quick-draw cut"),
	"s_blade_clash": ("both", "sword", ["defend", "clash"], "defence", "planted", "blade meets blade"),
	"s_weapon_lock": ("both", "sword", ["defend", "lock", "cinematic"], "defence", "planted", "blades locked, pushing"),
	"s_disarm_catch": ("both", "sword", ["defend", "disarm", "attack"], "strike", "planted_step", "twists the blade away and catches it"),
	"s_summon_weapon": ("both", "sword", ["cinematic", "summon"], "cinematic", "planted", "the weapon called into the hand"),
	"s_sign_blade_raised": ("both", "sword", ["cinematic", "sign", "cast"], "cinematic", "planted", "a sign made with the blade raised"),
	"s_running_slash": ("both", "sword", ["attack", "slash", "movement", "run"], "strike", "run", "running in and cutting (the first second trimmed: she is far away)"),
	"s_kneel_recover": ("both", "sword", ["movement", "recover"], "footwork", "kneel", "up from a kneel on the blade"),
}


def main():
	p = sys.argv[1]
	cat = json.load(open(p))
	clips = cat["clips"]
	by = {c["id"]: c for c in clips}
	for cid, (who, weapon, tags, beh, feet, note) in CLIPS.items():
		e = by.get(cid)
		if e is None:
			e = {"id": cid}
			clips.append(e)
			by[cid] = e
		e.update({
			"source": "Move_Library_v4_weapons", "category": "weapon", "behaviour": beh,
			"contexts": ["fight", "sparring", "monster_fight", "team_fight"] + (["transformation"] if "cinematic" in tags else []),
			"body": "full", "feet": feet, "mocap": "body_hands", "hands": "both" if weapon == "glaive" else "weapon_hand",
			"contact": "opponent_hurtbox" if beh in ("strike", "strike_aerial") else ("weapon" if beh == "defence" else "none"),
			"outfit_risk": "medium" if feet in ("jump", "vault", "kneel") else "low", "prop": weapon, "weapon": weapon,
			"who": who, "tags": [weapon] + tags, "hand_shape": "grip_pose", "loop": None, "speed_range": [0.85, 1.15],
			"blend_in_s": 0.12, "blend_out_s": 0.2, "cooldown_s": 0,
			"personality_weight": {"Mika": 1.4 if who != "luna" else 0.0, "Luna": 1.4 if who != "mika" else 0.0},
			"interrupt": "hit breaks into reaction", "needs_body_guard": True, "weapon_version_needed": False,
			"note": note,
		})
		e.setdefault("status", "unverified")
		e.setdefault("fill_from_frames", ["start_s", "end_s", "release_s", "contact_s"])
	json.dump(cat, open(p, "w"), indent=1)
	print("weapon entries:", len(CLIPS), "catalog size:", len(clips))


if __name__ == "__main__":
	main()
