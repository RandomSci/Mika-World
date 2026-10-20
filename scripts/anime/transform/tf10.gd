class_name Tf10
extends Node
## The Level 10 transformation (2026-10-20, Selwyn: Transformation_Kit_v1, "build the Level 10 transformation ... the
## exact timing" of tf_test_mika / tf_test_luna, 15 s in real time, in the world at night). Also his open Level 10
## review points: night look, nothing between the lens and her, smooth camera moves (no jump cuts), one flash style
## for both girls and at most 3 white frames, the skirt simulating with its leg colliders the whole time, a graceful
## descent, and each girl's clip her own.
##   0 to 3.5   gather     the kit's gather card at her feet, her halo sigil flat under her (whole sequence); eyes
##                         closed, prayer sign (tf_rise mocap, slowed to span 0 to 7 s)
##   3 to 7.5   spiral     the helix of light rising round her; she rises 1 m (3 to 7 s), arms opening, face lifting;
##                         her body turns to light (body_light, fresnel glow to a bright silhouette, 3 to 5.5 s)
##   7 to 11.5  cocoon     ribbons wrap her; inside, the old outfit (frozen, her last pose) burns away (burn_dissolve,
##                         8 to 10 s) while the new one stands in the same light, then the light dissolves from her head
##                         down (the vertical reveal, 10 to 11.5 s)
##   11 to 15   burst      two white frames and the kit's burst (much larger), petal rain from 12 s (Luna's tinted
##                         violet); she descends from 12.5 s, slowing to a soft touch down, into the reveal pose
##                         (tf_reveal mocap); the other girl reacts
## Camera: one continuous move per beat, each blended from the last (tweened cuts): her closed eyes, her hands, a slow
## orbit through the rise, a low wide hero shot at the burst, a medium on the pose, then both of them.
## Prints "[tf10] <t> <beat>".

const LEN := 15.0
const RISE_H := 1.0
const NIGHT := 22.5
const NEW_FORM := {"mika": "res://assets/characters/mika/stages/l10_starbloom/MikaStarbloom_L10Outfit.vrm",
	"luna": "res://assets/characters/luna/stages/l10_umbral/LunaUmbral_L10Outfit.vrm"}
## her colours for the light: [core, body, rim]
const COLORS := {"mika": [Color(1, 1, 1), Color(1.0, 0.8, 0.92), Color(1.0, 0.55, 0.8)],
	"luna": [Color(1, 1, 1), Color(0.82, 0.72, 1.0), Color(0.6, 0.4, 1.0)]}
const REACT := {"mika": "catch_falling_petal", "luna": "photo_frame_hands"}

var d: FightDirector
var who := ""
var other := ""
var c: WorldCharacter
var t := 0.0
var base := Vector3.ZERO
var light_mat: ShaderMaterial
var burn_mat: ShaderMaterial
var ghost: Node3D
var log: Array = []
var _ev: Array = []
var done := false
var _cover := 0.0
var _reveal_on := false


static func make(dir: FightDirector, w: String) -> Tf10:
	var tf := Tf10.new()
	tf.name = "Tf10_" + w
	tf.d = dir
	tf.who = w
	tf.other = "luna" if w == "mika" else "mika"
	tf.c = dir.F[w].c
	dir.add_child(tf)
	return tf


func _at(s: float, fn: Callable, label := "") -> void:
	_ev.append([s, fn, label])


var _hidden: Array = []


## Nothing between the lens and her (Selwyn's Level 10 review): the clearing's rune targets, torches and ruins' arch
## pieces near her are hidden for the sequence, shown again at its end.
func _hide_near() -> void:
	var root: Node = d.main.world if d.main.get("world") else d.main
	for n in root.find_children("*", "Node3D", true, false):
		var nd := n as Node3D
		if not nd.visible or nd is WorldCharacter:
			continue
		var nm := String(nd.name).to_lower()
		if not (nm.contains("rune") or nm.contains("target") or nm.contains("arch") or nm.contains("torch")):
			continue
		if d._flat(nd.global_position - base).length() < 12.0:
			nd.visible = false
			_hidden.append(nd)
	# the rune target boards (their posts, discs and sigils: MeleeSim._hide_props)
	var runes: Array = []
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n is RuneReactive:
			runes.append((n as Node3D).global_position)
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.visible or not gi.is_inside_tree():
			continue
		var cc := gi.global_transform * gi.get_aabb().get_center()
		for r in runes:
			if Vector2(cc.x - r.x, cc.z - r.z).length() < 0.75 and cc.y < r.y + 0.8 and cc.y > r.y - 1.6:
				gi.visible = false
				_hidden.append(gi)
				break


func start() -> void:
	base = d.pos(who)
	_hide_near()
	var cols: Array = COLORS[who]
	light_mat = ShaderMaterial.new()
	light_mat.shader = load("res://shaders/vfx/body_light.gdshader")
	light_mat.set_shader_parameter("core_color", cols[0])
	light_mat.set_shader_parameter("body_color", cols[1])
	light_mat.set_shader_parameter("rim_color", cols[2])
	light_mat.set_shader_parameter("glow", 1.15)
	light_mat.set_shader_parameter("flow", FX.noise())
	light_mat.set_shader_parameter("cover", 0.0)
	burn_mat = ShaderMaterial.new()
	burn_mat.shader = load("res://shaders/vfx/burn_dissolve.gdshader")
	burn_mat.set_shader_parameter("core_color", cols[0])
	burn_mat.set_shader_parameter("body_color", cols[1])
	burn_mat.set_shader_parameter("burn_color", cols[2])
	burn_mat.set_shader_parameter("glow", 1.3)
	burn_mat.set_shader_parameter("dissolve_texture", FX.noise())
	burn_mat.set_shader_parameter("dissolve_amount", 0.0)
	var feet := func() -> Vector3: return Vector3(base.x, FightDirector.ground_y(c, base) + 0.03, base.z)
	var body := func() -> Vector3: return Vector3(base.x, FightDirector.ground_y(c, base) + float(d.F[who].lift), base.z)
	var g := who
	# ---- the cards (the kit's timing)
	_at(0.0, func(): FlipbookFX.play(d.main, g + "_halo_sigil", feet, {"size": 3.2, "flat": true, "dur": LEN, "loop_s": 5.0, "fade_in": 0.6,
		"fade_out": 1.2, "intensity": 1.5, "light": 0.6, "black_cut": 0.16, "turn": 0.18}), "sigil")
	_at(0.0, func(): FlipbookFX.play(d.main, g + "_tf_gather", body, {"size": 3.6, "upright": true, "sink": 0.18, "dur": 3.5, "fade_in": 0.3,
		"fade_out": 0.5, "intensity": 1.1, "light": 0.3, "black_cut": 0.15, "near": 2.6}), "gather")
	_at(3.0, func(): FlipbookFX.play(d.main, g + "_tf_spiral", body, {"size": 3.4, "upright": true, "sink": 0.12, "dur": 4.5, "fade_in": 0.5,
		"fade_out": 0.6, "intensity": 1.5, "light": 2.0, "black_cut": 0.15, "near": 2.0}), "spiral")
	_at(7.0, func(): FlipbookFX.play(d.main, g + "_tf_cocoon", body, {"size": 3.1, "upright": true, "sink": 0.1, "dur": 4.5, "fade_in": 0.4,
		"fade_out": 0.4, "intensity": 1.4, "light": 2.2, "black_cut": 0.15, "near": 2.0}), "cocoon")
	_at(11.0, func(): FlipbookFX.play(d.main, g + "_tf_burst", body, {"size": 5.2, "upright": true, "sink": 0.3, "dur": 2.8, "fade_in": 0.05,
		"fade_out": 0.9, "intensity": 0.9 if who == "luna" else 0.6, "light": 0.8, "black_cut": 0.3, "near": 0.0, "edge_mask": 0.4, "edge_soft": 0.3,
		"dim_after": 0.3, "dim_to": 0.28 if who == "luna" else 0.18}), "burst")
	_at(12.0, func(): _petal_rain(2), "petal rain")
	_at(13.1, func(): _petal_rain(1), "petal rain behind the two-shot")
	# ---- the flash: the same for both girls, two white frames
	_at(11.0, func():
		if d.sfx:
			d.sfx.flash_seq([["white", 2]], 0.6), "flash")
	# ---- her body (the mocap through her pose stack)
	var L_rise := FightDeck.clip_length(c, "ml_tf_rise")
	_at(0.0, func():
		d.anim(who, "ml_tf_rise", 0.0, -1.0, L_rise / 7.0, 0.4)
		c.set_expression("blink", 1.0), "rise clip")
	_at(6.5, func(): c.set_expression("blink", 0.0), "eyes open")
	_at(8.0, func(): _swap(), "swap in the light")
	_at(11.55, func():
		var L_rev := FightDeck.clip_length(c, "ml_tf_reveal")
		d.anim(who, "ml_tf_reveal", 0.0, -1.0, L_rev / 3.45, 0.45), "reveal clip")
	# ---- the other girl: watching, then her reaction
	_at(0.4, func():
		var oc: WorldCharacter = d.F[other].c
		oc.set_expression("surprised", 0.6), "other watches")
	_at(12.8, func():
		var nm := "ml_" + String(REACT[who])
		if FightDeck.clip_length(d.F[other].c, nm) > 0.0:
			d.anim(other, nm, 0.0, -1.0, 1.0, 0.35)
		(d.F[other].c as WorldCharacter).set_expression("happy", 0.8), "other reacts")
	# ---- the camera: one continuous move per beat, blended from the last
	_at(0.0, func(): d.cut(d.ft + 0.001, "hero_low", who, {"exposure": 0.85}), "cam low hero")
	_at(2.0, func(): d.cut(d.ft + 0.001, "orbit_her", who, {"from": -55.0, "to": 35.0, "r": 4.6, "h": 0.5, "fov": 48.0, "tween": 2.2, "tween_trans": Tween.TRANS_SINE}), "cam orbit")
	_at(7.0, func(): d.cut(d.ft + 0.001, "orbit_her", who, {"from": 35.0, "to": 70.0, "r": 4.2, "h": 1.1, "fov": 46.0, "tween": 1.6, "tween_trans": Tween.TRANS_SINE}), "cam cocoon")
	_at(10.2, func(): d.cut(d.ft + 0.001, "hero_low", who, {"tween": 1.2, "tween_trans": Tween.TRANS_SINE}), "cam hero")
	_at(12.6, func(): d.cut(d.ft + 0.001, "orbit_her", who, {"from": 0.0, "to": 18.0, "r": 4.6, "h": 0.35, "fov": 46.0, "tween": 1.4, "tween_trans": Tween.TRANS_SINE}), "cam pose")
	_at(12.9, func(): d.cut(d.ft + 0.001, "fixed", who, _two_shot()), "cam both")
	_ev.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	# (the close ups crisp: half the bloom while they run, then back)
	var env: Environment = d.main.world.get("env") if d.main.get("world") and d.main.world.get("env") else null
	if env:
		var g0 := env.glow_intensity
		env.glow_intensity = g0 * 0.5
		_at(2.8, func(): create_tween().tween_property(env, "glow_intensity", g0, 1.0), "bloom back")
		_ev.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	print("[tf10] %s start at frame %d" % [who, Engine.get_frames_drawn()])


## The last 2 s: both girls in one medium two-shot from the side of the line between them, a little toward her (the
## other girl's reaction clearly in frame).
func _two_shot() -> Dictionary:
	var a := d.pos(who)
	var b := d.pos(other)
	var ax := d._flat(b - a)
	var gap := ax.length()
	ax = ax.normalized()
	var perp := ax.cross(Vector3.UP)
	var cam_o := get_viewport().get_camera_3d()
	if cam_o and perp.dot(cam_o.global_position - a) < 0.0:
		perp = -perp                                     # (the side the lens is already on: a glide, not a jump)
	var gy := FightDirector.ground_y(c, a)
	var mid := (a + b) * 0.5
	var look := Vector3(mid.x, gy + 1.1, mid.z)
	# (the side with a clear view of both: a trunk between pulled the lens in and lost the other girl)
	var pos := Vector3.ZERO
	var best := -1.0
	for sgn in [1.0, -1.0]:
		for dist in [gap * 0.8 + 2.0, gap * 0.8 + 1.2]:
			var cand: Vector3 = look + perp * sgn * dist + Vector3.UP * 0.2
			var got: Vector3 = d._unblock(look, cand)
			var clear := got.distance_to(look)
			if got.distance_to(cand) < 0.05:
				clear += 100.0
			if clear > best:
				best = clear
				pos = got
	print("[tf10] two-shot %s at %s, %s at %s (drawn %s, visible %s), lens %s looking at %s" % [who, str(a), other, str(b),
		str((d.F[other].c as Node3D).global_position), str((d.F[other].c as Node3D).is_visible_in_tree()), str(pos), str(look)])
	return {"pos": pos, "look": look, "fov": 50.0, "tween": 1.0, "tween_trans": Tween.TRANS_SINE}


## The old avatar handed over and frozen as burning light; the new one in her place, wearing the light already.
func _swap() -> void:
	var path: String = NEW_FORM[who]
	if c.avatar_path == path:
		return
	var deck_clip := "ml_tf_rise"
	if c.swap_avatar(path, null, null, true) and c.released_avatar:
		ghost = c.released_avatar
		c.released_avatar = null
		ghost.process_mode = Node.PROCESS_MODE_DISABLED
		d.main.add_child(ghost)
		ghost.global_transform = ghost.get_meta("released_xf", c.global_transform)
		for mi in ghost.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = null
			(mi as MeshInstance3D).material_override = burn_mat
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# her new skeleton gets the fight's deck and probe; the rise clip held where it was
	d.F[who].deck = FightDeck.make(c)
	d.F[who].probe = FightProbe.make(c.skeleton)
	PosePipeline.of(c).arrange()
	var L := FightDeck.clip_length(c, deck_clip)
	d.anim(who, deck_clip, maxf(L - 0.02, 0.0), L, 1.0, 0.01)
	c.set_expression("blink", 0.0)
	_light(c.avatar, true)
	var tw := create_tween()
	tw.tween_method(func(v: float): burn_mat.set_shader_parameter("dissolve_amount", v), 0.0, 1.0, 2.0)
	tw.tween_callback(func():
		if is_instance_valid(ghost):
			ghost.queue_free())


func _light(avatar: Node, on: bool) -> void:
	if avatar == null:
		return
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = light_mat if on else null


## Petal rain from 12 s: a few cards at depth BEHIND the girls as the lens sees them (her pose reads in front of it),
## half the old density; a second pair when the final two-shot starts. Luna's violet.
func _petal_rain(n := 2) -> void:
	var tint := Color(1, 1, 1) if who == "mika" else Color(0.72, 0.55, 1.0)
	var cam := get_viewport().get_camera_3d()
	var mid := (base + d.pos(other)) * 0.5
	var away := d._flat(mid - cam.global_position).normalized() if cam else d._flat(d.pos(other) - base).normalized()
	var across := away.cross(Vector3.UP)
	var spots := [[-1.4, 2.2, 4.0], [1.6, 3.0, 4.6]]
	for i in mini(n, spots.size()):
		var sp: Array = spots[i]
		var p: Vector3 = mid + across * float(sp[0]) + away * float(sp[1])
		p.y = FightDirector.ground_y(c, base) + 0.2
		var pf := func() -> Vector3: return p
		FlipbookFX.play(d.main, "mika_petal_rain", pf, {"size": float(sp[2]), "upright": true, "sink": 0.0, "dur": 3.0, "fade_in": 0.3,
			"fade_out": 0.9, "intensity": 0.7, "light": 0.3, "black_cut": 0.18, "near": 2.0, "tint": tint})


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	while not _ev.is_empty() and t >= float(_ev[0][0]):
		var e: Array = _ev.pop_front()
		(e[1] as Callable).call()
		if String(e[2]) != "":
			log.append([snappedf(t, 0.01), String(e[2])])
			print("[tf10] %.2f %s (frame %d)" % [t, String(e[2]), Engine.get_frames_drawn()])
	# the rise (3 to 7 s) and the descent (12.5 s on, slowing to a soft touch down)
	var lift := 0.0
	if t < 3.0:
		lift = 0.0
	elif t < 7.0:
		var u := (t - 3.0) / 4.0
		lift = RISE_H * u * u * (3.0 - 2.0 * u)
	elif t < 12.5:
		lift = RISE_H + 0.04 * sin((t - 7.0) * 1.6)                 # (floating, a breath of motion)
	else:
		var u2 := clampf((t - 12.5) / 2.3, 0.0, 1.0)
		lift = RISE_H * (1.0 - (1.0 - pow(1.0 - u2, 3.0)))          # ease out: fast at first, settling softly
	d.F[who].lift = lift
	# the body of light (3 to 5.5 s up, held; the vertical reveal 10 to 11.5 s from her head down)
	if t >= 3.0 and _cover < 1.0:
		_cover = clampf((t - 3.0) / 2.5, 0.0, 1.0)
		light_mat.set_shader_parameter("cover", _cover)
		if not _light_applied:
			_light_applied = true
			_light(c.avatar, true)
	if t >= 10.0 and t <= 11.6:
		var top := FightDirector.ground_y(c, base) + lift + 1.85
		var bot := FightDirector.ground_y(c, base) + lift - 0.1
		light_mat.set_shader_parameter("reveal_y", lerpf(top, bot, clampf((t - 10.0) / 1.5, 0.0, 1.0)))
	elif t > 11.6 and _cover > 0.0:
		_cover = 0.0
		_light(c.avatar, false)
	if t >= LEN:
		done = true
		for h in _hidden:
			if is_instance_valid(h):
				(h as Node3D).visible = true
		print("[tf10] %s end at frame %d" % [who, Engine.get_frames_drawn()])


var _light_applied := false
