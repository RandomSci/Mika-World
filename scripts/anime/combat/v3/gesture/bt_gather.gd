@tool
extends BTAction
## (gesture director) Until the release frame. A blow that breaks the gesture before the release fails the cast (the
## stagger branch takes over). Records her facing error when the gather starts.

func _tick(_delta: float) -> Status:
	var gd: GestureDirector = blackboard.get_var(&"gd")
	var id: String = blackboard.get_var(&"id")
	var e: Dictionary = gd.st[id]
	var atk: Dictionary = e.get("atk", {})
	if not atk.is_empty() and String(atk.get("outcome", "")) == "interrupted":
		e.hit_in_gather = gd.sim.t >= float(e.t_g0) - 0.05
		e.row.hit_at = snappedf(gd.sim.t - float(e.t_start), 0.01)
		e.phase = "stagger"
		return FAILURE
	if float(e.row.face_err_at_gather) < 0.0 and gd.sim.t >= float(e.t_g0):
		e.row.face_err_at_gather = snappedf(gd.face_error(id), 0.1)
		e.row.feet_at_gather = snappedf(maxf((gd.sim.limb_vel.get(id + ":lf", Vector3.ZERO) as Vector3).length(), (gd.sim.limb_vel.get(id + ":rf", Vector3.ZERO) as Vector3).length()), 0.01)
	if gd.sim.t >= float(e.t_rel) - GestureDirector.AIM_BEFORE:
		e.phase = "release"
		return SUCCESS
	return RUNNING
