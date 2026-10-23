extends RefCounted
## --mktest=waysidemask (2026-10-23 live log: 5339 "Out of bounds" errors in Wayside._terrain_mask each time a road
## stretch was built without a terrain cache): after the wayside's precompute returns, its masks must be filled.
## Run with --no-terrain-cache so the slow path is the one tested.

static func run(t) -> void:
	var w = load("res://scenes/areas/wayside.tscn").instantiate()
	t.main.add_child(w)
	w.setup("wayside")
	await w._precompute()
	var want: int = w._n * w._n
	print("[waysidemask] n %d, trail %d, hidden %d, heights %d (want %d each)" % [w._n, w._trail_mask.size(),
		w._hidden_mask.size(), w._hgrid.size(), want])
	print("[waysidemask] %s" % ("PASS masks filled before the ground is built" if want > 0 and w._trail_mask.size() == want and w._hidden_mask.size() == want else "FAIL masks empty"))
	w.queue_free()
