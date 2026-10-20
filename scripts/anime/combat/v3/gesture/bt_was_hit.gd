@tool
extends BTCondition
## (gesture director) Her gesture was broken by a blow.

func _tick(_delta: float) -> Status:
	var gd: GestureDirector = blackboard.get_var(&"gd")
	var id: String = blackboard.get_var(&"id")
	return SUCCESS if gd.st.has(id) and String(gd.st[id].phase) == "stagger" else FAILURE
