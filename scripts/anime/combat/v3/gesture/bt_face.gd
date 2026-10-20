@tool
extends BTAction
## (gesture director) She turns until her facing is within 15 deg of where the releasing hand must point (the
## opponent, turned by the gesture's aim), before anything else; at most 0.4 s.

var _t := 0.0

func _enter() -> void:
	_t = 0.0
	var gd: GestureDirector = blackboard.get_var(&"gd")
	var id: String = blackboard.get_var(&"id")
	gd.sim.d.F[id].yaw_extra = -deg_to_rad(float(gd.st[id].g.get("aim", 0.0)))


func _tick(delta: float) -> Status:
	var gd: GestureDirector = blackboard.get_var(&"gd")
	var id: String = blackboard.get_var(&"id")
	_t += delta
	if String(gd.st[id].s.state) in ["react", "down"]:
		gd.finish(id, "broken before the gather")       # (a blow while she turned or planted: no cast)
		return FAILURE
	var err := gd.face_error(id)
	var ult := bool(gd.st[id].sp.get("ultimate", false))       # (an ultimate turns during its eyes close up)
	if ult or err <= GestureDirector.FACE_DEG or _t >= GestureDirector.FACE_WAIT:
		gd.st[id].row.face_wait = snappedf(_t, 0.01)
		gd.st[id].phase = "plant"
		return SUCCESS
	return RUNNING
