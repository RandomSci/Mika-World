class_name FoliageBuilder
extends RefCounted
## Original plant geometry grown at load time (Milestone K environment pass): hanging vines, ivy mats on walls,
## weeping-willow curtains, exposed roots, stumps, fallen logs and drifting leaves. Every leaf card maps to one of
## the painted leaf sprites in the nature kit's `Leaves.png` atlas (CC0) and is shaded by our stylized foliage
## shader (wind, translucency), so grown plants match the placed ones. One mesh per curtain / mat / root cluster.

const LEAF_TEX := "Leaves.png"
# sprite rectangles in the atlas (u0, v0, u1, v1)
const SPR_THIN := Rect2(0.058, 0.04, 0.137, 0.39)
const SPR_ROUND := Rect2(0.80, 0.06, 0.177, 0.21)
const SPR_HEART := Rect2(0.80, 0.29, 0.177, 0.26)
const SPR_FERN := Rect2(0.02, 0.45, 0.27, 0.53)
const SPR_BROAD := Rect2(0.33, 0.59, 0.24, 0.39)


static func leaf_mat(crown := "plant", center := Vector3.ZERO, bottom := 0.0, top := 1.0, wind := 0.08) -> ShaderMaterial:
	var pal: Dictionary = NatureKit.CROWNS.get(crown, NatureKit.CROWNS["plant"])
	# hanging growth has no dark inner crown: a shallow gradient, lit from the sprite's own colour
	var top_c: Color = pal.top
	var bot_c: Color = (pal.top as Color).lerp(pal.bottom, 0.45)
	return Kit.shader_mat("res://shaders/nature/stylized_foliage.gdshader", {"albedo_tex": NatureKit.tex(LEAF_TEX),
		"tint_top": top_c, "tint_bottom": bot_c, "translucency_color": pal.trans, "canopy_center": center,
		"canopy_radius": 3.0, "canopy_bottom": bottom, "canopy_top": top, "spherize": 0.25, "translucency": 0.9,
		"tint_texture_mix": Vector4(0.7, 0, 0, 0), "wind_strength": wind, "flutter": 0.012, "alpha_cut": 0.45, "variation_strength": 0.15, "two_sided": 1.0})


static func bark_mat(dead := false) -> ShaderMaterial:
	return Kit.shader_mat("res://shaders/nature/stylized_bark.gdshader", {"albedo_tex": NatureKit.tex("Bark_%s.png" % ("DeadTree" if dead else "TwistedTree")),
		"normal_tex": NatureKit.tex("Bark_%s_Normal.png" % ("DeadTree" if dead else "TwistedTree")),
		"tint": Color(0.7, 0.68, 0.72) if dead else Color(0.78, 0.74, 0.7), "canopy_bottom": 0.0, "canopy_top": 1.0, "wind_strength": 0.0, "moss_amount": 0.6})


# ------------------------------------------------------------------ cards
## One double-visible leaf card (two triangles) at `c`, spanning `right` (width) and `up` (height), sprite `spr`.
static func _card(st: SurfaceTool, c: Vector3, right: Vector3, up: Vector3, spr: Rect2, n: Vector3) -> void:
	var p00 := c - right * 0.5
	var p10 := c + right * 0.5
	var p01 := c - right * 0.5 + up
	var p11 := c + right * 0.5 + up
	var uv00 := Vector2(spr.position.x, spr.end.y)   # sprite bottom at the card base
	var uv10 := Vector2(spr.end.x, spr.end.y)
	var uv01 := Vector2(spr.position.x, spr.position.y)
	var uv11 := Vector2(spr.end.x, spr.position.y)
	for tri in [[p00, uv00, p10, uv10, p11, uv11], [p00, uv00, p11, uv11, p01, uv01]]:
		for k in [0, 2, 4]:
			st.set_normal(n)
			st.set_uv(tri[k + 1])
			st.add_vertex(tri[k])


## A hanging strand: leaf cards stepping down from `top` along a slight curve; each card is a thin leaf
## alternating left/right of the stem. `out` = direction the curtain faces (away from the wall / toward the water).
static func _strand(st: SurfaceTool, top: Vector3, length: float, out: Vector3, rng: RandomNumberGenerator, spr := SPR_THIN, card := 0.42, swing := 0.35) -> void:
	var side := out.cross(Vector3.UP).normalized()
	var n := int(ceil(length / (card * 0.5)))
	var drift := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.08
	var p := top
	for i in n:
		var t := float(i) / maxf(n - 1, 1)
		# the strand bows outward a little at mid-length, then hangs straight
		var bow := out * sin(t * PI) * swing * 0.5 + drift * t
		var c := p + bow
		var s := card * rng.randf_range(0.8, 1.15)
		var ang := rng.randf_range(-0.9, 0.9)
		var r := (side * cos(ang) + out * sin(ang)) * s * 0.5 * (1.0 if i % 2 == 0 else -1.0)
		var u := Vector3(0, -s, 0) + out * rng.randf_range(-0.05, 0.12)
		_card(st, c + Vector3(0, s * 0.1, 0) + side * rng.randf_range(-0.08, 0.08), r, u, spr, (out + Vector3(0, 0.3, 0)).normalized())
		p += Vector3(0, -card * 0.5, 0)


# ------------------------------------------------------------------ builders
## Vines hanging from a set of anchor points (e.g. along a wall top or an arch), lengths in metres [min, max].
static func vine_curtain(parent: Node3D, anchors: Array, lengths: Vector2, out: Vector3, rng: RandomNumberGenerator, crown := "plant", name := "Vines") -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ymax := -INF
	var ymin := INF
	var cen := Vector3.ZERO
	for a in anchors:
		var top: Vector3 = a
		var L := rng.randf_range(lengths.x, lengths.y)
		_strand(st, top, L, out, rng)
		ymax = maxf(ymax, top.y)
		ymin = minf(ymin, top.y - L)
		cen += top
	cen /= maxf(anchors.size(), 1)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = leaf_mat(crown, cen - out * 2.5 - Vector3(0, (ymax - ymin) * 0.5, 0), ymax, ymin, 0.1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## An ivy mat clinging to a wall face: overlapping heart leaves on a grid, a few centimetres off the surface,
## thinning toward the top and the edges (ivy climbs from the ground). `origin` = bottom-left of the face.
static func ivy_sheet(parent: Node3D, origin: Vector3, right: Vector3, up: Vector3, w: float, h: float, rng: RandomNumberGenerator, cover := 0.75, name := "Ivy") -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := right.cross(up).normalized()
	var step := 0.22
	var y := 0.0
	while y < h:
		var x := 0.0
		while x < w:
			var fx := x / w
			var fy := y / h
			# coverage: dense low and in the middle, broken toward the top and the sides
			var k := cover * (1.0 - fy * fy) * (0.55 + 0.45 * sin(fx * PI)) * (0.7 + 0.3 * sin(x * 3.1 + y * 2.3))
			if rng.randf() < k:
				var c := origin + right * (x + rng.randf_range(-0.06, 0.06)) + up * (y + rng.randf_range(-0.06, 0.06)) + n * rng.randf_range(0.03, 0.09)
				var s := rng.randf_range(0.26, 0.42)
				var ang := rng.randf_range(-0.6, 0.6)
				var r := (right * cos(ang) + up * sin(ang)) * s
				var u := (up * cos(ang) - right * sin(ang)) * s * 1.1 - n * 0.02
				_card(st, c, r, u, SPR_HEART, (n + up * 0.2).normalized())
			x += step
		y += step
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = leaf_mat("plant", origin + right * w * 0.5 - n * 1.5, origin.y, origin.y + h, 0.03)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A weeping willow's curtain: long thin-leaf strands hanging from points around a crown, longest on the
## `lean` side (over the water). The crown itself is one of the kit's twisted trees placed by the caller.
static func willow_curtain(parent: Node3D, crown: Vector3, radius: float, count: int, lengths: Vector2, lean: Vector3, rng: RandomNumberGenerator, name := "Willow") -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ymin := INF
	for i in count:
		var ang := TAU * i / count + rng.randf_range(-0.2, 0.2)
		var rr := radius * rng.randf_range(0.55, 1.05)
		var top := crown + Vector3(cos(ang) * rr, rng.randf_range(-radius * 0.35, radius * 0.25), sin(ang) * rr)
		var out := Vector3(cos(ang), 0, sin(ang))
		var toward := clampf(out.dot(lean) * 0.5 + 0.5, 0.0, 1.0)
		var L := lerpf(lengths.x, lengths.y, toward) * rng.randf_range(0.75, 1.1)
		_strand(st, top, L, out, rng, SPR_THIN, 0.5, 0.25)
		ymin = minf(ymin, top.y - L)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = leaf_mat("twisted", crown, crown.y + radius * 0.3, ymin, 0.14)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


## Exposed roots radiating from a trunk base: tapered cones bowing over the ground (partly sunk).
static func roots(parent: Node3D, base: Vector3, trunk_r: float, count: int, length: Vector2, rng: RandomNumberGenerator, ground: Callable, dead := false, name := "Roots") -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var ang := TAU * i / count + rng.randf_range(-0.35, 0.35)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var L := rng.randf_range(length.x, length.y)
		var segs := 7
		var sides := 7
		var prev: Array = []
		for s in segs + 1:
			var t := float(s) / segs
			var d := trunk_r * 0.6 + L * t
			var p := base + dir * d
			var gy: float = ground.call(p.x, p.z)
			# leaves the trunk a little above ground, bows up, then dives under
			var y := lerpf(base.y + trunk_r * 0.55, gy - 0.35, smoothstep(0.0, 1.0, t)) + sin(t * PI) * 0.18
			var r := lerpf(trunk_r * 0.42, 0.03, t) * rng.randf_range(0.9, 1.1)
			var ring := []
			var side := dir.cross(Vector3.UP).normalized()
			for k in sides:
				var a := TAU * k / sides
				ring.append(Vector3(p.x, y, p.z) + (side * cos(a) + Vector3.UP * sin(a)) * r)
			if not prev.is_empty():
				for k in sides:
					var a0: Vector3 = prev[k]
					var a1: Vector3 = prev[(k + 1) % sides]
					var b0: Vector3 = ring[k]
					var b1: Vector3 = ring[(k + 1) % sides]
					var cen := (a0 + a1 + b0 + b1) * 0.25
					var axis := Vector3(p.x, y, p.z)
					var nrm := (cen - axis).normalized()
					for v in [a0, b0, b1, a0, b1, a1]:
						st.set_normal(nrm)
						st.set_uv(Vector2(v.x + v.z, v.y) * 0.5)
						st.add_vertex(v)
			prev = ring
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = bark_mat(dead)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


## A sawn / broken stump: flared base, slightly hollowed top with a lighter heartwood disc.
static func stump_mesh(radius: float, height: float, seed := 1) -> ArrayMesh:
	var key := "stump:%s:%s:%s" % [radius, height, seed]
	if Kit._meshes.has(key):
		return Kit._meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var prof := [Vector2(radius * 1.45, 0.0), Vector2(radius * 1.25, height * 0.12), Vector2(radius * 1.05, height * 0.45),
		Vector2(radius * rng.randf_range(0.95, 1.08), height), Vector2(radius * 0.8, height * rng.randf_range(0.9, 0.98)), Vector2(0.0, height * 0.92)]
	var m := Kit.lathe(prof, 11, true, true)
	Kit._meshes[key] = m
	return m


## Slow drifting leaves (ambient motion under the canopy): small two-tone leaf quads tumbling down.
static func leaf_fall(parent: Node3D, pos: Vector3, amount := 18) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.randomness = 0.6
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-9, -9, -9), Vector3(18, 18, 18))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(7.0, 1.0, 7.0)
	pm.direction = Vector3(0.3, -1, 0.1)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, -0.35, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.5
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.6
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.2
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.85, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	var cg := Gradient.new()
	cg.colors = PackedColorArray([Color(0.55, 0.62, 0.22), Color(0.78, 0.6, 0.2), Color(0.5, 0.7, 0.3)])
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	pm.color_initial_ramp = cgt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.16)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = NatureKit.tex(LEAF_TEX)
	m.uv1_scale = Vector3(SPR_ROUND.size.x, SPR_ROUND.size.y, 1.0)
	m.uv1_offset = Vector3(SPR_ROUND.position.x, SPR_ROUND.position.y, 0.0)
	m.roughness = 0.9
	m.backlight_enabled = true
	m.backlight = Color(0.5, 0.7, 0.3)
	q.material = m
	p.draw_pass_1 = q
	parent.add_child(p)
	return p
