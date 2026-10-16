class_name TfContinuity
extends RefCounted
## Continuity across a transformation (TransformationSequence): the moment before it starts is saved - for BOTH
## characters their exact transform, visibility, seated / lying state, the activity they were doing (their brain's
## running choice), the area, and the camera (the live camera's transform and lens, the camera director's framing) -
## and the moment it ends everything is put back exactly: she stands (or sits) in that very spot in the same area in
## her new outfit and resumes what she was doing; the other character never moves; nobody is sent to a spawn point.

var area := ""
var chars := {}            # who -> {pos, basis, visible, seated, lying, physics, choice, activity}
var cam: Camera3D
var cam_xf := Transform3D.IDENTITY
var cam_fov := 50.0
var director := {}         # camera director fields
var director_enabled := false
var rig_state := {}       # the third-person camera rig (its shot, focus, yaw / pitch, arm length)


static func capture(main: Node) -> TfContinuity:
	var s := TfContinuity.new()
	s.area = String(main.streaming.current_id) if main.get("streaming") else ""
	for who in main.characters:
		var c: WorldCharacter = main.characters[who]
		var b = main.mage_brains.get(who)
		s.chars[who] = {
			"pos": c.global_position, "basis": c.global_transform.basis, "visible": c.visible, "seated": c.seated,
			"lying": bool(c.get("lying")) if c.get("lying") != null else false,
			"physics": c.is_physics_processing(),
			"choice": (b.last_choice as Dictionary).duplicate(true) if b and b.get("last_choice") != null and b.busy and not (b.current as Dictionary).is_empty() else {},
			"activity": (b.current as Dictionary).duplicate(true) if b else {}}
	s.cam = main.get_viewport().get_camera_3d()
	if s.cam:
		s.cam_xf = s.cam.global_transform
		s.cam_fov = s.cam.fov
	var d = main.get("director")
	if d:
		s.director_enabled = bool(d.enabled)
		# every script variable of the camera director (its framing, its subject, its shot timers)
		for pr in (d as Object).get_property_list():
			if int(pr.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and String(pr.name) != "enabled":
				var v = d.get(pr.name)
				if v is Dictionary or v is Array:
					v = v.duplicate()
				s.director[String(pr.name)] = v
		var rig = d.get("rig")
		if rig:
			s.rig_state = s._vars(rig)
			if rig.get("arm"):
				s.rig_state["__arm_length"] = float(rig.arm.spring_length)
			if rig.get("camera"):
				s.rig_state["__cam_top_level"] = bool(rig.camera.top_level)
	return s


func _vars(o: Object) -> Dictionary:
	var out := {}
	for pr in o.get_property_list():
		if int(pr.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v = o.get(pr.name)
			if v is Dictionary or v is Array:
				v = v.duplicate()
			out[String(pr.name)] = v
	return out


func _freeze_rig(d: Object, on: bool) -> void:
	var rig = d.get("rig") if d else null
	if rig == null:
		return
	(rig as Node).set_process(not on)
	(rig as Node).set_physics_process(not on)
	var arm = rig.get("arm")
	if arm:
		(arm as Node).set_physics_process_internal(not on)


func _put_rig(d: Object) -> void:
	var rig = d.get("rig") if d else null
	if rig == null or rig_state.is_empty():
		return
	for k in rig_state:
		if not String(k).begins_with("__"):
			rig.set(k, rig_state[k])
	if rig_state.has("__arm_length") and rig.get("arm"):
		rig.arm.spring_length = float(rig_state["__arm_length"])
	if rig_state.has("__cam_top_level") and rig.get("camera"):
		rig.camera.top_level = bool(rig_state["__cam_top_level"])


## Holds both characters still where they are (no walking, no new decisions) while the sequence plays.
func freeze(main: Node) -> void:
	for who in chars:
		var c: WorldCharacter = main.characters[who]
		c.set_move_input(Vector3.ZERO, false)
		c.set_physics_process(false)
		var b = main.mage_brains.get(who)
		if b:
			b.hold = true
			b.interrupt("transformation")


## Everything back exactly as it was; each brain resumes the activity it was in the middle of. The camera is put
## back exactly; with hold_camera everyone and the camera stay exactly so (the restored moment holds while the flash
## clears) until release_camera().
func restore(main: Node, transformed: WorldCharacter, hold_camera := false) -> Dictionary:
	var report := {"area_before": area, "area_after": String(main.streaming.current_id) if main.get("streaming") else "", "chars": {}}
	for who in chars:
		var c: WorldCharacter = main.characters[who]
		var st: Dictionary = chars[who]
		if main.get("teleport_guard") and main.teleport_guard:
			main.teleport_guard.allow(c)
		c.global_position = st.pos
		c.global_transform.basis = st.basis
		c.visible = st.visible
		if not hold_camera:
			c.set_physics_process(bool(st.physics))
		if bool(st.seated) and not c.seated:
			c.set_seated(true, 0.05)
		elif bool(st.lying) and c.has_method("lie_down"):
			c.lie_down(0.05)
		var b = main.mage_brains.get(who)
		if b and not hold_camera:
			if not (st.choice as Dictionary).is_empty() and b.get("resume_next") != null:
				b.resume_next = st.choice
			b.hold = false
		report.chars[who] = {"pos_error": snappedf(c.global_position.distance_to(st.pos), 0.001), "resumes": String((st.activity as Dictionary).get("label", ""))}
	if cam and is_instance_valid(cam):
		cam.global_transform = cam_xf
		cam.fov = cam_fov
		cam.make_current()
	var d = main.get("director")
	if d:
		for k in director:
			d.set(k, director[k])
		d.enabled = director_enabled
		for k in director:
			d.set(k, director[k])          # (re-enabling it may have reset its mode)
		_put_rig(d)
		if hold_camera:
			d.set_process(false)           # paused, not disabled: disabling it would drop the rig's shot
			_freeze_rig(d, true)           # the rig and its spring arm too: the restored frame holds exactly
	if cam and is_instance_valid(cam):
		cam.global_transform = cam_xf
	report["camera_error"] = snappedf(cam.global_position.distance_to(cam_xf.origin), 0.001) if cam and is_instance_valid(cam) else -1.0
	return report


## Everyone moves on: both characters take up what they were doing and the camera director takes over again
## (from exactly the framing it had before).
func release_camera(main: Node) -> void:
	for who in chars:
		var c: WorldCharacter = main.characters[who]
		var st: Dictionary = chars[who]
		c.set_physics_process(bool(st.physics))
		var b = main.mage_brains.get(who)
		if b:
			if not (st.choice as Dictionary).is_empty() and b.get("resume_next") != null:
				b.resume_next = st.choice
			b.hold = false
	var d = main.get("director")
	if d:
		for k in director:
			d.set(k, director[k])
		_put_rig(d)
		_freeze_rig(d, false)
		d.set_process(true)
