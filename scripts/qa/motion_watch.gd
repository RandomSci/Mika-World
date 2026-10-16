class_name MotionWatch
extends Node
## Body-movement detector (QA): watches EVERY bone of each mage (body, limbs, face, hair, ribbons, cloth) in the
## world, every frame, and finds trembling - a part that keeps reversing direction at millimetre scale, or jerks.
## A still pose has neither; breathing is a slow smooth drift (few reversals); a tremble or a jittering spring has
## many. Measured separately while she stands idle, walks, and does anything else, so an idle tremble cannot hide
## behind walking motion.
##   * per bone: reversals per second (moved > 0.6 mm one way, then straight back) and jerk (mm per frame^2)
##   * worst bones per mage and state, each tagged with its group (body / arm / hand / head / hair / cloth / ...)
##   * tremor (mm): how far each sample is off the smooth path through its neighbours (timing-aware)
##   * verdict: a bone trembles when its tremor exceeds TREMOR_MM while it keeps reversing
## Use: --motion-watch in any run (a report every --motion-watch-s seconds, default 60) or MotionWatch.attach(main)
## from a test, then report(). Nothing it does is visible.

const STEP_M := 0.0006               # a movement under 0.6 mm between frames is "still"
const TREMBLE_REV := 6.0             # reversals per second
const TREMBLE_JERK := 0.6            # mm per frame^2
const TREMOR_MM := 1.2               # RMS off a smooth path over 5 frames: above this it visibly shakes
const STILL_SPEED := 0.05            # m/s: standing still

var main: Node
var stats := {}                      # who -> state -> bone -> [frames, reversals, jerk_sum]
var _prev := {}                      # who -> bone -> [p_prev, d_prev]
var _period := 60.0
var _acc := 0.0
var enabled := true


static func attach(m: Node) -> MotionWatch:
	var w := MotionWatch.new()
	w.name = "MotionWatch"
	w.main = m
	m.add_child(w)
	return w


func _ready() -> void:
	_period = float(RenderProfile.options.get("motion-watch-s", "60"))
	process_priority = 2000          # after animation, look-ats and springs have all run this frame


static func group_of(bone: String) -> String:
	var b := bone.to_lower()
	for pair in [["hair", "hair"], ["ribbon", "hair"], ["ahoge", "hair"], ["bang", "hair"], ["tail", "hair"], ["skirt", "cloth"], ["sleeve", "cloth"],
			["sash", "cloth"], ["cloth", "cloth"], ["coat", "cloth"], ["cape", "cloth"], ["medallion", "cloth"], ["bell", "cloth"], ["charm", "cloth"],
			["tassel", "cloth"], ["earring", "cloth"], ["pendant", "cloth"], ["ear", "ear"], ["eye", "face"], ["jaw", "face"], ["tongue", "face"],
			["head", "head"], ["neck", "head"], ["hand", "hand"], ["thumb", "hand"], ["index", "hand"], ["middle", "hand"], ["ring", "hand"],
			["little", "hand"], ["arm", "arm"], ["shoulder", "arm"], ["leg", "leg"], ["foot", "leg"], ["toe", "leg"], ["knee", "leg"],
			["hips", "body"], ["spine", "body"], ["chest", "body"]]:
		if b.contains(pair[0]):
			return pair[1]
	return "other"


func _state(c: WorldCharacter) -> String:
	if c.velocity.length() > STILL_SPEED:
		return "moving"
	var br = main.mage_brains.get(c.character_id) if main.get("mage_brains") else null
	var kind := String(br.current.get("kind", "")) if br and not br.current.is_empty() else ""
	if c.current_action == "idle" and (kind == "" or kind in ["rest", "journal", "research", "attune", "meet", "away"]):
		return "idle"
	return "other"


var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if not enabled or main == null or not main.get("characters"):
		return
	# the bones are sampled on each skeleton's FINAL pose (skeleton_updated: after the look-at, posture and spring
	# modifiers) - read here they would be the animation alone, and the hair / dress physics would be invisible
	for who in main.characters:
		var c0: WorldCharacter = main.characters[who]
		if c0 and c0.skeleton and not _hooked.has(who):
			_hooked[who] = c0.skeleton
			var w0 := String(who)
			c0.skeleton.skeleton_updated.connect(func(): _sample(w0))
	_camera(delta)


var _hooked := {}
var _last_t := {}


func _camera(delta: float) -> void:
	# the camera too: a lens that jumps back and forth makes everyone on screen look like they tremble
	var cam := get_viewport().get_camera_3d()
	if cam:
		var per_c: Dictionary = stats.get_or_add("camera", {}).get_or_add(_state(main.characters["mika"]) if main.characters.has("mika") else "any", {})
		var prev_c: Dictionary = _prev.get_or_add("camera", {})
		var aim := cam.global_position - cam.global_transform.basis.z * 3.0
		for pair in [["lens", cam.global_position], ["aim_3m", aim]]:
			var pc: Vector3 = pair[1]
			var prc = prev_c.get(pair[0])
			if prc == null:
				prev_c[pair[0]] = [pc, Vector3.ZERO]
				continue
			var d2: Vector3 = pc - (prc[0] as Vector3)
			var dp2: Vector3 = prc[1]
			if d2.length() > 1.5:
				prev_c[pair[0]] = [pc, Vector3.ZERO]
				continue
			var s2: Array = per_c.get_or_add(pair[0], [0, 0, 0.0])
			s2[0] += 1
			if d2.length() > STEP_M and dp2.length() > STEP_M and d2.dot(dp2) < 0.0:
				s2[1] += 1
			s2[2] += (d2 - dp2).length() * 1000.0
			prev_c[pair[0]] = [pc, d2]



func _sample(who: String) -> void:
	if not enabled:
		return
	var delta := _t - float(_last_t.get(who, _t - 1.0 / 30.0))
	_last_t[who] = _t
	if delta <= 0.0:
		return
	if true:
		var c: WorldCharacter = main.characters.get(who)
		if c == null or not c.visible or c.skeleton == null:
			return
		var sk := c.skeleton
		var st := _state(c)
		var per: Dictionary = stats.get_or_add(who, {}).get_or_add(st, {})
		var prev: Dictionary = _prev.get_or_add(who, {})
		var xf := sk.global_transform
		for bi in range(-2, sk.get_bone_count()):
			# -2: her root (the CharacterBody), -1: the skeleton node (the model under the root)
			var bn := "_ROOT" if bi == -2 else ("_SKELETON" if bi == -1 else sk.get_bone_name(bi))
			var p: Vector3 = c.global_position if bi == -2 else (xf.origin if bi == -1 else xf * sk.get_bone_global_pose(bi).origin)
			var pr = prev.get(bn)
			if pr == null:
				prev[bn] = [p, Vector3.ZERO, []]
				continue
			var d: Vector3 = p - (pr[0] as Vector3)
			var dp: Vector3 = pr[1]
			# a teleport / area change / avatar swap is not motion
			if d.length() > 0.5:
				prev[bn] = [p, Vector3.ZERO, []]
				continue
			var s: Array = per.get_or_add(bn, [0, 0, 0.0, 0.0, 0, 0.0])
			s[0] += 1
			s[5] += d.length() / maxf(delta, 0.001) * 1000.0   # speed, mm/s
			if d.length() > STEP_M and dp.length() > STEP_M and d.dot(dp) < 0.0:
				s[1] += 1
			s[2] += (d - dp).length() * 1000.0
			# tremor: how far the middle of the last 5 samples is off the straight line between their ends (real
			# times, so uneven frames do not count): smooth motion of any speed ~0, shaking is not
			var ring: Array = pr[2] if pr.size() > 2 else []
			ring.append([p, _t])
			if ring.size() > 5:
				ring.pop_front()
			if ring.size() == 5:
				var t0r: float = ring[0][1]
				var t4r: float = ring[4][1]
				var k := (float(ring[2][1]) - t0r) / maxf(t4r - t0r, 0.0001)
				var line_p: Vector3 = (ring[0][0] as Vector3).lerp(ring[4][0], k)
				var off := ((ring[2][0] as Vector3) - line_p).length() * 1000.0
				s[3] += off * off
				s[4] += 1
			prev[bn] = [p, d, ring]
		_clip_check(c, sk, xf, st)
	if RenderProfile.options.has("motion-watch"):
		_acc += delta
		if _acc >= _period:
			_acc = 0.0
			print("[motion] ", JSON.stringify(report(8)))
			print("[clip] ", JSON.stringify(clips))


# ------------------------------------------------------------------ the body inside walls / props
const CLIP_BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "RightUpperArm", "LeftLowerArm",
	"RightLowerArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"]
var clips := {}                      # who -> {total_frames, clip_frames, by_bone: {bone: n}, by_thing: {name: n}, worst_m, events: []}
var _clip_next := {}


## Is a body part INSIDE something solid (a wall, a ruin, a prop, a tree) - not the ground she stands on? A point
## query on the world layer at each body bone, plus the tips of her skirt / sleeves; the terrain does not count.
func _clip_check(c: WorldCharacter, sk: Skeleton3D, xf: Transform3D, st: String) -> void:
	var space := c.get_world_3d().direct_space_state
	var rec: Dictionary = clips.get_or_add(c.character_id, {"total_frames": 0, "clip_frames": 0, "by_bone": {}, "by_thing": {}, "by_state": {}, "events": []})
	rec.total_frames += 1
	var names: Array = CLIP_BONES.duplicate()
	if not _clip_next.has(c.character_id):
		var extra := []
		for bi in sk.get_bone_count():
			var bn := sk.get_bone_name(bi)
			if (bn.contains("Skirt") or bn.contains("Sleeve")) and (bn.ends_with("_end") or bn.ends_with("_4") or bn.ends_with("_7")):
				extra.append(bn)
		_clip_next[c.character_id] = extra
	names.append_array(_clip_next[c.character_id])
	var ex: Array[RID] = []
	for o in main.characters.values():
		if o is CollisionObject3D:
			ex.append((o as CollisionObject3D).get_rid())
	var hit_any := false
	var hips_i := sk.find_bone("Hips")
	var core: Vector3 = xf * sk.get_bone_global_pose(hips_i).origin if hips_i >= 0 else c.global_position + Vector3(0, 0.9, 0)
	for bn in names:
		var bi := sk.find_bone(bn)
		if bi < 0:
			continue
		var p: Vector3 = xf * sk.get_bone_global_pose(bi).origin
		# through a wall: a surface between her own body centre and this part (works for mesh walls too)
		if bn != "Hips" and core.distance_to(p) > 0.05:
			var rq := PhysicsRayQueryParameters3D.create(core, p, 1 | 4)
			rq.exclude = ex
			rq.hit_back_faces = true
			var rh := space.intersect_ray(rq)
			if not rh.is_empty() and rh.collider is Node:
				var rn := String((rh.collider as Node).name)
				if not ((rh.collider as Node).is_in_group("cat_terrain") or rn.to_lower().contains("terrain") or rn.to_lower().contains("ground")):
					hit_any = true
					rec.by_bone[bn] = int(rec.by_bone.get(bn, 0)) + 1
					var th := "through " + rn + " (" + String((rh.collider as Node).get_parent().name if (rh.collider as Node).get_parent() else "") + ")"
					rec.by_thing[th] = int(rec.by_thing.get(th, 0)) + 1
					if rec.events.size() < 200 and (rec.events.is_empty() or _t - float(rec.events[-1].t) > 1.0):
						rec.events.append({"t": snappedf(_t, 0.1), "bone": bn, "thing": th, "state": st, "action": c.current_action,
							"depth_m": snappedf(((rh.position as Vector3) - p).length(), 0.01), "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]})
					continue
		var q := PhysicsPointQueryParameters3D.new()
		q.position = p
		q.collision_mask = 1 | 4
		q.exclude = ex
		for h in space.intersect_point(q, 4):
			var col = h.get("collider")
			if col == null or not (col is Node):
				continue
			var nm := String((col as Node).name)
			if (col as Node).is_in_group("cat_terrain") or nm.to_lower().contains("terrain") or nm.to_lower().contains("ground"):
				continue
			hit_any = true
			rec.by_bone[bn] = int(rec.by_bone.get(bn, 0)) + 1
			var thing := nm + " (" + String((col as Node).get_parent().name if (col as Node).get_parent() else "") + ")"
			rec.by_thing[thing] = int(rec.by_thing.get(thing, 0)) + 1
			if rec.events.size() < 200 and (rec.events.is_empty() or _t - float(rec.events[-1].t) > 1.0):
				rec.events.append({"t": snappedf(_t, 0.1), "bone": bn, "thing": thing, "state": st, "action": c.current_action,
					"pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]})
			break
	if hit_any:
		rec.clip_frames += 1
		rec.by_state[st] = int(rec.by_state.get(st, 0)) + 1


## {who: {state: {seconds, trembling: [...], worst: [{bone, group, rev_per_s, jerk}]}}}; fps is the sampling rate.
func report(top := 10, fps := 30.0) -> Dictionary:
	var out := {}
	for who in stats:
		out[who] = {}
		for st in stats[who]:
			var per: Dictionary = stats[who][st]
			var rows := []
			var frames := 0
			for bn in per:
				var s: Array = per[bn]
				if int(s[0]) < 30:
					continue
				frames = maxi(frames, int(s[0]))
				var secs := float(s[0]) / fps
				var tremor := sqrt(float(s[3]) / maxf(float(s[4]), 1.0)) if s.size() > 4 else 0.0
				rows.append({"bone": bn, "group": group_of(bn), "rev_per_s": snappedf(float(s[1]) / secs, 0.1), "jerk": snappedf(float(s[2]) / float(s[0]), 0.01), "tremor_mm": snappedf(tremor, 0.01),
					"speed_mm_s": snappedf(float(s[5]) / float(s[0]), 0.1) if s.size() > 5 else 0.0})
			rows.sort_custom(func(a, b): return a.tremor_mm > b.tremor_mm)
			var trem := rows.filter(func(r): return r.tremor_mm > TREMOR_MM and r.rev_per_s > 2.0)
			var by_group := {}
			for r in trem:
				by_group[r.group] = int(by_group.get(r.group, 0)) + 1
			out[who][st] = {"seconds": snappedf(frames / fps, 0.1), "trembling_bones": trem.size(), "trembling_by_group": by_group, "worst": rows.slice(0, top)}
	return out


func reset() -> void:
	stats = {}
	_prev = {}
