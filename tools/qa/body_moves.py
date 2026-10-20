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
    # two-handed great sword (Mixamo): Luna's longsword
    "sword:great_sword_attack": ("sword", "longsword", ["attack", "slash", "light"]),
    "sword:great_sword_slash": ("sword", "longsword", ["attack", "slash"]),
    "sword:great_sword_slash_2": ("sword", "longsword", ["attack", "combo", "movement"]),
    "sword:great_sword_slash_3": ("sword", "longsword", ["attack", "combo", "heavy"]),
    "sword:great_sword_slash_4": ("sword", "longsword", ["attack", "slash", "movement"]),
    "sword:great_sword_slash_5": ("sword", "longsword", ["attack", "combo", "low"]),
    "sword:great_sword_high_spin_attack": ("sword", "longsword", ["attack", "spin", "movement", "cinematic"]),
    "sword:great_sword_jump_attack": ("sword", "longsword", ["attack", "aerial", "movement", "cinematic"]),
    "sword:great_sword_slide_attack": ("sword", "longsword", ["attack", "slide", "low", "movement"]),
    "sword:standalone_great_sword_slash": ("sword", "longsword", ["attack", "combo", "movement"]),
    "sword:draw_a_great_sword_1": ("sword", "longsword", ["draw"]),
    "sword:draw_a_great_sword_2": ("sword", "longsword", ["draw"]),
    "sword:great_sword_power_up": ("sword", "longsword", ["charge", "cinematic"]),
    "sword:great_sword_idle": ("sword", "longsword", ["stance", "loop"]),
    "sword:great_sword_idle_2": ("sword", "longsword", ["stance", "loop"]),
    "sword:great_sword_idle_3": ("sword", "longsword", ["stance", "loop"]),
    "sword:great_sword_idle_4": ("sword", "longsword", ["stance", "loop"]),
    "sword:great_sword_idle_5": ("sword", "longsword", ["stance", "loop"]),
    "sword:standalone_great_sword_idle": ("sword", "longsword", ["stance", "loop"]),
    # melee without the blade
    "ualf:Melee_Hook": ("melee", "", ["attack", "punch"]),
    "ualf:Melee_Hook_Rec": ("melee", "", ["recover"]),
    "ualf:Punch_Jab": ("melee", "", ["attack", "punch", "light"]),
    "ualf:Punch_Cross": ("melee", "", ["attack", "punch"]),
    "ualf:Shield_Dash": ("melee", "", ["attack", "charge", "movement"]),
    "sword:great_sword_kick": ("melee", "longsword", ["attack", "kick", "disabled"]),
    "sword:great_sword_kick_2": ("melee", "longsword", ["attack", "kick", "disabled"]),
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
    "sword:great_sword_casting": ("magic", "longsword", ["cast", "weapon"]),
    "sword:spell_cast": ("magic", "longsword", ["cast", "weapon"]),
    # defend
    "ualf:Sword_Block": ("defend", "rapier", ["defend", "block"]),
    "sword:great_sword_blocking": ("defend", "longsword", ["defend", "block"]),
    "sword:great_sword_blocking_2": ("defend", "longsword", ["defend", "block"]),
    "sword:great_sword_blocking_3": ("defend", "longsword", ["defend", "block"]),
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
    "sword:great_sword_jump": ("dodge", "longsword", ["dodge", "jump", "movement"]),
    "sword:great_sword_jump_2": ("dodge", "longsword", ["dodge", "jump"]),
    "sword:great_sword_crouching": ("dodge", "longsword", ["dodge", "duck"]),
    "sword:great_sword_crouching_2": ("dodge", "longsword", ["dodge", "duck"]),
    "sword:great_sword_crouching_3": ("dodge", "longsword", ["dodge", "duck", "loop"]),
    "sword:great_sword_crouching_4": ("dodge", "longsword", ["dodge", "duck"]),
    "sword:great_sword_crouching_5": ("dodge", "longsword", ["dodge", "duck"]),
    "sword:great_sword_crouching_6": ("dodge", "longsword", ["dodge", "duck"]),
    "sword:great_sword_strafe": ("dodge", "longsword", ["sidestep", "movement", "loop"]),
    "sword:great_sword_strafe_2": ("dodge", "longsword", ["sidestep", "movement", "loop"]),
    "sword:great_sword_strafe_3": ("dodge", "longsword", ["sidestep", "movement", "loop"]),
    "sword:great_sword_strafe_4": ("dodge", "longsword", ["sidestep", "movement", "loop"]),
    # hit reactions
    "ualf:Hit_Chest": ("hit", "", ["hit", "chest", "light"]),
    "ualf:Hit_Head": ("hit", "", ["hit", "head", "light"]),
    "ualf:Idle_Shield_Break": ("hit", "", ["hit", "stagger", "guard_break"]),
    "sword:great_sword_impact": ("hit", "longsword", ["hit", "light"]),
    "sword:great_sword_impact_2": ("hit", "longsword", ["hit"]),
    "sword:great_sword_impact_3": ("hit", "longsword", ["hit", "heavy"]),
    "sword:great_sword_impact_4": ("hit", "longsword", ["hit", "low"]),
    "sword:great_sword_impact_5": ("hit", "longsword", ["hit", "low", "heavy"]),
    # knockdowns
    "ualf:Hit_Knockback": ("knockdown", "", ["knockdown", "fall", "movement"]),
    "ualf:LayToIdle": ("knockdown", "", ["get_up"]),
    "ualf:Death01": ("knockdown", "", ["knockdown", "finish"]),
    "mixamo:standing_react_death_forward": ("knockdown", "", ["knockdown", "finish"]),
    "sword:two_handed_sword_death": ("knockdown", "longsword", ["knockdown", "finish"]),
    "sword:two_handed_sword_death_2": ("knockdown", "longsword", ["knockdown", "finish"]),
    # locomotion
    "ualf:Walk": ("locomotion", "", ["walk", "loop"]), "ualf:Jog_Fwd": ("locomotion", "", ["run", "loop"]),
    "ualf:Sprint": ("locomotion", "", ["sprint", "loop"]), "ualf:Crouch_Fwd": ("locomotion", "", ["crouch", "loop"]),
    "ualf:Crouch_Idle": ("locomotion", "", ["crouch", "loop"]), "ualf:Idle": ("locomotion", "", ["idle", "loop"]),
    "sword:great_sword_walk": ("locomotion", "longsword", ["walk", "loop"]), "sword:great_sword_walk_2": ("locomotion", "longsword", ["walk", "back", "loop"]),
    "sword:great_sword_run": ("locomotion", "longsword", ["run", "back", "loop"]), "sword:great_sword_run_2": ("locomotion", "longsword", ["run", "loop"]),
    "sword:great_sword_turn": ("locomotion", "longsword", ["turn"]), "sword:great_sword_turn_2": ("locomotion", "longsword", ["turn"]),
    "sword:great_sword_180_turn": ("locomotion", "longsword", ["turn"]), "sword:great_sword_180_turn_2": ("locomotion", "longsword", ["turn"]),
    "sword:standalone_great_sword_180_turn": ("locomotion", "longsword", ["turn"]),
}
# (2026-10-20 evening: the missing moves filled from what exists) side dodges, backsteps, Mika's one-handed steps
# ("<upper>|<lower>": her UAL one-handed guard over the great sword set's legs), the lunge from the lifted video mocap
MIKA_UP = "ualf:Sword_Idle|"
CAT.update({
    "sword:great_sword_jump@rev": ("dodge", "longsword", ["dodge", "backstep", "movement"]),
    "sword:great_sword_crouching_2@mirror": ("dodge", "longsword", ["dodge", "duck", "side"]),
    MIKA_UP + "sword:great_sword_strafe": ("dodge", "rapier", ["sidestep", "movement", "loop"]),
    MIKA_UP + "sword:great_sword_strafe_2": ("dodge", "rapier", ["sidestep", "movement", "loop"]),
    MIKA_UP + "sword:great_sword_strafe_3": ("dodge", "rapier", ["dodge", "side", "movement"]),
    MIKA_UP + "sword:great_sword_strafe_4": ("dodge", "rapier", ["dodge", "side", "movement"]),
    MIKA_UP + "sword:great_sword_jump@rev": ("dodge", "rapier", ["dodge", "backstep", "movement"]),
    MIKA_UP + "sword:great_sword_crouching_4": ("dodge", "rapier", ["dodge", "duck"]),
    MIKA_UP + "sword:great_sword_jump_2": ("dodge", "rapier", ["dodge", "jump"]),
    "ml_r_lunge_thrust": ("sword", "rapier", ["attack", "thrust", "lunge", "movement", "lift_depth"]),
})
SRC = {"ualf": "Quaternius UAL (CC0)", "sword": "Mixamo great sword pack", "mixamo": "Mixamo", "ml_r": "Move Library v4 video, depth lifted"}
FIXED = {"ml_r_lunge_thrust": {"len": 3.97, "hits": [{"t": 1.75, "reach": 1.1}], "travel": 1.1, "hips_low": 0.0}}


def base_of(clip):
    lo = clip.split("|")[-1]
    return lo.split("@")[0], ("@" + lo.split("@")[1]) if "@" in lo else ""


def catalog(moves):
    out = {}
    for clip, (cat, weapon, tags) in CAT.items():
        b, var = base_of(clip)
        m = dict(FIXED.get(clip) or moves.get(b, {}).get("mika", {}))
        if var == "@rev" and m:
            m["travel"] = -m.get("travel", 0.0)
            m["hits"] = []
        if var == "@mirror" and m:
            m["hits"] = m.get("hits", [])
        out[clip] = {"clip": clip, "source": SRC[clip.split("|")[-1].split(":")[0][:4] if clip.startswith("ml_r") else clip.split("|")[-1].split(":")[0]], "category": cat, "weapon": weapon, "tags": tags,
                     "len": m.get("len", 0.0), "hits": [h["t"] for h in m.get("hits", [])] if "attack" in tags else [],
                     "reach": [h["reach"] for h in m.get("hits", [])] if "attack" in tags else [],
                     "travel": m.get("travel", 0.0), "hips_low": m.get("hips_low", 0.0), "measured": bool(m)}
    return out


if __name__ == "__main__" and len(sys.argv) > 3:
    json.dump(catalog(json.load(open(sys.argv[2]))), open(sys.argv[3], "w"), indent=1)
