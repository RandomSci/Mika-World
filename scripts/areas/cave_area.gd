class_name CaveArea
extends KitArea
## A CRYSTAL CAVERNS area on the realistic toolkit (world-quality gate): a real cave, not a box. The ground is a
## floor heightfield (photographic scree / rock / trodden path, wet near water) and the rock above a CEILING
## heightfield that comes down to meet it at the edges - together one closed, irregular chamber. Walls and roof are
## photoscanned rock (triplanar, seeping wet streaks); stalactites hang from the roof and stalagmites rise from the
## floor; crystal clusters (CrystalKit) light it. Deep under rock the sky's light does not reach (vertex alpha =
## occlusion of indirect light), so a cave is dark except where crystals, lamps or the mouth light it.
## Subclasses define: floor_h(x, z), ceil_h(x, z) (<= floor_h where there is no rock overhead), trails, features()
## and links().

const SIZE := 180.0
const STEP := 1.0
const HALF := SIZE * 0.5

var trails: Array = []                 # [[points], width]
var crystal_spots: Array = []          # world positions of crystal clusters (mineral tint on the rock, lights)
var _n := 0
var _f := PackedFloat32Array()
var _c := PackedFloat32Array()
var rock_mat: ShaderMaterial


func floor_h(_x: float, _z: float) -> float:
	return 0.0


func ceil_h(x: float, z: float) -> float:
	return floor_h(x, z)


## 0 = open sky .. 1 = deep under rock (how much of the sky's ambient light is blocked).
func occlusion(x: float, z: float) -> float:
	var gap := ceil_h(x, z) - floor_h(x, z)
	return 1.0 if gap > 0.05 else 0.0


func features() -> Array:
	return []


func links() -> void:
	pass


func water_dist(_p: Vector2) -> float:
	return 999.0


# ------------------------------------------------------------------ grids
func _precompute() -> void:
	_n = int(SIZE / STEP) + 1
	_f.resize(_n * _n)
	_c.resize(_n * _n)
	for iz in _n:
		for ix in _n:
			var x := -HALF + ix * STEP
			var z := -HALF + iz * STEP
			var fy := floor_h(x, z)
			_f[iz * _n + ix] = fy
			_c[iz * _n + ix] = maxf(ceil_h(x, z), fy)


func _grid(g: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + HALF) / STEP, 0.0, _n - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, _n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	return lerpf(lerpf(g[iz * _n + ix], g[iz * _n + ix + 1], tx), lerpf(g[(iz + 1) * _n + ix], g[(iz + 1) * _n + ix + 1], tx), tz)


func height(x: float, z: float) -> float:
	return floor_h(x, z) if _f.is_empty() else _grid(_f, x, z)


func roof(x: float, z: float) -> float:
	return ceil_h(x, z) if _c.is_empty() else _grid(_c, x, z)


func ground_at(x: float, z: float) -> float:
	return height(x, z)


func trail_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 0.0
	for t in trails:
		var pts: Array = t[0]
		var w := float(t[1])
		for i in pts.size() - 1:
			var d := WhisperingWoods._seg_dist(p, pts[i], pts[i + 1])
			best = maxf(best, 1.0 - smoothstep(w * 0.35, w * 0.5 + 0.8, d))
	return best


func _mineral(x: float, z: float) -> float:
	var m := 0.0
	for c in crystal_spots:
		m = maxf(m, 1.0 - smoothstep(2.0, 9.0, Vector2(x - (c as Vector3).x, z - (c as Vector3).z).length()))
	return m


# ------------------------------------------------------------------ build
func build_steps() -> Array:
	var steps: Array = [_precompute, _floor, _ceiling, _formations]
	steps.append_array(features())
	steps.append(_links)
	return steps


func _floor() -> void:
	nav_aabb = AABB(Vector3(-HALF + 2, -40, -HALF + 2), Vector3(SIZE - 4, 120, SIZE - 4))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/real/real_terrain.gdshader")
	for pair in [["litter", "rock_wall_10"], ["floor", "stony_dirt_path"], ["path", "stony_dirt_path"], ["rock", "cliff_side"], ["bank", "rocky_terrain_02"]]:
		m.set_shader_parameter(pair[0] + "_alb", RealKit.ph_tex(pair[1], "diff"))
		m.set_shader_parameter(pair[0] + "_nrm", RealKit.ph_tex(pair[1], "nor_gl"))
	m.set_shader_parameter("moss_alb", RealKit.ph_tex("rocky_terrain_02", "diff"))
	m.set_shader_parameter("moss_nrm", RealKit.ph_tex("rocky_terrain_02", "nor_gl"))
	m.set_shader_parameter("noise_tex", Kit.noise())
	m.set_shader_parameter("tile", 0.26)
	m.set_shader_parameter("moss_amount", 0.0)        # no green carpet in a cave
	Kit.terrain(self, SIZE, STEP, height, func(x: float, z: float) -> Color:
		var wet := 1.0 - smoothstep(0.5, 4.0, water_dist(Vector2(x, z)))
		return Color(trail_at(x, z), 0.0, wet, occlusion(x, z)), m)


func _rock() -> ShaderMaterial:
	if rock_mat == null:
		rock_mat = ShaderMaterial.new()
		rock_mat.shader = load("res://shaders/world/cave_rock.gdshader")
		rock_mat.set_shader_parameter("rock_alb", RealKit.ph_tex("cliff_side", "diff"))
		rock_mat.set_shader_parameter("rock_nrm", RealKit.ph_tex("cliff_side", "nor_gl"))
		rock_mat.set_shader_parameter("noise_tex", Kit.noise())
		magic_receivers.append(rock_mat)
	return rock_mat


## The roof: every grid cell where there is rock overhead, facing down, solid (the camera and spells meet it).
func _ceiling() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := PackedInt32Array()
	idx.resize(_n * _n)
	idx.fill(-1)
	var vi := 0
	for iz in _n:
		for ix in _n:
			var k := iz * _n + ix
			var under := false
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var jx := clampi(ix + dx, 0, _n - 1)
					var jz := clampi(iz + dz, 0, _n - 1)
					if _c[jz * _n + jx] - _f[jz * _n + jx] > 0.05:
						under = true
			if not under:
				continue
			var x := -HALF + ix * STEP
			var z := -HALF + iz * STEP
			var hl := _c[iz * _n + maxi(ix - 1, 0)]
			var hr := _c[iz * _n + mini(ix + 1, _n - 1)]
			var hd := _c[maxi(iz - 1, 0) * _n + ix]
			var hu := _c[mini(iz + 1, _n - 1) * _n + ix]
			st.set_normal(-Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized())
			st.set_color(Color(0, 0, _mineral(x, z), occlusion(x, z)))
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, _c[k], z))
			idx[k] = vi
			vi += 1
	for iz in _n - 1:
		for ix in _n - 1:
			var a := idx[iz * _n + ix]
			var b := idx[iz * _n + ix + 1]
			var c := idx[(iz + 1) * _n + ix]
			var d := idx[(iz + 1) * _n + ix + 1]
			if a < 0 or b < 0 or c < 0 or d < 0:
				continue
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	if vi == 0:
		return
	st.generate_tangents()
	var mesh := st.commit()
	var body := StaticBody3D.new()
	body.name = "CaveRoof"
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _rock()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)


## Stalactites from the roof and stalagmites from the floor (off the paths). Each is one of several grown shapes
## (FORMATION_VARIANTS): irregular in section, ringed with drip ridges, leaning a little, fattening at the root -
## never a clean geometric cone. Vertex alpha carries a fixed share of the cave's occlusion (formation_occ) so
## they sit in the same light as the rock round them instead of going black.
const FORMATION_VARIANTS := 5
var formation_occ := 0.55


func _formation_mesh(seed: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var rings := 14
	var segs := 14
	var lean := Vector2(r.randf_range(-0.12, 0.12), r.randf_range(-0.12, 0.12))
	var ph := [r.randf() * TAU, r.randf() * TAU, r.randf() * TAU]
	var ridge_f := r.randf_range(14.0, 26.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings + 1:
		var t := float(i) / rings                     # 0 = tip, 1 = root
		# dripstone is blunt and bulbous, not a cone: a rounded tip, a thick body, a flare where it meets the rock
		var rad := 0.04 + 0.36 * pow(t, 0.55) + 0.16 * pow(t, 6.0)
		rad *= 1.0 + 0.07 * sin(t * ridge_f + ph[0]) * (1.0 - t * 0.6)   # drip rings
		var off := lean * pow(1.0 - t, 2.0)
		for j in segs + 1:
			var a := TAU * j / segs
			var lobe := 1.0 + 0.16 * sin(a * 2.0 + ph[1]) + 0.09 * sin(a * 3.0 + ph[2] + t * 4.0) + 0.05 * sin(a * 7.0 + t * 11.0)
			var rr := rad * lobe
			var v := Vector3(cos(a) * rr + off.x, t, sin(a) * rr + off.y)
			st.set_color(Color(0, 0, 0, formation_occ))
			st.set_uv(Vector2(float(j) / segs, t))
			st.set_normal(Vector3(cos(a), 0.35 * (1.0 - t), sin(a)).normalized())
			st.add_vertex(v)
	for i in rings:
		for j in segs:
			var a0 := i * (segs + 1) + j
			var b0 := a0 + segs + 1
			st.add_index(a0); st.add_index(a0 + 1); st.add_index(b0)
			st.add_index(a0 + 1); st.add_index(b0 + 1); st.add_index(b0)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func _formations() -> void:
	var meshes := []
	for v in FORMATION_VARIANTS:
		meshes.append(_formation_mesh(9100 + v * 37))
	var up_xf := []
	var down_xf := []
	for v in FORMATION_VARIANTS:
		up_xf.append([])
		down_xf.append([])
	for i in 900:
		var p := Vector2(rng.randf_range(-HALF + 4, HALF - 4), rng.randf_range(-HALF + 4, HALF - 4))
		var gap := roof(p.x, p.y) - height(p.x, p.y)
		if gap < 2.5:
			continue
		var s := rng.randf_range(0.6, 2.4) * clampf(gap / 8.0, 0.4, 1.6)
		var v := rng.randi() % FORMATION_VARIANTS
		if rng.randf() < 0.72:
			# hanging from the roof: the tip (y=0) points down; thinner and longer than the ones that grow up
			var hl := minf(s * 2.4, gap * 0.45)
			(down_xf[v] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 0.6, hl, s * 0.6)), Vector3(p.x, roof(p.x, p.y) - hl + 0.15, p.y)))
		elif trail_at(p.x, p.y) < 0.05 and water_dist(p) > 1.5:
			var hh := minf(s * 1.3, gap * 0.35)
			(up_xf[v] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI).scaled(Vector3(s * 0.75, hh, s * 0.75)), Vector3(p.x, height(p.x, p.y) + hh - 0.2, p.y)))
	var fm := _rock().duplicate() as ShaderMaterial
	fm.set_shader_parameter("mineral", Color(0.625, 0.625, 0.625))
	fm.set_shader_parameter("wet", 0.7)                 # dripstone is wet
	fm.set_shader_parameter("tone", Color(0.74, 0.7, 0.64))   # calcite: paler and warmer than the bedrock
	for v in FORMATION_VARIANTS:
		if not (down_xf[v] as Array).is_empty():
			Kit.multimesh(self, meshes[v], down_xf[v], 90.0, true, fm)
		if not (up_xf[v] as Array).is_empty():
			Kit.multimesh(self, meshes[v], up_xf[v], 90.0, true, fm)


func _links() -> void:
	links()
	boundary_box(Vector3(0, 0, 0), Vector3(SIZE - 6, 80, SIZE - 6))


## A crystal cluster with its light (colour by family), noted for the rock's mineral tint.
func crystals(at: Vector3, up: Vector3, size: float, family: int, seed: int, light := true) -> void:
	# saturated mineral colours (pale pastel cores tone-map to plastic): aquamarine, amethyst, a green fluorite
	var cols := [[Color(0.12, 0.5, 0.95), Color(0.3, 0.78, 1.0)], [Color(0.42, 0.18, 0.9), Color(0.62, 0.38, 1.0)], [Color(0.08, 0.75, 0.55), Color(0.3, 0.95, 0.75)]]
	var c: Array = cols[family % cols.size()]
	CrystalKit.cluster(self, at, up, size, c[0], c[1], seed, 7 + int(size * 2.0))
	crystal_spots.append(at)
	if light:
		Kit.omni(self, at + up.normalized() * size * 0.6, c[1], 0.8 + size * 0.25, 4.0 + size * 2.5)
