class_name DanceDeck
extends SkeletonModifier3D
## The lake duet's dancing (2026-10-19, Selwyn: "these 6 are the ONLY motions allowed in the lake dance. No hip hop,
## no other Mixamo clips, no code-made poses"): plays his six Mixamo dance clips (retargeted through the Mixamo bone
## map at import) straight onto her skeleton, crossfading from one to the next and starting any clip at any point,
## at any speed - so a routine can be cut from the six and timed to music. First in her modifier stack: it replaces
## the animation tree's pose; the softness pass, the dress sim and the drape all run after it. The hips keep their
## height and their sway (the weight shifts that make a dance breathe) but not the clip's travel: the slow drift is
## taken out (a 2.4 s moving average) so she stays on her mark. (Locked flat, she looked stiff and robotic.)

const DIR := "res://assets/animations/mixamo/"
const FILES := {"dancing_a": "lake_dancing_a.fbx", "dancing_b": "lake_dancing_b.fbx", "bellydancing": "lake_bellydancing.fbx",
	"belly_dance": "lake_belly_dance.fbx", "rumba": "lake_rumba.fbx", "samba": "lake_samba.fbx"}

static var _anims := {}                 # clip -> Animation (shared by both dancers)

var _maps := {}                         # clip -> [[track, bone, is_position]]
var _hips := -1
var _cur := {}                          # {clip, t, speed}
var _prev := {}
var _fade := 1.0
var _fade_len := 1.0
# her face while she dances (Selwyn: "the expressions when dancing are so bad, like they are not enjoying it"): a held
# smile in her own manner, and every few seconds a burst of joy - a laugh, a wink, a spark at each new move
const FACE := {
	"mika": {"hold": ["happy", 0.85], "bursts": [["excited", 0.9], ["laughing", 0.8], ["playful", 0.9], ["happy", 1.0], ["proud", 0.8]]},
	"luna": {"hold": ["happy", 0.6], "bursts": [["relaxed", 0.9], ["proud", 0.8], ["playful", 0.8], ["happy", 0.9], ["laughing", 0.55]]},
}
const DESPIKE_H := 1.0 / 30.0
const DESPIKE_RAD := 0.06               # ~3.4 deg of out-and-back is motion; more is a bad key
const WRAP_FADE := 0.45                 # s: a clip that runs past its end crossfades into its start (they are not loops)
var face_on := true
var _face_held := false
var _next_burst := 1.5
var _rng := RandomNumberGenerator.new()


static func clip_anim(clip: String) -> Animation:
	if not _anims.has(clip):
		var src: Node = (load(DIR + FILES[clip]) as PackedScene).instantiate()
		var ap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
		_anims[clip] = ap.get_animation("mixamo_com")
		src.free()
	return _anims[clip]


static func clip_length(clip: String) -> float:
	return clip_anim(clip).length


static func make(sk: Skeleton3D) -> DanceDeck:
	var d := DanceDeck.new()
	d.name = "DanceDeck"
	d.influence = 0.0
	sk.add_child(d)
	PosePipeline.arrange_for(sk)
	return d


## Crossfade (over `fade` s) into `clip`, starting `start` s into it, playing at `speed`.
func play(clip: String, start := 0.0, speed := 1.0, fade := 0.8) -> void:
	_prev = _cur
	_cur = {"clip": clip, "t": start, "speed": speed}
	_fade = 0.0
	_fade_len = maxf(fade, 0.001)
	if influence > 0.5 and not _prev.is_empty() and String(_prev.get("clip", "")) != clip:
		_burst(["excited", 0.9])                       # (a new move: a spark of joy)


## Puts the current clip at `t` s (after slow motion, at a cut: back in step with the music).
func sync(t: float) -> void:
	if not _cur.is_empty():
		_cur.t = t


func current() -> String:
	return String(_cur.get("clip", ""))


func _map(clip: String) -> Array:
	if _maps.has(clip):
		return _maps[clip]
	var sk := get_skeleton()
	var a := clip_anim(clip)
	var out := []
	for t in a.get_track_count():
		var bone := String(a.track_get_path(t)).get_slice(":", 1)
		var bi := sk.find_bone(bone)
		if bi < 0:
			continue
		var ty := a.track_get_type(t)
		if ty == Animation.TYPE_ROTATION_3D:
			out.append([t, bi, false])
		elif ty == Animation.TYPE_POSITION_3D and bone == "Hips":
			out.append([t, bi, true])
			_hips = bi
	_maps[clip] = out
	return out


func _process(delta: float) -> void:
	for p in [_cur, _prev]:
		if not p.is_empty():
			p.t = float(p.t) + delta * float(p.speed)
	_fade = minf(_fade + delta / _fade_len, 1.0)
	if not _cur.is_empty() and float(_cur.t) >= clip_length(String(_cur.clip)) and _fade >= 1.0:
		# the end of a clip that is not a loop: a crossfade back to its start, never a snap to its first frame
		_prev = _cur.duplicate()
		_cur.t = float(_cur.t) - clip_length(String(_cur.clip))
		_fade = 0.0
		_fade_len = WRAP_FADE
	_face(delta)


func _dancer() -> WorldCharacter:
	var n := get_parent()
	while n != null and not (n is WorldCharacter):
		n = n.get_parent()
	return n as WorldCharacter


## Her face while she dances; given back the moment the dance ends.
func _face(delta: float) -> void:
	var c := _dancer()
	if c == null or c.face == null:
		return
	var dancing := face_on and influence > 0.5 and not _cur.is_empty()
	if not dancing:
		if _face_held:
			_face_held = false
			c.face.set_hold("")
		return
	var cfg: Dictionary = FACE.get(c.character_id, FACE.luna)
	if not _face_held or c.face.hold.is_empty():
		_face_held = true
		c.face.set_hold(String(cfg.hold[0]), float(cfg.hold[1]))
	_next_burst -= delta
	if _next_burst <= 0.0:
		var bursts: Array = cfg.bursts
		_burst(bursts[_rng.randi() % bursts.size()])


func _burst(b: Array) -> void:
	var c := _dancer()
	if c == null or c.face == null:
		return
	_next_burst = _rng.randf_range(2.0, 4.5)
	c.face.pulse(String(b[0]), float(b[1]), _rng.randf_range(0.8, 1.6), 0.18, 0.7)


func _sample(p: Dictionary) -> Dictionary:
	var out := {}
	if p.is_empty():
		return out
	var a := clip_anim(String(p.clip))
	var t := fposmod(float(p.t), a.length)
	var ms := get_skeleton().motion_scale
	for m in _map(String(p.clip)):
		if m[2]:
			var v: Vector3 = a.position_track_interpolate(int(m[0]), t)
			var v0: Vector3 = a.position_track_interpolate(int(m[0]), 0.0)
			var avg := Vector3.ZERO
			for k in 7:
				avg += a.position_track_interpolate(int(m[0]), fposmod(t + (k - 3) * 0.4, a.length))
			avg /= 7.0
			var sway := Vector3(v.x - avg.x, 0.0, v.z - avg.z).limit_length(0.22)
			out[-1 - int(m[1])] = Vector3(v0.x + sway.x, v.y, v0.z + sway.z) * ms        # (positions keyed by -1 - bone)
		else:
			# despiked: a frame either side; a keyframe that jumps out and straight back (the Mixamo clips have a
			# few: 9-13 deg on the feet and shins of dancing_b every loop) gives way to the path between them
			var q := a.rotation_track_interpolate(int(m[0]), t)
			var q0 := a.rotation_track_interpolate(int(m[0]), fposmod(t - DESPIKE_H, a.length))
			var q1 := a.rotation_track_interpolate(int(m[0]), fposmod(t + DESPIKE_H, a.length))
			var excess := q0.angle_to(q) + q.angle_to(q1) - q0.angle_to(q1)
			if excess > DESPIKE_RAD:
				q = q.slerp(q0.slerp(q1, 0.5), clampf((excess - DESPIKE_RAD) / DESPIKE_RAD, 0.0, 1.0))
			out[int(m[1])] = q
	return out


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _cur.is_empty():
		return
	var b := _sample(_cur)
	var w := smoothstep(0.0, 1.0, _fade)
	var a := _sample(_prev) if w < 1.0 else {}
	for k in b:
		var vb = b[k]
		var va = a.get(k, null)
		if int(k) >= 0:
			var q: Quaternion = vb if va == null else (va as Quaternion).slerp(vb, w)
			sk.set_bone_pose_rotation(int(k), q)
		else:
			var v: Vector3 = vb if va == null else (va as Vector3).lerp(vb, w)
			sk.set_bone_pose_position(-1 - int(k), v)
