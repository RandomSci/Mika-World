class_name WaterPath
extends Node3D
## The magic path over Lantern Lake (2026-10-23, Selwyn: "walking on the lake must always be magic ... the path glows
## under each step with ripples, and it fades after they leave"). Two strips side by side from the shore out to a
## circle on the water: Mika's frost and stars on her side, Luna's moonlight on hers (shaders/lake/water_path.gdshader).
## Built in the lake area's own space; solid (a thin collider just over the water, world layer) only while it is lit,
## so the area's navmesh, baked again with it, reaches the circle and nowhere else on the water.

const SHADER := preload("res://shaders/lake/water_path.gdshader")
const TOP := 0.06                         # the walking surface over the water (m)
const STRIP_W := 1.35
const FROST := [Color(0.3, 0.7, 1.0), Color(0.85, 0.95, 1.0)]       # ice blue, the stars near white
const MOON := [Color(0.55, 0.38, 1.0), Color(0.9, 0.85, 1.0)]       # violet moonlight, silver

var from := Vector3.ZERO                  # area-local: the shore end (middle of the two strips)
var to := Vector3.ZERO                    # area-local: the circle's middle
var radius := 3.0
var mats: Array[ShaderMaterial] = []
var body: StaticBody3D
var walkers: Array = []                   # WorldCharacters whose steps light it
var _steps: Array = []                    # [Vector4(x, z, t, 1)]
var _feet := {}                           # character id + side -> {p, moving}
var _t := 0.0


## Make it (unlit, not solid yet). `from` / `to` in the parent's space.
func build(p_from: Vector3, p_to: Vector3, p_radius := 3.0) -> void:
	from = p_from
	to = p_to
	radius = p_radius
	name = "WaterPath"
	var d := Vector3(to.x - from.x, 0, to.z - from.z)
	var length := maxf(d.length() - radius * 0.6, 1.0)
	var fwd := d.normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var yaw := atan2(fwd.x, fwd.z)
	# the two strips (UV.y runs out from the shore), one each side of the middle line
	for i in 2:
		var m := _material(FROST if i == 0 else MOON, i)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(STRIP_W, length)
		pm.subdivide_depth = 0
		mi.mesh = pm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mid := from + fwd * (length * 0.5) + side * (STRIP_W * 0.5 * (-1.0 if i == 0 else 1.0))
		mi.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.UP, PI), Vector3(mid.x, TOP + 0.005 * (i + 1), mid.z))
		add_child(mi)
	# the circle
	var cm := _material([FROST[0], MOON[1]], 2)
	var ci := MeshInstance3D.new()
	var cp := PlaneMesh.new()
	cp.size = Vector2(radius * 2.0, radius * 2.0)
	ci.mesh = cp
	ci.material_override = cm
	ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ci.position = Vector3(to.x, TOP + 0.02, to.z)
	add_child(ci)
	# what they walk on: one box down the strips (a little into the bank) and the circle
	body = StaticBody3D.new()
	body.name = "PathFloor"
	body.collision_layer = 0                  # (solid only once it is lit)
	body.collision_mask = 0
	var bs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(STRIP_W * 2.0, 0.12, length + 1.5)
	bs.shape = box
	var bmid := from + fwd * ((length - 1.5) * 0.5)
	bs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(bmid.x, TOP - 0.06, bmid.z))
	body.add_child(bs)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 0.12
	cs.shape = cyl
	cs.position = Vector3(to.x, TOP - 0.06, to.z)
	body.add_child(cs)
	add_child(body)


func _material(cols: Array, style: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("style", style)
	m.set_shader_parameter("col_a", cols[0])
	m.set_shader_parameter("col_b", cols[1])
	m.set_shader_parameter("grow", 0.0)
	m.set_shader_parameter("fade", 1.0)
	mats.append(m)
	return m


## Solid or not (the world layer the navmesh bake and the characters see).
func set_solid(on: bool) -> void:
	body.collision_layer = 1 if on else 0


## Form it: each strip grows out from the shore over `secs`, the circle opens as the strips reach it.
func form(secs := 2.6) -> void:
	var tw := create_tween().set_parallel(true)
	for i in 2:
		tw.tween_method(func(v: float): mats[i].set_shader_parameter("grow", v), 0.0, 1.0, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): mats[2].set_shader_parameter("grow", v), 0.0, 1.0, secs * 0.6).set_delay(secs * 0.75)
	await tw.finished


## Fade it out (then it is free to be removed).
func dissolve(secs := 6.0) -> void:
	set_solid(false)
	var tw := create_tween()
	tw.tween_method(func(v: float):
		for m in mats:
			m.set_shader_parameter("fade", v), 1.0, 0.0, secs).set_trans(Tween.TRANS_SINE)
	await tw.finished


## Light a step at a world point (also called by the footstep watcher).
func step_at(p: Vector3) -> void:
	_steps.append(Vector4(p.x, p.z, _t, 1.0))
	if _steps.size() > 8:
		_steps.pop_front()
	var arr: Array[Vector4] = []
	for s in _steps:
		arr.append(s)
	while arr.size() < 8:
		arr.append(Vector4.ZERO)
	for m in mats:
		m.set_shader_parameter("steps", arr)


## On the path: within a strip or the circle (world point).
func covers(p: Vector3) -> bool:
	var l := to_local(p)
	if Vector2(l.x - to.x, l.z - to.z).length() < radius:
		return true
	var d := Vector3(to.x - from.x, 0, to.z - from.z)
	var u := Vector3(l.x - from.x, 0, l.z - from.z)
	var along := u.dot(d.normalized())
	return along > -1.0 and along < d.length() and absf(u.dot(Vector3(-d.normalized().z, 0, d.normalized().x))) < STRIP_W + 0.2


func _process(delta: float) -> void:
	_t += delta
	for m in mats:
		m.set_shader_parameter("now", _t)
	# a foot that came down on the path: it glows and rings out there
	for c in walkers:
		if not is_instance_valid(c):
			continue
		var sk: Skeleton3D = (c as WorldCharacter).skeleton
		for side in ["Left", "Right"]:
			var bi := sk.find_bone(side + "Foot")
			if bi < 0:
				continue
			var fp: Vector3 = sk.global_transform * sk.get_bone_global_pose(bi).origin
			var key := "%s:%s" % [(c as WorldCharacter).character_id, side]
			var st: Dictionary = _feet.get(key, {"p": fp, "moving": false})
			var v := Vector2(fp.x - st.p.x, fp.z - st.p.z).length() / maxf(delta, 0.001)
			var low := fp.y - global_position.y < TOP + 0.22
			if bool(st.moving) and v < 0.25 and low and covers(fp):
				step_at(fp)
				st.moving = false
			elif v > 0.9:
				st.moving = true
			st.p = fp
			_feet[key] = st
