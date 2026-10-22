class_name FightDirector
extends Node
## The duel and the training fights between Mika and Luna, staged like an anime MV (2026-10-19).
## The REFEREE (FightPlan) decides what happens - who attacks, whether a blow lands, is blocked or dodged, who wins -
## from the two mages' levels and a seeded roll. The director then STAGES each exchange from a beat library
## (scripts/anime/duel/fight_moves.gd): Mixamo/UAL fighting and casting clips on her skeleton (FightDeck) with the
## softness pass (BodyLife + SoftArms), her magic (FightFX: Mika's ice-blue stars, Luna's violet moons), the impact
## feel (hit-stop freeze frames, camera shake, white flash frames, speed lines only on big hits, sparks and debris,
## slow motion on the finisher) and the camera: a Phantom Camera shot list cut on the hits (close-up -> wide ->
## close-up, orbits, profile two-shots, overhead, crash zooms, whip pans, dutch roll), no shot longer than ~4 s.
## mode "duel": serious, ends with a winner, then both react (a hand up, a high five). mode "training": friendly
## sparring, lighter effects, touches instead of damage, teasing and laughs. Both earn XP (FightXP).

signal finished(result: Dictionary)

const LANE := 4.4                         # metres between them at their marks
const ARENA_R := 3.4                      # they never leave this radius round the centre (the rune targets stand at 5 m)

var main: Node
var mode := "duel"
var lane := LANE                          # (the spell duel: wider, its spells cross a bigger space)
var arena_r := ARENA_R
var opts := {}
var _spell: SpellBeats
var F := {}                               # id -> fighter {id, c, deck, reach, other, hp, touches, pos, yaw_k, look}
var fx: FightFX
var sfx: ScreenFX
var post: MVPost
var center := Vector3.ZERO
var axis := Vector3.RIGHT                 # unit, from Mika's mark toward Luna's
var side := 1.0                           # the camera's home side of the lane (180-degree rule)
var plan: Array = []
var result := {}
var intensity := 1.0                      # training: 0.65 (lighter effects, fewer flashes)
var ft := 0.0                             # fight clock (world time: hit-stop stops it, slow motion slows it)
var real_t := 0.0                         # frames / 30
var frame := 0
var done := false
var cam_log: Array = []                   # [real t, fight t, kind, who] per cut (QA: shot lengths)
var hit_log: Array = []                   # [fight t, kind, who, power]
var rng := RandomNumberGenerator.new()

var _ev: Array = []                       # [t, seq, Callable] sorted
var _seq := 0
var _shots: Array = []                    # [t, kind, who, opts]
var _shot_i := -1
var _shot: Array = []
var _shot_t0 := 0.0
var _shot_sm := {}
var _slow := 1.0
var _slow_until := -1.0
var _freeze := 0
var _lens := {"fov": 42.0, "shake": 0.0, "seed": 0.0, "roll": 0.0}
var _driver: PCamDriver
var _pcs: Array = []
var _attrs: CameraAttributesPractical
var _space_rids: Array = []
var _moves: FightMoves
var _host: Node
var _cam_top := false


# ------------------------------------------------------------------------------------------------ static helpers
## Ground height under p (a ray down through the area's colliders, ignoring the character's own body).
static func ground_y(c: Node3D, p: Vector3) -> float:
	var space := c.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 4.0, p.z), Vector3(p.x, p.y - 8.0, p.z))
	var ex: Array[RID] = []
	if c is CollisionObject3D:
		ex.append((c as CollisionObject3D).get_rid())
	for n in c.get_tree().get_nodes_in_group("avoid"):
		if n is CollisionObject3D:
			ex.append((n as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else p.y


## The clock to hour `h` (the day/night cycle follows it: 17.6 = a low golden sun over the clearing).
static func set_hour(m: Node, h: float) -> void:
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + h * 60.0
	if m.get("day_night") and m.day_night:
		m.day_night.clear_override()


## Turn her so her toes point along `dir` (flat).
static func face(c: WorldCharacter, dir: Vector3) -> void:
	c.rotation.y = yaw_for(c, dir)


static func yaw_for(c: WorldCharacter, dir: Vector3) -> float:
	var sk := c.skeleton
	var toe := sk.get_bone_global_rest(sk.find_bone("LeftToes")).origin - sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin
	var local := (c.global_basis.inverse() * (sk.global_basis * toe))
	local.y = 0.0
	var off := atan2(local.x, local.z)
	return atan2(dir.x, dir.z) - off


# ------------------------------------------------------------------------------------------------ setup
## Builds the fight at the training clearing: both mages on their marks, the stacks on their skeletons, the effects,
## the screen effects, the cinematic camera. opts: {seed, cinematic (hide overlays), center, axis_deg}.
func setup(m: Node, fight_mode: String, p_opts := {}) -> void:
	main = m
	mode = fight_mode
	opts = p_opts
	intensity = 1.0 if mode in ["duel", "spell"] else 0.65
	lane = float(opts.get("lane", 6.4 if mode == "spell" else LANE))
	arena_r = float(opts.get("arena_r", 4.6 if mode == "spell" else ARENA_R))
	rng.seed = int(opts.get("seed", 1907))
	center = opts.get("center", SanctuaryTerrain.TRAINING_CENTER_3D)
	var ang := deg_to_rad(float(opts.get("axis_deg", -15.0)))
	axis = Vector3(cos(ang), 0, sin(ang)).normalized()
	side = float(opts.get("side", 1.0))
	for id in ["mika", "luna"]:
		var c: WorldCharacter = main.characters[id]
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.end_gesture()
		c.set_physics_process(false)
		c.visible = true
		c.set_hair_frame("")
		var home := center + axis * (lane * 0.5) * (-1.0 if id == "mika" else 1.0)
		var f := {"id": id, "c": c, "other": "luna" if id == "mika" else "mika", "hp": 100.0, "touches": 0, "pos": home, "home": home,
			"yaw_k": 1.0, "yaw_extra": 0.0, "aura": {}, "shield": {}, "lift": 0.0}
		F[id] = f
		c.global_position = Vector3(home.x, ground_y(c, home), home.z)
		c.swap_avatar(c.avatar_path)                   # (springs start where she stands)
	for id in F:
		var f: Dictionary = F[id]
		var c: WorldCharacter = f.c
		face(c, _flat(F[f.other].pos - f.pos))
		f.deck = FightDeck.make(c)
		var life := BodyLife.make(c.skeleton, 1)
		life.look_weight = 0.5
		var other: String = f.other
		life.look = func() -> Vector3: return bone(other, "Head")
		f.life = life
		var soft := SoftArms.make(c.skeleton, 2)
		soft.finger_weight = 0.55
		f.soft = soft
		f.reach = FightReach.make(c.skeleton)
		f.probe = FightProbe.make(c.skeleton)
		(f.probe as FightProbe).scan_nan = RenderProfile.options.has("fight-camdebug")
		(f.deck as FightDeck).play("combat_idle", 0.0, -1.0, 1.0, 0.01, true)
	_hide_props()
	fx = FightFX.make(main.world if main.get("world") else main)
	fx.level = intensity
	for id in F:
		fx.hand_trails(F[id].c, id)
	sfx = ScreenFX.get_for(main)
	_moves = FightMoves.new()
	_moves.d = self
	_spell = SpellBeats.new()
	_spell.d = self
	_spell.m = _moves
	if bool(opts.get("cinematic", true)):
		for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if not (cl is ScreenFX) and not (cl is MVPost):
				(cl as CanvasLayer).visible = false
	_camera_setup()
	post = MVPost.make(main, null)


var _hidden: Array = []

## The practice dummy and the crystal on its stand stand in the clearing: hidden for the fight (they fill the
## foreground of the wide shots), shown again in teardown(). The rune targets stay - they dress the arena.
func _hide_props() -> void:
	var root: Node = main.world if main.get("world") else main
	for n in root.find_children("*", "Node3D", true, false):
		var nd := n as Node3D
		if not nd.visible or nd is WorldCharacter:
			continue
		var d := _flat(nd.global_position - center).length()
		if d > 6.6:
			continue
		var nm := String(nd.name).to_lower()
		if RenderProfile.options.has("fight-camdebug") and (nd is MeshInstance3D or nd.get_child_count() > 0) and d > 3.0:
			print("[fightprop] %.1f m %s %s" % [d, nd.name, nd.get_class()])
		if nm.contains("dummy") or nm.contains("practice_crystal") or nm.contains("crystal_stand"):
			nd.visible = false
			_hidden.append(nd)
	if mode == "spell":
		_clear_arena(root)
	# the stone stand under the practice crystal (an unnamed mesh at the crystal's foot)
	for h in _hidden.duplicate():
		if not String((h as Node).name).to_lower().contains("crystal"):
			continue
		for n in root.find_children("*", "VisualInstance3D", true, false):
			var mi := n as VisualInstance3D
			if mi.visible and _flat(mi.global_position - (h as Node3D).global_position).length() < 0.8 and not (h as Node).is_ancestor_of(mi):
				if RenderProfile.options.has("fight-camdebug"):
					print("[fightprop] hide near crystal: %s %s" % [mi.name, mi.get_class()])
				mi.visible = false
				_hidden.append(mi)


## The spell duel moves over the whole clearing and its shots are wide: the rune-target posts, standing stones and
## small props round it stood in the foreground of half the shots of the first render (22 Oct). For the duel they are
## hidden, and their colliders no longer pull the camera in (the "avoid" group); both are restored in teardown().
var _avoided: Array = []


func _clear_arena(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null or _is_char(mi):
			continue
		var d := _flat(mi.global_position - center).length()
		var sz := (mi.global_transform * mi.mesh.get_aabb()).size
		# (thin pieces too: hiding only the posts left their crossbars hanging in the air in the third render)
		if d < arena_r + 2.6 and maxf(sz.x, sz.z) < 3.0 and sz.y < 4.5 and maxf(sz.y, maxf(sz.x, sz.z)) > 0.08:
			mi.visible = false
			_hidden.append(mi)
		# further out: what may stand between a lens and them (trunks, ruins; the trees have no colliders, so the lens' ray
		# never saw the trunk that filled the fourth render for 4 s): hidden only while it is in the way (_occluders)
		elif d < arena_r + 14.0 and maxf(sz.x, sz.z) < 12.0 and maxf(sz.y, maxf(sz.x, sz.z)) > 0.3:
			_occ_cands.append(mi)
	for n in root.find_children("*", "StaticBody3D", true, false):
		var sb := n as StaticBody3D
		if _flat(sb.global_position - center).length() < arena_r + 2.6 and not String(sb.name).to_lower().contains("terrain") and not sb.is_in_group("avoid"):
			sb.add_to_group("avoid")
			_avoided.append(sb)


var _occ_cands: Array = []
var _occ_hidden := {}                 # mesh -> the frame time it last stood in the way


## A lens never looks through a trunk or a wall: anything between it and either of them (her head, chest, feet) is
## hidden for as long as it is in the way, and back 0.4 s after (no flicker).
func _occluders(cam: Vector3) -> void:
	var pts := []
	for id in F:
		pts.append_array([bone(id, "Head"), chest(id), pos(id) + Vector3(0, 0.25, 0)])
	for mi in _occ_cands:
		if not is_instance_valid(mi):
			continue
		var box: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
		var blocks := false
		for q in pts:
			if box.intersects_segment(cam, q):
				blocks = true
				break
		if blocks:
			if not _occ_hidden.has(mi) and (mi as MeshInstance3D).visible:
				(mi as MeshInstance3D).visible = false
				_occ_hidden[mi] = ft
			elif _occ_hidden.has(mi):
				_occ_hidden[mi] = ft
		elif _occ_hidden.has(mi) and ft - float(_occ_hidden[mi]) > 0.4:
			(mi as MeshInstance3D).visible = true
			_occ_hidden.erase(mi)


func _is_char(n: Node) -> bool:
	for id in F:
		if (F[id].c as Node).is_ancestor_of(n):
			return true
	return false


func _camera_setup() -> void:
	var cam: Camera3D = main.camera_rig.camera
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	if main.get("director"):
		main.director.set_process(false)
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	_cam_top = cam.top_level
	cam.top_level = true
	var host := PhantomCameraHost.new()
	_host = host
	host.interpolation_mode = PhantomCameraHost.InterpolationMode.MANUAL
	cam.add_child(host)
	_driver = PCamDriver.new()
	_driver.host = host
	main.add_child(_driver)
	_attrs = CameraAttributesPractical.new()
	_attrs.dof_blur_far_enabled = true
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)
	_driver.post = func(c: Camera3D) -> void:
		c.fov = float(_lens.fov)
		c.attributes = _attrs
		var k: float = _lens.shake
		if k > 0.001:
			var ph: float = _lens.seed
			c.global_position += c.global_basis * Vector3(sin(ph * 37.0), sin(ph * 51.0 + 1.3), 0.0) * 0.045 * k
			c.rotate_object_local(Vector3.FORWARD, sin(ph * 43.0 + 0.7) * 0.016 * k)
		if absf(float(_lens.roll)) > 0.0001:
			c.rotate_object_local(Vector3.FORWARD, float(_lens.roll))


# ------------------------------------------------------------------------------------------------ the fight
## Plans the fight (the referee) and stages it; returns the result when it is over.
func run() -> Dictionary:
	plan = FightPlan.make(mode, rng, {"mika": WorldState.mind("mika").level(), "luna": WorldState.mind("luna").level()}, opts)
	var t0 := 0.6
	for ex in plan:
		ex["t"] = t0
		t0 += _spell.stage(ex, t0) if String(ex.move).begins_with("s_") else _moves.stage(ex, t0)
	result = FightPlan.outcome(mode, plan)
	result["fight_s"] = t0
	print("[fight] %s plan: %s" % [mode, JSON.stringify(plan.map(func(e): return "%s %s>%s %s @%.1f" % [e.move, e.get("att", ""), e.get("def", ""), e.get("outcome", ""), e.t]))])
	print("[fight] shots %d, fight time %.1f s" % [_shots.size(), t0])
	set_process(true)
	print("[fight] start at engine frame %d" % Engine.get_frames_drawn())
	while ft < t0 + 0.2:
		await get_tree().process_frame
	done = true
	Engine.time_scale = 1.0
	result["award"] = FightXP.award(main, mode, result)
	finished.emit(result)
	return result


func _init() -> void:
	process_priority = -50
	set_process(false)


func _process(delta: float) -> void:
	frame += 1
	real_t += 1.0 / 30.0
	ft += delta
	# time: hit-stop (counted in rendered frames), then slow motion easing back
	if _freeze > 0:
		_freeze -= 1
		Engine.time_scale = 0.0001 if _freeze > 0 else _slow
	else:
		if _slow < 1.0 and ft >= _slow_until:
			_slow = minf(_slow + delta / 0.12 + 0.02, 1.0)
		Engine.time_scale = _slow
	if RenderProfile.options.has("fight-camdebug") and frame in [300, 560, 640]:
		_list_particles()
	if frame % 10 == 1:
		_quiet_strays()
	while not _ev.is_empty() and float(_ev[0][0]) <= ft:
		var e: Array = _ev.pop_front()
		(e[2] as Callable).call()
	_place(delta)
	_camera(delta)
	_lens.shake = maxf(float(_lens.shake) - (1.0 / 30.0) / 0.35, 0.0)
	_lens.seed = float(_lens.seed) + 1.0 / 30.0


func _place(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	for id in F:
		var f: Dictionary = F[id]
		var c: WorldCharacter = f.c
		var p: Vector3 = f.pos
		# never out of the clearing
		var off := _flat(p - center)
		if off.length() > arena_r:
			p = center + off.normalized() * arena_r
			f.pos = p
		if mode == "spell":
			# a spell duel is fought at range: never closer than 2 m (the first render came to 0.44 m)
			var op: Vector3 = F[f.other].pos
			var gap := _flat(p - op)
			if gap.length() < 2.0:
				p = op + (gap.normalized() if gap.length() > 0.05 else axis) * 2.0
				f.pos = p
		c.global_position = Vector3(p.x, ground_y(c, p) + float(f.lift), p.z)
		var want := yaw_for(c, _flat(F[f.other].pos - p)) + float(f.yaw_extra)
		c.rotation.y = lerp_angle(c.rotation.y, want, 1.0 - exp(-dt * 14.0 * float(f.yaw_k)))


# ------------------------------------------------------------------------------------------------ scheduling
func at(t: float, fn: Callable) -> void:
	_seq += 1
	var e := [t, _seq, fn]
	var i := _ev.size()
	while i > 0 and float(_ev[i - 1][0]) > t:
		i -= 1
	_ev.insert(i, e)


## A cut at fight time t to shot `kind` on `who` (opts: tween (s, a whip pan), roll (deg), at (world point), ...).
## Whole body only in the spell duel (Selwyn, 20 Oct: every shot head to feet, no face, hand or upper body close-ups):
## a closer kind asked for is taken as the nearest whole-body one.
const WHOLE_BODY := {"face": "wide_low", "face_ots": "wide", "ots": "wide", "hero_low": "wide_low", "crash": "wide", "hand": "wide", "crane": "wide_low", "behind": "wide"}


func cut(t: float, kind: String, who := "", shot_opts := {}) -> void:
	if mode == "spell" and WHOLE_BODY.has(kind):
		kind = String(WHOLE_BODY[kind])
	var s := [t, kind, who, shot_opts]
	var i := _shots.size()
	while i > 0 and float(_shots[i - 1][0]) > t:
		i -= 1
	_shots.insert(i, s)


# ------------------------------------------------------------------------------------------------ actions
func anim(id: String, clip: String, from := 0.0, to := -1.0, speed := 1.0, fade := 0.12, loop := false) -> float:
	return (F[id].deck as FightDeck).play(clip, from, to, speed, fade, loop)


func stance(id: String, fade := 0.25) -> void:
	anim(id, "combat_idle", rng.randf() * 1.5, -1.0, 1.0, fade, true)


## Moves her mark to `to` (a ground point) over dur, eased.
func move(id: String, to: Vector3, dur: float, trans := Tween.TRANS_QUAD, ease_ := Tween.EASE_OUT) -> void:
	var f: Dictionary = F[id]
	var tw := create_tween()
	tw.tween_method(func(v: Vector3): f.pos = v, f.pos as Vector3, clamp_arena(Vector3(to.x, center.y, to.z)), maxf(dur, 0.01)).set_trans(trans).set_ease(ease_)


## A point pulled back inside the clearing (they never leave ARENA_R round the centre).
func clamp_arena(p: Vector3) -> Vector3:
	var off := _flat(p - center)
	if off.length() > arena_r:
		return center + off.normalized() * arena_r + Vector3(0, p.y - center.y, 0)
	return p


## A hop: her body lifted by `h` m over dur (a jump the clip leaves on the ground).
func hop(id: String, h: float, dur: float) -> void:
	var f: Dictionary = F[id]
	var tw := create_tween()
	tw.tween_method(func(k: float): f.lift = h * sin(PI * k), 0.0, 1.0, maxf(dur, 0.01))


func pos(id: String) -> Vector3:
	return F[id].pos


func home(id: String) -> Vector3:
	return F[id].home


## Toward the other fighter (flat unit vector).
func fwd(id: String) -> Vector3:
	return _flat(F[F[id].other].pos - F[id].pos).normalized()


func bone(id: String, b: String) -> Vector3:
	var pr: FightProbe = F[id].get("probe")
	if pr and pr.pos.has(b):
		return pr.pos[b]
	var c: WorldCharacter = F[id].c
	var sk := c.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin


func chest(id: String) -> Vector3:
	return bone(id, "Chest") + Vector3(0, 0.08, 0)


func face_fx(id: String, emotion: String, k := 1.0, hold := 1.0) -> void:
	var c: WorldCharacter = F[id].c
	if c.face:
		c.face.pulse(emotion, k, hold)


func say(id: String, text: String) -> void:
	if main.get("voice") == null or main.voice == null:
		return
	var v = main.voice
	var run_ := func(): await v.say(id, text, {"subtitle": false})
	run_.call()


func sound(name: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	if main.get("audio") and main.audio:
		main.audio.play_cine(name, at, db, "fight", pitch)


## The impact feel: hit-stop frames, a flash (white for a touch; burst + inverted frames for a big one), a chromatic
## pulse, camera shake, speed lines only on the big ones.
func impact(power: float, big := false) -> void:
	var p := clampf(power, 0.0, 1.0) * (1.0 if mode == "duel" else 0.7)
	_freeze = maxi(_freeze, int(round(lerpf(2.0, 6.0, p))))
	if big and mode != "duel":
		big = false                               # (training stays light: no flash frames, no speed lines)
		sfx.chroma(0.4, 0.25)
	if big:
		sfx.flash_seq([["burst", 2], ["invert", 1], ["white", 1]], rng.randf_range(0.2, 1.2))
		sfx.speed_lines(1.0, 0.6)
		sfx.chroma(1.0, 0.35)
	elif mode == "duel" and p > 0.45:
		sfx.flash_seq([["white", 1]])
		sfx.chroma(0.6, 0.25)
	_lens.shake = maxf(float(_lens.shake), lerpf(0.35, 1.3, p))
	hit_log.append([snappedf(ft, 0.01), "big" if big else "hit", snappedf(power, 0.01)])


func slowmo(scale: float, dur: float) -> void:
	_slow = scale
	_slow_until = ft + dur
	Engine.time_scale = scale


func shake(k: float) -> void:
	_lens.shake = maxf(float(_lens.shake), k)


# ------------------------------------------------------------------------------------------------ camera
func _camera(delta: float) -> void:
	var ni := _shot_i
	while ni + 1 < _shots.size() and ft >= float(_shots[ni + 1][0]):
		ni += 1
	if ni < 0:
		return
	if ni != _shot_i:
		_shot_i = ni
		_shot = _shots[ni]
		_shot_t0 = ft
		_shot_sm.clear()
		var so: Dictionary = _shot[3]
		var pc := PhantomCamera3D.new()
		pc.name = "FIGHT_%02d_%s" % [ni, _shot[1]]
		main.add_child(pc)
		pc.set_tween_duration(float(so.get("tween", 0.0)))
		pc.set_tween_transition(Tween.TRANS_EXPO)
		_pcs.append(pc)
		if _pcs.size() > 3:
			(_pcs.pop_front() as Node).queue_free()
		cam_log.append([snappedf(real_t, 0.01), snappedf(ft, 0.01), _shot[1], _shot[2]])
		print("[fight] %.2f (ft %.2f) shot %d %s %s" % [real_t, ft, ni, _shot[1], _shot[2]])
	var opts2: Dictionary = _shot[3]
	var u := ft - _shot_t0
	var next_t := float(_shots[_shot_i + 1][0]) if _shot_i + 1 < _shots.size() else _shot_t0 + 3.0
	var cp := shot_cam(String(_shot[1]), String(_shot[2]), u, maxf(next_t - _shot_t0, 0.1), opts2)
	var pc2: PhantomCamera3D = _pcs[_pcs.size() - 1]
	var look: Vector3 = cp.look
	var p: Vector3 = _unblock(look, cp.pos)
	_occluders(p)
	if (look - p).length() > 0.01:
		pc2.global_transform = Transform3D(Basis.looking_at(look - p, Vector3.UP), p)
	pc2.set_priority(100 + _shot_i)
	if RenderProfile.options.has("fight-camdebug") and frame % 10 == 0:
		var lc := get_viewport().get_camera_3d()
		print("[fightcam] %s %s want %s look %s live %s fwd %s | mika %s luna %s head %s" % [_shot[1], _shot[2], str(p.snappedf(0.01)), str(look.snappedf(0.01)),
			str(lc.global_position.snappedf(0.01)) if lc else "-", str((-lc.global_basis.z).snappedf(0.01)) if lc else "-",
			str(pos("mika").snappedf(0.01)), str(pos("luna").snappedf(0.01)), str(bone(String(_shot[2]) if F.has(String(_shot[2])) else "mika", "Head").snappedf(0.01))])
	_lens.fov = cp.fov
	_lens.roll = deg_to_rad(float(opts2.get("roll", 0.0))) * (0.7 + 0.3 * sin(u * 1.3))
	var fd: float = (cp.focus - p).length()
	_attrs.dof_blur_far_distance = fd + float(cp.far)
	_attrs.dof_blur_far_transition = float(cp.far) * 2.5
	_attrs.dof_blur_amount = float(cp.amount)
	_attrs.dof_blur_near_enabled = float(cp.get("near", 0.0)) > 0.0
	_attrs.dof_blur_near_distance = maxf(fd - float(cp.get("near", 0.0)), 0.05)
	_attrs.dof_blur_near_transition = float(cp.get("near", 0.0)) * 0.8


## Other systems' particle emitters near the fighters (the shared energy motes, which render as black squares in
## this branch) are hidden for the fight; teardown() shows them again.
func _quiet_strays() -> void:
	var root: Node = main.get_node_or_null("Characters")
	if root == null:
		root = main
	for n in root.find_children("*", "GPUParticles3D", true, false):
		var g := n as GPUParticles3D
		if not g.visible or (fx and fx.is_ancestor_of(g)):
			continue
		var m: Material = g.draw_pass_1.surface_get_material(0) if g.draw_pass_1 else null
		if m is ShaderMaterial and (m as ShaderMaterial).shader and (m as ShaderMaterial).shader.resource_path.ends_with("energy_mote.gdshader"):
			g.visible = false
			_hidden.append(g)


func _list_particles() -> void:
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree() or fx.is_ancestor_of(g):
			continue
		var near := minf(g.global_position.distance_to(chest("mika")), g.global_position.distance_to(chest("luna")))
		if near > 2.5:
			continue
		if g is MeshInstance3D and (g as MeshInstance3D).skeleton != NodePath(""):
			continue                                   # (her own skinned meshes)
		if not (g is GPUParticles3D or g is CPUParticles3D or g is MultiMeshInstance3D):
			var sm: Material = g.material_override
			if sm == null and g is MeshInstance3D and (g as MeshInstance3D).mesh and (g as MeshInstance3D).mesh.get_surface_count() > 0:
				sm = (g as MeshInstance3D).mesh.surface_get_material(0)
			print("[fightparts] %d %.1f m %s %s %s" % [frame, near, g.get_path(), g.get_class(), (sm as ShaderMaterial).shader.resource_path if sm is ShaderMaterial and (sm as ShaderMaterial).shader else str(sm)])
			continue
		var mat := ""
		if g is GPUParticles3D and (g as GPUParticles3D).draw_pass_1:
			var m: Material = (g as GPUParticles3D).draw_pass_1.surface_get_material(0)
			mat = (m as ShaderMaterial).shader.resource_path if m is ShaderMaterial else str(m)
		print("[fightparts] %d %.1f m %s %s %s" % [frame, near, g.get_path(), g.get_class(), mat])


## The camera pulled in front of anything between it and what it looks at (the ruined walls, trees, stones).
func _unblock(look: Vector3, p: Vector3) -> Vector3:
	var c: WorldCharacter = F.mika.c
	var space := c.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(look, p)
	var ex: Array[RID] = []
	for n in get_tree().get_nodes_in_group("avoid"):
		if n is CollisionObject3D:
			ex.append((n as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return p
	var hp: Vector3 = hit.position
	var dir := (p - look).normalized()
	var d := maxf((hp - look).length() - 0.3, 0.6)
	var out := look + dir * d
	out.y = maxf(out.y, ground_y(c, out) + 0.15)
	return out


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _sm(key: String, p: Vector3, k := 0.25) -> Vector3:
	var v: Vector3 = _shot_sm.get(key, p)
	v = v.lerp(p, k)
	_shot_sm[key] = v
	return v


## One shot's camera u seconds (fight time) into it, `len_` its planned length: {pos, look, fov, focus, far, near, amount}.
func shot_cam(kind: String, who: String, u: float, len_: float, o: Dictionary) -> Dictionary:
	var k := clampf(u / len_, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var a: String = who if F.has(who) else "mika"
	var b: String = F[a].other
	var mid := (pos("mika") + pos("luna")) * 0.5
	var ax := _flat(pos("luna") - pos("mika")).normalized()
	var perp := ax.cross(Vector3.UP).normalized() * side * float(o.get("flip", 1.0))
	var gy := (F.mika.c as Node3D).global_position.y * 0.5 + (F.luna.c as Node3D).global_position.y * 0.5
	mid.y = gy
	var up := Vector3.UP
	var fa := fwd(a)
	var sa := fa.cross(Vector3.UP).normalized() * side       # her camera-side (keeps the 180-degree rule)
	match kind:
		"establish":
			var p0 := mid + perp * 8.5 - ax * 2.5 + up * 3.2
			var p1 := mid + perp * 7.0 - ax * 0.8 + up * 1.9
			return {"pos": p0.lerp(p1, e), "look": mid + up * 1.0, "fov": 40.0, "focus": mid + up, "far": 6.0, "amount": 0.03}
		"wide":
			var c0: Vector3 = _sm("mid", mid + up * 1.0, 0.2)
			var p := c0 + perp * float(o.get("dist", 6.6)) + up * 0.45 + ax * lerpf(-0.5, 0.5, e) * float(o.get("drift", 1.0))
			return {"pos": p, "look": c0, "fov": float(o.get("fov", 44.0)), "focus": c0, "far": 4.0, "amount": 0.03}
		"wide_low":
			var c1: Vector3 = _sm("mid", mid + up * 1.2, 0.2)
			var p2 := mid + perp * 5.2 + up * 0.28 + ax * lerpf(0.4, -0.4, e)
			return {"pos": p2, "look": c1 + up * 0.25, "fov": 50.0, "focus": c1, "far": 4.0, "amount": 0.03}
		"profile":
			var c2: Vector3 = _sm("mid", mid + up * 1.15, 0.25)
			var p3 := c2 + perp * lerpf(3.9, 3.4, e) + up * 0.1
			return {"pos": p3, "look": c2, "fov": 52.0, "focus": c2, "far": 2.5, "amount": 0.04}
		"face":
			var hd: Vector3 = _sm("hd", bone(a, "Head") + up * 0.02, 0.35)
			var sk_ := float(o.get("side", 0.38))
			var p4 := hd + fa * lerpf(1.05, 0.9, e) * (1.0 - sk_ * 0.45) + sa * sk_ - up * 0.04
			return {"pos": p4, "look": hd, "fov": 30.0, "focus": hd, "far": 0.35, "amount": 0.14}
		"face_ots":
			# over the other's shoulder onto her face
			var hd2: Vector3 = _sm("hd", bone(a, "Head") + up * 0.0, 0.35)
			var oh := bone(b, "Head")
			var away := _flat(oh - hd2).normalized()
			var p5 := oh + away * 0.55 - sa * 0.42 + up * 0.06
			return {"pos": p5, "look": hd2, "fov": 30.0, "focus": hd2, "far": 0.5, "near": 0.9, "amount": 0.14}
		"ots":
			# over HER shoulder toward the other (the attacker's view)
			var oc: Vector3 = _sm("oc", chest(b), 0.3)
			var mh := bone(a, "Head")
			var p6 := mh - fa * 0.7 + sa * 0.5 + up * 0.08
			return {"pos": p6, "look": oc, "fov": 40.0, "focus": oc, "far": 1.2, "near": 0.6, "amount": 0.1}
		"hero_low":
			var ch: Vector3 = _sm("ch", chest(a), 0.3)
			var gp := pos(a)
			gp.y = (F[a].c as Node3D).global_position.y
			var p7 := gp + fa * lerpf(2.3, 2.0, e) + sa * 1.0 + up * 0.22
			return {"pos": p7, "look": ch + up * 0.25, "fov": 46.0, "focus": ch, "far": 1.2, "amount": 0.07}
		"track":
			# alongside her as she moves (dashes)
			var ch2: Vector3 = _sm("ch", chest(a), 0.45)
			var p8 := ch2 + perp * 3.4 - up * 0.1 - fa * 0.4
			return {"pos": p8, "look": ch2 + fa * 0.7, "fov": 46.0, "focus": ch2, "far": 1.5, "amount": 0.06}
		"overhead":
			var c3: Vector3 = _sm("mid", mid, 0.2)
			var ang := lerpf(0.0, 0.5, e)
			var off := (perp * cos(ang) + ax * sin(ang)) * 2.2
			return {"pos": c3 + up * 7.0 + off, "look": c3 + up * 0.3, "fov": 46.0, "focus": c3, "far": 4.0, "amount": 0.02}
		"orbit":
			var c4: Vector3 = _sm("mid", mid + up * 1.05, 0.25)
			var a0 := float(o.get("from", 20.0))
			var a1 := float(o.get("to", 110.0))
			var an := deg_to_rad(lerpf(a0, a1, e))
			var r := float(o.get("r", 4.4))
			var p9 := c4 + (perp * cos(an) + ax * sin(an)) * r + up * lerpf(0.1, 0.5, e)
			return {"pos": p9, "look": c4, "fov": 46.0, "focus": c4, "far": 2.0, "amount": 0.04}
		"crash":
			# a crash zoom onto her (the fov snaps in over 0.15 s)
			var tgt: Vector3 = _sm("ch", chest(a) + up * 0.15, 0.5)
			var p10: Vector3 = _shot_sm.get("p0", tgt + sa * 2.2 + fa * 1.6 + up * 0.05)
			_shot_sm["p0"] = p10
			var f := lerpf(58.0, float(o.get("fov_to", 26.0)), smoothstep(0.0, 0.15, u))
			return {"pos": p10, "look": tgt, "fov": f, "focus": tgt, "far": 0.6, "amount": 0.1}
		"crane":
			# low beside her and rising with her jump
			var hp: Vector3 = _sm("hp", bone(a, "Hips"), 0.4)
			var gp2 := pos(a)
			gp2.y = gy
			var p11 := gp2 + perp * 3.6 + sa * 0.0 + up * (0.35 + (hp.y - gy) * 0.8) - fa * 0.8
			return {"pos": p11, "look": hp + up * 0.3, "fov": 50.0, "focus": hp, "far": 2.0, "amount": 0.05}
		"impact":
			var at_p: Vector3 = o.get("at", pos(a))
			var p12 := at_p + perp * 4.6 + up * 1.5 - ax * 1.0
			return {"pos": p12, "look": at_p + up * 0.7, "fov": 48.0, "focus": at_p, "far": 3.0, "amount": 0.03}
		"hand":
			var hb := String(o.get("bone", "RightHand"))
			var hnd: Vector3 = _sm("hand", bone(a, hb), 0.4)
			var p13 := hnd + sa * 0.42 + fa * 0.42 + up * 0.08
			return {"pos": p13, "look": hnd, "fov": 32.0, "focus": hnd, "far": 0.3, "amount": 0.16}
		"behind":
			var oc2: Vector3 = _sm("oc", chest(b), 0.25)
			var gp3 := pos(a)
			gp3.y = gy
			var p14 := gp3 - fa * 2.3 + sa * 0.7 + up * 0.8
			return {"pos": p14, "look": oc2, "fov": 46.0, "focus": oc2, "far": 2.0, "amount": 0.05}
		"two_mid":
			# a medium two-shot from 45 degrees (after the fight)
			var c5: Vector3 = _sm("mid", mid + up * 1.15, 0.2)
			var p15 := c5 + (perp * 0.8 + ax * 0.6 * float(o.get("lean", 1.0))).normalized() * lerpf(3.3, 3.0, e) + up * 0.2
			return {"pos": p15, "look": c5, "fov": 44.0, "focus": c5, "far": 1.6, "amount": 0.05}
	return {"pos": mid + perp * 6.0 + up * 1.4, "look": mid + up, "fov": 44.0, "focus": mid + up, "far": 3.0, "amount": 0.03}


## Undo the scene changes (used by the live hook after a fight).
func teardown() -> void:
	Engine.time_scale = 1.0
	for id in F:
		var f: Dictionary = F[id]
		for k in ["deck", "life", "soft", "reach", "probe"]:
			if f.has(k) and is_instance_valid(f[k]):
				(f[k] as Node).queue_free()
		(f.c as WorldCharacter).set_physics_process(true)
	if fx:
		fx.queue_free()
	if post:
		post.queue_free()
	if _driver:
		_driver.queue_free()
	if _host and is_instance_valid(_host):
		_host.queue_free()
	var cam: Camera3D = main.camera_rig.camera
	cam.top_level = _cam_top
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	for pc in _pcs:
		if is_instance_valid(pc):
			(pc as Node).queue_free()
	main.camera_rig.set_process(true)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_INHERIT
	if main.get("director"):
		main.director.set_process(true)
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_INHERIT
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = true
	for mi in _occ_hidden:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).visible = true
	_occ_hidden.clear()
	for nd in _hidden:
		if is_instance_valid(nd):
			(nd as Node3D).visible = true
	for sb in _avoided:
		if is_instance_valid(sb):
			(sb as Node).remove_from_group("avoid")
