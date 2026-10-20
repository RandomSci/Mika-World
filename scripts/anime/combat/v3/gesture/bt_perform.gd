@tool
extends BTAction
## (gesture director) The clip starts: blended in over 0.15 s at her own pace, full body or upper body as decided.

func _tick(_delta: float) -> Status:
	var gd: GestureDirector = blackboard.get_var(&"gd")
	var id: String = blackboard.get_var(&"id")
	var e: Dictionary = gd.st[id]
	var opts := {"speed": e.pace, "use": e.use, "fade": GestureDirector.FADE_IN}
	var atk: Dictionary = gd.sim.magic.cast(e.s, e.o, e.name, e.over, opts)
	if atk.is_empty() and String(e.sp.kind) != "barrier":
		gd.finish(id, "refused")
		return FAILURE
	e.atk = atk
	e.t_start = gd.sim.t
	var g: Dictionary = e.g
	var k := float(g.speed) / float(e.pace)          # (her pace stretches the gesture's times)
	e.t_g0 = e.t_start + GestureBook.at(g, float(g.gather[0])) * k
	var rels: Array = []
	for r in g.release:
		rels.append(e.t_start + GestureBook.at(g, float(r)) * k)
	e.t_rel = rels[0]
	e.t_last = rels[rels.size() - 1]
	e.t_end = e.t_start + GestureBook.length(g) * k
	e.row.face_err_at_gather = -1.0
	e.phase = "gather"
	return SUCCESS
