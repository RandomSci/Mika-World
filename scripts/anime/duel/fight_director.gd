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
var ARENA_R := 3.4
var no_comic := false                     # (CombatSim: no speed lines / inverted frames)                        # they never leave this radius round the centre (the staged duel; CombatSim widens it)

var main: Node
var mode := "duel"
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
## The fight's tempo (2026-10-20, Selwyn: "the fight is happening too fast", his references move in big readable
## beats): the whole fight runs at this share of real time (the moves, the clips, the effects, cloth and hair alike),
## hit stop and slow motion on top of it. --fight-tempo=x overrides.
var tempo := float(RenderProfile.options.get("fight-tempo", "1.0" if RenderProfile.options.has("fight-legacy-motion") else "0.9"))
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
func setup(m: Node, fight_mode: String, opts := {}) -> void:
	main = m
	mode = fight_mode
	intensity = 1.0 if mode == "duel" else 0.65
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
		var home := center + axis * (LANE * 0.5) * (-1.0 if id == "mika" else 1.0)
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
		if bool(opts.get("bare", false)):
			# Combat v3 (MeleeFighter) owns the body: no softness pass, no reach, no camera-facing hand trails
			f.probe = FightProbe.make(c.skeleton)
			(f.deck as FightDeck).play("combat_idle", 0.0, -1.0, 1.0, 0.01, true)
			continue
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
		if not bool(opts.get("bare", false)):
			fx.hand_trails(F[id].c, id)
	sfx = ScreenFX.get_for(main)
	_moves = FightMoves.new()
	_moves.d = self
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
		# (a shot cut with "snap" lands at once, a hard cut: the kit's ultimate shots; Phantom Camera otherwise eased
		# the lens in over a few tenths of a second, which turned a cut from far away into a glide)
		if not _shot.is_empty() and bool((_shot[3] as Dictionary).get("snap", false)) and not _pcs.is_empty() and is_instance_valid(_pcs[_pcs.size() - 1]):
			c.global_transform = (_pcs[_pcs.size() - 1] as Node3D).global_transform
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
	plan = FightPlan.make(mode, rng, {"mika": WorldState.mind("mika").level(), "luna": WorldState.mind("luna").level()})
	var t0 := 0.6
	for ex in plan:
		ex["t"] = t0
		t0 += _moves.stage(ex, t0)
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
		Engine.time_scale = 0.0001 if _freeze > 0 else _slow * tempo
	else:
		if _slow < 1.0 and ft >= _slow_until:
			_slow = minf(_slow + delta / 0.12 + 0.02, 1.0)
		Engine.time_scale = _slow * tempo
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
		if off.length() > ARENA_R:
			p = center + off.normalized() * ARENA_R
			f.pos = p
		# the drawn body follows her logical mark on a critically damped spring (0.05 s): the sim's corrections (a step
		# up to a strike, a push apart, a give of ground) arrive as single frame jumps of up to 15 cm, and drawn raw they
		# jerked her planted feet's IK every few frames, the main source of the legs' and body's trembling in fights
		# (2026-10-20). A jump over 2 m (a placement, a teleport) is taken at once.
		var shown: Vector3 = f.get("shown", p)
		var sv: Vector3 = f.get("shown_v", Vector3.ZERO)
		if shown.distance_to(p) > 2.0 or RenderProfile.options.has("no-root-smooth") or RenderProfile.options.has("fight-legacy-motion"):
			shown = p
			sv = Vector3.ZERO
		else:
			var wn := 1.0 / 0.05
			var nsub := maxi(int(ceil(dt * 240.0)), 1)
			var h := dt / float(nsub)
			for _i in nsub:
				sv += ((p - shown) * wn * wn - sv * 2.0 * wn) * h
				shown += sv * h
		f.shown = shown
		f.shown_v = sv
		c.global_position = Vector3(shown.x, ground_y(c, shown) + float(f.lift), shown.z)
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
func cut(t: float, kind: String, who := "", opts := {}) -> void:
	var s := [t, kind, who, opts]
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
	if off.length() > ARENA_R:
		return center + off.normalized() * ARENA_R + Vector3(0, p.y - center.y, 0)
	return p


## A hop: her body lifted by `h` m over dur (a jump the clip leaves on the ground).
func hop(id: String, h: float, dur: float) -> void:
	var f: Dictionary = F[id]
	if f.get("hop_tw") and (f.hop_tw as Tween).is_valid():
		(f.hop_tw as Tween).kill()                   # (a new arc replaces the one she is in)
	var tw := create_tween()
	tw.tween_method(func(k: float): f.lift = h * sin(PI * k), 0.0, 1.0, maxf(dur, 0.01))
	f.hop_tw = tw


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
func impact(power: float, big := false, decisive := false) -> void:
	var p := clampf(power, 0.0, 1.0) * (1.0 if mode == "duel" else 0.7)
	_freeze = maxi(_freeze, int(round(lerpf(2.0, 6.0, p))))
	if no_comic:
		# the live fight (CombatSim): no comic speed lines; one ink-burst frame only on the decisive blow
		if decisive:
			sfx.flash_seq([["burst", 1], ["white", 1]], rng.randf_range(0.2, 1.2))
			sfx.chroma(0.8, 0.3)
		elif big or p > 0.6:
			sfx.chroma(0.5, 0.2)
		_lens.shake = maxf(float(_lens.shake), lerpf(0.3, 1.1, p))
		hit_log.append([snappedf(ft, 0.01), "big" if big else "hit", snappedf(power, 0.01)])
		return
	if big and mode != "duel":
		big = false                               # (training stays light: no flash frames, no speed lines)
		sfx.chroma(0.4, 0.25)
	# (2026-10-20: no white frames in the duel, they stacked with the spells' light into white screens; the big hit
	# keeps the anime impact frame, an ink burst and one inverted frame)
	if big:
		sfx.flash_seq([["burst", 2], ["invert", 1]], rng.randf_range(0.2, 1.2))
		sfx.speed_lines(1.0, 0.6)
		sfx.chroma(1.0, 0.35)
	elif mode == "duel" and p > 0.45:
		sfx.chroma(0.6, 0.25)
	_lens.shake = maxf(float(_lens.shake), lerpf(0.35, 1.3, p))
	hit_log.append([snappedf(ft, 0.01), "big" if big else "hit", snappedf(power, 0.01)])


func slowmo(scale: float, dur: float) -> void:
	_slow = scale
	_slow_until = ft + dur
	Engine.time_scale = scale * tempo


## An ultimate's domain: the world dims and takes her colour (the grade darker and colder or more violet, a tinted fog
## low over the ground), eased in over `fade`; off restores what was there.
func domain(who: String, on: bool, fade := 0.8) -> void:
	var we: WorldEnvironment = null
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		we = n
		break
	if we == null or we.environment == null:
		return
	var e := we.environment
	if on:
		if not e.has_meta("domain_saved"):
			e.set_meta("domain_saved", [e.adjustment_enabled, e.adjustment_brightness, e.adjustment_saturation, e.fog_enabled, e.fog_light_color,
				e.fog_density, e.ambient_light_color, e.ambient_light_energy])
		var col: Color = CombatVFX.pal(who).edge
		e.adjustment_enabled = true
		e.fog_enabled = true
		var tw := create_tween().set_parallel(true)
		tw.tween_property(e, "adjustment_brightness", 0.55, fade)
		tw.tween_property(e, "adjustment_saturation", 0.85, fade)
		tw.tween_property(e, "fog_light_color", col.darkened(0.55), fade)
		tw.tween_property(e, "fog_density", 0.025, fade)
		tw.tween_property(e, "ambient_light_color", col.lerp(Color.WHITE, 0.3), fade)
		tw.tween_property(e, "ambient_light_energy", 0.6, fade)
	elif e.has_meta("domain_saved"):
		var sv: Array = e.get_meta("domain_saved")
		e.remove_meta("domain_saved")
		var tw2 := create_tween().set_parallel(true)
		tw2.tween_property(e, "adjustment_brightness", float(sv[1]), fade)
		tw2.tween_property(e, "adjustment_saturation", float(sv[2]), fade)
		tw2.tween_property(e, "fog_light_color", sv[4], fade)
		tw2.tween_property(e, "fog_density", float(sv[5]), fade)
		tw2.tween_property(e, "ambient_light_color", sv[6], fade)
		tw2.tween_property(e, "ambient_light_energy", float(sv[7]), fade)
		tw2.chain().tween_callback(func():
			e.adjustment_enabled = bool(sv[0])
			e.fog_enabled = bool(sv[3]))


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
		var opts: Dictionary = _shot[3]
		var pc := PhantomCamera3D.new()
		pc.name = "FIGHT_%02d_%s" % [ni, _shot[1]]
		main.add_child(pc)
		pc.set_tween_duration(float(opts.get("tween", 0.0)))
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
	if (look - p).length() > 0.01:
		pc2.global_transform = Transform3D(Basis.looking_at(look - p, Vector3.UP), p)
	pc2.set_priority(100 + _shot_i)
	if RenderProfile.options.has("fight-camdebug") and frame % 10 == 0:
		var lc := get_viewport().get_camera_3d()
		print("[fightcam] %s %s want %s look %s live %s fwd %s | mika %s luna %s head %s" % [_shot[1], _shot[2], str(p.snappedf(0.01)), str(look.snappedf(0.01)),
			str(lc.global_position.snappedf(0.01)) if lc else "-", str((-lc.global_basis.z).snappedf(0.01)) if lc else "-",
			str(pos("mika").snappedf(0.01)), str(pos("luna").snappedf(0.01)), str(bone(String(_shot[2]) if F.has(String(_shot[2])) else "mika", "Head").snappedf(0.01))])
	_lens.fov = cp.fov
	_attrs.exposure_multiplier = float(cp.get("exposure", 1.0))
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
		"duo":
			# the live fight's follow shot: both in frame however far apart, from her side of the line (180-degree rule)
			var sep := _flat(pos("luna") - pos("mika")).length()
			var cd: Vector3 = _sm("mid", mid + up * (1.0 + float(o.get("lift", 0.0))), 0.18)
			var dist := clampf(2.4 + sep * 0.72, float(o.get("min", 4.0)), 11.0) * float(o.get("k", 1.0))
			var pd: Vector3 = _sm("duo", cd + perp * dist + up * (0.35 + sep * 0.08 + float(o.get("high", 0.0))) - ax * float(o.get("lead", 0.0)), 0.12)
			return {"pos": pd, "look": cd, "fov": float(o.get("fov", 46.0)), "focus": cd, "far": 5.0, "amount": 0.025}
		"fixed":
			# a locked lens (labs and checks): a world position and a point to look at
			var lk: Vector3 = o.get("look", mid)
			return {"pos": o.get("pos", mid + perp * 4.0), "look": lk, "fov": float(o.get("fov", 40.0)), "focus": lk, "far": 6.0, "amount": 0.0}
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
		"eyes":
			# an extreme close-up on her eyes (an ultimate's opening): the lens just in front of her face, slightly off
			# axis, slowly pushing in
			var ey: Vector3 = _sm("hd", bone(a, "Head") + up * 0.06 * float(o.get("k", 1.0)), 0.5)
			var p_e := ey + fa * lerpf(0.62, 0.5, e) + sa * 0.08 + up * 0.01
			return {"pos": p_e, "look": ey, "fov": float(o.get("fov", 18.0)), "focus": ey, "far": 0.25, "amount": 0.18}
		"pullback":
			# from close on her to wide over the shot (an ultimate's release: the camera pulled back by the blast)
			var c6: Vector3 = _sm("mid", mid + up * 1.1, 0.25)
			var ch3 := chest(a)
			var near_p := ch3 + fa * 1.6 + sa * 1.0 + up * 0.1
			var far_p := c6 + perp * float(o.get("dist", 10.0)) + up * float(o.get("high", 3.2)) - ax * 1.5
			var ee := 1.0 - pow(1.0 - e, 3.0)
			return {"pos": near_p.lerp(far_p, ee), "look": ch3.lerp(c6, ee), "fov": lerpf(38.0, 52.0, ee), "focus": ch3.lerp(c6, ee), "far": 3.0, "amount": 0.03}
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
		"hit_close":
			# a close up on the point a blow lands (the references cut to the fist, the foot, the face at the hit),
			# 45 degrees off the line between them, a slow push in through the hit stop
			var at_h: Vector3 = o.get("at", chest(a))
			var fl := float(o.get("flip", 1.0))
			var dirh := (perp * fl + ax * 0.7).normalized()
			var ph := at_h + dirh * lerpf(1.35, 1.1, e) + up * 0.12
			return {"pos": ph, "look": at_h, "fov": 36.0, "focus": at_h, "far": 0.5, "amount": 0.12}
		"eye":
			# an extreme close-up on ONE eye (an ultimate's opening, the references' "eyes open" beat): the lens a hand's
			# breadth from her face, a little to the eye's side, creeping in
			var sk_e := (F[a].c as WorldCharacter).skeleton
			var eb := "LeftEye" if float(o.get("flip", 1.0)) > 0.0 else "RightEye"
			var ep: Vector3 = bone(a, eb) if sk_e.find_bone(eb) >= 0 else bone(a, "Head") + up * 0.07 + fa * 0.07 + sa * 0.032
			var eyp: Vector3 = _sm("eye", ep, 0.5)
			# 40 deg off her face on the eye's side, a little above; if a hand is near the line from the lens to the eye
			# (a cast with the hands raised to the face), the other side, then higher (2026-10-20: Mika's opening shot
			# filmed her sleeve)
			var p_y := eyp + fa * lerpf(0.3, 0.25, e) + sa * 0.2 * float(o.get("flip", 1.0)) + up * 0.04
			for tries in 3:
				var blocked := false
				for hb2 in ["LeftHand", "RightHand"]:
					var hp2 := bone(a, hb2)
					var seg_d := Geometry3D.get_closest_point_to_segment(hp2, eyp, p_y).distance_to(hp2)
					if seg_d < 0.09:
						blocked = true
				if not blocked:
					break
				p_y = eyp + fa * 0.27 + sa * 0.2 * float(o.get("flip", 1.0)) * (-1.0 if tries == 0 else 1.0) + up * (0.04 + 0.12 * tries)
			return {"pos": p_y, "look": eyp, "fov": float(o.get("fov", 16.0)), "focus": eyp, "far": 0.08, "amount": 0.22, "exposure": 0.85}
		"sign":
			# an extreme close-up on her two hands forming the sign (the point between them)
			var hl := bone(a, "LeftHand")
			var hr := bone(a, "RightHand")
			var hm: Vector3 = _sm("sign", (hl + hr) * 0.5 + (hl - hr).length() * 0.0 * up, 0.45)
			var p_s := hm + fa * lerpf(0.62, 0.5, e) + sa * 0.22 + up * 0.06
			# (exposure down: skin, white sleeves and the cast's light burned to white in this close-up)
			return {"pos": p_s, "look": hm, "fov": float(o.get("fov", 26.0)), "focus": hm, "far": 0.25, "amount": 0.18, "exposure": 0.62}
		"push":
			# a fast push-in on her, from a medium shot to her face in the shot's length (the release's held breath)
			var chp: Vector3 = _sm("ch", chest(a) + up * 0.12, 0.35)
			var ee2 := 1.0 - pow(1.0 - k, 3.0)
			var dir_p := (fa + sa * 0.45 - up * 0.12).normalized()
			var p_p := chp + dir_p * lerpf(float(o.get("from", 3.4)), float(o.get("to", 0.95)), ee2)
			return {"pos": p_p, "look": chp, "fov": lerpf(44.0, 32.0, ee2), "focus": chp, "far": 0.8, "amount": 0.1}
		"blade_close":
			# a close-up on the point where the blades meet or the blade lands (Download(7): the camera on the clash),
			# 50 deg off the line between them, pushing in through the hit stop
			var at_b: Vector3 = o.get("at", chest(a))
			var flb := float(o.get("flip", 1.0))
			var dirb := (perp * flb + ax * 0.5 + up * 0.15).normalized()
			var pb := at_b + dirb * lerpf(1.25, 0.95, e)
			return {"pos": pb, "look": at_b, "fov": 34.0, "focus": at_b, "far": 0.45, "amount": 0.14, "exposure": 0.85}
		"feet":
			# low beside her feet as she dashes (the references cut to the feet on a dash)
			var gf := pos(a)
			gf.y = (F[a].c as Node3D).global_position.y
			# (no lag on the feet: at a dash's speed a smoothed lens was left on empty ground)
			var pf: Vector3 = gf + sa * 1.3 + fa * 0.9 + up * 0.2
			return {"pos": pf, "look": gf + up * 0.3 + fa * 0.35, "fov": 46.0, "focus": gf, "far": 0.8, "amount": 0.08}
		"orbit_her":
			# a low orbit round HER (an ultimate's gather: the sigil and the blades forming round her)
			var chq: Vector3 = _sm("ch", chest(a), 0.3)
			var an2 := deg_to_rad(lerpf(float(o.get("from", -50.0)), float(o.get("to", 40.0)), e))
			var r2 := float(o.get("r", 2.6))
			var gq := Vector3(chq.x, gy, chq.z)
			var p_o := gq + (fa * cos(an2) + sa * sin(an2)) * r2 + up * float(o.get("h", 0.35))
			return {"pos": p_o, "look": chq + up * 0.35, "fov": float(o.get("fov", 50.0)), "focus": chq, "far": 1.5, "amount": 0.06}
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
	for nd in _hidden:
		if is_instance_valid(nd):
			(nd as Node3D).visible = true
