class_name DressSim
extends Node
## The skirt on Godot's own SpringBoneSimulator3D (2026-10-18, the dress fix): the VRM skirt chains (J_Sec_Skirt*)
## leave the VRM secondary and are simulated here instead, with
##  * leg colliders: a tapered capsule pair per leg (thigh, shin) that starts below the hip joint, so the skirt's
##    roots never begin inside a collider (the old thigh capsule held the roots inside it when she sat: every frame
##    they were shoved out to the far side - the "exploding" panel under the bench);
##  * a floor plane under her feet and, while she sits, the bench seat (a capsule along the seat) so the hem drapes
##    over the seat edge instead of through the stone;
##  * a speed limit on every skirt joint (LimitAngularVelocityModifier3D): no joint ever snaps;
##  * a warm-up: a new avatar starts from its rest pose (reset) and blends the simulation in over 0.4 s.
## Two modes:
##  * "guard" (profile.dress.sim = "guard", or --dress-guard): the VRM springs keep the skirt (their leg colliders work
##    and hold the A-line), and a LimitAngularVelocityModifier3D runs right after them (an internal modifier behind
##    the VRM's own) so no skirt joint can turn faster than max_deg_s - the jumps when she sits are capped.
##  * "sbs" (profile.dress.sim = "godot", or --dress-sim): the chains move to SpringBoneSimulator3D as described above.
##    (2026-10-18: in Godot 4.7.2 its colliders did not act on the skirt in our tests - kept for later, off by default.)
## --no-dress-sim turns both off.

const CHAIN_PREFIX := "Skirt"
var c: WorldCharacter
var sim: SpringBoneSimulator3D
var limit: LimitAngularVelocityModifier3D
var drape: SkirtDrape
var cfg: Dictionary = {}
var floor_plane: SpringBoneCollisionPlane3D
var _chains: Array = []                 # [root bone, end bone, joint count]
var _warm := 0.0
var _was_seated := false
var _seat: Array = []                 # [sphere, its world transform] while she sits


static func mode_for(ch: WorldCharacter) -> String:
	if RenderProfile.options.has("no-dress-sim"):
		return ""
	if RenderProfile.options.has("dress-sim"):
		return "sbs"
	if RenderProfile.options.has("dress-guard"):
		return "guard"
	var d: Dictionary = AppearanceRegistry.stage_for_avatar(ch.character_id, ch.avatar_path).get("profile", {}).get("dress", {})
	return {"godot": "sbs", "guard": "guard"}.get(String(d.get("sim", "")), "")


## Before the avatar enters the tree: take the skirt chains out of the VRM secondary (it builds its runtime from
## spring_bones in _ready). Returns how many chains were taken.
static func take_chains(avatar: Node) -> int:
	var sec = avatar.find_child("secondary", true, false)
	if sec == null or sec.get("spring_bones") == null:
		return 0
	var keep = sec.spring_bones.duplicate()
	keep.clear()
	var n := 0
	for sb in sec.spring_bones:
		if String(sb.comment).begins_with(CHAIN_PREFIX):
			n += 1
		else:
			keep.append(sb)
	sec.spring_bones = keep
	return n


static func attach(ch: WorldCharacter, mode := "sbs") -> DressSim:
	for n in ch.skeleton.get_children():
		if n is DressSim:
			n.queue_free()
	var d := DressSim.new()
	d.name = "DressSim"
	d.c = ch
	d.cfg = AppearanceRegistry.stage_for_avatar(ch.character_id, ch.avatar_path).get("profile", {}).get("dress", {})
	ch.skeleton.add_child(d)
	if mode == "guard":
		d._build_guard()
	else:
		d._build()
	return d


## Per-chain multiplier (profile.dress.chains {"Skirt00": {"stiffness": 2.5, ...}}), matched on the chain root's name.
func _ck(i: int, key: String) -> float:
	var ch: Dictionary = cfg.get("chains", {})
	for pre in ch:
		if String(_chains[i][0]).contains(String(pre)):
			return float((ch[pre] as Dictionary).get(key, 1.0))
	return 1.0


func _f(key: String, def: float) -> float:
	return float(RenderProfile.options.get("dress-" + key.replace("_", "-"), cfg.get(key, def)))


func _find_chains() -> void:
	var sk := c.skeleton
	for bi in sk.get_bone_count():
		var bn := sk.get_bone_name(bi)
		if not (bn.contains(CHAIN_PREFIX) and bn.ends_with("_0")):
			continue
		var end := bi
		var count := 1
		while true:
			var kids := sk.get_bone_children(end)
			if kids.is_empty():
				break
			end = kids[0]
			count += 1
		if count >= 2:
			_chains.append([bn, sk.get_bone_name(end), count])


## Guard mode: only the speed limit, after the VRM springs (they are an internal modifier at the back of the skeleton).
func _build_guard() -> void:
	_find_chains()
	limit = LimitAngularVelocityModifier3D.new()
	limit.name = "DressSpeedLimit"
	c.skeleton.add_child(limit, false, Node.INTERNAL_MODE_BACK)
	limit.chain_count = _chains.size()
	for i in _chains.size():
		limit.set_root_bone_name(i, _chains[i][0])
		limit.set_end_bone_name(i, _chains[i][1])
	limit.max_angular_velocity = deg_to_rad(_f("max_deg_s", 240.0))
	limit.reset.call_deferred()
	print("[dress] %s: %d skirt chains on the VRM springs, speed limit %.0f deg/s" % [c.character_id, _chains.size(), _f("max_deg_s", 240.0)])


func _build() -> void:
	var sk := c.skeleton
	# the chains: every J_Sec_SkirtNN_0 root and its deepest descendant
	for bi in sk.get_bone_count():
		var bn := sk.get_bone_name(bi)
		if not (bn.contains(CHAIN_PREFIX) and bn.ends_with("_0")):
			continue
		var end := bi
		var count := 1
		while true:
			var kids := sk.get_bone_children(end)
			if kids.is_empty():
				break
			end = kids[0]
			count += 1
		if count >= 2:
			_chains.append([bn, sk.get_bone_name(end), count])
	sim = SpringBoneSimulator3D.new()
	sim.name = "DressSprings"
	sk.add_child(sim)
	sim.setting_count = _chains.size()
	for i in _chains.size():
		var ch: Array = _chains[i]
		sim.set_root_bone_name(i, ch[0])
		sim.set_end_bone_name(i, ch[1])
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_direction(i, SkeletonModifier3D.BONE_DIRECTION_FROM_PARENT)
		sim.set_end_bone_length(i, _f("tip_length", 0.06))
		match String(RenderProfile.options.get("dress-center", cfg.get("center", "world"))):
			"body":
				sim.set_center_from(i, SpringBoneSimulator3D.CENTER_FROM_NODE)
				sim.set_center_node(i, sim.get_path_to(c))
			"hips":
				sim.set_center_from(i, SpringBoneSimulator3D.CENTER_FROM_BONE)
				sim.set_center_bone_name(i, "Hips")
			_:
				sim.set_center_from(i, SpringBoneSimulator3D.CENTER_FROM_WORLD_ORIGIN)
		sim.set_radius(i, _f("joint_radius", 0.015))
		sim.set_stiffness(i, _f("stiffness", 16.0) * _ck(i, "stiffness"))
		sim.set_drag(i, clampf(_f("drag", 0.7) * _ck(i, "drag"), 0.0, 1.0))
		sim.set_gravity(i, _f("gravity", 0.5) * _ck(i, "gravity"))
		sim.set_gravity_direction(i, Vector3.DOWN)
		sim.set_enable_all_child_collisions(i, true)
	# leg colliders: thigh and shin capsules along the bones, starting below the hip joint
	for side in ["Left", "Right"]:
		# (+ leg_margin: the panels slide over the legs instead of into them - Selwyn 2026-10-19)
		_leg_capsule(side + "UpperLeg", _f("thigh_radius", 0.065) + _f("leg_margin", 0.018), _f("thigh_start", 0.12))
		_leg_capsule(side + "LowerLeg", _f("shin_radius", 0.05) + _f("leg_margin", 0.018), 0.0)
	if RenderProfile.options.has("dress-debug-ball"):        # diagnostics: one big sphere on the hips
		var ball := SpringBoneCollisionSphere3D.new()
		ball.name = "DebugBall"
		ball.bone_name = "Hips"
		ball.radius = float(RenderProfile.options["dress-debug-ball"])
		sim.add_child(ball)
	floor_plane = SpringBoneCollisionPlane3D.new()
	floor_plane.name = "Floor"
	sim.add_child(floor_plane)
	# (the seat collider is created when she sits: the simulator reads a collider's size when it collects it)
	# the colliders are children now: (re)enable them per chain so the simulator collects them
	for i in _chains.size():
		sim.set_enable_all_child_collisions(i, false)
		sim.set_enable_all_child_collisions(i, true)
	# no joint ever snaps: a speed limit on every skirt chain (after the simulation in the modifier order)
	limit = LimitAngularVelocityModifier3D.new()
	limit.name = "DressSpeedLimit"
	sk.add_child(limit)
	limit.chain_count = _chains.size()
	for i in _chains.size():
		limit.set_root_bone_name(i, _chains[i][0])
		limit.set_end_bone_name(i, _chains[i][1])
	limit.max_angular_velocity = deg_to_rad(_f("max_deg_s", 240.0))
	# the seated drape: last, over the simulation and the speed limit (every seat, rock, step, log and the grass)
	if not RenderProfile.options.has("no-drape"):
		var roots := []
		for ch in _chains:
			roots.append(ch[0])
		drape = SkirtDrape.attach(c, roots)
	if RenderProfile.options.has("dress-debug"):
		sim.modification_processed.connect(_debug_print)
	# warm-up: from the rest pose, blended in
	sim.influence = 0.0
	_warm = 0.0
	sim.reset.call_deferred()
	print("[dress] %s: %d skirt chains on SpringBoneSimulator3D (stiffness %.2f drag %.2f gravity %.2f, limit %.0f deg/s)" % [c.character_id,
		_chains.size(), _f("stiffness", 16.0), _f("drag", 0.7), _f("gravity", 0.5), _f("max_deg_s", 240.0)])


func _leg_capsule(bone: String, r: float, start: float) -> void:
	var sk := c.skeleton
	var bi := sk.find_bone(bone)
	if bi < 0:
		return
	# the next joint of the leg by name (a VRM thigh's first child bone can be a cloth or twist bone, not the knee)
	var ci := sk.find_bone(bone.replace("UpperLeg", "LowerLeg") if bone.ends_with("UpperLeg") else bone.replace("LowerLeg", "Foot"))
	if ci < 0:
		return
	# measured on the skeleton itself (rest pose, skeleton space): the segment from the joint (plus `start`) to the
	# next joint, expressed in the bone's own frame - the bone axes of a VRM skeleton do not point at the child
	var bp: Transform3D = sk.get_bone_global_rest(bi)
	var a: Vector3 = bp.origin
	var e: Vector3 = sk.get_bone_global_rest(ci).origin
	var dir := (e - a).normalized()
	var length := a.distance_to(e)
	var mid := a + dir * (start + (length - start) * 0.5)
	var inv := bp.affine_inverse()
	var cap := SpringBoneCollisionCapsule3D.new()
	cap.name = "Leg_" + bone
	cap.bone_name = bone
	cap.radius = r
	cap.height = maxf(2.0 * r + 0.01, length - start + r)
	cap.position_offset = inv * mid
	var ldir: Vector3 = (inv.basis * dir).normalized()
	cap.rotation_offset = Quaternion(Vector3.UP, ldir)            # the capsule's height axis (local Y) along the leg
	sim.add_child(cap)


func _process(delta: float) -> void:
	if sim == null:
		return
	if _warm < 1.0:
		_warm = minf(1.0, _warm + delta / 0.4)
		sim.influence = _warm
	# the hem follows her: a world-space simulation (its colliders only work in world space in Godot 4.7.2) would
	# leave a run's whole skirt streaming behind like a flag - push it along with her own velocity instead
	var v := c.velocity
	v.y = 0.0
	sim.external_force = v * _f("follow", 0.6)
	# the floor under her feet
	var feet := c.global_position
	# (a collider without a bone is ignored by the simulator: floor and seat hang on the hips bone, their offset
	# recomputed every frame so they stay put in the world)
	_pin_to_hips(floor_plane, Transform3D(Basis.IDENTITY, feet + Vector3(0, _f("floor_lift", 0.015), 0)))
	for e in _seat:
		_pin_to_hips(e[0], e[1])
	if _was_seated and not c.seated:
		_clear_seat()
	if c.seated != _was_seated:
		# seated: the skirt holds its shape on the seat (stiffer, lighter) instead of sliding off it as a flat sheet
		var k := _f("seated_stiffness", 0.5) if c.seated else 1.0
		var g := _f("seated_gravity", 2.0) if c.seated else 1.0
		for i in _chains.size():
			sim.set_stiffness(i, _f("stiffness", 16.0) * _ck(i, "stiffness") * k)
			sim.set_gravity(i, _f("gravity", 0.5) * _ck(i, "gravity") * g)
	_was_seated = c.seated


## The seat she sits on (called by Interactable when she settles): a capsule along the seat, its top on the seat top.
func set_seat(seat: CollisionShape3D) -> void:
	if sim == null:
		return
	if seat == null or not (seat.shape is BoxShape3D):
		return
	_clear_seat()
	var box := seat.shape as BoxShape3D
	var t := seat.global_transform
	var sx := t.basis.x.length() * box.size.x
	var sz := t.basis.z.length() * box.size.z
	var top := t.origin.y + t.basis.y.length() * box.size.y * 0.5
	var along := t.basis.x.normalized() if sx >= sz else t.basis.z.normalized()
	var length := maxf(sx, sz)
	var r := clampf(minf(sx, sz) * 0.5, 0.08, 0.3)
	# a row of spheres along the seat, their tops on the seat's top (a capsule's rotation offset is not honoured)
	var n := maxi(2, ceili(length / (r * 0.8)) + 1)
	for i in n:
		var p: Vector3 = Vector3(t.origin.x, top - r, t.origin.z) + along * lerpf(-length * 0.5 + r * 0.5, length * 0.5 - r * 0.5, float(i) / float(n - 1))
		var ball := SpringBoneCollisionSphere3D.new()
		ball.name = "Seat_%d" % i
		ball.radius = r
		_pin_to_hips(ball, Transform3D(Basis.IDENTITY, p))
		sim.add_child(ball)
		_seat.append([ball, Transform3D(Basis.IDENTITY, p)])
	_recollect()
	print("[dress] %s sits: %d seat spheres r %.2f m, top %.2f m" % [c.character_id, n, r, top])


func _clear_seat() -> void:
	if _seat.is_empty():
		return
	for e in _seat:
		if is_instance_valid(e[0]):
			sim.remove_child(e[0])
			(e[0] as Node).queue_free()
	_seat.clear()
	_recollect()


func _recollect() -> void:
	for i in _chains.size():
		sim.set_enable_all_child_collisions(i, false)
		sim.set_enable_all_child_collisions(i, true)


func _pin_to_hips(col: SpringBoneCollision3D, world: Transform3D) -> void:
	var sk := c.skeleton
	var hi := sk.find_bone("Hips")
	if col.bone_name != "Hips":
		col.bone_name = "Hips"
	var hips_world: Transform3D = sk.global_transform * sk.get_bone_global_pose(hi)
	var rel := hips_world.affine_inverse() * world
	col.position_offset = rel.origin
	col.rotation_offset = rel.basis.get_rotation_quaternion()


var _dbg_n := 0
func _debug_print() -> void:
	_dbg_n += 1
	if _dbg_n % 60 != 0 or _dbg_n > 360:
		return
	var sk := c.skeleton
	var hp: Vector3 = sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	var ds := []
	for jn in ["J_Sec_Skirt00_3", "J_Sec_Skirt04_3", "J_Sec_Skirt08_3", "J_Sec_Skirt00_6"]:
		var ji := sk.find_bone(jn)
		if ji >= 0:
			var jp: Vector3 = sk.get_bone_global_pose(ji).origin
			ds.append("%s r=%.3f dy=%.3f" % [jn, Vector2(jp.x - hp.x, jp.z - hp.z).length(), jp.y - hp.y])
	print("[dress] frame %d influence %.2f joints vs hips: %s" % [_dbg_n, sim.influence, str(ds)])
