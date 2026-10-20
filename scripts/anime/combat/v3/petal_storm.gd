class_name PetalStorm
extends Node3D
## The petal storm (2026-10-20, Selwyn: the effect of a Bankai of cherry blossoms, "research ... and apply it"): our
## own take on that technique. Thousands of glowing petal-blades (shaders/magic/petal_storm + petal) moving as one
## living mass, each girl's storm in sakura pink with her own colour on the rims (ice blue Mika, violet Luna).
## Techniques, each flowing out of the last (the shader blends two shapes):
##   gather(at_fn, dur)                   petals spiral into her hand as she makes the sign, tighter and tighter
##   river(from_fn, to_fn, dur)           at the release, three ribbons pour from her hand along a curve to the target
##   engulf(at_fn, r, dur)                a churning sphere round the target, crushing inward at the end
##   shield(at_fn, r, dur)                the petals wrap round her body
##   scatter(at_fn, r, dur)               bursting out and drifting away (an impact, the end of a technique)
##   comets(from_fn, pts_fn, dur, ...)    up to 12 petal comets, each to its own target at its own launch time
##   columns(pts_fn, dur, ...)            spiralling petal pillars erupting from the ground, one after another
##   tide(from_fn, to_fn, dur, ...)       a curling wall of petals rolling along the ground
##   cascade(at_fn, height, dur, ...)     a funnel of petals pouring down from the sky
##   ripple(at_fn, r, dur)                a ring of petals skimming out over the ground (the ground's answer)
##   stream(from_fn, to_fn, dur, ...)     a continuous torrent held from her hand to the target (a beam)
## The storm carries its own light (following the mass) and never goes under the ground (ground(y)).
## Positions are callables read every frame (her hand, the other girl's chest), so the storm follows the living bodies.

const COUNT := 2400

var who := "mika"
var parts: GPUParticles3D
var haze: GPUParticles3D
var sparks: GPUParticles3D
var mat: ShaderMaterial
var _mats: Array = []                      # the shape material of every layer (petals, sparkles, glow)
var _trails: Array = []                    # GPUTrail ribbons on the lead stream
var fore_parts: GPUParticles3D
var _fore_mat: ShaderMaterial
var _fore_shown := 0.0
var _steps: Array = []                    # queued techniques [kind, args, dur]
var _cur := {}
var _clock := 0.0
var _k := 1.0
var _free_after := -1.0
var light: OmniLight3D
var light_k := 1.0                            # her light's strength for this storm (0 for none)
var _light_e := 0.0
var _idle := 0.0


static func make(host: Node, girl: String, count := COUNT) -> PetalStorm:
	var s := PetalStorm.new()
	s.who = girl
	s.name = "PetalStorm_" + girl
	host.add_child(s)
	s._build(count)
	return s


func _build(count: int) -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var aabb := AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))
	# the petals
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/magic/petal_storm.gdshader")
	_mats.append(mat)
	parts = _layer(count, mat, aabb)
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.068)
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/magic/petal.gdshader")
	pm.set_shader_parameter("rim", Vector3(0.55, 0.85, 1.0) if who == "mika" else Vector3(0.72, 0.45, 1.0))
	if who == "luna":
		pm.set_shader_parameter("deep", Vector3(0.9, 0.38, 0.72))
	q.material = pm
	parts.draw_pass_1 = q
	# the sparkles: tiny bright points riding a tenth of the petals (Kenney particle pack, CC0, flare_01)
	_mats.append(_layer_mat(1))
	sparks = _layer(maxi(count / 10, 40), _mats[1], aabb)
	var sq := QuadMesh.new()
	sq.size = Vector2(0.09, 0.09)
	sq.material = _sprite_mat(load("res://assets/vfx/kenney/flare_01.png"), Color(1.7, 1.45, 1.6), 0.0)
	sparks.draw_pass_1 = sq
	# the glow: soft round light riding an eighth of the petals, building where the swarm is densest (circle_05)
	_mats.append(_layer_mat(2))
	haze = _layer(maxi(count / 8, 60), _mats[2], aabb)
	var hq := QuadMesh.new()
	hq.size = Vector2(0.6, 0.6)
	hq.material = _sprite_mat(load("res://assets/vfx/kenney/circle_05.png"),
		(Color(1.0, 0.4, 0.66) if who == "luna" else Color(1.0, 0.48, 0.72)) * Color(0.13, 0.13, 0.13, 1.0), 1.2)
	haze.draw_pass_1 = hq
	_p("visible_frac", 0.0)
	for u in ["center", "a", "b", "c"]:
		_p(u, Vector3.ZERO)
	_p("prog", 0.0)
	# one pink light riding the densest part of the swarm, so the ground and the girls catch the petals' light
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.56, 0.78)
	light.omni_range = 5.5
	light.omni_attenuation = 1.6
	light.light_energy = 0.0
	light.light_specular = 0.25
	light.shadow_enabled = false
	add_child(light)


func _layer(n: int, pmat: ShaderMaterial, aabb: AABB) -> GPUParticles3D:
	var g := GPUParticles3D.new()
	g.amount = n
	g.lifetime = 600.0
	g.explosiveness = 1.0
	g.local_coords = false
	g.visibility_aabb = aabb
	g.process_material = pmat
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	g.emitting = true
	return g


func _layer_mat(layer: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = mat.shader
	m.set_shader_parameter("layer", layer)
	return m


## A soft sprite facing the camera, added (black is nothing), its brightness from the storm's COLOR, fading out near
## the lens (`near` metres).
func _sprite_mat(tex: Texture2D, col: Color, near: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.albedo_color = col
	m.disable_receive_shadows = true
	if near > 0.0:
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = near
		m.distance_fade_max_distance = near * 2.5
	return m


## Sets a shape parameter on every layer (they all ride the same shape).
func _p(name: String, v) -> void:
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter(name, v)


## A few large petals drifting between the camera and the technique (depth); they fade in with it and out at its end.
func fore(n := 22) -> PetalStorm:
	_fore_mat = ShaderMaterial.new()
	_fore_mat.shader = load("res://shaders/magic/petal_fore.gdshader")
	fore_parts = _layer(n, _fore_mat, AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800)))
	fore_parts.draw_pass_1 = parts.draw_pass_1
	return self


func _fore_step(dt: float) -> void:
	if _fore_mat == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c: Vector3 = mat.get_shader_parameter("center")
	if not c.is_finite():
		return
	var want := 0.0 if _cur.is_empty() or (String(_cur.kind) == "scatter" and float(_cur.t) / float(_cur.dur) > 0.5) else 1.0
	_fore_shown = move_toward(_fore_shown, want, dt * 2.0)
	_fore_mat.set_shader_parameter("cam_pos", cam.global_position)
	_fore_mat.set_shader_parameter("focus", c)
	_fore_mat.set_shader_parameter("tclock", _clock)
	_fore_mat.set_shader_parameter("shown", _fore_shown)


## GPUTrail ribbons on the lead stream (river, stream, comets, tide): `n` ribbons spiralling round the head.
func ribbons(n := 3) -> PetalStorm:
	for i in n:
		var tr := GPUTrail3D.new()
		tr.name = "Ribbon%d" % i
		tr.top_level = true
		add_child(tr)
		tr.fixed_fps = 30
		tr.length = 14
		var ramp := GradientTexture1D.new()
		var gr := Gradient.new()
		gr.set_color(0, Color(1.6, 1.25, 1.45, 0.0))
		gr.set_color(1, Color(1.9, 1.5, 1.7, 0.85))
		gr.add_point(0.6, Color(1.2, 0.6, 0.9, 0.45))
		ramp.gradient = gr
		ramp.use_hdr = true
		tr.color_ramp = ramp
		_trails.append(tr)
	return self


## The petals' size (1 = a real petal; the big techniques, seen from far, use bigger ones).
func petal_size(k: float) -> PetalStorm:
	_p("size", k)
	return self


## The ground under the technique: no petal goes below it.
func ground(y: float) -> PetalStorm:
	_p("ground_y", y)
	return self


## Queue a technique (they play in order; the first starts at once).
func play(kind: String, args: Dictionary, dur: float) -> PetalStorm:
	_steps.append([kind, args, dur])
	if _cur.is_empty():
		_next()
	return self


func gather(at_fn: Callable, dur: float) -> PetalStorm:
	return play("gather", {"at": at_fn}, dur)


func river(from_fn: Callable, to_fn: Callable, dur: float, arc := 1.6) -> PetalStorm:
	return play("river", {"from": from_fn, "to": to_fn, "arc": arc}, dur)


func engulf(at_fn: Callable, r: float, dur: float) -> PetalStorm:
	return play("engulf", {"at": at_fn, "r": r}, dur)


func shield(at_fn: Callable, r: float, dur: float) -> PetalStorm:
	return play("shield", {"at": at_fn, "r": r}, dur)


func scatter(at_fn: Callable, r: float, dur: float) -> PetalStorm:
	return play("scatter", {"at": at_fn, "r": r}, dur)


## pts_fn returns an Array of Vector4 (target xyz, launch delay in seconds from the step's start), at most 12.
func comets(from_fn: Callable, pts_fn: Callable, dur: float, fly := 0.4, width := 0.22, spread := 1.0, arc := 0.8) -> PetalStorm:
	return play("comets", {"from": from_fn, "pts": pts_fn, "rise": fly, "width": width, "spread": spread, "arc": arc}, dur)


## pts_fn returns an Array of Vector4 (base xyz, delay from the step's start), at most 12.
func columns(pts_fn: Callable, dur: float, height := 2.4, width := 0.4, rise := 0.22, taper := 0.45) -> PetalStorm:
	return play("columns", {"pts": pts_fn, "height": height, "width": width, "rise": rise, "taper": taper}, dur)


func tide(from_fn: Callable, to_fn: Callable, dur: float, width := 1.4, height := 1.6) -> PetalStorm:
	return play("tide", {"from": from_fn, "to": to_fn, "width": width, "height": height}, dur)


func cascade(at_fn: Callable, height: float, dur: float, width := 1.0) -> PetalStorm:
	return play("cascade", {"at": at_fn, "height": height, "width": width}, dur)


func ripple(at_fn: Callable, r: float, dur: float) -> PetalStorm:
	return play("ripple", {"at": at_fn, "r": r}, dur)


func stream(from_fn: Callable, to_fn: Callable, dur: float, width := 0.45, reach := 0.12, arc := 0.0) -> PetalStorm:
	return play("stream", {"from": from_fn, "to": to_fn, "width": width, "reach": reach, "arc": arc}, dur)


## Ends the storm after its queue (it frees itself).
func finish() -> void:
	_free_after = 0.0


const MODE := {"gather": 0, "river": 1, "engulf": 2, "shield": 3, "scatter": 4, "comets": 5, "columns": 6, "tide": 7, "cascade": 8,
	"ripple": 9, "stream": 10}
## How bright her light is in each shape (the light follows the mass).
const LIGHT := {"gather": 0.6, "river": 2.2, "engulf": 2.6, "shield": 0.7, "scatter": 1.2, "comets": 2.0, "columns": 2.4, "tide": 2.4,
	"cascade": 2.8, "ripple": 1.4, "stream": 3.0}


func _next() -> void:
	if _steps.is_empty():
		_cur = {}
		if _free_after >= 0.0:
			queue_free()
		return
	var st: Array = _steps.pop_front()
	var prev_mode: int = int(mat.get_shader_parameter("mode_b")) if not _cur.is_empty() else MODE[String(st[0])]
	_cur = {"kind": st[0], "args": st[1], "dur": maxf(float(st[2]), 0.05), "t": 0.0, "t0": _clock}
	_p("mode_a", prev_mode)
	_p("mode_b", MODE[String(st[0])])
	_k = 0.0


func _process(delta: float) -> void:
	if _cur.is_empty():
		# (nothing queued: a storm left waiting more than 2.5 s, its technique dropped, falls apart instead of hanging)
		_idle += delta
		if _idle > 2.5:
			_idle = 0.0
			var at: Vector3 = mat.get_shader_parameter("center")
			scatter(func() -> Vector3: return at, 0.9, 0.9)
			finish()
		return
	_idle = 0.0
	var dt := maxf(delta, 0.0)
	_clock += dt
	_cur.t = float(_cur.t) + dt
	var u := clampf(float(_cur.t) / float(_cur.dur), 0.0, 1.0)
	_k = minf(_k + dt / 0.25, 1.0)                   # (a change of shape flows over a quarter second)
	_p("k", _k)
	_p("tclock", _clock)
	var args: Dictionary = _cur.args
	match String(_cur.kind):
		"gather":
			_p("center", (args.at as Callable).call())
			_p("amount", u)
			_p("visible_frac", clampf(u * 0.6, 0.05, 0.35))
		"river":
			var p0: Vector3 = (args.from as Callable).call()
			var p2: Vector3 = (args.to as Callable).call()
			var mid := (p0 + p2) * 0.5
			var side := (p2 - p0).cross(Vector3.UP).normalized()
			# (a low wide sweep round to the side, not up into the trees: the river stays in the frame with both girls)
			var p1 := mid + Vector3.UP * float(args.arc) * 0.35 + side * float(args.arc) * 1.1 * (1.0 if who == "mika" else -1.0)
			_p("a", p0)
			_p("b", p1)
			_p("c", p2)
			_p("prog", u * 1.9)
			_p("trail", 0.9)
			_p("width", 0.7)
			_p("visible_frac", 0.9)
			_p("center", p0)
		"engulf":
			_p("center", (args.at as Callable).call())
			_p("radius", float(args.r) * (1.0 - 0.75 * pow(u, 3.0)))
			_p("visible_frac", 1.0)
		"shield":
			_p("center", (args.at as Callable).call())
			_p("radius", float(args.r))
			_p("visible_frac", 1.0)
		"scatter":
			_p("center", (args.at as Callable).call())
			_p("radius", float(args.r))
			_p("amount", u)
			_p("visible_frac", 1.0 - smoothstep(0.55, 1.0, u))
		"comets", "columns":
			var raw: Array = (args.pts as Callable).call()
			var pts := PackedVector4Array()
			for v in raw.slice(0, 12):
				var q: Vector4 = v
				pts.append(Vector4(q.x, q.y, q.z, float(_cur.t0) + q.w))
			while pts.size() < 12:
				pts.append(pts[pts.size() - 1] if pts.size() > 0 else Vector4())
			var ng := clampi(raw.size(), 1, 12)
			_p("pts", pts)
			_p("n_groups", ng)
			_p("rise", float(args.rise))
			_p("width", float(args.width))
			_p("visible_frac", 1.0)
			if String(_cur.kind) == "comets":
				var src0: Vector3 = (args.from as Callable).call()
				_p("a", src0)
				_p("spread", float(args.spread))
				_p("arc_h", float(args.arc))
				# her light rides the comets' heads (their mean)
				var head := Vector3.ZERO
				for i in ng:
					var q2: Vector4 = pts[i]
					var f2 := clampf((_clock - q2.w) / maxf(float(args.rise), 0.02), 0.0, 1.0)
					head += src0.lerp(Vector3(q2.x, q2.y, q2.z), f2)
				_p("center", head / float(ng))
			else:
				_p("height", float(args.height))
				_p("taper", float(args.taper))
				var c2 := Vector3.ZERO
				for i in ng:
					c2 += Vector3(pts[i].x, pts[i].y, pts[i].z)
				_p("center", c2 / float(ng) + Vector3.UP * float(args.height) * 0.4)
		"tide", "stream":
			var p0t: Vector3 = (args.from as Callable).call()
			var p2t: Vector3 = (args.to as Callable).call()
			var p1t := (p0t + p2t) * 0.5 + Vector3.UP * float(args.get("arc", 0.0))
			_p("a", p0t)
			_p("b", p1t)
			_p("c", p2t)
			_p("width", float(args.width))
			if String(_cur.kind) == "tide":
				_p("prog", u * 1.25)
				_p("trail", 0.45)
				_p("height", float(args.height))
				_p("visible_frac", 1.0)
				_p("center", p0t.lerp(p2t, clampf(u * 1.25, 0.0, 1.0)) + Vector3.UP * float(args.height) * 0.5)
			else:
				# the front reaches the target in `reach` seconds, then the torrent holds
				var fr := clampf(float(_cur.t) / maxf(float(args.reach), 0.02), 0.0, 1.0)
				_p("prog", fr)
				_p("flow", 1.6)
				_p("visible_frac", 1.0 if u < 0.85 else 1.0 - smoothstep(0.85, 1.0, u))
				_p("center", p0t.lerp(p2t, fr * 0.7))
		"cascade":
			_p("center", (args.at as Callable).call())
			_p("height", float(args.height))
			_p("width", float(args.width))
			_p("amount", clampf(u * 1.6, 0.0, 1.0))
			_p("visible_frac", 1.0)
		"ripple":
			_p("center", (args.at as Callable).call())
			_p("radius", float(args.r))
			_p("amount", u)
			_p("visible_frac", 1.0 - smoothstep(0.6, 1.0, u))
	_light_step(dt, u)
	_fore_step(dt)
	if u >= 1.0:
		_next()


## Her light follows the storm's mass: up as a shape forms, down as it ends. The ribbons ride the lead stream's head.
func _light_step(dt: float, u: float) -> void:
	if light == null:
		return
	var kind := String(_cur.kind)
	var want: float = float(LIGHT.get(kind, 1.5)) * light_k
	if kind == "scatter" or kind == "ripple":
		want *= 1.0 - u
	_light_e = lerpf(_light_e, want, clampf(dt * 10.0, 0.0, 1.0))
	light.light_energy = _light_e
	var c: Vector3 = _gv("center")
	var head := c
	var a0: Vector3 = _gv("a")
	var b0: Vector3 = _gv("b")
	var c0: Vector3 = _gv("c")
	var pr := clampf(_g("prog", 0.0), 0.0, 1.0)
	var wid := _g("width", 0.0)
	match kind:
		"river", "tide":
			head = a0.lerp(b0, pr).lerp(b0.lerp(c0, pr), pr)
			c = head
			if kind == "tide":
				head += Vector3.UP * _g("height", 0.0) * 0.5
		"stream":
			head = a0.lerp(b0, pr).lerp(b0.lerp(c0, pr), pr)
		"comets":
			var pts_v = mat.get_shader_parameter("pts")
			var pts: PackedVector4Array = pts_v if pts_v is PackedVector4Array else PackedVector4Array()
			if pts.size() > 0:
				var f := clampf((_clock - pts[0].w) / maxf(_g("rise", 0.0), 0.02), 0.0, 1.0)
				var tgt := Vector3(pts[0].x, pts[0].y, pts[0].z)
				head = a0.lerp(tgt, f) + Vector3.UP * _g("arc_h", 0.0) * 4.0 * f * (1.0 - f)
	if c.is_finite():
		light.global_position = c
	if not _trails.is_empty() and head.is_finite():
		_ribbons_step(head, maxf(wid * 0.8, 0.15) if kind in ["river", "stream", "comets", "tide"] else 0.25)


var _head_prev := Vector3.INF


## A shape parameter as a float (a uniform never set reads as null).
func _g(name: String, dflt: float) -> float:
	var v = mat.get_shader_parameter(name)
	return float(v) if v != null else dflt


func _gv(name: String) -> Vector3:
	var v = mat.get_shader_parameter(name)
	return v if v is Vector3 else Vector3.ZERO


func _ribbons_step(head: Vector3, r: float) -> void:
	var tg := (head - _head_prev) if _head_prev.is_finite() else Vector3.FORWARD
	_head_prev = head
	if tg.length() < 1e-4:
		tg = Vector3.FORWARD
	tg = tg.normalized()
	var sd := tg.cross(Vector3.UP)
	sd = sd.normalized() if sd.length() > 1e-3 else Vector3.RIGHT
	var up := sd.cross(tg).normalized()
	var cam := get_viewport().get_camera_3d()
	for i in _trails.size():
		var tr: GPUTrail3D = _trails[i]
		var ang := _clock * 8.0 + TAU * float(i) / float(_trails.size())
		var p := head + (sd * cos(ang) + up * sin(ang)) * r
		# the ribbon is flat across its motion, facing the camera (its width is the node's Y axis)
		var view := (cam.global_position - p).normalized() if cam else Vector3.UP
		var wy := tg.cross(view)
		wy = wy.normalized() if wy.length() > 1e-3 else up
		var xb := wy.cross(view).normalized()
		tr.global_transform = Transform3D(Basis(xb, wy * 0.04, view), p)
