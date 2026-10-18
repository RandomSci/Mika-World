extends RefCounted
## Shared by the kill/resume tests (persist_boat.gd, persist_dance.gd; not a test mode itself).
## Phase 1 sets an activity going, records the TRUTH (the live state at the very frame each save snapshot is taken:
## ScenePersist.captured) into <save>_truth.json, prints "READY_FOR_KILL" once a save that holds the running activity
## has reached the disk, and then keeps running until the shell kills it (SIGKILL: no clean shutdown, no save on
## exit). Phase 2 starts a new process on the same save and compares what came back with the truth of the snapshot
## that was actually loaded (by its seq).
## Options: --persist-phase=1|2 (default: 2 if a save was loaded), --persist-shots=<absolute dir> (GPU stills).


static func phase() -> String:
	return String(RenderProfile.options.get("persist-phase", "2" if String(WorldState.load_report.get("result", "")) == "loaded" else "1"))


static func truth_path() -> String:
	return WorldState.save_path.trim_suffix(".json") + "_truth.json"


## Atomic like the save (temp -> rename): a kill mid-write keeps the previous truth.
static func write_truth(entries: Dictionary) -> void:
	var tmp := truth_path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(entries))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(truth_path()))


static func read_truth() -> Dictionary:
	var txt := FileAccess.get_file_as_string(truth_path())
	var d = JSON.parse_string(txt) if txt != "" else null
	return d if d is Dictionary else {}


## Keep the newest 8 entries (by seq).
static func add_truth(entries: Dictionary, e: Dictionary) -> void:
	entries[str(int(e.seq))] = e
	var ks := entries.keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	while ks.size() > 8:
		entries.erase(ks.pop_front())
	write_truth(entries)


static func still(t, tag: String) -> String:
	var dir := String(RenderProfile.options.get("persist-shots", ""))
	if dir == "" or DisplayServer.get_name() == "headless":
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var img: Image = t.get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [dir, String(RenderProfile.options.get("mktest", "persist")), tag]
	if img and img.save_png(path) == OK:
		print("[persist] still: ", path)
		return path
	return ""


## The stream's overlays out of the stills; the framing guard off for the pinned test camera; the camera pinned.
static func pin_camera(t) -> CameraPin:
	var main: Node = t.main
	for cl in t.get_tree().root.find_children("*", "CanvasLayer", true, false):
		if not (cl is ScreenFX) and not (cl is MVPost):
			(cl as CanvasLayer).visible = false
	if main.get("hud") and main.hud:
		main.hud.visible = false
	for g in t.get_tree().root.find_children("FramingGuard", "", true, false):
		(g as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	pin.fov = 40.0
	pin.active = true
	return pin


static func find_lake(main: Node) -> Node3D:
	for n in main.world.find_children("*", "Node3D", true, false) + [main.world]:
		if n.get("water_mat") != null:
			return n
	return null


static func level_xp(who: String) -> Dictionary:
	var m := WorldState.mind(who)
	return {"level": m.level(), "xp": snappedf(float(m.progress.get("xp", 0.0)), 0.01)}


## Phase 1's ending: wait (the shell's SIGKILL ends the process). Never returns normally within the test's time.
static func await_kill(t, seconds := 900.0) -> void:
	print("[persist] READY_FOR_KILL save=%s last_save=%s" % [ProjectSettings.globalize_path(WorldState.save_path), JSON.stringify(WorldState.last_save)])
	await t._wait(seconds)
	t._check(false, "phase 1 was not killed (the shell must kill it after READY_FOR_KILL)")


## The world clock now vs the truth: the saved minutes + the catch-up for the time the game was closed + the time
## this process has run since (a game clock at WorldState.clock_rate).
static func clock_ok(truth_min: float) -> Dictionary:
	var ran_s := maxf(Time.get_ticks_msec() / 1000.0, Engine.get_process_frames() / 30.0)   # (movie mode: game time per frame)
	var expect := truth_min + float(WorldState.clock_catch_up.get("world_min", 0.0))
	var diff := WorldState.world_min - expect
	return {"ok": diff >= -1.0 and diff <= ran_s * WorldState.clock_rate * WorldState.clock_boost + 1.0, "now": snappedf(WorldState.world_min, 0.01),
		"saved": snappedf(truth_min, 0.01), "catch_up": WorldState.clock_catch_up, "diff_min": snappedf(diff, 0.01), "clock": WorldState.clock_text()}
