class_name SpellVFX
extends Node3D
## Combat v3 magic visuals: shaped, layered, out of the body. Every spell body is a real mesh (an ice shard - a long
## bipyramid crystal; a moon crescent - a lens swept along an arc; conjured blades, a scythe, a spear; a curved
## barrier) on the spell_core shader (bright facing core, soft grazing edges, flowing noise, burn-dissolve in / out),
## with converging motes while it gathers at her hand, a trail ribbon while it flies, sparks and a short light where it
## lands. Mika: ice white / blue. Luna: moon lilac / violet. Nothing is a flat quad or ring.

const PAL := CombatVFX.PAL

var vfx: CombatVFX                          # trails, sparks, lights (shared with the strikes)
var _sh: Shader
var _meshes := {}
var _mote_mesh: SphereMesh
var live: Array = []                        # movers / followers updated each frame
var stats := {"charges": 0, "projectiles": 0, "beams": 0, "spikes": 0, "waves": 0, "barriers": 0, "weapons": 0}


static func make(host: Node, combat_vfx: CombatVFX) -> SpellVFX:
	var s := SpellVFX.new()
	s.name = "SpellVFX"
	s.vfx = combat_vfx
	host.add_child(s)
	s._sh = load("res://shaders/anime/combat/v3/spell_core.gdshader")
	s._mote_mesh = SphereMesh.new()
	s._mote_mesh.radius = 0.008
	s._mote_mesh.height = 0.016
	s._mote_mesh.radial_segments = 6
	s._mote_mesh.rings = 3
	return s


func mat(who: String, energy := 2.6, dissolve := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _sh
	m.set_shader_parameter("core", PAL.get(who, PAL.mika).core)
	m.set_shader_parameter("edge", PAL.get(who, PAL.mika).edge)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("dissolve", dissolve)
	m.set_shader_parameter("noise", vfx.noise)
	return m


# ------------------------------------------------------------------------------------------------ meshes
## A crystal: two pyramids base to base (n sides), `length` along +Y with the widest ring at `waist` (0..1), UV.y 0..1.
func crystal(length: float, radius: float, sides := 6, waist := 0.35) -> ArrayMesh:
	var key := "c%.3f_%.3f_%d_%.2f" % [length, radius, sides, waist]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bot := Vector3.ZERO
	var top := Vector3(0, length, 0)
	var ring := []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		ring.append(Vector3(cos(a) * radius, length * waist, sin(a) * radius))
	for i in sides:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % sides]
		var u0 := float(i) / float(sides)
		var u1 := float(i + 1) / float(sides)
		for tri in [[bot, p1, p0, 0.0, waist, waist], [p0, p1, top, waist, waist, 1.0]]:
			var n := ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3)).normalized()
			st.set_normal(n)
			st.set_uv(Vector2(u0, tri[3]))
			st.add_vertex(tri[0])
			st.set_normal(n)
			st.set_uv(Vector2(u1, tri[4]))
			st.add_vertex(tri[1])
			st.set_normal(n)
			st.set_uv(Vector2((u0 + u1) * 0.5, tri[5]))
			st.add_vertex(tri[2])
	var m := st.commit()
	_meshes[key] = m
	return m


## A crescent: a lens profile swept along an arc of `span` deg, radius r, thickness th; the arc lies in the X-Y plane
## centred on +Y; UV.y runs along the arc (0..1), UV.x across. Thin at the horns, fat in the middle.
func crescent_mesh(r: float, th: float, span := 150.0, seg := 28) -> ArrayMesh:
	var key := "m%.3f_%.3f_%.0f" % [r, th, span]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof := 6
	var rows := []
	for i in seg + 1:
		var u := float(i) / float(seg)
		var a := deg_to_rad(90.0 - span * 0.5 + span * u)
		var c := Vector3(cos(a), sin(a), 0) * r
		var out := Vector3(cos(a), sin(a), 0)
		var w := th * sin(PI * u)                     # fat in the middle, needle horns
		var row := []
		for j in prof:
			var b := TAU * float(j) / float(prof)
			row.append(c + out * cos(b) * w * 1.6 + Vector3(0, 0, sin(b) * w * 0.45))
		rows.append(row)
	for i in seg:
		for j in prof:
			var a0: Vector3 = rows[i][j]
			var a1: Vector3 = rows[i][(j + 1) % prof]
			var b0: Vector3 = rows[i + 1][j]
			var b1: Vector3 = rows[i + 1][(j + 1) % prof]
			var u0 := float(i) / float(seg)
			var u1 := float(i + 1) / float(seg)
			var v0 := float(j) / float(prof)
			var v1 := float(j + 1) / float(prof)
			for tri in [[a0, b0, b1, Vector2(v0, u0), Vector2(v0, u1), Vector2(v1, u1)], [a0, b1, a1, Vector2(v0, u0), Vector2(v1, u1), Vector2(v1, u0)]]:
				var n := ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3)).normalized()
				for k in 3:
					st.set_normal(n)
					st.set_uv(tri[3 + k])
					st.add_vertex(tri[k])
	var m := st.commit()
	_meshes[key] = m
	return m


## A shaped body on the spell shader, in the world.
func body(mesh: Mesh, who: String, energy := 2.6, dissolve := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(who, energy, dissolve)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func shape_of(who: String) -> String:
	return "crescent" if who == "luna" else "shard"


func spell_mesh(who: String, size: float) -> Mesh:
	if shape_of(who) == "crescent":
		return crescent_mesh(0.22 * size, 0.05 * size, 160.0)
	return crystal(0.42 * size, 0.07 * size, 6, 0.3)


# ------------------------------------------------------------------------------------------------ gather at the hand
## Energy gathering at a hand bone for `dur` s: a small spinning shape that grows, motes converging from around her,
## a light growing. Follows the bone (src() -> world point) until released. Returns a handle (release / cancel).
func charge(src: Callable, who: String, dur: float, size := 1.0) -> Dictionary:
	stats.charges += 1
	var core := body(spell_mesh(who, 0.45 * size), who, 3.4, 1.0)
	var m: ShaderMaterial = core.material_override
	var motes := _gather_motes(who, size)
	var l := OmniLight3D.new()
	l.light_color = PAL.get(who, PAL.mika).edge.lightened(0.2)
	l.light_energy = 0.0
	l.omni_range = 1.6 * size
	l.shadow_enabled = false
	add_child(l)
	var h := {"kind": "charge", "core": core, "mat": m, "motes": motes, "light": l, "src": src, "t": 0.0, "dur": maxf(dur, 0.05), "size": size, "spin": 0.0}
	live.append(h)
	return h


func _gather_motes(who: String, size: float) -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = int(40 * size) + 10
	ps.lifetime = 0.45
	ps.local_coords = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 0.45 * size
	pm.gravity = Vector3.ZERO
	pm.radial_accel_min = -6.0 * size              # (pulled in toward the hand)
	pm.radial_accel_max = -9.0 * size
	pm.tangential_accel_min = 1.5
	pm.tangential_accel_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var g := Gradient.new()
	var p: Dictionary = PAL.get(who, PAL.mika)
	g.set_color(0, Color(p.edge.r, p.edge.g, p.edge.b, 0.0))
	g.add_point(0.3, Color(p.edge.r * 2.5, p.edge.g * 2.5, p.edge.b * 2.5, 0.9))
	g.set_color(g.get_point_count() - 1, Color(p.core.r * 3.0, p.core.g * 3.0, p.core.b * 3.0, 1.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	ps.process_material = pm
	ps.draw_pass_1 = _mote_mesh
	ps.material_override = vfx._spark_material(who)
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)
	ps.emitting = true
	return ps


## The charge leaves the hand: its shape is handed back (to become the projectile / beam head), motes and light go.
func release(h: Dictionary) -> MeshInstance3D:
	h.done = true
	if is_instance_valid(h.motes):
		(h.motes as GPUParticles3D).emitting = false
		get_tree().create_timer(0.5, true, false, false).timeout.connect((h.motes as Node).queue_free)
	if is_instance_valid(h.light):
		var l: OmniLight3D = h.light
		var tw := l.create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.15)
		tw.tween_callback(l.queue_free)
	return h.core


func cancel(h: Dictionary) -> void:
	var core: MeshInstance3D = release(h)
	if is_instance_valid(core):
		_vanish(core, 0.15)


# ------------------------------------------------------------------------------------------------ flight
## A shaped spell flying from `from` to the live point to() over `dur` s (a slight arc), nose first, a trail ribbon
## behind it; on_arrive(pos) when it gets there. `core` may be the charge's shape (it keeps growing into the bolt).
func projectile(core: MeshInstance3D, from: Vector3, to: Callable, who: String, dur: float, size := 1.0, arc := 0.15, on_arrive := Callable()) -> Dictionary:
	stats.projectiles += 1
	if not is_instance_valid(core):
		core = body(spell_mesh(who, size), who, 3.0)
	(core.material_override as ShaderMaterial).set_shader_parameter("dissolve", 0.0)
	core.mesh = spell_mesh(who, size)
	var h := {"kind": "bolt", "core": core, "from": from, "to": to, "t": 0.0, "dur": maxf(dur, 0.05), "arc": arc, "who": who, "size": size,
		"on_arrive": on_arrive, "pos": from}
	var hs := h
	h.trail = vfx.trail(func() -> Array:
		var p: Vector3 = hs.pos
		var dv: Vector3 = hs.get("dir", Vector3.FORWARD)
		return [p - dv * 0.5 * size, p], who, dur + 0.05, 2.6, 0.25)
	live.append(h)
	return h


func _bolt_pos(h: Dictionary, u: float) -> Vector3:
	var a: Vector3 = h.from
	var b: Vector3 = (h.to as Callable).call()
	var mid := (a + b) * 0.5 + Vector3.UP * float(h.arc) * a.distance_to(b)
	return a.lerp(mid, u).lerp(mid.lerp(b, u), u)


# ------------------------------------------------------------------------------------------------ beam
## A beam from the hands (a() -> start) to b() for `dur` s: a bright inner core and a soft sheath, both flowing, with
## shards / crescents riding it; fades in fast, out over 0.2 s.
func beam(a: Callable, b: Callable, who: String, dur: float, width := 1.0) -> Dictionary:
	stats.beams += 1
	var inner := CylinderMesh.new()
	inner.top_radius = 0.045 * width
	inner.bottom_radius = 0.045 * width
	inner.height = 1.0
	inner.radial_segments = 12
	inner.cap_top = false
	inner.cap_bottom = false
	var outer := CylinderMesh.new()
	outer.top_radius = 0.16 * width
	outer.bottom_radius = 0.11 * width
	outer.height = 1.0
	outer.radial_segments = 16
	outer.cap_top = false
	outer.cap_bottom = false
	var mi := body(inner, who, 4.0)
	var mo := body(outer, who, 1.4)
	(mo.material_override as ShaderMaterial).set_shader_parameter("flow", 3.5)
	var l := OmniLight3D.new()
	l.light_color = PAL.get(who, PAL.mika).edge.lightened(0.25)
	l.light_energy = 1.4
	l.omni_range = 2.5
	l.shadow_enabled = false
	add_child(l)
	var h := {"kind": "beam", "a": a, "b": b, "in": mi, "out": mo, "light": l, "t": 0.0, "dur": dur, "w": width}
	live.append(h)
	return h


# ------------------------------------------------------------------------------------------------ ground
## A line of shards (Mika: ice) / thorns (Luna: moon crescents on end) erupting one after another from `from` toward
## `to`, each rising fast, holding, dissolving. on_reach(pos) as the last one rises.
func spikes(from: Vector3, to: Vector3, who: String, n := 7, height := 0.9, on_reach := Callable()) -> void:
	stats.spikes += 1
	var dir := Vector3(to.x - from.x, 0, to.z - from.z)
	var len_ := dir.length()
	dir = dir.normalized()
	for i in n:
		var u := float(i + 1) / float(n)
		var at := from + dir * len_ * u
		var t0 := 0.05 * i
		var hgt := height * lerpf(0.6, 1.15, u) * randf_range(0.85, 1.15)
		get_tree().create_timer(t0, true, false, false).timeout.connect(func():
			for k in 3:
				var mesh := crystal(hgt * (1.0 if k == 0 else 0.6), 0.09 * (1.0 if k == 0 else 0.6), 5, 0.25) if who != "luna" else crescent_mesh(hgt * 0.45 * (1.0 if k == 0 else 0.7), 0.06, 120.0)
				var mi := body(mesh, who, 2.4, 1.0)
				var tilt := Basis(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized(), randf_range(0.1, 0.35) * (1.0 if k == 0 else 1.6))
				mi.global_transform = Transform3D(tilt, at + Vector3(randf_range(-0.12, 0.12), -0.05, randf_range(-0.12, 0.12)) * (0.0 if k == 0 else 1.0))
				var m: ShaderMaterial = mi.material_override
				var tw := mi.create_tween()
				tw.tween_method(func(v: float): m.set_shader_parameter("dissolve", v), 1.0, 0.0, 0.09)
				tw.tween_interval(0.35)
				tw.tween_method(func(v: float): m.set_shader_parameter("dissolve", v), 0.0, 1.0, 0.4)
				tw.tween_callback(mi.queue_free)
			vfx.dust(at, dir, 6, 0.8)
			if i == n - 1 and on_reach.is_valid():
				on_reach.call(at))


## A crescent wave skimming the ground from `from` toward `to` (her arm's sweep thrown out), on_arrive(pos).
func wave(from: Vector3, to: Callable, who: String, dur: float, size := 1.0, on_arrive := Callable()) -> void:
	stats.waves += 1
	var mi := body(crescent_mesh(0.55 * size, 0.07 * size, 150.0), who, 2.8)
	var h := {"kind": "wave", "core": mi, "from": from, "to": to, "t": 0.0, "dur": dur, "on_arrive": on_arrive, "who": who, "size": size}
	live.append(h)


# ------------------------------------------------------------------------------------------------ barrier
## A curved faceted barrier in front of her (toward() -> the threat), conjured in from the hands, cracks flash where it
## is struck, dissolves away. Returns a handle (hit / off).
func barrier(center: Callable, toward: Callable, who: String, radius := 0.85) -> Dictionary:
	stats.barriers += 1
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	sm.is_hemisphere = true
	var mi := body(sm, who, 1.3, 1.0)
	(mi.material_override as ShaderMaterial).set_shader_parameter("along_bias", 0.0)
	var h := {"kind": "barrier", "core": mi, "center": center, "toward": toward, "t": 0.0, "on": true}
	var m: ShaderMaterial = mi.material_override
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("dissolve", v), 1.0, 0.0, 0.12)
	live.append(h)
	return h


func barrier_hit(h: Dictionary, at: Vector3, who: String) -> void:
	var m: ShaderMaterial = (h.core as MeshInstance3D).material_override
	var tw := (h.core as Node).create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("energy", v), 4.5, 1.3, 0.25)
	vfx.impact(at, ((h.toward as Callable).call() - at).normalized() * -1.0, who, 0.6, "block")


func barrier_off(h: Dictionary) -> void:
	h.on = false
	_vanish(h.core, 0.25)


# ------------------------------------------------------------------------------------------------ conjured weapons
## A spell weapon drawn from light in her hand (src_xf() -> the hand bone's world transform): ice blade / star spear
## (Mika), violet scythe / moon whip (Luna). It is drawn in along its length from the grip, rides the hand, and
## dissolves when `vanish` is called. Returns a handle with "tip" (world point of its striking end) for trails and hits.
func weapon(kind: String, src_xf: Callable, who: String) -> Dictionary:
	stats.weapons += 1
	var root := Node3D.new()
	add_child(root)
	var parts := []
	var tip := Vector3(0, 0.9, 0)
	match kind:
		"ice_blade":
			var blade := crystal(0.85, 0.035, 4, 0.08)
			parts.append([blade, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.35)), Vector3(0, 0.06, 0))])
			parts.append([crystal(0.1, 0.06, 4, 0.5), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.05, 0.05, 0))])
			tip = Vector3(0, 0.9, 0)
		"star_spear":
			parts.append([crystal(1.5, 0.018, 6, 0.5), Transform3D(Basis(), Vector3(0, -0.55, 0))])
			parts.append([crystal(0.32, 0.06, 4, 0.25), Transform3D(Basis(), Vector3(0, 0.95, 0))])
			tip = Vector3(0, 1.27, 0)
		"violet_scythe":
			parts.append([crystal(1.3, 0.018, 6, 0.5), Transform3D(Basis(), Vector3(0, -0.45, 0))])
			parts.append([crescent_mesh(0.42, 0.07, 150.0), Transform3D(Basis(Vector3.FORWARD, -PI * 0.55), Vector3(0.15, 0.82, 0))])
			tip = Vector3(0.55, 0.95, 0)
		"moon_whip":
			for i in 7:
				parts.append([crescent_mesh(0.07, 0.02, 120.0), Transform3D(Basis(Vector3.UP, i * 0.9), Vector3(0, 0.12 + i * 0.16, 0))])
			tip = Vector3(0, 1.25, 0)
	var mats := []
	for p in parts:
		var mi := body(p[0], who, 3.0, 1.0)
		remove_child(mi)
		root.add_child(mi)
		mi.transform = p[1]
		mats.append(mi.material_override)
	var h := {"kind": "weapon", "root": root, "mats": mats, "src": src_xf, "tip_local": tip, "on": true, "who": who, "name": kind}
	for m in mats:
		var tw := root.create_tween()
		tw.tween_method(func(v: float): (m as ShaderMaterial).set_shader_parameter("dissolve", v), 1.0, 0.0, 0.22)
	live.append(h)
	return h


func weapon_tip(h: Dictionary) -> Vector3:
	if not is_instance_valid(h.root):
		return h.get("last_tip", Vector3.ZERO)
	var r: Node3D = h.root
	h.last_tip = r.global_transform * (h.tip_local as Vector3)
	return h.last_tip


func weapon_vanish(h: Dictionary) -> void:
	h.on = false
	for m in h.mats:
		var tw := (h.root as Node).create_tween()
		tw.tween_method(func(v: float): (m as ShaderMaterial).set_shader_parameter("dissolve", v), 0.0, 1.0, 0.35)
	get_tree().create_timer(0.4, true, false, false).timeout.connect((h.root as Node).queue_free)


# ------------------------------------------------------------------------------------------------ helpers
## A spell landing: sparks and glints from its own shape, a burst, a light, and the shape shatters (dissolves fast).
func burst_at(at: Vector3, dir: Vector3, who: String, power := 0.8) -> void:
	vfx.impact(at, dir, who, power, "hit")
	vfx.dust(at - Vector3(0, at.y - at.y, 0), dir, 6, 0.6)


func _vanish(mi: MeshInstance3D, dur: float) -> void:
	if not is_instance_valid(mi):
		return
	var m: ShaderMaterial = mi.material_override
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("dissolve", v), 0.0, 1.0, dur)
	tw.tween_callback(mi.queue_free)


func _orient(mi: MeshInstance3D, at: Vector3, dir: Vector3) -> void:
	var y := dir.normalized()
	if y.length() < 0.01:
		y = Vector3.UP
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x, y, z), at)


func _process(delta: float) -> void:
	var keep := []
	for h in live:
		match String(h.kind):
			"charge":
				if h.get("done", false):
					continue
				var core: MeshInstance3D = h.core
				if not is_instance_valid(core):
					continue
				h.t = float(h.t) + delta
				var u := clampf(float(h.t) / float(h.dur), 0.0, 1.0)
				var p: Vector3 = (h.src as Callable).call()
				h.spin = float(h.spin) + delta * lerpf(4.0, 14.0, u)
				core.global_transform = Transform3D(Basis(Vector3.UP, float(h.spin)) * Basis(Vector3.RIGHT, 0.4).scaled(Vector3.ONE * lerpf(0.25, 1.0, u)), p)
				(h.mat as ShaderMaterial).set_shader_parameter("dissolve", 1.0 - smoothstep(0.0, 0.45, u))
				if is_instance_valid(h.motes):
					(h.motes as Node3D).global_position = p
				if is_instance_valid(h.light):
					(h.light as OmniLight3D).global_position = p
					(h.light as OmniLight3D).light_energy = lerpf(0.0, 0.4, u) * float(h.size)
				keep.append(h)
			"bolt":
				var core2: MeshInstance3D = h.core
				h.t = float(h.t) + delta
				var u2 := clampf(float(h.t) / float(h.dur), 0.0, 1.0)
				var p2 := _bolt_pos(h, u2)
				var dv := (p2 - (h.pos as Vector3))
				if dv.length() > 0.0001:
					h.dir = dv.normalized()
				h.pos = p2
				if is_instance_valid(core2):
					_orient(core2, p2, h.get("dir", Vector3.FORWARD))
					if String(h.who) == "luna":
						core2.global_transform = core2.global_transform.rotated_local(Vector3.RIGHT, PI * 0.5)
				if u2 >= 1.0:
					if (h.on_arrive as Callable).is_valid():
						(h.on_arrive as Callable).call(p2)
					_vanish(core2, 0.08)
					continue
				keep.append(h)
			"beam":
				h.t = float(h.t) + delta
				var a: Vector3 = (h.a as Callable).call()
				var b: Vector3 = (h.b as Callable).call()
				var len_ := maxf(a.distance_to(b), 0.05)
				var fade := 1.0 - smoothstep(float(h.dur) - 0.2, float(h.dur), float(h.t))
				var grow := smoothstep(0.0, 0.08, float(h.t))
				for key in ["in", "out"]:
					var mi: MeshInstance3D = h[key]
					if not is_instance_valid(mi):
						continue
					_orient(mi, (a + b) * 0.5, b - a)
					mi.scale = Vector3(grow * fade, len_, grow * fade)
				if is_instance_valid(h.light):
					(h.light as OmniLight3D).global_position = a.lerp(b, 0.3)
					(h.light as OmniLight3D).light_energy = 1.4 * fade
				if float(h.t) >= float(h.dur):
					for key in ["in", "out", "light"]:
						if is_instance_valid(h[key]):
							(h[key] as Node).queue_free()
					continue
				keep.append(h)
			"streak":
				var hd: Node3D = h.head
				h.t = float(h.t) + delta
				var u5 := clampf(float(h.t) / float(h.dur), 0.0, 1.0)
				var a5: Vector3 = h.from
				var b5: Vector3 = (h.to as Callable).call()
				var p5 := a5.lerp(b5, u5)
				var dv5 := p5 - (h.pos as Vector3)
				if dv5.length() > 0.0001:
					h.dir = dv5.normalized()
				h.pos = p5
				if is_instance_valid(hd):
					hd.global_position = p5
					var cam := get_viewport().get_camera_3d()
					if cam:
						hd.look_at(cam.global_position, Vector3.UP)
						hd.rotate_object_local(Vector3.FORWARD, float(h.t) * 6.0)
				if u5 >= 1.0:
					if (h.on_arrive as Callable).is_valid():
						(h.on_arrive as Callable).call(p5)
					if is_instance_valid(hd):
						hd.queue_free()
					continue
				keep.append(h)
			"wave":
				var mi2: MeshInstance3D = h.core
				h.t = float(h.t) + delta
				var u3 := clampf(float(h.t) / float(h.dur), 0.0, 1.0)
				var a3: Vector3 = h.from
				var b3: Vector3 = (h.to as Callable).call()
				var p3 := a3.lerp(b3, u3)
				var d3 := Vector3(b3.x - a3.x, 0, b3.z - a3.z).normalized()
				if is_instance_valid(mi2):
					var x := d3.cross(Vector3.UP).normalized()
					mi2.global_transform = Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)).rotated(x, -PI * 0.5).scaled(Vector3.ONE * lerpf(0.7, 1.3, u3)), p3 + Vector3.UP * 0.35)
				if u3 >= 1.0:
					if (h.on_arrive as Callable).is_valid():
						(h.on_arrive as Callable).call(p3)
					_vanish(mi2, 0.12)
					continue
				keep.append(h)
			"barrier":
				if not h.on or not is_instance_valid(h.core):
					continue
				var c: Vector3 = (h.center as Callable).call()
				var tow: Vector3 = (h.toward as Callable).call()
				_orient(h.core, c, tow - c)
				keep.append(h)
			"weapon":
				if not h.on or not is_instance_valid(h.root):
					continue
				(h.root as Node3D).global_transform = (h.src as Callable).call()
				keep.append(h)
	live = keep


# ================================================================================================ the reference look
# (Selwyn 2026-10-20: "copy the magic and how it moves in the reference videos" - Download(5) / (6) / (7): huge swept
# crescent slashes with a white-hot leading edge and a glassy smear, eruptions of crystals bursting outward in a ring,
# swirling white wind domes, comet streaks with star flares, dark tendrils out of a glowing pool, rotating light frames)

var _smear_sh: Shader


## A ring sector mesh (arc of `sweep` deg in the X-Z plane from +X toward +Z, inner radius ri, outer ro): UV.x along the
## arc 0..1, UV.y inner 0 .. outer 1.
func sector(ri: float, ro: float, sweep: float, seg := 48) -> ArrayMesh:
	var key := "s%.2f_%.2f_%.0f" % [ri, ro, sweep]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var u0 := float(i) / float(seg)
		var u1 := float(i + 1) / float(seg)
		var a0 := deg_to_rad(sweep * u0)
		var a1 := deg_to_rad(sweep * u1)
		var p := [Vector3(cos(a0), 0, sin(a0)) * ri, Vector3(cos(a0), 0, sin(a0)) * ro, Vector3(cos(a1), 0, sin(a1)) * ro, Vector3(cos(a1), 0, sin(a1)) * ri]
		var uv := [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_normal(Vector3.UP)
				st.set_uv(uv[k])
				st.add_vertex(p[k])
	var m := st.commit()
	_meshes[key] = m
	return m


func smear_mat(who: String, energy := 3.0) -> ShaderMaterial:
	if _smear_sh == null:
		_smear_sh = load("res://shaders/anime/combat/v3/slash_smear.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _smear_sh
	m.set_shader_parameter("core", PAL.get(who, PAL.mika).core)
	m.set_shader_parameter("edge", PAL.get(who, PAL.mika).edge)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("noise", vfx.noise)
	return m


## A crescent slash swept around `center`: the arc lies in the plane with normal `nrm`, starting toward `start`,
## radius r (width w), sweeping `sweep` deg in `dur` s; the smear follows the leading edge and fades. `travel`
## moves the whole arc along that vector over its life (a flying slash). Returns the node.
func slash_arc(center: Vector3, nrm: Vector3, start: Vector3, r: float, w: float, sweep: float, dur: float, who: String,
		energy := 3.0, travel := Vector3.ZERO, tail := 0.55) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = sector(maxf(r - w, 0.02), r, sweep)
	var m := smear_mat(who, energy)
	m.set_shader_parameter("tail", tail)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var y := nrm.normalized()
	var x := (start - y * start.dot(y)).normalized()
	if x.length() < 0.01:
		x = y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	# the sector sweeps from +X toward +Z; flip so it turns the way asked (x -> start, sweep about nrm)
	mi.global_transform = Transform3D(Basis(x, y, -z), center)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("head", v), 0.0, 1.0 + tail, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur * 0.45).set_delay(dur * 0.7)
	if travel != Vector3.ZERO:
		tw.parallel().tween_property(mi, "global_position", center + travel, dur * 1.15)
	tw.tween_callback(mi.queue_free)
	return mi


## A comet streak: a thin line of light flying from -> to in `dur` s with a star-flare head (crossed glint needles and a
## light) and a long fading tail; on_arrive(pos).
func streak(from: Vector3, to: Callable, who: String, dur: float, width := 1.0, on_arrive := Callable()) -> Dictionary:
	stats.projectiles += 1
	var head := Node3D.new()
	add_child(head)
	for k in 4:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.012 * width
		cm.height = (0.34 if k < 2 else 0.18) * width
		cm.radial_segments = 4
		cm.rings = 0
		for sgn in [1.0, -1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = cm
			var gm := ShaderMaterial.new()
			gm.shader = vfx._glint_sh
			gm.set_shader_parameter("col", PAL.get(who, PAL.mika).core)
			gm.set_shader_parameter("energy", 5.0)
			mi.material_override = gm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			head.add_child(mi)
			var ang := PI * 0.25 * k + (0.0 if sgn > 0 else PI)
			mi.transform = Transform3D(Basis(Vector3.FORWARD, ang), Vector3(-sin(ang), cos(ang), 0) * cm.height * 0.5)
	var l := OmniLight3D.new()
	l.light_color = PAL.get(who, PAL.mika).core
	l.light_energy = 1.6
	l.omni_range = 2.2
	l.shadow_enabled = false
	head.add_child(l)
	var h := {"kind": "streak", "head": head, "from": from, "to": to, "t": 0.0, "dur": maxf(dur, 0.04), "pos": from, "on_arrive": on_arrive, "who": who}
	var hs := h
	h.trail = vfx.trail(func() -> Array:
		var p: Vector3 = hs.pos
		var dv: Vector3 = hs.get("dir", Vector3.FORWARD)
		var up := dv.cross(Vector3.UP).normalized() * 0.03 * width
		return [p - up, p + up], who, dur + 0.02, 4.0, 1.0)
	h.trail.hist_max = 14
	live.append(h)
	return h


## Crystals bursting out of the ground in a ring around `center`, leaning outward (ice: Mika; moon shards: Luna),
## with a white mist flash; they hold and dissolve.
func crystal_burst(center: Vector3, who: String, radius := 1.2, n := 14, height := 1.0) -> void:
	stats.spikes += 1
	for i in n:
		var a := TAU * (float(i) + randf_range(-0.3, 0.3)) / float(n)
		var rr := radius * randf_range(0.35, 1.0)
		var at := center + Vector3(cos(a), 0, sin(a)) * rr
		var hgt := height * randf_range(0.5, 1.25) * (1.15 - rr / radius * 0.5)
		var out := Vector3(cos(a), 0, sin(a))
		var mesh := crystal(hgt, 0.07 * hgt + 0.03, 5, 0.22) if who != "luna" else crescent_mesh(hgt * 0.45, 0.06, 120.0)
		var mi := body(mesh, who, 2.8, 1.0)
		var lean := Basis(out.cross(Vector3.UP).normalized(), -randf_range(0.35, 0.8))
		mi.global_transform = Transform3D(lean.rotated(Vector3.UP, randf() * TAU) if who == "luna" else lean, at + Vector3(0, -0.08, 0))
		var m: ShaderMaterial = mi.material_override
		var t0 := randf_range(0.0, 0.07)
		var tw := mi.create_tween()
		tw.tween_interval(t0)
		tw.tween_method(func(v: float): m.set_shader_parameter("dissolve", v), 1.0, 0.0, 0.07)
		tw.tween_interval(0.45)
		tw.tween_method(func(v: float): m.set_shader_parameter("dissolve", v), 0.0, 1.0, 0.5)
		tw.tween_callback(mi.queue_free)
	swirl(center + Vector3(0, 0.6, 0), who, radius * 0.9, 0.45, 5)
	vfx.dust(center, Vector3.UP, 16, 1.2)
	vfx._light(center + Vector3(0, 0.8, 0), PAL.get(who, PAL.mika).core, 2.2, 0.35)


## A dome of swirling white wind: several crescent smears at random tilts around a point, sweeping fast.
func swirl(center: Vector3, who: String, radius := 1.2, dur := 0.45, n := 5) -> void:
	for i in n:
		var nrm := Vector3(randf_range(-1, 1), randf_range(0.4, 1.2), randf_range(-1, 1)).normalized()
		var st := nrm.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
		slash_arc(center, nrm, st, radius * randf_range(0.75, 1.1), radius * 0.35, randf_range(160.0, 260.0), dur * randf_range(0.8, 1.2), who, 2.2, Vector3.ZERO, 0.8)


## A ring of light sweeping round on the ground (a frost / moon glyph being cut into the floor).
func ground_ring(center: Vector3, who: String, radius := 1.6, dur := 0.4) -> void:
	slash_arc(center + Vector3(0, 0.04, 0), Vector3.UP, Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), radius, radius * 0.18, 330.0, dur, who, 3.2, Vector3.ZERO, 0.9)


## Dark-violet tendrils (claws) bursting out of a glowing pool at `at` and curling up / toward `toward`.
func tendrils(at: Vector3, toward: Vector3, who: String, n := 5, height := 1.6) -> void:
	stats.spikes += 1
	var fwd := Vector3(toward.x - at.x, 0, toward.z - at.z).normalized()
	for i in n:
		var a := randf_range(-1.2, 1.2)
		var base := at + fwd.rotated(Vector3.UP, a + PI * 0.5) * randf_range(0.1, 0.6)
		var tip := at + Vector3.UP * height * randf_range(0.7, 1.2) + fwd.rotated(Vector3.UP, a) * randf_range(0.3, 0.9)
		var ctrl := (base + tip) * 0.5 + Vector3.UP * height * 0.4 - fwd * 0.3
		var mi := MeshInstance3D.new()
		mi.mesh = _tube(base, ctrl, tip, 0.09 * randf_range(0.7, 1.2), 18)
		var m := mat(who, 1.6, 1.0)
		m.set_shader_parameter("core", Color(0.75, 0.5, 1.0))
		m.set_shader_parameter("edge", Color(0.25, 0.05, 0.5))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_transform = Transform3D.IDENTITY
		var tw := mi.create_tween()
		tw.tween_interval(0.04 * i)
		tw.tween_method(func(v: float): m.set_shader_parameter("dissolve", v), 1.0, 0.0, 0.12)
		tw.tween_interval(0.5)
		tw.tween_method(func(v: float): m.set_shader_parameter("dissolve", v), 0.0, 1.0, 0.45)
		tw.tween_callback(mi.queue_free)
	ground_ring(at, who, 0.9, 0.35)
	vfx._light(at + Vector3(0, 0.4, 0), Color(0.6, 0.3, 1.0), 2.0, 0.6)


## A tapered tube along a quadratic curve a -> c -> b (thick at a, needle at b); UV.y along it.
func _tube(a: Vector3, c: Vector3, b: Vector3, r0: float, seg := 16) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var rings := []
	for i in seg + 1:
		var u := float(i) / float(seg)
		var p := a.lerp(c, u).lerp(c.lerp(b, u), u)
		var p2 := a.lerp(c, minf(u + 0.01, 1.0)).lerp(c.lerp(b, minf(u + 0.01, 1.0)), minf(u + 0.01, 1.0))
		var t := (p2 - p).normalized() if u < 1.0 else (b - c).normalized()
		var x := t.cross(Vector3.UP if absf(t.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
		var y := t.cross(x).normalized()
		var r := r0 * pow(1.0 - u, 0.8)
		var ring := []
		for j in sides:
			var ang := TAU * float(j) / float(sides)
			ring.append(p + (x * cos(ang) + y * sin(ang)) * r)
		rings.append(ring)
	for i in seg:
		for j in sides:
			var q := [rings[i][j], rings[i][(j + 1) % sides], rings[i + 1][(j + 1) % sides], rings[i + 1][j]]
			var uv := [Vector2(float(j) / sides, float(i) / seg), Vector2(float(j + 1) / sides, float(i) / seg),
				Vector2(float(j + 1) / sides, float(i + 1) / seg), Vector2(float(j) / sides, float(i + 1) / seg)]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var n := ((q[tri[1]] as Vector3) - (q[tri[0]] as Vector3)).cross((q[tri[2]] as Vector3) - (q[tri[0]] as Vector3)).normalized()
				for k in tri:
					st.set_normal(n)
					st.set_uv(uv[k])
					st.add_vertex(q[k])
	return st.commit()


## Rotating geometric light frames (rhombus outlines) closing on `center` (Download(7) 11.5-12.5 s): Luna's moon seal.
func frames(center: Vector3, who: String, n := 3, size := 1.1, dur := 0.6) -> void:
	for i in n:
		var root := Node3D.new()
		add_child(root)
		root.global_position = center
		var s := size * (1.0 + 0.35 * i)
		var corners := [Vector3(0, s, 0), Vector3(s * 0.7, 0, 0), Vector3(0, -s, 0), Vector3(-s * 0.7, 0, 0)]
		for k in 4:
			var a: Vector3 = corners[k]
			var b: Vector3 = corners[(k + 1) % 4]
			var cm := CylinderMesh.new()
			cm.top_radius = 0.018
			cm.bottom_radius = 0.018
			cm.height = a.distance_to(b)
			cm.radial_segments = 6
			cm.rings = 0
			var mi := MeshInstance3D.new()
			mi.mesh = cm
			mi.material_override = mat(who, 4.0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			var y := (b - a).normalized()
			var x := y.cross(Vector3.FORWARD).normalized()
			mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
		root.basis = Basis(Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)).normalized(), randf() * TAU)
		root.scale = Vector3.ONE * 1.8
		var tw := root.create_tween()
		tw.tween_property(root, "scale", Vector3.ONE * 0.6, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN).set_delay(0.05 * i)
		tw.parallel().tween_property(root, "rotation", root.rotation + Vector3(0, PI * (1.0 if i % 2 == 0 else -1.0), 0), dur)
		tw.tween_callback(root.queue_free)
	vfx._light(center, PAL.get(who, PAL.mika).core, 1.8, dur)


## The fight look: glow switched on with a high threshold for the length of a fight - only magic blooms, faces and
## cloth keep their detail (the reference: bloom on effects only); restored after.
static func fight_glow(main: Node, on: bool) -> void:
	var we: WorldEnvironment = null
	for n in main.get_tree().root.find_children("*", "WorldEnvironment", true, false):
		we = n
		break
	if we == null or we.environment == null:
		return
	var e := we.environment
	if on:
		if not e.has_meta("fight_glow_saved"):
			e.set_meta("fight_glow_saved", [e.glow_enabled, e.glow_intensity, e.glow_hdr_threshold, e.glow_bloom, e.glow_strength,
				e.glow_blend_mode, e.glow_normalized, e.adjustment_enabled, e.adjustment_brightness, e.adjustment_saturation, e.adjustment_contrast])
		# magic blooms hard (additive, not normalized), only above the threshold - cloth and faces keep their detail
		e.glow_enabled = true
		e.glow_normalized = false
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		e.glow_intensity = 0.8
		e.glow_strength = 1.15
		e.glow_bloom = 0.0
		e.glow_hdr_threshold = 1.7
		for i in 7:
			e.set_glow_level(i, [0.0, 0.5, 1.0, 1.0, 0.9, 0.6, 0.3][i])
		# the fight grade (the reference: the world dimmed and greyed while they fight, so their magic is what glows)
		e.adjustment_enabled = true
		e.adjustment_brightness = 0.82
		e.adjustment_saturation = 0.72
		e.adjustment_contrast = 1.08
	elif e.has_meta("fight_glow_saved"):
		var sv: Array = e.get_meta("fight_glow_saved")
		e.glow_enabled = sv[0]
		e.glow_intensity = sv[1]
		e.glow_hdr_threshold = sv[2]
		e.glow_bloom = sv[3]
		e.glow_strength = sv[4]
		e.glow_blend_mode = sv[5]
		e.glow_normalized = sv[6]
		e.adjustment_enabled = sv[7]
		e.adjustment_brightness = sv[8]
		e.adjustment_saturation = sv[9]
		e.adjustment_contrast = sv[10]
		e.remove_meta("fight_glow_saved")
