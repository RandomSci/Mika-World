class_name ShotAudit
extends Node
## The in-game half of the video quality check (Selwyn, 24 Oct: "create a subsystem to check the videos you created
## and its goal is quality"). With --shot-audit=<file.csv> it writes what the camera really shows, ten times a second
## of game time, after every camera script (FramingGuard included): Mika's head and feet inside the picture, how big
## her face is (FramingRule's face fraction; the whole-body rule wants it small), whether something solid hides her
## head, how far the lens is, whether the lens sits in a keep-out, Luna in the picture, the director's mode and the
## frame number (the movie writer's frame = the video frame). tools/qa/video_qa.py reads it beside the video.

const EVERY_S := 0.1

var path := ""
var _f: FileAccess
var _t := 0.0
var main: Node


func setup(m: Node, p: String) -> void:
	main = m
	path = p
	process_priority = 100001                # after FramingGuard (100000): the picture as it really is
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f:
		_f.store_line("frame,t,mode,mika_in,head_in,feet_in,face_frac,hidden,lens_dist,in_keepout,luna_in,streaming")
	print("[shotaudit] writing %s" % path)


func _process(delta: float) -> void:
	if _f == null or main == null:
		return
	_t += delta
	if _t < EVERY_S:
		return
	_t = 0.0
	var cam := get_viewport().get_camera_3d()
	var mika: WorldCharacter = main.characters.get("mika") if main.get("characters") else null
	if cam == null or mika == null:
		return
	var feet := mika.global_position + Vector3(0, 0.05, 0)
	var head := feet + Vector3(0, 1.55, 0)
	var sk := mika.skeleton
	if sk and sk.find_bone("Head") >= 0:
		head = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin + Vector3(0, 0.12, 0)
	var head_in := mika.visible and not cam.is_position_behind(head) and cam.is_position_in_frustum(head)
	var feet_in := mika.visible and not cam.is_position_behind(feet) and cam.is_position_in_frustum(feet)
	var space := mika.get_world_3d().direct_space_state
	var hidden := false
	if head_in:
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, head, CameraDirector.LOS)
		var ex: Array[RID] = []
		for c in main.characters.values():
			if c is CollisionObject3D:
				ex.append((c as CollisionObject3D).get_rid())
		q.exclude = ex
		var hit := space.intersect_ray(q)
		hidden = not hit.is_empty() and (hit.position as Vector3).distance_to(head) > 0.4
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = cam.global_position
	pq.collision_mask = ThirdPersonCamera.LENS_ONLY
	var in_ko := not space.intersect_point(pq, 1).is_empty()
	var luna: WorldCharacter = main.characters.get("luna")
	var luna_in := luna != null and luna.visible and cam.is_position_in_frustum(luna.global_position + Vector3(0, 1.0, 0))
	var mode := String(main.director.mode) if main.get("director") and main.director else ""
	var st := String(main.streaming.state) if main.get("streaming") and main.streaming else ""
	_f.store_line("%d,%.2f,%s,%d,%d,%d,%.3f,%d,%.2f,%d,%d,%s" % [Engine.get_frames_drawn(), Time.get_ticks_msec() / 1000.0, mode,
		int(mika.visible), int(head_in), int(feet_in), FramingRule.face_frac(cam.global_position, head, cam.fov), int(hidden),
		cam.global_position.distance_to(head), int(in_ko), int(luna_in), st])


func _exit_tree() -> void:
	if _f:
		_f.flush()
		_f = null
