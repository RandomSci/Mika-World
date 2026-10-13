class_name StreamContext
extends RefCounted
## The honest stream state the mages (and the overlays / bridge) may use. In this DEV build there is NO
## livestream connection: mode is "dev", live is false, and viewer comments only come from DEV inputs
## (bridge "chat", F9, tests). Nothing here pretends an audience exists.

static func describe(main: Node) -> Dictionary:
	var cam := main.get_viewport().get_camera_3d()
	var pending := {}
	if main.chat:
		for e in main.chat.queue:
			pending[String(e.get("to", "general"))] = int(pending.get(String(e.get("to", "general")), 0)) + 1
	var avail := {}
	for who in main.mages:
		avail[who] = main.chat._safe_point(who) if main.chat else false
	return {"mode": "dev", "live": false, "chat_source": "dev inputs only (bridge / F9 / tests)", "followed": String(main.focus),
		"pending_comments": pending, "available_to_answer": avail,
		"camera": [snappedf(cam.global_position.x, 0.1), snappedf(cam.global_position.y, 0.1), snappedf(cam.global_position.z, 0.1)] if cam else []}
