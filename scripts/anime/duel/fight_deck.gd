class_name FightDeck
extends SkeletonModifier3D
## The fighters' motion (duel / training, 2026-10-19): DanceDeck generalised to ANY clip - the character's own
## library (WorldCharacter.CLIPS: Mixamo casts, UAL combat set, reactions), the Mixamo great-sword set
## ("sword:great_sword_kick", retargeted through the Mixamo bone map at import) and any UAL pack animation
## ("ual:Roll", "ual_react:NinjaJump_Land"). First in her modifier stack, so the softness pass (BodyLife, SoftArms),
## the dress simulation and the drape all run after it. Each move is a SEGMENT of a clip: [from, to] at a speed,
## crossfaded in, then held on its last frame (or looped) until the next move - so a combo is a chain of segments.
## The hips keep their height (jumps, crouches, the weight in a stance) but not the clip's travel: the fight
## director moves her body itself (dashes, knock-backs), so a clip never drags her off her mark.

const SWORD_DIR := "res://assets/animations/mixamo_sword/"
const UAL := {"ual": "res://assets/animations/ual/ual_combat.glb", "ual_rest": "res://assets/animations/ual/ual_rest.glb",
	"ual_react": "res://assets/animations/ual/ual_react.glb"}

static var _ext := {}                    # "sword:x" / "ual:x" -> Animation (shared by both fighters)

var c: WorldCharacter
var hips_lift := 0.0                     # metres added to the hips (a hop the clip does not have)
var _maps := {}                          # anim instance id -> [[track, bone, is_position]]
var _cur := {}                           # {anim, clip, t, from, to, speed, loop}
var _prev := {}
var _fade := 1.0
var _fade_len := 1.0
var log: Array = []                      # [clip, t] of each move started (QA)


static func make(ch: WorldCharacter) -> FightDeck:
	var d := FightDeck.new()
	d.name = "FightDeck"
	d.c = ch
	d.influence = 1.0
	ch.skeleton.add_child(d)
	ch.skeleton.move_child(d, 0)
	return d


## The Animation for a clip name: the character's library first, then "sword:<file>" / "<pack>:<anim>".
static func anim_for(ch: WorldCharacter, clip: String) -> Animation:
	if ch and ch.has_clip(clip):
		return ch.body_player.get_animation("mx/" + clip)
	if _ext.has(clip):
		return _ext[clip]
	var a: Animation = null
	if clip.begins_with("sword:"):
		var path := SWORD_DIR + clip.trim_prefix("sword:") + ".fbx"
		if ResourceLoader.exists(path):
			var src: Node = (load(path) as PackedScene).instantiate()
			var ap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
			if ap and ap.has_animation("mixamo_com"):
				a = ap.get_animation("mixamo_com")
			src.free()
	elif clip.contains(":"):
		var pid := clip.get_slice(":", 0)
		if UAL.has(pid) and ResourceLoader.exists(UAL[pid]):
			var src2: Node = (load(UAL[pid]) as PackedScene).instantiate()
			var ap2: AnimationPlayer = src2.find_child("AnimationPlayer", true, false)
			var an := clip.get_slice(":", 1)
			if ap2 and ap2.has_animation(an):
				a = ap2.get_animation(an)
			src2.free()
	if a == null:
		push_warning("[fight] no clip " + clip)
	_ext[clip] = a
	return a


static func clip_length(ch: WorldCharacter, clip: String) -> float:
	var a := anim_for(ch, clip)
	return a.length if a else 0.0


## Crossfade (over `fade` s) into `clip` from `from` s to `to` s (-1 = its end) at `speed`; afterwards the last frame
## holds (loop = false) or the segment repeats (loop = true).
func play(clip: String, from := 0.0, to := -1.0, speed := 1.0, fade := 0.15, loop := false) -> float:
	var a := anim_for(c, clip)
	if a == null:
		return 0.0
	var end := a.length if to < 0.0 else minf(to, a.length)
	_prev = _cur
	_cur = {"anim": a, "clip": clip, "t": from, "from": from, "to": end, "speed": speed, "loop": loop}
	_fade = 0.0 if not _prev.is_empty() else 1.0
	_fade_len = maxf(fade, 0.001)
	log.append([clip, snappedf(from, 0.01)])
	return (end - from) / maxf(speed, 0.01)


func current() -> String:
	return String(_cur.get("clip", ""))


## Seconds left in the current segment (0 once it holds).
func left() -> float:
	if _cur.is_empty():
		return 0.0
	return maxf(float(_cur.to) - float(_cur.t), 0.0) / maxf(float(_cur.speed), 0.01)


func set_speed(s: float) -> void:
	if not _cur.is_empty():
		_cur.speed = s


func _process(delta: float) -> void:
	for p in [_cur, _prev]:
		if p.is_empty():
			continue
		var t := float(p.t) + delta * float(p.speed)
		if t > float(p.to):
			t = float(p.from) + fposmod(t - float(p.from), maxf(float(p.to) - float(p.from), 0.01)) if p.loop else float(p.to)
		p.t = t
	_fade = minf(_fade + delta / _fade_len, 1.0)


func _map(a: Animation) -> Array:
	var key := a.get_instance_id()
	if _maps.has(key):
		return _maps[key]
	var sk := get_skeleton()
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
	_maps[key] = out
	return out


## The humanoid bones a clip has no track for (the bakes carry no shoulders, toes or eyes): while the deck plays a clip
## it owns her whole body, so these are held at rest instead of showing whatever plays underneath (2026-10-20: her
## locomotion idle kept moving the shoulders under a held gesture frame, and her hands with them, 2 to 10 cm).
var _fill := {}                           # Animation instance id -> [[bone, rest rotation], ...]


func _fill_of(a: Animation) -> Array:
	var key := a.get_instance_id()
	if _fill.has(key):
		return _fill[key]
	var sk := get_skeleton()
	var have := {}
	for m in _map(a):
		if not m[2]:
			have[int(m[1])] = true
	var out := []
	var prof := SkeletonProfileHumanoid.new()
	for i in prof.bone_size:
		var nm := prof.get_bone_name(i)
		if nm in [&"Root", &"LeftEye", &"RightEye"]:
			continue                      # (the eyes belong to the look at)
		var bi := sk.find_bone(nm)
		if bi >= 0 and not have.has(bi):
			out.append([bi, sk.get_bone_rest(bi).basis.get_rotation_quaternion()])
	_fill[key] = out
	return out


func _sample(p: Dictionary) -> Dictionary:
	var out := {}
	if p.is_empty():
		return out
	if not RenderProfile.options.has("no-deck-fill"):
		for fb in _fill_of(p.anim):
			out[int(fb[0])] = fb[1]
	var a: Animation = p.anim
	var t := clampf(float(p.t), 0.0, a.length)
	var ms := get_skeleton().motion_scale
	for m in _map(a):
		if m[2]:
			var v: Vector3 = a.position_track_interpolate(int(m[0]), t)
			var v0: Vector3 = a.position_track_interpolate(int(m[0]), 0.0)
			out[-1 - int(m[1])] = Vector3(v0.x, v.y, v0.z) * ms + Vector3(0, hips_lift, 0)
		else:
			out[int(m[1])] = a.rotation_track_interpolate(int(m[0]), t)
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
