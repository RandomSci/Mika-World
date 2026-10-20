#!/usr/bin/env python3
"""catalog_body_moves.py <body_moves.json> <action_catalog.json> <scan_mika_log> <scan_luna_log>

2026-10-20, Selwyn: suit mocap (Mixamo, Quaternius UAL) is the fight's body; the Move Library video clips stay for
hand signs, gestures and ultimate poses. Adds (or replaces) one action catalog entry per suit mocap clip with its
category, weapon, tags, timings (contact frames, travel), source and its body scan on both girls; marks the video
clips of fight body categories (strike, weapon, dodge, defence, hit_reaction, footwork) as "fight_body": false.
Status like the rest of the catalog: pass at most 10 percent failing frames and no penetration over 3 cm, else
blocked (with the rules that failed).
"""
import json
import sys

CAT_MAP = {"sword": "weapon", "melee": "strike", "magic": "spell_gesture", "defend": "defence", "dodge": "dodge",
           "hit": "hit_reaction", "knockdown": "hit_reaction", "locomotion": "footwork"}
VIDEO_FIGHT = {"strike", "weapon", "dodge", "defence", "hit_reaction", "footwork"}


def scans(path):
    out = {}
    for line in open(path):
        if "[guardscan] clip " in line:
            r = json.loads(line.split("[guardscan] clip ", 1)[1])
            out[r.get("clip")] = r
    return out


def main():
    moves = json.load(open(sys.argv[1]))
    cat = json.load(open(sys.argv[2]))
    sc = {"mika": scans(sys.argv[3]), "luna": scans(sys.argv[4])}
    keep = [c for c in cat["clips"] if c.get("source_kind") != "suit_mocap"]
    for c in keep:
        if c.get("category") in VIDEO_FIGHT:
            c["fight_body"] = False
            c["note_20261020"] = "video mocap: superseded by suit mocap for the fight's body; kept for gestures and poses"
    n_pass = 0
    for clip, m in moves.items():
        scan = {}
        status = "pass"
        why = []
        for g in ("mika", "luna"):
            r = sc[g].get(clip)
            if not r:
                status = "unscanned"
                continue
            frac = r["failing"] / max(r["frames"], 1)
            pen = r["rules"].get("penetration", {}).get("worst", 0.0)
            scan[g] = {"failing": r["failing"], "frames": r["frames"], "rules": {k: v["n"] for k, v in r["rules"].items()},
                       "penetration_worst_m": pen}
            if frac > 0.10 or pen > 0.03:
                if status != "unscanned":
                    status = "blocked"
                top = sorted(r["rules"].items(), key=lambda kv: -kv[1]["n"])[:2]
                why.append("%s %d of %d frames (%s)" % (g, r["failing"], r["frames"], ", ".join(k for k, _ in top)))
        n_pass += status == "pass"
        keep.append({"id": clip, "deck": clip, "source": m["source"], "source_kind": "suit_mocap", "category": CAT_MAP[m["category"]],
                     "body_category": m["category"], "weapon": m["weapon"] or None, "tags": m["tags"],
                     "contexts": ["fight", "sparring", "monster_fight", "team_fight"], "body": "full", "feet": "root_motion",
                     "mocap": "suit", "fight_body": True, "start_s": 0.0, "end_s": m["len"], "contact_s": m["hits"][0] if m["hits"] else None,
                     "hits_s": m["hits"], "reach_m": m["reach"], "travel_m": m["travel"], "hips_low": m["hips_low"],
                     "timing_from": "suit mocap (weapon hand speed peaks)", "status": status, "why": "; ".join(why), "scan": scan})
    cat["clips"] = keep
    cat["about_suit_mocap"] = ("20 October: %d suit mocap clips (Mixamo great sword pack, Mixamo casts and falls, Quaternius UAL fight set, "
                               "CC0) are the fight's body (BodyMoves, PairedPlay, WeaponDuel); video mocap stays for hand signs, gestures "
                               "and ultimate poses. %d pass the body rules on both girls." % (len(moves), n_pass))
    json.dump(cat, open(sys.argv[2], "w"), indent=1, ensure_ascii=False)
    print("catalog", len(keep), "entries;", len(moves), "suit mocap,", n_pass, "pass")


if __name__ == "__main__":
    main()
