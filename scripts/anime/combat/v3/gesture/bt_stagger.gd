@tool
extends BTAction
## (gesture director) A blow broke her gesture. In the gather it is a stagger, never the small flinch: MagicCaster
## .abort marks her gather as broken and HitReactions raises a flinch to its stagger (one reaction system for every
## blow, so the rig never plays two reactions at once). She is free again when the reaction ends.

func _tick(_delta: float) -> Status:
	var gd: GestureDirector = blackboard.get_var(&"gd")
	var id: String = blackboard.get_var(&"id")
	var e: Dictionary = gd.st[id]
	var s: Dictionary = e.s
	if String(s.state) == "react" and gd.sim.t < float(s.get("until", 0.0)):
		return RUNNING
	e.row.reaction = String(s.get("last_reaction", ""))
	gd.finish(id, "staggered" if bool(e.hit_in_gather) else "broken")
	return SUCCESS
