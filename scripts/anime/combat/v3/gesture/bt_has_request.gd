@tool
extends BTCondition
## (gesture director) A cast is waiting for her body.

func _tick(_delta: float) -> Status:
	var gd: GestureDirector = blackboard.get_var(&"gd")
	var id: String = blackboard.get_var(&"id")
	return SUCCESS if gd.st.has(id) and String(gd.st[id].phase) == "face" else FAILURE
