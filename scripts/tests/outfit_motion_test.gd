extends Node
## --outfitmotion: one outfit, in the real world, through the moves she makes on stream. Run once per look:
##   --outfit-who=mika|luna --outfit-stage=<appearance stage id>
##   --outfitmotion=<dir>      writes <dir>/<tag>_motion.json (+ the movie, when run with --write-movie)
##   --motion-perf             real-time pass: frame times only (no per-frame measuring, which costs CPU)
## Moves: idle, walk, turn around while walking, run, run and turn, stop, cast a real spell, weapon (draw, hold,
## walk with it, two attacks, sheathe), sit on the ground, lie down and get up. Wide/medium follow camera only.
## Per phase it measures (final pose, springs included - read in skeleton_updated):
##  * cloth through legs/body: the loose cloth (skirt, gown, dress, coat, cape, wings) skinned on the CPU every 3rd
##    frame, against tapered capsules of her own legs and torso fitted to her body mesh; depth beyond the rest pose
##  * spring bones per chain: jitter (2nd difference of the tip in hips space), stretch (tip to chain root vs rest,
##    explosion), amplitude (stiff when nearly rigid while she moves), NaN
##  * weapon: grip to palm distance, weapon vertices inside her body capsules
##  * feet: height above the ground vs her standing calibration, sliding of the planted foot
## Changes no progress.

const CLOTH := ["Skirt", "Gown", "Dress", "Coat", "Cape", "Wing", "Robe", "Cloak", "Train", "Tail", "Lining"]
const CLIP_CM := 1.0           # cloth deeper than this into her (beyond its rest depth) counts as clipping
## Her body as tapered capsules [bone a, bone b, radius at a, radius at b] in cm: the median distance of the body-mesh
## vertices each bone drives, fitted on the full body of her L1 outfit (later outfits' body meshes have the parts under
## leggings and boots removed, so a per-outfit fit is unreliable). Same skeleton and body for every look of a mage.
const BODY := {
	"mika": [["LeftUpperLeg", "LeftLowerLeg", 7.2, 4.6], ["RightUpperLeg", "RightLowerLeg", 7.3, 4.6], ["LeftLowerLeg", "LeftFoot", 3.9, 2.8],
		["RightLowerLeg", "RightFoot", 3.9, 2.8], ["Hips", "Spine", 9.2, 9.2], ["Spine", "Chest", 8.8, 8.8], ["Chest", "UpperChest", 8.8, 8.8], ["UpperChest", "Neck", 10.0, 5.0]],
	"luna": [["LeftUpperLeg", "LeftLowerLeg", 7.6, 4.6], ["RightUpperLeg", "RightLowerLeg", 7.5, 4.6], ["LeftLowerLeg", "LeftFoot", 3.9, 2.9],
		["RightLowerLeg", "RightFoot", 3.9, 2.9], ["Hips", "Spine", 9.4, 9.4], ["Spine", "Chest", 9.0, 9.0], ["Chest", "UpperChest", 9.2, 9.2], ["UpperChest", "Neck", 10.5, 3.8]],
}

var main: Node
var m: WorldCharacter
var sk: Skeleton3D
var dir := ""
var tag := ""
var perf := false
var phase := "setup"
var phases := []               # [{name, frame0, frame1, t0, t1}]
var rep := {}
var frame := 0
var _cam_off := Vector3.ZERO
var _cam_look_y := 0.9
var _cam_dist := 3.8
var _cam_pos := Vector3.ZERO
var _cam_init := false
var _home := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _ground := {}              # foot bone -> ground y under it (physics frame)
var _bone := {}                # name -> index
# cloth
var _cloth := []               # [{name, mi, idx: PackedInt32Array (subsampled vertices), v: PackedVector3Array, bones, weights, nw, bind_bone: PackedInt32Array, bind_pose: Array, rest_depth: PackedFloat32Array}]
var _caps := []                # [{name, a, b, ra, rb}] (bone indices + radii)
var _calibrated := false
var _foot_calib := {}
# per-phase accumulators
var acc := {}
var _tips := {}                # chain -> [tip bone, root bone, rest_len]
var _prev_tip := {}            # tip bone -> [p(t-1), p(t-2)]
var _frame_ms: Array[float] = []
var _last_us := 0
var _gpu_ms: Array[float] = []
var _phase_ms := {}


func _ready() -> void:
	dir = String(RenderProfile.options.get("outfitmotion", "user://outfitmotion"))
	if not dir.begins_with("/") and not dir.contains("://"):
		dir = "user://" + dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir) if dir.contains("://") else dir)
	perf = RenderProfile.options.has("motion-perf")
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _phase(name: String) -> void:
	var f := Engine.get_process_frames()
	if not phases.is_empty():
		phases[-1]["frame1"] = f
		phases[-1]["t1"] = Time.get_ticks_msec() / 1000.0
	phase = name
	phases.append({"name": name, "frame0": f, "t0": Time.get_ticks_msec() / 1000.0})
	print("[motion] phase %s frame %d" % [name, f])


# ------------------------------------------------------------------------------------------------ camera
func _process(_d: float) -> void:
	if m == null:
		return
	var now := Time.get_ticks_usec()
	if _last_us > 0 and phase != "setup" and phase != "done":
		_frame_ms.append((now - _last_us) / 1000.0)
		_phase_ms.get_or_add(phase, []).append((now - _last_us) / 1000.0)
		_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	_last_us = now
	if _cam_off == Vector3.ZERO:
		return
	var rig: ThirdPersonCamera = main.camera_rig
	var look := m.global_position + Vector3(0, _cam_look_y, 0)
	var want := m.global_position + _cam_off.normalized() * _cam_dist + Vector3(0, 0.55, 0)
	_cam_pos = want if not _cam_init else _cam_pos.lerp(want, 0.08)
	_cam_init = true
	rig.set_shot(_cam_pos, look, 42.0)      # 3.8 m at 42 deg: the frame is 2.9 m tall, her face (~23 cm) under 8%


# ------------------------------------------------------------------------------------------------ setup
func _run() -> void:
	var who := String(RenderProfile.options.get("outfit-who", "mika"))
	var other := "luna" if who == "mika" else "mika"
	m = main.characters[who]
	main.player.enabled = false
	for w in main.mage_brains:
		main.mage_brains[w].hold = true
	for w in main.mage_brains:
		var t0 := Time.get_ticks_msec()
		while not main.mage_brains[w].current.is_empty() and Time.get_ticks_msec() - t0 < 30000:
			await get_tree().process_frame
	main.hud.visible = false
	main.prompt.visible = false
	if main.get("overlay_ui"):
		main.overlay_ui.visible = false
	for k in ["brain", "duel", "companionship", "attention", "impacts", "mage_talk", "performance", "director"]:
		var n: Node = main.get(k)
		if n:
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var o: WorldCharacter = main.characters.get(other)
	var spot: Vector3 = (main.characters.mika as WorldCharacter).global_position
	if o:
		o.global_position = spot + Vector3(40, 0, 40)
		o.visible = false
		o.process_mode = Node.PROCESS_MODE_DISABLED
	var want := String(RenderProfile.options.get("outfit-stage", ""))
	if want != "":
		AppearanceRegistry.preview(who, want)
		m.swap_avatar(AppearanceRegistry.avatar_for(who))
	m.global_position = spot
	m.velocity = Vector3.ZERO
	tag = "%s_%s" % [who, String(AppearanceRegistry.stage_for_avatar(who, m.avatar_path).get("id", "base"))]
	sk = m.skeleton
	for i in sk.get_bone_count():
		_bone[sk.get_bone_name(i)] = i
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	rep = {"who": who, "stage": AppearanceRegistry.stage_for_avatar(who, m.avatar_path).get("id", ""), "avatar": m.avatar_path.get_file(),
		"mode": "perf" if perf else "measure", "weapon": {}}
	await _wait(2.0)
	_home = m.global_position
	_fwd = _open_direction(14.0)
	m.rotation.y = atan2(-_fwd.x, -_fwd.z)
	var side := _fwd.cross(Vector3.UP).normalized()
	_cam_off = side * 0.85 + _fwd * 0.55
	_set_tips()
	if not perf:
		sk.skeleton_updated.connect(_on_pose)
	await _wait(2.5)
	if not perf:
		_calibrate()
	await _moves()
	_phase("done")
	_write()
	print("[motion] done ", tag)
	get_tree().quit()


func _open_direction(dist: float) -> Vector3:
	var space := m.get_world_3d().direct_space_state
	var best := -m.global_transform.basis.z
	var best_d := -1.0
	for k in 24:
		var a := k * TAU / 24.0
		var d := Vector3(sin(a), 0, cos(a))
		var free := dist
		for s in [-1.0, 1.0]:                     # both directions (she walks out and back)
			for h in [0.4, 1.2]:
				var q := PhysicsRayQueryParameters3D.create(m.global_position + Vector3(0, h, 0), m.global_position + Vector3(0, h, 0) + d * dist * s)
				q.exclude = [m.get_rid()]
				var r := space.intersect_ray(q)
				if not r.is_empty():
					free = minf(free, (r.position - q.from).length() * (1.0 if s > 0 else 2.0))
		for s2 in [-1.0, 1.0]:
			var h0 := _ground_at(m.global_position)
			for k2 in range(1, int(dist * (1.0 if s2 > 0 else 0.6))):
				if absf(_ground_at(m.global_position + d * k2 * s2) - h0) > 0.06:
					free = minf(free, k2 * (1.0 if s2 > 0 else 1.6))
					break
		if free > best_d:
			best_d = free
			best = d
	rep["open_m"] = snappedf(best_d, 0.1)
	return best


func _ground_at(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.0, 0), p - Vector3(0, 3.0, 0))
	q.exclude = [m.get_rid()]
	var r := m.get_world_3d().direct_space_state.intersect_ray(q)
	return (r.position as Vector3).y if not r.is_empty() else -100.0


# ------------------------------------------------------------------------------------------------ the moves
func _moves() -> void:
	_phase("settle")
	await _wait(2.5)
	_phase("idle")
	await _wait(3.0)
	_phase("walk")
	m.set_move_input(_fwd, false)
	await _wait(3.0)
	_phase("turn_walk")
	m.set_move_input(-_fwd, false)
	await _wait(3.2)
	_phase("run")
	m.set_move_input(_fwd, true)
	await _wait(1.4)
	_phase("turn_run")
	m.set_move_input(-_fwd, true)
	await _wait(1.6)
	_phase("stop")
	m.set_move_input(Vector3.ZERO, false)
	await _wait(1.6)
	# a real spell (the stream's magic system); the spoken incantation is off (--no-voice)
	_phase("cast")
	var cast := {}
	for s in main.magic.known_spells(m.character_id):
		if s.castable:
			cast = await main.magic.cast(m, String(s.id))
			if cast.get("ok", false):
				break
	if not cast.get("ok", false):
		m.play_gesture("spell_casting", 0.25, 0.4)
	rep["cast"] = {"spell": cast.get("spell", "gesture spell_casting"), "ok": cast.get("ok", false), "clip": cast.get("clip", "")}
	var tc := Time.get_ticks_msec()
	await _wait(1.0)
	while m.casting and Time.get_ticks_msec() - tc < 9000:
		await get_tree().process_frame
	await _wait(1.0)
	# her weapon
	if m.sword and m.sword.available:
		rep.weapon["id"] = m.sword.weapon_id
		var lw := m.sword.blade_root.get_node_or_null("LookWeapon")
		rep.weapon["model"] = String(AppearanceRegistry.stage_for_avatar(m.character_id, m.avatar_path).get("profile", {}).get("weapon", {}).get("model", "")).get_file() if lw else "procedural magic blade (no permanent weapon at this form)"
		_phase("weapon_draw")
		await m.sword.draw()
		await _wait(1.2)
		_phase("weapon_hold")
		await _wait(2.0)
		_phase("weapon_walk")
		m.set_move_input(_fwd, false)
		await _wait(2.4)
		m.set_move_input(-_fwd, false)
		await _wait(2.4)
		m.set_move_input(Vector3.ZERO, false)
		await _wait(0.8)
		_phase("weapon_attack")
		await m.sword.attack()
		await _wait(0.3)
		await m.sword.attack()
		await _wait(1.0)
		_phase("weapon_sheathe")
		m.sword.sheathe()
		await _wait(1.2)
	else:
		rep.weapon["model"] = "no weapon layer"
	await _wait(0.5)
	# sit on the ground (as when she listens to the rain), then lie down and get up
	_cam_dist = 3.4
	_cam_look_y = 0.6
	_phase("sit_down")
	m.play_gesture("sit_ground_enter", 0.3, 0.3)
	m.set_ground_pose("sit", m.animation_length("sit_ground_enter") * 0.9)
	await _wait(m.animation_length("sit_ground_enter") * 0.85)
	m.play_gesture("sit_ground_loop", 0.3, 0.6)
	_phase("sit")
	await _wait(3.0)
	_phase("sit_up")
	m.end_gesture()
	m.play_gesture("sit_ground_exit", 0.2, 0.4)
	m.set_ground_pose("", m.animation_length("sit_ground_exit") * 0.9)
	await _wait(m.animation_length("sit_ground_exit") + 0.4)
	_cam_look_y = 0.4
	_phase("lie_down")
	await m.lie_down()
	_phase("lie")
	await _wait(3.0)
	_phase("get_up")
	_cam_look_y = 0.7
	await m.get_up()
	_cam_look_y = 0.9
	_cam_dist = 3.8
	# a winged form flies: take off, hover, fly out over the sanctuary and back, land
	if m.flight:
		await _wait(1.0)
		_cam_dist = 7.5
		_cam_look_y = 1.2
		_phase("fly_takeoff")
		var r1: Dictionary = await m.flight.take_off(4.0)
		_phase("fly_hover")
		await _wait(2.5)
		_phase("fly_out")
		var r2: Dictionary = await m.flight.fly_to(_home + _fwd * 16.0)     # over the ruins and down on the far side
		_phase("fly_back")
		var r3: Dictionary = await m.flight.fly_to(_home + _fwd.cross(Vector3.UP) * 1.5)
		_phase("fly_landed")
		rep["flight"] = {"take_off": r1, "out": r2, "back": r3, "metres": snappedf(m.flight.flown_m, 0.1)}
		await _wait(1.5)
		_cam_dist = 3.8
		_cam_look_y = 0.9
	_phase("settle_end")
	await _wait(3.0)
	_phase("still_end")
	await _wait(3.0)


# ------------------------------------------------------------------------------------------------ measuring
func _set_tips() -> void:
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		if not nm.begins_with("J_Sec_") or not sk.get_bone_children(i).is_empty():
			continue
		var chain := nm.trim_prefix("J_Sec_").trim_suffix("_end").rstrip("0123456789_")
		var root := i
		while sk.get_bone_parent(root) >= 0 and sk.get_bone_name(sk.get_bone_parent(root)).begins_with("J_Sec_"):
			root = sk.get_bone_parent(root)
		var rl := (sk.get_bone_global_rest(i).origin - sk.get_bone_global_rest(root).origin).length()
		if rl < 0.01:
			continue
		_tips.get_or_add(chain, []).append([i, root, rl])


func _mesh_name_cloth(n: String) -> bool:
	for c in CLOTH:
		if n.contains(c):
			return true
	return false


## Body capsules fitted to her body mesh (median distance of the vertices each bone drives, at both ends), and the
## loose cloth meshes with their rest depth (a waistband sits on her hips by design: only depth beyond that counts).
func _calibrate() -> void:
	for b in BODY.get(m.character_id, BODY.mika):
		if _bone.has(b[0]) and _bone.has(b[1]):
			_caps.append({"name": "%s-%s" % [b[0], b[1]], "a": _bone[b[0]], "b": _bone[b[1]], "ra": b[2] / 100.0, "rb": b[3] / 100.0})
	rep["capsules_cm"] = _caps.map(func(c): return [c.name, snappedf(c.ra * 100, 0.1), snappedf(c.rb * 100, 0.1)])
	# loose cloth
	for mi in m.avatar.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if not _mesh_name_cloth(nm) or mi.mesh == null or mi.skin == null:
			continue
		var arr := (mi as MeshInstance3D).mesh.surface_get_arrays(0)
		var n := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var step := maxi(1, n / 1500)
		var c := _cloth_entry(mi, step)
		var rest := PackedFloat32Array()
		var pts := _skin(c)
		for p in pts:
			rest.append(_depth(p)[0])
		c["rest_depth"] = rest
		_cloth.append(c)
	rep["cloth_meshes"] = _cloth.map(func(c): return "%s (%d of %d verts)" % [c.name, c.v.size(), c.total])
	# feet: standing height of each foot bone above the ground
	for f in ["LeftFoot", "RightFoot"]:
		if _bone.has(f) and _ground.has(f):
			_foot_calib[f] = (sk.global_transform * sk.get_bone_global_pose(_bone[f]).origin).y - float(_ground[f])
	rep["foot_standing_height_cm"] = _foot_calib.keys().map(func(k): return [k, snappedf(_foot_calib[k] * 100, 0.1)])
	_calibrated = true


func _cloth_entry(mi: MeshInstance3D, step: int) -> Dictionary:
	var arr := mi.mesh.surface_get_arrays(0)
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var B: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var W: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var nw := B.size() / maxi(V.size(), 1)
	var v := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var dom := PackedInt32Array()
	for k in range(0, V.size(), step):
		v.append(V[k])
		var best := 0
		for j in nw:
			bones.append(B[k * nw + j])
			weights.append(W[k * nw + j])
			if W[k * nw + j] > W[k * nw + best]:
				best = j
		dom.append(B[k * nw + best])
	var sn := mi.skin
	var bind_bone := PackedInt32Array()
	var bind_pose := []
	for i in sn.get_bind_count():
		var bb := sn.get_bind_bone(i)
		if bb < 0:
			bb = sk.find_bone(sn.get_bind_name(i))
		bind_bone.append(bb)
		bind_pose.append(sn.get_bind_pose(i))
	for k in dom.size():
		dom[k] = bind_bone[dom[k]]
	return {"name": String(mi.name), "mi": mi, "v": v, "bones": bones, "weights": weights, "nw": nw, "bind_bone": bind_bone, "bind_pose": bind_pose, "dom": dom, "total": V.size()}


## Skeleton-space positions of the entry's vertices in the current (final) pose.
func _skin(c: Dictionary) -> PackedVector3Array:
	var bx := []
	for i in c.bind_bone.size():
		bx.append(sk.get_bone_global_pose(c.bind_bone[i]) * (c.bind_pose[i] as Transform3D) if c.bind_bone[i] >= 0 else Transform3D.IDENTITY)
	var out := PackedVector3Array()
	out.resize(c.v.size())
	var nw: int = c.nw
	var V: PackedVector3Array = c.v
	var B: PackedInt32Array = c.bones
	var W: PackedFloat32Array = c.weights
	for k in V.size():
		var p := Vector3.ZERO
		for j in nw:
			var w := W[k * nw + j]
			if w > 0.0:
				p += ((bx[B[k * nw + j]] as Transform3D) * V[k]) * w
		out[k] = p
	return out


func _skin_all(mi: MeshInstance3D, step: int) -> Dictionary:
	var c := _cloth_entry(mi, step)
	return {"p": _skin(c), "dom": c.dom}


## Deepest capsule penetration of a skeleton-space point: [depth m (negative = outside), capsule name].
func _depth(p: Vector3, skip := -1) -> Array:
	var best := -1.0
	var bn := ""
	for c in _caps:
		if c.a == skip:
			continue
		var pa := sk.get_bone_global_pose(c.a).origin
		var pb := sk.get_bone_global_pose(c.b).origin
		var ab := pb - pa
		var t := clampf((p - pa).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var r: float = lerpf(c.ra, c.rb, t)
		var d := r - p.distance_to(pa + ab * t)
		if d > best:
			best = d
			bn = c.name
	return [best, bn]


func _A() -> Dictionary:
	return acc.get_or_add(phase, {"frames": 0, "clip_samples": 0, "clip_frames": 0, "clip_max_cm": 0.0, "clip_where": "", "clip_verts_max": 0,
		"tips": {}, "nan": 0, "grip_cm": [], "wpn_inside_frames": 0, "wpn_max_cm": 0.0, "wpn_where": "", "feet": [], "root_ground_cm": []})


func _physics_process(_d: float) -> void:
	if m == null or sk == null or perf:
		return
	var space := m.get_world_3d().direct_space_state
	for f in ["LeftFoot", "RightFoot"]:
		if not _bone.has(f):
			continue
		var p := sk.global_transform * sk.get_bone_global_pose(_bone[f]).origin
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p - Vector3(0, 2.0, 0))
		q.exclude = [m.get_rid()]
		var r := space.intersect_ray(q)
		if not r.is_empty():
			_ground[f] = r.position.y
	var q2 := PhysicsRayQueryParameters3D.create(m.global_position + Vector3(0, 1.0, 0), m.global_position - Vector3(0, 2.0, 0))
	q2.exclude = [m.get_rid()]
	var r2 := space.intersect_ray(q2)
	if not r2.is_empty():
		_ground["root"] = r2.position.y


func _on_pose() -> void:
	if not _calibrated or phase in ["setup", "done"]:
		return
	frame += 1
	var A := _A()
	A.frames += 1
	var hips := sk.get_bone_global_pose(_bone.get("Hips", 0))
	var hinv := hips.affine_inverse()
	# springs
	for chain in _tips:
		var T: Dictionary = A.tips.get_or_add(chain, {"hf": 0.0, "n": 0, "stretch_max": 0.0, "sum": Vector3.ZERO, "sum2": 0.0, "cnt": 0, "spikes": 0})
		for tp in _tips[chain]:
			var gp := sk.get_bone_global_pose(tp[0]).origin
			if not gp.is_finite():
				A.nan += 1
				continue
			var p := hinv * gp
			var st := (gp - sk.get_bone_global_pose(tp[1]).origin).length() / float(tp[2])
			T.stretch_max = maxf(T.stretch_max, st)
			var pv: Array = _prev_tip.get(tp[0], [])
			if pv.size() >= 1:
				T.speed_max = maxf(float(T.get("speed_max", 0.0)), (p - (pv[0] as Vector3)).length() / maxf(get_process_delta_time(), 1e-4))
			if pv.size() == 2:
				var h := (p - (pv[0] as Vector3) * 2.0 + (pv[1] as Vector3)).length()
				T.hf += h * h
				T.n += 1
				if h > 0.03:
					T.spikes += 1
			_prev_tip[tp[0]] = [p, pv[0] if pv.size() > 0 else p]
			# amplitude: per tip mean/var in hips space (sum of squares around the running per-tip mean is kept simple:
			# the variance of the chain's tips is the spread of p minus its per-tip mean -> store per tip)
			var key: int = tp[0]
			var S: Dictionary = T.get_or_add("per", {})
			var e: Array = S.get_or_add(key, [Vector3.ZERO, 0.0, 0])
			e[0] = (e[0] as Vector3) + p
			e[1] = float(e[1]) + p.length_squared()
			e[2] = int(e[2]) + 1
	# feet + root on the ground
	for f in _foot_calib:
		if _ground.has(f):
			var p := sk.global_transform * sk.get_bone_global_pose(_bone[f]).origin
			A.feet.append([f, p.x, p.y - float(_ground[f]) - float(_foot_calib[f]), p.z, get_process_delta_time()])
	A.get_or_add("speed", []).append(Vector2(m.velocity.x, m.velocity.z).length())
	if _ground.has("root"):
		A.root_ground_cm.append((m.global_position.y - float(_ground.root)) * 100.0)
	# weapon
	var sw := m.sword
	if sw and sw.drawn and sw.blade_root and sw.blade_root.visible:
		var palm := sk.get_bone_global_pose(_bone["RightHand"]).origin
		if _bone.has("RightMiddleProximal"):
			palm = palm.lerp(sk.get_bone_global_pose(_bone["RightMiddleProximal"]).origin, 0.5)
		var lw: Node3D = sw.blade_root.get_node_or_null("LookWeapon")
		var gx: Transform3D = sk.global_transform.affine_inverse() * (lw.global_transform if lw else sw.blade_root.global_transform)
		var ga := gx * (Vector3(0, -0.09, 0) if lw else Vector3(0, -0.12, 0))
		var gb := gx * (Vector3(0, 0.09, 0) if lw else Vector3(0, 0.14, 0))
		if sw.blade_root.get_parent() == m.right_hand:
			A.grip_cm.append(palm.distance_to(Geometry3D.get_closest_point_to_segment(palm, ga, gb)) * 100.0)
		if frame % 3 == 0:
			var worst := 0.0
			var where := ""
			for mi in sw.blade_root.find_children("*", "MeshInstance3D", true, false):
				if not mi.is_visible_in_tree() or mi.mesh == null:
					continue
				var vv: PackedVector3Array = (mi as MeshInstance3D).mesh.get_faces()
				var stp := maxi(3, (vv.size() / 300) * 3)
				var xf: Transform3D = sk.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
				for k in range(0, vv.size(), stp):
					var d := _depth(xf * vv[k])
					if d[0] > worst:
						worst = d[0]
						where = d[1]
			if worst * 100.0 > CLIP_CM:
				A.wpn_inside_frames += 1
				if worst * 100.0 > A.wpn_max_cm:
					A.wpn_max_cm = snappedf(worst * 100.0, 0.1)
					A.wpn_where = where
	# cloth (every 3rd frame)
	if frame % 3 == 0 and not _cloth.is_empty():
		A.clip_samples += 1
		var any := false
		var nverts := 0
		for c in _cloth:
			var pts := _skin(c)
			var rd: PackedFloat32Array = c.rest_depth
			for k in pts.size():
				var d := _depth(pts[k])
				var pen: float = (float(d[0]) - maxf(rd[k], 0.0)) * 100.0
				if pen > CLIP_CM:
					any = true
					nverts += 1
					if pen > A.clip_max_cm:
						A.clip_max_cm = snappedf(pen, 0.1)
						A.clip_where = "%s into %s" % [c.name, d[1]]
		if any:
			A.clip_frames += 1
			A.clip_verts_max = maxi(A.clip_verts_max, nverts)


# ------------------------------------------------------------------------------------------------ report
func _write() -> void:
	var out := {}
	for ph in phases:
		var nm: String = ph.name
		if nm == "done":
			continue
		var r := {"frames": [ph.frame0, ph.get("frame1", ph.frame0)], "seconds": snappedf(float(ph.get("t1", ph.t0)) - float(ph.t0), 0.01)}
		if acc.has(nm):
			var A: Dictionary = acc[nm]
			r["clip"] = {"pct_frames": snappedf(100.0 * A.clip_frames / maxf(A.clip_samples, 1), 0.1), "max_cm": A.clip_max_cm, "where": A.clip_where, "verts_max": A.clip_verts_max}
			var springs := {}
			for chain in A.tips:
				var T: Dictionary = A.tips[chain]
				var amp := 0.0
				for key in T.get("per", {}):
					var e: Array = T.per[key]
					var n := maxf(float(e[2]), 1.0)
					var mean: Vector3 = e[0] / n
					amp = maxf(amp, sqrt(maxf(float(e[1]) / n - mean.length_squared(), 0.0)))
				springs[chain] = {"jitter_mm": snappedf(sqrt(T.hf / maxf(T.n, 1)) * 1000.0, 0.01), "spikes_over_3cm": T.spikes,
					"stretch_max": snappedf(T.stretch_max, 0.01), "tip_speed_max_m_s": snappedf(float(T.get("speed_max", 0.0)), 0.01), "amplitude_mm": snappedf(amp * 1000.0, 0.1)}
			r["springs"] = springs
			r["nan"] = A.nan
			if not A.grip_cm.is_empty():
				r["grip_to_palm_cm"] = {"mean": snappedf(A.grip_cm.reduce(func(a, b): return a + b, 0.0) / A.grip_cm.size(), 0.1), "max": snappedf(A.grip_cm.max(), 0.1)}
			if A.has("wpn_inside_frames") and (A.wpn_inside_frames > 0 or not A.grip_cm.is_empty()):
				r["weapon_in_body"] = {"frames": A.wpn_inside_frames, "max_cm": A.wpn_max_cm, "where": A.wpn_where}
			r["feet"] = _feet(A.feet)
			r["body_speed_m_s"] = snappedf(_median(A.get("speed", [])), 0.01)
			if not A.root_ground_cm.is_empty():
				r["root_above_ground_cm"] = {"min": snappedf(A.root_ground_cm.min(), 0.1), "max": snappedf(A.root_ground_cm.max(), 0.1)}
		out[nm] = r
	rep["phases"] = out
	if not _frame_ms.is_empty():
		var s := _frame_ms.duplicate()
		s.sort()
		var g := _gpu_ms.duplicate()
		g.sort()
		var tot: float = _frame_ms.reduce(func(a, b): return a + b, 0.0)
		rep["perf"] = {"avg_fps": snappedf(_frame_ms.size() / (tot / 1000.0), 0.1), "frame_ms_p50": snappedf(s[s.size() / 2], 0.1),
			"frame_ms_p99": snappedf(s[int(s.size() * 0.99)], 0.1), "frame_ms_max": snappedf(s[-1], 0.1), "frames_over_50ms": s.filter(func(x): return x > 50.0).size(),
			"gpu_ms_p50": snappedf(g[g.size() / 2], 0.01), "gpu_ms_p99": snappedf(g[int(g.size() * 0.99)], 0.01), "max_fps_cap": Engine.max_fps,
			"vsync": DisplayServer.window_get_vsync_mode(), "primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
	if rep.has("perf"):
		var pp := {}
		for k in _phase_ms:
			var a: Array = _phase_ms[k]
			pp[k] = {"fps": snappedf(a.size() / maxf(a.reduce(func(x, y): return x + y, 0.0) / 1000.0, 0.001), 0.1), "max_ms": snappedf(a.max(), 0.1)}
		rep.perf["by_phase"] = pp
	var path := "%s/%s_%s.json" % [dir, tag, "perf" if perf else "motion"]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	print("[motion] wrote ", path)


func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


## Height of each foot over the ground vs her standing calibration (+ = floating, - = sunk), and sliding: the
## horizontal speed of a foot while it is planted (within 2.5 cm of its lowest height in this phase).
func _feet(rows: Array) -> Dictionary:
	var out := {}
	for f in ["LeftFoot", "RightFoot"]:
		var r := rows.filter(func(x): return x[0] == f)
		if r.size() < 4:
			continue
		var hs: Array = r.map(func(x): return float(x[2]))
		var lo: float = hs.min()
		var slide := []
		for k in range(1, r.size()):
			if float(r[k][2]) < lo + 0.012 and float(r[k - 1][2]) < lo + 0.012:
				slide.append(Vector2(r[k][1] - r[k - 1][1], r[k][3] - r[k - 1][3]).length() / maxf(float(r[k][4]), 1e-4))
		hs.sort()
		out[f] = {"lowest_cm": snappedf(lo * 100, 0.1), "median_cm": snappedf(float(hs[hs.size() / 2]) * 100, 0.1),
			"planted_slide_m_s": snappedf(_median(slide), 0.01), "planted_frames": slide.size()}
	return out
