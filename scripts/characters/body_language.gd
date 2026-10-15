class_name BodyLanguage
extends SkeletonModifier3D
## The whole body says what she feels and how she is (the developer: "The characters lack body languages and
## expressiveness ... When hurt, etc."). Additive, on top of whatever she is doing (walking, idling, casting,
## gestures) and below the head posture; eased, never snapping. It reads her FaceController mix (emotions) and her
## CONDITION (injury from real blows, exhaustion, exertion) and moves the spine, chest, shoulders and arms:
##   hurt / injured  - curls a little toward the struck side, the near arm comes in to guard the ribs, shoulders
##                     tense; winces now and then while it lasts; a limp in the gait (hip drop on the bad side)
##   tired / spent   - shoulders drop, chest sinks, a slower gait, slow deep sighs
##   exertion        - heavy breathing after running / fighting (chest and shoulders heave, faster when hurt)
##   happy / excited / playful / proud - chest up, shoulders open, a bounce in the step; excited fidgets
##   sad / concerned - shoulders forward and down, chest closed, head heavy; arms drawn in
##   shy             - shoulders raised, arms close, body turned a little away
##   frustrated      - shoulders squared and tense, a sharp exhale now and then
##   scared / surprised - shoulders up, the body pulls back
##   speaking        - the hands and forearms talk: emphasis beats in time with the voice
##   holding a barrier (a ward, the Gilded Grove) - knees soft and hips down, leaning into it, both arms up and
##                     out with the palms toward it; as its charges run out the strain shows: faster breath, the
##                     arms tremble, the face set and pained. Every blow it takes knocks her torso and arms back
##                     (and a heavy one pushes her back a step); when it breaks she sags with the release.
## Injury heals over minutes (faster when resting); it follows real hits only (BodyReaction.reacted).

var c: WorldCharacter
var amount := 1.0
var injury := 0.0                  # 0..1, from real blows; heals over time
var injury_side := 1.0             # +1 = her right side was struck, -1 = left
var exertion := 0.0                # 0..1, from running / fighting; recovers at rest
var speaking := false
var barrier := 0.0                 # 0..1 how hard she is holding a barrier (Ward feeds it every frame it is up)
var barrier_kind := ""             # leaf / mirror / grove: where her hands go
var barrier_strain := 0.0          # 0..1 grows as the barrier's charges are spent
var _barrier_seen := 0.0           # time since the ward last fed us (the hold fades out if it stops)
var _impact := 0.0                 # the knock-back of the last blow on her barrier (decays)
var _release := 0.0                # the sag when the barrier breaks
var _t := 0.0
var _cur := {}                     # channel -> eased value
var _bones := {}
var _wince := 0.0
var _next_wince := 5.0
var _sigh := 0.0
var _next_sigh := 8.0
var _step_phase := 0.0
var log: Array = []

const BONES := ["Hips", "Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand"]


static func attach(ch: WorldCharacter, amt := 1.0) -> BodyLanguage:
	if ch.skeleton == null or ch.skeleton.find_bone("Spine") < 0:
		return null
	var b := BodyLanguage.new()
	b.name = "BodyLanguage"
	b.c = ch
	b.amount = amt
	ch.skeleton.add_child(b)
	return b


func _ready() -> void:
	var sk := get_skeleton()
	if sk:
		for n in BONES:
			_bones[n] = sk.find_bone(n)


## A real blow landed (BodyReaction): she carries it for a while.
func on_hit(info: Dictionary) -> void:
	var sev := float(info.get("severity", 0.3))
	var tier := String(info.get("tier", ""))
	var add := {"flinch": 0.18, "stagger": 0.35, "down": 0.6}.get(tier, sev * 0.3) as float
	injury = clampf(injury + add, 0.0, 1.0)
	injury_side = float(info.get("side", injury_side))
	exertion = clampf(exertion + 0.35, 0.0, 1.0)
	_next_wince = _t + 1.2
	log.append({"t": snappedf(_t, 0.1), "event": "hit", "tier": tier, "injury": snappedf(injury, 0.01)})
	if log.size() > 40:
		log.pop_front()


## Walk / run tempo multiplier from how she is (a hurt or tired girl walks slower, an excited one quicker).
## Called every frame by her Ward while it is up: what she holds and how spent it is (0 fresh .. 1 almost gone).
func hold_barrier(kind: String, strain: float) -> void:
	barrier_kind = kind
	barrier_strain = clampf(strain, 0.0, 1.0)
	_barrier_seen = 0.0
	if c and c.face and barrier < 0.2:
		c.face.pulse("determined", 0.7, 1.2)


## A blow lands on her barrier: the torso and arms are knocked back (heavier = more), the face flinches, and a
## heavy one pushes her back a step if there is room behind her.
func barrier_impact(from: Vector3, heavy: bool) -> void:
	_impact = 1.0 if heavy else 0.6
	exertion = clampf(exertion + (0.12 if heavy else 0.06), 0.0, 1.0)
	if c == null:
		return
	if c.face:
		c.face.pulse("hurt" if heavy else "surprised", 0.55 if heavy else 0.4, 0.35)
	var away := c.global_position - from
	away.y = 0.0
	if heavy and away.length() > 0.05:
		var push := away.normalized() * 0.28
		if not c.test_move(c.global_transform, push):
			var tw := c.create_tween()
			tw.tween_property(c, "global_position", c.global_position + push, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if heavy and VoiceService.instance and VoiceService.instance.enabled and not speaking and randf() < 0.5:
		VoiceService.instance.react(c.character_id, "effort")


## The barrier broke or was let go: the arms come down; if it was spent under strain, she sags with the release.
func barrier_released(spent: bool) -> void:
	_barrier_seen = 99.0
	if spent:
		_release = 1.0
		exertion = clampf(exertion + 0.15, 0.0, 1.0)
		if c and c.face:
			c.face.pulse("tired", 0.5, 1.0)


func tempo() -> float:
	var m := _mix()
	var t := 1.0 - injury * 0.22 - float(m.get("tired", 0.0)) * 0.18 - float(m.get("sad", 0.0)) * 0.12
	t += float(m.get("excited", 0.0)) * 0.1 + float(m.get("happy", 0.0)) * 0.04 + float(m.get("playful", 0.0)) * 0.06
	return clampf(t, 0.72, 1.15)


func _mix() -> Dictionary:
	return c.face._mix if c and c.face else {}


func _ease(ch: String, want: float, rate: float, dt: float) -> float:
	var v := float(_cur.get(ch, 0.0))
	v = lerpf(v, want, 1.0 - exp(-rate * dt))
	_cur[ch] = v
	return v


func _process_modification_with_delta(dt: float) -> void:
	var sk := get_skeleton()
	if sk == null or c == null or amount <= 0.0:
		return
	_t += dt
	var m := _mix()
	var hv := Vector2(c.velocity.x, c.velocity.z).length()
	var moving := hv > 0.4
	# condition: injury heals (faster at rest), exertion builds when running / fighting and recovers
	var resting := c.seated or c.ground_pose != ""
	injury = maxf(0.0, injury - dt * (0.006 if resting else 0.0016))     # a real blow shows for minutes
	var exert_in := clampf((hv - c.walk_speed) / maxf(c.run_speed - c.walk_speed, 0.1), 0.0, 1.0) * 0.12 + (0.05 if c.combat_stance else 0.0)
	exertion = clampf(exertion + dt * exert_in - dt * (0.035 if not moving else 0.01), 0.0, 1.0)
	var down := c.reaction != null and c.reaction.active and c.reaction.tier in ["stagger", "down"]
	var w := amount * (0.0 if down else 1.0)          # the knock-down sequence owns her body while it plays
	var mind = WorldState.mind(c.character_id) if c.character_id != "" else null
	var tired := maxf(float(m.get("tired", 0.0)), clampf((0.45 - (float(mind.vigor) if mind else 1.0)) * 1.4, 0.0, 0.8))
	var happy := float(m.get("happy", 0.0)) + float(m.get("laughing", 0.0)) * 0.8
	var excited := float(m.get("excited", 0.0)) + float(m.get("surprised", 0.0)) * 0.3
	var proud := float(m.get("proud", 0.0)) + float(m.get("determined", 0.0)) * 0.6 + float(m.get("playful", 0.0)) * 0.4
	var sad := float(m.get("sad", 0.0)) + float(m.get("concerned", 0.0)) * 0.5 + float(m.get("hurt", 0.0)) * 0.3
	var shy := float(m.get("shy", 0.0))
	var tense := float(m.get("frustrated", 0.0)) + float(m.get("surprised", 0.0)) * 0.6 + float(m.get("hurt", 0.0)) * 0.4
	# winces and sighs (short events on top of the steady posture)
	if injury > 0.25 and _t > _next_wince:
		_next_wince = _t + randf_range(4.0, 9.0) / maxf(injury, 0.3)
		_wince = 1.0
		if c.face:
			c.face.pulse("hurt", 0.55 + injury * 0.4, 0.5)
		# now and then a pained breath in her own voice (never while she speaks)
		if injury > 0.5 and not speaking and randf() < 0.3 and VoiceService.instance and VoiceService.instance.enabled:
			VoiceService.instance.react(c.character_id, "effort")
	if tired > 0.3 and _t > _next_sigh and not speaking:
		_next_sigh = _t + randf_range(9.0, 16.0)
		_sigh = 1.0
	_wince = maxf(0.0, _wince - dt * 1.6)
	_sigh = maxf(0.0, _sigh - dt * 0.45)
	var wince := sin(minf(_wince, 1.0) * PI) if _wince > 0.0 else 0.0
	var sigh := sin((1.0 - _sigh) * PI) * float(_sigh > 0.0)
	# breathing: calm 0.3 Hz, heaving up to ~1.1 Hz when spent or hurt
	var br_rate := 0.3 + exertion * 0.7 + injury * 0.25
	var breath := sin(_t * TAU * br_rate)
	var br_amp := 0.008 + exertion * 0.035 + injury * 0.015
	# the gait: step phase from speed (limp and bounce live on it)
	_step_phase += dt * hv / 0.72 * PI
	var step := sin(_step_phase)
	# ---- channels (radians), eased
	var slump := _ease("slump", w * (tired * 0.24 + sad * 0.16 + injury * 0.08 + shy * 0.05 - proud * 0.1 - happy * 0.09 - excited * 0.08), 3.0, dt)
	var curl := _ease("curl", w * injury * 0.14 * injury_side, 3.0, dt)                       # bend toward the hurt side
	var sh_up := _ease("sh_up", w * (shy * 0.14 + tense * 0.14 + excited * 0.06 - tired * 0.14 - sad * 0.1), 4.0, dt)
	var sh_fwd := _ease("sh_fwd", w * (sad * 0.12 + tired * 0.08 + shy * 0.1 + injury * 0.05 - proud * 0.08 - happy * 0.05), 3.0, dt)
	var guard := _ease("guard", w * clampf(injury * 1.3, 0.0, 1.0), 2.5, dt)
	var arms_in := _ease("arms_in", w * (shy * 0.5 + sad * 0.35 + float(m.get("scared", 0.0)) * 0.6), 3.0, dt)
	var bounce := _ease("bounce", w * clampf(happy * 0.6 + excited * 0.9, 0.0, 1.0), 3.0, dt) * (1.0 if moving else 0.0)
	var limp := _ease("limp", w * clampf(injury * 1.4, 0.0, 1.0), 2.0, dt) * (1.0 if moving else 0.0)
	var talk := _ease("talk", w * (1.0 if speaking and not c.casting and not moving else 0.0), 4.0, dt)
	# a happy / excited girl standing still shifts her weight and sways; a tense one is still
	var sway := _ease("sway", w * clampf(happy * 0.7 + excited + float(m.get("playful", 0.0)), 0.0, 1.0) * (0.0 if moving else 1.0), 2.0, dt)
	# a barrier held: eased in over ~0.3 s, out over ~0.6 s when the ward stops feeding it
	_barrier_seen += dt
	var hold := _ease("barrier", w * (1.0 if _barrier_seen < 0.25 else 0.0), 3.5 if _barrier_seen < 0.25 else 1.8, dt)
	barrier = hold
	var strain := hold * barrier_strain
	_impact = maxf(0.0, _impact - dt * 3.2)
	_release = maxf(0.0, _release - dt * 0.9)
	var knock := sin(minf(_impact, 1.0) * PI * 0.5) * hold
	var sag := sin(minf(_release, 1.0) * PI)
	var tremor := strain * (sin(_t * 41.0) * 0.6 + sin(_t * 57.0) * 0.4) * 0.025
	if hold > 0.05:
		br_rate += strain * 0.6
		br_amp += strain * 0.02
		breath = sin(_t * TAU * br_rate)
	_mood_gestures(m, tired, moving)
	# skeleton space: the VRM faces +Z, its left is +X
	var rx := Vector3.RIGHT      # pitch axis (+ = top forward)
	var fz := Vector3.BACK       # roll axis (+ = top toward -X = her right)
	var uy := Vector3.UP
	# leaning into the barrier (forward), knocked back by a blow, sagging when it breaks
	var lean := hold * (0.07 + strain * 0.06) - knock * 0.22 + sag * 0.16
	_rot(sk, "Spine", Basis(rx, slump * 0.45 + breath * br_amp * 0.3 + sigh * 0.04 + wince * 0.08 + lean) * Basis(fz, curl * 0.5 + limp * step * 0.035 * injury_side))
	_rot(sk, "Chest", Basis(rx, slump * 0.35 - breath * br_amp * 0.6 - sigh * 0.05 + wince * 0.06 + lean * 0.6) * Basis(fz, curl * 0.5))
	_rot(sk, "UpperChest", Basis(rx, slump * 0.2 - breath * br_amp * 0.4))
	var sw := sin(_t * TAU * 0.35)
	_rot(sk, "Hips", Basis(fz, limp * step * 0.06 * injury_side + sway * sw * 0.05) * Basis(uy, bounce * step * 0.03 + sway * sw * 0.04),
		Vector3(sway * sw * 0.025, bounce * absf(step) * 0.025 - limp * maxf(0.0, step * injury_side) * 0.03 - hold * (0.035 + strain * 0.03) - sag * 0.03, 0))
	for side in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0          # +X side is her left
		var hurt_side := (s < 0.0 and injury_side > 0.0) or (s > 0.0 and injury_side < 0.0)
		var raise := sh_up + breath * br_amp * 0.8 + sigh * 0.06 + wince * 0.05 * (1.0 if hurt_side else 0.4)
		_rot(sk, side + "Shoulder", Basis(fz, s * raise) * Basis(uy, -s * sh_fwd))
		# arms: drawn in (shy, sad, scared), the hurt side's arm guards the ribs, talking hands
		var g := guard if hurt_side else guard * 0.25
		var talk_beat := talk * (0.5 + 0.5 * sin(_t * (2.6 if s > 0 else 3.1) + s)) * (0.6 + 0.4 * sin(_t * 0.9 + s * 2.0))
		# (a hanging arm: pitch about X brings it forward, roll about Z brings it in toward the body)
		# holding a barrier: both arms up and forward (the grove: up and out, to the dome round them), palms toward
		# it, trembling as it weakens; a blow knocks them back
		var arm_up := hold * (1.05 if barrier_kind != "grove" else 1.25) - knock * 0.45 - sag * 0.2
		var arm_out := hold * (0.12 if barrier_kind != "grove" else 0.45)
		_rot(sk, side + "UpperArm", Basis(fz, -s * (arms_in * 0.14 + g * 0.3 - talk_beat * 0.08 - arm_out)) * Basis(rx, -(g * 0.4 + arms_in * 0.12 + talk_beat * 0.18 + arm_up + tremor)))
		_rot(sk, side + "LowerArm", Basis(rx, -(g * 1.15 + arms_in * 0.35 + talk_beat * 0.65 + hold * (0.35 + strain * 0.25) - knock * 0.2)))
		_rot(sk, side + "Hand", Basis(rx, talk * sin(_t * 3.7 + s) * 0.18 - g * 0.2 + hold * 0.55 + tremor * 2.0))


## Now and then, standing idle, a whole-body gesture from her mood (from the animation library): folded arms when
## frustrated, a neck stretch when tired / stiff after a fight, a stretch of the arms after resting.
var _next_gesture := 12.0


func _mood_gestures(m: Dictionary, tired: float, moving: bool) -> void:
	if _t < _next_gesture or moving or c.casting or c.seated or c.ground_pose != "" or c.combat_stance or speaking:
		return
	if c.current_action != "idle":
		return
	_next_gesture = _t + randf_range(14.0, 26.0)
	var g := ""
	if float(m.get("frustrated", 0.0)) > 0.4 or float(m.get("determined", 0.0)) > 0.6:
		g = "idle_folded"
	elif tired > 0.4 or injury > 0.35:
		g = "stretch_neck"
	elif float(m.get("happy", 0.0)) > 0.5 and randf() < 0.4:
		g = "stretch_arms"
	if g != "" and c.play_gesture(g, 0.5, 0.7):
		log.append({"t": snappedf(_t, 0.1), "event": "gesture", "gesture": g})


## Rotate a bone by `delta` expressed in skeleton space (around its current orientation), plus an optional offset.
func _rot(sk: Skeleton3D, bone: String, delta: Basis, offset := Vector3.ZERO) -> void:
	var bi: int = _bones.get(bone, -1)
	if bi < 0:
		return
	var gp := sk.get_bone_global_pose(bi)
	var parent := sk.get_bone_parent(bi)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var ng := Transform3D(delta * gp.basis, gp.origin + offset)
	var local := pg.affine_inverse() * ng
	sk.set_bone_pose_rotation(bi, local.basis.get_rotation_quaternion())
	if offset != Vector3.ZERO:
		sk.set_bone_pose_position(bi, local.origin)


func status() -> Dictionary:
	return {"injury": snappedf(injury, 0.01), "side": injury_side, "exertion": snappedf(exertion, 0.01), "speaking": speaking, "tempo": snappedf(tempo(), 0.01),
		"channels": _cur.keys().map(func(k): return [k, snappedf(float(_cur[k]), 0.02)])}
