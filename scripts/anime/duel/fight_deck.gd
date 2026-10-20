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
	"ual_react": "res://assets/animations/ual/ual_react.glb", "ualf": "res://assets/animations/ual/ual_fight.glb"}
const MIXAMO_DIR := "res://assets/animations/mixamo/"
## (2026-10-20, Selwyn: suit mocap is the fight's body) UAL's root motion, read from its _RM export (the clips in
## ual_fight.glb are the in-place ones): clip -> {fps, len, fwd [m per frame], left [m per frame]}
const UAL_ROOT := "res://assets/animations/ual/ual_fight_root.json"
static var _root := {}

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
## Suit mocap ("sword:", "mixamo:", "ualf:") comes conditioned for HER body (SuitFix, 2026-10-20: limbs, twists, ankles,
## arms out of her dress), prebaked per skeleton like the Move Library bakes; "<clip>@mirror" is it with left and
## right swapped, "<clip>@rev" run backward (a side dodge the other way, a step back from a step in).
static func anim_for(ch: WorldCharacter, clip: String) -> Animation:
	if ch and ch.has_clip(clip):
		return ch.body_player.get_animation("mx/" + clip)
	if clip.contains("|"):
		# "<upper>|<lower>": her upper body from one clip over the legs and travel of another (2026-10-20: Mika's
		# one-handed sword guard over the only side steps there are, the great sword set's)
		var ck := clip + "|" + (_rest_key(ch) if ch else "")
		if not _ext.has(ck):
			var up := anim_for(ch, clip.get_slice("|", 0))
			var lo := anim_for(ch, clip.get_slice("|", 1))
			_ext[ck] = _compose(up, lo) if up and lo else null
		return _ext[ck]
	var suit := ch != null and (clip.begins_with("sword:") or clip.begins_with("mixamo:") or clip.begins_with("ualf:"))
	var key := clip + ("|" + _rest_key(ch) if suit else "")
	if _ext.has(key):
		return _ext[key]
	var base := clip.get_slice("@", 0)
	var variant := clip.get_slice("@", 1) if clip.contains("@") else ""
	var a := _raw(base)
	if a != null and suit:
		var sig := ("%d|%s|%s" % [SuitFix.VERSION, variant, FileAccess.get_md5(_source(base) + ".import")]).md5_text()
		var cp := MocapBake.BAKED_DIR + _rest_key(ch) + "/deck__" + clip.replace(":", "__").replace("@", "__") + ".res"
		var hit: Animation = load(cp) as Animation if ResourceLoader.exists(cp) and not RenderProfile.options.has("no-prebake") else null
		if hit != null and String(hit.get_meta("src", "")) == sig:
			a = hit
		else:
			a = a.duplicate(true) as Animation
			if variant == "mirror":
				a = SuitFix.mirror(ch.skeleton, a)
			elif variant == "rev":
				a = SuitFix.reverse(a)
			var st := SuitFix.condition(ch, ch.skeleton, a)
			print("[deck] %s conditioned for %s %s" % [clip, String(ch.character_id), str(st)])
			a.set_meta("src", sig)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cp.get_base_dir()))
			ResourceSaver.save(a, cp, ResourceSaver.FLAG_COMPRESS)
	if a == null:
		push_warning("[fight] no clip " + clip)
	_ext[key] = a
	return a


const LOWER := ["Root", "Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]


## The legs, hips and travel of `lo` (its length) under the upper body of `up` (looped through it).
static func _compose(up: Animation, lo: Animation) -> Animation:
	var out := Animation.new()
	out.length = lo.length
	out.loop_mode = lo.loop_mode
	for ti in lo.get_track_count():
		if String(lo.track_get_path(ti)).get_slice(":", 1) in LOWER:
			var nt := out.add_track(lo.track_get_type(ti))
			out.track_set_path(nt, lo.track_get_path(ti))
			for kk in lo.track_get_key_count(ti):
				out.track_insert_key(nt, lo.track_get_key_time(ti, kk), lo.track_get_key_value(ti, kk))
	for ti in up.get_track_count():
		if up.track_get_type(ti) != Animation.TYPE_ROTATION_3D or String(up.track_get_path(ti)).get_slice(":", 1) in LOWER:
			continue
		var nt2 := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(nt2, up.track_get_path(ti))
		var t := 0.0
		while t <= lo.length + 0.0001:
			out.rotation_track_insert_key(nt2, t, up.rotation_track_interpolate(ti, fposmod(t, maxf(up.length, 0.01))))
			t += 1.0 / 30.0
	return out


static var _rk := {}


static func _rest_key(ch: WorldCharacter) -> String:
	var id := ch.skeleton.get_instance_id()
	if not _rk.has(id):
		_rk[id] = MocapBake.rest_key(ch.skeleton)
	return _rk[id]


static func _source(clip: String) -> String:
	if clip.begins_with("sword:"):
		return SWORD_DIR + clip.get_slice(":", 1) + ".fbx"
	if clip.begins_with("mixamo:"):
		return MIXAMO_DIR + clip.get_slice(":", 1) + ".fbx"
	return String(UAL.get(clip.get_slice(":", 0), ""))


static var _raws := {}


## The clip as imported (shared by both girls).
static func _raw(clip: String) -> Animation:
	if _raws.has(clip):
		return _raws[clip]
	var a: Animation = null
	if clip.begins_with("sword:") or clip.begins_with("mixamo:"):
		var path := _source(clip)
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
	_raws[clip] = a
	return a


## The clip's own travel over the ground (root motion) at clip time t, in her frame: x = metres to her left, y = metres
## forward. UAL clips: their _RM export's root bone; Mixamo clips: the hips' horizontal track (the deck itself keeps
## the hips on her mark, so this is the travel the fight gives her mark instead).
static func root_at(ch: WorldCharacter, clip: String, t: float) -> Vector2:
	if clip.contains("|"):
		return root_at(ch, clip.get_slice("|", 1), t)
	if clip.ends_with("@mirror"):
		var m := root_at(ch, clip.get_slice("@", 0), t)
		return Vector2(-m.x, m.y)
	if clip.ends_with("@rev"):
		var b := clip.get_slice("@", 0)
		var L := clip_length(ch, b)
		return root_at(ch, b, L - t) - root_at(ch, b, L)
	if clip.begins_with("ml_"):
		# (the Move Library's mocap is hip-centred: its catalogued travel, eased in over the windup to the contact)
		var e: Dictionary = BodyMoves.entry(clip)
		var c_t := float((e.get("hits", [1.0]) as Array)[0]) if not (e.get("hits", []) as Array).is_empty() else 1.0
		var u := clampf((t - (c_t - 0.95)) / 0.95, 0.0, 1.0)
		return Vector2(0.0, float(e.get("travel", 0.0)) * u * u * (3.0 - 2.0 * u))
	if clip.begins_with("ualf:"):
		if _root.is_empty():
			var j = JSON.parse_string(FileAccess.get_file_as_string(UAL_ROOT))
			_root = j if typeof(j) == TYPE_DICTIONARY else {"_none": true}
		var r: Dictionary = _root.get(clip.get_slice(":", 1), _root.get(clip.get_slice(":", 1) + "_Loop", {}))   # (the import drops "_Loop")
		if r.is_empty():
			return Vector2.ZERO
		var fw: Array = r.fwd
		var lf: Array = r.left
		var x := clampf(t * float(r.fps), 0.0, float(fw.size() - 1))
		var i := int(floor(x))
		var j2 := mini(i + 1, fw.size() - 1)
		var u := x - float(i)
		return Vector2(lerpf(float(lf[i]), float(lf[j2]), u), lerpf(float(fw[i]), float(fw[j2]), u))
	if clip.begins_with("sword:") or clip.begins_with("mixamo:"):
		var a := anim_for(ch, clip)
		if a == null or ch == null:
			return Vector2.ZERO
		var sk := ch.skeleton
		var ti := -1
		for k in a.get_track_count():
			if a.track_get_type(k) == Animation.TYPE_POSITION_3D and String(a.track_get_path(k)).get_slice(":", 1) == "Hips":
				ti = k
		if ti < 0:
			return Vector2.ZERO
		var left := (sk.get_bone_global_rest(sk.find_bone("LeftUpperArm")).origin - sk.get_bone_global_rest(sk.find_bone("RightUpperArm")).origin).normalized()
		var fwd := left.cross(Vector3.UP).normalized()
		var dv := (a.position_track_interpolate(ti, clampf(t, 0.0, a.length)) - a.position_track_interpolate(ti, 0.0)) * sk.motion_scale
		return Vector2(dv.dot(left), dv.dot(fwd))
	return Vector2.ZERO


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
	if c and c.cloth_clearance:
		c.cloth_clearance.allow = false            # (the fight owns her arms: no folded hands, 2026-10-20)
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
