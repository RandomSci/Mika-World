class_name AttackHazard
extends Node3D
## One creature attack in flight: a TELEGRAPH the mages can see, then a resolution against where each mage
## actually is at that moment. Nothing is decided in advance - a mage who steps out of the marked ground,
## or out of a projectile's path, is simply not hit.
##   area        - a circle on the ground (slam): hits mages inside `radius` of `center` at `t_hit`
##   arc         - a sector in front of the creature (sweep): range `radius`, +-`half_angle` around `dir`
##   projectile  - a real moving bolt from `center` along `dir` at `speed`; hits the first mage it touches
## Mages perceive hazards only through their senses (see `perceived_by`): no hidden knowledge.

signal resolved(hazard: AttackHazard, struck: Array)

var kind := "area"
var owner_monster: Node3D = null
var owner_mage: Node3D = null      # a training bolt's caster: never struck by her own spell
var center := Vector3.ZERO
var dir := Vector3.FORWARD
var radius := 2.0
var half_angle := PI
var speed := 9.0
var max_range := 14.0
var vigor := 0.06
var heavy := false
var style := "ember"               # projectile look: ember (glowing bolt) | stone (a thrown boulder)
var t_hit := 0.0                    # seconds from spawn until it lands (area / arc)
var age := 0.0
var color := Color(1.0, 0.55, 0.25)
var done := false
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _bolt: Node3D
var _travelled := 0.0
var _exclude: Array = []


static func active(world: Node) -> Array:
	return world.get_tree().get_nodes_in_group("attack_hazard") if world else []


func _ready() -> void:
	add_to_group("attack_hazard")
	if kind in ["area", "arc"]:
		_mesh = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(radius * 2.0, radius * 2.0)
		_mesh.mesh = pm
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/telegraph.gdshader")
		_mat.set_shader_parameter("color", color)
		_mat.set_shader_parameter("half_angle", half_angle if kind == "arc" else 3.2)
		_mesh.material_override = _mat
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)
		global_position = center + Vector3(0, 0.06, 0)
		if kind == "arc":
			# the shader's forward (+V) is the plane's local +Z: turn local +Z toward the sweep direction
			look_at(global_position - Vector3(dir.x, 0, dir.z), Vector3.UP)
	else:
		global_position = center
		_bolt = Node3D.new()
		add_child(_bolt)
		if style == "stone":
			var rock := MeshInstance3D.new()
			var sm2 := SphereMesh.new()
			sm2.radius = 0.28
			sm2.height = 0.5
			sm2.radial_segments = 7
			sm2.rings = 4
			rock.mesh = sm2
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color(0.42, 0.4, 0.37)
			rm.roughness = 0.95
			rock.material_override = rm
			_bolt.add_child(rock)
			var dust := FX.particles(14, 0.5, FX.pm_puff("dust"), FX.puff_mesh(0.25))
			dust.emitting = true
			_bolt.add_child(dust)
			return
		var core := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		core.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color.lerp(Color(1.0, 0.9, 0.6), 0.25)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.6
		core.material_override = m
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bolt.add_child(core)
		var trail := FX.particles(18, 0.45, FX.pm_motes("fire", "trail"), FX.mote_mesh(0.06))
		trail.emitting = true
		_bolt.add_child(trail)
		var l := FX.light(color, 1.2 * float(RenderProfile.get_setting("magic_light_scale")), 3.0)
		_bolt.add_child(l)


## What a mage standing at `p` can know about this hazard: only if she can see it (creature in view and in
## range) - the planner never reads hazards she could not perceive.
func perceived_by(c: Node3D) -> bool:
	if done or not is_instance_valid(c):
		return false
	var src: Vector3 = (owner_monster.global_position if is_instance_valid(owner_monster) else center)
	var d := Vector2(c.global_position.x - src.x, c.global_position.z - src.z).length()
	if d > 26.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(c.global_position + Vector3(0, 1.5, 0), src + Vector3(0, 1.0, 0))
	q.exclude = _exclude + [c.get_rid()]
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Seconds until it lands on point `p` (area/arc: the fixed timing; projectile: when it reaches p's
## distance along its path, INF if p is not in its path).
func time_to(p: Vector3) -> float:
	if kind == "projectile":
		var pos := _bolt.global_position if _bolt else center
		var to := p - pos
		var along := Vector3(dir.x, 0, dir.z).normalized().dot(Vector3(to.x, 0, to.z))
		if along < 0.0:
			return INF
		return along / maxf(speed, 0.1)
	return maxf(0.0, t_hit - age)


## Would a mage standing at `p` be struck if she stays there?
func threatens(p: Vector3, margin := 0.35) -> bool:
	match kind:
		"area":
			return Vector2(p.x - center.x, p.z - center.z).length() <= radius + margin
		"arc":
			var v := Vector2(p.x - center.x, p.z - center.z)
			if v.length() > radius + margin:
				return false
			return v.length() < 0.6 or absf(Vector2(dir.x, dir.z).angle_to(v)) <= half_angle + 0.15
		_:
			var pos := _bolt.global_position if _bolt else center
			var f := Vector3(dir.x, 0, dir.z).normalized()
			var to := Vector3(p.x - pos.x, 0, p.z - pos.z)
			var along := f.dot(to)
			if along < -0.3 or along > max_range:
				return false
			return (to - f * along).length() <= 0.45 + margin


## A direction (unit, flat) that leaves the danger quickest from `p`.
func escape_dir(p: Vector3) -> Vector3:
	match kind:
		"area":
			var v := Vector3(p.x - center.x, 0, p.z - center.z)
			return v.normalized() if v.length() > 0.2 else Vector3(-dir.z, 0, dir.x).normalized()
		"arc":
			var side := Vector3(-dir.z, 0, dir.x).normalized()
			var v2 := Vector3(p.x - center.x, 0, p.z - center.z)
			return (v2.normalized() * 0.4 + side * (1.0 if side.dot(v2) >= 0.0 else -1.0)).normalized()
		_:
			var f := Vector3(dir.x, 0, dir.z).normalized()
			var side2 := Vector3(-f.z, 0, f.x)
			var pos := _bolt.global_position if _bolt else center
			return side2 if side2.dot(Vector3(p.x - pos.x, 0, p.z - pos.z)) >= 0.0 else -side2


func _physics_process(delta: float) -> void:
	if done:
		return
	age += delta
	if kind in ["area", "arc"]:
		if _mat:
			_mat.set_shader_parameter("progress", clampf(age / maxf(t_hit, 0.01), 0.0, 1.0))
			_mat.set_shader_parameter("intensity", 0.8 + 1.2 * clampf(age / maxf(t_hit, 0.01), 0.0, 1.0))
		if age >= t_hit:
			_resolve_ground()
		return
	# projectile: swept movement, hits a mage whose body it touches, stops on solid ground / walls
	var step := Vector3(dir.x, dir.y, dir.z).normalized() * speed * delta
	var from := _bolt.global_position
	var to := from + step
	_travelled += step.length()
	var struck := []
	for c in _mages():
		if c == owner_mage:
			continue
		var cp: Vector3 = c.global_position + Vector3(0, 1.0, 0)
		var seg := Geometry3D.get_closest_point_to_segment(cp, from, to)
		if seg.distance_to(cp) < 0.55 and not c.has_meta("transforming"):
			struck.append(c)
			break
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = _exclude
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_bolt.global_position = to if hit.is_empty() else hit.position
	if not struck.is_empty() or not hit.is_empty() or _travelled > max_range:
		_finish(struck, _bolt.global_position)


func _resolve_ground() -> void:
	var struck := []
	for c in _mages():
		if c.has_meta("transforming") or c == owner_mage:
			continue
		if threatens(c.global_position, 0.0):
			struck.append(c)
	_finish(struck, center)


func _finish(struck: Array, at: Vector3) -> void:
	done = true
	remove_from_group("attack_hazard")
	resolved.emit(self, struck)
	if kind == "projectile":
		if style == "stone":
			FX.burst(get_parent(), at, 12, 1.0, FX.pm_puff("dust"), FX.puff_mesh(0.45))
		else:
			FX.burst(get_parent(), at, 18, 0.5, FX.pm_motes("fire", "burst"), FX.mote_mesh(0.05))
		queue_free()
	else:
		var tw := create_tween()
		tw.tween_method(func(k: float): if _mat: _mat.set_shader_parameter("intensity", 2.0 * (1.0 - k)), 0.0, 1.0, 0.35)
		tw.tween_callback(queue_free)


func _mages() -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("mage"):
		if n is WorldCharacter and (n as WorldCharacter).is_visible_in_tree():
			out.append(n)
	return out


func set_exclude(rids: Array) -> void:
	_exclude = rids
