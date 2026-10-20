#!/usr/bin/env python3
"""body_moves.py <move_measure.json> [out.json]

From move_measure's dump (each combat clip posed on both girls at 30 fps): per clip the weapon hand's speed peaks
(the contact frames of a strike or a combo), the hand's reach forward at each peak (from where her hips started,
the clip's root travel included), the clip's travel, how low her hips go. Prints a table, writes out.json.
Rows: [Hips, Head, LeftHand, RightHand, LeftFoot, RightFoot, Chest, root(x left, 0, z fwd)] in her frame.
"""
import json
import sys

import numpy as np


def analyse(c, girl):
    R = np.array(c["rows"], float)
    n = len(R)
    if n < 4:
        return {}
    root = R[:, 7]
    rh = R[:, 3] + root * [1, 0, 1]
    lh = R[:, 2] + root * [1, 0, 1]
    hand = (rh + lh) * 0.5 if np.linalg.norm(rh - lh, axis=1).mean() < 0.25 else rh   # two hands on one hilt
    v = np.linalg.norm(np.diff(R[:, 3], axis=0), axis=1) * 30.0                         # the hand's own speed
    v = np.convolve(v, np.ones(3) / 3, mode="same")
    peaks = []
    vmax = v.max() if len(v) else 0
    for i in range(1, len(v) - 1):
        if v[i] >= v[i - 1] and v[i] >= v[i + 1] and v[i] > 0.55 * vmax and v[i] > 2.0:
            if not peaks or i - peaks[-1] > 7:
                peaks.append(i)
            elif v[i] > v[peaks[-1]]:
                peaks[-1] = i
    hips0 = R[0, 0]
    leg = girl["leg"]
    hits = [{"t": round((i + 1) / 30.0, 3), "speed": round(float(v[i]), 2),
             "reach": round(float(hand[i + 1, 2] - hips0[2]), 3), "height": round(float(hand[i + 1, 1] - R[0, 4:6, 1].min()), 3)} for i in peaks]
    return {"len": round(c["len"], 3), "hits": hits, "travel": round(float(root[-1, 2]), 3), "travel_left": round(float(root[-1, 0]), 3),
            "hips_low": round(float((R[:, 0, 1] - R[:, 4:6, 1].min(1)).min() / leg), 3), "two_hand": bool(hand is not rh),
            "hand_max_speed": round(float(vmax), 2)}


def main():
    d = json.load(open(sys.argv[1]))
    out = {}
    for girl in d:
        for clip, c in d[girl]["clips"].items():
            if c.get("missing"):
                continue
            out.setdefault(clip, {})[girl] = analyse(c, d[girl])
    for clip, g in out.items():
        m = g.get("mika", {})
        print("%-40s len %5.2f travel %5.2f low %.2f hits %s" % (clip, m.get("len", 0), m.get("travel", 0), m.get("hips_low", 0),
              " ".join("%.2f(r%.2f h%.2f)" % (h["t"], h["reach"], h["height"]) for h in m.get("hits", []))))
    if len(sys.argv) > 2:
        json.dump(out, open(sys.argv[2], "w"), indent=1)


if __name__ == "__main__":
    main()


# ------------------------------------------------------------------ the catalog (2026-10-20, suit mocap as the fight's body)
CAT = {
    # one-handed sword (UAL, CC0): Mika's rapier
    "ualf:Sword_Attack": ("sword", "rapier", ["attack", "thrust", "lunge", "movement"]),
    "ualf:Sword_Regular_A": ("sword", "rapier", ["attack", "slash", "light", "combo_start"]),
    "ualf:Sword_Regular_A_Rec": ("sword", "rapier", ["attack", "recover"]),
    "ualf:Sword_Regular_B": ("sword", "rapier", ["attack", "slash", "light", "parry"]),
    "ualf:Sword_Regular_B_Rec": ("sword", "rapier", ["attack", "recover"]),
    "ualf:Sword_Regular_C": ("sword", "rapier", ["attack", "slash", "heavy", "movement"]),
    "ualf:Sword_Regular_Combo": ("sword", "rapier", ["attack", "combo", "movement"]),
    "ualf:Sword_Heavy_Combo": ("sword", "rapier", ["attack", "combo", "heavy", "movement", "cinematic"]),
    "ualf:Sword_Dash": ("sword", "rapier", ["attack", "dash", "movement", "cinematic"]),
    "ualf:Sword_Idle": ("sword", "rapier", ["stance", "loop"]),
    # two-handed great sword (Mixamo): Luna's glaive
    "sword:great_sword_attack": ("sword", "glaive", ["attack", "slash", "light"]),
    "sword:great_sword_slash": ("sword", "glaive", ["attack", "slash"]),
    "sword:great_sword_slash_2": ("sword", "glaive", ["attack", "combo", "movement"]),
    "sword:great_sword_slash_3": ("sword", "glaive", ["attack", "combo", "heavy"]),
    "sword:great_sword_slash_4": ("sword", "glaive", ["attack", "slash", "movement"]),
    "sword:great_sword_slash_5": ("sword", "glaive", ["attack", "combo", "low"]),
    "sword:great_sword_high_spin_attack": ("sword", "glaive", ["attack", "spin", "movement", "cinematic"]),
    "sword:great_sword_jump_attack": ("sword", "glaive", ["attack", "aerial", "movement", "cinematic"]),
    "sword:great_sword_slide_attack": ("sword", "glaive", ["attack", "slide", "low", "movement"]),
    "sword:standalone_great_sword_slash": ("sword", "glaive", ["attack", "combo", "movement"]),
    "sword:draw_a_great_sword_1": ("sword", "glaive", ["draw"]),
    "sword:draw_a_great_sword_2": ("sword", "glaive", ["draw"]),
    "sword:great_sword_power_up": ("sword", "glaive", ["charge", "cinematic"]),
    "sword:great_sword_idle": ("sword", "glaive", ["stance", "loop"]),
    "sword:great_sword_idle_2": ("sword", "glaive", ["stance", "loop"]),
    "sword:great_sword_idle_3": ("sword", "glaive", ["stance", "loop"]),
    "sword:great_sword_idle_4": ("sword", "glaive", ["stance", "loop"]),
    "sword:great_sword_idle_5": ("sword", "glaive", ["stance", "loop"]),
    "sword:standalone_great_sword_idle": ("sword", "glaive", ["stance", "loop"]),
    # melee without the blade
    "ualf:Melee_Hook": ("melee", "", ["attack", "punch"]),
    "ualf:Melee_Hook_Rec": ("melee", "", ["recover"]),
    "ualf:Punch_Jab": ("melee", "", ["attack", "punch", "light"]),
    "ualf:Punch_Cross": ("melee", "", ["attack", "punch"]),
    "ualf:Shield_Dash": ("melee", "", ["attack", "charge", "movement"]),
    "sword:great_sword_kick": ("melee", "glaive", ["attack", "kick", "disabled"]),
    "sword:great_sword_kick_2": ("melee", "glaive", ["attack", "kick", "disabled"]),
    # magic
    "mixamo:standing_1h_magic_attack_03": ("magic", "", ["cast", "one_hand"]),
    "mixamo:standing_2h_magic_attack_01": ("magic", "", ["cast", "two_hand"]),
    "mixamo:wide_arm_spell_casting": ("magic", "", ["cast", "channel"]),
    "mixamo:prepare_and_cast": ("magic", "", ["cast", "gather"]),
    "mixamo:spell_casting": ("magic", "", ["cast", "channel"]),
    "ualf:Spell_Simple_Enter": ("magic", "", ["cast", "gather"]),
    "ualf:Spell_Simple_Shoot": ("magic", "", ["cast", "release"]),
    "ualf:Spell_Simple_Exit": ("magic", "", ["cast", "recover"]),
    "ualf:Spell_Simple_Idle": ("magic", "", ["cast", "loop"]),
    "ualf:OverhandThrow": ("magic", "", ["cast", "throw"]),
    "sword:great_sword_casting": ("magic", "glaive", ["cast", "weapon"]),
    "sword:spell_cast": ("magic", "glaive", ["cast", "weapon"]),
    # defend
    "ualf:Sword_Block": ("defend", "rapier", ["defend", "block"]),
    "sword:great_sword_blocking": ("defend", "glaive", ["defend", "block"]),
    "sword:great_sword_blocking_2": ("defend", "glaive", ["defend", "block"]),
    "sword:great_sword_blocking_3": ("defend", "glaive", ["defend", "block"]),
    # dodge
    "ualf:Roll": ("dodge", "", ["dodge", "roll", "movement"]),
    "ualf:NinjaJump_Start": ("dodge", "", ["dodge", "jump"]),
    "ualf:NinjaJump_Idle": ("dodge", "", ["dodge", "jump", "loop"]),
    "ualf:NinjaJump_Land": ("dodge", "", ["dodge", "land"]),
    "ualf:Slide_Start": ("dodge", "", ["dodge", "slide", "movement"]),
    "ualf:Slide": ("dodge", "", ["dodge", "slide", "loop"]),
    "ualf:Slide_Exit": ("dodge", "", ["dodge", "slide"]),
    "ualf:Jump_Start": ("dodge", "", ["dodge", "jump"]),
    "ualf:Jump_Land": ("dodge", "", ["dodge", "land"]),
    "sword:great_sword_jump": ("dodge", "glaive", ["dodge", "jump", "movement"]),
    "sword:great_sword_jump_2": ("dodge", "glaive", ["dodge", "jump"]),
    "sword:great_sword_crouching": ("dodge", "glaive", ["dodge", "duck"]),
    "sword:great_sword_crouching_2": ("dodge", "glaive", ["dodge", "duck"]),
    "sword:great_sword_crouching_3": ("dodge", "glaive", ["dodge", "duck", "loop"]),
    "sword:great_sword_crouching_4": ("dodge", "glaive", ["dodge", "duck"]),
    "sword:great_sword_crouching_5": ("dodge", "glaive", ["dodge", "duck"]),
    "sword:great_sword_crouching_6": ("dodge", "glaive", ["dodge", "duck"]),
    "sword:great_sword_strafe": ("dodge", "glaive", ["sidestep", "movement", "loop"]),
    "sword:great_sword_strafe_2": ("dodge", "glaive", ["sidestep", "movement", "loop"]),
    "sword:great_sword_strafe_3": ("dodge", "glaive", ["sidestep", "movement", "loop"]),
    "sword:great_sword_strafe_4": ("dodge", "glaive", ["sidestep", "movement", "loop"]),
    # hit reactions
    "ualf:Hit_Chest": ("hit", "", ["hit", "chest", "light"]),
    "ualf:Hit_Head": ("hit", "", ["hit", "head", "light"]),
    "ualf:Idle_Shield_Break": ("hit", "", ["hit", "stagger", "guard_break"]),
    "sword:great_sword_impact": ("hit", "glaive", ["hit", "light"]),
    "sword:great_sword_impact_2": ("hit", "glaive", ["hit"]),
    "sword:great_sword_impact_3": ("hit", "glaive", ["hit", "heavy"]),
    "sword:great_sword_impact_4": ("hit", "glaive", ["hit", "low"]),
    "sword:great_sword_impact_5": ("hit", "glaive", ["hit", "low", "heavy"]),
    # knockdowns
    "ualf:Hit_Knockback": ("knockdown", "", ["knockdown", "fall", "movement"]),
    "ualf:LayToIdle": ("knockdown", "", ["get_up"]),
    "ualf:Death01": ("knockdown", "", ["knockdown", "finish"]),
    "mixamo:standing_react_death_forward": ("knockdown", "", ["knockdown", "finish"]),
    "sword:two_handed_sword_death": ("knockdown", "glaive", ["knockdown", "finish"]),
    "sword:two_handed_sword_death_2": ("knockdown", "glaive", ["knockdown", "finish"]),
    # locomotion
    "ualf:Walk": ("locomotion", "", ["walk", "loop"]), "ualf:Jog_Fwd": ("locomotion", "", ["run", "loop"]),
    "ualf:Sprint": ("locomotion", "", ["sprint", "loop"]), "ualf:Crouch_Fwd": ("locomotion", "", ["crouch", "loop"]),
    "ualf:Crouch_Idle": ("locomotion", "", ["crouch", "loop"]), "ualf:Idle": ("locomotion", "", ["idle", "loop"]),
    "sword:great_sword_walk": ("locomotion", "glaive", ["walk", "loop"]), "sword:great_sword_walk_2": ("locomotion", "glaive", ["walk", "back", "loop"]),
    "sword:great_sword_run": ("locomotion", "glaive", ["run", "back", "loop"]), "sword:great_sword_run_2": ("locomotion", "glaive", ["run", "loop"]),
    "sword:great_sword_turn": ("locomotion", "glaive", ["turn"]), "sword:great_sword_turn_2": ("locomotion", "glaive", ["turn"]),
    "sword:great_sword_180_turn": ("locomotion", "glaive", ["turn"]), "sword:great_sword_180_turn_2": ("locomotion", "glaive", ["turn"]),
    "sword:standalone_great_sword_180_turn": ("locomotion", "glaive", ["turn"]),
}
SRC = {"ualf": "Quaternius UAL (CC0)", "sword": "Mixamo great sword pack", "mixamo": "Mixamo"}


def catalog(moves):
    out = {}
    for clip, (cat, weapon, tags) in CAT.items():
        g = moves.get(clip, {})
        m = g.get("mika", {})
        out[clip] = {"clip": clip, "source": SRC[clip.split(":")[0]], "category": cat, "weapon": weapon, "tags": tags,
                     "len": m.get("len", 0.0), "hits": [h["t"] for h in m.get("hits", [])] if "attack" in tags else [],
                     "reach": [h["reach"] for h in m.get("hits", [])] if "attack" in tags else [],
                     "travel": m.get("travel", 0.0), "hips_low": m.get("hips_low", 0.0), "measured": bool(m)}
    return out


if __name__ == "__main__" and len(sys.argv) > 3:
    json.dump(catalog(json.load(open(sys.argv[2]))), open(sys.argv[3], "w"), indent=1)
