class_name PickupAction
extends RefCounted
## Picking something up with the body, not by teleport:
##   face the item -> play Mixamo "Picking Up" (floor or chest height) -> when the bend of the clip brings her
##   shoulder within arm's reach, the right-arm IK reaches the item -> it rides in her palm while she straightens
##   -> it is tucked away at her hip (shrinks into her satchel) -> the arm relaxes.
## Returns true only if the hand really reached it; the caller adds it to her inventory only then.

static func pick(c: WorldCharacter, item: Node3D) -> Dictionary:
	if c == null or item == null or not is_instance_valid(item) or c.casting or c.handler.held != null:
		return {"ok": false, "detail": "hands busy"}
	var tree := c.get_tree()
	c.look_at_point(item.global_position)
	var t0 := Time.get_ticks_msec()
	while c.current_action == "look_at" and Time.get_ticks_msec() - t0 < 1500:
		await tree.process_frame
	c.look_head_at(item.global_position)
	var low := item.global_position.y - c.global_position.y < 0.7
	var clip := "pick_floor" if low else "pick_chest"
	if not c.has_clip(clip):
		clip = "pick_chest" if c.has_clip("pick_chest") else ""
	var length := c.animation_length(clip) if clip != "" else 1.6
	if clip != "":
		c.play_gesture(clip, 0.25, 0.45)
	var t_start := Time.get_ticks_msec()
	var got := false
	var reach_at := -1.0
	while true:
		await tree.process_frame
		if not is_instance_valid(item):
			break
		var t := (Time.get_ticks_msec() - t_start) / 1000.0
		if not got and t > length * 0.22 and c.handler.can_reach(item.global_position):
			got = await c.handler.reach(item.global_position + Vector3(0, 0.03, 0), 0.28)
			reach_at = (Time.get_ticks_msec() - t_start) / 1000.0
		if got and is_instance_valid(item):
			item.global_position = c.handler.palm()        # it rides in her hand while she straightens
		if t > length * (0.72 if got else 0.6):
			break
	if got and is_instance_valid(item):
		# tuck it away at her hip: a short, visible move + shrink (into the satchel)
		var hip := c.global_position + c.global_transform.basis.x * 0.22 + Vector3(0, 0.95, 0)
		var tw := item.create_tween().set_parallel(true)
		tw.tween_property(item, "global_position", hip, 0.35).set_trans(Tween.TRANS_SINE)
		tw.tween_property(item, "scale", Vector3.ONE * 0.05, 0.35)
		await tw.finished
	await c.handler.relax(0.4)
	c.look_head_at(null)
	return {"ok": got, "clip": clip, "reach_at_s": snappedf(reach_at, 0.01), "detail": "picked it up" if got else "could not reach it"}
