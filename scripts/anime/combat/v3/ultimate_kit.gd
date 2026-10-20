class_name UltimateKit
extends Node
## The cinematic ultimate kit (2026-10-20, Selwyn: "a cinematic ultimate kit, shared by every ultimate and big spell,
## reference style Wuthering Waves and Honkai ultimates, technique only"). One timeline, built round a spell's gather
## and release, that every ultimate runs (UltimateCast) and a big spell runs in its short form (big_spell):
##   camera        4 to 7 shots in 3 to 5 s on the fight's Phantom Camera director: one eye in extreme close-up with a
##                 dutch tilt, her two hands forming the sign, a low orbit round her as the halo forms, the low hero
##                 shot, a fast push-in on her face, the wide release, the impact, the aftermath
##   speed ramp    slow motion 0.25x through the last breath before the release, a snap to full speed on it, a hit stop
##                 on the first hit
##   impact frames on the hit only: two frames of inverted black and white, one starburst frame, one white frame,
##                 radial speed lines and a chromatic pulse
##   colour        her grade takes the whole screen through the cast (Mika pink with white highlights, Luna violet with
##                 gold), a vignette on her, then both let go
##   domain        3 to 5 s of her sky (the realm sky: Mika a pink night of stars with petals falling over the whole
##                 arena, Luna the violet eclipse), her fog and light, then the area's own sky back
##   post          radial blur and speed lines on the push-in, a lens flare at her hands on the release
##   giant shapes  a sigil halo behind her (drawn on through the gather, flaring at the release) with the flipbook
##                 on it; Mika a ring of conjured blades round her that rain on the other girl with the petal burst
##                 where they land; Luna a giant ghost of her weapon cutting a crescent with the crescent flipbook on it
## Everything is our own design; the references give the technique (Download(4) 0 to 20 s, Download(7) 26 to 32 s).

const GRADE := {
	"mika": [Color(1.0, 0.42, 0.68), Color(1.0, 0.95, 0.97)],
	"luna": [Color(0.48, 0.24, 0.95), Color(1.0, 0.88, 0.66)],
}
const HALO := {
	"mika": [Vector3(1.0, 0.5, 0.76), Vector3(1.0, 0.95, 0.97), 0],
	"luna": [Vector3(0.6, 0.36, 1.0), Vector3(1.0, 0.84, 0.5), 1],
}

var sim: MeleeSim
var d: FightDirector
var who := ""
var other := ""
var big := true                              # the full ultimate (false: a big spell's short form)
var t0 := 0.0                                # its start on the fight clock
var _hit_done := false
var _nodes: Array = []
var _halo: MeshInstance3D
var _halo_mat: ShaderMaterial
var _halo_card: FlipbookFX
var _ground_card: FlipbookFX
var _rain: CanvasLayer
var _spin := 0.0
var _blades: Array = []                      # [MeshInstance3D, ShaderMaterial, slot angle, state dict]
var _blade_ring_on := false
var _domain := {}


static func sfx_of(dd: FightDirector) -> ScreenFX:
	return ScreenFX.get_for(dd)


## The full ultimate round its gesture timing (fight seconds from now): gather start g0, the release t_rel, length L.
## shape: "blades" (Mika's ring of conjured blades) or "ghost" (Luna's ghost weapon slash).
static func ultimate(s: MeleeSim, caster: String, target: String, g0: float, t_rel: float, L: float, shape: String) -> UltimateKit:
	var k := UltimateKit.new()
	k.name = "UltimateKit_" + caster
	k.sim = s
	k.d = s.d
	k.who = caster
	k.other = target
	k.t0 = s.d.ft
	s.d.main.add_child(k)
	s.set("ult_kit", k)
	k._plan(g0, t_rel, L, shape)
	return k


## A big spell's short form: the low hero shot, the push-in, the wide release, the flare and the grade, no domain and
## no slow windup longer than a breath.
static func big_spell(s: MeleeSim, caster: String, target: String, t_rel: float) -> UltimateKit:
	var k := UltimateKit.new()
	k.name = "BigSpellKit_" + caster
	k.sim = s
	k.d = s.d
	k.who = caster
	k.other = target
	k.big = false
	k.t0 = s.d.ft
	s.d.main.add_child(k)
	k._plan_short(t_rel)
	return k


func _plan(g0: float, T: float, L: float, shape: String) -> void:
	var sfx := sfx_of(d)
	var G := maxf(g0, 0.35)
	var col: Array = GRADE[who]
	var hold_cast := T + 0.4
	# the shots (4 to 7 between the opening and the impact)
	sim.cine_hold = sim.t + L + 1.6
	d.cut(t0 + 0.001, "eye", who, {"snap": true, "roll": 9.0, "flip": 1.0 if who == "mika" else -1.0})
	d.cut(t0 + G, "sign", who, {"snap": true, "roll": -7.0})
	var t_orb := G + (T - G) * 0.42
	d.cut(t0 + t_orb, "orbit_her", who, {"snap": true, "from": -70.0, "to": 25.0, "r": 3.2, "h": 0.2, "roll": 6.0, "fov": 52.0})
	d.cut(t0 + T - 0.42, "hero_low", who, {"snap": true, "roll": -4.0})
	d.cut(t0 + T - 0.16, "push", who, {"snap": true, "from": 3.6, "to": 1.05})
	d.cut(t0 + T - 0.01, "pullback", who, {"snap": true, "dist": 12.0, "high": 3.8})
	d.cut(t0 + L + 0.3, "two_mid", who, {"snap": true})
	# colour, vignette, the domain
	sfx.wash2(col[0], col[1], 0.6, 0.35, hold_cast, 0.7)
	sfx.vignette_hold(0.55, 0.3, hold_cast, 0.5)
	_domain_on(clampf(T + 1.6, 3.0, 5.0))
	# the halo sigil (FX_Cinematic_v1): assembling behind her through the gather and turning, a second one flat on the
	# ground under her; the drawn halo (sigil_halo) only when the video cards are off
	if FlipbookFX.enabled():
		var hname := who + "_halo_sigil"
		_halo_card = FlipbookFX.play(d.main, hname, func() -> Vector3: return _halo_at(), {"size": 5.0, "f0": 0.0, "f1": 63.0,
			"dur": T + 0.9, "fade_in": 0.3, "fade_out": 0.5, "intensity": 1.3, "light": 3.0, "light_range": 7.0, "black_cut": 0.15})
		var fy := sim.d.pos(who)
		_ground_card = FlipbookFX.play(d.main, hname, func() -> Vector3: return Vector3(sim.d.pos(who).x, fy.y + 0.04, sim.d.pos(who).z),
			{"size": 4.2, "flat": true, "f0": 0.0, "f1": 63.0, "dur": T + 1.2, "fade_in": 0.4, "fade_out": 0.6, "intensity": 1.2, "light": 0.0,
			"black_cut": 0.15})
		_nodes.append(_halo_card)
		_nodes.append(_ground_card)
	else:
		_halo_build()
		var tw := create_tween()
		tw.tween_method(func(v: float): _halo_mat.set_shader_parameter("reveal", v), 0.0, 1.0, maxf(T - 0.3, 0.4)).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_method(func(v: float): _halo_mat.set_shader_parameter("fade", v), 0.0, 1.0, 0.4)
	if shape == "blades":
		sim.at(G, func(): _blades_build())
	# the speed ramp: the last breath before the release in slow motion, the release at full speed
	sim.at(T - 0.42, func():
		d.slowmo(0.25, 0.42)
		sfx.zoom_blur(0.5, 0.9)
		sfx.speed_lines(0.55, 0.9))
	sim.at(T, func(): _release(shape))
	sim.at(L + 1.4, func(): _end())


func _plan_short(T: float) -> void:
	var sfx := sfx_of(d)
	var col: Array = GRADE[who]
	d.cut(t0 + maxf(T - 0.55, 0.0), "hero_low", who, {"snap": true, "roll": -4.0})
	d.cut(t0 + maxf(T - 0.18, 0.0), "push", who, {"snap": true, "from": 3.2, "to": 1.3})
	d.cut(t0 + T, "pullback", who, {"snap": true, "dist": 9.0, "high": 2.6})
	sfx.wash2(col[0], col[1], 0.5, 0.25, T + 0.3, 0.5)
	sfx.vignette_hold(0.35, 0.2, T + 0.2, 0.4)
	sim.at(maxf(T - 0.18, 0.0), func():
		d.slowmo(0.5, 0.18)
		sfx.zoom_blur(0.35, 0.5))
	sim.at(T, func():
		_flare()
		sfx.chroma(0.5, 0.3))
	sim.at(T + 2.5, func(): queue_free())


# ------------------------------------------------------------------------------------------------ the release and the hit
func _release(shape: String) -> void:
	var sfx := sfx_of(d)
	d.slowmo(1.0, 0.0)
	Engine.time_scale = d.tempo
	_flare()
	sfx.chroma(0.7, 0.35)
	sfx.shake(0.05, 0.4)
	if _halo_mat:
		var tw := create_tween()
		tw.tween_method(func(v: float): _halo_mat.set_shader_parameter("boost", v), 0.35, 0.0, 0.8)
		tw.tween_method(func(v: float): _halo_mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.8)
	if shape == "blades":
		_blades_fire()
	elif shape == "ghost":
		_ghost_slash()


## The first hit of the ultimate: the impact frames, the hit stop, the speed lines, a cut to the impact.
func on_hit(p: Vector3) -> void:
	if _hit_done:
		return
	_hit_done = true
	var sfx := sfx_of(d)
	d.impact(1.0, false)                              # (the hit stop and the shake; the frames are ours)
	FlipbookFX.play(d.main, "fx_impact_starburst", func() -> Vector3: return p, {"size": 1.8, "f0": 4.0, "f1": 63.0, "dur": 0.6,
		"fade_in": 0.02, "fade_out": 0.25, "intensity": 1.6, "light": 4.0, "black_cut": 0.16})
	sfx.flash_seq([["invert_bw", 2], ["burst", 1], ["white", 1]], atan2(1.0, 0.4))
	sfx.speed_lines(0.9, 0.5, _uv(p), Color(1, 1, 1))
	sfx.chroma(1.0, 0.4)
	d.cut(d.ft + 0.01, "impact", who, {"snap": true, "at": p})
	d.cut(d.ft + 0.75, "pullback", who, {"snap": true, "dist": 11.0, "high": 3.4})


func _flare() -> void:
	var f: MeleeFighter = sim.F[who]
	var hl: Vector3 = f.trace.get("LeftHand", f.sk.global_position)
	var hr: Vector3 = f.trace.get("RightHand", f.sk.global_position)
	var col: Array = GRADE[who]
	sfx_of(d).lens_flare(_uv((hl + hr) * 0.5), (col[1] as Color).lerp(col[0], 0.35), 0.7, 0.8)


func _uv(p: Vector3) -> Vector2:
	var cam := d.get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(p):
		return Vector2(0.5, 0.5)
	var vs := d.get_viewport().get_visible_rect().size
	return (cam.unproject_position(p) / vs).clamp(Vector2(0.02, 0.02), Vector2(0.98, 0.98))


# ------------------------------------------------------------------------------------------------ the halo
## Behind her as the camera sees her (a step back from her chest along the line from the lens), above her shoulders.
func _halo_at() -> Vector3:
	var f: MeleeFighter = sim.F[who]
	var ch: Vector3 = f.trace.get("Chest", f.sk.global_position + Vector3.UP * 1.2)
	var cam := d.get_viewport().get_camera_3d()
	var away := (ch - cam.global_position) if cam else -d.fwd(who)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -d.fwd(who)
	return ch + away * 2.0 + Vector3.UP * 0.45


func _halo_build() -> void:
	_halo = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(4.2, 4.2) if who == "mika" else Vector2(4.6, 4.6)
	_halo.mesh = q
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = load("res://shaders/magic/sigil_halo.gdshader")
	var h: Array = HALO[who]
	_halo_mat.set_shader_parameter("col", h[0])
	_halo_mat.set_shader_parameter("hi", h[1])
	_halo_mat.set_shader_parameter("figure", h[2])
	_halo_mat.set_shader_parameter("reveal", 0.0)
	_halo_mat.set_shader_parameter("fade", 0.0)
	_halo_mat.set_shader_parameter("intensity", 1.4)
	_halo.material_override = _halo_mat
	_halo.top_level = true
	d.main.add_child(_halo)
	_nodes.append(_halo)
	var l := OmniLight3D.new()
	l.light_color = Color(h[0].x, h[0].y, h[0].z)
	l.omni_range = 7.0
	l.light_energy = 2.0
	l.shadow_enabled = false
	_halo.add_child(l)


# ------------------------------------------------------------------------------------------------ Mika's ring of blades
func _blades_build() -> void:
	var svfx: SpellVFX = sim.magic.svfx
	var mesh := svfx.crystal(1.7, 0.075, 4, 0.14)
	for i in 12:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/magic/ult_glow.gdshader")
		m.set_shader_parameter("col", Vector3(1.0, 0.5, 0.76))
		m.set_shader_parameter("hi", Vector3(1.0, 0.95, 0.98))
		m.set_shader_parameter("intensity", 1.8)
		m.set_shader_parameter("reveal", 0.0)
		mi.material_override = m
		mi.top_level = true
		d.main.add_child(mi)
		_nodes.append(mi)
		var st := {"mode": "ring", "t": 0.0}
		_blades.append([mi, m, TAU * float(i) / 12.0, st])
		# each blade drawn out of the air, one after another round the ring
		var tw := mi.create_tween()
		tw.tween_interval(0.06 * float(i))
		tw.tween_method(func(v: float): m.set_shader_parameter("reveal", v), 0.0, 1.0, 0.35)
	_blade_ring_on = true


func _ring_center() -> Vector3:
	var f: MeleeFighter = sim.F[who]
	var ch: Vector3 = f.trace.get("Chest", f.sk.global_position + Vector3.UP * 1.2)
	return ch + Vector3.UP * 1.3 - d.fwd(who) * 0.4


func _blades_fire() -> void:
	var of_r: MeleeFighter = sim.F[other]
	var ring_at: Vector3 = of_r.trace.get("Chest", of_r.sk.global_position + Vector3.UP)
	# (the ring of light swords closing on her: frames 0 to 50, the white ball at its end left out)
	sim.at(0.15, func():
		FlipbookFX.play(d.main, "fx_blade_ring", func() -> Vector3: return ring_at, {"size": 4.5, "f0": 0.0, "f1": 50.0, "dur": 1.1,
			"fade_in": 0.05, "fade_out": 0.3, "intensity": 1.5, "light": 4.0, "black_cut": 0.16}))
	var of: MeleeFighter = sim.F[other]
	var tgt: Vector3 = of.sk.global_position
	var gy := sim.d.pos(other).y
	var rng := sim.rng
	for i in _blades.size():
		var b: Array = _blades[i]
		var st: Dictionary = b[3]
		var off := Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-1.6, 1.6)) if i % 3 != 0 else Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		st.to = Vector3(tgt.x + off.x, gy + 0.05, tgt.z + off.z)
		st.delay = 0.05 * float(i)
		st.dur = 0.28
		st.mode = "fire"
		st.t = 0.0
		st.from = (b[0] as Node3D).global_position


func _blades_step(delta: float) -> void:
	if not _blade_ring_on:
		return
	_spin += delta * 0.9
	var c := _ring_center()
	var fa := d.fwd(who)
	var sa := fa.cross(Vector3.UP).normalized()
	var of: MeleeFighter = sim.F[other]
	var aim: Vector3 = of.trace.get("Chest", of.sk.global_position + Vector3.UP)
	var bursts := 0
	for b in _blades:
		if not is_instance_valid(b[0]):
			continue
		var mi: MeshInstance3D = b[0]
		var st: Dictionary = b[3]
		var ang := float(b[2]) + _spin
		if st.mode == "ring":
			# a ring of blades standing round and above her, every point turned on the other girl
			var p := c + (sa * cos(ang) + Vector3.UP * sin(ang) * 0.75) * 2.4 - fa * 0.3
			mi.global_transform = Transform3D(_basis_y(aim - p), p)
		elif st.mode == "fire":
			st.t = float(st.t) + delta
			var u := clampf((float(st.t) - float(st.delay)) / float(st.dur), 0.0, 1.0)
			if float(st.t) < float(st.delay):
				var p0 := c + (sa * cos(ang) + Vector3.UP * sin(ang) * 0.75) * 2.4 - fa * 0.3
				mi.global_transform = Transform3D(_basis_y((st.to as Vector3) - p0), p0)
				st.from = p0
				continue
			var e := u * u
			var p2: Vector3 = (st.from as Vector3).lerp(st.to, e)
			mi.global_transform = Transform3D(_basis_y((st.to as Vector3) - (st.from as Vector3)), p2)
			if u >= 1.0:
				st.mode = "landed"
				var at: Vector3 = st.to
				if bursts < 4:
					bursts += 1
					FlipbookFX.play(d.main, "mika_petal_burst", func() -> Vector3: return at + Vector3.UP * 0.6, {"size": 2.6, "f0": 11.0,
						"dur": 1.3, "fade_in": 0.03, "fade_out": 0.5, "intensity": 1.6, "light": 3.0, "black_cut": 0.16})
				sim.magic.arts.impact(at + Vector3.UP * 0.3, at.y - 0.05, who, 0.5)
				var mt: ShaderMaterial = b[1]
				var tw := mi.create_tween()
				tw.tween_method(func(v: float): mt.set_shader_parameter("fade", v), 1.0, 0.0, 0.5)
				tw.tween_callback(mi.queue_free)


## A basis whose +Y (a blade's length) points along dir.
static func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized() if dir.length() > 1e-4 else Vector3.UP
	var x := y.cross(Vector3.UP)
	x = x.normalized() if x.length() > 1e-3 else Vector3.RIGHT
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# ------------------------------------------------------------------------------------------------ Luna's ghost slash
## A giant ghost of her scythe swinging overhead through a crescent as tall as a tree, the crescent flipbook on it.
func _ghost_slash() -> void:
	var svfx: SpellVFX = sim.magic.svfx
	var f: MeleeFighter = sim.F[who]
	var fa := d.fwd(who)
	var sa := fa.cross(Vector3.UP).normalized()
	var base: Vector3 = f.sk.global_position + fa * 1.6
	# the crescent: an arc in her forward and up plane, sweeping from behind her head over and down in front
	var R := 5.2
	var mi := MeshInstance3D.new()
	mi.mesh = svfx.crescent_mesh(R, 0.9, 175.0, 40)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/magic/ult_glow.gdshader")
	m.set_shader_parameter("col", Vector3(0.62, 0.38, 1.0))
	m.set_shader_parameter("hi", Vector3(1.0, 0.86, 0.55))
	m.set_shader_parameter("intensity", 1.0)
	m.set_shader_parameter("reveal", 0.0)
	m.set_shader_parameter("along_tail", 0.0)
	mi.material_override = m
	mi.top_level = true
	d.main.add_child(mi)
	_nodes.append(mi)
	# (the mesh's arc lies in its X-Y plane centred on +Y: X along her forward, Y up, Z her side; centred low so the
	# arc rises over her and lands on the ground in front of her)
	var b := Basis(-fa, Vector3.UP, -sa)                 # (+X behind her: the arc is drawn from behind over to the front)
	mi.global_transform = Transform3D(b, base + Vector3.UP * (R * 0.15 - R * 0.05))
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("reveal", v), 0.0, 1.0, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.0)
	tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, 0.5)
	tw.tween_callback(mi.queue_free)
	# the ghost weapon: her scythe, four times her size, swinging through the arc with it
	var piv := base + Vector3.UP * (R * 0.15 - R * 0.05)
	var t_s := sim.t
	FlipbookFX.play(d.main, "fx_ghost_slash", func() -> Vector3: return piv + Vector3.UP * R * 0.45 + fa * 0.4, {"size": 9.0, "f0": 0.0,
		"f1": 63.0, "dur": 1.5, "fade_in": 0.03, "fade_out": 0.4, "intensity": 1.6, "light": 5.0, "light_range": 10.0, "black_cut": 0.16,
		"roll_fn": func() -> float: return sim.magic.arts.screen_roll(piv + Vector3.UP * R + fa * 0.5, piv + fa * R * 0.9)})
	if FlipbookFX.enabled():
		return
	var w := svfx.weapon("violet_scythe", func() -> Transform3D:
		var u := clampf((sim.t - t_s) / 0.2, 0.0, 1.0)
		var a := deg_to_rad(lerpf(175.0, 5.0, 1.0 - pow(1.0 - u, 2.0)))
		var dir := fa * cos(a) + Vector3.UP * sin(a)
		var bb := _basis_y(dir).scaled(Vector3(4.0, 4.0, 4.0))
		return Transform3D(bb, piv), "luna")
	(w.root as Node).reparent(d.main)
	sim.at(0.75, func(): svfx.weapon_vanish(w))
	# the crescent flipbook on the arc, turned to it
	FlipbookFX.play(d.main, "luna_crescent_slash", func() -> Vector3: return piv + Vector3.UP * R * 0.55 + fa * 0.3, {"size": 8.0, "f0": 0.0,
		"f1": 63.0, "dur": 1.8, "fade_in": 0.03, "fade_out": 0.5, "intensity": 1.8, "light": 5.0, "light_range": 9.0,
		"roll_fn": func() -> float: return sim.magic.arts.screen_roll(piv + Vector3.UP * R, piv + fa * R)})


# ------------------------------------------------------------------------------------------------ the domain
## Her sky for `dur` seconds: the realm sky over the area's own, her fog and light; for Mika petals falling over the
## whole arena. Blended in and back out.
func _domain_on(dur: float) -> void:
	var we: WorldEnvironment = null
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		we = n
		break
	if we == null or we.environment == null:
		return
	var env := we.environment
	var saved_sky := env.sky
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sky/realm_sky.gdshader")
	var base_m: Material = saved_sky.sky_material if saved_sky else null
	if base_m is PanoramaSkyMaterial:
		m.set_shader_parameter("day_pano", (base_m as PanoramaSkyMaterial).panorama)
		m.set_shader_parameter("night_pano", (base_m as PanoramaSkyMaterial).panorama)
		m.set_shader_parameter("mixk", 0.0)
	elif base_m is ShaderMaterial:
		var sm := base_m as ShaderMaterial
		for pn in ["day_pano", "night_pano", "mixk", "day_energy", "night_energy"]:
			var v = sm.get_shader_parameter(pn)
			if v != null:
				m.set_shader_parameter(pn, v)
		if sm.get_shader_parameter("night_pano") == null and sm.get_shader_parameter("pano") != null:
			m.set_shader_parameter("day_pano", sm.get_shader_parameter("pano"))
			m.set_shader_parameter("night_pano", sm.get_shader_parameter("pano"))
	if ResourceLoader.exists("res://assets/sky/eso_milky_way/eso0932a_6000x3000.jpg"):
		m.set_shader_parameter("galaxy", load("res://assets/sky/eso_milky_way/eso0932a_6000x3000.jpg"))
		m.set_shader_parameter("galaxy_rot", Basis(Vector3(1, 0, 0), deg_to_rad(-62.0)) * Basis(Vector3(0, 1, 0), deg_to_rad(35.0)))
	m.set_shader_parameter("realm", 0 if who == "mika" else 1)
	m.set_shader_parameter("ice", Vector3(1.0, 0.62, 0.86))          # (Mika's night: pink, not the old ice blue)
	var c_pos := sim.d.pos(who)
	var o_pos := sim.d.pos(other)
	m.set_shader_parameter("origin_dir", (c_pos - o_pos + Vector3.UP * 4.0).normalized())
	m.set_shader_parameter("moon_dir", (o_pos - c_pos + Vector3.UP * 9.0).normalized())
	m.set_shader_parameter("realm_k", 0.0)
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	_domain = {"env": env, "sky": saved_sky, "mat": m}
	# her light over the world (no fog: the old domain's fog turned the frame milky), back by the end
	var sv := [env.ambient_light_color, env.ambient_light_energy, env.adjustment_enabled, env.adjustment_brightness, env.ambient_light_source]
	var amb: Color = (GRADE[who][0] as Color).lerp(Color.WHITE, 0.35)
	env.adjustment_enabled = true
	# (the ambient light from a colour, not the sky: the eclipse sky would put the whole world in the dark)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = sv[0]
	env.ambient_light_energy = maxf(float(sv[1]), 0.55)
	var twe := create_tween()
	twe.tween_property(env, "ambient_light_color", amb, 0.6)
	twe.parallel().tween_property(env, "adjustment_brightness", float(sv[3]) * 0.88, 0.6)
	twe.tween_interval(maxf(dur - 1.4, 0.5))
	twe.tween_property(env, "ambient_light_color", sv[0], 0.8)
	twe.parallel().tween_property(env, "adjustment_brightness", float(sv[3]), 0.8)
	twe.parallel().tween_property(env, "ambient_light_energy", sv[1], 0.8)
	twe.tween_callback(func():
		env.adjustment_enabled = bool(sv[2])
		env.ambient_light_source = sv[4])
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("realm_k", v), 0.0, 1.0, 0.8)
	if who == "luna":
		tw.parallel().tween_method(func(v: float): m.set_shader_parameter("eclipse", v), 0.0, 1.0, 1.6)
	tw.tween_interval(maxf(dur - 1.6, 0.5))
	tw.tween_method(func(v: float): m.set_shader_parameter("realm_k", v), 1.0, 0.0, 0.8)
	tw.tween_callback(func(): env.sky = saved_sky)
	if who == "mika":
		_petal_fall(dur)
		_petal_rain(dur)


## The petal rain sheet over the whole screen through Mika's domain (FX_Cinematic_v1 mika_petal_rain: full frame,
## no edge fade), added, looping at 16 fps, eased in and out.
func _petal_rain(dur: float) -> void:
	if not FlipbookFX.enabled():
		return
	_rain = CanvasLayer.new()
	_rain.layer = 85                                  # (under ScreenFX's 90: the grade and the impact frames are on top)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = """shader_type canvas_item;
render_mode blend_add;
uniform sampler2D sheet : source_color, filter_linear_mipmap;
uniform float frame = 0.0;
uniform float k = 0.0;
void fragment() {
	float i = mod(floor(frame), 64.0);
	vec2 c = vec2(mod(i, 8.0), floor(i / 8.0));
	vec2 uv = vec2(UV.x, UV.y * (SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y) * (16.0 / 9.0) * 0.5625 / 0.5625);
	vec3 col = texture(sheet, (c + fract(UV)) / 8.0).rgb;
	float l = max(col.r, max(col.g, col.b));
	COLOR = vec4(col * smoothstep(0.1, 0.2, l) * k * 0.8, 1.0);
}"""
	m.set_shader_parameter("sheet", load(FlipbookFX.SHEETS["mika_petal_rain"]))
	r.material = m
	_rain.add_child(r)
	d.get_tree().root.add_child(_rain)
	var t0r := Time.get_ticks_msec()
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("k", v), 0.0, 1.0, 0.6)
	tw.tween_interval(maxf(dur - 1.4, 0.4))
	tw.tween_method(func(v: float): m.set_shader_parameter("k", v), 1.0, 0.0, 0.8)
	tw.tween_callback(func(): _rain.queue_free())
	r.set_process(true)
	var step := func():
		if is_instance_valid(m):
			m.set_shader_parameter("frame", float(Time.get_ticks_msec() - t0r) / 1000.0 * 16.0)
	_rain_step = step


var _rain_step: Callable


## Petals falling over the whole arena through her domain (a wide box above the fight, slow, swaying).
func _petal_fall(dur: float) -> void:
	var g := GPUParticles3D.new()
	g.amount = 2600
	g.lifetime = 5.0
	g.preprocess = 4.0
	g.local_coords = false
	g.visibility_aabb = AABB(Vector3(-20, -12, -20), Vector3(40, 24, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 0.5, 13)
	pm.direction = Vector3(0.2, -1, 0.1)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0.15, -0.35, 0.05)
	pm.angular_velocity_min = -180.0
	pm.angular_velocity_max = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 1.6
	pm.scale_max = 3.2
	# (the petal material reads COLOR as sparkle, colour variant, fade, shown)
	var cr := Gradient.new()
	cr.set_color(0, Color(0.5, 0.1, 1.0, 1.0))
	cr.set_color(1, Color(0.5, 0.95, 1.0, 1.0))
	var ct := GradientTexture1D.new()
	ct.gradient = cr
	pm.color_initial_ramp = ct
	g.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.068)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/magic/petal.gdshader")
	q.material = mat
	g.draw_pass_1 = q
	g.top_level = true
	d.main.add_child(g)
	g.global_position = (sim.d.pos(who) + sim.d.pos(other)) * 0.5 + Vector3.UP * 9.0
	_nodes.append(g)
	sim.at(maxf(dur - 1.0, 0.5), func():
		if is_instance_valid(g):
			g.emitting = false)
	sim.at(dur + 4.0, func():
		if is_instance_valid(g):
			g.queue_free())


# ------------------------------------------------------------------------------------------------ frame and end
func _process(delta: float) -> void:
	if _rain_step.is_valid():
		_rain_step.call()
	if _halo and is_instance_valid(_halo):
		_halo.global_position = _halo_at()
		_halo_mat.set_shader_parameter("spin", sim.t * 0.35 if sim else 0.0)
	_blades_step(delta)


func _end() -> void:
	for n in _nodes:
		if n == null or not is_instance_valid(n):
			continue
		if not (n is GPUParticles3D):
			(n as Node).queue_free()
	if sim.get("ult_kit") == self:
		sim.set("ult_kit", null)
	queue_free()
