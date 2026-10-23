class_name VillagerRequests
extends RefCounted
## Helping the villagers (2026-10-23; data/requests.json). A resident asks once, as a chat topic; Mika says yes and the
## request stays open in her mind (saved): knowledge "request:<id>" = "open" | "done", "request_asked_unix:<id>". What
## she does anyway now has a reason: gathering the herb they asked for, travelling back to their village, waking the
## crystal in the square. When she has it (or has done it) she goes back to them and they thank her: activity
## "help:<id>", which pays the XP (progression.json, proposed rates). Mika only (the one who said yes).

static var data := {}


static func load_data() -> Dictionary:
	if data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/requests.json"))
		data = d if d is Dictionary else {"requests": [], "max_open": 2}
	return data


static func by_id(rq_id: String) -> Dictionary:
	for r in load_data().requests:
		if String(r.id) == rq_id:
			return r
	return {}


static func state(m: MageMind, rq_id: String) -> String:
	return String(m.knowledge.get("request:" + rq_id, ""))


static func open_ones(m: MageMind) -> Array:
	return load_data().requests.filter(func(r): return state(m, String(r.id)) == "open")


## The resident's request as a chat topic ({} when there is none to ask now).
static func ask_topic(m: MageMind, rid: String) -> Dictionary:
	if open_ones(m).size() >= int(load_data().get("max_open", 2)):
		return {}
	for r in load_data().requests:
		if String(r.resident) != rid or state(m, String(r.id)) != "":
			continue
		if open_ones(m).any(func(o): return String(o.resident) == rid):
			return {}
		return {"id": "request:" + String(r.id), "line": String(r.ask), "reply": String(r.reply),
			"effects": {"knowledge": {"request:" + String(r.id): "open", "request_asked_unix:" + String(r.id): int(Time.get_unix_time_from_system())}}}
	return {}


## Has she what this request needs (the items in her bag, or the spell done at its target since she was asked)?
static func ready(m: MageMind, r: Dictionary) -> bool:
	var need: Dictionary = r.get("need", {})
	if need.has("item"):
		return int(m.inventory.get(String(need.item), 0)) >= int(need.get("n", 1))
	if need.has("magic_target"):
		var asked := float(m.knowledge.get("request_asked_unix:" + String(r.id), 0.0))
		var suffix := ":" + String(need.magic_target)
		for k in m.activity_counts:
			if String(k).begins_with("magic:") and String(k).ends_with(suffix) and float((m.activity_counts[k] as Dictionary).get("last_unix", 0.0)) > asked:
				return true
	return false


## Why an option matters more now: a promise to keep. [bonus, reason] for gather / magic / visit options.
static func pull(m: MageMind, o: Dictionary) -> Array:
	for r in open_ones(m):
		var need: Dictionary = r.get("need", {})
		var who := String(r.resident).capitalize()
		match String(o.get("kind", "")):
			"gather":
				if need.has("item") and String(need.item) == String(o.get("item", "")) and not ready(m, r):
					return [0.45, "%s asked for %s" % [who, String(need.item)]]
			"magic":
				if need.has("magic_target") and String(o.get("target", "")) == String(need.magic_target) and not ready(m, r):
					return [0.55, "%s asked her to wake it" % who]
			"visit":
				var area := String(r.get("area", ""))
				var match_area := String(o.get("area", "")) == area or (area.begins_with("wayside:") and String(o.get("location", "")) == area.trim_prefix("wayside:"))
				if match_area and (ready(m, r) or need.has("magic_target")):
					return [0.4, "a promise to %s" % who]
	return [0.0, ""]


## "Bring it to them" options: a ready request whose resident she can see from here.
static func help_options(brain) -> Array:
	var out := []
	if not brain.main.get("town"):
		return out
	for r in open_ones(brain.mind):
		if not ready(brain.mind, r):
			continue
		var rr = brain.main.town.residents.get(String(r.resident))
		if rr == null or not is_instance_valid(rr) or not rr.visible or rr.state in ["walking", "inside"]:
			continue
		if brain.me.global_position.distance_to(rr.global_position) > 40.0:
			continue
		out.append({"kind": "help", "key": "help:" + String(r.id), "request": String(r.id), "resident": String(r.resident),
			"label": "bring %s what she promised" % String(rr.data.get("name", r.resident)) if r.need.has("item") else "tell %s it is done" % String(rr.data.get("name", r.resident))})
	return out


## Go to them, hand it over (or tell them), their thanks.
static func help(brain, o: Dictionary) -> Dictionary:
	var r := by_id(String(o.request))
	var rr = brain.main.town.residents.get(String(o.resident)) if brain.main.get("town") else null
	if r.is_empty() or rr == null or not is_instance_valid(rr) or not rr.visible:
		return {"ok": false, "detail": "they are not here any more"}
	if not ready(brain.mind, r):
		return {"ok": false, "detail": "she does not have it any more"}
	var me: WorldCharacter = brain.me
	var to: Vector3 = rr.global_position + (me.global_position - rr.global_position).normalized() * 1.5
	if not await brain._walk(to):
		return {"ok": false, "detail": "could not get to %s" % String(rr.data.get("name", ""))}
	me.look_at_point(rr.global_position)
	rr.notice(me, false)
	rr.state = "talking"
	rr._face_yaw = atan2(me.global_position.x - rr.global_position.x, me.global_position.z - rr.global_position.z)
	me.look_head_at(rr.global_position + Vector3(0, 1.6, 0))
	if brain.is_foreground() and brain.main.get("director"):
		brain.main.director.focus_conversation(rr, 12.0)          # both faces, the hand-over in the picture
	var need: Dictionary = r.get("need", {})
	if need.has("item") and me.has_clip("interact"):
		me.play_gesture("interact", 0.25, 0.4)             # (handing it over)
	await brain.main.voice.say(brain._voice(), String(r.done_reply), {"max_wait": 2.5, "mood": "happy"})
	if need.has("item"):
		me.end_gesture()
	rr.play("talk", 0.3)
	await brain.main.voice.say(String(rr.data.get("voice", rr.id)), String(r.thanks), {"max_wait": 2.5})
	me.look_head_at(null)
	var eff := {"knowledge": {"request:" + String(r.id): "done", "helped_resident:" + String(r.resident): 1}}
	if need.has("item"):
		eff["items"] = {String(need.item): -int(need.get("n", 1))}
	var changes := WorldState.record_activity({"id": "help:" + String(r.id), "verb": "help", "label": "Helped %s" % String(rr.data.get("name", r.resident))}, eff, brain.agent_id)
	Highlights.moment(brain.main, "help", "%s helps %s" % [MagicSystem.display_name(brain.agent_id), String(rr.data.get("name", r.resident))], 3.0)
	rr.state = "at:" + String(rr.activity)
	rr._begin_activity()
	return {"ok": true, "detail": "helped %s (%s)" % [String(rr.data.get("name", "")), String(r.id)], "changes": changes}
