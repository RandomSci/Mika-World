@tool
extends BTAction
## (gesture director) Moving: the gesture goes to her upper body only (the rig keeps her legs walking). Standing: her
## feet settle (both under 5 cm/s) before the gather; at most 0.3 s.

var _t := 0.0

func _enter() -> void:
	_t = 0.0


func _tick(delta: float) -> Status:
	var gd: GestureDirector = blackboard.get_var(&"gd")
	var id: String = blackboard.get_var(&"id")
	var e: Dictionary = gd.st[id]
	_t += delta
	if String(e.s.state) in ["react", "down"]:
		gd.finish(id, "broken before the gather")       # (a blow while she turned or planted: no cast)
		return FAILURE
	var moving := float(gd.speed.get(id, 0.0)) > GestureDirector.MOVING
	if bool(e.sp.get("ultimate", false)):
		e.row.moving = moving
		e.phase = "perform"
		return SUCCESS                          # (an ultimate keeps its camera timeline: no wait)
	if moving:
		e.use = "upper"
		e.row.moving = true
		e.phase = "perform"
		return SUCCESS
	var lf: Vector3 = gd.sim.limb_vel.get(id + ":lf", Vector3.ZERO)
	var rf: Vector3 = gd.sim.limb_vel.get(id + ":rf", Vector3.ZERO)
	if (lf.length() < 0.05 and rf.length() < 0.05) or _t >= GestureDirector.PLANT_WAIT:
		e.row.plant_wait = snappedf(_t, 0.01)
		e.row.feet_at_plant = snappedf(maxf(lf.length(), rf.length()), 0.01)
		e.row.moving = false
		e.phase = "perform"
		return SUCCESS
	return RUNNING
