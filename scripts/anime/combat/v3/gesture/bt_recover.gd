@tool
extends BTAction
## (gesture director) The clip plays out; MagicCaster hands her back to the rig over 0.2 s at its end.

func _tick(_delta: float) -> Status:
	var gd: GestureDirector = blackboard.get_var(&"gd")
	var id: String = blackboard.get_var(&"id")
	var e: Dictionary = gd.st[id]
	if gd.sim.t >= float(e.t_end):
		gd.finish(id, "done")
		return SUCCESS
	return RUNNING
