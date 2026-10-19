class_name FightFX
extends Node3D
## The duel's magic (2026-10-19): Mika's ice-blue star magic, Luna's violet moon magic, built to the reference rules
## (~/Downloads/Anime_Reference_Breakdown.md): every bright thing has three layers (white-hot core, coloured glow,
## faint haze - shaders/anime/duel/fight_glow), clean shapes rather than particle soup (stars, crescents, rings,
## beams, a shield lattice), a few sparks round them. Charge-up auras with particles drawn inward and a turning
## magic circle, projectiles with ribbon trails, clashing beams with a clash orb, shields that crack and shatter,
## ground impact rings, sparks, debris and explosions. Everything runs on world time, so hit-stop freezes it and
## slow motion slows it (the anime look). Positions are world points; the node sits at the world origin.

const TEX := "res://assets/vfx/brackeys/particles/alpha/"
const PAL := {
	"mika": {"glow": Color(0.42, 0.72, 1.0), "core": Color(0.9, 0.97, 1.0), "tex": "star_07_a.png", "dust": "star_04_a.png", "accent": Color(1.0, 0.86, 0.55), "points": 5.0},
	"luna": {"glow": Color(0.66, 0.4, 1.0), "core": Color(0.98, 0.94, 1.0), "tex": "slash_01_a.png", "dust": "flare_01_a.png", "accent": Color(1.0, 0.82, 0.5), "points": 0.0},
}

var level := 1.0                         # effect intensity (training < 1: lighter)
var _trails: Array = []                  # {src, hist, mi, im, mat, w, len, live, temp, vis}
var _movers: Array = []                  # projectiles {node, trail, dust, from, to, t, dur, arc, on_hit, who, spin}
var _follow: Array = []                  # [node, Callable -> Vector3]
var _beams: Array = []
var _hand := {}                          # "who:bone" -> {trail, prev, dust}
var _now := 0.0
var _nan_said := false


static func make(host: Node) -> FightFX:
	var f := FightFX.new()
	f.name = "FightFX"
	host.add_child(f)
	f.top_level = true
	f.global_transform = Transform3D.IDENTITY
	return f


static func pal(who: String) -> Dictionary:
	return PAL.get(who, PAL.mika)


# ------------------------------------------------------------------------------------------------ building blocks
func glow_mat(who: String, energy := 3.0, tex := "") -> ShaderMaterial:
	var p := pal(who)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/duel/fight_glow.gdshader")
	m.set_shader_parameter("tex", load(TEX + (tex if tex != "" else String(p.tex))))
	m.set_shader_parameter("color", p.glow)
	m.set_shader_parameter("core", p.core)
	m.set_shader_parameter("energy", energy)
	return m


func sprite(at: Vector3, size: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	add_child(mi)
	mi.global_position = at
	return mi


func tex_mat(tex: String, col: Color, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/duel/fight_sprite.gdshader")
	m.set_shader_parameter("tex", load(TEX + tex))
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	return m


func quad(size: Vector2, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	return q


func fade_ramp(a := 0.08, b := 0.6) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, a, b, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func shrink() -> CurveTexture:
	var cv := Curve.new()
	cv.add_point(Vector2(0, 1))
	cv.add_point(Vector2(1, 0.2))
	var ct := CurveTexture.new()
	ct.curve = cv
	return ct


func particles(amount: int, life: float, pm: ParticleProcessMaterial, mesh: Mesh, one_shot := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.one_shot = one_shot
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.visibility_aabb = AABB(Vector3(-10, -4, -10), Vector3(20, 14, 20))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	if one_shot:
		p.explosiveness = 0.92
		p.emitting = true
		get_tree().create_timer(life + 0.8, false).timeout.connect(p.queue_free)
	return p


func light(at: Vector3, col: Color, energy: float, dur: float, rng := 6.0) -> void:
	var l := OmniLight3D.new()
	add_child(l)
	l.global_position = at
	l.light_color = col
	l.omni_range = rng
	l.light_energy = energy * level
	l.shadow_enabled = false
	var tl := create_tween()
	tl.tween_property(l, "light_energy", 0.0, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tl.tween_callback(l.queue_free)


func follow(n: Node3D, src: Callable) -> void:
	_follow.append([n, src])


## A sprite that pops (scale up fast, fade out): flashes, star bursts.
func pop(at: Vector3, who: String, size: float, dur: float, energy := 5.0, tex := "", grow := 1.6, spin := 0.0) -> MeshInstance3D:
	var m := glow_mat(who, energy * level, tex)
	m.set_shader_parameter("spin", spin)
	var s := sprite(at, size, m)
	s.scale = Vector3.ONE * 0.4
	var tw := create_tween().set_parallel()
	tw.tween_property(s, "scale", Vector3.ONE * grow, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)
	return s


# ------------------------------------------------------------------------------------------------ ribbons (trails)
func trail(src: Callable, who: String, w: float, length: int, energy := 3.0) -> Dictionary:
	var p := pal(who)
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/duel/fight_ribbon.gdshader")
	m.set_shader_parameter("color", p.glow)
	m.set_shader_parameter("core", p.core)
	m.set_shader_parameter("energy", energy * level)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.extra_cull_margin = 16.0
	add_child(mi)
	var t := {"src": src, "hist": PackedVector3Array(), "mi": mi, "im": im, "mat": m, "w": w, "len": length, "live": true, "temp": false}
	_trails.append(t)
	return t


func end_trail(t: Dictionary) -> void:
	t.live = false
	t.temp = true


func _draw_trail(t: Dictionary, cam: Camera3D, frozen: bool) -> void:
	var hist: PackedVector3Array = t.hist
	if not frozen:
		if t.live:
			var np: Vector3 = (t.src as Callable).call()
			if not np.is_finite():
				if not _nan_said:
					_nan_said = true
					print("[fightnan] trail point not finite: ", np)
				np = hist[0] if hist.size() > 0 else Vector3.ZERO
			hist.insert(0, np)
			if hist.size() > int(t.len):
				hist.resize(int(t.len))
		elif hist.size() > 0:
			hist.resize(maxi(0, hist.size() - 2))
	t.hist = hist
	var im: ImmediateMesh = t.im
	im.clear_surfaces()
	if hist.size() < 3 or cam == null:
		if t.temp and hist.size() == 0:
			(t.mi as Node).queue_free()
			_trails.erase(t)
		return
	var pts := PackedVector3Array()
	for i in hist.size() - 1:
		var p0 := hist[maxi(i - 1, 0)]
		var p1 := hist[i]
		var p2 := hist[i + 1]
		var p3 := hist[mini(i + 2, hist.size() - 1)]
		for s in 3:
			var u := s / 3.0
			var u2 := u * u
			var u3 := u2 * u
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))
	pts.append(hist[hist.size() - 1])
	var full := float(int(t.len) * 3)
	var w: float = t.w
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var a := pts[i]
		var dir := (pts[i] - pts[i + 1]) if i < pts.size() - 1 else (pts[i - 1] - pts[i])
		if dir.length() < 0.00001:
			dir = Vector3.UP * 0.001
		var view := (cam.global_position - a).normalized()
		var side := dir.cross(view)
		side = side.normalized() * w if side.length() > 0.000001 else Vector3.ZERO
		var u := float(i) / full
		im.surface_set_uv(Vector2(u, 0.0))
		im.surface_add_vertex(a + side)
		im.surface_set_uv(Vector2(u, 1.0))
		im.surface_add_vertex(a - side)
	im.surface_end()


## Light ribbons behind both hands (bright only while the hand moves fast: strikes, sweeps, spins).
func hand_trails(c: WorldCharacter, who: String) -> void:
	for hb in ["LeftHand", "RightHand"]:
		var sk := c.skeleton
		var bi := sk.find_bone(hb)
		var src := func() -> Vector3: return sk.global_transform * sk.get_bone_global_pose(bi).origin
		var hi := sk.find_bone("Hips")
		var hips := func() -> Vector3: return sk.global_transform * sk.get_bone_global_pose(hi).origin
		var t := trail(src, who, 0.035, 14, 3.2)
		_hand[who + ":" + hb] = {"trail": t, "src": src, "hips": hips, "prev": Vector3.INF, "vis": 0.0}


func dust_emitter(who: String, amount := 60, size := 0.035) -> GPUParticles3D:
	var p := pal(who)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.4
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.gravity = Vector3(0, -0.2, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	pm.color_ramp = fade_ramp(0.05, 0.5)
	pm.scale_curve = shrink()
	return particles(amount, 0.9, pm, quad(Vector2(size, size), tex_mat(String(p.dust), (p.glow as Color).lerp(Color.WHITE, 0.4), 3.2)))


# ------------------------------------------------------------------------------------------------ charge-up
## Her aura while she gathers power: light drawn inward from round her, motes rising, a magic circle turning under her
## feet and a glow at her chest. Returns a handle for aura_off().
func aura(c: WorldCharacter, who: String, k := 1.0) -> Dictionary:
	var p := pal(who)
	var col: Color = p.glow
	var base := c.global_position
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 1.25
	pm.radial_accel_min = -6.0
	pm.radial_accel_max = -3.5
	pm.gravity = Vector3(0, 0.6, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.1
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color_ramp = fade_ramp(0.25, 0.8)
	var inward := particles(int(90 * k * level), 0.7, pm, quad(Vector2(0.05, 0.05), tex_mat(String(p.dust), col.lerp(Color.WHITE, 0.35), 3.5)))
	inward.global_position = base + Vector3(0, 1.0, 0)
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm2.emission_ring_axis = Vector3.UP
	pm2.emission_ring_radius = 0.7
	pm2.emission_ring_inner_radius = 0.2
	pm2.emission_ring_height = 0.05
	pm2.direction = Vector3.UP
	pm2.spread = 8.0
	pm2.initial_velocity_min = 1.2
	pm2.initial_velocity_max = 2.6
	pm2.gravity = Vector3.ZERO
	pm2.scale_min = 0.6
	pm2.scale_max = 1.2
	pm2.color_ramp = fade_ramp(0.1, 0.5)
	pm2.particle_flag_align_y = true
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/anime/duel/fight_streak.gdshader")
	sm.set_shader_parameter("color", col)
	sm.set_shader_parameter("energy", 3.0 * level)
	var rising := particles(int(40 * k * level), 0.8, pm2, quad(Vector2(0.03, 0.4), sm))
	rising.global_position = base + Vector3(0, 0.05, 0)
	var circ := circle(base, who, 2.4 * k)
	var chest := sprite(base + Vector3(0, 1.1, 0), 1.3 * k, glow_mat(who, 0.7 * level, "light_01_a.png"))
	(chest.material_override as ShaderMaterial).set_shader_parameter("shape_scale", 0.3)
	var sk := c.skeleton
	var ci := sk.find_bone("Chest")
	follow(chest, func() -> Vector3: return sk.global_transform * sk.get_bone_global_pose(ci).origin + Vector3(0, 0.05, 0))
	follow(inward, func() -> Vector3: return c.global_position + Vector3(0, 1.0, 0))
	follow(rising, func() -> Vector3: return c.global_position + Vector3(0, 0.05, 0))
	follow(circ.node, func() -> Vector3: return c.global_position + Vector3(0, 0.03, 0))
	light(base + Vector3(0, 1.2, 0), col, 1.5 * k, 1.6, 5.0)
	return {"nodes": [inward, rising, chest], "circle": circ}


func aura_off(h: Dictionary) -> void:
	if h.is_empty():
		return
	for n in h.nodes:
		if not is_instance_valid(n):
			continue
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = false
			get_tree().create_timer(1.0, false).timeout.connect((n as Node).queue_free)
		else:
			var m: ShaderMaterial = (n as MeshInstance3D).material_override
			var tw := create_tween()
			tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, 0.35)
			tw.tween_callback((n as Node).queue_free)
	circle_off(h.circle)


## A magic circle on the ground (Mika: a five-point star; Luna: crescents), turning; returns {node, mat}.
func circle(at: Vector3, who: String, size := 2.4) -> Dictionary:
	var p := pal(who)
	var mi := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(size, size)
	mi.mesh = pl
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/duel/fight_ring.gdshader")
	m.set_shader_parameter("color", p.glow)
	m.set_shader_parameter("mode", 1)
	m.set_shader_parameter("points", p.points)
	m.set_shader_parameter("energy", 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.03, 0)
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("energy", v), 0.0, 2.2 * level, 0.25)
	var h := {"node": mi, "mat": m, "turn": 0.0}
	mi.set_meta("circle", h)
	return h


func circle_off(h: Dictionary) -> void:
	if h.is_empty() or not is_instance_valid(h.node):
		return
	var m: ShaderMaterial = h.mat
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, 0.4)
	tw.tween_callback((h.node as Node).queue_free)


## A growing orb of her light at a hand (the moment before a release); follows the bone, gone after `dur`.
func hand_charge(c: WorldCharacter, who: String, bone := "RightHand", dur := 0.6, size := 0.5) -> MeshInstance3D:
	var sk := c.skeleton
	var bi := sk.find_bone(bone)
	var src := func() -> Vector3: return sk.global_transform * sk.get_bone_global_pose(bi).origin
	var m := glow_mat(who, 4.0 * level)
	var s := sprite(src.call(), size, m)
	s.scale = Vector3.ONE * 0.2
	follow(s, src)
	var tw := create_tween().set_parallel()
	tw.tween_property(s, "scale", Vector3.ONE, dur * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("spin", v), 0.0, 3.0, dur)
	tw.chain().tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, 0.12)
	tw.chain().tween_callback(s.queue_free)
	return s


# ------------------------------------------------------------------------------------------------ projectiles
## A bolt of her magic from `from` to the point `to` returns (evaluated as it flies, so it can track): a shaped core
## (star / crescent) turning, a ribbon trail, sparkle dust; `arc` lifts the path's middle; on_hit(at) at the end.
func projectile(from: Vector3, to: Callable, who: String, dur: float, size := 0.55, arc := 0.3, on_hit := Callable(), side := 0.0) -> Dictionary:
	var m := glow_mat(who, 5.0 * level)
	var s := sprite(from, size, m)
	var d := {"node": s, "mat": m, "from": from, "to": to, "t": 0.0, "dur": maxf(dur, 0.05), "arc": arc, "side": side, "on_hit": on_hit, "who": who, "pos": from}
	d.trail = trail(func() -> Vector3: return d.pos, who, size * 0.16, 16, 3.5)
	d.dust = dust_emitter(who, 50, 0.04)
	_movers.append(d)
	return d


func _mover_pos(d: Dictionary) -> Vector3:
	var k := clampf(float(d.t) / float(d.dur), 0.0, 1.0)
	var to: Vector3 = (d.to as Callable).call()
	var p := (d.from as Vector3).lerp(to, k)
	var dir := (to - (d.from as Vector3))
	var sideways := dir.cross(Vector3.UP).normalized() if dir.length() > 0.01 else Vector3.RIGHT
	p += Vector3.UP * float(d.arc) * sin(PI * k) + sideways * float(d.side) * sin(PI * k)
	return p


# ------------------------------------------------------------------------------------------------ beams and the clash
## A beam from a(): to b(): (both evaluated every frame); returns a handle (set "fade", end with beam_off).
func beam(a: Callable, b: Callable, who: String, width := 0.34) -> Dictionary:
	var p := pal(who)
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/duel/fight_beam.gdshader")
	m.set_shader_parameter("color", p.glow)
	m.set_shader_parameter("core", p.core)
	m.set_shader_parameter("energy", 4.0 * level)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.extra_cull_margin = 16.0
	add_child(mi)
	var muzzle := sprite(a.call(), width * 3.2, glow_mat(who, 4.0 * level, "flare_01_a.png"))
	follow(muzzle, a)
	var h := {"mi": mi, "im": im, "mat": m, "a": a, "b": b, "w": width, "grow": 0.0, "muzzle": muzzle}
	_beams.append(h)
	return h


func beam_off(h: Dictionary) -> void:
	if h.is_empty():
		return
	_beams.erase(h)
	for n in [h.mi, h.muzzle]:
		if is_instance_valid(n):
			(n as Node).queue_free()


func _draw_beam(h: Dictionary, cam: Camera3D, delta: float) -> void:
	h.grow = minf(float(h.grow) + delta / 0.18, 1.0)
	var a: Vector3 = (h.a as Callable).call()
	var b: Vector3 = (h.b as Callable).call()
	b = a.lerp(b, float(h.grow))
	var im: ImmediateMesh = h.im
	im.clear_surfaces()
	if cam == null or (b - a).length() < 0.05:
		return
	var m: ShaderMaterial = h.mat
	m.set_shader_parameter("scroll", _now)
	m.set_shader_parameter("length_m", (b - a).length())
	var dir := (b - a).normalized()
	var view := (cam.global_position - (a + b) * 0.5).normalized()
	var side := dir.cross(view).normalized() * float(h.w) * (1.0 + 0.08 * sin(_now * 40.0))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := 12
	for i in n + 1:
		var u := float(i) / n
		var p := a.lerp(b, u)
		im.surface_set_uv(Vector2(u, 0.0))
		im.surface_add_vertex(p + side)
		im.surface_set_uv(Vector2(u, 1.0))
		im.surface_add_vertex(p - side)
	im.surface_end()


## The clash point where two beams meet: an orb in both colours, sparks spraying, rings pulsing. Returns a handle
## whose "at" Callable it follows; clash_off() ends it.
func clash(at: Callable) -> Dictionary:
	var o1 := sprite(at.call(), 1.3, glow_mat("mika", 5.0 * level, "light_01_a.png"))
	var o2 := sprite(at.call(), 1.0, glow_mat("luna", 5.0 * level, "magic_03_a.png"))
	(o1.material_override as ShaderMaterial).set_shader_parameter("shape_scale", 0.35)
	follow(o1, at)
	follow(o2, at)
	var sp := spark_emitter("mika", 70)
	var sp2 := spark_emitter("luna", 70)
	follow(sp, at)
	follow(sp2, at)
	return {"nodes": [o1, o2, sp, sp2], "at": at, "pulse": 0.0}


func clash_off(h: Dictionary) -> void:
	for n in h.get("nodes", []):
		if is_instance_valid(n):
			(n as Node).queue_free()


func spark_emitter(who: String, amount := 60) -> GPUParticles3D:
	var p := pal(who)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3(0, 0.3, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 2.2
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, -6.0, 0)          # (no damping: a velocity-aligned spark at zero speed is a NaN black square)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = fade_ramp(0.02, 0.4)
	pm.particle_flag_align_y = true
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/anime/duel/fight_streak.gdshader")
	sm.set_shader_parameter("color", p.glow)
	sm.set_shader_parameter("energy", 4.5 * level)
	return particles(amount, 0.45, pm, quad(Vector2(0.025, 0.28), sm))


# ------------------------------------------------------------------------------------------------ impacts
## Sparks thrown from a point (streaks along their velocity), mostly along `dir`.
func sparks(at: Vector3, dir: Vector3, who: String, n := 40, speed := 6.0) -> void:
	var p := pal(who)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.06
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = speed * 0.3
	pm.initial_velocity_max = speed * 0.7
	pm.gravity = Vector3(0, -7.0, 0)          # (no damping: see spark_emitter)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color_ramp = fade_ramp(0.02, 0.45)
	pm.particle_flag_align_y = true
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/anime/duel/fight_streak.gdshader")
	sm.set_shader_parameter("color", (p.glow as Color).lerp(Color.WHITE, 0.2))
	sm.set_shader_parameter("energy", 5.0 * level)
	var s := particles(int(n * level), 0.55, pm, quad(Vector2(0.03, 0.34), sm), true)
	s.global_position = at


## Rock and earth chips kicked up from the ground (dark, lit, falling back).
func debris(at: Vector3, n := 18, power := 1.0) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 1.8 * power
	pm.initial_velocity_max = 4.0 * power
	pm.gravity = Vector3(0, -12.0, 0)
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	pm.scale_min = 0.4
	pm.scale_max = 1.4
	var rock := PrismMesh.new()
	rock.size = Vector3(0.09, 0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.56, 0.48, 0.4)
	mat.roughness = 0.95
	mat.emission_enabled = true                    # (lit by the blast: never a black speck against the glow)
	mat.emission = Color(0.42, 0.36, 0.32)
	mat.emission_energy_multiplier = 0.8
	rock.material = mat
	var s := particles(int(n * 0.35), 1.0, pm, rock, true)
	s.explosiveness = 1.0
	s.global_position = at + Vector3(0, 0.1, 0)
	puff(at, int(10 * power) + 4, 0.5 * power + 0.2)


## A ground impact ring racing outward (+ a second, slower one).
func ground_ring(at: Vector3, who: String, size := 3.0, n := 2, dur := 0.7) -> void:
	var p := pal(who)
	for i in n:
		var mi := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		pl.size = Vector2(size, size) * (1.0 + i * 0.45)
		mi.mesh = pl
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/anime/duel/fight_ring.gdshader")
		m.set_shader_parameter("color", p.glow if i == 0 else (p.glow as Color).lerp(Color.WHITE, 0.3))
		m.set_shader_parameter("energy", 3.0 * level)
		m.set_shader_parameter("mode", 0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = at + Vector3(0, 0.04 + i * 0.01, 0)
		var tw := create_tween()
		tw.tween_interval(i * 0.08)
		tw.tween_method(func(v: float): m.set_shader_parameter("t", v), 0.0, 1.0, dur * (1.0 + i * 0.4))
		tw.tween_callback(mi.queue_free)


## A struck point: a four-point star flare, a burst of sparks, a flash of light (small = a touch, big = a real hit).
func hit_spark(at: Vector3, who: String, dir: Vector3, big := false) -> void:
	pop(at, who, 1.4 if big else 0.8, 0.22 if big else 0.16, 5.0, "star_07_a.png", 1.8, randf() * 0.6)
	pop(at, who, 2.2 if big else 1.2, 0.26, 1.6, "scorch_02_a.png", 1.4, randf() * TAU)
	sparks(at, dir, who, 46 if big else 24, 7.0 if big else 5.0)
	light(at, (pal(who).glow as Color).lerp(Color.WHITE, 0.4), 4.0 if big else 2.0, 0.35, 5.0)


## An explosion of her magic at a point on the ground (an aerial slam, the finisher): a white-hot star burst, her
## colour blooming out, two ground rings, sparks, debris and a light flash.
func explosion(at: Vector3, who: String, size := 1.0) -> void:
	pop(at + Vector3(0, 0.6 * size, 0), who, 3.0 * size, 0.3, 5.0, "star_07_a.png", 1.8)
	pop(at + Vector3(0, 0.7 * size, 0), who, 3.6 * size, 0.45, 1.3, "light_01_a.png", 1.4)
	pop(at + Vector3(0, 0.5 * size, 0), who, 3.6 * size, 0.4, 1.6, "scorch_02_a.png", 1.5, randf() * TAU)
	ground_ring(at, who, 3.4 * size, 2, 0.8)
	sparks(at + Vector3(0, 0.3, 0), Vector3.UP, who, int(70 * size), 9.0 * size)
	debris(at, int(22 * size), size)
	light(at + Vector3(0, 1.0, 0), (pal(who).glow as Color).lerp(Color.WHITE, 0.3), 3.0 * size, 0.5, 7.0 * size)


## A crescent slash of light: an arc of radius r about `center` in the plane with normal `nrm`, swept from angle a0 to
## a1 (degrees, measured from `ref`) over `dur`; the ribbon's head leads and its tail fades (3-6 frames of life).
func crescent(center: Vector3, nrm: Vector3, ref: Vector3, r: float, a0: float, a1: float, who: String, dur := 0.18, width := 0.12) -> void:
	var n := nrm.normalized()
	var x := (ref - n * ref.dot(n)).normalized()
	var y := n.cross(x)
	var st := {"k": 0.0}
	var src := func() -> Vector3:
		var a := deg_to_rad(lerpf(a0, a1, float(st.k)))
		return center + (x * cos(a) + y * sin(a)) * r
	var t := trail(src, who, width, 22, 4.0)
	var tw := create_tween()
	tw.tween_method(func(v: float): st.k = v, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(end_trail.bind(t))


## Dust kicked up from the ground (soft smoke sprites, ground-coloured, alpha blended - not the light layer).
func puff(at: Vector3, n := 8, size := 0.4) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.2, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	# light and thin: a dark alpha puff in front of a blast punches black holes into the bloom behind it
	g.colors = PackedColorArray([Color(0.86, 0.82, 0.76, 0.0), Color(0.86, 0.82, 0.76, 0.22), Color(0.9, 0.87, 0.82, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.5))
	cv.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = cv
	pm.scale_curve = ct
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = load(TEX + "smoke_04_a.png")
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var s := particles(n, 1.1, pm, quad(Vector2(size, size), m), true)
	s.global_position = at + Vector3(0, 0.15, 0)


## Ghost copies of her body along a dash (anime afterimages).
func afterimages(c: WorldCharacter, who: String, n := 4, every := 0.05) -> void:
	var col: Color = (pal(who).glow as Color).lerp(Color.WHITE, 0.25)
	for i in n:
		get_tree().create_timer(i * every, false).timeout.connect(func(): ghost(c, col, 0.28))


## One ghost of her body in this instant's pose (as Afterimage.spawn_model, but without the face mesh - its eye
## surfaces came out as black dots in the ghost shader).
func ghost(c: WorldCharacter, col: Color, life: float) -> void:
	if c == null or not is_instance_valid(c.avatar):
		return
	var holder := Node3D.new()
	holder.name = "FightGhost"
	add_child(holder)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fx/afterimage.gdshader")
	mat.set_shader_parameter("color", col)
	Afterimage.fill(holder, c.avatar, mat, func(m: MeshInstance3D) -> bool: return String(m.name).to_lower().contains("face"))
	var tw := holder.create_tween()
	tw.tween_method(func(k: float) -> void: mat.set_shader_parameter("fade", 1.0 - k), 0.0, 1.0, life)
	tw.tween_callback(holder.queue_free)


# ------------------------------------------------------------------------------------------------ shields
## A curved shield of light in front of her (toward `facing`), at chest height; returns a handle for shield_hit /
## shield_shatter / shield_off.
func shield(c: WorldCharacter, who: String, toward: Callable, radius := 0.95) -> Dictionary:
	var p := pal(who)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	sm.is_hemisphere = false
	mi.mesh = sm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/duel/fight_shield.gdshader")
	m.set_shader_parameter("color", p.glow)
	m.set_shader_parameter("energy", 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var h := {"node": mi, "mat": m, "crack": 0.0, "c": c, "toward": toward, "who": who, "flash": 0.0}
	var place := func() -> Vector3:
		var to: Vector3 = (toward.call() as Vector3) - c.global_position
		to.y = 0.0
		to = to.normalized() if to.length() > 0.01 else Vector3.FORWARD
		mi.global_basis = Basis.looking_at(-to, Vector3.UP) * Basis.from_scale(Vector3(0.78, 0.98, 0.26))
		return c.global_position + Vector3(0, 1.05, 0) + to * 0.62
	follow(mi, place)
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("energy", v), 0.0, 1.05 * level, 0.12)
	light(c.global_position + Vector3(0, 1.1, 0), p.glow, 1.2, 0.5, 4.0)
	return h


func shield_hit(h: Dictionary, at: Vector3, crack_add := 0.35) -> void:
	if h.is_empty() or not is_instance_valid(h.node):
		return
	var mi: MeshInstance3D = h.node
	var m: ShaderMaterial = h.mat
	h.crack = minf(float(h.crack) + crack_add, 1.0)
	var local := mi.global_transform.affine_inverse() * at
	m.set_shader_parameter("hit_local", local.normalized() * 1.0)
	m.set_shader_parameter("crack", h.crack)
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("hit_flash", v), 1.0, 0.0, 0.35)
	pop(at, String(h.who), 1.1, 0.18, 5.0, "magic_03_a.png", 1.5)


func shield_shatter(h: Dictionary, impact_dir: Vector3) -> void:
	if h.is_empty() or not is_instance_valid(h.node):
		return
	var mi: MeshInstance3D = h.node
	var at := mi.global_position
	var p := pal(String(h.who))
	# shards: flat bright triangles flying out from the strike
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.6, 0.7, 0.15)
	pm.direction = impact_dir.normalized() + Vector3(0, 0.3, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -5.0, 0)
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	pm.color_ramp = fade_ramp(0.02, 0.6)
	var pr := PrismMesh.new()
	pr.size = Vector3(0.12, 0.16, 0.01)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = (p.glow as Color).lerp(Color.WHITE, 0.55)
	sm.emission_enabled = true
	sm.emission = p.glow
	sm.emission_energy_multiplier = 3.0
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pr.material = sm
	var s := particles(36, 0.9, pm, pr, true)
	s.global_position = at
	pop(at, String(h.who), 2.4, 0.3, 6.0, "magic_03_a.png", 1.8)
	shield_off(h, 0.05)


func shield_off(h: Dictionary, dur := 0.25) -> void:
	if h.is_empty() or not is_instance_valid(h.node):
		return
	for f in _follow.duplicate():
		if f[0] == h.node:
			_follow.erase(f)
	var m: ShaderMaterial = h.mat
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur)
	tw.tween_callback((h.node as Node).queue_free)


## A pillar of her light rising behind her (the finisher's power-up).
func pillar(at: Vector3, who: String, height := 7.0, dur := 1.6) -> void:
	var lo := at + Vector3(0, 0.05, 0)
	var hi := at + Vector3(0, height, 0)
	var h := beam(func() -> Vector3: return lo, func() -> Vector3: return hi, who, 0.55)
	(h.mat as ShaderMaterial).set_shader_parameter("energy", 1.3 * level)
	(h.muzzle as MeshInstance3D).visible = false
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_method(func(v: float): (h.mat as ShaderMaterial).set_shader_parameter("fade", v), 1.0, 0.0, 0.4)
	tw.tween_callback(beam_off.bind(h))


# ------------------------------------------------------------------------------------------------ the frame
func _process(delta: float) -> void:
	_now += delta
	var frozen := delta < 0.0005                      # hit-stop: trails and ribbons hold still
	var cam := get_viewport().get_camera_3d()
	for f in _follow.duplicate():
		if not is_instance_valid(f[0]):
			_follow.erase(f)
			continue
		(f[0] as Node3D).global_position = (f[1] as Callable).call()
	for n in get_children():
		if n.has_meta("circle"):
			var h: Dictionary = n.get_meta("circle")
			h.turn = float(h.turn) + delta * 0.6
			(h.mat as ShaderMaterial).set_shader_parameter("turn", h.turn)
	for d in _movers.duplicate():
		d.t = float(d.t) + delta
		var p := _mover_pos(d)
		d.pos = p
		var s: MeshInstance3D = d.node
		if is_instance_valid(s):
			s.global_position = p
			(d.mat as ShaderMaterial).set_shader_parameter("spin", float(d.t) * 9.0)
		(d.dust as GPUParticles3D).global_position = p
		if float(d.t) >= float(d.dur):
			_movers.erase(d)
			end_trail(d.trail)
			(d.dust as GPUParticles3D).emitting = false
			get_tree().create_timer(1.0, false).timeout.connect((d.dust as Node).queue_free)
			if is_instance_valid(s):
				s.queue_free()
			if (d.on_hit as Callable).is_valid():
				(d.on_hit as Callable).call(p)
	for k in _hand:
		var h: Dictionary = _hand[k]
		var p: Vector3 = (h.src as Callable).call() - (h.hips as Callable).call()     # (her own sweep, not her walking)
		var spd := 0.0 if h.prev == Vector3.INF or frozen else (p - (h.prev as Vector3)).length() / maxf(delta, 0.001)
		if not frozen:
			h.prev = p
		var vis := clampf((spd - 1.6) / 2.5, 0.0, 1.0)
		h.vis = lerpf(float(h.vis), vis, 0.5 if vis > float(h.vis) else 0.15)
		if is_nan(float(h.vis)) or is_inf(float(h.vis)):
			if not _nan_said:
				_nan_said = true
				print("[fightnan] hand trail fade not finite (speed %s)" % str(spd))
			h.vis = 0.0
		((h.trail as Dictionary).mat as ShaderMaterial).set_shader_parameter("fade_all", float(h.vis))
	for t in _trails.duplicate():
		_draw_trail(t, cam, frozen)
	for b in _beams:
		_draw_beam(b, cam, delta)
