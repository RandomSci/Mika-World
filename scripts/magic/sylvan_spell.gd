class_name SylvanSpell
extends FamilySpell
## Mika's family (V3 Part XIII): wind that curves and things that grow. No closed circles and no straight
## lines - her magic sweeps, spirals and unfolds.
##   spiral  GALE SPIRAL - leaves lift off the ground round her feet while a small spiral of air forms between
##           her hands (a two-handed sweep); the gust leaves as a WEAVING helix of two braided ribbons shedding
##           leaves - the ribbons are drawn along the path the gust has really flown - and bursts at impact
##           into leaves and air, shoving the creature back (Monster.push through the data "push")
##   ground  VERDANT BIND - a wreath of leaves opens under her; on the release a green seam races along the
##           ground to the aimed point and ROOTS erupt there in a cage (RootCage) round whatever stands inside,
##           holding a ground creature for a while (Monster.bind through the data "bind_s"). Judged when the
##           roots close: a creature that has moved on is not caught; flyers out of reach are not caught.
##   ward    LEAF WARD - a ring of leaves takes up orbit round her and takes the next blows (Ward "leaf")

const HELIX_R := 0.24
const HELIX_W := 11.0
const SEAM_SPEED := 15.0
const PATH_LEN := 26

var projectile: Node3D
var core: MeshInstance3D
var _axis_pos := Vector3.ZERO
var _proj_pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _perp := Vector3.RIGHT
var _upv := Vector3.UP
var _travelled := 0.0
var _helix_t := 0.0
var _path: Array = []                    # [axis, offset] from the head backwards
var _ribbons: Array[MeshInstance3D] = []
var _seam: MeshInstance3D
var _seam_mat: ShaderMaterial
var _seam_from := Vector3.ZERO
var _seam_to := Vector3.ZERO
var _seam_len := 1.0
var _seam_t := -1.0
var _seam_leaves: GPUParticles3D
var _erupted := false
var cage: RootCage


func _build() -> void:
	var pal := FX.palette(element)
	var k := 1.35 if signature else 1.0
	match style:
		"spiral":
			ground = FX.quad("res://shaders/magic/wind_arcs.gdshader", 3.4 * k, {"color": pal[0], "arcs": 3 + tier, "intensity": 0.0, "draw_progress": 0.0})
			add_child(ground)
			var lift := FX.particles(int(44 * k) + 10 * tier, 1.3, FX.pm_leaves("lift"), FX.leaf_mesh(0.08), false)
			lift.name = "Lift"
			lift.emitting = false
			add_child(lift)
			core = FX.quad("res://shaders/magic/wind_arcs.gdshader", 0.75 * k, {"color": pal[1], "arcs": 4, "intensity": 0.0, "draw_progress": 1.0, "spin": 4.5}, false)
			hand_fx.add_child(core)
			var orbit := FX.particles(26 + 8 * tier, 0.9, FX.pm_leaves("orbit"), FX.leaf_mesh(0.06), true)
			orbit.name = "Orbit"
			orbit.emitting = false
			hand_fx.add_child(orbit)
			var gather := FX.particles(60 + 20 * tier, 0.8, FX.pm_motes("wind", "gather"), FX.mote_mesh(0.04), true)
			gather.name = "Gather"
			gather.emitting = false
			hand_fx.add_child(gather)
		"ground":
			ground = FX.quad("res://shaders/magic/leaf_ring.gdshader", 2.4, {"color": pal[0], "vein_color": pal[1], "intensity": 0.0, "draw_progress": 0.0, "leaves": 10 + 2 * tier})
			add_child(ground)
			var gather2 := FX.particles(60 + 20 * tier, 0.8, FX.pm_motes("nature", "gather"), FX.mote_mesh(0.04), true)
			gather2.name = "Gather"
			gather2.emitting = false
			hand_fx.add_child(gather2)
			var sprout := FX.particles(18, 0.8, FX.pm_leaves("orbit"), FX.leaf_mesh(0.05), true)
			sprout.name = "Orbit"
			sprout.emitting = false
			hand_fx.add_child(sprout)
		"ward":
			var gather3 := FX.particles(40, 0.6, FX.pm_motes("wind", "gather"), FX.mote_mesh(0.035), true)
			gather3.name = "Gather"
			gather3.emitting = false
			hand_fx.add_child(gather3)


func _on_gather() -> void:
	super()
	if has_node("Lift"):
		(get_node("Lift") as GPUParticles3D).emitting = true


func _hand_point() -> Vector3:
	match style:
		"spiral", "ground":
			# a two-handed sweep: the spiral forms between her hands
			return (caster.left_hand.global_position + caster.right_hand.global_position) * 0.5
	return caster.right_hand.global_position


func _update(awaken: float, build: float, fade: float, hand: Vector3, fwd: Vector3, delta: float) -> void:
	var released := _fired.has("release")
	if ground:
		var gm: ShaderMaterial = ground.material_override
		gm.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, awaken))
		gm.set_shader_parameter("intensity", (1.0 + 0.6 * build) * awaken * fade * (0.8 + 0.2 * tier) * (1.8 if style == "spiral" else 1.3))
	if has_node("Lift"):
		var lift: GPUParticles3D = get_node("Lift")
		lift.global_position = caster.global_position + Vector3(0, 0.05, 0)
		if released and t > phase_time("release") + 0.3:
			lift.emitting = false
	if core and not released:
		core.global_position = hand + fwd * 0.22
		core.look_at(core.global_position + fwd, Vector3.UP if absf(fwd.y) < 0.95 else Vector3.FORWARD)
		core.scale = Vector3.ONE * maxf(0.02, smoothstep(0.0, 1.0, build))
		(core.material_override as ShaderMaterial).set_shader_parameter("intensity", 2.4 * build * fade)
	if style == "ground" and _seam_t >= 0.0 and not _erupted:
		_seam_t += delta
		var reach := clampf(_seam_t * SEAM_SPEED / _seam_len, 0.0, 1.0)
		_seam_mat.set_shader_parameter("reach", reach)
		if _seam_leaves:
			_seam_leaves.global_position = _seam_from.lerp(_seam_to, reach) + Vector3(0, 0.1, 0)
		if reach >= 1.0:
			_erupt()


func _release(hand: Vector3, dir: Vector3) -> void:
	_announce("release", hand)
	_stop_hand_particles()
	match style:
		"spiral":
			_launch(hand, dir)
		"ground":
			_seam_from = _ground(caster.global_position + Vector3(dir.x, 0, dir.z).normalized() * 0.4) + Vector3(0, 0.05, 0)
			_seam_to = _ground(aim) + Vector3(0, 0.05, 0)
			_seam_len = maxf(_seam_from.distance_to(_seam_to), 0.5)
			var q := QuadMesh.new()
			q.size = Vector2(_seam_len, 0.42)
			_seam = MeshInstance3D.new()
			_seam.mesh = q
			_seam_mat = ShaderMaterial.new()
			_seam_mat.shader = load("res://shaders/magic/root_seam.gdshader")
			_seam_mat.set_shader_parameter("color", FX.palette("nature")[0])
			_seam_mat.set_shader_parameter("tip_color", FX.palette("nature")[1])
			_seam_mat.set_shader_parameter("intensity", 1.6)
			_seam_mat.set_shader_parameter("reach", 0.0)
			_seam_mat.set_shader_parameter("wobble", 1.0)
			_seam.material_override = _seam_mat
			_seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			get_parent().add_child(_seam)
			var along := (_seam_to - _seam_from).normalized()
			var side := Vector3.UP.cross(along).normalized()
			# the quad's +X runs along the seam, its normal points up (flat on the ground)
			_seam.global_transform = Transform3D(Basis(along, side, Vector3.UP).orthonormalized(), (_seam_from + _seam_to) * 0.5)
			_seam_leaves = FX.particles(24, 0.9, FX.pm_leaves("sprout"), FX.leaf_mesh(0.05), false)
			_seam_leaves.emitting = true
			get_parent().add_child(_seam_leaves)
			_seam_leaves.global_position = _seam_from
			_seam_t = 0.0
			_sfx("roots_seam", _seam_from, -8.0)
		"ward":
			var w := Ward.new()
			get_parent().add_child(w)
			var charges := 2 + (1 if mastery >= 1.5 else 0)
			var seconds := float(def.get("ward_s", 4.0)) + 1.5 * minf(mastery, 3.0)
			w.setup(caster, "leaf", spell_id, charges, seconds, false)
			_resolve({"outcome": "self", "point": _v(caster.global_position), "ward": "leaf", "charges": charges, "seconds": snappedf(seconds, 0.1)})


# ------------------------------------------------------------------ the spiral in flight
func _launch(hand: Vector3, dir: Vector3) -> void:
	projectile = Node3D.new()
	get_parent().add_child(projectile)
	_axis_pos = hand + dir * 0.3
	_proj_pos = _axis_pos
	projectile.global_position = _proj_pos
	var speed := float(def.get("speed", 9.0)) * (1.0 + 0.08 * tier)
	_vel = dir * speed
	_perp = dir.cross(Vector3.UP)
	if _perp.length() < 0.05:
		_perp = Vector3.RIGHT
	_perp = _perp.normalized()
	_upv = _perp.cross(dir).normalized()
	_helix_t = 0.0
	_path.clear()
	if core:
		core.reparent(projectile, false)
		core.position = Vector3.ZERO
		core.scale = Vector3.ONE * (1.0 if not signature else 1.3)
		core.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD)
		(core.material_override as ShaderMaterial).set_shader_parameter("intensity", 2.8)
		(core.material_override as ShaderMaterial).set_shader_parameter("spin", 7.0)
	for rb in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/magic/spiral_ribbon.gdshader")
		var pal := FX.palette("wind")
		m.set_shader_parameter("color", pal[0] if rb == 0 else Color(0.95, 1.0, 0.85))
		m.set_shader_parameter("color2", pal[1] if rb == 0 else FX.palette("nature")[0])
		m.set_shader_parameter("intensity", 2.3 * (1.0 if not signature else 1.3))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(mi)
		_ribbons.append(mi)
	var leaves := FX.particles(30 + 10 * tier, 0.7, FX.pm_leaves("trail"), FX.leaf_mesh(0.06), false)
	leaves.name = "Leaves"
	leaves.emitting = true
	projectile.add_child(leaves)
	var trail := FX.particles(60 + 15 * tier, 0.4, FX.pm_motes("wind", "trail"), FX.mote_mesh(0.06), false)
	trail.name = "Trail"
	trail.emitting = true
	projectile.add_child(trail)
	projectile.add_child(FX.light(FX.palette("wind")[0], 1.1 * _light_scale, 3.5))
	_flying = true


func _fly(delta: float) -> void:
	_helix_t += delta
	_axis_pos += _vel * delta
	var ph := _helix_t * HELIX_W
	var r := HELIX_R * (1.0 + 0.3 * tier) * (1.4 if signature else 1.0)
	var offset := (_perp * cos(ph) + _upv * sin(ph)) * r
	var next := _axis_pos + offset
	var hit := MagicSystem.sweep(caster.get_world_3d(), _proj_pos, next, [caster.get_rid()])
	if not hit.is_empty():
		_land(hit.position, hit.collider)
		return
	if target and is_instance_valid(target):
		var tp := target.aim_point()
		var seg := next - _proj_pos
		var tt := clampf((tp - _proj_pos).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		var closest := _proj_pos + seg * tt
		if closest.distance_to(tp) <= target.aim_radius + 0.55 and tt < 1.0:
			_land(closest, null, true)
			return
		if target.kind == "water" and next.y <= tp.y + 0.02:
			_land(Vector3(next.x, tp.y, next.z), null, true)
			return
	_proj_pos = next
	_travelled += (_vel * delta).length()
	projectile.global_position = _proj_pos
	_path.push_front([_axis_pos, offset])
	if _path.size() > PATH_LEN:
		_path.resize(PATH_LEN)
	_draw_ribbons()
	if _travelled > float(def.get("range", 12.0)) + 3.0:
		_land(_proj_pos, null)


## Two ribbons braided round the axis the gust has really travelled: one through the head's own path, the
## other on the opposite side of the axis.
func _draw_ribbons() -> void:
	var n := _path.size()
	for rb in _ribbons.size():
		var im := _ribbons[rb].mesh as ImmediateMesh
		im.clear_surfaces()
		if n < 3:
			continue
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in n:
			var e: Array = _path[i]
			var off: Vector3 = e[1] * (1.0 if rb == 0 else -1.0)
			var p: Vector3 = e[0] + off
			var ahead: Vector3 = _path[maxi(i - 1, 0)][0]
			var behind: Vector3 = _path[mini(i + 1, n - 1)][0]
			var along := (ahead - behind).normalized()
			var side := along.cross(off.normalized()).normalized()
			var w := (0.07 if rb == 0 else 0.05) * pow(1.0 - float(i) / n, 0.7) + 0.01
			var u := float(i) / (n - 1)
			im.surface_set_uv(Vector2(u, 0.0))
			im.surface_add_vertex(p - side * w)
			im.surface_set_uv(Vector2(u, 1.0))
			im.surface_add_vertex(p + side * w)
		im.surface_end()


func _land(point: Vector3, collider: Object, on_target := false) -> void:
	_flying = false
	var outcome := "hit" if on_target else MagicSystem.judge(target, point, collider, 0.9)
	var res := {"outcome": outcome, "point": _v(point), "distance_from_target_m": snappedf(point.distance_to(target.aim_point()), 0.01) if target else -1.0}
	if collider is Node and outcome != "hit":
		res["blocked_by"] = String((collider as Node).name)
	_announce("impact" if outcome == "hit" else outcome, point)
	_impact_fx(point, outcome == "hit")
	_resolve(res)
	if projectile:
		for c in projectile.get_children():
			if c is GPUParticles3D:
				(c as GPUParticles3D).emitting = false
			elif c is OmniLight3D or c is MeshInstance3D:
				c.visible = false
		get_tree().create_timer(0.9).timeout.connect(projectile.queue_free)
	for rb in _ribbons:
		var m: ShaderMaterial = rb.material_override
		var tw := rb.create_tween()
		tw.tween_method(func(v: float): m.set_shader_parameter("intensity", v), 2.3, 0.0, 0.35)
		tw.tween_callback(rb.queue_free)
	_ribbons.clear()


func _impact_fx(point: Vector3, big: bool) -> void:
	var host := get_parent()
	FX.burst(host, point, 34 if big else 18, 1.1, FX.pm_leaves("burst"), FX.leaf_mesh(0.07))
	FX.burst(host, point, 40, 0.6, FX.pm_motes("wind", "burst"), FX.mote_mesh(0.04, true))
	FX.burst(host, point, 22 if big else 12, 1.3, FX.pm_puff("dust"), FX.puff_mesh(0.5))
	var g := _ground(point)
	if point.y - g.y < 1.8:
		ImpactFX.ground_ring(host, g + Vector3(0, 0.05, 0), FX.palette("wind")[0], 1.7 if big else 1.1)
	var flash := FX.light(FX.palette("wind")[0], (2.0 if big else 1.1) * _light_scale, 4.0)
	host.add_child(flash)
	flash.global_position = point + Vector3(0, 0.3, 0)
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)


# ------------------------------------------------------------------ the roots
func _travel_time(p: Vector3) -> float:
	return caster.global_position.distance_to(p) / SEAM_SPEED + 0.12


func _pending() -> bool:
	return style == "ground" and _fired.has("release") and not _erupted


func _erupt() -> void:
	_erupted = true
	var gy := _seam_to.y - 0.05
	var radius := 1.35 + 0.2 * tier
	var outcome := "missed"
	var point := Vector3(_seam_to.x, gy + 0.3, _seam_to.z)
	var dist := -1.0
	if target and is_instance_valid(target):
		var tp := target.aim_point()
		var flat := Vector2(tp.x - _seam_to.x, tp.z - _seam_to.z).length()
		dist = flat
		var reachable := tp.y - gy < 2.3            # roots reach a standing creature, not one high in the air
		if flat <= radius + target.aim_radius and reachable:
			outcome = "hit"
			point = Vector3(tp.x, gy + 0.3, tp.z)
	cage = RootCage.new()
	get_parent().add_child(cage)
	cage.global_position = Vector3(_seam_to.x, gy, _seam_to.z)
	cage.build(tier, signature, radius)
	cage.hold(float(def.get("bind_s", 3.5)) * (0.75 + 0.25 * minf(power, 1.0)) if outcome == "hit" else 1.1)
	_announce("impact" if outcome == "hit" else "missed", point)
	_sfx("roots_erupt", point, -3.0)
	FX.burst(get_parent(), point, 26, 1.2, FX.pm_leaves("burst"), FX.leaf_mesh(0.07))
	FX.burst(get_parent(), point - Vector3(0, 0.2, 0), 14, 1.4, FX.pm_puff("dust"), FX.puff_mesh(0.55))
	if _seam:
		var sm := _seam_mat
		var tw := _seam.create_tween()
		tw.tween_method(func(v: float): sm.set_shader_parameter("intensity", v), 1.6, 0.0, 0.7)
		tw.tween_callback(_seam.queue_free)
	if _seam_leaves:
		_seam_leaves.emitting = false
		get_tree().create_timer(1.2).timeout.connect(_seam_leaves.queue_free)
	_resolve({"outcome": outcome, "point": _v(point), "distance_from_target_m": snappedf(dist, 0.01), "radius": radius})


## The cage of roots: curved root tubes grown from the ground round the bound creature, swaying while they
## hold, withering (browning, sinking back) when the hold ends. Original geometry (bark material of the kit).
class RootCage extends Node3D:
	var roots: Array[MeshInstance3D] = []
	var tips: Array[MeshInstance3D] = []
	var heights: Array[float] = []
	var _grow := 0.0
	var _hold := 2.0
	var _phase := "grow"
	var _t := 0.0
	var _rng := RandomNumberGenerator.new()
	var mat: ShaderMaterial

	func build(tier: int, signature: bool, radius: float) -> void:
		_rng.seed = 1301 + tier
		mat = FoliageBuilder.bark_mat(false).duplicate()
		mat.set_shader_parameter("tint", Color(0.98, 0.9, 0.82))
		mat.set_shader_parameter("moss_amount", 0.75)
		var leaf_mat := FoliageBuilder.leaf_mat("plant", Vector3.ZERO, 0.0, 2.0, 0.05)
		var lst := SurfaceTool.new()
		lst.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 9 + tier + (2 if signature else 0)
		for i in n:
			var ang := TAU * i / n + _rng.randf_range(-0.2, 0.2)
			var r0 := radius * _rng.randf_range(0.8, 1.05)
			var h := _rng.randf_range(1.25, 1.75) * (1.15 if signature else 1.0)
			var twist := _rng.randf_range(-0.6, 0.6)
			var pts: Array[Vector3] = []
			var steps := 9
			for s in steps + 1:
				var k := float(s) / steps
				# out from the ground at the ring, rising and bending in over the centre, with a slight twist
				var rr := lerpf(r0, radius * 0.28, k * k)
				var a2 := ang + twist * k
				var y := h * sin(k * PI * 0.5) - 0.08
				pts.append(Vector3(cos(a2) * rr, y, sin(a2) * rr) + Vector3(_rng.randf_range(-0.03, 0.03), 0, _rng.randf_range(-0.03, 0.03)))
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_tube(st, pts, 0.075 * (1.2 if signature else 1.0), 0.022, 6)
			st.index()
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.scale = Vector3(1.0, 0.01, 1.0)
			add_child(mi)
			roots.append(mi)
			heights.append(h)
			# a few young leaves unfurling from the tip of each root
			var tip := pts[pts.size() - 1]
			var tdir := (pts[pts.size() - 1] - pts[pts.size() - 3]).normalized()
			for L in 3:
				var out := tdir.rotated(Vector3.UP, _rng.randf_range(-1.2, 1.2)).rotated(Vector3.RIGHT, _rng.randf_range(-0.5, 0.5))
				var right := out.cross(Vector3.UP).normalized() * _rng.randf_range(0.09, 0.13)
				var up := (out * 0.6 + Vector3.UP * 0.5).normalized() * _rng.randf_range(0.16, 0.24)
				FoliageBuilder._card(lst, tip - tdir * 0.05 * L, right, up, FoliageBuilder.SPR_HEART if L != 1 else FoliageBuilder.SPR_ROUND, (out + Vector3.UP).normalized())
			var lmi := MeshInstance3D.new()
			lst.index()
			lmi.mesh = lst.commit()
			lst = SurfaceTool.new()
			lst.begin(Mesh.PRIMITIVE_TRIANGLES)
			lmi.material_override = leaf_mat
			lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lmi.scale = Vector3(1.0, 0.01, 1.0)
			add_child(lmi)
			tips.append(lmi)
		var leaves := FX.particles(26, 1.3, FX.pm_leaves("sprout"), FX.leaf_mesh(0.07), false)
		leaves.one_shot = true
		leaves.explosiveness = 0.7
		leaves.emitting = true
		add_child(leaves)
		leaves.position.y = 0.2

	func hold(seconds: float) -> void:
		_hold = seconds

	func _process(delta: float) -> void:
		_t += delta
		match _phase:
			"grow":
				_grow = minf(_grow + delta / 0.38, 1.0)
				var k := 1.0 - pow(1.0 - _grow, 3.0)
				var over := 1.0 + 0.12 * sin(k * PI)
				for i in roots.size():
					roots[i].scale = Vector3(1.0, maxf(0.01, k * over), 1.0)
					tips[i].scale = Vector3(1.0, maxf(0.01, k * over), 1.0)
				if _grow >= 1.0:
					_phase = "hold"
			"hold":
				_hold -= delta
				for i in roots.size():
					roots[i].rotation.z = sin(_t * 2.1 + i) * 0.02
					roots[i].rotation.x = cos(_t * 1.7 + i * 0.7) * 0.02
					tips[i].rotation = roots[i].rotation
				if _hold <= 0.0:
					_phase = "wither"
					mat.set_shader_parameter("tint", Color(0.55, 0.42, 0.3))
					mat.set_shader_parameter("moss_amount", 0.0)
					var leaves := FX.particles(22, 1.6, FX.pm_leaves("burst"), FX.leaf_mesh(0.06), false)
					leaves.one_shot = true
					leaves.explosiveness = 0.8
					leaves.emitting = true
					add_child(leaves)
					leaves.position.y = 0.9
					if AudioDirector.instance:
						AudioDirector.instance.play3d("roots_wither", global_position, "SFX", -10.0, "roots")
			"wither":
				_grow = maxf(_grow - delta / 0.7, 0.0)
				for i in roots.size():
					roots[i].scale = Vector3(1.0, maxf(0.01, _grow * _grow), 1.0)
					tips[i].visible = false
				if _grow <= 0.0:
					queue_free()

	static func _tube(st: SurfaceTool, pts: Array[Vector3], r0: float, r1: float, sides: int) -> void:
		var prev: Array = []
		for i in pts.size():
			var p := pts[i]
			var dirv: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var side := dirv.cross(Vector3.UP)
			if side.length() < 0.01:
				side = Vector3.RIGHT
			side = side.normalized()
			var up := side.cross(dirv).normalized()
			var r := lerpf(r0, r1, float(i) / (pts.size() - 1))
			var ring := []
			for k in sides:
				var ang := TAU * k / sides
				ring.append(p + (side * cos(ang) + up * sin(ang)) * r)
			if not prev.is_empty():
				for k in sides:
					var a0: Vector3 = prev[k]
					var a1: Vector3 = prev[(k + 1) % sides]
					var b0: Vector3 = ring[k]
					var b1: Vector3 = ring[(k + 1) % sides]
					var cen := (a0 + a1 + b0 + b1) * 0.25
					var nrm := (cen - p).normalized()
					for v in [a0, b0, b1, a0, b1, a1]:
						st.set_normal(nrm)
						st.set_uv(Vector2(float(k) / sides, v.y * 0.6))
						st.add_vertex(v)
			prev = ring
