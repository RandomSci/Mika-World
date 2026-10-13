class_name PersistTest
extends Node
## --persisttest=<mode>: regression tests for state that must survive restarts. Driven by
## tools/run_regression.sh (each mode is its own Godot process; restart = a new process).
##   integrity  save rotation, unreadable/newer saves, shrink guard, journal "seq" cursor + legacy migration
##   npc1       persistent session: a traveller arrives, Mika talks with her, state is saved
##   npc2       restart: the saved conversation state loads and the next conversation runs (the generic-beat
##              path that used to fail with "Invalid operands 'float' and 'int' in operator '%'")
##   llm        ONE real API call (needs --llm-real) to confirm the DEV key + model work; never prints the key
##   realcopy   a COPY of the real save (made by the runner) loads, migrates, saves and reloads intact
##   trials     the four trials the planner could not reach: each one is completed by running an option the
##              planner itself generated (no direct interactable calls, no granted completions)
## Only disposable saves named user://test_regress_*.json are touched; the real save is never opened.
## Prints "[persisttest] PASS <mode>" or "[persisttest] FAIL <mode>: ..." and exits 0 / 1.

const PREFIX := "user://test_regress_"

var main: Node
var mode := ""
var checks: Array = []
var failed := false


func _ready() -> void:
	mode = String(RenderProfile.options.get("persisttest", ""))
	_run.call_deferred()


func _check(ok: bool, what: String, detail = "") -> void:
	checks.append({"ok": ok, "check": what, "detail": str(detail).left(300)})
	print("[persisttest]   %s %s %s" % ["ok  " if ok else "FAIL", what, ("(" + str(detail).left(200) + ")") if str(detail) != "" else ""])
	if not ok:
		failed = true


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	print("[persisttest] mode=%s save_path=%s persistent=%s" % [mode, WorldState.save_path, WorldState.persistent])
	if WorldState.save_path == WorldState.SAVE_PATH or not WorldState.save_path.begins_with(PREFIX):
		_check(false, "refusing to run: save path must be a disposable %s*.json file" % PREFIX, WorldState.save_path)
		_finish()
		return
	match mode:
		"integrity": _integrity()
		"npc1": await _npc(1)
		"npc2": await _npc(2)
		"trials": await _trials()
		"llm": await _llm_once()
		"realcopy": _realcopy()
		_: _check(false, "unknown mode '%s'" % mode)
	_finish()


func _finish() -> void:
	var dir := RenderProfile.shots_dir + "/persisttest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open("%s/%s.json" % [dir, mode], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"mode": mode, "passed": not failed, "checks": checks}, "  "))
		f.close()
	print("[persisttest] %s %s%s" % ["FAIL" if failed else "PASS", mode, (": %d failed check(s)" % checks.filter(func(c): return not c.ok).size()) if failed else ""])
	get_tree().quit(1 if failed else 0)


# ------------------------------------------------------------------ helpers
func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _clean(base: String) -> void:
	var d := DirAccess.open("user://")
	for fn in d.get_files():
		if fn.begins_with(base.trim_prefix("user://")):
			d.remove(fn)


func _use_save(name: String) -> void:
	WorldState.save_path = PREFIX + name + ".json"
	_clean(WorldState._base())
	WorldState._last_rotation = -1e12
	WorldState._loaded_floor = {}


func _reset_state() -> void:
	WorldState.knowledge = {}
	WorldState.trials_done = {}
	WorldState.discovered_locations = {WorldState.registry.start_location: true}
	WorldState.activity_log.clear()
	WorldState.activity_seq = 0


# ------------------------------------------------------------------ integrity
func _integrity() -> void:
	WorldState.persistent = true
	var keep_state := WorldState.save_data()   # restored at the end (this process never saves for real anyway)

	# 1. round trip + verified write
	_use_save("roundtrip")
	_reset_state()
	WorldState.knowledge["lore:test"] = 1
	WorldState.record_activity({"id": "test:a"}, {"knowledge": {"fact:a": 1}})
	_check(WorldState.save_game(), "save_game writes a verified file")
	WorldState.knowledge = {}
	_check(WorldState.load_game() and WorldState.knowledge.has("fact:a"), "load_game restores what was saved", WorldState.load_report)

	# 2. rotation: once per interval, older backups shift down
	var first := _text(WorldState.save_path)
	WorldState.knowledge["fact:b"] = 1
	WorldState.save_game()
	_check(_text(WorldState._backup_path(1)) == first, "first save of a session rotates the previous save into .bak1")
	var bak1 := _text(WorldState._backup_path(1))
	WorldState.knowledge["fact:c"] = 1
	WorldState.save_game()
	_check(_text(WorldState._backup_path(1)) == bak1 and not FileAccess.file_exists(WorldState._backup_path(2)), "autosaves inside the interval do not churn backups")
	WorldState._last_rotation = -1e12
	var before_third := _text(WorldState.save_path)
	WorldState.knowledge["fact:d"] = 1
	WorldState.save_game()
	_check(_text(WorldState._backup_path(1)) == before_third and _text(WorldState._backup_path(2)) == bak1, "after the interval: .bak1 -> .bak2, current -> .bak1")

	# 3. unreadable save: preserved, newest readable backup restored, nothing lost
	var good := _text(WorldState._backup_path(1))
	_write(WorldState.save_path, "{\"version\": 1, \"knowledge\": {trunc")
	WorldState.knowledge = {}
	var ok := WorldState.load_game()
	var kept := String(WorldState.load_report.get("preserved_as", ""))
	_check(ok and WorldState.load_report.get("restored_from", "") == WorldState._backup_path(1), "corrupt save -> restored from .bak1", WorldState.load_report)
	_check(kept != "" and _text(kept).begins_with("{\"version\": 1, \"knowledge\": {trunc"), "the unreadable file is preserved byte for byte", kept)
	_check(_text(WorldState.save_path) == good and WorldState.knowledge.has("fact:a"), "the save now holds the backup's progress")

	# 4. unreadable save and no backups: start fresh but keep the bad file
	_use_save("nobackup")
	_write(WorldState.save_path, "not json")
	var r4 := WorldState.load_game()
	_check(not r4 and _text(String(WorldState.load_report.get("preserved_as", ""))) == "not json", "no backup: nothing loaded, bad file kept", WorldState.load_report)

	# 5. a save from a newer version is never overwritten
	_use_save("newer")
	var newer := JSON.stringify({"version": WorldState.SAVE_VERSION + 1, "knowledge": {"future": 1}})
	_write(WorldState.save_path, newer)
	WorldState.load_game()
	_check(not WorldState.persistent, "newer save disables saving for the session", WorldState.load_report)
	WorldState._process(5.0)   # the autosave tick must not write
	_check(_text(WorldState.save_path) == newer, "newer save left untouched")
	WorldState.persistent = true

	# 6. shrink guard: an accidental reset must not overwrite real progress
	_use_save("shrink")
	_reset_state()
	for i in 10:
		WorldState.knowledge["lore:%d" % i] = 1
	WorldState.save_game()
	WorldState.load_game()
	var on_disk := _text(WorldState.save_path)
	WorldState.knowledge = {"lore:0": 1}
	_check(not WorldState.save_game() and _text(WorldState.save_path) == on_disk, "save refused when knowledge would shrink 10 -> 1")
	WorldState._loaded_floor = {}

	# 7. journal: the cursor is a sequence number, valid after trimming and restarts
	_use_save("journal")
	_reset_state()
	for i in 260:
		WorldState.record_activity({"id": "read:liber_orbis:%d" % (i % 3), "verb": "read", "label": "x"}, {})
	var e1 := Journal.compose()
	WorldState.knowledge["journal"] = [{"heading": e1.heading, "text": e1.text}]
	WorldState.knowledge["journal_cursor"] = e1.cursor
	_check(int(e1.cursor) == 260, "cursor = seq of the last event considered", e1.cursor)
	WorldState.save_game()
	WorldState.activity_log.clear()
	WorldState.activity_seq = 0
	WorldState.load_game()
	_check(WorldState.activity_log.size() == 200 and WorldState.activity_seq == 260, "save keeps 200 entries, seq survives the restart", [WorldState.activity_log.size(), WorldState.activity_seq])
	_check(Journal.compose().is_empty(), "nothing new to write right after the restart")
	WorldState.record_activity({"id": "alchemy_luminous_draught", "verb": "craft", "label": "Brewed"}, {})
	var e2 := Journal.compose()
	_check(not e2.is_empty() and String(e2.text).contains("Luminous Draught") and int(e2.cursor) == 261, "a new event after the restart is journaled", e2)

	# 8. legacy save (no "seq"): position cursor keeps its meaning; a cursor past a trimmed log is clamped
	_use_save("legacy")
	var log := []
	for i in 56:
		log.append({"t": i, "location": "", "activity": {"id": "talk:x:%d" % i} if i != 50 else {"id": "alchemy_fizz"}, "changes": {}})
	var legacy := {"version": 1, "discovered_locations": {}, "visited_locations": {}, "seen_landmarks": {}, "inventory": {}, "skills": {}, "trials_done": {},
		"knowledge": {"journal_cursor": 45.0, "journal": []}, "activity_log": log}
	_write(WorldState.save_path, JSON.stringify(legacy))
	WorldState.load_game()
	var e3 := Journal.compose()
	_check(WorldState.activity_seq == 56 and int(WorldState.knowledge.journal_cursor) == 45 and String(e3.get("text", "")).contains("fizzed"),
		"legacy save: entries numbered by position, cursor 45 still means 'entries after 45'", [WorldState.activity_seq, WorldState.knowledge.journal_cursor, e3])
	legacy.knowledge.journal_cursor = 350.0
	_write(WorldState.save_path, JSON.stringify(legacy))
	WorldState.load_game()
	_check(int(WorldState.knowledge.journal_cursor) == 56, "legacy cursor beyond a trimmed log is clamped (journal resumes)", WorldState.knowledge.journal_cursor)

	for n in ["roundtrip", "nobackup", "newer", "shrink", "journal", "legacy"]:
		_clean(PREFIX + n)
	WorldState._apply_save(keep_state)
	WorldState.persistent = false


# ------------------------------------------------------------------ NPC conversation across a restart
func _npc(phase: int) -> void:
	_check(WorldState.persistent, "running persistently (--persist)")
	var id := "wandering_mage"
	if phase == 2:
		_check(WorldState.load_report.get("result", "") == "loaded", "restart loaded the saved session", WorldState.load_report)
		var raw = WorldState.npc_state.get(id, {}).get("conversations")
		_check(raw != null, "saved conversation state present", raw)
		_check(typeof(raw) == TYPE_FLOAT, "JSON reload yields a float counter (the condition that used to break)", type_string(typeof(raw)))
		var st: Dictionary = main.dialogue.state_of(id)
		_check(typeof(st.conversations) == TYPE_INT and st.conversations >= 1 and st.met, "state_of normalises the counter to int", st.conversations)
	await _wait(3.0)
	var npc: TravelerNPC = main.npcs.arrive(id)
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(npc) and npc.state != "idle" and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	_check(is_instance_valid(npc) and npc.state == "idle", "traveller arrived")
	var mika: WorldCharacter = main.characters["mika"]
	mika.global_position = npc.global_position + npc.global_transform.basis.z * 1.8
	await get_tree().physics_frame
	if phase == 2:
		var beats: Array = main.dialogue.choose_beats(id, npc)
		var generic := beats.filter(func(b): return (b.when as Dictionary).is_empty())
		_check(not generic.is_empty(), "the generic-beat (modulo) path is exercised", beats.map(func(b): return b.id))
	var r: Dictionary = await main.dialogue.converse(id, mika)
	_check(r.get("ok", false) and (r.get("lines", []) as Array).size() >= 2, "conversation %d ran" % phase, r.get("detail", r.get("lines", [])))
	var conv := int(main.dialogue.state_of(id).conversations)
	_check(conv == phase, "conversation counter = %d" % phase, conv)
	_check(WorldState.save_game(), "state saved")


# ------------------------------------------------------------------ trials through the planner
func _trials() -> void:
	var brain: SanctuaryBrain = main.brain
	var need := {"attune_circle": "ritual_circle_attune", "heartstone": "heartstone_attune", "watch": "watchpoint_survey", "strike_targets": "rune_target_"}
	_reset_state()
	# before she has read about them, attunements are not offered (discovery constraint)
	var keys := brain.options().map(func(o): return o.key)
	_check(not keys.has("attune:ritual_circle_attune") and not keys.has("attune:heartstone_attune"), "attunements hidden until she has read about them")
	# what reading the scroll and the chamber tablet would have taught her
	WorldState.knowledge["read:scroll_first_circle"] = [0]
	WorldState.knowledge["read:chamber_tablet"] = [0]
	await _wait(2.0)
	for k in 12:
		var open := need.keys().filter(func(t): return not WorldState.trials_done.has(t))
		if open.is_empty():
			break
		var opts := brain.ranked()
		var pick := {}
		for o in opts:
			if o.kind == "attune" and o.interactable in ["ritual_circle_attune", "heartstone_attune"] and brain._advances_trial(o.interactable):
				pick = o
			elif o.kind == "magic" and String(o.target).begins_with("rune_target_") and o.get("trial", false) and o.spell == "arcane_orb":
				pick = o
			elif o.kind == "explore" and o.sub_area == "watchpoint" and not WorldState.knowledge.has("survey:realm"):
				pick = o
			if not pick.is_empty():
				break
		if pick.is_empty():
			_check(false, "planner offers an option for the open trials", open)
			return
		_check(pick.get("why", []).any(func(w): return String(w).contains("trial")) or pick.kind == "explore", "option scored with its trial reason: %s" % pick.label, pick.get("why", []))
		var res: Dictionary = await brain.run_activity(pick)
		print("[persisttest]   ran %s -> ok=%s %s" % [pick.key, res.get("ok", false), str(res.get("detail", "")).left(100)])
		await _wait(1.0)
	for t in need:
		_check(WorldState.trials_done.has(t), "trial '%s' completed through planner activities" % t, WorldState.mission_state().trials.filter(func(x): return x.id == t))
	var struck: Dictionary = WorldState._prefix_counts.get("rune_target_", {})
	_check(struck.size() >= 4, "four distinct rune targets really struck", struck.keys())


# ------------------------------------------------------------------ one bounded API call
func _llm_once() -> void:
	var llm: LLMClient = main.llm
	print("[persisttest]   llm status: ", llm.status)
	_check(llm.provider == "openai", "real provider active (DEV .env + .env.dev)", llm.describe().status)
	if llm.provider != "openai":
		return
	var r: Dictionary = await llm.ask_json("Reply as JSON {\"ok\": true, \"word\": string} with one fantasy word.", "ping", {"ok": false, "word": "mock"})
	_check(r.provider == "openai", "answer came from the API (not the mock fallback)", r.provider)
	_check(r.json.get("ok", false) == true and String(r.json.get("word", "")) != "", "answer parsed as the requested JSON", r.json)
	_check(llm.stats.real_calls == 1, "exactly one real call made", llm.stats)


# ------------------------------------------------------------------ a copy of the real save
func _realcopy() -> void:
	var r := WorldState.load_report
	_check(r.get("result", "") == "loaded", "copy of the real save loads", r)
	var before := {"knowledge": WorldState.knowledge.size(), "trials": WorldState.trials_done.size(), "discovered": WorldState.discovered_locations.size(),
		"npcs": WorldState.npc_state.size(), "story": String(WorldState.story_state.get("stage", "")), "skills": WorldState.skills.duplicate(),
		"journal": (WorldState.knowledge.get("journal", []) as Array).size()}
	print("[persisttest]   loaded: ", JSON.stringify(before))
	_check(WorldState.activity_seq == WorldState.activity_log.size() and int(WorldState.knowledge.get("journal_cursor", 0)) <= WorldState.activity_seq,
		"legacy activity log migrated to seq numbers", [WorldState.activity_seq, WorldState.knowledge.get("journal_cursor")])
	for id in WorldState.npc_state:
		var st: Dictionary = main.dialogue.state_of(id)
		_check(typeof(st.conversations) == TYPE_INT and typeof(st.visits) == TYPE_INT, "npc %s counters are ints" % id, [st.visits, st.conversations])
	WorldState.persistent = true
	_check(WorldState.save_game(), "migrated copy saves")
	WorldState.knowledge = {}
	WorldState.load_game()
	var after := {"knowledge": WorldState.knowledge.size(), "trials": WorldState.trials_done.size(), "discovered": WorldState.discovered_locations.size(),
		"npcs": WorldState.npc_state.size(), "story": String(WorldState.story_state.get("stage", "")), "skills": WorldState.skills.duplicate(),
		"journal": (WorldState.knowledge.get("journal", []) as Array).size()}
	_check(JSON.stringify(after) == JSON.stringify(before), "memories, trials, discoveries, NPC relations, story and skills identical after save + reload", after)
	WorldState.persistent = false
