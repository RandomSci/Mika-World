class_name Affect
extends Node
## What each mage FEELS right now, from observable state and events only (Milestone K). Drives FaceController:
##   baseline (every 0.5 s) — from her own mind and what she is doing:
##     low vigor / energy -> tired; studying / reading / journalling -> concentrating or thoughtful;
##     fighting -> determined (concerned when hurt); resting at ease -> relaxed; exploring -> a little curious;
##     a conversation she is part of -> listening when the other speaks
##   events (short pulses, her own style — data/mages.json "reactions"):
##     discovery, clue, first sight of something, spell hit / miss, struck, victory (relief when spent, joy when
##     fresh), level up, fusion, a laugh in a line
## Stable personality lives in data/mages.json "face" (expressiveness, biases, blink rate); moods are transient
## and are never written to her save.

var main: Node
var _acc := 0.0
var log: Array = []


func setup(m: Node) -> void:
	main = m
	WorldState.mage_event.connect(_on_mage_event)
	if main.spawner:
		main.spawner.mage_hit.connect(func(mage, _m, amount): react(mage.character_id, "struck", clampf(0.6 + float(amount) * 3.0, 0.6, 1.0)))
		main.spawner.monster_defeated.connect(func(_m, by): if by != "": react(by, "victory"))
	if main.progression:
		main.progression.leveled.connect(func(w, _l): react(w, "level_up"))
	if main.magic:
		main.magic.cast_resolved.connect(_on_cast)
		if main.magic.fusion:
			main.magic.fusion.fused.connect(func(f): for w in f.mages: react(w, "fusion"))
	if main.voice:
		main.voice.line_started.connect(_on_line_started)
		main.voice.line_finished.connect(_on_line_finished)


func _face(who: String) -> FaceController:
	var c = main.characters.get(who)
	return c.face if c and c.visible and c.face else null


## An observed event -> a short expression in her own style. Returns the emotion used ("" if none).
func react(who: String, event: String, scale := 1.0) -> String:
	var f := _face(who)
	if f == null:
		return ""
	var r: Array = _reaction(who, event)
	if r.is_empty():
		return ""
	f.pulse(String(r[0]), float(r[1]) * scale, float(r[2]))
	if r.size() > 3 and main.characters[who].head_posture and String(r[3]) == "nod":
		main.characters[who].head_posture.nod(0.1)
	log.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "who": who, "event": event, "emotion": r[0]})
	if log.size() > 80:
		log.pop_front()
	return String(r[0])


func _reaction(who: String, event: String) -> Array:
	var table: Dictionary = Progression.mages.get(who, {}).get("reactions", {})
	var e: Array = table.get(event, [])
	if event == "victory":
		# spent -> relief; fresh -> joy (her own word for it from the table)
		var vigor := WorldState.mind(who).vigor
		if vigor < 0.45:
			return table.get("victory_spent", ["relieved", 0.8, 2.5])
	return e


func _on_mage_event(who: String, kind: String, data) -> void:
	if kind == "trial":
		react(who, "discovery")
	elif kind == "activity":
		var ch: Dictionary = data.get("changes", {})
		for k in ch:
			var ks := String(k)
			if ks.begins_with("knowledge.clue:") or ks.begins_with("knowledge.region_sign:"):
				react(who, "clue")
				return
			if ks.begins_with("knowledge.bestiary:") and ch[k][0] == 0:
				react(who, "first_sight")
				return
			if ks.begins_with("knowledge.reaction:") and ch[k][0] == 0:
				react(who, "discovery")
				return


func _on_cast(res: Dictionary) -> void:
	var who := String(res.get("caster", ""))
	if who == "" or res.get("outcome", "") == "refused":
		return
	if res.get("outcome", "") == "hit":
		react(who, "spell_hit")
	elif res.get("outcome", "") in ["missed", "blocked"]:
		react(who, "spell_miss")


func _on_line_started(speaker: String, text: String) -> void:
	# the speaker's face follows her own words; the other mage, if close, listens
	var f := _face(speaker)
	if f:
		f.set_hold(_line_emotion(speaker, text), 0.55)
	for who in main.characters:
		if who == speaker:
			continue
		var lc = main.characters[who]
		var sc = main.characters.get(speaker)
		if lc.visible and sc and sc.visible and lc.global_position.distance_to(sc.global_position) < 6.0 and lc.face:
			lc.face.set_hold("listening", 0.8)
			lc.look_head_at(sc.global_position + Vector3(0, 1.45, 0))


func _on_line_finished(speaker: String, _res: Dictionary) -> void:
	var f := _face(speaker)
	if f:
		f.set_hold("", 0.0)
	for who in main.characters:
		if who != speaker and main.characters[who].face:
			var lf: FaceController = main.characters[who].face
			if lf.hold.has("listening"):
				lf.set_hold("", 0.0)
				if main.characters[who].head_posture:
					main.characters[who].head_posture.nod(0.07)


## The emotion a line carries, from its words (punctuation and a few cue words; no model call).
static func _line_emotion(_speaker: String, text: String) -> String:
	var t := text.to_lower()
	if t.ends_with("?") or t.begins_with("what") or t.begins_with("why") or t.contains("wonder"):
		return "curious"
	if t.contains("careful") or t.contains("hurt") or t.contains("too much") or t.contains("are you ok") or t.contains("step back"):
		return "concerned"
	if t.ends_with("!") and (t.contains("did it") or t.contains("got it") or t.contains("look") or t.contains("amazing") or t.contains("beautiful")):
		return "excited"
	if t.contains("hmm") or t.contains("maybe") or t.contains("perhaps") or t.contains("i think"):
		return "thoughtful"
	if t.contains("thank") or t.contains("glad") or t.contains("good") or t.contains("nice"):
		return "happy"
	return "neutral"


func _process(delta: float) -> void:
	_acc -= delta
	if _acc > 0.0 or main == null:
		return
	_acc = 0.5
	for who in main.characters:
		var c = main.characters[who]
		if not c.visible or c.face == null:
			continue
		c.face.set_baseline(_baseline(who, c))


func _baseline(who: String, c) -> Dictionary:
	var mind := WorldState.mind(who)
	var b = main.mage_brains.get(who)
	var kind := String(b.current.get("kind", "")) if b and not b.current.is_empty() else ""
	var out := {}
	var energy: float = float(b.needs.get("energy", 1.0)) if b else 1.0
	var tired := clampf((0.45 - mind.vigor) * 1.6, 0.0, 0.7) + clampf((0.3 - energy) * 1.5, 0.0, 0.5)
	if tired > 0.05:
		out["tired"] = tired
	match kind:
		"research", "magic", "alchemy", "attune":
			out["concentrating"] = 0.45
		"journal", "investigate":
			out["thoughtful"] = 0.4
		"hunt":
			out["determined"] = 0.5 if mind.vigor > 0.4 else 0.2
			if mind.vigor < 0.4:
				out["concerned"] = 0.4
		"rest":
			out["relaxed"] = 0.35
		"explore", "roam", "gather":
			out["curious"] = 0.18
	if c.casting:
		out["concentrating"] = maxf(float(out.get("concentrating", 0.0)), 0.55)
	return out
