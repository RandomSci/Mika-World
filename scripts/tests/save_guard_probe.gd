extends SceneTree
## The 23 Oct 01:45 incident, replayed: `godot --headless --path . --script res://scripts/tests/save_guard_probe.gd`
## (no flags) loads every autoload, WorldState among them. Then the worst a careless test can do: switch saving on by
## hand and save. The save guard must refuse both (tools: ~/.cache/mika_qa/tools/save_guard_proof.sh, which runs this
## against a throwaway copy of the user folder and checks the copied save's hash).

var _frames := 0


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 30:
		var ws = root.get_node_or_null("WorldState")
		if ws == null:
			print("[guardprobe] no WorldState autoload")
			quit(2)
			return true
		print("[guardprobe] stage_run=%s persistent=%s save_path=%s loaded=%s" % [str(ws.stage_run), str(ws.persistent), ws.save_path, str(ws.load_report)])
		ws.persistent = true                      # what a careless test could do
		ws.world_min += 600.0
		var ok: bool = ws.save_game("guard probe")
		print("[guardprobe] save_game returned %s, last_save %s" % [str(ok), str(ws.last_save)])
		quit(0)
	return false
