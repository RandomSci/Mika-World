class_name MoonBoat
extends Node3D
## The Moon Lantern Boat (2026-10-19, Selwyn's asset ~/Downloads/boat/BOAT_meshy.glb, split into hull / two oars / two
## lanterns at their pivots and scaled to 3.2 m by tools in ~/.cache/mika_qa/boat_work/split.py): a reusable activity
## on any water - it floats (a gentle bob, roll and pitch, ripples at the hull and a wake when it moves) and offers
## actions for whoever is aboard: board, sit, row, trail a hand, light a lantern, set floating lanterns on the water,
## stargaze, point, rest a chin on a hand, look at the water. Stargazing, fishing, chatting and the song scene build
## on these.
##
## Boat space: bow toward -X, up +Y, the origin at the waterline. Seats: "bow" (the long cushioned bench, its aft end,
## facing the stern - the rower's seat) and "stern" (the cushioned stern seat, facing the bow).

const SCENE := "res://assets/props/boat/moon_boat.glb"
const SEATS := {
	"bow": {"pos": Vector3(-0.3, 0.22, 0.0), "yaw": PI * 0.5, "feet": Vector3(0.12, -0.02, 0.0)},     # faces +X
	"stern": {"pos": Vector3(0.86, 0.21, 0.0), "yaw": -PI * 0.5, "feet": Vector3(0.42, -0.02, 0.0)},  # faces -X
}
const OAR_GRIP := 0.24                   # m from the oarlock pivot in to the grip
const HIPS_ABOVE_SEAT := 0.09
const SCALE := 1.3                       # (Selwyn: "about 1.3x so both girls fit naturally" - 4.2 m long)
## The hull's inside (boat space, before SCALE): along X from the bow seat's front to the stern seat's back, and the
## half width there - a draped skirt is kept within it (never out through the hull).
const INSIDE_X := Vector2(-0.95, 1.22)
const INSIDE_HALF_W := 0.38

var water_y := 0.0
var hull: MeshInstance3D
var oars := {}                           # "L"/"R" -> {node, rest: Basis, axis_in: Vector3 (oar space, toward the grip)}
var lanterns := {}                       # "bow"/"stern" -> {node, mats: [], light: OmniLight3D, lit: float}
var riders := {}                         # seat -> {c, pose: SeatPose, life: BodyLife, root_y, mode}
var speed := 0.0                         # m/s along the bow (-X)
var turn := 0.0                          # rad/s
var rowing := false
var _row_phase := 0.0
var _caught := false                     # this stroke's catch ripple made
var _t := 0.0
var _since_ripple := 0.0
var _yaw := 0.0
var _base := Vector3.ZERO                # the boat's waterline position (before bob)
var _ring_shader: Shader
var _floaters: Array = []                # floating lanterns set on the water: {node, vel}
var lake: Node3D                         # (for its lantern mesh and material)
var day_night: Node                      # lanterns and stargazing are for the night only (Selwyn, 2026-10-19)


static func spawn(parent: Node, at: Vector3, yaw: float, water: float) -> MoonBoat:
	var b := MoonBoat.new()
	b.name = "MoonBoat"
	parent.add_child(b)
	b.water_y = water
	b._base = Vector3(at.x, water, at.z)
	b._yaw = yaw
	b.scale = Vector3.ONE * SCALE
	b._build()
	b._place()
	return b


func _build() -> void:
	var sc: Node3D = (load(SCENE) as PackedScene).instantiate()
	add_child(sc)
	_ring_shader = load("res://shaders/anime/boat/water_ripple.gdshader")
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(m.name)
		if nm.begins_with("Hull"):
			hull = m
		elif nm.begins_with("Oar_"):
			var side := "L" if nm.contains("L") else "R"
			# the grip direction: from the pivot toward the mesh's inboard end (the vertex nearest the boat's centreline)
			var aabb := m.get_aabb()
			var inboard := Vector3(aabb.position.x, aabb.end.y, 0.0)
			var best := Vector3.ZERO
			var bd := INF
			var arrays := m.mesh.surface_get_arrays(0)
			for v in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var wz := absf(m.position.z + v.z)
				if wz < bd:
					bd = wz
					best = v
			oars[side] = {"node": m, "rest": m.basis, "axis_in": best.normalized()}
			m.set_meta("no_drape", true)                 # (they move: a skirt never drapes on an oar)
		elif nm.begins_with("Lantern_"):
			var which := "bow" if nm.contains("Bow") else "stern"
			var mats := []
			for si in m.mesh.get_surface_count():
				var src := m.get_active_material(si)
				if src is StandardMaterial3D:
					var mm := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					mm.emission_enabled = true
					mm.emission_texture = mm.albedo_texture
					mm.emission = Color(1.0, 0.72, 0.4)
					mm.emission_energy_multiplier = 0.0
					m.set_surface_override_material(si, mm)
					mats.append(mm)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.7, 0.4)
			l.light_energy = 0.0
			l.omni_range = 4.0
			l.omni_attenuation = 1.4
			l.shadow_enabled = false
			m.add_child(l)
			l.position = Vector3(0, -0.12 if which == "bow" else -0.1, 0)
			lanterns[which] = {"node": m, "mats": mats, "light": l, "lit": 0.0}
			m.set_meta("no_drape", true)
	if hull:
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Where a seat is in the world now: {origin, basis (facing), feet}
func seat_xform(seat: String) -> Transform3D:
	var s: Dictionary = SEATS[seat]
	var t := global_transform * Transform3D(Basis(Vector3.UP, float(s.yaw)), s.pos)
	return Transform3D(t.basis.orthonormalized(), t.origin)


## The seat for a posed drape: her seat (origin on the cushion, z her forward, x her left), the cushion's edges, the
## floor and her feet.
func seat_drape(seat_name: String) -> Dictionary:
	var st := seat_xform(seat_name)
	var e: Dictionary = {"bow": {"front": 0.13, "back": 0.4, "side": 0.4}, "stern": {"front": 0.2, "back": 0.17, "side": 0.34}}[seat_name]
	var floor_w := (global_transform * Vector3(0, -0.03, 0)).y
	var ft := _feet_targets(seat_name)
	return {"xf": st, "front": e.front, "back": e.back, "side": e.side, "floor": floor_w, "feet": ft}


## A world point kept inside the hull (for the seated drape).
func contain_point(p: Vector3) -> Vector3:
	var lp := global_transform.affine_inverse() * p
	var taper := clampf(1.0 - absf(lp.x - 0.1) / 1.25, 0.55, 1.0)       # (narrower toward bow and stern)
	var w := INSIDE_HALF_W * taper
	lp.x = clampf(lp.x, INSIDE_X.x, INSIDE_X.y)
	lp.z = clampf(lp.z, -w, w)
	lp.y = maxf(lp.y, -0.01)
	return global_transform * lp


func grip(side: String) -> Vector3:
	var o: Dictionary = oars[side]
	var n: Node3D = o.node
	return n.global_transform * ((o.axis_in as Vector3) * OAR_GRIP)


## Night? (the day/night cycle's applied night amount, or its override); without a cycle: yes.
func night() -> bool:
	if day_night == null or not is_instance_valid(day_night):
		return true
	if int(day_night.get("override")) == 1:
		return true
	if int(day_night.get("override")) == 0:
		return false
	return float(day_night.get("k")) >= 0.5


## Her left (+1) or right (-1) side in the world, from a seat transform (the seat's z is her forward, x her left).
static func side_vec(st: Transform3D, side: String) -> Vector3:
	return st.basis.x * (1.0 if side == "Left" else -1.0)


func lantern_pos(which: String) -> Vector3:
	return (lanterns[which].node as Node3D).global_position + Vector3(0, -0.12, 0)


# ------------------------------------------------------------------------------------------------ riders and actions
## Seat her (she is already standing in the boat beside the seat, or anywhere: she is placed). Her stack: SeatPose,
## BodyLife, SoftArms (made here once).
func seat(c: WorldCharacter, seat_name: String) -> void:
	var sk := c.skeleton
	var pose: SeatPose = null
	var life: BodyLife = null
	for n in sk.get_children():
		if n is SeatPose:
			pose = n
		elif n is BodyLife:
			life = n
	if pose == null:
		pose = SeatPose.make(sk, 0)
	if life == null:
		life = BodyLife.make(sk, 1)
		life.look_weight = 0.45
	var soft: SoftArms = null
	for n in sk.get_children():
		if n is SoftArms:
			soft = n
	if soft == null:
		soft = SoftArms.make(sk, 2)
	soft.elbow_min = deg_to_rad(8.0)
	PosePipeline.arrange_for(sk)                   # (the one owner of the order: activity, IK, collision, cloth)
	var order := []
	for n in sk.get_children():
		order.append(String(n.name))
	print("[boat] %s's modifiers: %s" % [c.character_id, ", ".join(order)])
	var toe := sk.global_basis * (sk.get_bone_global_rest(sk.find_bone("LeftToes")).origin - sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin)
	var tl := c.global_basis.inverse() * toe
	var face_fix := Basis(Vector3.UP, -atan2(tl.x, tl.z))       # turns her toes onto the seat's forward (+z)
	riders[seat_name] = {"c": c, "pose": pose, "life": life, "soft": soft, "root_dy": -0.25, "mode": "sit", "face_fix": face_fix,
		"gaze": "partner", "gaze_t": randf_range(3.0, 5.0)}
	for n in sk.get_children():
		if n is SkirtDrape:
			(n as SkirtDrape).frame = self
			(n as SkirtDrape).contain = contain_point
			(n as SkirtDrape).posed = seat_drape.bind(seat_name)
	# cloth spring chains (not the hair) rest while she sits: no flapping through the hull
	var sec = c.avatar.find_child("secondary", true, false) if c.avatar else null
	if sec and sec.get("spring_bones_internal") != null:
		var keep := []
		var keep_c := []
		var parked := []
		var centers = sec.get("springs_centers")
		for i in sec.spring_bones_internal.size():
			var sb = sec.spring_bones_internal[i]
			var hair := false
			for j in sb.joint_nodes:
				if String(j).contains("Hair") or String(j).contains("Earring"):
					hair = true
			if hair:
				keep.append(sb)
				if centers != null and i < centers.size():
					keep_c.append(centers[i])
			else:
				parked.append(sb)
		sec.spring_bones_internal.assign(keep)
		if centers != null:
			sec.springs_centers = PackedInt32Array(keep_c)
		print("[boat] %s: %d cloth spring chains rest while seated" % [c.character_id, parked.size()])
	life.look = _auto_look.bind(seat_name)
	var st0 := seat_xform(seat_name)
	c.global_transform = Transform3D(st0.basis * face_fix, st0.origin + st0.basis.y * -0.25)
	# sitting must take: a spell still being cast (or any action) would make the sit clip refuse, and she would stand
	# in the boat - finish it first and retry until the clip really plays
	if c.casting:
		c.stop_action()
	var tries := 0
	while not c.play_gesture("sit_loop", 0.5, 0.5) and tries < 20:
		c.stop_action()
		tries += 1
		await get_tree().create_timer(0.15).timeout
	if tries > 0:
		print("[boat] %s: sitting took %d retries" % [c.character_id, tries])
	c.set_seated(true, 0.7)
	# the root sits so her hips rest on the cushion (measured from the clip once it plays)
	await get_tree().create_timer(0.6).timeout
	var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	riders[seat_name].root_dy = HIPS_ABOVE_SEAT - (hips.y - c.global_position.y)
	await get_tree().process_frame
	for n in sk.get_children():
		if n is SkirtDrape:
			(n as SkirtDrape).resample()           # now that she sits on the cushion: sample the boat around her
	# feet on the floor in front of the seat
	pose.plant("Left", Vector3.INF, 1.0)
	pose.plant("Right", Vector3.INF, 1.0)


## Where she looks when no action needs her eyes: her friend (they talk), the sky, the water, the way ahead.
func _auto_look(seat_name: String) -> Vector3:
	var r: Dictionary = riders.get(seat_name, {})
	if r.is_empty():
		return Vector3.INF
	var st := seat_xform(seat_name)
	match String(r.gaze):
		"partner":
			for other in riders:
				if other != seat_name:
					var oc: WorldCharacter = riders[other].c
					return oc.skeleton.global_transform * oc.skeleton.get_bone_global_pose(oc.skeleton.find_bone("Head")).origin
		"sky":
			return st.origin + st.basis.z * 4.0 + Vector3(0, 8.0, 0)
		"water":
			var p := st.origin + side_vec(st, "Left") * 1.4 + st.basis.z * 0.8
			p.y = water_y
			return p
	return st.origin + st.basis.z * 6.0 + Vector3(0, 1.0, 0)


## Give her eyes back to the idle glances (after an action that set its own look).
func free_gaze(seat_name: String) -> void:
	var r: Dictionary = riders.get(seat_name, {})
	if not r.is_empty():
		(r.life as BodyLife).look = _auto_look.bind(seat_name)
		(r.life as BodyLife).look_weight = 0.45
		(r.life as BodyLife).look_max = deg_to_rad(38.0)


func rider(seat_name: String) -> Dictionary:
	return riders.get(seat_name, {})


func _feet_targets(seat_name: String) -> Array:
	var s: Dictionary = SEATS[seat_name]
	var sb := Basis(Vector3.UP, float(s.yaw))
	var f: Vector3 = s.pos + sb.z * (0.5 if seat_name == "bow" else 0.36)    # (their feet stay ~40 cm apart along the boat)
	f -= sb.x * 0.15               # each to her own right: facing each other, their legs pass side by side, never through
	f.y = -0.02
	return [global_transform * (f + sb.x * 0.13), global_transform * (f - sb.x * 0.13)]    # [left, right]


## Row: the rower (bow seat) pulls both oars in a slow stroke; the boat moves bow-first. on = false lays the oars in.
func row(on: bool) -> void:
	rowing = on
	var r: Dictionary = rider("bow")
	if r.is_empty():
		return
	var pose: SeatPose = r.pose
	var soft: SoftArms = r.soft
	soft.grip = {"Left": 0.85 if on else 0.0, "Right": 0.85 if on else 0.0}
	if not on:
		pose.release("Left")
		pose.release("Right")
		pose.lean = 0.0


## A trailing hand in the water over the side (side "Left"/"Right" of HER body), with a little wake from her fingers.
func trail_hand(seat_name: String, side: String, on: bool) -> void:
	var r: Dictionary = rider(seat_name)
	if r.is_empty():
		return
	r.mode = ("trail_" + side) if on else "sit"
	var pose: SeatPose = r.pose
	if on:
		pose.roll = deg_to_rad(-43.0 if side == "Left" else 43.0)
		pose.lean = deg_to_rad(8.0)
	else:
		pose.roll = 0.0
		pose.lean = 0.0
		pose.release(side)


## Where her trailing hand dips into the water (world).
func trail_point(seat_name: String, side: String) -> Vector3:
	var st := seat_xform(seat_name)
	var p := st.origin + side_vec(st, side) * (0.6 * SCALE) + st.basis.z * -0.05
	p.y = water_y + 0.1                          # (the wrist just above: her fingers are in the water)
	return p


## Light a lantern with a spark of magic from her fingertip ("bow" / "stern"); awaitable.
func light_lantern(seat_name: String, which: String, side := "Right") -> void:
	if not night():
		print("[boat] no lanterns in the day")
		return
	var r: Dictionary = rider(seat_name)
	var lp := lantern_pos(which)
	if not r.is_empty():
		var c: WorldCharacter = r.c
		var pose: SeatPose = r.pose
		var sh := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone(side + "UpperArm")).origin
		pose.reach(side, sh + (lp - sh).normalized() * 0.55, 1.0, Vector3(0.3 if side == "Right" else -0.3, -0.8, 0.0))
		(r.life as BodyLife).look = func() -> Vector3: return lp
		await get_tree().create_timer(1.0).timeout
		var tip := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone(side + "Hand")).origin
		await _spark(tip, lp, 0.7)
	_ignite(which)
	await get_tree().create_timer(0.8).timeout
	if not r.is_empty():
		(r.pose as SeatPose).release(side)
		free_gaze(seat_name)


func _ignite(which: String) -> void:
	var L: Dictionary = lanterns[which]
	var tw := create_tween()
	tw.tween_method(func(v):
		L.lit = v
		for m in L.mats:
			(m as StandardMaterial3D).emission_energy_multiplier = v * 1.3
		(L.light as OmniLight3D).light_energy = v * 0.7, 0.0, 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	_burst_at(lantern_pos(which), Color(1.0, 0.78, 0.45), 18)


## A little spark that flies from a to b (her fingertip to a wick); awaitable.
func _spark(a: Vector3, b: Vector3, dur: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/dance/glow_sprite.gdshader")
	m.set_shader_parameter("tex", load("res://assets/vfx/brackeys/particles/alpha/star_07_a.png"))
	m.set_shader_parameter("color", Color(1.0, 0.85, 0.55))
	m.set_shader_parameter("energy", 6.0)
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = a
	var tw := create_tween()
	tw.tween_method(func(k):
		var p := a.lerp(b, k)
		p.y += sin(k * PI) * 0.18
		mi.global_position = p, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	mi.queue_free()


func _burst_at(p: Vector3, col: Color, n: int) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.gravity = Vector3(0, 0.1, 0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var p3 := GPUParticles3D.new()
	p3.amount = n
	p3.lifetime = 1.2
	p3.one_shot = true
	p3.explosiveness = 0.9
	p3.local_coords = false
	p3.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/dance/glow_sprite.gdshader")
	m.set_shader_parameter("tex", load("res://assets/vfx/brackeys/particles/alpha/star_04_a.png"))
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", 4.0)
	q.material = m
	p3.draw_pass_1 = q
	get_parent().add_child(p3)
	p3.global_position = p
	p3.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p3.queue_free)


## A small floating lantern: it appears in her hand with a glint, she lights it, leans over the side and sets it on
## the water, where it drifts away. Awaitable.
func place_lantern(seat_name: String, side := "Left") -> void:
	if not night():
		print("[boat] no lanterns in the day")
		return
	var r: Dictionary = rider(seat_name)
	if r.is_empty() or lake == null:
		return
	var c: WorldCharacter = r.c
	var pose: SeatPose = r.pose
	var sk := c.skeleton
	var hand := func() -> Vector3: return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(side + "Hand")).origin
	var mi := MeshInstance3D.new()
	mi.mesh = lake.get("lantern_mesh")
	var sm := lake.call("_lantern_material", 0) as ShaderMaterial
	sm.set_shader_parameter("tint", Color(1.0, 0.56, 0.17))
	sm.set_shader_parameter("hot", Color(1.0, 0.9, 0.64))
	sm.set_shader_parameter("energy", 0.0)
	mi.material_override = sm
	mi.scale = Vector3.ONE * 0.3
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	# 1. held in front of her chest: it appears with a glint
	var st := seat_xform(seat_name)
	var front: Vector3 = st.basis.z
	var chest := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Chest")).origin
	var hold := chest + front * 0.32 + Vector3(0, -0.08, 0)
	pose.reach(side, hold, 1.0)
	var follow := true
	var follow_fn := func():
		while follow and is_instance_valid(mi):
			mi.global_position = (hand.call() as Vector3) + Vector3(0, -0.06, 0)
			await get_tree().process_frame
	follow_fn.call()
	(r.life as BodyLife).look = func() -> Vector3: return mi.global_position if is_instance_valid(mi) else Vector3.INF
	await get_tree().create_timer(0.7).timeout
	_burst_at(mi.global_position + Vector3(0, 0.1, 0), Color(1.0, 0.85, 0.6), 10)
	create_tween().tween_method(func(v): sm.set_shader_parameter("energy", v), 0.0, 1.6, 0.8)
	await get_tree().create_timer(1.0).timeout
	# 2. lean over the side and set it on the water
	var sgn := -1.0 if side == "Left" else 1.0
	var her_side: Vector3 = side_vec(st, side)
	var water := st.origin + her_side * (0.62 * SCALE) + front * 0.15
	water.y = water_y + 0.08
	pose.roll = deg_to_rad(24.0 * sgn)
	pose.lean = deg_to_rad(10.0)
	pose.reach(side, water + Vector3(0, 0.1, 0), 1.0)
	await get_tree().create_timer(1.3).timeout
	follow = false
	var tw := create_tween()
	tw.tween_property(mi, "global_position", Vector3(water.x, water_y + 0.01, water.z), 0.5).set_trans(Tween.TRANS_SINE)
	await tw.finished
	ring(Vector3(water.x, water_y, water.z), 0.7, Color(0.7, 0.76, 0.9), 0.3)
	_floaters.append({"node": mi, "vel": (her_side * 0.12 + Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03))), "seed": randf() * 10.0})
	await get_tree().create_timer(0.5).timeout
	pose.release(side)
	pose.roll = 0.0
	pose.lean = 0.0
	free_gaze(seat_name)


## Lean back and look up at the sky (on), or sit up again.
func stargaze(seat_name: String, on: bool) -> void:
	if on and not night():
		print("[boat] no stargazing in the day")
		return
	var r: Dictionary = rider(seat_name)
	if r.is_empty():
		return
	var pose: SeatPose = r.pose
	r.mode = "stargaze" if on else "sit"
	pose.lean = deg_to_rad(-20.0) if on else 0.0
	var c: WorldCharacter = r.c
	(r.life as BodyLife).look = func() -> Vector3:
		if r.mode != "stargaze":
			return Vector3.INF
		var st := seat_xform(seat_name)
		return st.origin + st.basis.z * 3.0 + Vector3(0, 9.0, 0)
	(r.life as BodyLife).look_max = deg_to_rad(60.0) if on else deg_to_rad(38.0)
	(r.life as BodyLife).look_weight = 0.7 if on else 0.45
	if on and seat_name == "bow":
		# no backrest: she props herself on her hands behind her
		var st := seat_xform(seat_name)
		var back: Vector3 = -st.basis.z
		pose.reach("Left", st.origin + back * 0.28 + side_vec(st, "Left") * 0.2 + Vector3(0, 0.02, 0), 0.9, Vector3(-0.3, 0.2, 0.6))
		pose.reach("Right", st.origin + back * 0.28 + side_vec(st, "Right") * 0.2 + Vector3(0, 0.02, 0), 0.9, Vector3(0.3, 0.2, 0.6))
	elif not on:
		pose.release("Left")
		pose.release("Right")
		free_gaze(seat_name)


## Point at a spot in the sky (world direction) for a few seconds; awaitable.
func point_at(seat_name: String, dir: Vector3, side := "Right", seconds := 2.5) -> void:
	var r: Dictionary = rider(seat_name)
	if r.is_empty():
		return
	var c: WorldCharacter = r.c
	var sk := c.skeleton
	var sh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(side + "UpperArm")).origin
	(r.pose as SeatPose).reach(side, sh + dir.normalized() * 0.6, 1.0, Vector3(0.5 if side == "Right" else -0.5, -0.6, -0.2))
	await get_tree().create_timer(seconds).timeout
	(r.pose as SeatPose).release(side)


## Chin resting on a hand, the elbow on her knee (on), or not.
func chin_rest(seat_name: String, on: bool, side := "Right") -> void:
	var r: Dictionary = rider(seat_name)
	if r.is_empty():
		return
	r.mode = ("chin_" + side) if on else "sit"
	var pose: SeatPose = r.pose
	pose.lean = deg_to_rad(16.0) if on else 0.0
	if not on:
		pose.release(side)


## Look down at the water over the side for a while (on), or back up.
func look_water(seat_name: String, on: bool, side := "Left") -> void:
	var r: Dictionary = rider(seat_name)
	if r.is_empty():
		return
	r.mode = ("water_" + side) if on else "sit"
	(r.life as BodyLife).look = func() -> Vector3:
		if not String(r.mode).begins_with("water"):
			return Vector3.INF
		var st := seat_xform(seat_name)
		var p := st.origin + side_vec(st, side) * 1.2 + st.basis.z * 0.6
		p.y = water_y
		return p
	(r.life as BodyLife).look_weight = 0.65 if on else 0.45
	(r.pose as SeatPose).roll = deg_to_rad(-8.0 if side == "Left" else 8.0) if on else 0.0


## A ripple ring on the water at p.
func ring(p: Vector3, size := 1.0, col := Color(0.8, 0.86, 1.0), energy := 0.9) -> void:
	if RenderProfile.options.has("ring-debug"):
		print("[ring] size %.2f energy %.3f at %s" % [size, energy, str(p.snappedf(0.1))])
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(2.0, 2.0) * size
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("strength", clampf(energy * 0.25, 0.03, 0.09))  # (a swell of the water, never a glow)
	m.set_shader_parameter("width", 0.11)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = Vector3(p.x, water_y + 0.008, p.z)
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("t", v), 0.0, 1.0, 2.6)
	tw.tween_callback(mi.queue_free)


# ------------------------------------------------------------------------------------------------ every frame
func _place() -> void:
	var bob := 0.022 * sin(_t * 1.25) + 0.01 * sin(_t * 2.3 + 1.1)
	var rl := deg_to_rad(1.6) * sin(_t * 0.9) + deg_to_rad(0.6) * sin(_t * 1.7 + 0.4)
	var pt := deg_to_rad(0.9) * sin(_t * 1.1 + 0.8)
	if rowing:
		pt += deg_to_rad(0.8) * sin(_row_phase * TAU)
	global_transform = Transform3D(Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, rl) * Basis(Vector3.BACK, pt), _base + Vector3(0, bob, 0))


func _process(delta: float) -> void:
	_t += delta
	# rowing: the stroke drives the boat; the oars sweep, dip and feather
	var fwd := -(Basis(Vector3.UP, _yaw) * Vector3.RIGHT)          # the bow's way
	if rowing:
		_row_phase = fmod(_row_phase + delta / 3.4, 1.0)
		var drive := _row_phase < 0.42
		if drive:
			speed = minf(speed + delta * 0.55, 1.1)
	speed = maxf(speed - delta * speed * 0.18, 0.0)
	_base += fwd * speed * delta
	_yaw += turn * delta
	_place()
	_animate_oars(delta)
	# riders ride with the boat; their hands and feet go where the action needs them
	for seat_name in riders:
		var r: Dictionary = riders[seat_name]
		var c: WorldCharacter = r.c
		r.gaze_t = float(r.gaze_t) - delta
		if float(r.gaze_t) <= 0.0:
			var pick := randf()
			r.gaze = "partner" if pick < 0.5 else ("sky" if pick < 0.7 else ("water" if pick < 0.85 else "ahead"))
			r.gaze_t = randf_range(3.5, 7.0)
		var st := seat_xform(seat_name)
		c.global_transform = Transform3D(st.basis * (r.face_fix as Basis), st.origin + st.basis.y * float(r.root_dy))
		# closed loop: her hips settle exactly on the cushion whatever the clip's timing (the clip's own hips, before
		# any correction, read every frame)
		var skh := c.skeleton
		var hy := (skh.global_transform * skh.get_bone_global_pose(skh.find_bone("Hips")).origin).y
		var err := HIPS_ABOVE_SEAT - (hy - st.origin.y)
		if absf(err) > 0.002 and String(c.current_gesture) == "sit_loop":
			r.root_dy = float(r.root_dy) + err * minf(1.0, delta * 6.0)
		var pose: SeatPose = r.pose
		var ft := _feet_targets(seat_name)
		pose.plant("Left", ft[0] + Vector3(0, 0.07, 0), float(pose.leg.Left.goal))
		pose.plant("Right", ft[1] + Vector3(0, 0.07, 0), float(pose.leg.Right.goal))
		if seat_name == "bow" and rowing:
			var ph := _row_phase * TAU
			pose.lean = deg_to_rad(10.0) * cos(ph)
			pose.reach("Left", grip("L"), 1.0, Vector3(-0.6, -0.5, -0.4), true)
			pose.reach("Right", grip("R"), 1.0, Vector3(0.6, -0.5, -0.4), true)
		var mode := String(r.mode)
		if mode.begins_with("trail_"):
			var side := mode.trim_prefix("trail_")
			var sgn := -1.0 if side == "Left" else 1.0
			var p := st.origin + side_vec(st, side) * (0.6 * SCALE) + st.basis.z * -0.05
			p.y = water_y + 0.1
			pose.reach(side, p, 1.0, Vector3(0.6 * sgn, -0.3, -0.5))
			# the other hand rests on her thigh (never in the air)
			var other := "Right" if side == "Left" else "Left"
			var skc := c.skeleton
			var ul := skc.global_transform * skc.get_bone_global_pose(skc.find_bone(other + "UpperLeg")).origin
			var ll := skc.global_transform * skc.get_bone_global_pose(skc.find_bone(other + "LowerLeg")).origin
			pose.reach(other, ul.lerp(ll, 0.6) + Vector3(0, 0.1, 0), 1.0, Vector3(0.4 * -sgn, -0.4, -0.4))
			if speed > 0.05 and fmod(_t, 0.9) < delta:
				ring(p, 0.3 + speed * 0.25, Color(0.66, 0.72, 0.86), 0.2)
		elif mode.begins_with("chin_"):
			var side2 := mode.trim_prefix("chin_")
			var sk := c.skeleton
			var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
			pose.reach(side2, head + st.basis.z * 0.17 + Vector3(0, -0.1, 0), 1.0, Vector3(0.15 if side2 == "Right" else -0.15, -1.0, 0.2))
	# the water: a slow ring round the hull, a wake at the bow when she moves
	_since_ripple += delta
	if speed > 0.08 and _since_ripple > 1.4:
		_since_ripple = 0.0
		var k := clampf(speed / 1.0, 0.0, 1.0)
		var side_v := fwd.cross(Vector3.UP)
		ring(global_position + fwd * 2.0, 0.5 + 0.4 * k, Color(0.62, 0.68, 0.82), 0.16 * k)
		ring(global_position + side_v * 0.75 + fwd * 0.4, 0.4, Color(0.62, 0.68, 0.82), 0.1 * k)
		ring(global_position - side_v * 0.75 + fwd * 0.4, 0.4, Color(0.62, 0.68, 0.82), 0.1 * k)
	# floating lanterns drift and bob
	for f in _floaters:
		var n: Node3D = f.node
		if not is_instance_valid(n):
			continue
		var p2 := n.global_position + (f.vel as Vector3) * delta
		p2.y = water_y + 0.01 + 0.012 * sin(_t * 1.4 + float(f.seed))
		n.global_position = p2
		f.vel = (f.vel as Vector3) * (1.0 - delta * 0.05)
		n.rotation.y += delta * 0.1


func _animate_oars(_delta: float) -> void:
	for side in oars:
		var o: Dictionary = oars[side]
		var n: Node3D = o.node
		var sgn := 1.0 if side == "L" else -1.0
		var yaw := 0.0
		var pitch := 0.0
		if rowing:
			var ph := _row_phase * TAU
			# drive (blade in the water, the grip comes toward her) then the recovery (blade up, back to the catch)
			yaw = deg_to_rad(28.0) * cos(ph)
			pitch = deg_to_rad(7.0) * (1.0 if _row_phase > 0.45 else -0.6)
			if _row_phase < 0.05 and not _caught:
				var blade: Vector3 = n.global_transform * (-(o.axis_in as Vector3) * 1.0)
				ring(Vector3(blade.x, water_y, blade.z), 0.45, Color(0.66, 0.72, 0.86), 0.22)
		var lift := deg_to_rad(16.0) if rowing else 0.0            # (grips above her lap, blades lower)
		var q := Quaternion(Vector3.UP, yaw * sgn) * Quaternion(Vector3.RIGHT, (pitch + lift) * sgn)
		if rowing and side == "R":
			_caught = _row_phase < 0.05
		n.basis = n.basis.slerp(Basis(q) * (o.rest as Basis), 0.25)


## QA: the oar grips against the rower's shoulders.
func debug_grips() -> String:
	var r: Dictionary = rider("bow")
	if r.is_empty():
		return "no rower"
	var c: WorldCharacter = r.c
	var sk := c.skeleton
	var out := []
	for side in ["Left", "Right"]:
		var sh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(side + "UpperArm")).origin
		var g := grip("L" if side == "Left" else "R")
		out.append("%s grip %s shoulder %s dist %.2f" % [side, str(g.snappedf(0.01)), str(sh.snappedf(0.01)), g.distance_to(sh)])
	return "; ".join(out)


## QA: a rider's action state.
func debug_rider(seat_name: String) -> String:
	var r: Dictionary = rider(seat_name)
	if r.is_empty():
		return "no rider"
	var pose: SeatPose = r.pose
	var c: WorldCharacter = r.c
	var sk := c.skeleton
	var sh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftUpperArm")).origin
	var tg: Vector3 = pose.arm.Left.target
	return "calls %d active %s infl %.2f | %s mode %s roll %.2f lean %.2f armL w %.2f goal %.2f target dist %.2f  idx %d/%d ok %s" % [pose.calls, str(pose.active), pose.influence, seat_name, r.mode, pose.roll,
		pose.lean, float(pose.arm.Left.w), float(pose.arm.Left.goal), (tg.distance_to(sh) if tg != Vector3.INF else -1.0),
		pose.get_index(), sk.get_child_count(), str(pose.get("_ok"))]


# ------------------------------------------------------------------------------------------------ persistence
## (ScenePersist contract, 2026-10-19: group "persistent_activity", persist_key / snapshot / restore.) A restart puts
## the boat back where it floated, with the same heading, speed and stroke, the same girls on the same seats doing
## the same thing (rowing, a hand in the water, stargazing...), the lanterns lit as they were and the floating
## lanterns where they drifted. restore() also builds a boat made with MoonBoat.new() (ScenePersist rebuilds it).
func _enter_tree() -> void:
	add_to_group("persistent_activity")


func persist_key() -> String:
	return "moon_boat:" + String(name)


## Changes when the activity changes step (a save follows at once).
func persist_step() -> String:
	var parts := ["rowing" if rowing else "drifting"]
	for s in riders:
		var c = riders[s].get("c")
		parts.append("%s=%s:%s" % [s, String(c.character_id) if is_instance_valid(c) else "?", String(riders[s].get("mode", ""))])
	for w in lanterns:
		if float(lanterns[w].lit) > 0.5:
			parts.append("lit:" + w)
	parts.append("floating:%d" % _floaters.size())
	return ",".join(parts)


func snapshot() -> Dictionary:
	if hull == null:
		return {}
	var rs := {}
	var who := []
	for s in riders:
		var c = riders[s].get("c")
		if not is_instance_valid(c):
			continue
		rs[s] = {"who": String(c.character_id), "mode": String(riders[s].get("mode", "sit")), "gaze": String(riders[s].get("gaze", "partner"))}
		who.append(String(c.character_id))
	var lit := {}
	for w in lanterns:
		lit[w] = snappedf(float(lanterns[w].lit), 0.001)
	var fl := []
	for f in _floaters:
		var n: Node3D = f.get("node")
		if n == null or not is_instance_valid(n):
			continue
		var v: Vector3 = f.vel
		fl.append({"p": [n.global_position.x, n.global_position.y, n.global_position.z], "v": [v.x, v.y, v.z], "seed": float(f.get("seed", 0.0)),
			"ry": n.rotation.y})
	return {"kind": "moon_boat", "step": persist_step(), "name": String(name), "base": [_base.x, _base.y, _base.z], "yaw": _yaw,
		"water_y": water_y, "speed": speed, "turn": turn, "rowing": rowing, "row_phase": _row_phase, "t": _t, "riders": rs,
		"lit": lit, "floaters": fl, "participants": who}


func restore(d: Dictionary) -> void:
	if d.has("name") and String(d.name) != "":
		name = String(d.name)
	water_y = float(d.get("water_y", water_y))
	var b: Array = d.get("base", [])
	if b.size() == 3:
		_base = Vector3(float(b[0]), water_y, float(b[2]))
	_yaw = float(d.get("yaw", _yaw))
	_t = float(d.get("t", _t))
	turn = float(d.get("turn", 0.0))
	if hull == null:                     # a boat made by ScenePersist: built as spawn() builds it
		scale = Vector3.ONE * SCALE
		_build()
	_place()
	set_meta("persist_restored_at", [_base.x, _base.y, _base.z])     # (QA: where the restore put it, before it rows on)
	var m := get_tree().current_scene
	if lake == null:
		for n in get_parent().find_children("*", "Node3D", true, false) + [get_parent()]:
			if n.get("water_mat") != null:
				lake = n
				break
	if day_night == null and m and m.get("day_night"):
		day_night = m.day_night
	# the lanterns as they were (lit, no spark: they were already burning)
	var lit: Dictionary = d.get("lit", {})
	for w in lit:
		if lanterns.has(w):
			var L: Dictionary = lanterns[w]
			L.lit = float(lit[w])
			for mm in L.mats:
				(mm as StandardMaterial3D).emission_energy_multiplier = float(lit[w]) * 1.3
			(L.light as OmniLight3D).light_energy = float(lit[w]) * 0.7
	# the floating lanterns where they drifted
	for f in (d.get("floaters", []) as Array):
		if lake == null:
			break
		var mi := MeshInstance3D.new()
		mi.mesh = lake.get("lantern_mesh")
		var sm := lake.call("_lantern_material", 0) as ShaderMaterial
		sm.set_shader_parameter("tint", Color(1.0, 0.56, 0.17))
		sm.set_shader_parameter("hot", Color(1.0, 0.9, 0.64))
		sm.set_shader_parameter("energy", 1.6)
		mi.material_override = sm
		mi.scale = Vector3.ONE * 0.3
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(mi)
		var p: Array = f.get("p", [0, 0, 0])
		var v: Array = f.get("v", [0, 0, 0])
		mi.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		mi.rotation.y = float(f.get("ry", 0.0))
		_floaters.append({"node": mi, "vel": Vector3(float(v[0]), float(v[1]), float(v[2])), "seed": float(f.get("seed", 0.0))})
	# the girls back on their seats (both at once), doing what they were doing
	var guard = m.get("teleport_guard") if m else null
	var chars := {}
	for c in get_tree().get_nodes_in_group("mage"):
		chars[String(c.get("character_id"))] = c
	var rs: Dictionary = d.get("riders", {})
	for s in rs:
		var c: WorldCharacter = chars.get(String(rs[s].get("who", "")))
		if c == null or not SEATS.has(s):
			continue
		if riders.has(s) and riders[s].c == c:
			continue
		if guard:
			guard.allow(c)
		c.stop_action()
		c.visible = true
		c.set_physics_process(false)
		c.velocity = Vector3.ZERO
		seat(c, s)                       # (placed on the seat at once; the hips settle on the cushion in 0.6 s)
	speed = float(d.get("speed", 0.0))
	_row_phase = float(d.get("row_phase", 0.0))
	set_meta("persist_restored_speed", speed)
	if bool(d.get("rowing", false)):
		row(true)
	for s in rs:
		if not riders.has(s):
			continue
		riders[s].gaze = String(rs[s].get("gaze", "partner"))
		var mode := String(rs[s].get("mode", "sit"))
		if mode.begins_with("trail_"):
			trail_hand(s, mode.trim_prefix("trail_"), true)
		elif mode == "stargaze":
			stargaze(s, true)
		elif mode.begins_with("chin_"):
			chin_rest(s, true, mode.trim_prefix("chin_"))
		elif mode.begins_with("water_"):
			look_water(s, true, mode.trim_prefix("water_"))
	await get_tree().create_timer(0.75).timeout
	print("[boat] resumed: %s at %s, speed %.2f, %s" % [name, str(_base.snappedf(0.01)), speed, persist_step()])


# ------------------------------------------------------------------------------------------------ leaving the boat
# (LakeRitual, 2026-10-19 - appended only) the living world's boat ritual needs her OUT of the boat again and the boat
# brought in to the pier / pushed off from it.

## She gets up: the seated stack (SeatPose, BodyLife, SoftArms) is removed, the drape lets go of the boat, seated off.
## The caller moves her (an arc onto the pier) and turns her physics back on. Returns her (or null).
func unseat(seat_name: String) -> WorldCharacter:
	var r: Dictionary = riders.get(seat_name, {})
	if r.is_empty():
		return null
	riders.erase(seat_name)
	var c: WorldCharacter = r.c
	if seat_name == "bow" and rowing:
		row(false)
	for k in ["pose", "life", "soft"]:
		var n = r.get(k)
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	if c and is_instance_valid(c):
		for n in c.skeleton.get_children():
			if n is SkirtDrape:
				(n as SkirtDrape).frame = null
				(n as SkirtDrape).contain = Callable()
				if n.get("posed") != null:
					n.set("posed", Callable())
				(n as SkirtDrape).resample()
		c.end_gesture()
		c.set_seated(false, 0.5)
	return c


## Glide (no strokes: pushed off, or coasting in) to a waterline point and heading over `seconds`; awaitable.
func glide_to(at: Vector3, yaw: float, seconds: float) -> void:
	var b0 := _base
	var y0 := _yaw
	var b1 := Vector3(at.x, water_y, at.z)
	speed = 0.0
	var tw := create_tween()
	tw.tween_method(func(k: float):
		_base = b0.lerp(b1, k)
		_yaw = lerp_angle(y0, yaw, k), 0.0, 1.0, maxf(seconds, 0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


## The heading the boat has now (the bow's way is -(Basis(UP, yaw) * X)).
func heading() -> float:
	return _yaw
