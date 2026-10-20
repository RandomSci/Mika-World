class_name ScenePersist
extends Node
## PERSISTENCE (2026-10-19, Selwyn: "they must ALWAYS continue exactly where they left off after any restart, crash,
## stream drop or reboot"). WorldState already saves progress (level, XP, inventory, story, trials, memory, the clock)
## and each mage's area + place; this node adds the LIVE SCENE to the same atomic save (temp file -> read back ->
## rename, see WorldState._write_save): where each mage stands and faces, what her planner is doing, her recent
## decisions and needs, the activity she is in and its step (the boat mid-lake with who sits where and whether Luna
## rows, a dance at its clip time and song position), the lake's lanterns (released ones, viewers' names).
##
## Written every 30 s (WorldState.PERIODIC_SAVE_S) and at once on every activity change (a step signature polled
## twice a second). On load, resume() puts everything back and the activity carries on from its saved step - never
## from the start, never at home: the area main resumed in is the area the save was made in.
##
## ACTIVITY CONTRACT (shared with the night-ritual activities): any node in group "persistent_activity" implements
##   persist_key() -> String          unique and stable ("moon_boat:MoonBoat", "dance:DanceSession")
##   snapshot() -> Dictionary         JSON-safe state ({} = nothing worth resuming). Conventions: "step" (a short
##                                    string that changes when the activity changes step: triggers a save),
##                                    "participants" (mage ids: placed by the activity, their planners are held)
##   restore(d: Dictionary) -> void   may be a coroutine; may be called on a freshly made node (Script.new(), added
##                                    under the area) - it must then build itself from d
## Optional: persist_step() -> String (a cheap step signature; otherwise snapshot().step is read), and a static
## persist_spawn(parent: Node, d: Dictionary) -> Node to build the node instead of Script.new().

const GROUP := "persistent_activity"
const VERSION := 1
const POLL_S := 0.5
const MIN_GAP_S := 1.0                    # activity saves at most once a second (the latest step always follows)

signal captured(scene: Dictionary)        # a snapshot was taken for a save (tests record the truth here)
signal resumed(report: Dictionary)

var main: Node
var restoring := false
var resumed_done := false
var report := {}                          # what resume() found and did (tests, the log)
var seq := 0                              # capture counter (each snapshot carries it; continues across restarts)
var last_capture := {}
var _pending: Array = []                  # activity records for an area that is not loaded (restored when it is)
var _sig := ""
var _poll := 0.0
var _since_save := 99.0
var _closing := false


func setup(m: Node) -> void:
	main = m
	seq = int(WorldState.scene.get("seq", 0))
	WorldState.scene_provider = capture
	main.streaming.area_activated.connect(_on_area_activated)
	main.streaming.transition_started.connect(_on_transition_started)
	_ensure_helpers()


func _exit_tree() -> void:
	# closing: the area and its activities may already have left the tree (no capture now); the scene of the last
	# second is what WorldState writes when it is freed
	if not restoring and not _fresh.is_empty():
		WorldState.scene = _fresh
	_closing = true
	WorldState.scene_provider = Callable()


# ------------------------------------------------------------------------------------------------------- capture
## The live scene ({} while a restore runs: WorldState then keeps the loaded scene, so a half-restored world is never
## written over a good save).
func capture() -> Dictionary:
	return _build(true)


var _fresh := {}                          # the scene of the last second (written on a clean exit)
var _fresh_t := 0.0


func _build(for_save: bool) -> Dictionary:
	if restoring or _closing or main == null or not is_instance_valid(main) or main.get("streaming") == null:
		return {}
	if for_save:
		seq += 1
	var area: String = main.streaming.current_id
	var d := {"v": VERSION, "seq": seq, "unix": int(Time.get_unix_time_from_system()), "area": area, "focus": String(main.focus),
		"clock": {"world_min": WorldState.world_min, "day": WorldState.day(), "hour_f": snappedf(WorldState.hour_f(), 0.001),
			"real_clock": WorldState.real_clock},
		"goal": WorldState.current_goal, "story_stage": str(WorldState.story_state.get("stage", "")), "mages": {}, "activities": []}
	if main.get("day_night") and main.day_night:
		d["day_night"] = {"override": int(main.day_night.override), "k": snappedf(float(main.day_night.k), 0.01)}
	for who in main.mages:
		d.mages[who] = _mage_state(who)
	var keys := {}
	for n in get_tree().get_nodes_in_group(GROUP):
		var rec := _record(n)
		if not rec.is_empty() and not keys.has(rec.key):
			keys[rec.key] = true
			d.activities.append(rec)
	for rec in _pending:
		if not keys.has(rec.key):
			d.activities.append(rec)
	if for_save:
		last_capture = d
		captured.emit(d)
	_fresh = d
	return d


func _mage_state(who: String) -> Dictionary:
	var c: WorldCharacter = main.characters.get(who)
	var m := WorldState.mind(who)
	var e := {"area": String(m.location.get("area", "")), "level": m.level(), "xp": float(m.progress.get("xp", 0.0)),
		"form": String(m.progress.get("appearance", ""))}
	if c and is_instance_valid(c):
		e["visible"] = c.visible
		if c.visible and c.is_inside_tree():
			e["area"] = String(main.streaming.current_id)
			e["pos"] = _v3(c.global_position)
			e["yaw"] = snappedf(c.global_rotation.y, 0.0001)
			e["physics"] = c.is_physics_processing()
			e["action"] = String(c.current_action)
			if String(c.current_action) == "navigate_to":
				var g: Vector3 = c.get("_nav_goal")
				e["nav_goal"] = _v3(g)                # (where the walk was going: it carries on there after a restart)
				e["nav_run"] = bool(c.get("_run"))
			e["ground_pose"] = String(c.ground_pose)
			e["seated"] = c.seated
		else:
			e["pos"] = m.location.get("pos", [])
		if main.get("transformer") == null or main.transformer == null or String(main.transformer.playing) == "":
			e["avatar"] = c.avatar_path          # (never a transformation caught half-way)
	var b = main.mage_brains.get(who) if main.get("mage_brains") else null
	if b:
		var cur: Dictionary = b.current
		var needs := {}
		for k in b.needs:
			needs[k] = snappedf(float(b.needs[k]), 0.001)
		e["brain"] = {"enabled": bool(b.enabled), "hold": bool(b.hold), "needs": needs,
			"current": {"kind": String(cur.get("kind", "")), "key": String(cur.get("key", "")), "label": String(cur.get("label", ""))},
			"history": _safe((b.history as Array).slice(maxi(0, (b.history as Array).size() - 12)))}
	return e


func _record(n: Node) -> Dictionary:
	if not is_instance_valid(n) or not n.is_inside_tree() or not n.has_method("persist_key") or not n.has_method("snapshot"):
		return {}
	var data = n.call("snapshot")
	if not data is Dictionary or (data as Dictionary).is_empty():
		return {}
	if not n.has_meta("persist_area"):
		n.set_meta("persist_area", String(main.streaming.current_id))
	var scr: Script = n.get_script()
	var parent := ""
	if main.world and n.get_parent() and (n.get_parent() == main.world or main.world.is_ancestor_of(n.get_parent())):
		parent = String(main.world.get_path_to(n.get_parent()))
	return {"key": String(n.call("persist_key")), "script": scr.resource_path if scr else "", "area": String(n.get_meta("persist_area")),
		"parent": parent, "step": str((data as Dictionary).get("step", "")), "data": _safe(data)}


## The change signature: the area, each activity's step, each mage's planner activity and seat. A change saves at once.
func _signature() -> String:
	var parts: Array = [String(main.streaming.current_id)]
	for n in get_tree().get_nodes_in_group(GROUP):
		if not is_instance_valid(n) or not n.is_inside_tree() or not n.has_method("persist_key"):
			continue
		var st := ""
		if n.has_method("persist_step"):
			st = str(n.call("persist_step"))
		elif n.has_method("snapshot"):
			st = str((n.call("snapshot") as Dictionary).get("step", ""))
		parts.append("%s=%s" % [n.call("persist_key"), st])
	for who in main.mages:
		var b = main.mage_brains.get(who)
		var c: WorldCharacter = main.characters.get(who)
		parts.append("%s:%s:%s" % [who, String(b.current.get("key", "")) if b else "", (c.ground_pose + ("/seated" if c.seated else "")) if c else ""])
	return "|".join(parts)


func _process(delta: float) -> void:
	_since_save += delta
	_poll -= delta
	_fresh_t -= delta
	if _poll > 0.0 or main == null:
		return
	_poll = POLL_S
	if restoring or not WorldState.persistent or main.streaming.state != "idle":
		return
	if _fresh_t <= 0.0:
		_fresh_t = 1.0
		_build(false)
		_tag_participants()
	var s := _signature()
	if s == _sig or _since_save < MIN_GAP_S:
		return
	var first := _sig == ""
	_sig = s
	if first:
		return                            # (the first look is the baseline, not a change)
	_since_save = 0.0
	WorldState.save_async("activity")


## Every mage in a running persistent activity carries meta "persist_activity" = its key (other code leaves her be:
## e.g. the lake's "nobody stands in the water" rescue must not pull a dancer off her mark); cleared when it ends.
func _tag_participants() -> void:
	var now := {}
	for rec in (_fresh.get("activities", []) as Array):
		if String(rec.get("area", "")) != String(main.streaming.current_id):
			continue
		for p in (rec.get("data", {}) as Dictionary).get("participants", []):
			now[String(p)] = String(rec.key)
	for who in main.characters:
		var c: Node = main.characters[who]
		if now.has(who):
			c.set_meta("persist_activity", now[who])
		elif c.has_meta("persist_activity"):
			c.remove_meta("persist_activity")


## Save right now (an activity that wants its new step on disk without waiting for the poll).
func changed(_reason := "activity") -> void:
	if WorldState.persistent and not restoring:
		_since_save = 0.0
		WorldState.save_async("activity")


# ------------------------------------------------------------------------------------------------------- restore
## After main has loaded the saved area and placed the mages: everything back where it was, the activities resumed.
func resume() -> void:
	var sc: Dictionary = WorldState.scene
	report = {"loaded": String(WorldState.load_report.get("result", "")) == "loaded", "seq": int(sc.get("seq", 0)),
		"area_saved": String(sc.get("area", "")), "activities": {}, "mages": {}}
	if not report.loaded or sc.is_empty() or RenderProfile.options.has("start") or RenderProfile.options.has("no-resume"):
		report["skipped"] = "no saved scene" if sc.is_empty() else "not loaded / --start / --no-resume"
		resumed_done = true
		resumed.emit(report)
		return
	restoring = true
	var t0 := Time.get_ticks_msec()
	while main.streaming.state != "idle" or main.world == null:
		await get_tree().process_frame
	report["area_now"] = String(main.streaming.current_id)
	_ensure_helpers()
	var area: String = main.streaming.current_id
	# the night look as it was (a test override; the clock itself is WorldState's)
	var dn: Dictionary = sc.get("day_night", {})
	if main.get("day_night") and main.day_night and int(dn.get("override", -1)) >= 0 and int(main.day_night.override) < 0:
		main.day_night.set_override(int(dn.override) == 1)
	var activities: Array = sc.get("activities", [])
	var parts := {}                       # mage -> the activity she is in
	for rec in activities:
		if String(rec.get("area", "")) != area:
			continue
		for p in (rec.get("data", {}) as Dictionary).get("participants", []):
			parts[String(p)] = String(rec.key)
	var mages: Dictionary = sc.get("mages", {})
	for who in mages:
		if main.characters.has(who):
			_restore_mage(who, mages[who], parts, area)
	var due := []
	for rec in activities:
		if String(rec.get("area", "")) == area:
			due.append(rec)
		else:
			_pending.append(rec)
	await _restore_all(due)
	report["ms"] = Time.get_ticks_msec() - t0
	report["pending"] = _pending.map(func(r): return String(r.key))
	restoring = false
	resumed_done = true
	_sig = ""
	print("[resume] scene #%d restored in %d ms: area %s, activities %s%s" % [report.seq, report.ms, area,
		", ".join(report.activities.keys()) if not report.activities.is_empty() else "none",
		(" (pending: %s)" % ", ".join(report.pending)) if not _pending.is_empty() else ""])
	resumed.emit(report)
	if WorldState.persistent:
		WorldState.save_async("resumed")


func _restore_mage(who: String, e: Dictionary, parts: Dictionary, area: String) -> void:
	var c: WorldCharacter = main.characters[who]
	var r := {}
	# her look as it was (only a different, existing model; before any activity builds its pose stack on her)
	var av := String(e.get("avatar", ""))
	if av != "" and av != c.avatar_path and ResourceLoader.exists(av):
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		r["avatar"] = c.swap_avatar(av)
	# her planner: needs and recent decisions back; held while an activity resumes with her in it
	var b = main.mage_brains.get(who)
	var bs: Dictionary = e.get("brain", {})
	if b and not bs.is_empty():
		for k in (bs.get("needs", {}) as Dictionary):
			if b.needs.has(k):
				b.needs[k] = float(bs.needs[k])
		if (b.history as Array).is_empty() and bs.get("history") is Array:
			b.history = (bs.history as Array).duplicate(true)
		if parts.has(who):
			b.interrupt("resuming " + String(parts[who]))
			b.hold = true
			if not bool(bs.get("enabled", true)) and b.enabled:
				b.set_enabled(false)
			r["brain"] = "held (%s)" % ("disabled" if not b.enabled else "enabled")
	# not in an activity: exactly where she stood, facing the same way (main resumed her on the nearest walkable
	# point; this is the saved spot itself when it is that close)
	var pos: Array = e.get("pos", [])
	if not parts.has(who) and bool(e.get("visible", false)) and String(e.get("area", "")) == area and c.visible and pos.size() == 3:
		var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if at.distance_to(c.global_position) < 3.0:
			if main.teleport_guard:
				main.teleport_guard.allow(c)
			c.global_position = at + Vector3(0, 0.02, 0)
			c.velocity = Vector3.ZERO
			r["placed"] = _v3(at)
		if e.has("yaw"):
			c.global_rotation.y = float(e.yaw)
		var ng: Array = e.get("nav_goal", [])
		if String(e.get("action", "")) == "navigate_to" and ng.size() == 3:
			c.navigate_to(Vector3(float(ng[0]), float(ng[1]), float(ng[2])), bool(e.get("nav_run", false)))
			c.set_meta("resumed_walk", true)          # (her brain lets this walk finish before it plans anything new)
			r["walking_to"] = ng
	if parts.has(who):
		c.set_meta("persist_activity", String(parts[who]))
		if main.teleport_guard:
			main.teleport_guard.allow(c)       # the activity places her (a seat in the boat, her mark on the water)
		c.stop_action()
		r["activity"] = parts[who]
	report.mages[who] = r


## All at once (an activity's restore may wait for another's: the ritual waits for the boat to seat its riders), and
## never longer than RESTORE_WAIT_MS: a restore that goes on (a ritual carrying on to its end) is the activity running.
const RESTORE_WAIT_MS := 4000


func _restore_all(due: Array) -> void:
	var st := {"left": due.size()}
	for rec in due:
		_restore_one(rec, st)
	var t1 := Time.get_ticks_msec()
	while int(st.left) > 0 and Time.get_ticks_msec() - t1 < RESTORE_WAIT_MS:
		await get_tree().process_frame


func _restore_one(rec: Dictionary, st: Dictionary) -> void:
	await _restore_activity(rec)
	st.left = int(st.left) - 1


func _restore_activity(rec: Dictionary) -> void:
	var key := String(rec.get("key", ""))
	var data: Dictionary = rec.get("data", {})
	for p in data.get("participants", []):
		var c: WorldCharacter = main.characters.get(String(p))
		if c and main.teleport_guard:
			main.teleport_guard.allow(c)
	var node := _live(key)
	var created := false
	if node == null:
		var path := String(rec.get("script", ""))
		if path == "" or not ResourceLoader.exists(path):
			report.activities[key] = {"ok": false, "why": "no script " + path}
			push_warning("[resume] cannot rebuild %s (no script %s)" % [key, path])
			return
		var scr: Script = load(path)
		var parent: Node = main.world
		if not (String(rec.get("parent", "")) in ["", "."]) and main.world.get_node_or_null(NodePath(String(rec.parent))):
			parent = main.world.get_node(NodePath(String(rec.parent)))
		if _has_method(scr, "persist_spawn"):
			node = scr.call("persist_spawn", parent, data)
		else:
			node = scr.new()
			parent.add_child(node)
		created = true
	if node == null:
		report.activities[key] = {"ok": false, "why": "spawn failed"}
		return
	node.set_meta("persist_area", String(rec.get("area", main.streaming.current_id)))
	var entry := {"ok": true, "created": created, "step": String(rec.get("step", "")), "done": false}
	report.activities[key] = entry
	print("[resume]   %s %s at step '%s'" % [key, "rebuilt" if created else "resuming", rec.get("step", "")])
	await node.call("restore", data)
	if is_instance_valid(node):
		if not node.is_in_group(GROUP):
			node.add_to_group(GROUP)
		entry["after"] = _safe(node.call("snapshot"))     # (the state right after its restore: tests compare it)
	entry["done"] = true


func _live(key: String) -> Node:
	for n in get_tree().get_nodes_in_group(GROUP):
		if is_instance_valid(n) and n.is_inside_tree() and n.has_method("persist_key") and String(n.call("persist_key")) == key:
			return n
	return null


static func _has_method(scr: Script, nm: String) -> bool:
	for m in scr.get_script_method_list():
		if String(m.name) == nm:
			return true
	return false


## An area is about to unload: its live activities are kept (they resume when the area loads again).
func _on_transition_started(_from: String, _to: String) -> void:
	if restoring:
		return
	for n in get_tree().get_nodes_in_group(GROUP):
		var rec := _record(n)
		if rec.is_empty():
			continue
		_pending = _pending.filter(func(r): return String(r.key) != rec.key)
		_pending.append(rec)


func _on_area_activated(area: String, _r = null) -> void:
	_ensure_helpers()
	var due := _pending.filter(func(r): return String(r.area) == area)
	if due.is_empty():
		return
	_pending = _pending.filter(func(r): return String(r.area) != area)
	restoring = true
	await _restore_all(due)
	restoring = false


## Built-in persistent parts of an area: the lake's free lanterns (theirs and the viewers', with the names).
func _ensure_helpers() -> void:
	if main == null or main.world == null:
		return
	for n in main.world.find_children("*", "Node3D", true, false):
		if n.get("free_lanterns") != null and n.get("embedded") != null and n.get_node_or_null("LanternsPersist") == null:
			var h = preload("res://scripts/activities/lake_lanterns_persist.gd").new()
			h.name = "LanternsPersist"
			h.lake = n
			h.area_id = String(main.streaming.current_id)
			n.add_child(h)


# ------------------------------------------------------------------------------------------------------- helpers
static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


static func v3(a) -> Vector3:
	if a is Array and (a as Array).size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.INF


## JSON-safe copy: vectors and colours become arrays, objects are dropped, NaN/INF become null.
static func _safe(v):
	match typeof(v):
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				var x = _safe(v[k])
				if x != null or v[k] == null:
					o[str(k)] = x
			return o
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_safe(x))
			return a
		TYPE_VECTOR3:
			return _v3(v)
		TYPE_VECTOR2:
			return [v.x, v.y]
		TYPE_COLOR:
			return [v.r, v.g, v.b, v.a]
		TYPE_FLOAT:
			return null if is_nan(v) or is_inf(v) else v
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return null
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return String(v)
	return v
