class_name Companionship
extends Node
## Mika and Luna as close companions with separate minds (Milestone K).
##   * conversations with real turn-taking, built from each speaker's OWN memory (clues she found, creatures she
##     fought, books she read, places she looked at, things they did together): both of them bring topics; the
##     listener reacts from HER memory (knew it / new to her) and remembers only that she was TOLD
##     ("told:<speaker>:<topic>" = what was said) — knowledge is never copied between minds
##   * invitations: either mage may propose a shared activity; the other decides from her own state (vigor, energy,
##     what she is doing, temperament, how close they are) and says why when she declines
##   * doing things together: the follower walks beside / slightly behind the leader at a matched pace (no
##     teleporting), the leader waits when the follower falls behind, they arrive, look, talk about what each sees,
##     and each records her own experience ("together:<n>" in each mind with her own wording)
## Rule-driven; an optional language model may rephrase lines on camera (MageTalk._phrase, one call).

signal joint_finished(entry: Dictionary)

const BOND_GAIN := 0.06

var main: Node
var cfg := {}
var log: Array = []
var active := {}
var force_accept := false          # tests: skip the invitation's mood roll                    # the joint activity in progress {kind, leader, follower, t0, stage}
var _rng := RandomNumberGenerator.new()


func setup(m: Node) -> void:
	main = m
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/companionship.json"))
	_rng.seed = 20261014


func busy() -> bool:
	return not active.is_empty()


func line(who: String, key: String, fill := {}) -> String:
	var arr: Array = cfg.get("lines", {}).get(who, {}).get(key, [])
	if arr.is_empty():
		return ""
	var s := String(arr[_rng.randi() % arr.size()])
	for k in fill:
		s = s.replace("{%s}" % k, String(fill[k]))
	return s


# ------------------------------------------------------------------ memory -> topics (her own mind only)
static func _clue_hint(key: String) -> String:
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	for id in story.get("clues", {}):
		var c: Dictionary = story.clues[id]
		if (c.get("any_knowledge", []) as Array).has(key):
			return String(c.get("hint", ""))
	return ""


static func _clue_title(key: String) -> String:
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	for id in story.get("clues", {}):
		var c: Dictionary = story.clues[id]
		if (c.get("any_knowledge", []) as Array).has(key):
			return String(c.get("title", "")).to_lower()
	return key.get_slice(":", 1).replace("_", " ")


## Things SHE could bring up, most recent / most interesting first: [{kind, topic, fill, w}].
static func topics(who: String, other: String) -> Array:
	var m := WorldState.mind(who)
	var om := WorldState.mind(other)
	var out := []
	var told_other := func(topic: String) -> bool: return om.knowledge.has("told:%s:%s" % [who, topic])
	# what she did, newest first (from her own activity log)
	var logv: Array = m.activity_log
	var seen := {}
	for i in range(logv.size() - 1, maxi(-1, logv.size() - 60), -1):
		var e: Dictionary = logv[i]
		var id := String(e.get("activity", {}).get("id", ""))
		var recency := 1.0 - float(logv.size() - 1 - i) / 60.0
		for k in e.get("changes", {}):
			var ks := String(k).trim_prefix("knowledge.")
			if ks.begins_with("clue:") and not seen.has(ks) and not told_other.call(ks):
				seen[ks] = true
				var hint := _clue_hint(ks)
				if hint != "":
					out.append({"kind": "clue", "topic": ks, "fill": {"hint": hint, "topic": _clue_title(ks)}, "w": 1.2 + recency})
		if id.begins_with("defeat:") and not seen.has(id):
			seen[id] = true
			var kind := id.trim_prefix("defeat:")
			var nm := String(Spawner.load_data().monsters.get(kind, {}).get("name", kind)).to_lower()
			if not told_other.call("monster:" + kind):
				out.append({"kind": "creature", "topic": "monster:" + kind, "fill": {"creature": nm}, "creature": kind, "w": 1.0 + recency})
		if id.begins_with("read:") and id.get_slice(":", 2) == "" and not seen.has(id):
			pass
		if (id.begins_with("read:") or id.begins_with("book:")) and not seen.has("book:" + id.get_slice(":", 1)):
			var bid := id.get_slice(":", 1)
			seen["book:" + bid] = true
			var books: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/books.json")).get("books", {})
			if books.has(bid) and not told_other.call("book:" + bid):
				out.append({"kind": "book", "topic": "book:" + bid, "fill": {"book": String(books[bid].get("title", bid))}, "w": 0.6 + recency * 0.5})
		if id.begins_with("roam:") and not seen.has("place"):
			seen["place"] = true
			var lbl := String(e.get("activity", {}).get("label", "")).trim_prefix("Looked at ")
			if lbl != "" and not told_other.call("place:" + id):
				out.append({"kind": "place", "topic": "place:" + id, "fill": {"place": lbl}, "w": 0.7 + recency * 0.5})
	# asking: she heard the other did something but was never told about it
	for k in m.knowledge:
		var ks := String(k)
		if ks.begins_with("heard:%s:" % other):
			var topic := ks.trim_prefix("heard:%s:" % other)
			if not m.knowledge.has("told:%s:%s" % [other, topic]):
				var fill := {}
				if topic.begins_with("monster:"):
					fill["creature"] = String(Spawner.load_data().monsters.get(topic.trim_prefix("monster:"), {}).get("name", topic)).to_lower()
					out.append({"kind": "ask_creature", "topic": topic, "fill": fill, "creature": topic.trim_prefix("monster:"), "w": 1.1})
				elif topic.begins_with("clue:"):
					out.append({"kind": "ask_clue", "topic": topic, "fill": {"topic": _clue_title(topic)}, "w": 1.0})
	# unfinished business and a fight finally won (V3 Part 5: what happened shapes what she talks about)
	for k in m.knowledge:
		var kk := String(k)
		if (kk.begins_with("unfinished:") or kk.begins_with("overcame:")) and m.knowledge[k] is Dictionary and not told_other.call(kk):
			var ent: Dictionary = m.knowledge[k]
			var nm2 := String(ent.get("name", kk.get_slice(":", 1))).to_lower()
			if kk.begins_with("unfinished:"):
				out.append({"kind": "worry", "topic": kk, "fill": {"creature": nm2}, "w": 1.35})
			else:
				out.append({"kind": "triumph", "topic": kk, "fill": {"creature": nm2}, "w": 1.3})
	# shared memories (each recalls her OWN record of it)
	for k in m.knowledge:
		var ks2 := String(k)
		if ks2.begins_with("together:") and m.knowledge[k] is Dictionary and om.knowledge.has(ks2):
			out.append({"kind": "reminisce", "topic": ks2, "fill": {"memory": String(m.knowledge[k].get("memory", "went out together"))}, "w": 0.5})
	out.sort_custom(func(a, b): return float(a.w) > float(b.w))
	return out


# ------------------------------------------------------------------ conversation composition
## A conversation between a (who started it) and b: 4-9 lines, both bring topics, real reactions.
func compose(a: String, b: String, first_meeting := false) -> Array:
	var out := []
	if first_meeting:
		return out                   # MageTalk keeps its authored introductions for a first meeting
	out.append({"who": a, "text": line(a, "greet"), "gesture": "waving" if _rng.randf() < 0.4 else ""})
	out.append({"who": b, "text": line(b, "greet")})
	var ta := topics(a, b)
	var tb := topics(b, a)
	var used := {}
	for turn in 2:
		var sp := a if turn == 0 else b
		var ls := b if sp == a else a
		var tl: Array = ta if sp == a else tb
		var t: Dictionary = {}
		for cand in tl:
			if not used.has(cand.topic):
				t = cand
				break
		if t.is_empty():
			continue
		used[t.topic] = true
		out.append_array(_exchange(sp, ls, t))
	if out.size() <= 1:
		out.append({"who": b, "text": line(b, "ask_place")})
		out.append({"who": a, "text": line(a, "answer_none")})
	return out.filter(func(l): return String(l.text) != "")


## One topic: the opener and the listener's reaction from her OWN memory. Each line carries `teach`:
## the topic the listener is now told about (recorded after the line was really spoken).
func _exchange(sp: String, ls: String, t: Dictionary) -> Array:
	var lm := WorldState.mind(ls)
	var out := []
	match String(t.kind):
		"clue":
			out.append({"who": sp, "text": line(sp, "share_clue", t.fill), "teach": {"to": ls, "topic": t.topic, "text": t.fill.hint}, "gesture": "pointing" if _rng.randf() < 0.3 else ""})
			out.append({"who": ls, "text": line(ls, "react_known" if lm.knowledge.has(t.topic) else "react_new")})
		"creature":
			out.append({"who": sp, "text": line(sp, "share_creature", t.fill), "teach": {"to": ls, "topic": t.topic, "text": "%s fought a %s" % [MagicSystem.display_name(sp), t.fill.creature]}})
			var knows := int(lm.knowledge.get("defeated:" + String(t.creature), 0)) > 0
			out.append({"who": ls, "text": line(ls, "react_creature_known" if knows else "react_creature_new")})
		"book":
			out.append({"who": sp, "text": line(sp, "share_book", t.fill), "teach": {"to": ls, "topic": t.topic, "text": "%s read %s" % [MagicSystem.display_name(sp), t.fill.book]}})
			out.append({"who": ls, "text": line(ls, "react_known" if lm.knowledge.has(String(t.topic).replace("book:", "read:")) else "react_new")})
		"place":
			out.append({"who": sp, "text": line(sp, "share_place", t.fill), "teach": {"to": ls, "topic": t.topic, "text": t.fill.place}, "gesture": "pointing"})
			out.append({"who": ls, "text": line(ls, "ack")})
		"ask_creature":
			out.append({"who": sp, "text": line(sp, "ask_creature", t.fill)})
			# the answer comes from the LISTENER's own memory of that fight
			out.append({"who": ls, "text": line(ls, "answer_creature", t.fill), "teach": {"to": sp, "topic": t.topic, "text": "%s's advice about the %s" % [MagicSystem.display_name(ls), t.fill.creature]}})
			out.append({"who": sp, "text": line(sp, "react_new")})
		"ask_clue":
			var hint := _clue_hint(String(t.topic)) if lm.knowledge.has(String(t.topic)) else ""
			out.append({"who": sp, "text": line(sp, "ask_clue", t.fill)})
			if hint != "":
				out.append({"who": ls, "text": hint, "teach": {"to": sp, "topic": t.topic, "text": hint}})
				out.append({"who": sp, "text": line(sp, "react_new")})
			else:
				out.append({"who": ls, "text": line(ls, "answer_none")})
		"reminisce":
			out.append({"who": sp, "text": line(sp, "reminisce", t.fill)})
			out.append({"who": ls, "text": line(ls, "reminisce_reply")})
		"worry":
			out.append({"who": sp, "text": line(sp, "share_worry", t.fill), "teach": {"to": ls, "topic": t.topic, "text": "%s had to back away from a %s" % [MagicSystem.display_name(sp), t.fill.creature]}})
			out.append({"who": ls, "text": line(ls, "react_worry", t.fill)})
		"triumph":
			out.append({"who": sp, "text": line(sp, "share_triumph", t.fill), "teach": {"to": ls, "topic": t.topic, "text": "%s beat the %s in the end" % [MagicSystem.display_name(sp), t.fill.creature]}})
			out.append({"who": ls, "text": line(ls, "react_triumph", t.fill)})
	return out


## After a line was really spoken: the listener remembers what she was told (not the fact itself).
static func remember_told(teach: Dictionary, speaker: String) -> void:
	if teach.is_empty():
		return
	var lm := WorldState.mind(String(teach.to))
	lm.knowledge["told:%s:%s" % [speaker, String(teach.topic)]] = String(teach.get("text", "")).left(160)


# ------------------------------------------------------------------ invitations
## Would `who` join `kind` with `inviter` right now? Decided from her own state. -> {accept, reason, u}
func consider(who: String, inviter: String, kind: String) -> Dictionary:
	var b = main.mage_brains.get(who)
	var c: WorldCharacter = main.characters.get(who)
	if b == null or c == null or not c.visible:
		return {"accept": false, "reason": "away"}
	var m := WorldState.mind(who)
	var spec: Dictionary = cfg.get("join", {}).get("activities", {}).get(kind, {})
	var doing := String(b.current.get("kind", ""))
	if c.casting or doing in ["hunt", "perform", "meet", "research", "alchemy", "attune", "together"] or (main.performance and main.performance.busy() and String(main.performance.active.get("who", "")) == who):
		return {"accept": false, "reason": "busy"}
	var energy := float(b.needs.get("energy", 1.0))
	if bool(spec.get("strenuous", false)) and (m.vigor < 0.5 or energy < 0.35):
		return {"accept": false, "reason": "tired"}
	if m.vigor < 0.25:
		return {"accept": false, "reason": "tired"}
	var rel: Dictionary = MageTalk.rel(who, inviter)
	var temper := float(b.profile.get("temperament", {}).get(_temper_kind(kind), 1.0))
	var u := float(spec.get("base", 0.5)) * temper + 0.35 * float(rel.get("camaraderie", 0.0)) + 0.2 * float(b.needs.get("social", 0.4)) - 0.15 * float(rel.get("rivalry", 0.0))
	if doing in ["", "explore", "roam", "journal", "rest"]:
		u += 0.1
	u += _rng.randf_range(-0.08, 0.08)                       # people are not perfectly predictable
	return {"accept": u >= 0.45, "reason": "mood" if u < 0.45 else "", "u": snappedf(u, 0.01)}


static func _temper_kind(kind: String) -> String:
	return {"explore_together": "explore", "gather_together": "gather", "rest_together": "rest", "study_together": "research", "train_together": "magic", "expedition": "explore"}.get(kind, "meet")


# ------------------------------------------------------------------ doing it together
## Invite and, if accepted, do it. Called from the inviter's planner (kind "together").
func invite(a: SanctuaryBrain, other: String, kind: String, target: Dictionary) -> Dictionary:
	if busy() or (main.mage_talk and main.mage_talk.busy()):
		return {"ok": false, "detail": "already doing something together"}
	var b: SanctuaryBrain = main.mage_brains.get(other)
	var bc: WorldCharacter = main.characters.get(other)
	if b == null or bc == null or not bc.visible:
		return {"ok": false, "detail": "%s is not around" % MagicSystem.display_name(other)}
	active = {"kind": kind, "leader": a.agent_id, "follower": other, "t0": Time.get_ticks_msec() / 1000.0, "stage": "inviting"}
	var me := a.me
	a.current.stage = "going over to %s" % MagicSystem.display_name(other)
	await approach_for_talk(a, bc, 1.7)
	var dec := consider(other, a.agent_id, kind)
	if force_accept:
		dec = {"accept": true, "reason": "", "u": 1.0}
	var spec: Dictionary = cfg.get("join", {}).get("activities", {}).get(kind, {})
	var label := String(spec.get("label", kind))
	for k in target.get("fill", {}):
		label = label.replace("{%s}" % k, String(target.fill[k]))
	me.look_at_point(bc.global_position)
	me.look_head_at(bc.global_position + Vector3(0, 1.45, 0))
	bc.look_head_at(me.global_position + Vector3(0, 1.45, 0))
	if main.director and main.director.enabled:
		main.director.focus_conversation(bc if main.director.mika == me else me, 10.0)
	await _say(a.agent_id, line(a.agent_id, "propose", {"activity": label}))
	await get_tree().create_timer(0.35).timeout
	var entry := {"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "kind": kind, "leader": a.agent_id, "follower": other, "label": label,
		"accepted": dec.accept, "reason": dec.get("reason", ""), "u": dec.get("u", 0.0)}
	if not dec.accept:
		await _say(other, line(other, "decline_" + String(dec.reason) if dec.reason in ["tired", "busy", "mood"] else "decline_mood"))
		me.look_head_at(null)
		bc.look_head_at(null)
		a.mind.knowledge["declined_by:%s:%s" % [other, kind]] = Time.get_unix_time_from_system()
		log.append(entry)
		if log.size() > 200:
			log.pop_front()
		active = {}
		return {"ok": false, "detail": "%s declined (%s)" % [MagicSystem.display_name(other), dec.reason], "entry": entry}
	await _say(other, line(other, "accept"))
	b.hold = true
	b.interrupt("social")
	var t0 := Time.get_ticks_msec()
	while not b.current.is_empty() and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	b.current = {"kind": "together", "label": "%s with %s" % [label, MagicSystem.display_name(a.agent_id)], "stage": "following"}
	var res: Dictionary
	match kind:
		"explore_together", "expedition":
			res = await _explore_together(a, b, target)
		"rest_together":
			res = await _rest_together(a, b, target)
		"train_together":
			if main.get("duel"):
				res = await main.duel.run(a, b)
			else:
				res = {"ok": false, "detail": "no training ground"}
		"stargaze_together":
			res = await _stargaze_together(a, b, target)
		_:
			res = await _explore_together(a, b, target)
	# each of them keeps her OWN memory of it
	var n := int(a.mind.knowledge.get("together_count", 0)) + 1
	for pair in [[a.agent_id, other], [other, a.agent_id]]:
		var mm := WorldState.mind(pair[0])
		var rel2 := MageTalk.rel(pair[0], pair[1])
		rel2.camaraderie = minf(1.0, float(rel2.camaraderie) + BOND_GAIN)
		rel2["together"] = int(rel2.get("together", 0)) + 1
		var mem := String(res.get("memory_" + String(pair[0]), res.get("memory", "spent time together")))
		mm.knowledge["together:%s:%d" % [pair[1], n]] = {"memory": mem, "unix": int(Time.get_unix_time_from_system())}
		mm.knowledge["together_count"] = n
		WorldState.record_activity({"id": "together:%s:%s" % [kind, pair[1]], "verb": "together", "label": "%s with %s" % [label.capitalize(), MagicSystem.display_name(pair[1])]},
			res.get("effects_" + String(pair[0]), {}), pair[0])
	b.current = {}
	b.hold = false
	me.look_head_at(null)
	bc.look_head_at(null)
	entry["result"] = res.get("detail", "")
	log.append(entry)
	if log.size() > 200:
		log.pop_front()
	active = {}
	joint_finished.emit(entry)
	return {"ok": res.get("ok", false), "detail": "%s with %s: %s" % [label, MagicSystem.display_name(other), res.get("detail", "")], "entry": entry}


## Stand where people stand to talk: ~1.6 m from the other, on the navmesh, with nothing between them, as close
## to where she already is as possible; walk there (precise last steps) and face each other.
static func approach_for_talk(brain, other: WorldCharacter, dist := 1.6) -> void:
	var me: WorldCharacter = brain.me
	var map := me.get_world_3d().navigation_map
	var space := me.get_world_3d().direct_space_state
	var base := Vector3(me.global_position.x - other.global_position.x, 0, me.global_position.z - other.global_position.z)
	if base.length() < 0.1:
		base = Vector3.BACK
	base = base.normalized()
	var best := Vector3.INF
	for ang in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4, PI]:
		var want: Vector3 = other.global_position + base.rotated(Vector3.UP, ang) * dist
		var p := NavigationServer3D.map_get_closest_point(map, want)
		if p.distance_to(Vector3(want.x, p.y, want.z)) > 0.35:
			continue
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.3, 0), other.global_position + Vector3(0, 1.3, 0))
		q.exclude = [me.get_rid(), other.get_rid()]
		q.collision_mask = 1
		if not space.intersect_ray(q).is_empty():
			continue
		best = p
		break
	if best == Vector3.INF:
		return
	if me.global_position.distance_to(best) > 2.0:
		await brain._walk(best)
	if Vector2(me.global_position.x - best.x, me.global_position.z - best.z).length() > 0.4:
		me.navigate_to(best, false)
		var t0 := Time.get_ticks_msec()
		while me.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 6000:
			await me.get_tree().process_frame
	# the last steps by hand (navigation stops within ~0.7 m): walk in until she is at talking distance
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 2500:
		var to := Vector3(best.x - me.global_position.x, 0, best.z - me.global_position.z)
		if to.length() < 0.2:
			break
		me.set_move_input(to.normalized() * clampf(to.length() * 1.5, 0.35, 1.0), false)
		await me.get_tree().physics_frame
	me.set_move_input(Vector3.ZERO, false)
	me.look_at_point(other.global_position)
	other.look_at_point(me.global_position)


func _say(who: String, text: String, gesture := "") -> Dictionary:
	if text == "":
		return {}
	var c: WorldCharacter = main.characters.get(who)
	if gesture != "" and c and not c.casting:
		c.play_gesture(gesture, 0.3, 0.5)
	return await main.voice.say(String(Progression.mages.get(who, {}).get("voice", who)), text)


## Walk to a place together (the leader's choice), look, each says what SHE sees, come back to the moment.
func _explore_together(a: SanctuaryBrain, b: SanctuaryBrain, target: Dictionary) -> Dictionary:
	var lead := a.me
	var fol := b.me
	var to: Vector3 = target.get("pos", lead.global_position)
	active.stage = "setting off together"
	var f := FollowCompanion.new()
	f.name = "Follow_" + b.agent_id
	f.leader = lead
	f.follower = fol
	add_child(f)
	var walked := await walk_together(lead, f, to, 40.0)
	active.stage = "looking around together"
	await _say(a.agent_id, line(a.agent_id, "together_arrive"))
	# each looks for herself: what she can see from here (her own perception)
	var seen := {}
	for br in [a, b]:
		var noticed: Array = br.perceive()
		var what := ""
		if not noticed.is_empty():
			var it = main.world.interactables.get(noticed[0])
			what = String(it.label).to_lower() if it else ""
		seen[br.agent_id] = what
		br.me.look_at_point(to + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2)))
	await get_tree().create_timer(1.0).timeout
	for br in [b, a]:
		if String(seen[br.agent_id]) != "":
			await _say(br.agent_id, line(br.agent_id, "together_observe", {"noticed": seen[br.agent_id]}), "pointing")
			await get_tree().create_timer(0.4).timeout
	await _say(b.agent_id, line(b.agent_id, "together_done"))
	f.queue_free()
	var place := String(target.get("fill", {}).get("place", "the woods"))
	var out := {"ok": walked, "detail": "walked to %s together%s" % [place, "" if walked else " (part of the way)"],
		"memory": "walked out to %s together" % place}
	for br in [a, b]:
		var cellk := ExplorationMap.cell_key(br.me.global_position)
		out["effects_" + br.agent_id] = {"knowledge": {"place:%s:%s" % [main.streaming.current_id, cellk]: 1}}
		if String(seen[br.agent_id]) != "":
			out["memory_" + br.agent_id] = "walked out to %s together and saw %s" % [place, seen[br.agent_id]]
	return out


## V3 quiet scene: walk to open grass together, lie down side by side, look up, say a little, say nothing for a
## while, get up. Real clips (the UAL get-up played backwards, the held lying pose with breathing), real looks
## (heads turn to whoever speaks, then back to the sky), the camera on a stargazing mode for the whole scene.
func _stargaze_together(a: SanctuaryBrain, b: SanctuaryBrain, target: Dictionary) -> Dictionary:
	var lead := a.me
	var fol := b.me
	var spot: Vector3 = target.get("pos", lead.global_position)
	var place := String(target.get("fill", {}).get("place", "the grass"))
	active.stage = "walking out to the grass"
	var f := FollowCompanion.new()
	f.name = "Follow_" + b.agent_id
	f.leader = lead
	f.follower = fol
	add_child(f)
	var walked := await walk_together(lead, f, spot, 45.0)
	f.queue_free()
	# two places 1.3 m apart, both facing the same open way (away from where they came from)
	var map := lead.get_world_3d().navigation_map
	var facing := Vector3(spot.x - lead.global_position.x, 0, spot.z - lead.global_position.z)
	facing = facing.normalized() if facing.length() > 0.5 else -lead.global_transform.basis.z
	var perp := Vector3(-facing.z, 0, facing.x)
	var pa := NavigationServer3D.map_get_closest_point(map, spot + perp * 0.65)
	var pb := NavigationServer3D.map_get_closest_point(map, spot - perp * 0.65)
	active.stage = "settling into the grass"
	lead.navigate_to(pa, false)
	fol.navigate_to(pb, false)
	var tw := 0.0
	while (lead.current_action == "navigate_to" or fol.current_action == "navigate_to") and tw < 12.0:
		await get_tree().physics_frame
		tw += get_physics_process_delta_time()
	lead.look_at_point(lead.global_position + facing * 3.0)
	fol.look_at_point(fol.global_position + facing * 3.0)
	await get_tree().create_timer(0.8).timeout
	await _say(a.agent_id, line(a.agent_id, "stargaze_arrive"))
	if main.director:
		main.director.begin_stargaze(lead, fol)
	lead.lie_down()
	await get_tree().create_timer(0.9).timeout
	await _say(b.agent_id, line(b.agent_id, "stargaze_arrive"))
	await fol.lie_down()
	var sky_a := lead.global_position + Vector3(0, 14, 0) + facing * 2.0
	var sky_b := fol.global_position + Vector3(0, 14, 0) + facing * 2.0
	lead.look_head_at(sky_a)
	fol.look_head_at(sky_b)
	await get_tree().create_timer(5.0).timeout
	# a few words, real pauses, heads turning to whoever speaks
	var beats := [[a, b, "stargaze_quiet", 4.0], [b, a, "stargaze_wonder", 1.0], [a, b, "stargaze_reply", 6.0], [a, b, "stargaze_wonder", 1.0], [b, a, "stargaze_reply", 7.0], [b, a, "stargaze_quiet", 5.0]]
	var said := 0
	for bt in beats:
		var sp: SanctuaryBrain = bt[0]
		var ls: SanctuaryBrain = bt[1]
		var text := line(sp.agent_id, String(bt[2]))
		if text == "...":
			await get_tree().create_timer(float(bt[3])).timeout
			continue
		sp.me.look_head_at(ls.me.global_position + Vector3(0, 0.25, 0))
		ls.me.look_head_at(sp.me.global_position + Vector3(0, 0.25, 0))
		active.stage = "%s speaks" % MagicSystem.display_name(sp.agent_id)
		await _say(sp.agent_id, text)
		said += 1
		await get_tree().create_timer(0.8).timeout
		sp.me.look_head_at(sky_a if sp == a else sky_b)
		ls.me.look_head_at(sky_a if ls == a else sky_b)
		await get_tree().create_timer(float(bt[3])).timeout
	active.stage = "just watching"
	await get_tree().create_timer(8.0).timeout
	await _say(a.agent_id, line(a.agent_id, "stargaze_done"))
	lead.look_head_at(null)
	fol.look_head_at(null)
	await _say(b.agent_id, line(b.agent_id, "stargaze_done"))
	fol.get_up()
	await get_tree().create_timer(0.7).timeout
	await lead.get_up()
	if main.director:
		main.director.end_stargaze()
	for br in [a, b]:
		br.needs.energy = clampf(float(br.needs.energy) + 0.18, 0.0, 1.0)
	var out := {"ok": walked, "detail": "lay in the grass at %s and watched the stars (%d lines)" % [place, said],
		"memory": "lay in the grass at %s and watched the stars" % place}
	for br in [a, b]:
		out["effects_" + br.agent_id] = {"knowledge": {"stargazed:%s" % main.streaming.current_id: 1}}
	return out


func _rest_together(a: SanctuaryBrain, b: SanctuaryBrain, target: Dictionary) -> Dictionary:
	var f := FollowCompanion.new()
	f.leader = a.me
	f.follower = b.me
	add_child(f)
	await walk_together(a.me, f, target.get("pos", a.me.global_position), 30.0)
	f.queue_free()
	a.me.look_at_point(b.me.global_position)
	b.me.look_at_point(a.me.global_position)
	for br in [a, b]:
		br.mind.vigor = clampf(br.mind.vigor + 0.0, 0.0, 1.0)      # resting itself recovers through the normal rates
	var conv := compose(a.agent_id, b.agent_id)
	for l in conv:
		await _say(String(l.who), String(l.text), String(l.get("gesture", "")))
		remember_told(l.get("teach", {}), String(l.who))
		await get_tree().create_timer(_rng.randf_range(0.3, 0.9)).timeout
	await get_tree().create_timer(4.0).timeout
	return {"ok": true, "detail": "rested and talked (%d lines)" % conv.size(), "memory": "rested together and talked"}


## The leader walks to `to` while the follower keeps up; the leader waits (and looks back) when she falls
## behind. Real navigation for both; returns true when the leader arrived.
func walk_together(lead: WorldCharacter, f: FollowCompanion, to: Vector3, max_s: float) -> bool:
	var map := lead.get_world_3d().navigation_map
	var goal := NavigationServer3D.map_get_closest_point(map, to)
	# set off together: she waits (looking at her friend) until her companion has come up beside her
	var tw := 0.0
	if f.gap() > 2.6:
		lead.look_head_at(f.follower.global_position + Vector3(0, 1.45, 0))
		while f.gap() > 2.6 and tw < 10.0:
			await get_tree().physics_frame
			tw += get_physics_process_delta_time()
		lead.look_head_at(null)
	if String(active.get("stage", "")) == "setting off together":
		active.stage = "walking together"
	lead.navigate_to(goal, false)
	var t := 0.0   # GAME time: under Movie Maker recording real time runs many times slower than the game
	var waiting := false
	var pace0: float = lead.pace
	while t < max_s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var gap := f.gap()
		# she walks at her companion's pace: a hurt or tired friend sets it, and she eases off further when the
		# gap opens (instead of striding ahead and stopping to wait)
		var fol: WorldCharacter = f.follower
		var ft: float = fol.body_language.tempo() if fol and fol.body_language and is_instance_valid(fol.body_language) else 1.0
		var lt: float = lead.body_language.tempo() if lead.body_language and is_instance_valid(lead.body_language) else 1.0
		lead.pace = pace0 * clampf(ft / maxf(lt, 0.5) * (1.0 - clampf((gap - 2.2) / 5.0, 0.0, 0.45)), 0.5, 1.0)
		if gap > 5.5 and not waiting and lead.current_action == "navigate_to":
			waiting = true
			lead.stop_action()
			lead.look_head_at(f.follower.global_position + Vector3(0, 1.45, 0))
		elif waiting and gap < 2.6:
			waiting = false
			lead.look_head_at(null)
			lead.navigate_to(goal, false)
		elif not waiting and lead.current_action != "navigate_to":
			break
	lead.look_head_at(null)
	lead.pace = pace0
	return Vector2(lead.global_position.x - goal.x, lead.global_position.z - goal.z).length() < 2.0
