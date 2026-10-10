class_name SanctuaryTerrain
extends RefCounted
## Heightfield for the forest clearing: flat sanctuary floor, worn paths, a flattened
## training clearing to the east, and wooded hills rising toward the horizon.
## Godot axes: north = -Z (toward the arch gateway), east = +X.

const SIZE := 200.0
const STEP := 1.0
const TRAINING_CENTER := Vector2(26.0, 4.0)

# Path polylines (x, z)
const PATHS := [
	[Vector2(0, 8.0), Vector2(1.5, 20), Vector2(-2.5, 36), Vector2(0, 62), Vector2(4, 100)],
	[Vector2(7.5, 1.5), Vector2(15, 4.5), Vector2(26, 4.0)],
	[Vector2(0, -9.5), Vector2(0, -17), Vector2(1.5, -30), Vector2(-3, -55), Vector2(0, -100)],
	[Vector2(26, 4.0), Vector2(34, 14), Vector2(48, 20)],
	[Vector2(1.5, 13.0), Vector2(9.0, 12.5), Vector2(14.0, 15.5)],          # to the Meditation Garden
	[Vector2(-1.0, -19.5), Vector2(-10.0, -22.0), Vector2(-17.5, -21.0)],    # to the Altar Chamber
	[Vector2(-2.5, 36.0), Vector2(-10.0, 38.5), Vector2(-14.5, 38.0)],       # to the Watchpoint
]
const GARDEN := Vector2(15, 17)
const CHAMBER := Vector2(-21, -21)
const WATCH := Vector2(-18, 38)
const POND := Vector2(16.5, 19.0)

var noise := FastNoiseLite.new()
var micro := FastNoiseLite.new()
var grid := PackedFloat32Array()   # heights computed once by build_mesh(); reused for collision + placement


func _init() -> void:
	noise.seed = 4242
	noise.frequency = 0.018
	noise.fractal_octaves = 4
	micro.seed = 99
	micro.frequency = 0.15
	micro.fractal_octaves = 2


static func dist_to_paths(p: Vector2) -> float:
	var best := 1e9
	for path in PATHS:
		for i in path.size() - 1:
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
	return best


func flat_mask(p: Vector2) -> float:
	var d := p.length()
	var f := 1.0 - smoothstep(19.0, 34.0, d)
	f = maxf(f, 1.0 - smoothstep(9.0, 15.0, p.distance_to(TRAINING_CENTER)))
	f = maxf(f, (1.0 - smoothstep(2.0, 7.0, dist_to_paths(p))) * 0.8)
	f = maxf(f, 1.0 - smoothstep(7.0, 11.0, p.distance_to(GARDEN)))
	f = maxf(f, 1.0 - smoothstep(6.5, 10.0, p.distance_to(CHAMBER)))
	f = maxf(f, 1.0 - smoothstep(5.0, 8.0, p.distance_to(WATCH)))
	return f


func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var d := p.length()
	var flat := flat_mask(p)
	var rise := pow(smoothstep(24.0, 95.0, d), 1.4) * 4.5
	var hills := (noise.get_noise_2d(x, z) * 0.5 + 0.5) * 2.6 * smoothstep(20.0, 60.0, d)
	var h := (rise + hills) * (1.0 - flat)
	# gentle micro-relief everywhere except the sanctuary floor itself
	h += micro.get_noise_2d(x, z) * 0.12 * smoothstep(9.0, 13.0, d)
	# worn path: slightly sunken
	h -= (1.0 - smoothstep(0.6, 1.8, dist_to_paths(p))) * 0.06
	# the garden pond basin
	h -= (1.0 - smoothstep(1.6, 3.3, p.distance_to(POND))) * 0.6
	return h


func build_mesh() -> ArrayMesh:
	var n := int(SIZE / STEP) + 1
	var half := SIZE * 0.5
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for iz in n:
		for ix in n:
			heights[iz * n + ix] = height(-half + ix * STEP, -half + iz * STEP)
	grid = heights
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			var x := -half + ix * STEP
			var z := -half + iz * STEP
			var hl := heights[iz * n + maxi(ix - 1, 0)]
			var hr := heights[iz * n + mini(ix + 1, n - 1)]
			var hd := heights[maxi(iz - 1, 0) * n + ix]
			var hu := heights[mini(iz + 1, n - 1) * n + ix]
			var nrm := Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			var p := Vector2(x, z)
			var path := 1.0 - smoothstep(1.1, 2.6, dist_to_paths(p))
			path = maxf(path, 1.0 - smoothstep(2.6, 3.4, p.distance_to(POND)))  # muddy pond bed
			var d := p.length()
			var leaf := smoothstep(17.0, 30.0, d) * (1.0 - (1.0 - smoothstep(7.0, 12.0, p.distance_to(TRAINING_CENTER))))
			# leaf litter also gathers at the base of the ruin walls
			leaf = maxf(leaf, (1.0 - smoothstep(0.8, 2.5, absf(d - 14.5))) * 0.65 * float(absf(x) > 9.0))
			st.set_color(Color(path, leaf, 0.0))
			st.set_normal(nrm)
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, heights[iz * n + ix], z))
	for iz in n - 1:
		for ix in n - 1:
			var i := iz * n + ix
			st.add_index(i); st.add_index(i + 1); st.add_index(i + n)
			st.add_index(i + 1); st.add_index(i + n + 1); st.add_index(i + n)
	st.generate_tangents()
	return st.commit()


func build_collision_shape() -> HeightMapShape3D:
	var n := int(SIZE / STEP) + 1
	var half := SIZE * 0.5
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	if grid.size() != n * n:
		build_mesh()
	shape.map_data = grid
	return shape


## Bilinear lookup into the precomputed grid (identical to the collision surface).
func fast_height(x: float, z: float) -> float:
	var n := int(SIZE / STEP) + 1
	if grid.size() != n * n:
		return height(x, z)
	var fx := clampf((x + SIZE * 0.5) / STEP, 0.0, n - 1.001)
	var fz := clampf((z + SIZE * 0.5) / STEP, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := grid[iz * n + ix]
	var h10 := grid[iz * n + ix + 1]
	var h01 := grid[(iz + 1) * n + ix]
	var h11 := grid[(iz + 1) * n + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
