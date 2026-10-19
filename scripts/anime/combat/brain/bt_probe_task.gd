@tool
extends BTAction
## (LimboAI probe) counts its ticks on the blackboard and succeeds on the third.

func _tick(_delta: float) -> Status:
	var n: int = blackboard.get_var(&"ticks", 0) + 1
	blackboard.set_var(&"ticks", n)
	return SUCCESS if n >= 3 else RUNNING
