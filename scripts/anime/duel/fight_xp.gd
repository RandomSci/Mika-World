class_name FightXP
extends RefCounted
## What a fight earns toward level 100 (2026-10-19). Through the normal verified path: each mage's bout is written
## with WorldState.record_activity, and Progression pays it from data/progression.json - a first duel won / lost /
## first training bout pays once ("first_activity": fight_won: 40, fight_lost: 25, fight_training: 15), later ones a
## decaying repeat (fight_won 12, fight_lost 8, fight_training 5). Skills grow with what she really did: her element
## for blows that landed, "warding" for blocks, "evasion" for dodges. Returns {who: xp gained} for the overlay / QA.

static func award(main: Node, mode: String, r: Dictionary) -> Dictionary:
	var out := {}
	for who in ["mika", "luna"]:
		var other := "luna" if who == "mika" else "mika"
		var kind := "fight_training"
		var outcome_word := "trained"
		if mode == "duel":
			var won: bool = String(r.get("winner", "")) == who
			kind = "fight_won" if won else "fight_lost"
			outcome_word = "won" if won else "lost"
		var m := WorldState.mind(who)
		var xp0 := float(m.progress.xp) + float(m.progress.get("xp_bank", 0.0))
		var hits := int(r.get("hits", {}).get(who, 0))
		var blocks := int(r.get("blocks", {}).get(who, 0))
		var dodges := int(r.get("dodges", {}).get(who, 0))
		var skills := {}
		var elem := "star_magic" if who == "mika" else "moon_magic"
		if hits > 0:
			skills[elem] = 0.04 * hits
		if blocks > 0:
			skills["warding"] = 0.03 * blocks
		if dodges > 0:
			skills["evasion"] = 0.03 * dodges
		var label := "%s with %s (%s, %d hit%s, %d block%s, %d dodge%s)" % ["Duelled" if mode == "duel" else "Sparred", MagicSystem.display_name(other),
			outcome_word, hits, "" if hits == 1 else "s", blocks, "" if blocks == 1 else "s", dodges, "" if dodges == 1 else "s"]
		WorldState.record_activity({"id": "%s:%s" % [kind, other], "verb": "fight", "label": label, "target": other},
			{"knowledge": {("duelled:" if mode == "duel" else "sparred:") + other: 1}, "skills": skills}, who)
		out[who] = snappedf(float(m.progress.xp) + float(m.progress.get("xp_bank", 0.0)) - xp0, 0.1)
	return out
