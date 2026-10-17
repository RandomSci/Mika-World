class_name FaceController
extends RefCounted
## Expressive faces for every VRoid mage (Milestone K) — a port of Mika-Character-Lab's ExpressionController
## (`src/face/ExpressionController.js`) to Godot. It drives the face mesh's own VRoid morphs (Fcl_BRW_* brows,
## Fcl_EYE_* eyes, Fcl_MTH_* mouth, Fcl_MTH_A/I/U/E/O visemes) directly at runtime, so NO VRM file is modified
## (Mika's Level 10 form and both Luna models are marked `modification: prohibited`).
##
##   * emotions are recipes over brow / eye / mouth components, blended by intensity, normalised per facial region
##     and smoothed by per-component damped springs (brows lead, eyes follow, mouth settles slowest)
##   * three layers: a BASELINE mood from her real state (tired, focused, at ease…), short event PULSES that decay
##     back (surprise at a hit, joy at a discovery), and an optional HOLD (a conversation line's emotion)
##   * natural blinking: asymmetric profile (close 70 ms, hold 40 ms, open 130 ms), personal interval, occasional
##     double blinks, a blink on large gaze shifts, suppressed while the eyes are closed by a smile
##   * speech visemes from the voice amplitude (A / O / I / U / E mixed from the envelope), smile yields to speech
##   * posture hints (head tilt / pitch, gaze up / down) read by HeadPosture
##   * personality: `expressiveness` scales everything (Mika warm and open, Luna composed), per-emotion biases
## Expressions only come from callers that observed something; nothing here fires on a timer except blinking.

const COMPONENTS := {
	"brow_angry": "Fcl_BRW_Angry", "brow_fun": "Fcl_BRW_Fun", "brow_joy": "Fcl_BRW_Joy", "brow_sorrow": "Fcl_BRW_Sorrow", "brow_surprised": "Fcl_BRW_Surprised",
	"eye_natural": "Fcl_EYE_Natural", "eye_angry": "Fcl_EYE_Angry", "eye_fun": "Fcl_EYE_Fun", "eye_joy": "Fcl_EYE_Joy", "eye_joy_r": "Fcl_EYE_Joy_R", "eye_joy_l": "Fcl_EYE_Joy_L",
	"eye_sorrow": "Fcl_EYE_Sorrow", "eye_surprised": "Fcl_EYE_Surprised", "eye_spread": "Fcl_EYE_Spread",
	"mouth_close": "Fcl_MTH_Close", "mouth_up": "Fcl_MTH_Up", "mouth_down": "Fcl_MTH_Down", "mouth_angry": "Fcl_MTH_Angry", "mouth_small": "Fcl_MTH_Small",
	"mouth_large": "Fcl_MTH_Large", "mouth_neutral": "Fcl_MTH_Neutral", "mouth_fun": "Fcl_MTH_Fun", "mouth_joy": "Fcl_MTH_Joy", "mouth_sorrow": "Fcl_MTH_Sorrow",
	"mouth_surprised": "Fcl_MTH_Surprised", "mouth_fang": "Fcl_MTH_SkinFung",
	"blink": "Fcl_EYE_Close", "blink_r": "Fcl_EYE_Close_R", "blink_l": "Fcl_EYE_Close_L",
	"v_a": "Fcl_MTH_A", "v_i": "Fcl_MTH_I", "v_u": "Fcl_MTH_U", "v_e": "Fcl_MTH_E", "v_o": "Fcl_MTH_O",
}

## Recipes (from the lab, extended with the states the world needs: concentrating, concerned, tired, listening).
const EMOTIONS := {
	"neutral": {"face": {}, "posture": {}},
	"happy": {"face": {"brow_joy": .65, "eye_fun": .35, "eye_joy": .28, "mouth_up": .7, "mouth_fun": .3, "blush": .3}, "posture": {"roll": .06}},
	"excited": {"face": {"brow_surprised": .35, "brow_joy": .55, "eye_spread": .2, "eye_joy": .15, "mouth_joy": .8, "blush": .3}, "posture": {"pitch": -.05}},
	"surprised": {"face": {"brow_surprised": 1.0, "eye_surprised": .7, "eye_spread": .35, "mouth_surprised": .7}, "posture": {"pitch": -.08}},
	"curious": {"face": {"brow_surprised": .35, "brow_fun": .3, "eye_spread": .18, "mouth_small": .45}, "posture": {"roll": .16, "pitch": .03}},
	"confused": {"face": {"brow_sorrow": .5, "brow_angry": .25, "eye_angry": .12, "mouth_sorrow": .25, "mouth_small": .35}, "posture": {"roll": -.18}},
	"concerned": {"face": {"brow_sorrow": .7, "eye_sorrow": .25, "mouth_small": .3, "mouth_down": .25}, "posture": {"pitch": .04}},
	"concentrating": {"face": {"brow_angry": .35, "brow_sorrow": .15, "eye_angry": .22, "mouth_close": .35, "mouth_small": .2}, "posture": {"pitch": .05}},
	"thoughtful": {"face": {"brow_sorrow": .25, "brow_angry": .15, "eye_fun": .2, "mouth_small": .4}, "posture": {"roll": .1, "gaze_up": .6}},
	"listening": {"face": {"brow_fun": .25, "eye_natural": .2, "mouth_up": .2}, "posture": {"roll": .07}},
	"shy": {"face": {"brow_sorrow": .55, "eye_fun": .5, "mouth_small": .6, "mouth_up": .3, "blush": 1.0}, "posture": {"pitch": .16, "roll": .12, "gaze_down": .6}},
	"sad": {"face": {"brow_sorrow": 1.0, "eye_sorrow": .7, "mouth_sorrow": .8, "mouth_down": .2}, "posture": {"pitch": .14, "gaze_down": .3}},
	"frustrated": {"face": {"brow_angry": .8, "eye_angry": .45, "mouth_angry": .6}, "posture": {"pitch": .06}},
	"tired": {"face": {"brow_sorrow": .25, "eye_fun": .3, "blink": .32, "mouth_neutral": .3}, "posture": {"pitch": .1, "roll": .08}},
	"relaxed": {"face": {"brow_fun": .4, "eye_fun": .4, "mouth_up": .5}, "posture": {"roll": .05}},
	"playful": {"face": {"brow_fun": .5, "eye_joy_l": .9, "mouth_fang": .45, "mouth_up": .6, "blush": .25}, "posture": {"roll": .15}},
	"proud": {"face": {"brow_fun": .5, "eye_fun": .25, "mouth_up": .65}, "posture": {"pitch": -.1}},
	"relieved": {"face": {"brow_sorrow": .3, "brow_joy": .3, "eye_fun": .45, "mouth_up": .45, "blush": .15}, "posture": {"pitch": .03, "roll": .04}},
	"laughing": {"face": {"brow_joy": .85, "eye_joy": 1.0, "mouth_joy": 1.0, "blush": .5}, "posture": {"pitch": -.08, "roll": .08}},
	"hurt": {"face": {"brow_sorrow": .75, "brow_angry": .3, "eye_angry": .55, "mouth_angry": .35, "mouth_small": .2}, "posture": {"pitch": .08}},
	"dazed": {"face": {"brow_sorrow": .45, "blink": .42, "eye_sorrow": .2, "mouth_small": .35, "mouth_down": .2}, "posture": {"roll": .12, "pitch": .1}},
	"determined": {"face": {"brow_angry": .9, "eye_angry": .45, "eye_spread": .1, "mouth_close": .45, "mouth_angry": .25, "mouth_up": .1}, "posture": {"pitch": -.06}},
}

## Legacy single-preset names (older callers) -> emotions.
const LEGACY := {"happy": "happy", "relaxed": "relaxed", "surprised": "surprised", "angry": "frustrated", "sad": "sad"}
## Day 3: components a model lacks (Luna's VRoid face has no EYE_Fun / EYE_Spread / MTH_Small / MTH_Close / MTH_Large /
## SkinFung) borrow the nearest shape it has, scaled, instead of silently doing nothing
const FALLBACK := {"eye_fun": ["eye_joy", 0.45], "eye_spread": ["eye_surprised", 0.5], "mouth_small": ["v_u", 0.3],
	"mouth_close": ["mouth_neutral", 0.6], "mouth_large": ["v_a", 0.3], "mouth_fang": ["mouth_up", 0.3]}
const HALFLIFE := {"brow": 0.07, "eye": 0.09, "mouth": 0.11, "other": 0.09}

var c: Node3D                       # the WorldCharacter
var face: MeshInstance3D
var idx := {}                       # component -> blend shape index
var springs := {}                   # component -> [value, velocity]
var expressiveness := 1.0
var bias := {}                      # emotion -> multiplier (personality)
var blink_mean := 3.6               # seconds between blinks (personal)
var baseline := {}                  # emotion -> intensity, from her state (set by Affect)
var pulses: Array = []              # [{emotion, peak, t, attack, hold, release}]
var hold := {}                      # emotion -> intensity while a line / scene lasts
var overrides := {}                 # component -> weight (direct)
var mouth_amp := 0.0                # speech envelope (0..1), from the voice
var posture := {}
var _mix := {}                      # smoothed emotion intensities
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _next_blink := 1.5
var _blink_t := -1.0
var _double := false
var _viseme := "v_a"
var _viseme_t := 0.0
var log: Array = []                 # recent emotion changes (tests / overlay)
## Day 3: the model's own blush (a separate Face_Blush mesh with one "Blush" morph), driven by the recipes' "blush"
var blush_mesh: MeshInstance3D
var blush_idx := -1
var _blush := 0.0
## Day 3: while a close-up is live, expressions read a little stronger (CloseupLook sets it)
var closeup_boost := 1.0
var brow_overlay: MeshInstance3D    # brows drawn through the fringe (the lab's technique; VRoid bangs hide them)
var _brow_mat: StandardMaterial3D
var brow_alpha := 0.45
var debug_brow := []
## Day 3 (per character, from the face config): a resting shape (Luna's lids sit wider open), the fallbacks in use,
## and how far the mouth opens while she talks
var rest := {}
var alias := {}
var mouth_scale := 1.0


## A blend shape by its VRoid component name. Models rebuilt in Blender (the level 1-10 Celestial stages) keep the
## VRoid morphs but carry a mesh prefix ("Face.M_F00_000_00_Fcl_BRW_Joy"): match the name or its suffix.
static func find_shape(m: MeshInstance3D, comp: String) -> int:
	var i := m.find_blend_shape_by_name(comp)
	if i >= 0:
		return i
	for k in m.mesh.get_blend_shape_count():
		var n := String(m.mesh.get_blend_shape_name(k))
		if n.ends_with("_" + comp) or n.ends_with("." + comp):
			return k
	return -1


static func attach(character: Node3D, avatar: Node, cfg: Dictionary) -> FaceController:
	var fc := FaceController.new()
	fc.c = character
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh and m.mesh.get_blend_shape_count() > 20 and find_shape(m, "Fcl_BRW_Joy") >= 0:
			fc.face = m
			break
	if fc.face == null:
		return null
	for k in COMPONENTS:
		var i := find_shape(fc.face, COMPONENTS[k])
		if i >= 0:
			fc.idx[k] = i
			fc.springs[k] = [0.0, 0.0]
	fc.expressiveness = float(cfg.get("expressiveness", 1.0))
	for mi2 in avatar.find_children("Face_Blush*", "MeshInstance3D", true, false):
		var bm := mi2 as MeshInstance3D
		if bm.mesh and bm.mesh.get_blend_shape_count() > 0:
			fc.blush_mesh = bm
			fc.blush_idx = maxi(bm.find_blend_shape_by_name("Blush"), 0)
			bm.set_blend_shape_value(fc.blush_idx, 0.0)
			break
	for k in (FALLBACK if bool(cfg.get("fallbacks", false)) else {}):      # (opt-in: Mika's approved face is unchanged)
		if not fc.idx.has(k) and fc.idx.has(FALLBACK[k][0]):
			fc.alias[k] = FALLBACK[k]
	fc.rest = cfg.get("rest", {})
	fc.mouth_scale = float(cfg.get("mouth_scale", 1.0))
	fc.bias = cfg.get("bias", {})
	fc.blink_mean = float(cfg.get("blink_mean", 3.6))
	fc._rng.seed = hash(String(character.get("character_id"))) + 17
	fc._next_blink = fc._rng.randf_range(0.8, 2.5)
	# the importer's whole-face presets must not fight the component layer: zero every other morph once
	for i in fc.face.mesh.get_blend_shape_count():
		fc.face.set_blend_shape_value(i, 0.0)
	if bool(cfg.get("brows_through_fringe", true)):
		fc._build_brow_overlay(float(cfg.get("brow_alpha", 0.45)))
	return fc


## The lab's "brows through the fringe": a one-surface copy of the brow geometry (same skin, same blend shapes)
## drawn after everything without depth test, faintly and in the hair's tint, so brow acting reads through the
## bangs; it fades out as she turns away from the camera. The VRM itself is untouched.
func _build_brow_overlay(alpha: float) -> void:
	var src := face.mesh as ArrayMesh
	if src == null:
		return
	var si := -1
	for i in src.get_surface_count():
		var m := src.surface_get_material(i)
		if m and "FaceBrow" in m.resource_name:
			si = i
	if si < 0:
		return
	var am := ArrayMesh.new()
	am.blend_shape_mode = src.blend_shape_mode
	for b in src.get_blend_shape_count():
		am.add_blend_shape(src.get_blend_shape_name(b))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(si), src.surface_get_blend_shape_arrays(si))
	_brow_mat = StandardMaterial3D.new()
	_brow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_brow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_brow_mat.no_depth_test = true
	_brow_mat.render_priority = 20
	_brow_mat.cull_mode = BaseMaterial3D.CULL_BACK
	var sm := src.surface_get_material(si) as ShaderMaterial
	if sm and sm.get_shader_parameter("_MainTex") is Texture2D:
		_brow_mat.albedo_texture = sm.get_shader_parameter("_MainTex")
	brow_alpha = alpha
	_brow_mat.albedo_color = Color(0.62, 0.58, 0.60, alpha)
	am.surface_set_material(0, _brow_mat)
	brow_overlay = MeshInstance3D.new()
	brow_overlay.name = "BrowOverlay"
	brow_overlay.mesh = am
	brow_overlay.skin = face.skin
	brow_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.get_parent().add_child(brow_overlay)
	brow_overlay.transform = face.transform
	brow_overlay.skeleton = brow_overlay.get_path_to(face.get_node(face.skeleton))


# ------------------------------------------------------------------ API
## A short reaction to something observed: rises over `attack`, holds, then fades back to her baseline.
func pulse(emotion: String, intensity := 1.0, hold_s := 1.2, attack := 0.12, release := 0.9) -> void:
	if not EMOTIONS.has(emotion):
		return
	pulses = pulses.filter(func(p): return p.emotion != emotion)
	# anime faces read at stream distance only with committed shapes: events land a little above the recipe
	pulses.append({"emotion": emotion, "peak": intensity * 1.2, "t": 0.0, "attack": attack, "hold": hold_s, "release": release})
	_note(emotion, intensity, "pulse")


## Hold an emotion while something lasts (a conversation line, a concentrated cast); "" clears.
func set_hold(emotion: String, intensity := 1.0) -> void:
	hold.clear()
	if emotion != "" and EMOTIONS.has(emotion):
		hold[emotion] = intensity
		_note(emotion, intensity, "hold")


func set_baseline(mix: Dictionary) -> void:
	baseline = mix


## Old API (set_expression("happy", 0.6)): a held pulse that fades when the weight returns to 0.
func legacy(ex: String, weight: float) -> void:
	if ex == "aa":
		mouth_amp = weight
		return
	if ex == "blink":
		if weight > 0.0:
			overrides["blink"] = weight
		else:
			overrides.erase("blink")
		return
	var e: String = LEGACY.get(ex, ex)
	if weight <= 0.001:
		pulses = pulses.filter(func(p): return p.emotion != e)
		hold.erase(e)
	else:
		hold[e] = weight


func blink_now() -> void:
	if _blink_t < 0.0:
		_blink_t = 0.0


func bound_count() -> int:
	return idx.size()


func dominant() -> String:
	var best := "neutral"
	var bv := 0.15
	for e in _mix:
		if float(_mix[e]) > bv:
			bv = float(_mix[e])
			best = e
	return best


# ------------------------------------------------------------------ per frame
func update(delta: float) -> void:
	if face == null or not is_instance_valid(face):
		return
	_t += delta
	# 1) target emotion mix = baseline + held + decaying pulses (scaled by personality)
	var target := {}
	for e in baseline:
		target[e] = float(target.get(e, 0.0)) + float(baseline[e])
	for e in hold:
		target[e] = maxf(float(target.get(e, 0.0)), float(hold[e]))
	var keep := []
	for p in pulses:
		p.t += delta
		var k := 0.0
		if p.t < p.attack:
			k = p.t / p.attack
		elif p.t < p.attack + p.hold:
			k = 1.0
		else:
			k = 1.0 - (p.t - p.attack - p.hold) / p.release
		if k > 0.0:
			keep.append(p)
			target[p.emotion] = maxf(float(target.get(p.emotion, 0.0)), float(p.peak) * smoothstep(0.0, 1.0, k))
	pulses = keep
	# 2) smooth emotion intensities (cross-blend)
	var all := {}
	for e in target:
		all[e] = true
	for e in _mix:
		all[e] = true
	for e in all:
		var want := float(target.get(e, 0.0)) * expressiveness * closeup_boost * float(bias.get(e, 1.0))
		_mix[e] = lerpf(float(_mix.get(e, 0.0)), want, 1.0 - exp(-delta * 7.0))
		if float(_mix[e]) < 0.002 and want == 0.0:
			_mix.erase(e)
	# 3) compose component targets from recipes; posture hints
	var comp := {}
	posture = {}
	for e in _mix:
		var w := clampf(float(_mix[e]), 0.0, 1.5)
		var r: Dictionary = EMOTIONS.get(e, {})
		for k in r.get("face", {}):
			comp[k] = float(comp.get(k, 0.0)) + float(r.face[k]) * w
		for k in r.get("posture", {}):
			posture[k] = float(posture.get(k, 0.0)) + float(r.posture[k]) * w
	for k in overrides:
		comp[k] = float(overrides[k])
	for k in alias:
		if comp.has(k):
			comp[alias[k][0]] = float(comp.get(alias[k][0], 0.0)) + float(comp[k]) * float(alias[k][1])
			comp.erase(k)
	# 4) per-region normalisation (a region never shows more than reads cleanly)
	var sums := {}
	for k in comp:
		var rg := _region(k)
		if rg != "other":
			sums[rg] = float(sums.get(rg, 0.0)) + float(comp[k])
	for k in comp.keys():
		var rg2 := _region(k)
		var lim := 1.15 if rg2 == "mouth" else 1.4
		if float(sums.get(rg2, 0.0)) > lim:
			comp[k] = float(comp[k]) * lim / float(sums[rg2])
	# 4b) the resting shape, yielding to whatever the region is already doing
	for k in rest:
		var busy := 0.0
		for k2 in comp:
			if k2 != k and _region(k2) == _region(k):
				busy += float(comp[k2])
		comp[k] = float(comp.get(k, 0.0)) + float(rest[k]) * (1.0 - clampf(busy * 1.5, 0.0, 1.0))
	# 5) speech: visemes from the envelope take the mouth over, smile shapes yield
	if mouth_amp > 0.02:
		_viseme_t -= delta
		if _viseme_t <= 0.0:
			_viseme_t = _rng.randf_range(0.07, 0.14)
			var pool := ["v_a", "v_a", "v_o", "v_e", "v_i", "v_u"]
			_viseme = pool[_rng.randi() % pool.size()]
		var a := clampf(mouth_amp * 1.4 * mouth_scale, 0.0, 0.9)
		comp[_viseme] = a
		comp["v_a"] = maxf(float(comp.get("v_a", 0.0)), a * 0.35)
		var y := clampf(1.0 - a * 0.8, 0.25, 1.0)
		for k in comp.keys():
			if String(k).begins_with("mouth_"):
				comp[k] = float(comp[k]) * y
	# 6) micro-variation so a held face stays alive
	comp["brow_fun"] = float(comp.get("brow_fun", 0.0)) + 0.035 * maxf(0.0, sin(_t * 0.6) * sin(_t * 0.23 + 1.0))
	# 7) blink (suppressed while a smile already closes the eyes)
	var closed := clampf(float(comp.get("eye_joy", 0.0)) + float(comp.get("blink", 0.0)) * 0.8, 0.0, 1.0)
	comp["blink"] = clampf(float(comp.get("blink", 0.0)) + _blink(delta) * (1.0 - closed), 0.0, 1.0)
	for k in rest:                    # a blink closes over the resting lids too
		if _region(k) == "eye":
			comp[k] = float(comp.get(k, 0.0)) * (1.0 - float(comp["blink"]))
	# 7b) blush (its own mesh): slow in, slower out, like real colour
	if blush_mesh and is_instance_valid(blush_mesh):
		var bgoal := clampf(float(comp.get("blush", 0.0)), 0.0, 1.0)
		_blush = lerpf(_blush, bgoal, 1.0 - pow(0.5, delta / (0.35 if bgoal > _blush else 0.9)))
		blush_mesh.set_blend_shape_value(blush_idx, _blush)
	# 8) springs per component -> blend shapes
	var mirror := brow_overlay != null and is_instance_valid(brow_overlay)
	for k in idx:
		var goal := clampf(float(comp.get(k, 0.0)), 0.0, 1.0)
		var s: Array = springs[k]
		var hl: float = 0.012 if k == "blink" else (0.03 if String(k).begins_with("v_") else float(HALFLIFE[_region(k)]))
		var kk := 1.0 - pow(0.5, delta / hl)
		s[0] = lerpf(float(s[0]), goal, kk)
		face.set_blend_shape_value(int(idx[k]), float(s[0]))
		if mirror:
			brow_overlay.set_blend_shape_value(int(idx[k]), float(s[0]))
	# 9) brow overlay: visible from the front only (fades as the head turns away from the camera)
	if mirror:
		var cam := face.get_viewport().get_camera_3d()
		var k2 := 0.0
		if cam:
			var sk: Skeleton3D = c.get("skeleton")
			var hb := sk.find_bone("Head") if sk else -1
			var head_xf: Transform3D = sk.global_transform * sk.get_bone_global_pose(hb) if hb >= 0 else face.global_transform
			# forward = from the head bone toward the midpoint of the eyes (independent of bone axis conventions)
			var le := sk.find_bone("LeftEye") if sk else -1
			var re := sk.find_bone("RightEye") if sk else -1
			var head_fwd := -c.global_transform.basis.z
			if le >= 0 and re >= 0:
				var eyes := sk.global_transform * ((sk.get_bone_global_pose(le).origin + sk.get_bone_global_pose(re).origin) * 0.5)
				var v := eyes - head_xf.origin
				v.y = 0.0
				if v.length() > 0.01:
					head_fwd = v.normalized()
			var to_cam := cam.global_position - head_xf.origin
			to_cam.y *= 0.5
			to_cam = to_cam.normalized()
			k2 = smoothstep(0.25, 0.6, head_fwd.dot(to_cam))
			debug_brow = [head_fwd, to_cam, k2, head_xf.origin, cam.global_position, c.global_position, cam.name]
		_brow_mat.albedo_color.a = brow_alpha * k2
		brow_overlay.visible = k2 > 0.01


func _blink(delta: float) -> float:
	if _blink_t < 0.0 and _t >= _next_blink:
		_blink_t = 0.0
		_double = _rng.randf() < 0.15
	if _blink_t < 0.0:
		return 0.0
	var b := _blink_t
	_blink_t += delta
	var v := b / 0.07 if b < 0.07 else (1.0 if b < 0.11 else (1.0 - (b - 0.11) / 0.13 if b < 0.24 else 0.0))
	if b >= 0.24:
		if _double:
			_double = false
			_blink_t = -1.0
			_next_blink = _t + 0.12
		else:
			_blink_t = -1.0
			# focused people blink less, tired people more
			var focus := float(_mix.get("concentrating", 0.0)) + float(_mix.get("listening", 0.0)) * 0.5
			var tired := float(_mix.get("tired", 0.0))
			_next_blink = _t + blink_mean * _rng.randf_range(0.6, 1.6) * (1.0 + focus * 0.6) / (1.0 + tired * 1.2)
	return v


static func _region(k: String) -> String:
	if k.begins_with("brow_"):
		return "brow"
	if k.begins_with("eye_"):
		return "eye"
	if k.begins_with("mouth_"):
		return "mouth"
	return "other"


func _note(e: String, w: float, how: String) -> void:
	log.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01), "emotion": e, "w": snappedf(w, 0.01), "how": how})
	if log.size() > 80:
		log.pop_front()
