extends Node3D
## STARFALL HILL (env-test, standalone test scene - not in data/world.json or any route yet).
## Quiet, peaceful, a little lonely and romantic: two friends lying on a hill under one huge old tree at night,
## watching the Milky Way. The sky is the star: the ESO all-sky Milky Way panorama (eso0932a, CC BY 4.0, CREDITS.md)
## arched across the sky, crisp stars, occasional shooting stars. One hero tree (Poly Haven island_tree_01, CC0, a real
## scanned 3D tree) on a gentle grassy hill, leaves swaying; dense dark grass in the wind, a few small glowing
## wildflowers near the girls, fireflies at many depths; distant hill silhouettes, a misty valley, faraway village lights.
## Mika and Luna lie on their backs under the edge of the canopy, heads close together (UAL LayToIdle pose + breathing,
## Mika's arm behind her head, Luna now and then pointing at the sky), their hair fanning out on the grass (a ground
## collider for the VRM spring bones). Faces: soft cool key from the sky, skin kept bright and clean by the grade,
## no hard cast shadows, catchlights, blinks and gentle smiles. Ground realism from photo scans (Poly Haven CC0):
## scanned grass clumps round them, periwinkles whose petals glow softly, ferns and a mossy boulder at the roots,
## leaf litter under the tree. PERMANENT CAMERA RULE (docs/world_look_rules.md): no close-ups - every shot is wide or
## medium-wide, knees-up or wider; FramingGuard enforces it and QA reports the largest face size per shot.
## Run alone, always with a test flag so no save is touched:
##   godot --path . res://scenes/areas/starfall_hill.tscn -- --fresh --save-path=user://test_starfall.json
##     [--cam=cine|wide|overhead|side|pov]  keys 1-4 hold a shot, 0 = cine loop, F3 = monitor overlay
##     [--starfall-qa --out=/abs/dir]  per-shot FPS / draw calls / VRAM / GPU ms + one still per shot + grounding
##     [--clip]  warm-up, then the 10 s sequence once, then quit (with --write-movie and --fixed-fps 30)

const HALF := 520.0
const CELLS := 220
const VALLEY_DIR := Vector2(1.0, -0.15)        # the land falls away east into the valley
const BED := Vector2(2.2, 4.4)                 # where their heads meet (the tree stands at the origin)
const FEET_DIR := Vector2(0.12, 1.0)           # their bodies point down the hill, toward the wide camera
const SPLAY := 4.0                             # degrees each body turns outward from FEET_DIR (nearly parallel)
const HEAD_GAP := 0.95                         # head to head centre: ~40 cm of grass between the two bodies
const BED_SLOPE := 9.0                         # degrees: their patch of grass tips down the hill toward the wide lens
const GLOW_EXTENT := 30.0
const SCAN_R := 6.5
const WIDE_CAM := Vector2(-2.6, 17.0)          # the wide lens, down the hill from where they lie
const PLATE_AZ := 8.0                          # the backdrop plate's centre (degrees from north): behind the tree                            # scanned grass clumps within this radius of where they lie
const WARMUP := 6.0
const SEQUENCE := [["wide", 3.0], ["luna_point", 3.4], ["overhead", 2.0], ["pov", 1.6]]
const LOOP := [["wide", 10.0], ["luna_point", 8.0], ["overhead", 8.0], ["side", 9.0], ["pov", 8.0]]
const CHAR_LAYER := 2 | 4                      # Mika on layer 2, Luna on layer 3 (their own keys)
const LAYER := {"mika": 2, "luna": 4}
const CORE_AZ := 34.0                          # the galactic core: low in the north-north-east (right of the wide shot)
const CORE_EL := 9.0
const ARCH_AZ := -38.0                         # ...and the band arching up through the north-west sky over the tree
const ARCH_EL := 58.0

var env: Environment
var attrs: CameraAttributesPractical
var skylight: DirectionalLight3D
var char_key: DirectionalLight3D
var char_keys := {}
const KEY_ENERGY := {"mika": 0.34, "luna": 0.72}
var char_rim: DirectionalLight3D
var cam: Camera3D
var blur_mat: ShaderMaterial
var grade_mat: ShaderMaterial
var mask_vp: SubViewport
var mask_cam: Camera3D
var overlay: Label
var guard: FramingGuard
var characters := {}
var limbs := {}
var lie_dir := {}                  # who -> world direction from her head toward her feet (flat)
var head_spot := {}                # who -> where her head rests (world, on the ground)
var counts := {}
var tree_top := 15.0
var canopy_r := 7.0
var glow_tex: ImageTexture
var mode := "cine"
var shot := "wide"
var shot_t := 0.0
var _seq_i := 0
var _focus := 10.0
var _bed_h := 0.0
var _prev_view := Transform3D.IDENTITY
var _placed := false
var _point_w := 0.0
var _point_state := "rest"
var _point_clock := 0.0
var _point_rest := 3.0
var _point_hold := false
var _look_t := {"mika": 0.8, "luna": 1.9}
var _look_tgt := {}
var _mood_t := {"mika": 2.5, "luna": 4.5}
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var use_backdrop := true
var world_vp: SubViewport           # the 3D scene renders here (transparent background) when the backdrop is used


func _ready() -> void:
	DisplayServer.window_set_title("Starfall Hill (env-test)")
	use_backdrop = not RenderProfile.options.has("eso-sky")
	_rng.seed = 1016
	_noise.seed = 11
	_noise.frequency = 0.008
	_noise.fractal_octaves = 3
	_bed_h = _h_raw(BED.x, BED.y)
	Progression.load_data()
	Engine.max_fps = int(RenderProfile.get_setting("max_fps"))     # the stream's locked 30
	_environment()
	_lights()
	_terrain()
	if not use_backdrop:
		_hills()
	_tree()
	_characters()
	_glow_map()
	_grass()
	_scanned_plants()
	if not use_backdrop:
		_village()
	_cameras()
	_fireflies()
	_post()
	_mask_pass()
	_overlay()
	guard = FramingGuard.new()
	guard.name = "FramingGuard"
	guard.characters = characters.values()
	guard.camera = cam
	add_child(guard)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if world_vp:
		RenderingServer.viewport_set_measure_render_time(world_vp.get_viewport_rid(), true)
	print("[starfall] adapter=%s | %s | profile=%s max_fps=%d | grass_blades=%d flowers=%d tree_h=%.1f canopy_r=%.1f" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderProfile.profile,
		Engine.max_fps, counts.get("grass_blades", 0), counts.get("flowers", 0), tree_top, canopy_r])
	_settle.call_deferred()
	if RenderProfile.options.has("starfall-qa"):
		_qa.call_deferred()
	elif RenderProfile.options.has("clip"):
		_clip.call_deferred()


# ---------------------------------------------------------------- terrain

func _h_raw(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var r := p.length()
	var hill := 9.0 * exp(-r * r / (2.0 * 34.0 * 34.0))
	var dv := p.dot(VALLEY_DIR.normalized())
	var valley := -38.0 * smoothstep(12.0, 170.0, dv) + (44.0 * smoothstep(290.0, 520.0, dv) if not use_backdrop else 0.0)
	var roll := _noise.get_noise_2d(x, z) * 2.4 * smoothstep(12.0, 70.0, r)
	if use_backdrop:
		# the painted plate carries the far hills, the misty valley and the village: beyond ~20 m the hill falls away
		# steeply, so from where they lie the ground ends low in the frame and the painted hills stay above it
		return hill + roll * 0.4 - 48.0 * smoothstep(18.0, 75.0, r)
	return hill + valley + roll


## The hill, with a smooth patch of grass where the two of them lie, tipped gently down the hill (so they can be
## seen lying there from below, the way the reference frames them).
func h(x: float, z: float) -> float:
	var wb := 1.0 - smoothstep(2.6, 5.2, Vector2(x, z).distance_to(BED))
	return lerpf(_h_raw(x, z), bed_plane(x, z), wb)


func bed_plane(x: float, z: float) -> float:
	var f := FEET_DIR.normalized()
	return _bed_h - (Vector2(x, z) - BED).dot(f) * tan(deg_to_rad(BED_SLOPE))


func bed_normal() -> Vector3:
	var f := Vector3(FEET_DIR.x, 0, FEET_DIR.y).normalized()
	return Vector3.UP.rotated(f.cross(Vector3.UP).normalized(), -deg_to_rad(BED_SLOPE)).normalized()


func _grid(u: float) -> float:
	# dense round the hilltop (~0.3 m cells), wide toward the far rim
	return HALF * signf(u) * (0.12 * absf(u) + 0.88 * pow(absf(u), 3.0))


func _terrain() -> void:
	var n := CELLS + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		var z := _grid(-1.0 + 2.0 * j / CELLS) + BED.y * 0.5
		for i in n:
			var x := _grid(-1.0 + 2.0 * i / CELLS) + BED.x * 0.5
			var e := 0.25
			st.set_normal(Vector3(h(x - e, z) - h(x + e, z), 2.0 * e, h(x, z - e) - h(x, z + e)).normalized())
			st.set_uv(Vector2(x, z) / 2.6)
			st.add_vertex(Vector3(x, h(x, z), z))
	for j in CELLS:
		for i in CELLS:
			var a := j * n + i
			for k in [a, a + 1, a + n, a + 1, a + n + 1, a + n]:
				st.add_index(k)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/starfall/ground_real.gdshader")
	var tex := "res://assets/polyhaven/textures/leafy_grass/leafy_grass_%s_2k.jpg"
	sm.set_shader_parameter("grass_alb", load(tex % "diff"))
	sm.set_shader_parameter("grass_nor", load(tex % "nor_gl"))
	sm.set_shader_parameter("leaf_alb", load("res://assets/polyhaven/textures/forest_leaves_02/forest_leaves_02_diffuse_2k.jpg"))
	sm.set_shader_parameter("leaf_nor", load("res://assets/polyhaven/textures/forest_leaves_02/forest_leaves_02_nor_gl_2k.jpg"))
	sm.set_shader_parameter("trunk", Vector3.ZERO)
	sm.set_shader_parameter("litter_r", 7.5)
	sm.set_shader_parameter("brightness", 0.42)
	mi.material_override = sm
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)


## Distant hills, layer behind layer, dark against the sky; the depth fog turns the far ones to violet haze.
func _hills() -> void:
	var layers := [[430.0, 22.0, 55.0, Color(0.006, 0.006, 0.016)], [660.0, 35.0, 90.0, Color(0.009, 0.008, 0.024)],
		[980.0, 50.0, 140.0, Color(0.012, 0.011, 0.034)]]
	var nz := FastNoiseLite.new()
	nz.seed = 77
	nz.frequency = 0.9
	for L in layers:
		var r0: float = L[0]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var seg := 1440
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			# a forested ridge: the broad hill line plus the bumps of the tree crowns along it
			var y0: float = float(L[1]) + (float(L[2]) - float(L[1])) * (nz.get_noise_1d(a0 * r0 * 0.004) * 0.5 + 0.5) + _crowns(a0 * r0, r0)
			var y1: float = float(L[1]) + (float(L[2]) - float(L[1])) * (nz.get_noise_1d(a1 * r0 * 0.004) * 0.5 + 0.5) + _crowns(a1 * r0, r0)
			var p0 := Vector3(cos(a0) * r0, -60.0, sin(a0) * r0)
			var p1 := Vector3(cos(a1) * r0, -60.0, sin(a1) * r0)
			var q0 := Vector3(p0.x, y0 - 30.0, p0.z)
			var q1 := Vector3(p1.x, y1 - 30.0, p1.z)
			for v in [p0, p1, q1, p0, q1, q0]:
				st.set_normal((-v).normalized())
				st.add_vertex(v)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = L[3]
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.name = "Hills%d" % int(r0)
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# ---------------------------------------------------------------- the tree

func _tree() -> void:
	var scene: PackedScene = load("res://assets/polyhaven/models/island_tree_01/island_tree_01_2k.gltf")
	var t: Node3D = scene.instantiate()
	t.name = "HeroTree"
	add_child(t)
	print("[starfall] tree meshes: ", t.find_children("*", "MeshInstance3D", true, false).size())
	var aabb := AABB()
	var first := true
	var tinv := t.global_transform.affine_inverse()
	for mi in t.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var bb := (tinv * m.global_transform) * m.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
	print("[starfall] tree model aabb ", aabb)
	var k := 15.5 / maxf(aabb.size.y, 0.1)
	t.scale = Vector3.ONE * k
	t.rotation.y = deg_to_rad(200.0)
	var base := Vector3(0, h(0, 0) - aabb.position.y * k - 0.25, 0)
	t.position = base
	tree_top = aabb.size.y * k
	print("[starfall] tree at ", base, " scale ", k)
	canopy_r = maxf(aabb.size.x, aabb.size.z) * k * 0.5
	var wind := load("res://shaders/starfall/foliage_wind.gdshader")
	for mi in t.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in m.mesh.get_surface_count():
			var src := m.get_active_material(si) as StandardMaterial3D
			if src == null:
				continue
			var nm := String(src.resource_name)
			if nm.ends_with("_leaves") or nm.ends_with("_branches"):
				var sm := ShaderMaterial.new()
				sm.shader = wind
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("normal_tex", src.normal_texture)
				sm.set_shader_parameter("arm_tex", src.roughness_texture if src.roughness_texture else src.ao_texture)
				sm.set_shader_parameter("base_world", base)
				sm.set_shader_parameter("calm_height", 4.5)
				sm.set_shader_parameter("amp", 0.03 if nm.ends_with("_leaves") else 0.02)
				sm.set_shader_parameter("tint", Color(0.55, 0.62, 0.8))
				m.set_surface_override_material(si, sm)
			else:
				var bark := src.duplicate() as StandardMaterial3D
				bark.albedo_color = Color(0.6, 0.62, 0.75)
				m.set_surface_override_material(si, bark)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.9
	cyl.height = 4.0
	cs.shape = cyl
	cs.position = Vector3(0, h(0, 0) + 2.0, 0)
	body.add_child(cs)
	add_child(body)


# ---------------------------------------------------------------- grass, flowers, village

## The two body lines on the ground (head spot -> feet), for flattening the grass under them.
func _body_dist(x: float, z: float) -> float:
	var best := 99.0
	for who in ["mika", "luna"]:
		var hs := _head_target(who)
		var a := Vector2(hs.x, hs.z)
		var dir := _feet_dir(who)
		var b := a + Vector2(dir.x, dir.z) * 1.55
		var p := Vector2(x, z)
		var ab := b - a
		var tt := clampf((p - a).dot(ab) / ab.length_squared(), -0.25, 1.0)
		best = minf(best, p.distance_to(a + ab * tt))
	return best


func _feet_dir(who: String) -> Vector3:
	var f := Vector3(FEET_DIR.x, 0, FEET_DIR.y).normalized()
	return f.rotated(Vector3.UP, deg_to_rad(SPLAY) * (-1.0 if who == "mika" else 1.0))


func _head_target(who: String) -> Vector3:
	var f := Vector3(FEET_DIR.x, 0, FEET_DIR.y).normalized()
	var side := f.cross(Vector3.UP).normalized()          # toward Mika's side (west when the feet point south)
	var p := Vector3(BED.x, 0, BED.y) + side * HEAD_GAP * 0.5 * (1.0 if who == "mika" else -1.0)
	return Vector3(p.x, h(p.x, p.z), p.z)


func _flower_density(x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(BED)
	var near := (1.0 - smoothstep(1.2, 5.5, d)) * 0.9
	var body := _body_dist(x, z)
	return clampf(near * smoothstep(0.55, 0.9, body), 0.0, 1.0)


func _glow_map() -> void:
	var res := 128
	var img := Image.create(res, res, false, Image.FORMAT_RF)
	for j in res:
		for i in res:
			var x := -GLOW_EXTENT + (i + 0.5) * 2.0 * GLOW_EXTENT / res
			var z := -GLOW_EXTENT + (j + 0.5) * 2.0 * GLOW_EXTENT / res
			img.set_pixel(i, j, Color(_flower_density(x, z) * 0.5, 0, 0))
	glow_tex = ImageTexture.create_from_image(img)



func _grass_mesh(blades: int, width: float, spread: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = blades * 977 + int(width * 10000)
	var base_i := 0
	for k in blades:
		var ang := r.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var root := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * spread
		var hh := r.randf_range(0.65, 1.0)
		var lean := dir * r.randf_range(0.08, 0.32)
		var w := width * r.randf_range(0.75, 1.25)
		var n := (dir * -0.35 + Vector3.UP).normalized()
		var id := r.randf()
		for s in 4:
			var t := s / 3.0
			var c := root + Vector3(0, hh * t, 0) + lean * t * t
			var ww := w * (1.0 - t * 0.92)
			for e in [-1.0, 1.0]:
				st.set_normal(n)
				st.set_uv(Vector2(id, t))
				st.add_vertex(c + side * ww * e)
		for s in 3:
			var q := base_i + s * 2
			for i in [q, q + 1, q + 3, q, q + 3, q + 2]:
				st.add_index(i)
		base_i += 8
	return st.commit()


func _grass() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/moonbloom/grass.gdshader")
	sm.set_shader_parameter("glow_map", glow_tex)
	sm.set_shader_parameter("glow_extent", GLOW_EXTENT)
	sm.set_shader_parameter("base_color", Color(0.015, 0.03, 0.05))
	sm.set_shader_parameter("tip_color", Color(0.07, 0.11, 0.2))
	sm.set_shader_parameter("tip_light", Color(0.22, 0.26, 0.62))
	sm.set_shader_parameter("glow_color", Color(0.45, 0.5, 1.0))
	sm.set_shader_parameter("wind_strength", 0.12)
	sm.set_shader_parameter("fade_start", 45.0)
	sm.set_shader_parameter("fade_end", 95.0)
	var fd := float(RenderProfile.get_setting("foliage_density"))
	var c := Vector2(BED.x * 0.5, BED.y * 0.5)
	var rings := [["GrassNear", 0.0, 14.0, int(40000 * fd), 6, 0.006, 0.07], ["GrassMid", 13.0, 42.0, int(46000 * fd), 6, 0.011, 0.1],
		["GrassFar", 40.0, 70.0 if use_backdrop else 110.0, int((22000 if use_backdrop else 36000) * fd), 5, 0.026, 0.18]]
	var blades := 0
	for ring in rings:
		var xforms: Array[Transform3D] = []
		var customs: Array[Color] = []
		var r0: float = ring[1]
		var r1: float = ring[2]
		while xforms.size() < int(ring[3]):
			var rr := sqrt(lerpf(r0 * r0, r1 * r1, _rng.randf()))
			var a := _rng.randf() * TAU
			var x := c.x + cos(a) * rr
			var z := c.y + sin(a) * rr
			if Vector2(x, z).length() < 1.1:
				continue                                    # the trunk
			if rr < 8.0 and Vector2(x, z).distance_to(BED) < SCAN_R and _body_dist(x, z) > 0.5:
				continue                                    # the scanned grass grows here
			var sy := _rng.randf_range(0.3, 0.6) * (1.0 + 0.3 * _noise.get_noise_2d(x * 9.0, z * 9.0))
			sy *= lerpf(1.0, 0.35, _wide_corridor(x, z))          # low along the wide lens's line to them
			if rr < 8.0:
				var bd := _body_dist(x, z)
				sy *= lerpf(0.18, 1.0, smoothstep(0.35, 0.95, bd))      # pressed flat where they lie
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1.0, sy, 1.0))
			xforms.append(Transform3D(b, Vector3(x, h(x, z) - 0.02, z)))
			customs.append(Color(_rng.randf(), 0, 0, 0))
		_multimesh(ring[0], _grass_mesh(ring[4], ring[5], ring[6]), sm, xforms, customs)
		blades += xforms.size() * int(ring[4])
	# the wide shot's foreground: thick tall grass right in front of the lens (soft in the depth of field)
	var fx: Array[Transform3D] = []
	var fc: Array[Color] = []
	var wc := WIDE_CAM + Vector2(-1.2, 3.5)
	while fx.size() < int(14000 * fd):
		var rr := sqrt(_rng.randf()) * 7.0
		var a := _rng.randf() * TAU
		var x := wc.x + cos(a) * rr
		var z := wc.y + sin(a) * rr
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1.0, _rng.randf_range(0.45, 0.85), 1.0))
		fx.append(Transform3D(b, Vector3(x, h(x, z) - 0.02, z)))
		fc.append(Color(_rng.randf(), 0, 0, 0))
	_multimesh("GrassForeground", _grass_mesh(7, 0.008, 0.08), sm, fx, fc)
	blades += fx.size() * 7
	counts["grass_blades"] = blades


func _flower_mesh() -> ArrayMesh:
	# a small open wildflower: thin stem, six petals opening almost flat round a bright centre
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var H := 0.22
	for rot in [0.0, PI * 0.5]:
		var side := Vector3(cos(rot), 0, sin(rot)) * 0.0025
		for s in 4:
			var t0 := s / 4.0
			var t1 := (s + 1) / 4.0
			var c0 := Vector3(0.01 * t0 * t0, H * t0, 0)
			var c1 := Vector3(0.01 * t1 * t1, H * t1, 0)
			for pv in [[c0 - side, t0], [c0 + side, t0], [c1 + side, t1], [c0 - side, t0], [c1 + side, t1], [c1 - side, t1]]:
				st.set_normal(Vector3(0, 0, 1))
				st.set_uv(Vector2(0.0, pv[1]))
				st.set_color(Color(0, 0, 0))
				st.add_vertex(pv[0])
	var top := Vector3(0.01, H, 0)
	for k in 6:
		var ang := k * TAU / 6.0
		var out := Vector3(cos(ang), 0, sin(ang))
		var perp := Vector3(-out.z, 0, out.x)
		var mid := top + out * 0.022 + Vector3(0, 0.004, 0)
		var tip := top + out * 0.04 + Vector3(0, 0.012, 0)
		for pv in [[top, 0.0], [mid - perp * 0.013, 0.6], [tip, 1.0], [top, 0.0], [tip, 1.0], [mid + perp * 0.013, 0.6]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(1.0, 1.0))
			st.set_color(Color(0, pv[1], 0))
			st.add_vertex(pv[0])
	for k in 5:
		var a0 := k * TAU / 5.0
		var a1 := (k + 1) * TAU / 5.0
		for p in [top + Vector3(0, 0.007, 0), top + Vector3(cos(a0), 0.002, sin(a0)) * 0.008, top + Vector3(cos(a1), 0.002, sin(a1)) * 0.008]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5, 1.0))
			st.set_color(Color(0, 1, 0))
			st.add_vertex(p)
	return st.commit()


func _wildflowers() -> void:
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var tries := 0
	# a few near them (their faces' soft light), very few scattered over the hilltop
	while xforms.size() < 420 and tries < 60000:
		tries += 1
		var rr := sqrt(_rng.randf()) * (6.0 if xforms.size() < 300 else 22.0)
		var a := _rng.randf() * TAU
		var x := BED.x + cos(a) * rr
		var z := BED.y + sin(a) * rr
		var d := _flower_density(x, z) if xforms.size() < 300 else 0.15 * smoothstep(0.9, 1.5, _body_dist(x, z))
		if _rng.randf() > d or Vector2(x, z).length() < 1.3:
			continue
		var s := _rng.randf_range(0.8, 1.35)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
		b = Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, 0.25)) * b
		xforms.append(Transform3D(b, Vector3(x, h(x, z) - 0.01, z)))
		customs.append(Color(_rng.randf(), _rng.randf_range(0.5, 1.1), _rng.randf(), 0))
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/moonbloom/flower.gdshader")
	sm.set_shader_parameter("petal_color", Color(0.85, 0.9, 1.0))
	sm.set_shader_parameter("glow_a", Color(0.55, 0.68, 1.0))
	sm.set_shader_parameter("glow_b", Color(0.78, 0.72, 1.0))
	sm.set_shader_parameter("glow_c", Color(0.95, 0.97, 1.0))
	sm.set_shader_parameter("glow_energy", 1.7)
	sm.set_shader_parameter("stem_color", Color(0.02, 0.05, 0.05))
	sm.set_shader_parameter("wind_strength", 0.03)
	_multimesh("Wildflowers", _flower_mesh(), sm, xforms, customs)
	counts["flowers"] = xforms.size()


func _village() -> void:
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var vr := RandomNumberGenerator.new()
	vr.seed = 5
	var centre := Vector2(440, -40)
	for k in 56:
		var p := centre + Vector2(vr.randf_range(-30, 30), vr.randf_range(-55, 55)) * (0.4 + 0.6 * vr.randf())
		var s := vr.randf_range(2.2, 3.6)
		xforms.append(Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(p.x, h(p.x, p.y) + vr.randf_range(1.5, 6.0), p.y)))
		customs.append(Color(0, 0, 0, 0))
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/starfall/village_lights.gdshader")
	_multimesh("VillageLights", q, sm, xforms, customs)


func _multimesh(nm: String, mesh: Mesh, mat: Material, xforms: Array[Transform3D], customs: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_custom_data(k, customs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


# ---------------------------------------------------------------- fireflies

func _emitter(nm: String, parent: Node3D, at: Vector3, amount: int, life: float, box: Vector3, quad: Vector2, gravity: Vector3, turb: float) -> void:
	var gp := GPUParticles3D.new()
	gp.name = nm
	gp.amount = maxi(1, int(amount * float(RenderProfile.get_setting("particle_scale"))))
	gp.lifetime = life
	gp.preprocess = life
	gp.visibility_aabb = AABB(-box - Vector3(10, 10, 10), (box + Vector3(10, 10, 10)) * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.gravity = gravity
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.18
	pm.direction = Vector3(0.3, 0.4, 0.2)
	pm.spread = 150.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = turb
	pm.turbulence_noise_scale = 5.0
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.09
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.15, Color(1, 1, 1, 1))
	ramp.add_point(0.85, Color(1, 1, 1, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = quad
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/moonbloom/firefly.gdshader")
	sm.set_shader_parameter("color", Color(0.95, 0.92, 0.5))
	sm.set_shader_parameter("energy", 5.0)
	q.material = sm
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.position = at
	parent.add_child(gp)


func _fireflies() -> void:
	var bed := Vector3(BED.x, _bed_h, BED.y)
	var up := Vector3(0, 0.02, 0)
	_emitter("FirefliesNear", self, bed + Vector3(0, 0.7, 0), 60, 9.0, Vector3(4.0, 0.6, 4.0), Vector2(0.045, 0.045), up, 1.0)
	_emitter("FirefliesTree", self, Vector3(0, h(0, 0) + 2.2, 0), 120, 10.0, Vector3(14, 2.0, 14), Vector2(0.08, 0.08), up, 1.3)
	_emitter("FirefliesSlope", self, Vector3(25, h(25, 0) + 2.0, 8), 140, 10.0, Vector3(40, 3.0, 40), Vector2(0.2, 0.2), up, 1.6)
	_emitter("FirefliesLens", cam, Vector3(0, 0, -1.5), 6, 8.0, Vector3(1.2, 0.6, 0.8), Vector2(0.025, 0.025), Vector3.ZERO, 0.5)


# ---------------------------------------------------------------- sky, light, grade

func _environment() -> void:
	env = Environment.new()
	if use_backdrop:
		# the photographic plate (assets/sky_backdrop.png) is the sky, far hills, misty valley and village: the 3D
		# scene renders over a transparent background and the final pass puts the plate behind it, raw
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.background_color = Color(0, 0, 0, 0)
	else:
		env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skm := ShaderMaterial.new()
	skm.shader = load("res://shaders/starfall/milky_sky.gdshader")
	if ResourceLoader.exists("res://assets/sky/eso_milky_way/eso0932a_6000x3000.jpg"):   # the --eso-sky fallback (not shipped)
		skm.set_shader_parameter("pano", load("res://assets/sky/eso_milky_way/eso0932a_6000x3000.jpg"))
	skm.set_shader_parameter("sky_rot", _sky_rotation())
	skm.set_shader_parameter("meteor_heading", deg_to_rad(5.0))
	sky.sky_material = skm
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	if use_backdrop:
		env.sky = null
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.06, 0.07, 0.18)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if use_backdrop else Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	RenderProfile.apply_to_environment(env)
	env.ssr_enabled = false
	env.ssil_enabled = false
	env.volumetric_fog_enabled = false              # calm: the valley mist is height fog
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.5                    # moonlit white cloth never blooms; fireflies and petals do
	env.glow_hdr_scale = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for lv in [[0, 0.0], [1, 0.2], [2, 0.6], [3, 1.0], [4, 0.9], [5, 0.6], [6, 0.3]]:
		env.set_glow_level(lv[0], lv[1])
	# depth haze turns the far hills violet; height fog fills the valley with mist
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.045, 0.04, 0.12)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	env.fog_height = -10.0
	env.fog_height_density = 0.09
	if use_backdrop:
		# where the falling ground meets the painted hills: a soft height mist in the plate's own haze colour
		env.fog_light_color = Color(0.13, 0.12, 0.28)
		env.fog_density = 0.0035
		env.fog_height = _bed_h - 4.0
		env.fog_height_density = 0.22
	env.adjustment_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## World -> galactic frame: the galactic core sits low over the valley and the band arches up and across the sky
## behind the tree, the way the reference frames it.
func _sky_dir(az_deg: float, el_deg: float) -> Vector3:
	# azimuth from north (-Z) toward east (+X)
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


func _sky_rotation() -> Basis:
	var core := _sky_dir(CORE_AZ, CORE_EL)
	var arch := _sky_dir(ARCH_AZ, ARCH_EL)
	var n := core.cross(arch).normalized()
	var zg := -core
	var yg := (n - zg * n.dot(zg)).normalized()
	var xg := yg.cross(zg)
	return Basis(xg, yg, zg).transposed()


func _lights() -> void:
	skylight = DirectionalLight3D.new()
	skylight.name = "Starlight"
	skylight.light_color = Color(0.5, 0.56, 1.0)
	skylight.light_energy = 1.55
	skylight.shadow_enabled = true
	skylight.light_angular_distance = 3.0
	skylight.directional_shadow_max_distance = 40.0
	skylight.light_cull_mask = 1
	skylight.shadow_caster_mask = 1 | CHAR_LAYER
	skylight.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(skylight)
	skylight.look_at_from_position(Vector3.ZERO, Vector3(-0.35, -1.0, 0.25), Vector3.FORWARD)
	# the two of them are lit by ONE soft moonlight (same direction as the world's, gentler, no cast shadows on them)
	var cm := DirectionalLight3D.new()
	cm.name = "MoonlightOnThem"
	cm.light_color = Color(0.78, 0.84, 1.0)
	cm.light_energy = 1.05
	cm.light_specular = 0.15
	cm.shadow_enabled = false
	cm.light_cull_mask = CHAR_LAYER
	cm.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(cm)
	cm.look_at_from_position(Vector3.ZERO, Vector3(-0.35, -1.0, 0.25), Vector3.FORWARD)



func _post() -> void:
	var q := MeshInstance3D.new()
	q.name = "MotionBlur"
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	q.mesh = qm
	blur_mat = ShaderMaterial.new()
	blur_mat.shader = load("res://shaders/moonbloom/motion_blur.gdshader")
	blur_mat.set_shader_parameter("shutter", 0.35)
	blur_mat.render_priority = -128
	q.material_override = blur_mat
	q.extra_cull_margin = 16384.0
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(q)
	q.position = Vector3(0, 0, -0.5)
	_prev_view = cam.global_transform.affine_inverse()
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade_mat = ShaderMaterial.new()
	grade_mat.shader = load("res://shaders/moonbloom/grade.gdshader")
	# deep blue and violet, crushed blacks; the Milky Way and fireflies stay the brightest things; calm
	grade_mat.set_shader_parameter("shadow_col", Color(0.002, 0.004, 0.012))
	grade_mat.set_shader_parameter("mid_col", Color(0.06, 0.09, 0.3))
	grade_mat.set_shader_parameter("high_col", Color(0.82, 0.86, 1.0))
	grade_mat.set_shader_parameter("black_point", 0.0)
	grade_mat.set_shader_parameter("white_point", 1.0)
	grade_mat.set_shader_parameter("keep_hue", 0.72)
	grade_mat.set_shader_parameter("saturation", 1.05)
	grade_mat.set_shader_parameter("vignette", 0.42)
	grade_mat.set_shader_parameter("aberration", 0.0)
	grade_mat.set_shader_parameter("grain", 0.012)
	grade_mat.set_shader_parameter("lift_gamma", 0.85)
	grade_mat.set_shader_parameter("char_keep", 0.5)
	grade_mat.set_shader_parameter("char_real", 1.0)            # the two of them in their real colours
	if use_backdrop:
		grade_mat.set_shader_parameter("use_scene_tex", true)
		grade_mat.set_shader_parameter("scene_tex", world_vp.get_texture())
		layer.layer = 1
		var plate: Texture2D = load("res://assets/sky_backdrop.png")
		grade_mat.set_shader_parameter("use_backdrop", true)
		grade_mat.set_shader_parameter("backdrop", plate)
		grade_mat.set_shader_parameter("backdrop_aspect", float(plate.get_width()) / float(plate.get_height()))
		var vs := get_viewport().get_visible_rect().size
		grade_mat.set_shader_parameter("screen_aspect", vs.x / vs.y)
		grade_mat.set_shader_parameter("meteor_energy", 1.6)
		# anchored in the world: the painted far hills always sit on the true horizon, just above the 3D hill falling
		# away; centred behind the tree as the wide shot sees it. Exactly 180 degrees wide, so the plate and its mirror
		# close the circle with no seam behind the camera; as tall as its own aspect makes it (~100 degrees)
		var span_h := PI
		grade_mat.set_shader_parameter("plate_world", true)
		grade_mat.set_shader_parameter("plate_span_h", span_h)
		grade_mat.set_shader_parameter("plate_span_v", span_h * float(plate.get_height()) / float(plate.get_width()))
		grade_mat.set_shader_parameter("plate_az", deg_to_rad(PLATE_AZ))
		grade_mat.set_shader_parameter("plate_horizon_v", 0.715)
	cr.material = grade_mat
	layer.add_child(cr)
	cr.visible = not RenderProfile.options.has("no-grade")
	# (no motion-blur quad over the backdrop: it is a full-screen pass that would paint the transparent sky opaque)
	q.visible = not RenderProfile.options.has("no-blur") and not use_backdrop


func _mask_pass() -> void:
	mask_vp = SubViewport.new()
	mask_vp.name = "CharacterMask"
	mask_vp.size = Vector2i(get_viewport().get_visible_rect().size / 2.0)
	mask_vp.transparent_bg = true
	mask_vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	mask_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mask_vp.positional_shadow_atlas_size = 0
	add_child(mask_vp)
	mask_cam = Camera3D.new()
	mask_cam.cull_mask = CHAR_LAYER
	mask_cam.near = cam.near
	mask_cam.far = 80.0
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	mask_cam.environment = e
	mask_vp.add_child(mask_cam)
	mask_cam.current = true
	grade_mat.set_shader_parameter("char_mask", mask_vp.get_texture())
	grade_mat.set_shader_parameter("debug_skin", RenderProfile.options.has("skin-debug"))


# ---------------------------------------------------------------- the two of them

func _characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)
	WorldState.register_mind("luna")
	for spec in [["mika", "Mika"], ["luna", "Luna"]]:
		var who: String = spec[0]
		var c := WorldCharacter.new()
		c.name = spec[1]
		c.character_id = who
		c.display_name = spec[1]
		c.avatar_path = TransformationDirector.avatar_for(who)
		chars.add_child(c)
		var hs := _head_target(who)
		c.global_position = hs + _feet_dir(who) * 0.7 + Vector3(0, 0.05, 0)
		characters[who] = c
		lie_dir[who] = _feet_dir(who)
		head_spot[who] = hs
		c.play_gesture("lie_loop", 0.05, 0.4)
		c.set_ground_pose("lie", 0.05)
		print("[starfall] %s avatar=%s stage=%s" % [who, c.avatar_path, String(c.stage().get("id", "?"))])
	_character_look()


func _bone(c: WorldCharacter, names: Array) -> Variant:
	if c.skeleton == null:
		return null
	for n in names:
		var i := c.skeleton.find_bone(n)
		if i >= 0:
			return c.skeleton.global_transform * c.skeleton.get_bone_global_pose(i).origin
	return null


func _head(who: String) -> Vector3:
	var hp = _bone(characters[who], ["Head"])
	return (hp as Vector3) + Vector3(0, 0.06, 0) if hp != null else head_spot[who] + Vector3(0, 0.12, 0)


## Once the lying pose has settled: turn and move each of them so her head lies on its spot and her body points
## down the hill (measured from her own bones, so any rig fits), then give the springs their ground, the arms
## their poses and the faces their life.
func _settle() -> void:
	await get_tree().create_timer(0.9).timeout
	for pass_i in 2:
		for who in characters:
			var c: WorldCharacter = characters[who]
			var hd = _bone(c, ["Head"])
			var hp = _bone(c, ["Hips"])
			if hd == null or hp == null:
				continue
			var cur: Vector3 = (hp as Vector3) - (hd as Vector3)
			cur.y = 0
			var want: Vector3 = lie_dir[who]
			var ang := cur.normalized().signed_angle_to(want, Vector3.UP)
			c.rotate_y(ang)
			await get_tree().process_frame
			await get_tree().process_frame
			hd = _bone(c, ["Head"])
			var tgt: Vector3 = head_spot[who]
			var off := Vector3(tgt.x - (hd as Vector3).x, 0, tgt.z - (hd as Vector3).z)
			c.global_position += off
			await get_tree().process_frame
	for who in characters:
		var c: WorldCharacter = characters[who]
		c.set_physics_process(false)                 # placed, not simulated (no sliding down the slope)
		var ld: Vector3 = lie_dir[who]
		var hd0 = _bone(c, ["Head"])
		var pivot: Vector3 = hd0 if hd0 != null else c.global_position
		var xf := c.global_transform
		var rot := Basis(ld.cross(Vector3.UP).normalized(), -deg_to_rad(BED_SLOPE))
		xf.origin = pivot + rot * (xf.origin - pivot)
		xf.basis = rot * xf.basis
		c.global_transform = xf
	await get_tree().process_frame
	await get_tree().process_frame
	for who in characters:
		var c: WorldCharacter = characters[who]
		var hd = _bone(c, ["Head"])
		if hd != null:
			var tgt: Vector3 = head_spot[who]
			c.global_position += Vector3(tgt.x - (hd as Vector3).x, (h(tgt.x, tgt.z) + 0.125) - (hd as Vector3).y, tgt.z - (hd as Vector3).z)
	await get_tree().process_frame
	for who in characters:
		var c: WorldCharacter = characters[who]
		if not RenderProfile.options.has("no-ground-springs"):
			_ground_springs(c, who)
		if not RenderProfile.options.has("no-arms"):
			_pose_arms(c, who)
		_char_layers(c)
		c.look_head_at(_head(who) + Vector3(0, 3.0, 0))
		if c.head_look:
			c.head_look.influence = 0.5
	_placed = true
	print("[starfall] placed: ", _grounding())


## The spring bones (hair, skirt) get the ground: a huge sphere whose top is the grass under her, so the hair fans
## out on the grass instead of hanging through it.
func _ground_springs(c: WorldCharacter, who: String) -> void:
	var sec := c.avatar.find_child("secondary", true, false)
	if sec == null or sec.get("spring_bones") == null:
		return
	# One sphere per chain: the solver keeps each joint's CENTRE at least (sphere radius + the joint's own hit radius)
	# from the sphere's centre, and this rig's joints are big (the stage profile scales hair hit radii x2.2). So each
	# chain's sphere top sits below the grass by that chain's largest joint radius: every joint then rests ~2 cm above
	# the grass. (One shared sphere pushed whole strands and skirts straight up off the ground.)
	# lying down: the cloth (skirt, cape, sleeves, sashes, tassels, pendants) does not simulate at all - it lies flat in
	# its own pose on the grass; only the hair moves, firmly damped, so it settles in one smooth fan on the grass
	# lying down, every chain keeps simulating, heavily damped, on the ground collider below:
	#   hair  - a little firmer and well damped: it settles in one smooth fan on the grass, no jitter
	#   skirt / cape / sash - soft and heavy: the fabric sinks and lies flat on the grass round her
	#   sleeves (incl. the sheer drapes) - soft, extra gravity: they hang DOWN from a raised arm, loose
	#   ears / tassels / pendants - just damped
	var kept = sec.spring_bones.duplicate()
	kept.clear()
	var kinds := {}
	for sb in sec.spring_bones:
		var cm := String(sb.comment)
		var d: Resource = (sb as Resource).duplicate()
		var k := "other"
		if cm.begins_with("Hair") and not cm.begins_with("HairRibbon"):
			k = "hair"
			d.set("stiffness_scale", float(d.get("stiffness_scale")) * 1.25)
			d.set("drag_force_scale", clampf(float(d.get("drag_force_scale")) * 1.5, 0.0, 0.85))
			d.set("gravity_scale", float(d.get("gravity_scale")) * 0.9)
		elif cm.begins_with("Skirt") or cm.begins_with("Cape") or cm.begins_with("Sash"):
			k = "cloth"
			d.set("stiffness_scale", float(d.get("stiffness_scale")) * 0.45)
			d.set("drag_force_scale", 0.88)
			d.set("gravity_scale", float(d.get("gravity_scale")) * 1.4)
		elif cm.begins_with("Sleeve"):
			k = "sleeve"
			# barely any memory of its shape, real weight: the sheer drape falls toward the grass from a raised arm
			d.set("stiffness_scale", float(d.get("stiffness_scale")) * 0.08)
			d.set("drag_force_scale", 0.65)
			d.set("gravity_scale", float(d.get("gravity_scale")) * 3.0)
		elif not cm.begins_with("Ear"):
			d.set("drag_force_scale", clampf(float(d.get("drag_force_scale")) * 1.5, 0.0, 0.85))
		kinds[k] = int(kinds.get(k, 0)) + 1
		kept.append(d)
	sec.spring_bones = kept
	print("[starfall] %s: lying springs %s" % [who, kinds])
	var R := 40.0
	var hs: Vector3 = head_spot[who]
	var n := 0
	for sb in sec.spring_bones:
		# a joint's hit radius = hit_radius_scale * its per-joint value, or the scale itself when the chain has no
		# per-joint list (VRM 1.0 imports here keep everything in the scale)
		var hr: PackedFloat64Array = sb.hit_radius
		var rmax := 0.0
		for v in hr:
			rmax = maxf(rmax, v)
		rmax = float(sb.hit_radius_scale) * (rmax if not hr.is_empty() else 1.0)
		var ball := Node3D.new()
		ball.name = "GroundBall_%s_%d" % [who, n]
		add_child(ball)
		# addons/vrm/vrm_secondary.gd passes the skeleton's transform where VrmRuntimeCollider.update() expects its
		# inverse, so a node-attached collider ends up at S * S * node instead of S^-1 * S * ... ; placing the node at
		# S^-1 * S^-1 * (the point we mean) cancels that (the skeleton stays put once she lies down).
		var nrm := bed_normal()
		var surf := Vector3(hs.x, bed_plane(hs.x, hs.z), hs.z)
		var want := Transform3D(Basis.IDENTITY, surf + nrm * (0.02 - rmax - R))
		var s_inv := c.skeleton.global_transform.affine_inverse()
		ball.global_transform = s_inv * s_inv * want
		var col = load("res://addons/vrm/vrm_collider.gd").new()
		col.radius = R
		col.node_path = ball.get_path()
		var grp = load("res://addons/vrm/vrm_collider_group.gd").new()
		grp.colliders.append(col)
		sb.collider_groups.append(grp)
		n += 1
	if sec.has_method("_on_recreate_collider"):
		sec._on_recreate_collider()
	var sk := c.skeleton
	print("[starfall] %s: ground collider on %d spring chains; skeleton scale %s, avatar scale %s, secondary %s" % [who, n,
		sk.global_transform.basis.get_scale(), c.avatar.scale, sec.get_path()])


# ---------------------------------------------------------------- arms (two-bone aim on top of the lying clip)

class LimbPose extends SkeletonModifier3D:
	## arms: [{upper, lower, hand, target: Callable -> world point, pole: Callable -> world direction, w: Callable -> 0..1,
	##         straight_wrist: bool}]
	## curls: [{bones: [proximal, intermediate, distal], deg: [a, b, c]}] - fingers bent toward the palm (measured from
	##        her own hand bones each frame); straight: [bones] - fingers held fully extended (their rest pose)
	var arms: Array = []
	var curls: Array = []
	var straight: Array = []
	var hand_bones := {}             # {hand, index, middle, little, thumb} bone ids of the posed hand
	var finger_w: Callable

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		var inv := sk.global_transform.affine_inverse()
		for a in arms:
			var w: float = (a.w as Callable).call()
			if w <= 0.001:
				continue
			var tgt: Vector3 = inv * ((a.target as Callable).call() as Vector3)
			var pole: Vector3 = (inv.basis * ((a.pole as Callable).call() as Vector3)).normalized()
			_two_bone(sk, a.upper, a.lower, a.hand, tgt, pole, w)
			if bool(a.get("straight_wrist", false)):
				# the hand continues the forearm's line (no broken wrist)
				var e := sk.get_bone_global_pose(a.lower).origin
				var hp := sk.get_bone_global_pose(a.hand).origin
				var mid := sk.get_bone_global_pose(hand_bones.middle).origin
				_aim(sk, a.hand, mid, hp + (hp - e).normalized() * mid.distance_to(hp), w)
		var fw: float = finger_w.call() if finger_w.is_valid() else 0.0
		if fw <= 0.001 or hand_bones.is_empty():
			return
		for b in straight:
			sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b).slerp(sk.get_bone_rest(b).basis.get_rotation_quaternion(), fw))
		var palm := _palm_normal(sk)
		for c in curls:
			for i in (c.bones as Array).size():
				var b: int = c.bones[i]
				var kids := sk.get_bone_children(b)
				if b < 0 or kids.is_empty():
					continue
				var g := sk.get_bone_global_pose(b)
				var d := (sk.get_bone_global_pose(kids[0]).origin - g.origin).normalized()
				var axis := d.cross(palm).normalized()
				if axis.length() < 0.5:
					continue
				_rotate_global(sk, b, Basis(axis, deg_to_rad(float(c.deg[i])) * fw))

	## The palm's outward normal (skeleton space), the side the fingers close toward: the thumb sits on that side.
	func _palm_normal(sk: Skeleton3D) -> Vector3:
		var h := sk.get_bone_global_pose(hand_bones.hand).origin
		var i := sk.get_bone_global_pose(hand_bones.index).origin
		var l := sk.get_bone_global_pose(hand_bones.little).origin
		var m := sk.get_bone_global_pose(hand_bones.middle).origin
		var t := sk.get_bone_global_pose(hand_bones.thumb).origin
		var n := (m - h).cross(i - l).normalized()
		return n if n.dot(t - (i + l) * 0.5) >= 0.0 else -n

	func _rotate_global(sk: Skeleton3D, bone: int, r: Basis) -> void:
		var g := sk.get_bone_global_pose(bone)
		var p := sk.get_bone_parent(bone)
		var pg := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
		sk.set_bone_pose_rotation(bone, (pg.inverse() * (r * g.basis.orthonormalized())).get_rotation_quaternion())

	func _two_bone(sk: Skeleton3D, u: int, l: int, hnd: int, tgt: Vector3, pole: Vector3, w: float) -> void:
		var s := sk.get_bone_global_pose(u).origin
		var e := sk.get_bone_global_pose(l).origin
		var hp := sk.get_bone_global_pose(hnd).origin
		var a := s.distance_to(e)
		var b := e.distance_to(hp)
		var to := tgt - s
		var d := clampf(to.length(), 0.05, a + b - 0.002)
		var dir := to.normalized()
		var ca := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
		var perp := (pole - dir * pole.dot(dir)).normalized()
		var elbow := s + dir * a * ca + perp * a * sqrt(1.0 - ca * ca)
		_aim(sk, u, e, elbow, w)
		hp = sk.get_bone_global_pose(hnd).origin
		_aim(sk, l, hp, s + dir * d, w)

	func _aim(sk: Skeleton3D, bone: int, from_pt: Vector3, to_pt: Vector3, w: float) -> void:
		var g := sk.get_bone_global_pose(bone)
		var d0 := (from_pt - g.origin).normalized()
		var d1 := (to_pt - g.origin).normalized()
		if d0.dot(d1) > 0.99999:
			return
		_rotate_global(sk, bone, Basis(Quaternion.IDENTITY.slerp(Quaternion(d0, d1), w)))


## Mika: right arm folded behind her head, left hand resting on her waist.
## Luna: left hand on her waist; her right hand rests on her chest and, every so often, rises over a second to point
## up at a star - upper arm 70-80 degrees up from the grass, elbow a little bent, forearm and wrist in one line, index
## finger straight, the other three curled into the palm, thumb tucked - holds for a few seconds with a tiny wrist
## move, then comes slowly back down. Her head and eyes follow where she points.
func _pose_arms(c: WorldCharacter, who: String) -> void:
	var sk := c.skeleton
	var lp := LimbPose.new()
	lp.name = "LimbPose"
	sk.add_child(lp)
	var B := func(n: String) -> int: return sk.find_bone(n)
	var bw := func(names: Array) -> Vector3:
		var v = _bone(c, names)
		return v if v != null else c.global_position
	var up := bed_normal()
	var feet := func() -> Vector3: return lie_dir[who]
	var right := func() -> Vector3:
		var r: Vector3 = (bw.call(["RightUpperArm"]) as Vector3) - (bw.call(["LeftUpperArm"]) as Vector3)
		r -= up * r.dot(up)
		return r.normalized()
	if who == "mika":
		lp.arms.append({"upper": B.call("RightUpperArm"), "lower": B.call("RightLowerArm"), "hand": B.call("RightHand"),
			"target": func() -> Vector3: return _head("mika") - up * 0.11 - (feet.call() as Vector3) * 0.03 + (right.call() as Vector3) * 0.07,
			"pole": func() -> Vector3: return (right.call() as Vector3) * 0.8 - (feet.call() as Vector3) * 0.7 + up * 0.15,
			"w": func() -> float: return 1.0})
		lp.arms.append({"upper": B.call("LeftUpperArm"), "lower": B.call("LeftLowerArm"), "hand": B.call("LeftHand"),
			"target": func() -> Vector3: return (bw.call(["Hips"]) as Vector3) - (feet.call() as Vector3) * 0.2 + up * 0.13 - (right.call() as Vector3) * 0.02,
			"pole": func() -> Vector3: return -(right.call() as Vector3) - up * 0.4,
			"w": func() -> float: return 1.0})
	else:
		lp.arms.append({"upper": B.call("LeftUpperArm"), "lower": B.call("LeftLowerArm"), "hand": B.call("LeftHand"),
			"target": func() -> Vector3: return (bw.call(["Hips"]) as Vector3) - (feet.call() as Vector3) * 0.15 + up * 0.13 - (right.call() as Vector3) * 0.06,
			"pole": func() -> Vector3: return -(right.call() as Vector3) - up * 0.4,
			"w": func() -> float: return 1.0})
		var arm_len := (bw.call(["RightUpperArm"]) as Vector3).distance_to(bw.call(["RightLowerArm"])) + (bw.call(["RightLowerArm"]) as Vector3).distance_to(bw.call(["RightHand"]))
		lp.arms.append({"upper": B.call("RightUpperArm"), "lower": B.call("RightLowerArm"), "hand": B.call("RightHand"), "straight_wrist": true,
			"target": func() -> Vector3:
				var sh: Vector3 = bw.call(["RightUpperArm"])
				var rest: Vector3 = (bw.call(["UpperChest", "Chest"]) as Vector3) + up * 0.14 + (right.call() as Vector3) * 0.02 + (feet.call() as Vector3) * 0.08
				# 76 degrees up from the grass, leaning toward her head and a little outward; a tiny wrist move in the hold
				var dir: Vector3 = (up * sin(deg_to_rad(76.0)) - (feet.call() as Vector3) * cos(deg_to_rad(76.0)) + (right.call() as Vector3) * 0.08).normalized()
				var wob: Vector3 = (right.call() as Vector3) * sin(_t * 1.6) * 0.012 + (feet.call() as Vector3) * sin(_t * 1.1 + 1.0) * 0.008
				var pt: Vector3 = sh + dir * arm_len * 0.95 + wob * _point_w
				var e := _point_w * _point_w * (3.0 - 2.0 * _point_w)
				return rest.lerp(pt, e),
			"pole": func() -> Vector3: return (feet.call() as Vector3) * 0.8 + (right.call() as Vector3) * 0.5 - up * 0.1,
			"w": func() -> float: return 1.0})
		lp.hand_bones = {"hand": B.call("RightHand"), "index": B.call("RightIndexProximal"), "middle": B.call("RightMiddleProximal"),
			"little": B.call("RightLittleProximal"), "thumb": B.call("RightThumbProximal")}
		lp.straight = [B.call("RightIndexProximal"), B.call("RightIndexIntermediate"), B.call("RightIndexDistal")]
		for f in [["Middle", [78.0, 92.0, 60.0]], ["Ring", [82.0, 94.0, 60.0]], ["Little", [86.0, 92.0, 58.0]], ["Thumb", [24.0, 38.0, 30.0]]]:
			var names := ["Right%sMetacarpal" % f[0], "Right%sProximal" % f[0], "Right%sDistal" % f[0]] if f[0] == "Thumb" else \
				["Right%sProximal" % f[0], "Right%sIntermediate" % f[0], "Right%sDistal" % f[0]]
			lp.curls.append({"bones": names.map(func(n): return sk.find_bone(n)), "deg": f[1]})
		lp.finger_w = func() -> float: return clampf(_point_w * 1.4, 0.0, 1.0)
	limbs[who] = lp


## Luna's pointing, as a little scene of its own: rest a while, raise the arm over a second, hold 4 s on a star,
## lower it slowly (1.8 s). In the clip and in QA it is timed so the medium shot catches the hold.
func _update_pointing(delta: float) -> void:
	_point_clock += delta
	var durs := {"rest": _point_rest, "raise": 1.0, "hold": 4.0, "lower": 1.8}
	if _point_hold:
		_point_state = "hold"
	elif _point_clock >= float(durs[_point_state]):
		_point_clock = 0.0
		_point_state = {"rest": "raise", "raise": "hold", "hold": "lower", "lower": "rest"}[_point_state]
		if _point_state == "rest":
			_point_rest = randf_range(6.0, 9.0)
	match _point_state:
		"raise": _point_w = clampf(_point_clock / 1.0, 0.0, 1.0)
		"hold": _point_w = 1.0
		"lower": _point_w = 1.0 - clampf(_point_clock / 1.8, 0.0, 1.0)
		_: _point_w = 0.0


# ---------------------------------------------------------------- their look (scene-only; nothing in their files changes)

func _character_look() -> void:
	# (their own materials, untouched: real colours, no rim / matcap / emission added)
	for who in characters:
		var c: WorldCharacter = characters[who]
		_char_layers(c)
		c.apply_light_balance(1.05, env.ambient_light_energy)
		if c.face:
			c.face.set_baseline({"happy": 0.42, "relaxed": 0.35} if who == "mika" else {"happy": 0.34, "relaxed": 0.4})
	for t in [0.5, 2.0, 5.0]:
		get_tree().create_timer(t).timeout.connect(func():
			for who in characters:
				_char_layers(characters[who]))


func _char_layers(c: WorldCharacter) -> void:
	for vi in c.find_children("*", "VisualInstance3D", true, false):
		(vi as VisualInstance3D).layers = LAYER[c.character_id]


func _tune_material(who: String, nm: String, sm: ShaderMaterial, matcap: Texture2D) -> void:
	if sm.get_shader_parameter("_ShadeColor") == null:
		return
	if "_SKIN" in nm:
		sm.set_shader_parameter("_ShadeColor", Color(0.9, 0.82, 0.94) if who == "mika" else Color(0.88, 0.78, 0.88))
		sm.set_shader_parameter("_RimColor", Color(0.08, 0.08, 0.2))
		sm.set_shader_parameter("_RimFresnelPower", 4.0)
		sm.set_shader_parameter("_RimLift", 0.0)
		if "Body" in nm:
			sm.set_shader_parameter("_ReceiveShadowRate", 0.4)
	elif "Hair" in nm and not "Flower" in nm:
		sm.set_shader_parameter("_ShadeColor", Color(0.8, 0.8, 0.97) if who == "mika" else Color(0.76, 0.7, 0.9))
		sm.set_shader_parameter("_RimColor", Color(0.4, 0.42, 0.9))
		sm.set_shader_parameter("_RimFresnelPower", 3.2)
		sm.set_shader_parameter("_RimLift", 0.05)
		sm.set_shader_parameter("_RimLightingMix", 0.3)
		sm.set_shader_parameter("_SphereAdd", matcap)
		sm.set_shader_parameter("_MatcapColor", Color(0.26, 0.28, 0.42) if who == "mika" else Color(0.45, 0.45, 0.6))
		sm.set_shader_parameter("_ReceiveShadowRate", 0.5)
	elif "EyeHighlight" in nm:
		sm.set_shader_parameter("_EmissionColor", Color(1, 1, 1))
		sm.set_shader_parameter("_EmissionMultiplier", 1.5)
		var tex = sm.get_shader_parameter("_MainTex")
		if tex:
			sm.set_shader_parameter("_EmissionMap", tex)
	elif nm.begins_with("L1_"):
		sm.set_shader_parameter("_RimColor", Color(0.14, 0.15, 0.36))
		sm.set_shader_parameter("_RimFresnelPower", 3.5)
		sm.set_shader_parameter("_RimLift", 0.03)


func _hair_matcap() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		for i in n:
			var x := (i + 0.5) / n * 2.0 - 1.0
			var y := (j + 0.5) / n * 2.0 - 1.0
			var r2 := x * x + y * y
			if r2 > 1.0:
				img.set_pixel(i, j, Color(0, 0, 0))
				continue
			var v := clampf(exp(-pow((y + 0.42) / 0.13, 2.0)) * (1.0 - x * x * 0.7) * 0.85 + exp(-r2 * 2.5) * 0.18, 0.0, 1.0)
			img.set_pixel(i, j, Color(v * 0.9, v * 0.92, v))
	return ImageTexture.create_from_image(img)


## Faces never frozen: small head turns (toward each other, up at the sky, to the lens in a close-up), gentle smiles
## and soft moods; the face rig blinks on its own. Luna points at the sky now and then.
func _animate_faces(delta: float) -> void:
	if not _placed:
		return
	_update_pointing(delta)
	for who in characters:
		var c: WorldCharacter = characters[who]
		_look_t[who] = float(_look_t[who]) - delta
		if float(_look_t[who]) <= 0.0:
			_look_t[who] = randf_range(2.5, 5.5)
			var other := "luna" if who == "mika" else "mika"
			var r := randf()
			if shot == who:
				_look_tgt[who] = "cam"
			elif r < 0.4:
				_look_tgt[who] = "sky"
			elif r < 0.75:
				_look_tgt[who] = other
			else:
				_look_tgt[who] = "point"
		var tgt := _head(who) + Vector3(0, 3.0, 0) - (lie_dir[who] as Vector3) * 0.6
		match String(_look_tgt.get(who, "sky")):
			"cam":
				tgt = cam.global_position
			"mika", "luna":
				tgt = _head(String(_look_tgt[who])) + Vector3(0, 0.25, 0)
			"point":
				tgt = _head("luna") + Vector3(0, 2.5, 0) - (lie_dir["luna"] as Vector3) * 1.2
		if who == "luna" and _point_w > 0.25:
			# her head turns a little toward where she points, her eyes go up to the star
			var hand = _bone(c, ["RightHand"])
			var sh = _bone(c, ["RightUpperArm"])
			if hand != null and sh != null:
				tgt = (hand as Vector3) + ((hand as Vector3) - (sh as Vector3)).normalized() * 4.0
		var ht: Node3D = c.get("_head_target")
		if ht:
			ht.global_position = ht.global_position.lerp(tgt, clampf(delta * 1.8, 0.0, 1.0))
		_mood_t[who] = float(_mood_t[who]) - delta
		if float(_mood_t[who]) <= 0.0 and c.face:
			_mood_t[who] = randf_range(5.0, 9.5)
			var moods := ["happy", "shy", "happy", "relaxed"] if who == "mika" else ["happy", "relaxed", "thoughtful", "happy"]
			c.face.pulse(moods[randi() % moods.size()], randf_range(0.3, 0.6), randf_range(1.6, 3.0))


# ---------------------------------------------------------------- cameras

## 1 wide: from down the hill, the tree and the two small under a huge Milky Way (slow push-in)
## 2 overhead: high straight down at the two of them whole, hair spread on the grass, flowers round them (slow turn)
## 3 side: medium-wide from beside them, both full length in the grass, the trunk and roots behind (slow push)
## 4 pov: low, well behind their heads, looking up past them at the sky (slow tilt up)
## (no close-ups, ever: docs/world_look_rules.md)
func _shot(nm: String, t: float) -> Dictionary:
	var e := t * t * (3.0 - 2.0 * t)
	var hm := _head("mika")
	var hl := _head("luna")
	var mid := (hm + hl) * 0.5
	var f := (Vector3(FEET_DIR.x, 0, FEET_DIR.y)).normalized()
	var side := f.cross(Vector3.UP).normalized()
	match nm:
		"core":
			var core := _sky_dir(CORE_AZ, CORE_EL)
			var p0 := Vector3(BED.x, _bed_h + 1.6, BED.y)
			return {"pos": p0, "at": p0 + core * 10.0, "up": Vector3.UP, "fov": 70.0, "focus": p0 + core * 50.0}
		"tree":
			return {"pos": Vector3(4.0, h(4, 14) + 1.6, 14.0), "at": Vector3(0, h(0, 0) + 5.0, 0), "up": Vector3.UP, "fov": 60.0, "focus": Vector3(0, h(0, 0) + 5.0, 0)}
		"overhead":
			var p := mid + f * 0.62 + Vector3(0, lerpf(3.6, 3.25, e), 0) + side * lerpf(0.08, -0.08, e)
			return {"pos": p, "at": mid + f * 0.62, "up": -f.rotated(Vector3.UP, deg_to_rad(lerpf(-4.0, 4.0, e))), "fov": 50.0, "focus": mid}
		"pov":
			var p := mid - f * lerpf(3.4, 3.1, e) + Vector3(0, 0.6, 0) + side * 0.1
			var at := mid + f * 4.0 + Vector3(0, lerpf(1.7, 2.6, e), 0)
			return {"pos": p, "at": at, "up": Vector3.UP, "fov": 60.0, "focus": mid + f * 0.4}
		"luna_point":
			# medium-wide from Luna's outer side, a little toward her feet and low: her whole body and the raised
			# arm and hand against the sky (her face well under the 10% rule)
			var lf: Vector3 = lie_dir["luna"]
			var outer := -lf.cross(Vector3.UP).normalized()
			var chest := hl + lf * 0.35
			# from the uphill side, looking across and down the slope: behind her the ground falls away and the painted
			# hills, mist and village lights stay above it
			var p := chest + outer * lerpf(3.1, 2.8, e) - lf * 1.6 + Vector3(0, lerpf(1.15, 1.05, e), 0)
			return {"pos": p, "at": chest + Vector3(0, 0.35, 0) + lf * 0.5, "up": Vector3.UP, "fov": 50.0, "focus": chest}
		"side":
			var body := mid + f * 0.75
			var p := body + side * lerpf(4.3, 3.9, e) + Vector3(0, lerpf(1.8, 1.6, e), 0) - f * 1.8
			return {"pos": p, "at": body + Vector3(0, 0.05, 0) + f * 0.6, "up": Vector3.UP, "fov": 46.0, "focus": body}
	# wide (default): from down the hill
	var gx := WIDE_CAM.x + lerpf(0.0, 0.6, e)
	var gz := WIDE_CAM.y - lerpf(0.0, 1.6, e)
	var p := Vector3(gx, h(gx, gz) + 2.5, gz)
	return {"pos": p, "at": Vector3(1.0, h(0, 0) + 5.2, 0.5), "up": Vector3.UP, "fov": 62.0, "focus": mid}


func _cameras() -> void:
	cam = Camera3D.new()
	cam.name = "StreamCamera"
	cam.near = 0.03
	cam.far = 2500.0
	var host: Node = self
	if use_backdrop:
		world_vp = SubViewport.new()
		world_vp.name = "World3D"
		world_vp.size = Vector2i(get_viewport().get_visible_rect().size)
		world_vp.transparent_bg = true
		world_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(world_vp)
		RenderProfile.apply_to_viewport(world_vp)
		# FSR 2 / TAA resolve to an opaque image: the transparent background the plate shows through needs plain
		# scaling with FXAA (no MSAA: with ~15 M grass primitives it cost the side shot its 30 fps)
		world_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		world_vp.scaling_3d_scale = 1.0
		world_vp.use_taa = false
		world_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		world_vp.msaa_3d = Viewport.MSAA_DISABLED
		host = world_vp
	attrs = CameraAttributesPractical.new()
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_amount = 0.08
	cam.attributes = attrs
	host.add_child(cam)
	cam.current = true
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_MEDIUM, true)
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	var want := String(RenderProfile.options.get("cam", "cine"))
	if want in ["wide", "luna_point", "overhead", "side", "pov"]:
		mode = "hold"
		shot = want
	_apply_shot(0.0, true)


func _shot_len(nm: String) -> float:
	for s in LOOP:
		if s[0] == nm:
			return float(s[1])
	return 8.0


func _apply_shot(delta: float, snap := false) -> void:
	shot_t += delta
	var list: Array = SEQUENCE if RenderProfile.options.has("clip") else LOOP
	if mode == "cine":
		var dur := float(list[_seq_i % list.size()][1])
		if shot_t >= dur:
			shot_t -= dur
			_seq_i += 1
			snap = true
		shot = String(list[_seq_i % list.size()][0])
		dur = float(list[_seq_i % list.size()][1])
		_frame(_shot(shot, clampf(shot_t / dur, 0.0, 1.0)), delta, snap)
	else:
		var ping := absf(fmod(shot_t / _shot_len(shot), 2.0) - 1.0)
		_frame(_shot(shot, 1.0 - ping), delta, snap)


func _frame(s: Dictionary, delta: float, snap: bool) -> void:
	var drift := Vector3(sin(_t * 0.23) * 0.02, sin(_t * 0.17 + 1.0) * 0.012, cos(_t * 0.19) * 0.018)
	cam.fov = s.fov
	var up: Vector3 = s.up
	var fwd: Vector3 = (s.at - (s.pos + drift)).normalized()
	if absf(fwd.dot(up.normalized())) > 0.999:
		up = Vector3.FORWARD
	cam.look_at_from_position(s.pos + drift, s.at, up)
	var d: float = cam.global_position.distance_to(s.focus)
	if snap:
		_focus = d + 1.5
	_focus = lerpf(_focus, d, clampf(delta * 2.5, 0.0, 1.0))
	var close := d < 1.3
	attrs.dof_blur_amount = 0.12 if close else 0.07
	attrs.dof_blur_near_distance = maxf(_focus - (0.35 if close else 2.0), 0.05)
	attrs.dof_blur_near_transition = 0.25 if close else 1.5
	attrs.dof_blur_far_distance = _focus + (0.25 if close else 4.0)
	attrs.dof_blur_far_transition = 0.8 if close else 25.0
	_light_characters()


## The characters' key comes from the sky above their faces (a touch toward their feet and the lens); the rim grazes
## in from beyond their heads, outlining hair against the grass.
func _light_characters() -> void:
	if char_key == null or char_rim == null:
		return
	var f := Vector3(FEET_DIR.x, 0, FEET_DIR.y).normalized()
	var v := cam.global_position - (Vector3(BED.x, _bed_h, BED.y))
	v.y = 0
	var lean := v.normalized() * 0.25 if v.length() > 0.1 else Vector3.ZERO
	var key_src := (Vector3.UP + f * 0.35 + lean).normalized()
	for k in char_keys.values():
		(k as DirectionalLight3D).look_at_from_position(Vector3.ZERO, -key_src, Vector3.FORWARD if absf(key_src.y) > 0.99 else Vector3.UP)
	var rim_src := (-f + Vector3.UP * 0.35).normalized()
	char_rim.look_at_from_position(Vector3.ZERO, -rim_src, Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	blur_mat.set_shader_parameter("prev_view", Projection(_prev_view))
	_apply_shot(delta)
	_prev_view = cam.global_transform.affine_inverse()
	if mask_cam:
		mask_cam.global_transform = cam.global_transform
		mask_cam.fov = cam.fov
	if use_backdrop and grade_mat:
		grade_mat.set_shader_parameter("cam_basis", cam.global_basis.orthonormalized())
		grade_mat.set_shader_parameter("tan_half_v", tan(deg_to_rad(cam.fov) * 0.5))
	_animate_faces(delta)
	if overlay and overlay.visible:
		overlay.text = _monitor_text()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var keys := {KEY_1: "wide", KEY_2: "luna_point", KEY_3: "overhead", KEY_4: "side", KEY_5: "pov"}
		if keys.has(e.keycode):
			mode = "hold"
			shot = keys[e.keycode]
			shot_t = 0.0
			_apply_shot(0.0, true)
		elif e.keycode == KEY_0:
			mode = "cine"
			shot_t = 0.0
		elif e.keycode == KEY_F3:
			overlay.visible = not overlay.visible


func _overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	overlay = Label.new()
	overlay.position = Vector2(14, 10)
	overlay.add_theme_font_size_override("font_size", 14)
	overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	overlay.add_theme_constant_override("outline_size", 5)
	overlay.visible = false
	layer.add_child(overlay)


func _monitor_text() -> String:
	var m := monitors()
	return "%s | %.1f fps | gpu %.1f ms | draw %d | prims %dk | vram %.0f MB" % [shot, m.fps, m.gpu_ms, m.draw_calls,
		int(m.primitives / 1000), m.vram_mb]


func monitors() -> Dictionary:
	var rid := (world_vp if world_vp else get_viewport()).get_viewport_rid()
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(rid),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"texture_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"buffer_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
	}


# ---------------------------------------------------------------- clip + QA

func _clip() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	mode = "hold"
	shot = "wide"
	await get_tree().create_timer(WARMUP).timeout
	mode = "cine"
	_seq_i = 0
	shot_t = 0.0
	# she starts to point as the wide shot ends: raised during the cut, held through her medium shot
	_point_state = "rest"
	_point_clock = 0.0
	_point_rest = 2.0
	_apply_shot(0.0, true)
	await get_tree().create_timer(10.2).timeout
	get_tree().quit()


func _qa() -> void:
	var out := String(RenderProfile.options.get("out", ProjectSettings.globalize_path("user://starfall_qa")))
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)   # a covered window gets throttled
	var measure_s := float(RenderProfile.options.get("measure", "10"))
	var report := {"adapter": RenderingServer.get_video_adapter_name(), "profile": RenderProfile.profile, "max_fps": Engine.max_fps,
		"window": DisplayServer.window_get_size(), "counts": counts, "shots": {}}
	mode = "hold"
	shot = "wide"
	await get_tree().create_timer(WARMUP + 2.0).timeout
	report["grounding"] = _grounding()
	if world_vp:
		var wi := world_vp.get_texture().get_image()
		print("[starfall] world view alpha: corners %.3f %.3f top %.3f ground %.3f format=%d" % [wi.get_pixel(20, 20).a, wi.get_pixel(1900, 20).a, wi.get_pixel(960, 60).a, wi.get_pixel(960, 1040).a, wi.get_format()])
		if RenderProfile.options.has("alpha-probe"):
			for step in ["glow", "fog", "ssao", "ssil", "dof", "msaa", "fxaa", "lens"]:
				match step:
					"glow": env.glow_enabled = false
					"fog": env.fog_enabled = false
					"ssao": env.ssao_enabled = false
					"ssil": env.ssil_enabled = false
					"dof":
						attrs.dof_blur_near_enabled = false
						attrs.dof_blur_far_enabled = false
					"msaa": world_vp.msaa_3d = Viewport.MSAA_DISABLED
					"fxaa": world_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
					"lens":
						for n2 in cam.get_children():
							if n2 is GeometryInstance3D:
								(n2 as GeometryInstance3D).visible = false
				for k in 4:
					await RenderingServer.frame_post_draw
				print("[starfall] alpha after -%s: %.3f" % [step, world_vp.get_texture().get_image().get_pixel(960, 60).a])
	var names := ["wide", "luna_point", "overhead", "side", "pov"]
	if RenderProfile.options.has("core-shot"):
		names.push_front("core")
		names.push_front("tree")
	for nm in names:
		shot = nm
		shot_t = 0.0
		_point_hold = nm == "luna_point"              # catch her pointing in the medium shot
		_apply_shot(0.0, true)
		await get_tree().create_timer(2.0).timeout
		guard.worst_frac = 0.0
		var hits0 := guard.hits
		var r := await _measure(measure_s)
		r["largest_face_frac_of_frame"] = snappedf(guard.worst_frac, 0.001)
		r["guard_corrections"] = guard.hits - hits0
		r["rule_ok"] = guard.worst_frac <= FramingRule.MAX_FACE_FRAC + 0.005
		await RenderingServer.frame_post_draw
		var path := out.path_join("starfall_%s.png" % nm)
		get_viewport().get_texture().get_image().save_png(path)
		r["shot"] = path
		report.shots[nm] = r
		print("[starfall] %s: fps %.2f worst %.1f ms hitches %d gpu %.2f/%.2f ms draw %d prims %dk vram %.0f MB focused %s face %.1f%% rule_ok %s" % [nm,
			r.fps, r.worst_frame_ms, r.hitches_over_50ms, r.gpu_ms_median, r.gpu_ms_p95, r.draw_calls, int(r.primitives / 1000), r.vram_mb, r.focused_all,
			r.largest_face_frac_of_frame * 100.0, r.rule_ok])
	report["grounding_end"] = _grounding()
	var f := FileAccess.open(out.path_join("starfall_report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[starfall] report written: ", out.path_join("starfall_report.json"))
	get_tree().quit()


func _measure(seconds: float) -> Dictionary:
	var frames := 0
	var t := 0.0
	var worst := 0.0
	var hitches := 0
	var gpu := []
	var draws := []
	var prims := []
	var vram := 0.0
	var focused := true
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		frames += 1
		worst = maxf(worst, dt)
		if dt > 0.05:
			hitches += 1
		focused = focused and DisplayServer.window_is_focused()
		var m := monitors()
		gpu.append(m.gpu_ms)
		draws.append(m.draw_calls)
		prims.append(m.primitives)
		vram = maxf(vram, m.vram_mb)
	gpu.sort()
	return {"fps": snappedf(frames / t, 0.01), "frames": frames, "worst_frame_ms": snappedf(worst * 1000.0, 0.1),
		"hitches_over_50ms": hitches, "focused_all": focused, "gpu_ms_median": snappedf(gpu[gpu.size() / 2], 0.01),
		"gpu_ms_p95": snappedf(gpu[int(gpu.size() * 0.95)], 0.01), "draw_calls": int(draws.max()), "primitives": int(prims.max()),
		"vram_mb": snappedf(vram, 0.1)}


## Lying on the grass, not floating or sunk: head, hips and heels above the terrain under them; facing up.
func _grounding() -> Dictionary:
	var g := {}
	for who in characters:
		var c: WorldCharacter = characters[who]
		var d := {}
		for part in [["head", ["Head"]], ["hips", ["Hips"]], ["l_heel", ["LeftFoot"]], ["r_heel", ["RightFoot"]], ["l_hand", ["LeftHand"]], ["r_hand", ["RightHand"]]]:
			var bp = _bone(c, part[1])
			if bp != null:
				d[part[0] + "_above_ground_m"] = snappedf((bp as Vector3).y - h((bp as Vector3).x, (bp as Vector3).z), 0.001)
		var hd = _bone(c, ["Head"])
		var hp = _bone(c, ["Hips"])
		if hd != null and hp != null:
			var body: Vector3 = (hp as Vector3) - (hd as Vector3)
			body.y = 0
			d["body_dir_error_deg"] = snappedf(rad_to_deg(body.normalized().angle_to(lie_dir[who])), 0.1)
			d["head_spot_error_m"] = snappedf(Vector2((hd as Vector3).x, (hd as Vector3).z).distance_to(Vector2((head_spot[who] as Vector3).x, (head_spot[who] as Vector3).z)), 0.01)
		g[who] = d
	return g


## 1 on the line from the wide lens to where they lie (the grass there stays low so both read), 0 elsewhere.
func _wide_corridor(x: float, z: float) -> float:
	var a := WIDE_CAM
	var b := BED + FEET_DIR.normalized() * 0.8
	var ab := b - a
	var tt := clampf((Vector2(x, z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var d := Vector2(x, z).distance_to(a + ab * tt)
	return (1.0 - smoothstep(1.2, 2.6, d)) * smoothstep(0.15, 0.3, tt)


## Tree crowns along a distant ridge (arc length -> metres of bumps; the farther the ridge, the smaller they read).
func _crowns(arc: float, r0: float) -> float:
	# rounded crowns of different sizes packed along the ridge (sqrt of a rectified sine gives domed tops)
	var k := 16.0 * pow(430.0 / r0, 0.6)
	var c1 := sqrt(absf(sin(arc * 0.16)))
	var c2 := sqrt(absf(sin(arc * 0.37 + 1.3)))
	var c3 := sqrt(absf(sin(arc * 0.83 + 2.1)))
	return (c1 * 0.5 + c2 * 0.35 + c3 * 0.25) * k


# ---------------------------------------------------------------- photo-scanned ground plants (Poly Haven, CC0)

## Each mesh of a scanned glTF as {mesh, material (plant_wind), aabb}.
func _scan_variants(path: String, petal_glow := 0.0, amp := 0.12, tint := Color(1, 1, 1)) -> Array:
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var out := []
	var shader := load("res://shaders/starfall/plant_wind.gdshader")
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var src := m.get_active_material(0) as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = shader
		if src:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			sm.set_shader_parameter("normal_tex", src.normal_texture)
			sm.set_shader_parameter("arm_tex", src.roughness_texture if src.roughness_texture else src.ao_texture)
			sm.set_shader_parameter("alpha_cut", src.alpha_scissor_threshold if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.4)
		var aabb := m.mesh.get_aabb()
		sm.set_shader_parameter("root_y", aabb.position.y)
		sm.set_shader_parameter("amp", amp)
		sm.set_shader_parameter("petal_glow", petal_glow)
		sm.set_shader_parameter("tint", tint)
		out.append({"mesh": m.mesh, "mat": sm, "aabb": aabb})
	root.free()
	return out


## Scatter scanned variants: `spots` = Array of [Vector3 ground point, yaw, scale]; one MultiMesh per variant.
func _scatter(nm: String, variants: Array, spots: Array) -> int:
	var per := {}
	for i in spots.size():
		var v: int = _rng.randi() % variants.size()
		if not per.has(v):
			per[v] = []
		per[v].append(spots[i])
	var n := 0
	for v in per:
		var var_d: Dictionary = variants[v]
		var aabb: AABB = var_d.aabb
		var centre := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
		var xforms: Array[Transform3D] = []
		var customs: Array[Color] = []
		for sp in per[v]:
			var b := Basis(Vector3.UP, float(sp[1])).scaled(Vector3.ONE * float(sp[2]))
			xforms.append(Transform3D(b, sp[0]) * Transform3D(Basis.IDENTITY, -centre))
			customs.append(Color(0, 0, 0, 0))
		var mmi := _multimesh("%s_%d" % [nm, v], var_d.mesh, var_d.mat, xforms, customs)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n += xforms.size()
	return n


func _scanned_plants() -> void:
	# grass clumps round them, thick but parted where they lie
	var grass := _scan_variants("res://assets/polyhaven/models/grass_medium_02/grass_medium_02_1k.gltf", 0.0, 0.14, Color(0.78, 0.86, 0.95))
	for g in grass:
		print("[starfall] scanned grass variant size ", (g.aabb as AABB).size)
	var gs := []
	var tries := 0
	var want := int(2100 * float(RenderProfile.get_setting("foliage_density")))
	while gs.size() < want and tries < want * 20:
		tries += 1
		var rr := sqrt(_rng.randf()) * SCAN_R
		var a := _rng.randf() * TAU
		var x := BED.x + cos(a) * rr
		var z := BED.y + sin(a) * rr
		if _body_dist(x, z) < 0.5 or Vector2(x, z).length() < 1.2:
			continue
		gs.append([Vector3(x, h(x, z) - 0.02, z), _rng.randf() * TAU, _rng.randf_range(1.3, 2.1)])
	var n_grass := _scatter("ScanGrass", grass, gs)
	# periwinkles: blue-violet flowers in loose drifts near them (their petals glow softly), a few under the tree
	var peri := _scan_variants("res://assets/polyhaven/models/periwinkle_plant/periwinkle_plant_1k.gltf", 1.4, 0.05)
	var ps := []
	tries = 0
	while ps.size() < 150 and tries < 20000:
		tries += 1
		var rr := lerpf(0.9, 5.5, pow(_rng.randf(), 0.8))
		var a := _rng.randf() * TAU
		var x := BED.x + cos(a) * rr
		var z := BED.y + sin(a) * rr
		if _body_dist(x, z) < 0.55 or Vector2(x, z).length() < 1.3 or _rng.randf() > _flower_density(x, z) + 0.15:
			continue
		ps.append([Vector3(x, h(x, z) - 0.01, z), _rng.randf() * TAU, _rng.randf_range(0.6, 1.0)])
	var n_peri := _scatter("Periwinkles", peri, ps)
	# ferns round the roots (away from them), a mossy boulder bedded among the roots
	var fern := _scan_variants("res://assets/polyhaven/models/fern_02/fern_02_1k.gltf", 0.0, 0.06, Color(0.75, 0.82, 0.9))
	var fs := []
	for k in 11:
		var a := deg_to_rad(110.0 + k * 22.0 + _rng.randf_range(-8, 8))
		var rr := _rng.randf_range(1.5, 3.4)
		var x := cos(a) * rr
		var z := sin(a) * rr
		if Vector2(x, z).distance_to(BED) < 2.4:
			continue
		fs.append([Vector3(x, h(x, z) - 0.03, z), _rng.randf() * TAU, _rng.randf_range(0.8, 1.25)])
	_scatter("Ferns", fern, fs)
	var rock: Node3D = (load("res://assets/polyhaven/models/boulder_01/boulder_01_1k.gltf") as PackedScene).instantiate()
	add_child(rock)
	rock.scale = Vector3.ONE * 0.22
	rock.rotation.y = 1.1
	rock.position = Vector3(-1.9, h(-1.9, -1.2) - 0.18, -1.2)
	counts["flowers"] = n_peri
	counts["scan_grass"] = n_grass
