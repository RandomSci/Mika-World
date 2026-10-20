@tool
extends BTAction
## (gesture director) Round the release frame Godot's AimModifier3D turns her casting arm toward the target (in over
## 0.15 s, out over 0.25 s after the last release). The aim error is measured at the release.

func _tick(_delta: float) -> Status:
	var gd: GestureDirector = blackboard.get_var(&"gd")
	var id: String = blackboard.get_var(&"id")
	var e: Dictionary = gd.st[id]
	var atk: Dictionary = e.get("atk", {})
	if not atk.is_empty() and String(atk.get("outcome", "")) == "interrupted":
		gd.set_aim(id, 0.0)
		e.row.hit_at = snappedf(gd.sim.t - float(e.t_start), 0.01)
		e.phase = "stagger"
		return FAILURE
	var t: float = gd.sim.t
	var w := 0.0
	if t < float(e.t_rel):
		w = clampf(1.0 - (float(e.t_rel) - t) / GestureDirector.AIM_BEFORE, 0.0, 1.0)
	elif t <= float(e.t_last):
		w = 1.0
	else:
		w = clampf(1.0 - (t - float(e.t_last)) / GestureDirector.AIM_AFTER, 0.0, 1.0)
	gd.set_aim(id, w)
	if not e.row.has("aim_err") and t >= float(e.t_rel):
		e.row.aim_err = snappedf(gd.aim_error(id), 0.1)
		e.row.aim_need = float(e.g.get("aim", 0.0))
	if t >= float(e.t_last) + GestureDirector.AIM_AFTER:
		gd.set_aim(id, 0.0)
		e.phase = "recover"
		return SUCCESS
	return RUNNING
