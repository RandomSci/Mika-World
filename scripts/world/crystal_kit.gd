class_name CrystalKit
extends RefCounted
## Mineral crystals for the Crystal Caverns: clusters of hexagonal prisms with pointed terminations growing out of
## rock at angles (big ones in the middle, a spray of small ones round them), drawn with shaders/world/crystal.gdshader
## (refraction of what is behind, inner glow toward the tip, sharp glints). Vertex colour R = height along each
## crystal (0 base .. 1 tip) for the shader.

static var _mats := {}


static func mat(tint: Color, core: Color, glow := 1.6) -> ShaderMaterial:
	var key := "%s|%s|%.2f" % [tint.to_html(), core.to_html(), glow]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/world/crystal.gdshader")
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("core", core)
		m.set_shader_parameter("glow", glow)
		_mats[key] = m
	return _mats[key]


## One crystal (hexagonal prism + pyramid tip) along +Y from the origin into SurfaceTool `st`, transformed by xf.
static func _crystal(st: SurfaceTool, xf: Transform3D, r: float, h: float, tip: float, rng: RandomNumberGenerator) -> void:
	var sides := 6
	var ring0 := []
	var ring1 := []
	for i in sides:
		var a := TAU * i / sides + rng.randf_range(-0.08, 0.08)
		var rr := r * rng.randf_range(0.85, 1.12)
		ring0.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
		ring1.append(Vector3(cos(a) * rr * 0.96, h, sin(a) * rr * 0.96))
	var apex := Vector3(rng.randf_range(-0.15, 0.15) * r, h + tip, rng.randf_range(-0.15, 0.15) * r)
	for i in sides:
		var j := (i + 1) % sides
		# side facet (flat-shaded: one normal per facet)
		var q := [ring0[i], ring0[j], ring1[j], ring1[i]]
		var hs := [0.0, 0.0, h / (h + tip), h / (h + tip)]
		var n := ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[3] as Vector3) - (q[0] as Vector3)).normalized()
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(Color(hs[k], 0, 0))
			st.set_normal(xf.basis * -n)
			st.add_vertex(xf * (q[k] as Vector3))
		# tip facet
		var t := [ring1[i], ring1[j], apex]
		var nt := ((t[1] as Vector3) - (t[0] as Vector3)).cross((t[2] as Vector3) - (t[0] as Vector3)).normalized()
		for k in [0, 2, 1]:
			st.set_color(Color(1.0 if k == 2 else h / (h + tip), 0, 0))
			st.set_normal(xf.basis * -nt)
			st.add_vertex(xf * (t[k] as Vector3))


## A cluster at `at` growing along `up` (a floor cluster: UP; a ceiling one: DOWN; a wall one: sideways).
static func cluster(parent: Node3D, at: Vector3, up: Vector3, size: float, tint: Color, core: Color, seed: int, count := 9, glow := 1.6) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Basis(Quaternion(Vector3.UP, up.normalized())) if up.normalized().dot(Vector3.UP) > -0.999 else Basis(Vector3.RIGHT, PI)
	for i in count:
		var big := i < 2
		var h := size * (rng.randf_range(0.8, 1.2) if big else rng.randf_range(0.18, 0.6))
		var r := h * rng.randf_range(0.11, 0.17)
		var tilt := rng.randf_range(0.0, 0.25 if big else 0.75)
		var yaw := rng.randf() * TAU
		var off := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * (0.0 if i == 0 else rng.randf_range(0.2, 0.75) * size * 0.4)
		var b := base * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
		_crystal(st, Transform3D(b, base * off - base * Vector3(0, r * 0.6, 0)), r, h, r * rng.randf_range(1.4, 2.4), rng)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat(tint, core, glow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	parent.add_child(mi)
	return mi
