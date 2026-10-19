extends Node3D
## LANTERN LAKE. Standalone test scene (env-test) AND, embedded (Day 2), the world-building of the living area
## LanternLakeArea (scripts/areas/lantern_lake_area.gd): with `embedded` set it builds only the place - sky, water and
## its mirror, pier, reeds, pines, lanterns, mist, fireflies - into the host area's environment; no cameras, overlay
## or characters of its own; the mirror follows whatever camera the stream uses.
## A calm mountain lake at dusk: a painted sky and mountain backdrop (shaders/lantern_lake/dusk_sky.gdshader, drawn
## per pixel, so it is sharp at any size and mirrors exactly), real 3D water with a planar reflection (a mirrored
## camera renders everything above the water every frame), an old wooden pier, reeds and cattails at the waterline,
## real spruces and firs on the banks (RealKit conifers), low mist on the water, fireflies in the reeds.
## Hundreds of warm paper lanterns rise slowly over the lake and float on the water (two MultiMeshes animated on the
## GPU - one draw call each - every one glowing and mirrored in the lake). Mika and Luna kneel at the end of the pier
## and every few minutes light and release a lantern together.
## VIEWER LANTERNS: viewer_lantern(name, kind) sends up a lantern with the name glowing softly on two sides, rising
## from the pier - the hook for subscribers, members, Super Chats and chat wishes later (kind: chat | subscriber |
## member | superchat). Test it with the L key, --viewer-lantern=Name[:kind],..., or a line "kind name" appended to
## user://lantern_lake_commands.txt while it runs (tools/lantern_lake_viewer.sh).
## PERMANENT CAMERA RULE (docs/world_look_rules.md): wide and medium shots only, no face over 10% of the frame
## height; FramingGuard enforces it and QA reports the largest face per shot.
## Run alone, always with a test flag so no save is touched:
##   godot --path . res://scenes/areas/lantern_lake.tscn -- --fresh --save-path=user://test_lantern_lake.json
##     [--cam=wide|medium|water|rise|high]  keys 1-5 hold a shot, 0 = cine loop, L = test viewer lantern, R = release
##     now, F3 = monitor overlay   [--release-every=180] seconds between their releases
##     [--lake-qa --out=/abs/dir]  per-shot FPS / draw calls / VRAM / GPU ms + one still per shot + face sizes
##     [--clip]  warm-up, then the 10 s sequence once, then quit (with --write-movie and --fixed-fps 30)

const WATER_Y := 0.0
const DECK_Y := 0.62
const PIER_X := 4.0
const PIER_Z0 := 9.0                  # the land end of the pier
const PIER_Z1 := -3.5                 # the lake end
const PIER_W := 2.1
const KNEEL_Z := -2.35                # where they kneel, facing the lake (north, -Z)
const KNEEL_GAP := 0.84               # between their two centres
const HELD_Z := -2.85                 # the lantern they release, in front of them between the two
const WATER_LAYER := 1 << 9
const MIST_LAYER := 1 << 10
const GRASS_LAYER := 1 << 11
const CHAR_LAYER := 1 << 1
const WARMUP := 6.0
const LOOP := [["wide", 12.0], ["medium", 9.0], ["water", 10.0], ["high", 9.0], ["rise", 8.0]]
const SEQUENCE := [["wide", 3.5], ["medium", 3.6], ["rise", 3.1]]
const KINDS := {
	"chat": {"tint": Color(1.0, 0.42, 0.11), "hot": Color(1.0, 0.83, 0.52), "energy": 1.15, "text": Color(1.0, 0.93, 0.72)},
	"subscriber": {"tint": Color(1.0, 0.5, 0.12), "hot": Color(1.0, 0.88, 0.55), "energy": 1.3, "text": Color(1.0, 0.95, 0.75)},
	"member": {"tint": Color(1.0, 0.36, 0.3), "hot": Color(1.0, 0.78, 0.7), "energy": 1.15, "text": Color(1.0, 0.92, 0.88)},
	"superchat": {"tint": Color(1.0, 0.58, 0.1), "hot": Color(1.0, 0.94, 0.62), "energy": 1.5, "text": Color(1.0, 0.97, 0.8)},
}

var env: Environment
var cam: Camera3D
var refl_vp: SubViewport
var refl_cam: Camera3D
var water_mat: ShaderMaterial
var guard: Node
var embedded := false                  # built inside LanternLakeArea (the living world)
var host_env: Environment              # (embedded) the area's environment to dress
var overlay: Label
var characters := {}
var limbs := {}
var counts := {}
var mode := "cine"
var shot := "wide"
var shot_t := 0.0
var _seq_i := 0
var _t := 0.0
var _placed := false
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var lantern_mesh: ArrayMesh
var lantern_shader: Shader
var free_lanterns: Array = []          # script-driven lanterns in the air: {node, mat, light, vel, age, kind, name}
var held: Dictionary = {}              # the lantern on the pier between them: {node, mat, light}
var ritual := "idle"                   # idle | reach | lift | hold | release | watch
var ritual_t := 0.0
var release_every := 180.0
var _next_release := 22.0
var _next_held := -1.0
var _viewer_queue: Array = []
var _viewer_cool := 0.0
var _viewer_side := 1.0
var _cmd_poll := 0.0
var _look_t := {"mika": 1.0, "luna": 2.2}
var _look_tgt := {"mika": "lake", "luna": "lake"}
var _mood_t := {"mika": 3.0, "luna": 5.0}
var _watch: Node3D                     # the lantern they follow with their eyes
var font: SystemFont
var hip_rest := {}                     # who -> hips bone height over her feet, standing (measured)
var thigh_rest := {}                   # who -> hip joint (upper leg) height over her feet, standing
var kneel_up := 0.0                    # 0 = sitting back on her heels (seiza), 1 = up on her knees (lifting)
var leg_len := {}                      # who -> Vector2(thigh, shin) metres


func _ready() -> void:
	if not embedded:
		DisplayServer.window_set_title("Lantern Lake (env-test)")
	_rng.seed = 2026
	_noise.seed = 31
	_noise.frequency = 0.02
	_noise.fractal_octaves = 3
	release_every = float(RenderProfile.options.get("release-every", "180"))
	Progression.load_data()
	if not embedded:
		Engine.max_fps = int(RenderProfile.get_setting("max_fps"))
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Noto Serif", "DejaVu Serif", "Liberation Serif", "serif"])
	font.font_weight = 600
	lantern_shader = load("res://shaders/lantern_lake/lantern.gdshader")
	lantern_mesh = _lantern_mesh(16)
	if embedded:
		_environment()
		_lights()
		_terrain()
		_water()
		_pier()
		_pines()
		_reeds()
		_lanterns()
		_mist()
		_reflection()
		_fireflies()
		RenderingServer.frame_pre_draw.connect(_mirror_camera)
		_seed_sky()
		_placed = true
		print("[lake] embedded in the living world: %s" % counts)
		return
	_viewport_settings()
	_environment()
	_lights()
	_terrain()
	_water()
	_pier()
	_pines()
	_reeds()
	_lanterns()
	_mist()
	_cameras()
	_reflection()
	_fireflies()
	_characters()
	_post()
	_overlay()
	if ResourceLoader.exists("res://scripts/world/framing_guard.gd"):
		guard = load("res://scripts/world/framing_guard.gd").new()
		guard.name = "FramingGuard"
		guard.set("characters", characters.values())
		guard.set("camera", cam)
		add_child(guard)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	RenderingServer.frame_pre_draw.connect(_mirror_camera)
	_seed_sky()
	_spawn_held()
	print("[lake] adapter=%s | profile=%s max_fps=%d | %s" % [RenderingServer.get_video_adapter_name(), RenderProfile.profile, Engine.max_fps, counts])
	print("[lake] viewer lantern commands: ", ProjectSettings.globalize_path("user://lantern_lake_commands.txt"))
	_settle.call_deferred()
	var vl := String(RenderProfile.options.get("viewer-lantern", ""))
	if vl != "":
		for item in vl.split(","):
			var nm := item.get_slice(":", 0).strip_edges()
			var kd := item.get_slice(":", 1).strip_edges() if item.contains(":") else "chat"
			if nm != "":
				_viewer_queue.append([nm, kd])
	if RenderProfile.options.has("pose-probe"):
		_pose_probe.call_deferred()
	elif RenderProfile.options.has("lake-qa"):
		_qa.call_deferred()
	elif RenderProfile.options.has("clip"):
		_clip.call_deferred()
	elif RenderProfile.options.has("still"):
		_still.call_deferred()


func _viewport_settings() -> void:
	var vp := get_viewport()
	# native resolution with 2x MSAA: no temporal jitter (the GPU-animated lanterns have no motion vectors, so TAA /
	# FSR 2 would smear them); FXAA cleans the alpha-cut foliage
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	vp.use_taa = false
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = 2048


# ---------------------------------------------------------------- the land and the lake

## How far a point is outside the lake, metres (negative = in the water): the near shore curves round behind the
## lens, the banks run north on both sides, the far end closes 520 m away under the mountains.
func shore_e(x: float, z: float) -> float:
	var wob := _noise.get_noise_2d(x, z) * 4.0
	var zs := 7.6 + 0.0045 * x * x + wob * 0.5
	var w := 52.0 + 0.1 * maxf(0.0, -z) + wob
	var e := maxf(z - zs, absf(x - 3.0) - w)
	e = maxf(e, -520.0 - z + wob * 2.0)
	# the pier's little bank: the shore reaches out a few metres where the pier starts
	var pb := 3.2 - Vector2(x - PIER_X, (z - PIER_Z0) * 0.6).length()
	return maxf(e, pb * 0.8) if z > PIER_Z0 - 4.0 else e


func h(x: float, z: float) -> float:
	var e := shore_e(x, z)
	if e < 0.0:
		return maxf(-3.2, e * 0.32) - 0.05
	var rise := 0.1 + e * 0.07 + 0.2 * smoothstep(5.0, 70.0, e) * (e - 5.0)
	var roll := _noise.get_noise_2d(x * 0.5, z * 0.5) * 2.5 * smoothstep(3.0, 30.0, e)
	return rise + roll


func _grid(u: float, lo: float, hi: float, c: float) -> float:
	var a := absf(u)
	var f := 0.14 * a + 0.86 * a * a * a
	return c + (f * (hi - c) if u > 0.0 else -f * (c - lo))


func _terrain() -> void:
	var nx := 230
	var nz := 260
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz + 1:
		var z := _grid(-1.0 + 2.0 * j / nz, -760.0, 80.0, 4.0)
		for i in nx + 1:
			var x := _grid(-1.0 + 2.0 * i / nx, -330.0, 330.0, 2.0)
			var e := 0.2
			st.set_normal(Vector3(h(x - e, z) - h(x + e, z), 2.0 * e, h(x, z - e) - h(x, z + e)).normalized())
			st.add_vertex(Vector3(x, h(x, z), z))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			for k in [a, a + 1, a + nx + 1, a + 1, a + nx + 2, a + nx + 1]:
				st.add_index(k)
	var mi := MeshInstance3D.new()
	mi.name = "Shore"
	mi.mesh = st.commit()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/lantern_lake/shore.gdshader")
	var t := "res://assets/polyhaven/textures/%s/%s_%s_%s.jpg"
	sm.set_shader_parameter("grass_alb", load(t % ["leafy_grass", "leafy_grass", "diff", "2k"]))
	sm.set_shader_parameter("grass_nor", load(t % ["leafy_grass", "leafy_grass", "nor_gl", "2k"]))
	sm.set_shader_parameter("mud_alb", load(t % ["mud_forest", "mud_forest", "diff", "2k"]))
	sm.set_shader_parameter("mud_nor", load(t % ["mud_forest", "mud_forest", "nor_gl", "2k"]))
	sm.set_shader_parameter("floor_alb", load(t % ["forest_floor", "forest_floor", "diff", "2k"]))
	sm.set_shader_parameter("floor_nor", load(t % ["forest_floor", "forest_floor", "nor_gl", "2k"]))
	sm.set_shader_parameter("water_y", WATER_Y)
	sm.set_shader_parameter("brightness", 0.5)
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	counts["terrain_tris"] = nx * nz * 2


func _water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(2600, 2600)
	var mi := MeshInstance3D.new()
	mi.name = "Lake"
	mi.mesh = pm
	mi.position = Vector3(0, WATER_Y, -500)
	mi.layers = WATER_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/lantern_lake/water.gdshader")
	for k in ["ripple_a", "ripple_b"]:
		var nt := NoiseTexture2D.new()
		nt.width = 512
		nt.height = 512
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0 if k == "ripple_a" else 4.0
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012 if k == "ripple_a" else 0.02
		fn.fractal_octaves = 3
		fn.seed = 3 if k == "ripple_a" else 8
		nt.noise = fn
		water_mat.set_shader_parameter(k, nt)
	water_mat.set_shader_parameter("water_y", WATER_Y)
	mi.material_override = water_mat
	add_child(mi)


# ---------------------------------------------------------------- the pier

func _pier() -> void:
	var wood := StandardMaterial3D.new()
	var tx := "res://assets/polyhaven/textures/wood_table_001/wood_table_001_%s_1k.jpg"
	wood.albedo_texture = load(tx % "diff")
	wood.normal_enabled = true
	wood.normal_texture = load(tx % "nor_gl")
	wood.roughness_texture = load(tx % "rough")
	wood.albedo_color = Color(0.5, 0.47, 0.44)
	wood.vertex_color_use_as_albedo = true
	wood.uv1_scale = Vector3(1.0, 1.0, 1.0)
	var post_mat := StandardMaterial3D.new()
	var mx := "res://assets/polyhaven/textures/moss_wood/moss_wood_%s_2k.jpg"
	post_mat.albedo_texture = load(mx % "diff")
	post_mat.normal_enabled = true
	post_mat.normal_texture = load(mx % "nor_gl")
	post_mat.roughness_texture = load(mx % "rough")
	post_mat.albedo_color = Color(0.45, 0.43, 0.42)
	post_mat.uv1_triplanar = true
	post_mat.uv1_scale = Vector3(1.2, 1.2, 1.2)
	var plank := BoxMesh.new()
	plank.size = Vector3(PIER_W, 0.045, 0.19)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plank
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	var z := PIER_Z0
	while z > PIER_Z1:
		var b := Basis(Vector3.UP, _rng.randf_range(-0.012, 0.012)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.01, 0.01))
		b = b.scaled(Vector3(_rng.randf_range(0.97, 1.03), 1.0, 1.0))
		xs.append(Transform3D(b, Vector3(PIER_X + _rng.randf_range(-0.04, 0.04), DECK_Y - 0.0225 + _rng.randf_range(-0.006, 0.006), z - 0.095)))
		var g := _rng.randf_range(0.72, 1.08)
		cs.append(Color(g, g * _rng.randf_range(0.95, 1.0), g * _rng.randf_range(0.9, 1.0)))
		z -= 0.205
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Planks"
	mmi.multimesh = mm
	mmi.material_override = wood
	add_child(mmi)
	# stringers and cross beams under the deck
	for sx in [-0.85, 0.85]:
		_box("Stringer", Vector3(0.12, 0.16, PIER_Z0 - PIER_Z1), Vector3(PIER_X + sx, DECK_Y - 0.125, (PIER_Z0 + PIER_Z1) * 0.5), wood)
	# posts: every 2.5 m both sides; the two at the end stand up above the deck
	var pz := PIER_Z1 + 0.15
	var k := 0
	while pz < PIER_Z0 - 0.5:
		for sx in [-1.0, 1.0]:
			var top := DECK_Y + (0.5 if k == 0 else (0.28 if k == 2 else -0.04))
			var cyl := CylinderMesh.new()
			var r := _rng.randf_range(0.085, 0.11)
			cyl.top_radius = r
			cyl.bottom_radius = r * 1.05
			cyl.height = top + 0.35
			cyl.radial_segments = 12
			var p := MeshInstance3D.new()
			p.name = "Post"
			p.mesh = cyl
			p.material_override = post_mat
			p.position = Vector3(PIER_X + sx * (PIER_W * 0.5 + 0.02), (top - 0.35) * 0.5, pz)
			p.rotation = Vector3(_rng.randf_range(-0.03, 0.03), _rng.randf(), _rng.randf_range(-0.03, 0.03))
			add_child(p)
		_box("CrossBeam", Vector3(PIER_W + 0.25, 0.12, 0.1), Vector3(PIER_X, DECK_Y - 0.2, pz), wood)
		pz += 2.5
		k += 1
	var body := StaticBody3D.new()
	body.name = "PierBody"
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(PIER_W, 0.1, PIER_Z0 - PIER_Z1)
	shape.shape = bx
	shape.position = Vector3(PIER_X, DECK_Y - 0.05, (PIER_Z0 + PIER_Z1) * 0.5)
	body.add_child(shape)
	add_child(body)
	counts["planks"] = xs.size()


func _box(nm: String, size: Vector3, at: Vector3, mat: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	add_child(mi)


# ---------------------------------------------------------------- pines, reeds, grass

func _pines() -> void:
	var variants := ["RealSpruce_A", "RealSpruce_B", "RealFir", "RealPineYoung"]
	# the colour pass: autumn and blossom trees among the pines along the shore, every crown its own colour
	var broad := [] if RealKit.enabled() == false or RenderProfile.options.has("plain-trees") else ["RealMaple", "RealBeech_A", "RealBeech_B", "RealOak", "RealYoung"]
	var all_v: Array = variants + broad
	var near := {}
	var far := {}
	var near_c := {}
	var far_c := {}
	for v in all_v:
		near[v] = []
		far[v] = []
		near_c[v] = []
		far_c[v] = []
	var focus := Vector2(PIER_X, 0.0)
	var placed := 0
	var tries := 0
	while placed < 2600 and tries < 60000:
		tries += 1
		var x := _rng.randf_range(-320.0, 320.0)
		var z := _rng.randf_range(-740.0, 70.0)
		var e := shore_e(x, z)
		if e < 2.5:
			continue
		# the pier's bank and the lens positions stay open; the forest thickens away from the water
		if Vector2(x - PIER_X, z - PIER_Z0).length() < 9.0 or Vector2(x + 1.5, z - 6.5).length() < 7.0:
			continue
		# the high lens over the bank and its view down to the pier stay open
		if Vector2(x + 6.2, z - 17.2).length() < 10.0 or (x > -12.0 and x < 8.0 and z > 6.0 and z < 24.0):
			continue
		var dens := smoothstep(2.5, 14.0, e) * (0.45 + 0.55 * (_noise.get_noise_2d(x * 0.8, z * 0.8) * 0.5 + 0.5))
		var d := Vector2(x, z).distance_to(focus)
		dens *= 1.0 if d < 140.0 else (0.5 if d < 300.0 else 0.32)
		if _rng.randf() > dens:
			continue
		var v: String = variants[_rng.randi() % variants.size()] if e > 6.0 else (["RealPineYoung", "RealSpruce_B"][_rng.randi() % 2])
		var s := _rng.randf_range(0.75, 1.25) * (0.7 if v == "RealPineYoung" else 1.0)
		var roll := _rng.randf()
		if not broad.is_empty() and roll < 0.55 * (1.0 - smoothstep(18.0, 60.0, e)) + 0.12:
			v = broad[_rng.randi() % broad.size()]
			s = _rng.randf_range(0.62, 0.95) * (1.25 if v == "RealYoung" else 1.0)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
		var xf := Transform3D(b, Vector3(x, h(x, z) - 0.2, z))
		var col := _crown_color(v)
		if d < 110.0:
			near[v].append(xf)
			near_c[v].append(col)
		else:
			far[v].append(xf)
			far_c[v].append(col)
		placed += 1
	var nn := 0
	var nf := 0
	for v in all_v:
		for pass_i in [[near, false, near_c], [far, true, far_c]]:
			var list: Array = (pass_i[0] as Dictionary)[v]
			if list.is_empty():
				continue
			var mesh: ArrayMesh = RealKit._tree(v, pass_i[1], 1.0, "bark_brown_02")
			if not broad.is_empty():
				_colour_crowns(mesh, broad.has(v), pass_i[1])
			var tris := 0
			for si in mesh.get_surface_count():
				tris += mesh.surface_get_array_index_len(si) / 3
			counts["tris_%s_%s" % [v, "far" if pass_i[1] else "near"]] = tris
			var xs: Array[Transform3D] = []
			xs.assign(list)
			# the mesh keeps its own bark / needle materials: no override
			var cs: Array[Color] = []
			cs.assign((pass_i[2] as Dictionary)[v] if not broad.is_empty() else [])
			_multimesh_tiled("Pines_%s_%s" % [v, "far" if pass_i[1] else "near"], mesh, null, xs, cs, 40.0 if not pass_i[1] else 90.0)
			if pass_i[1]:
				nf += list.size()
			else:
				nn += list.size()
			if broad.has(v):
				counts["broadleaf"] = int(counts.get("broadleaf", 0)) + list.size()
	counts["pines_near"] = nn
	counts["pines_far"] = nf


## A crown's colour (multimesh custom data: rgb, a = how far its leaves take it). The pines stay evergreen but deep
## and jewel-like (emerald to teal); the broadleaf trees are the colour: crimson and scarlet maples, golden beeches,
## copper oaks, and young trees in blossom (sakura pink to plum).
func _crown_color(v: String) -> Color:
	var pal: Array
	match v:
		"RealMaple":
			pal = [Color(0.86, 0.08, 0.12), Color(0.95, 0.24, 0.07), Color(0.78, 0.05, 0.28)]
		"RealBeech_A", "RealBeech_B":
			pal = [Color(1.0, 0.68, 0.08), Color(0.98, 0.5, 0.05), Color(0.95, 0.8, 0.2)]
		"RealOak":
			pal = [Color(0.92, 0.36, 0.06), Color(0.8, 0.22, 0.05), Color(0.98, 0.56, 0.12)]
		"RealYoung":
			pal = [Color(1.0, 0.55, 0.75), Color(0.98, 0.7, 0.86), Color(0.82, 0.36, 0.78)]
		_:
			pal = [Color(0.1, 0.5, 0.3), Color(0.06, 0.42, 0.4), Color(0.16, 0.56, 0.22)]
	var c: Color = pal[_rng.randi() % pal.size()]
	c = c.lerp(pal[_rng.randi() % pal.size()], _rng.randf() * 0.5)
	return Color(c.r, c.g, c.b, 1.0 if not (v.begins_with("RealSpruce") or v == "RealFir" or v == "RealPineYoung") else 0.75)


## The colour pass on one tree mesh's leaves (its own duplicated material): richer colour, moonlit crown tops, a
## little light of their own so the colours read at night, and a few softly glowing, twinkling twigs (spirit
## blossoms) - more on the broadleaf trees, fewer far away.
func _colour_crowns(mesh: ArrayMesh, broadleaf: bool, far_lod: bool) -> void:
	for si in mesh.get_surface_count():
		var m := mesh.surface_get_material(si) as ShaderMaterial
		if m == null or m.shader == null or not m.shader.resource_path.ends_with("real_leaf.gdshader"):
			continue
		m.set_shader_parameter("saturation", 0.6)
		m.set_shader_parameter("specular", 0.12)            # (the sky's violet sheen washed the colours to pastel)
		m.set_shader_parameter("self_lit", 0.3 if broadleaf else 0.1)
		m.set_shader_parameter("sheen", 0.12)
		m.set_shader_parameter("sheen_color", Color(0.5, 0.65, 1.0))
		m.set_shader_parameter("glow_amount", 0.012 if broadleaf and not far_lod else 0.0)
		m.set_shader_parameter("glow_energy", 1.2)


func _reed_mesh(blades: int, heads: int, height: float, width: float, seed_v: int, droop := 0.45) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	for k in blades:
		var ang := r.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var root := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * 0.1
		var hh := height * r.randf_range(0.55, 1.0)
		var bend := r.randf_range(0.08, droop) * hh
		var w := width * r.randf_range(0.7, 1.3)
		var segs := 5
		for s in segs + 1:
			var t := float(s) / segs
			var c := root + Vector3(0, hh * t, 0) + dir * bend * t * t
			var ww := w * (1.0 - t * 0.94)
			for e in [-1.0, 1.0]:
				st.set_normal((Vector3.UP * 0.3 + dir * -0.6 + side * e * 0.2).normalized())
				st.set_uv(Vector2(0.0, t))
				st.set_uv2(Vector2(0.0, 0.0))
				st.add_vertex(c + side * ww * e)
	# indices for the blades
	var per := (5 + 1) * 2
	for k in blades:
		for s in 5:
			var q := k * per + s * 2
			for i in [q, q + 1, q + 3, q, q + 3, q + 2]:
				st.add_index(i)
	var base := blades * per
	for k in heads:
		var root := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * 0.07
		var hh := height * r.randf_range(1.0, 1.25)
		var lean := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * 0.08 * hh
		# stem: two crossed thin strips
		for rot in [0.0, PI * 0.5]:
			var side := Vector3(cos(rot), 0, sin(rot)) * 0.0028
			for s in 2:
				var t := float(s)
				var c := root + Vector3(0, hh * t, 0) + lean * t * t
				for e in [-1.0, 1.0]:
					st.set_normal(Vector3(0, 0, 1))
					st.set_uv(Vector2(0.0, t))
					st.set_uv2(Vector2(1.0, 0.0))
					st.add_vertex(c + side * e)
			for i in [base, base + 1, base + 3, base, base + 3, base + 2]:
				st.add_index(i)
			base += 4
		# the brown cattail head near the top
		var hc := root + Vector3(0, hh * 0.86, 0) + lean * 0.74
		var seg := 6
		var hl := 0.1 * height / 1.5
		for ring in 2:
			for j in seg:
				var a := TAU * j / seg
				var p := hc + Vector3(cos(a) * 0.011, ring * hl, sin(a) * 0.011)
				st.set_normal(Vector3(cos(a), 0, sin(a)))
				st.set_uv(Vector2(0.0, 0.9))
				st.set_uv2(Vector2(2.0, 0.0))
				st.add_vertex(p)
		for j in seg:
			var a0 := base + j
			var a1 := base + (j + 1) % seg
			for i in [a0, a1, a1 + seg, a0, a1 + seg, a0 + seg]:
				st.add_index(i)
		base += seg * 2
	return st.commit()


func _reeds() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/lantern_lake/reed.gdshader")
	sm.set_shader_parameter("water_y", WATER_Y)
	var meshes := [_reed_mesh(22, 1, 1.5, 0.028, 1), _reed_mesh(18, 0, 1.2, 0.026, 2), _reed_mesh(24, 2, 1.7, 0.03, 3)]
	var lists := [[], [], []]
	var placed := 0
	var tries := 0
	while placed < 5200 and tries < 400000:
		tries += 1
		var x := _rng.randf_range(-120.0, 130.0)
		var z := _rng.randf_range(-220.0, 30.0)
		var e := shore_e(x, z)
		if e < -3.2 or e > 1.4:
			continue
		var band := exp(-pow((e + 0.9) / 1.3, 2.0))
		var patch := _noise.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5
		if _rng.randf() > band * (0.25 + 0.95 * patch):
			continue
		# the pier, the lenses and the water lanterns' lane stay clear
		if absf(x - PIER_X) < 1.6 and z < PIER_Z0 + 1.0:
			continue
		if Vector2(x + 1.5, z - 6.2).length() < 1.8:
			continue
		var s := _rng.randf_range(0.75, 1.2)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.85, 1.15), s))
		lists[_rng.randi() % 3].append(Transform3D(b, Vector3(x, h(x, z) - 0.05, z)))
		placed += 1
	# the wide shot's foreground: a thick clump of reeds bottom left and a few bottom right, like the reference -
	# broad, long leaves that arch over (their own mesh)
	var fg_mesh := _reed_mesh(30, 1, 1.65, 0.05, 11, 0.75)
	var fg: Array[Transform3D] = []
	for k in 220:
		var x := _rng.randf_range(-6.4, -1.4)
		var z := _rng.randf_range(1.6, 5.8)
		if Vector2(x + 1.65, z - 6.1).length() < 2.1:
			continue
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.9, 1.3))
		fg.append(Transform3D(b, Vector3(x, minf(h(x, z), -0.3), z)))
	for k in 70:
		var x := _rng.randf_range(0.4, 2.7)
		var z := _rng.randf_range(2.0, 5.2)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.15))
		fg.append(Transform3D(b, Vector3(x, minf(h(x, z), -0.3), z)))
	var fgc: Array[Color] = []
	for xf in fg:
		fgc.append(Color(_rng.randf(), 0, 0, 0))
	_multimesh("ReedsForeground", fg_mesh, sm, fg, fgc)
	var n := 0
	for i in 3:
		var customs: Array[Color] = []
		var xs: Array[Transform3D] = []
		for xf in lists[i]:
			xs.append(xf)
			customs.append(Color(_rng.randf(), 0, 0, 0))
		_multimesh_tiled("Reeds_%d" % i, meshes[i], sm, xs, customs, 32.0)
		counts["tris_reed_%d" % i] = (meshes[i] as ArrayMesh).surface_get_array_index_len(0) / 3
		n += xs.size()
	counts["reed_clumps"] = n
	# grass on the banks (the same shader, short blades)
	var gm := sm.duplicate() as ShaderMaterial
	gm.set_shader_parameter("leaf_base", Color(0.025, 0.035, 0.03))
	gm.set_shader_parameter("leaf_tip", Color(0.09, 0.11, 0.07))
	gm.set_shader_parameter("wind", 0.04)
	var gx: Array[Transform3D] = []
	var gc: Array[Color] = []
	tries = 0
	while gx.size() < 9000 and tries < 300000:
		tries += 1
		var x := _rng.randf_range(-60.0, 70.0)
		var z := _rng.randf_range(-40.0, 40.0)
		var e := shore_e(x, z)
		if e < 0.2 or e > 18.0:
			continue
		if absf(x - PIER_X) < 1.3 and absf(z - PIER_Z0) < 2.0:
			continue
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1.0, _rng.randf_range(0.6, 1.1), 1.0))
		gx.append(Transform3D(b, Vector3(x, h(x, z) - 0.02, z)))
		gc.append(Color(_rng.randf(), 0, 0, 0))
	# (not in the mirror: from the water the bank grass is hidden behind the reeds and the bank's edge)
	_multimesh_tiled("BankGrass", _reed_mesh(9, 0, 0.55, 0.01, 7), gm, gx, gc, 24.0, GRASS_LAYER)
	counts["grass_clumps"] = gx.size()


## The same, cut into square tiles so each tile is frustum-culled on its own (a lake-wide MultiMesh would draw the
## banks behind the lens too, in both the view and the mirror).
func _multimesh_tiled(nm: String, mesh: Mesh, mat: Material, xforms: Array[Transform3D], customs: Array[Color], tile: float, layers := 1) -> int:
	var cells := {}
	for i in xforms.size():
		var o := xforms[i].origin
		var key := Vector2i(floori(o.x / tile), floori(o.z / tile))
		if not cells.has(key):
			cells[key] = [[] as Array[Transform3D], [] as Array[Color]]
		(cells[key][0] as Array[Transform3D]).append(xforms[i])
		(cells[key][1] as Array[Color]).append(customs[i] if i < customs.size() else Color(0, 0, 0, 0))
	for key in cells:
		var mmi := _multimesh("%s_%d_%d" % [nm, key.x, key.y], mesh, mat, cells[key][0], cells[key][1])
		mmi.layers = layers
	return cells.size()


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


# ---------------------------------------------------------------- lanterns

## A paper sky lantern, 1 m tall: a slightly tapered paper bag with a rounded top, an open bottom with a wire hoop,
## two cross wires and the small flame in the middle (UV.x round, UV.y up, UV2.x part 0 paper / 1 flame / 2 wire).
func _lantern_mesh(seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof := []          # [radius, y]
	for i in 9:
		var t := i / 8.0
		var y := 0.72 * t
		prof.append([lerpf(0.27, 0.37, smoothstep(0.0, 1.0, t) * 0.85 + t * 0.15), y])
	for i in range(1, 7):
		var a := (PI * 0.5) * (i / 6.0)
		prof.append([0.37 * cos(a * 0.98), 0.72 + 0.28 * sin(a)])
	var rings := prof.size()
	var idx := 0
	for i in rings:
		var r: float = prof[i][0]
		var y: float = prof[i][1]
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, rings - 1)
		var dr: float = float(prof[i1][0]) - float(prof[i0][0])
		var dy: float = float(prof[i1][1]) - float(prof[i0][1])
		for j in seg + 1:
			var a := TAU * j / seg
			var n := Vector3(cos(a) * dy, -dr, sin(a) * dy).normalized()
			st.set_normal(n)
			st.set_uv(Vector2(float(j) / seg, y))
			st.set_uv2(Vector2(0, 0))
			st.add_vertex(Vector3(cos(a) * r, y, sin(a) * r))
	for i in rings - 1:
		for j in seg:
			var a := i * (seg + 1) + j
			var b := a + seg + 1
			for k in [a, a + 1, b, a + 1, b + 1, b]:      # clockwise seen from outside: Godot's front face
				st.add_index(k)
	idx = rings * (seg + 1)
	# the top closes in one point
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0.5, 1.0))
	st.set_uv2(Vector2(0, 0))
	st.add_vertex(Vector3(0, 1.0, 0))
	var top := idx
	idx += 1
	var last := (rings - 1) * (seg + 1)
	for j in seg:
		for k in [last + j, last + j + 1, top]:
			st.add_index(k)
	# the wire hoop (a thin band just outside the paper at the bottom) and two cross wires
	for j in seg + 1:
		var a := TAU * j / seg
		for y in [0.0, 0.022]:
			st.set_normal(Vector3(cos(a), 0, sin(a)))
			st.set_uv(Vector2(float(j) / seg, 0.0))
			st.set_uv2(Vector2(2, 0))
			st.add_vertex(Vector3(cos(a) * 0.276, y, sin(a) * 0.276))
	for j in seg:
		var a := idx + j * 2
		for k in [a, a + 2, a + 1, a + 1, a + 2, a + 3]:
			st.add_index(k)
	idx += (seg + 1) * 2
	for rot in [0.0, PI * 0.5]:
		var d := Vector3(cos(rot), 0, sin(rot))
		var sd := Vector3(-d.z, 0, d.x) * 0.004
		for p in [-d * 0.27 - sd, -d * 0.27 + sd, d * 0.27 - sd, d * 0.27 + sd]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0, 0.01))
			st.set_uv2(Vector2(2, 0))
			st.add_vertex(p + Vector3(0, 0.03, 0))
		for k in [idx, idx + 2, idx + 1, idx + 1, idx + 2, idx + 3]:
			st.add_index(k)
		idx += 4
	# the flame: two crossed small quads in the middle
	for rot in [0.0, PI * 0.5]:
		var d := Vector3(cos(rot), 0, sin(rot)) * 0.03
		for p in [-d + Vector3(0, 0.035, 0), d + Vector3(0, 0.035, 0), -d * 0.3 + Vector3(0, 0.13, 0), d * 0.3 + Vector3(0, 0.13, 0)]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0, 0.05))
			st.set_uv2(Vector2(1, 0))
			st.add_vertex(p)
		for k in [idx, idx + 2, idx + 1, idx + 1, idx + 2, idx + 3]:
			st.add_index(k)
		idx += 4
	return st.commit()


func _lantern_material(anim: int) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = lantern_shader
	sm.set_shader_parameter("anim", anim)
	return sm


## The festival: hundreds of lanterns rising slowly over the lake (born far out over the water, so no one pops in
## near the lens) and hundreds floating on it, thickest round the pier.
func _lanterns() -> void:
	var sky_x: Array[Transform3D] = []
	var sky_c: Array[Color] = []
	while sky_x.size() < 520:
		var x := _rng.randf_range(-130.0, 140.0)
		var z := -_rng.randf_range(48.0, 470.0) if _rng.randf() < 0.62 else -_rng.randf_range(40.0, 160.0)
		if shore_e(x, z) > -8.0:
			continue
		var s := _rng.randf_range(0.8, 1.15)
		sky_x.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, WATER_Y + 1.5, z)))
		sky_c.append(Color(_rng.randf(), _rng.randf_range(0.22, 0.5), _rng.randf_range(0.75, 1.25), 0))
	var smk := _lantern_material(1)
	smk.set_shader_parameter("rise_range", 175.0)
	var m1 := _multimesh("SkyLanterns", lantern_mesh, smk, sky_x, sky_c)
	m1.custom_aabb = AABB(Vector3(-400, -10, -900), Vector3(800, 260, 1000))
	m1.layers = 1
	var wx: Array[Transform3D] = []
	var wc: Array[Color] = []
	var tries := 0
	while wx.size() < 360 and tries < 60000:
		tries += 1
		var near := _rng.randf() < 0.55
		var x := _rng.randf_range(-22.0, 34.0) if near else _rng.randf_range(-70.0, 80.0)
		var z := -_rng.randf_range(-6.5, 45.0) if near else -_rng.randf_range(20.0, 260.0)
		if shore_e(x, z) > -1.6:
			continue
		# the pier and its posts, and the lenses over the water, stay clear
		if absf(x - PIER_X) < 1.9 and z > PIER_Z1 - 1.4:
			continue
		if Vector2(x + 1.5, z + 9.0).length() < 2.2 or Vector2(x + 1.5, z - 6.0).length() < 2.6:
			continue
		var clash := false
		for o in wx.slice(maxi(0, wx.size() - 60)):
			if Vector2(o.origin.x, o.origin.z).distance_to(Vector2(x, z)) < 0.9:
				clash = true
				break
		if clash:
			continue
		var s := _rng.randf_range(0.42, 0.62)
		wx.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, WATER_Y - 0.02, z)))
		wc.append(Color(_rng.randf(), _rng.randf_range(0.15, 0.6), _rng.randf_range(0.7, 1.15), 0))
	var smw := _lantern_material(2)
	smw.set_shader_parameter("energy", 1.15)
	var m2 := _multimesh("WaterLanterns", lantern_mesh, smw, wx, wc)
	m2.custom_aabb = AABB(Vector3(-200, -5, -400), Vector3(400, 20, 420))
	counts["sky_lanterns"] = sky_x.size()
	counts["water_lanterns"] = wx.size()
	# warm light from the lanterns on the water round the pier end, on the pier, the reeds and the two of them
	for p in [Vector3(PIER_X - 3.0, 0.35, KNEEL_Z - 4.0), Vector3(PIER_X + 3.5, 0.35, KNEEL_Z - 3.0), Vector3(PIER_X - 1.0, 0.35, KNEEL_Z - 9.0)]:
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.62, 0.3)
		ol.light_energy = 0.55
		ol.omni_range = 6.5
		ol.omni_attenuation = 1.6
		ol.shadow_enabled = false
		ol.position = p
		add_child(ol)


## One lantern the script moves itself (theirs, a viewer's, or one released earlier).
func _make_lantern(kind := "chat", name_text := "", size := 0.95) -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.mesh = lantern_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := _lantern_material(0)
	var k: Dictionary = KINDS.get(kind, KINDS.chat)
	sm.set_shader_parameter("tint", k.tint)
	sm.set_shader_parameter("hot", k.hot)
	sm.set_shader_parameter("energy", k.energy)
	mi.material_override = sm
	mi.scale = Vector3.ONE * size
	add_child(mi)
	var d := {"node": mi, "mat": sm, "light": null, "vel": Vector3.ZERO, "age": 0.0, "kind": kind, "name": name_text,
		"seed": _rng.randf(), "spin": _rng.randf_range(-0.12, 0.12)}
	if name_text != "":
		var vp := SubViewport.new()
		vp.size = Vector2i(1024, 520)
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var lb := Label.new()
		lb.text = name_text
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.size = Vector2(1024, 520)
		var fs := int(clampf(1900.0 / maxf(name_text.length(), 1.0), 80.0, 290.0))
		lb.add_theme_font_override("font", font)
		lb.add_theme_font_size_override("font_size", fs)
		lb.add_theme_color_override("font_color", k.text)
		lb.add_theme_color_override("font_outline_color", Color(0.35, 0.12, 0.02, 0.85))
		lb.add_theme_constant_override("outline_size", maxi(6, fs / 12))
		vp.add_child(lb)
		mi.add_child(vp)
		sm.set_shader_parameter("name_tex", vp.get_texture())
		sm.set_shader_parameter("name_on", 1.0)
		d["vp"] = vp
	return d


func _lantern_light(d: Dictionary, energy: float, shadows: bool) -> void:
	var ol := OmniLight3D.new()
	ol.light_color = Color(1.0, 0.6, 0.28)
	ol.light_energy = energy
	ol.omni_range = 5.5
	ol.omni_attenuation = 1.4
	ol.shadow_enabled = shadows
	ol.shadow_bias = 0.06
	ol.position = Vector3(0, 0.35, 0)
	(d.node as Node3D).add_child(ol)
	d["light"] = ol


## Lanterns the two of them (and viewers) released before the stream started: already up in the air round the pier,
## so the sky near the lens is never empty; they drift away and up like every other one.
func _seed_sky() -> void:
	for k in 34:
		var d := _make_lantern("chat", "", _rng.randf_range(0.85, 1.0))
		var a := _rng.randf_range(-1.1, 1.3)
		var r := _rng.randf_range(10.0, 60.0)
		var p := Vector3(PIER_X + sin(a) * r, _rng.randf_range(5.0, 34.0) + r * 0.35, KNEEL_Z - cos(a) * r)
		(d.node as Node3D).position = p
		d.vel = Vector3(0.05, _rng.randf_range(0.28, 0.45), -0.03)
		d.age = 30.0
		free_lanterns.append(d)


func _update_lanterns(delta: float) -> void:
	var gone := []
	for d in free_lanterns:
		var n: Node3D = d.node
		d.age = float(d.age) + delta
		var target := Vector3(0.05 + 0.03 * sin(_t * 0.2 + float(d.seed) * 9.0), 0.45 + float(d.seed) * 0.15, -0.035)
		d.vel = (d.vel as Vector3).lerp(target, clampf(delta * 0.25, 0.0, 1.0))
		n.position += (d.vel as Vector3) * delta
		n.rotation.y += float(d.spin) * delta
		n.rotation.z = sin(_t * 0.4 + float(d.seed) * 7.0) * 0.05
		var lt: OmniLight3D = d.light
		if lt:
			var hgt := n.position.y - DECK_Y
			lt.light_energy = maxf(0.0, lerpf(float(lt.get_meta("e0", lt.light_energy)), 0.0, smoothstep(2.0, 14.0, hgt)))
			if hgt > 14.0:
				lt.queue_free()
				d.light = null
		if n.position.y > 185.0:
			gone.append(d)
	for d in gone:
		(d.node as Node3D).queue_free()
		free_lanterns.erase(d)


# ---------------------------------------------------------------- their lantern: light it, lift it, let it go

func _spawn_held() -> void:
	held = _make_lantern("chat", "", 0.82)
	var n: Node3D = held.node
	n.position = Vector3(PIER_X, DECK_Y + 0.004, HELD_Z)
	(held.mat as ShaderMaterial).set_shader_parameter("lit", 0.0)
	n.scale = Vector3.ONE * 0.0
	_lantern_light(held, 0.0, true)
	(held.light as OmniLight3D).set_meta("e0", 1.6)
	held["appear"] = 0.0


func start_release() -> void:
	if ritual != "idle" or held.is_empty():
		return
	ritual = "reach"
	ritual_t = 0.0
	print("[lake] release: they light the lantern")


func _update_ritual(delta: float) -> void:
	if not _placed:
		return
	if ritual == "idle" and _t >= _next_release and not held.is_empty() and float(held.get("appear", 1.0)) >= 1.0:
		start_release()
	if held.is_empty() and _next_held > 0.0 and _t >= _next_held:
		_spawn_held()
		_next_held = -1.0
	if not held.is_empty() and float(held.get("appear", 1.0)) < 1.0:
		held.appear = minf(1.0, float(held.appear) + delta / 1.6)
		var a := float(held.appear)
		(held.node as Node3D).scale = Vector3.ONE * 0.82 * (a * a * (3.0 - 2.0 * a))
	if ritual == "idle":
		return
	ritual_t += delta
	var n: Node3D = held.node if not held.is_empty() else null
	var lt: OmniLight3D = held.light if not held.is_empty() else null
	match ritual:
		"reach":
			var k := smoothstep(0.6, 2.0, ritual_t)
			(held.mat as ShaderMaterial).set_shader_parameter("lit", k)
			lt.light_energy = 1.6 * k
			if ritual_t >= 2.0:
				ritual = "lift"
				ritual_t = 0.0
		"lift":
			var k := smoothstep(0.0, 2.0, ritual_t)
			n.position.y = DECK_Y + 0.004 + k * 1.02
			if ritual_t >= 2.0:
				ritual = "hold"
				ritual_t = 0.0
		"hold":
			n.position.y = DECK_Y + 1.026 + smoothstep(0.0, 1.2, ritual_t) * 0.2
			if ritual_t >= 1.2:
				ritual = "release"
				ritual_t = 0.0
				# it is free: up it goes, slowly, on its own warm air
				held.vel = Vector3(0.0, 0.05, 0.0)
				held.age = 0.0
				free_lanterns.append(held)
				_watch = n
				held = {}
				_next_held = _t + 24.0
				print("[lake] release: let go at %.1f s" % _t)
		"release":
			if ritual_t >= 1.4:
				ritual = "watch"
				ritual_t = 0.0
		"watch":
			if ritual_t >= 7.5:
				ritual = "idle"
				ritual_t = 0.0
				_watch = null
				_next_release = _t + release_every


## Where their hands are: 0 = resting in the lap, 1 = on the lantern's bottom hoop.
func _hand_w() -> float:
	match ritual:
		"reach": return smoothstep(0.0, 1.4, ritual_t)
		"lift", "hold": return 1.0
		"release": return 1.0
		"watch": return 1.0 - smoothstep(0.0, 1.8, ritual_t)
	return 0.0


## The hold point on the hoop for one hand (world), following the lantern; after the release the hands stay up
## for a moment where it was, open, then sink back.
var _last_hold := {}
func _grip(who: String, inner: bool) -> Vector3:
	var c: Vector3
	if not held.is_empty():
		c = (held.node as Node3D).global_position
		_last_hold["c"] = c
	else:
		c = _last_hold.get("c", Vector3(PIER_X, DECK_Y + 1.2, HELD_Z))
		if ritual == "release":
			c += Vector3(0, 0.12 * smoothstep(0.0, 0.6, ritual_t), 0)
	var me: WorldCharacter = characters[who]
	var to_me := me.global_position - c
	to_me.y = 0
	var dir := to_me.normalized()
	var r := 0.27 * 0.82
	var ang := deg_to_rad(28.0 if inner else -38.0) * (1.0 if who == "mika" else -1.0)
	return c + dir.rotated(Vector3.UP, ang) * (r + 0.02) + Vector3(0, 0.02, 0)


# ---------------------------------------------------------------- Mika and Luna

func _characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)
	WorldState.register_mind("luna")
	for spec in [["mika", "Mika", -1.0], ["luna", "Luna", 1.0]]:
		var who: String = spec[0]
		var c := WorldCharacter.new()
		c.name = spec[1]
		c.character_id = who
		c.display_name = spec[1]
		c.avatar_path = TransformationDirector.avatar_for(who)
		chars.add_child(c)
		c.global_position = Vector3(PIER_X + float(spec[2]) * KNEEL_GAP * 0.5, DECK_Y + 0.02, KNEEL_Z)
		c.rotation.y = 0.0
		characters[who] = c
		if c.foot_guard:
			c.foot_guard.enabled = false        # it would lift her hips back up off her heels
		c.apply_light_balance(0.9, 1.0)
		if c.face:
			c.face.set_baseline({"happy": 0.38, "relaxed": 0.4} if who == "mika" else {"happy": 0.3, "relaxed": 0.45})
		print("[lake] %s avatar=%s stage=%s" % [who, c.avatar_path, String(c.stage().get("id", "?"))])


func _play_clip(c: WorldCharacter, clip: String, fade := 0.3) -> void:
	var bt := c.anim_tree.tree_root as AnimationNodeBlendTree
	var one := bt.get_node("cast") as AnimationNodeOneShot
	one.fadein_time = fade
	one.fadeout_time = 0.4
	bt.get_node("cast_anim").animation = "mx/" + clip
	c.anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


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
	return (hp as Vector3) + Vector3(0, 0.08, 0) if hp != null else (characters[who] as Node3D).global_position + Vector3(0, 1.1, 0)


## Once the idle has settled: her height of hips over her feet is measured standing, then she kneels (seiza: her
## hips come down onto her heels, the legs folded under her by the scene's own leg IK), the springs get the deck
## and the arms their poses.
func _settle() -> void:
	await get_tree().create_timer(0.9).timeout
	for who in characters:
		var c: WorldCharacter = characters[who]
		c.set_physics_process(false)
		c.collision_layer = 0            # placed, not simulated: no camera ray (the framing guard's pull-back) stops on her
		c.global_position.y = DECK_Y
		await get_tree().process_frame
		var hp = _bone(c, ["Hips"])
		var up = _bone(c, [("LeftUpperLeg")])
		hip_rest[who] = ((hp as Vector3).y if hp != null else DECK_Y + 0.9) - DECK_Y
		thigh_rest[who] = ((up as Vector3).y if up != null else DECK_Y + 0.85) - DECK_Y
		var kn = _bone(c, ["LeftLowerLeg"])
		var ft = _bone(c, ["LeftFoot"])
		leg_len[who] = Vector2((up as Vector3).distance_to(kn), (kn as Vector3).distance_to(ft)) if up != null and kn != null and ft != null else Vector2(0.42, 0.4)
		print("[lake] %s: hips %.3f, hip joint %.3f, thigh %.3f, shin %.3f m" % [who, hip_rest[who], thigh_rest[who], leg_len[who].x, leg_len[who].y])
	await get_tree().process_frame
	for who in characters:
		var c: WorldCharacter = characters[who]
		if not RenderProfile.options.has("no-deck-springs"):
			_deck_springs(c, who)
		if not RenderProfile.options.has("no-arms"):
			_pose_arms(c, who)
		for vi in c.find_children("*", "VisualInstance3D", true, false):
			(vi as VisualInstance3D).layers = 1 | CHAR_LAYER
		if c.head_look:
			c.head_look.influence = 0.55
	_placed = true
	print("[lake] placed: ", _grounding())


## The spring bones (hair, skirt, sleeves) get the pier: one big sphere per chain whose top is the deck, so the skirt
## and hair rest on the planks instead of hanging through them. addons/vrm/vrm_secondary.gd places node colliders at
## S * S * node instead of S^-1 * S * ...; the node goes at S^-1 * S^-1 * (the point we mean) to cancel it
## (the skeleton stays put while she kneels).
func _deck_springs(c: WorldCharacter, who: String) -> void:
	var sec := c.avatar.find_child("secondary", true, false)
	if sec == null or sec.get("spring_bones") == null:
		return
	var kept = sec.spring_bones.duplicate()
	kept.clear()
	for sb in sec.spring_bones:
		var d: Resource = (sb as Resource).duplicate()
		var cm := String(d.get("comment"))
		if cm.begins_with("Skirt") or cm.begins_with("Cape") or cm.begins_with("Sash"):
			# kneeling, the skirt drapes over her folded thighs and falls to the planks round her (less memory of its
			# standing A-line shape, more weight, well damped)
			d.set("stiffness_scale", float(d.get("stiffness_scale")) * 0.4)
			d.set("drag_force_scale", clampf(float(d.get("drag_force_scale")) * 1.6, 0.0, 0.85))
			d.set("gravity_scale", float(d.get("gravity_scale")) * 1.8)
		elif cm.begins_with("Hair"):
			d.set("drag_force_scale", clampf(float(d.get("drag_force_scale")) * 1.25, 0.0, 0.8))
		kept.append(d)
	sec.spring_bones = kept
	var R := 40.0
	var n := 0
	var base := c.global_position
	for sb in sec.spring_bones:
		var hr: PackedFloat64Array = sb.hit_radius
		var rmax := 0.0
		for v in hr:
			rmax = maxf(rmax, v)
		rmax = float(sb.hit_radius_scale) * (rmax if not hr.is_empty() else 1.0)
		var ball := Node3D.new()
		ball.name = "DeckBall_%s_%d" % [who, n]
		add_child(ball)
		var want := Transform3D(Basis.IDENTITY, Vector3(base.x, DECK_Y + 0.015 - rmax - R, base.z))
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
	print("[lake] %s: deck collider on %d spring chains" % [who, n])


class LimbPose extends SkeletonModifier3D:
	## legs: [{upper, lower, foot, ankle: Callable -> world point, pole: Callable -> world dir, toe: Callable -> world point}]
	##        solved first (the kneel), then
	## arms: [{upper, lower, hand, target: Callable -> world point, pole: Callable -> world dir, w: Callable -> 0..1}]
	var legs: Array = []
	var arms: Array = []
	var watch := {}                  # name -> bone id: their final world positions are kept in `measured` (QA)
	var measured := {}

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		var inv := sk.global_transform.affine_inverse()
		for g in legs:
			var at: Vector3 = inv * ((g.ankle as Callable).call() as Vector3)
			var pl: Vector3 = (inv.basis * ((g.pole as Callable).call() as Vector3)).normalized()
			_two_bone(sk, g.upper, g.lower, g.foot, at, pl, 1.0)
			var kids := sk.get_bone_children(g.foot)
			if not kids.is_empty():
				var tp: Vector3 = inv * ((g.toe as Callable).call() as Vector3)
				_aim(sk, g.foot, sk.get_bone_global_pose(kids[0]).origin, tp, 1.0)
		for a in arms:
			var w: float = (a.w as Callable).call()
			if w <= 0.001:
				continue
			var tgt: Vector3 = inv * ((a.target as Callable).call() as Vector3)
			var pole: Vector3 = (inv.basis * ((a.pole as Callable).call() as Vector3)).normalized()
			_two_bone(sk, a.upper, a.lower, a.hand, tgt, pole, w)
		for k in watch:
			if int(watch[k]) >= 0:
				measured[k] = sk.global_transform * sk.get_bone_global_pose(watch[k]).origin

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


## Both hands rest in her lap; for the release both go to the lantern's hoop (the inner hand at its side, the outer
## one reaching across to its front), lift it up over their heads together and let it go.
func _pose_arms(c: WorldCharacter, who: String) -> void:
	var sk := c.skeleton
	var lp := LimbPose.new()
	lp.name = "LimbPose"
	sk.add_child(lp)
	var B := func(n: String) -> int: return sk.find_bone(n)
	var side := -1.0 if who == "mika" else 1.0         # Mika kneels on the left (west), Luna on the right
	var right := Vector3.RIGHT
	var fwd := Vector3.FORWARD
	# seiza: knees on the planks in front of her hips, shins flat on the deck behind them, the tops of her feet down
	# and her heels under her; when she rises onto her knees the knees stay where they are
	var lt: float = leg_len[who].x
	var ls: float = leg_len[who].y
	for leg in [["Left", -1.0], ["Right", 1.0]]:
		var pre: String = leg[0]
		var ls_side: float = leg[1]
		var knee_at := func() -> Vector3:
			var u = _bone(c, [pre + "UpperLeg"])
			var uu: Vector3 = u if u != null else c.global_position
			var kh := DECK_Y + 0.075
			var dk := sqrt(maxf(lt * lt - pow(uu.y - kh, 2.0), 0.0004))
			return Vector3(uu.x, kh, uu.z) + fwd * dk + right * ls_side * 0.012
		lp.legs.append({"upper": B.call(pre + "UpperLeg"), "lower": B.call(pre + "LowerLeg"), "foot": B.call(pre + "Foot"),
			"ankle": func() -> Vector3:
				var k: Vector3 = knee_at.call()
				var ah := DECK_Y + 0.07
				var back := sqrt(maxf(ls * ls - pow(k.y - ah, 2.0), 0.0004))
				return Vector3(k.x - ls_side * 0.02, ah, k.z) - fwd * back,
			"pole": func() -> Vector3: return fwd - Vector3.UP * 0.2,
			"toe": func() -> Vector3:
				var k: Vector3 = knee_at.call()
				var ah := DECK_Y + 0.07
				var back := sqrt(maxf(ls * ls - pow(k.y - ah, 2.0), 0.0004))
				return Vector3(k.x - ls_side * 0.03, DECK_Y + 0.035, k.z) - fwd * (back + 0.15)})
	var lap := func(hand_side: float) -> Vector3:
		# her hands rest on her thighs, a little toward her knees
		var pre := "Left" if hand_side < 0.0 else "Right"
		var u = _bone(c, [pre + "UpperLeg"])
		var k = _bone(c, [pre + "LowerLeg"])
		if u == null or k == null:
			return c.global_position + Vector3(0, 0.4, -0.2)
		return (u as Vector3).lerp(k, 0.62) + Vector3(0, 0.085, 0) - right * hand_side * 0.035
	for arm in [["Left", -1.0], ["Right", 1.0]]:
		var pre: String = arm[0]
		var hs: float = arm[1]
		var inner := hs == -side                      # the hand toward the other one (Mika's right, Luna's left)
		lp.arms.append({"upper": B.call(pre + "UpperArm"), "lower": B.call(pre + "LowerArm"), "hand": B.call(pre + "Hand"),
			"target": func() -> Vector3:
				var w := _hand_w()
				var rest: Vector3 = lap.call(hs)
				if w <= 0.0:
					return rest
				var g := _grip(who, inner)
				var e := w * w * (3.0 - 2.0 * w)
				return rest.lerp(g, e),
			"pole": func() -> Vector3: return right * hs * 0.8 - fwd * 0.1 - Vector3.UP * 0.6,
			"w": func() -> float: return 1.0})
	for part in [["head", "Head"], ["hips", "Hips"], ["l_knee", "LeftLowerLeg"], ["r_knee", "RightLowerLeg"], ["l_foot", "LeftFoot"],
			["r_foot", "RightFoot"], ["l_toes", "LeftToes"], ["r_toes", "RightToes"], ["l_hand", "LeftHand"], ["r_hand", "RightHand"]]:
		lp.watch[part[0]] = B.call(part[1])
	limbs[who] = lp


## Faces never frozen: they look out over the lake, up at the lanterns, at each other; during a release both follow
## their lantern up into the sky. Gentle smiles and soft moods; the face rig blinks on its own.
func _animate_faces(delta: float) -> void:
	if not _placed:
		return
	for who in characters:
		var c: WorldCharacter = characters[who]
		var other := "luna" if who == "mika" else "mika"
		_look_t[who] = float(_look_t[who]) - delta
		if float(_look_t[who]) <= 0.0:
			_look_t[who] = randf_range(2.5, 6.0)
			var r := randf()
			_look_tgt[who] = "lake" if r < 0.4 else ("sky" if r < 0.7 else other)
		var tgt := _head(who) + Vector3(0, 0.6, -6.0)
		match String(_look_tgt[who]):
			"sky":
				tgt = _head(who) + Vector3((0.8 if who == "luna" else -0.6), 4.5, -5.0)
			"mika", "luna":
				tgt = _head(other) + Vector3(0, -0.05, -0.1)
		if ritual in ["reach", "lift", "hold"] and not held.is_empty():
			tgt = (held.node as Node3D).global_position + Vector3(0, 0.45, 0)
		elif _watch and is_instance_valid(_watch):
			tgt = _watch.global_position + Vector3(0, 0.4, 0)
		var ht: Node3D = c.get("_head_target")
		if ht:
			ht.global_position = ht.global_position.lerp(tgt, clampf(delta * 2.0, 0.0, 1.0))
		_mood_t[who] = float(_mood_t[who]) - delta
		if float(_mood_t[who]) <= 0.0 and c.face:
			_mood_t[who] = randf_range(5.0, 9.0)
			var moods := ["happy", "relaxed", "happy", "shy"] if who == "mika" else ["happy", "relaxed", "thoughtful", "happy"]
			c.face.pulse(moods[randi() % moods.size()], randf_range(0.3, 0.55), randf_range(1.6, 3.0))


# ---------------------------------------------------------------- viewer lanterns (the hook for the stream)

## A viewer's lantern: it appears just past the end of the pier beside the two of them, glows up, and rises into
## the festival with their name glowing softly on two sides. kind: chat | subscriber | member | superchat.
## (2026-10-19, LakeRitual) at: where it appears (world; default the end of the pier); face: a world point its name
## turns toward (the lens). Every launch emits viewer_launched (the two of them look up at it and thank the viewer).
func viewer_lantern(viewer: String, kind := "chat", at := Vector3.INF, face := Vector3.INF) -> void:
	viewer = viewer.strip_edges().substr(0, 28)
	if viewer == "":
		return
	if not KINDS.has(kind):
		kind = "chat"
	_viewer_queue.append([viewer, kind, at, face])


## Their own lantern (no name) let go at a world point (from the boat).
func release_at(at: Vector3) -> void:
	_viewer_queue.append(["", "chat", at, Vector3.INF])


signal viewer_launched(viewer: String, kind: String, lantern: Node3D)


func _launch_viewer(viewer: String, kind: String, at := Vector3.INF, face := Vector3.INF) -> void:
	var d := _make_lantern(kind, viewer, 0.9 if kind != "superchat" else 1.05)
	var n: Node3D = d.node
	_viewer_side = -_viewer_side
	n.position = Vector3(PIER_X + _viewer_side * 1.15, DECK_Y + 0.25, PIER_Z1 - 0.7)
	n.rotation.y = PI + _rng.randf_range(-0.3, 0.3)       # the name side toward the shore and the lenses
	d.vel = Vector3(0.0, 0.12, -0.02)
	d.spin = _rng.randf_range(-0.06, 0.06)
	if at != Vector3.INF:
		n.global_position = at
		d.spin = _rng.randf_range(-0.02, 0.02)
	if face != Vector3.INF:
		var fd := face - n.global_position
		n.global_rotation = Vector3(0.0, atan2(-fd.x, -fd.z), 0.0)     # (the name is on its local -Z side)
	_lantern_light(d, 1.1 if kind == "superchat" else 0.8, false)
	(d.light as OmniLight3D).set_meta("e0", (d.light as OmniLight3D).light_energy)
	free_lanterns.append(d)
	counts["viewer_lanterns"] = int(counts.get("viewer_lanterns", 0)) + 1
	print("[lake] viewer lantern: %s (%s)" % [viewer, kind])
	viewer_launched.emit(viewer, kind, n)
	# they notice it
	for who in characters:
		_look_t[who] = 3.5
	if ritual == "idle":
		_watch = n
		get_tree().create_timer(4.0).timeout.connect(func(): if ritual == "idle": _watch = null)
	for who in characters:
		var c: WorldCharacter = characters[who]
		if c.face:
			c.face.pulse("happy", 0.55, 2.2)
	if free_lanterns.size() > 70:
		# the oldest viewer-free lanterns high up go first
		for old in free_lanterns:
			if (old.node as Node3D).position.y > 60.0:
				(old.node as Node3D).queue_free()
				free_lanterns.erase(old)
				break


func _poll_commands(delta: float) -> void:
	_viewer_cool -= delta
	if not _viewer_queue.is_empty() and _viewer_cool <= 0.0 and _placed:
		var it: Array = _viewer_queue.pop_front()
		_launch_viewer(it[0], it[1], it[2] if it.size() > 2 else Vector3.INF, it[3] if it.size() > 3 else Vector3.INF)
		_viewer_cool = 1.4
	_cmd_poll -= delta
	if _cmd_poll > 0.0:
		return
	_cmd_poll = 0.5
	var path := "user://lantern_lake_commands.txt"
	if not FileAccess.file_exists(path):
		return
	var txt := FileAccess.get_file_as_string(path)
	if txt.strip_edges() == "":
		return
	FileAccess.open(path, FileAccess.WRITE).close()
	for line in txt.split("\n"):
		var l := line.strip_edges()
		if l == "":
			continue
		if l == "release":
			start_release()
			continue
		var kd := l.get_slice(" ", 0).to_lower()
		var nm := l.substr(kd.length()).strip_edges() if KINDS.has(kd) else l
		viewer_lantern(nm, kd if KINDS.has(kd) else "chat")


# ---------------------------------------------------------------- sky, light, mist, fireflies, post

func _environment() -> void:
	env = host_env if embedded and host_env else Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skm := ShaderMaterial.new()
	skm.shader = load("res://shaders/lantern_lake/dusk_sky.gdshader")
	sky.sky_material = skm
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.22, 0.42)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# linear: the painted sky keeps exactly the colours it was painted in; lantern cores clip warm-white
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.2
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.75
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.05
	env.glow_hdr_scale = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for lv in [[0, 0.0], [1, 0.35], [2, 0.7], [3, 0.9], [4, 0.6], [5, 0.3], [6, 0.0]]:
		env.set_glow_level(lv[0], lv[1])
	# violet depth haze over the far water and banks; low mist on the lake
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.26, 0.24, 0.45)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0042
	env.fog_sky_affect = 0.0
	env.fog_height = WATER_Y + 2.2
	env.fog_height_density = 0.06
	env.adjustment_enabled = false
	env.glow_enabled = not RenderProfile.options.has("no-glow")
	if embedded:
		return                             # (the area's WorldEnvironment carries it)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _lights() -> void:
	# a weak cool sky light from the north-west afterglow: shapes, no cast shadows (the lanterns are the light here)
	var dl := DirectionalLight3D.new()
	dl.name = "DuskSky"
	dl.light_color = Color(0.62, 0.62, 1.0)
	dl.light_energy = 0.32
	dl.light_specular = 0.0          # no glare off the wet mud and the planks
	dl.shadow_enabled = false
	dl.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(dl)
	dl.look_at_from_position(Vector3.ZERO, Vector3(0.25, -0.45, 1.0), Vector3.UP)
	# the two of them: a soft cool fill from the lake side so their hair and clothes read against the water
	var cf := DirectionalLight3D.new()
	cf.name = "FillOnThem"
	cf.light_color = Color(0.72, 0.74, 1.0)
	cf.light_energy = 0.38
	cf.light_specular = 0.1
	cf.shadow_enabled = false
	cf.light_cull_mask = CHAR_LAYER if not embedded else 0xFFFFF     # (embedded: the real mages are on layer 1)
	cf.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(cf)
	cf.look_at_from_position(Vector3.ZERO, Vector3(-0.2, -0.55, 0.8), Vector3.UP)


func _mist() -> void:
	if RenderProfile.options.has("no-mist"):
		return
	var sh := load("res://shaders/lantern_lake/mist.gdshader")
	for L in [[0.18, 0.26, 0.0], [0.6, 0.2, 1.7], [1.25, 0.14, 3.9]]:
		var pm := PlaneMesh.new()
		pm.size = Vector2(1400, 1400)
		var mi := MeshInstance3D.new()
		mi.name = "Mist"
		mi.mesh = pm
		mi.position = Vector3(0, WATER_Y + float(L[0]), -450)
		mi.layers = MIST_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("density", L[1])
		sm.set_shader_parameter("layer_seed", L[2])
		mi.material_override = sm
		add_child(mi)


func _emitter(nm: String, at: Vector3, amount: int, life: float, box: Vector3, quad: float) -> void:
	var gp := GPUParticles3D.new()
	gp.name = nm
	gp.amount = maxi(1, int(amount * float(RenderProfile.get_setting("particle_scale"))))
	gp.lifetime = life
	gp.preprocess = life
	gp.visibility_aabb = AABB(-box - Vector3(6, 6, 6), (box + Vector3(6, 6, 6)) * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.gravity = Vector3(0, 0.01, 0)
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.15
	pm.direction = Vector3(0.3, 0.3, 0.2)
	pm.spread = 160.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.08
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
	q.size = Vector2(quad, quad)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/moonbloom/firefly.gdshader")
	sm.set_shader_parameter("color", Color(0.9, 0.95, 0.45))
	sm.set_shader_parameter("energy", 4.0)
	q.material = sm
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.position = at
	add_child(gp)


func _fireflies() -> void:
	_emitter("FirefliesNearShore", Vector3(-4.0, 0.9, 6.5), 40, 9.0, Vector3(6.0, 0.6, 2.5), 0.04)
	_emitter("FirefliesPierBank", Vector3(9.0, 1.0, 8.0), 35, 9.0, Vector3(5.0, 0.7, 3.0), 0.04)
	_emitter("FirefliesLeftBank", Vector3(-38.0, 1.4, -20.0), 120, 10.0, Vector3(8.0, 1.2, 40.0), 0.12)
	_emitter("FirefliesRightBank", Vector3(48.0, 1.4, -20.0), 120, 10.0, Vector3(8.0, 1.2, 40.0), 0.12)


func _post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/lantern_lake/post.gdshader")
	cr.material = sm
	cr.visible = not RenderProfile.options.has("no-post")
	layer.add_child(cr)


# ---------------------------------------------------------------- the reflection

func _reflection() -> void:
	refl_vp = SubViewport.new()
	refl_vp.name = "LakeReflection"
	var vs := get_viewport().get_visible_rect().size
	var rs := float(RenderProfile.options.get("reflect-scale", "0.5"))
	refl_vp.size = Vector2i(int(vs.x * rs), int(vs.y * rs))
	refl_vp.use_hdr_2d = true
	refl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	refl_vp.msaa_3d = Viewport.MSAA_DISABLED
	refl_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	refl_vp.positional_shadow_atlas_size = 0
	refl_vp.use_taa = false
	add_child(refl_vp)
	refl_cam = Camera3D.new()
	refl_cam.name = "MirrorCamera"
	refl_cam.cull_mask = 0xFFFFF & ~(WATER_LAYER | MIST_LAYER | GRASS_LAYER)
	refl_cam.near = 0.05
	refl_cam.far = 2500.0
	var re := env.duplicate() as Environment
	re.glow_enabled = false
	re.ssao_enabled = false
	refl_cam.environment = re
	refl_vp.add_child(refl_cam)
	refl_cam.current = true
	water_mat.set_shader_parameter("reflection", refl_vp.get_texture())
	RenderingServer.viewport_set_measure_render_time(refl_vp.get_viewport_rid(), true)


## Every frame right before drawing (after every camera script and the framing guard): the mirror image of the
## lens below the water plane. A mirror flips handedness, so the camera keeps a proper basis (x negated) and the
## water samples the image mirrored back (1 - u).
func _mirror_camera() -> void:
	var vc: Camera3D = cam if cam else (get_viewport().get_camera_3d() if is_inside_tree() else null)
	if refl_cam == null or vc == null:
		return
	var g := vc.global_transform
	var R := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1))
	var b := Basis(-(R * g.basis.x), R * g.basis.y, R * g.basis.z)
	var p := g.origin
	refl_cam.global_transform = Transform3D(b, Vector3(p.x, 2.0 * WATER_Y - p.y, p.z))
	refl_cam.fov = vc.fov
	refl_cam.keep_aspect = vc.keep_aspect


# ---------------------------------------------------------------- cameras

## wide: from the near shore left of the pier, low among the reeds: the pier coming in from the right, the two of them
##   kneeling at its end, the lake full of lanterns, the mountains and the sky (slow push)
## medium: behind them on the pier, three-quarter: both whole, kneeling, the lantern between them, the lake beyond
## water: low over the water off the end of the pier: the two from the front-left, small, their reflections
## rise: from the pier behind them, tilting up after their lantern into the festival
## high: a high wide over the bank: the whole lake, the pier, the lanterns
## (no close-ups, ever: docs/world_look_rules.md)
func _shot(nm: String, t: float) -> Dictionary:
	var e := t * t * (3.0 - 2.0 * t)
	match nm:
		"medium":
			var p := Vector3(PIER_X + lerpf(1.75, 1.55, e), DECK_Y + lerpf(1.42, 1.32, e), KNEEL_Z + lerpf(3.3, 3.0, e))
			return {"pos": p, "at": Vector3(PIER_X - 0.25, DECK_Y + 0.85, KNEEL_Z - 2.6), "fov": 50.0}
		"water":
			var p := Vector3(lerpf(-2.2, -1.6, e), WATER_Y + 0.5, KNEEL_Z - lerpf(7.4, 7.0, e))
			return {"pos": p, "at": Vector3(PIER_X + 0.4, DECK_Y + 0.95, KNEEL_Z + 0.4), "fov": 52.0}
		"rise":
			var follow: Vector3 = _last_hold.get("c", Vector3(PIER_X, DECK_Y + 1.3, HELD_Z))
			if _watch and is_instance_valid(_watch):
				follow = _watch.global_position
			var p := Vector3(PIER_X + 1.0, DECK_Y + 1.5, KNEEL_Z + 4.4)
			# follows it up, but never so far that the two of them leave the bottom of the frame
			var at := Vector3(PIER_X - 0.1, clampf(follow.y + 1.0, DECK_Y + 2.2, DECK_Y + 2.9) + lerpf(0.0, 0.4, e), clampf(follow.z - 1.0, KNEEL_Z - 9.0, KNEEL_Z - 1.5))
			return {"pos": p, "at": at, "fov": 62.0}
		"side_probe":
			# dev only (--still --shots=side_probe): their legs from the side, to check the kneel
			return {"pos": Vector3(PIER_X - 3.4, DECK_Y + 0.6, KNEEL_Z - 0.1), "at": Vector3(PIER_X, DECK_Y + 0.4, KNEEL_Z - 0.1), "fov": 40.0}
		"high":
			var p := Vector3(lerpf(-7.0, -5.5, e), 8.5, lerpf(18.0, 16.5, e))
			return {"pos": p, "at": Vector3(PIER_X + 2.0, 1.0, -28.0), "fov": 55.0}
	# wide
	var p := Vector3(lerpf(-1.9, -1.4, e), 1.38, lerpf(6.4, 5.8, e))
	return {"pos": p, "at": Vector3(PIER_X + 2.4, 3.4, -16.0), "fov": 55.0}


func _cameras() -> void:
	cam = Camera3D.new()
	cam.name = "StreamCamera"
	cam.near = 0.05
	cam.far = 2500.0
	add_child(cam)
	cam.current = true
	var want := String(RenderProfile.options.get("cam", "cine"))
	if want in ["wide", "medium", "water", "rise", "high"]:
		mode = "hold"
		shot = want
	_apply_shot(0.0)


func _shot_len(nm: String) -> float:
	for s in LOOP:
		if s[0] == nm:
			return float(s[1])
	return 8.0


func _apply_shot(delta: float) -> void:
	if mode == "probe":
		return
	shot_t += delta
	var list: Array = SEQUENCE if RenderProfile.options.has("clip") else LOOP
	if mode == "cine":
		var dur := float(list[_seq_i % list.size()][1])
		if shot_t >= dur:
			shot_t -= dur
			_seq_i += 1
		shot = String(list[_seq_i % list.size()][0])
		dur = float(list[_seq_i % list.size()][1])
		_frame(_shot(shot, clampf(shot_t / dur, 0.0, 1.0)))
	else:
		var ping := absf(fmod(shot_t / _shot_len(shot), 2.0) - 1.0)
		_frame(_shot(shot, 1.0 - ping))


func _frame(s: Dictionary) -> void:
	var drift := Vector3(sin(_t * 0.23) * 0.02, sin(_t * 0.17 + 1.0) * 0.012, cos(_t * 0.19) * 0.018)
	cam.fov = s.fov
	cam.look_at_from_position(s.pos + drift, s.at, Vector3.UP)


## Her hips over the planks: down on her heels, or up on her knees while they lift the lantern (the knees stay put:
## her hips come forward as they rise).
func _update_kneel(delta: float) -> void:
	if leg_len.is_empty():
		return
	var want := 0.0
	match ritual:
		"lift": want = smoothstep(0.2, 1.8, ritual_t)
		"hold", "release": want = 1.0
		"watch": want = 1.0 - smoothstep(1.5, 4.0, ritual_t)
	kneel_up = move_toward(kneel_up, want, delta * 0.9)
	var e := kneel_up * kneel_up * (3.0 - 2.0 * kneel_up)
	for who in characters:
		if not leg_len.has(who):
			continue
		var c: WorldCharacter = characters[who]
		var lt: float = leg_len[who].x
		var kh := 0.075
		var h_seiza := 0.255
		var h_tall := kh + lt * 0.95
		var hh := lerpf(h_seiza, h_tall, e)
		var dk0 := sqrt(maxf(lt * lt - pow(h_seiza - kh, 2.0), 0.0))
		var dk := sqrt(maxf(lt * lt - pow(hh - kh, 2.0), 0.0))
		c.avatar.position = Vector3(0.0, hh - float(thigh_rest[who]), -(dk0 - dk))


var _prof := {}
## (embedded) a lantern set free from the end of the pier - when the two sitting there let one go.
func release_from_pier() -> void:
	_launch_viewer("", "chat")


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_mirror_camera):
		RenderingServer.frame_pre_draw.disconnect(_mirror_camera)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_t += delta
	if embedded:
		_update_lanterns(delta)
		_poll_commands(delta)
		return
	_update_ritual(delta)
	_update_kneel(delta)
	_update_lanterns(delta)
	_poll_commands(delta)
	_apply_shot(delta)
	_animate_faces(delta)
	if overlay and overlay.visible:
		overlay.text = _monitor_text()
	if RenderProfile.options.has("cpu-prof"):
		_prof["n"] = int(_prof.get("n", 0)) + 1
		_prof["us"] = int(_prof.get("us", 0)) + Time.get_ticks_usec() - t0
		if int(_prof.n) % 60 == 0:
			print("[lake] cpu: scene _process %.2f ms/frame | process %.1f ms physics %.1f ms | fps %.1f" % [float(_prof.us) / 60000.0,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_FPS)])
			_prof.us = 0


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var keys := {KEY_1: "wide", KEY_2: "medium", KEY_3: "water", KEY_4: "rise", KEY_5: "high"}
		if keys.has(e.keycode):
			mode = "hold"
			shot = keys[e.keycode]
			shot_t = 0.0
		elif e.keycode == KEY_0:
			mode = "cine"
			shot_t = 0.0
		elif e.keycode == KEY_L:
			var names := ["Aiko", "StarryNight", "Mochi_42", "Kenji", "LunaFan", "Sakura"]
			var kinds := KINDS.keys()
			viewer_lantern(names[randi() % names.size()], kinds[randi() % kinds.size()])
		elif e.keycode == KEY_R:
			start_release()
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
	return "%s | %.1f fps | gpu %.1f ms (+refl %.1f) | draw %d | prims %dk | vram %.0f MB | %s" % [shot, m.fps, m.gpu_ms,
		m.refl_gpu_ms, m.draw_calls, int(m.primitives / 1000), m.vram_mb, ritual]


func monitors() -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		"refl_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(refl_vp.get_viewport_rid()) if refl_vp else 0.0,
		"cpu_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	}


# ---------------------------------------------------------------- clip, QA, pose probe

func _clip() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	mode = "hold"
	shot = "wide"
	_next_release = 1e9
	var vq := _viewer_queue.duplicate()
	_viewer_queue.clear()
	await get_tree().create_timer(WARMUP).timeout
	mode = "cine"
	_seq_i = 0
	shot_t = 0.0
	# a viewer's lantern goes up in the wide shot; theirs is lit at 1.7 s, lifted through the medium shot and let go
	# as it ends, and the last shot follows it up
	for it in vq:
		_viewer_queue.append(it)
	_viewer_cool = 0.6
	get_tree().create_timer(1.7).timeout.connect(start_release)
	await get_tree().create_timer(10.2).timeout
	get_tree().quit()


func _qa() -> void:
	var out := String(RenderProfile.options.get("out", ProjectSettings.globalize_path("user://lantern_lake_qa")))
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	var measure_s := float(RenderProfile.options.get("measure", "8"))
	var report := {"adapter": RenderingServer.get_video_adapter_name(), "profile": RenderProfile.profile, "max_fps": Engine.max_fps,
		"window": DisplayServer.window_get_size(), "reflection": refl_vp.size, "counts": counts, "shots": {}}
	mode = "hold"
	shot = "wide"
	_next_release = 1e9
	await get_tree().create_timer(WARMUP + 1.0).timeout
	report["grounding"] = _grounding()
	viewer_lantern("Aiko", "member")
	viewer_lantern("StarryNight", "superchat")
	var names := ["wide", "medium", "water", "rise", "high"]
	for nm in names:
		shot = nm
		shot_t = 0.0
		if nm == "medium":
			start_release()            # caught mid-lift in the medium shot
		_apply_shot(0.0)
		await get_tree().create_timer(2.0 if nm != "medium" else 3.2).timeout
		guard.worst_frac = 0.0
		var hits0: int = int(guard.get("hits")) if guard else 0
		var r := await _measure(measure_s if nm != "medium" else 1.0)
		r["largest_face_frac_of_frame"] = snappedf(guard.worst_frac, 0.001)
		r["guard_corrections"] = (int(guard.get("hits")) if guard else 0) - hits0
		r["rule_ok"] = guard.worst_frac <= FramingRule.MAX_FACE_FRAC + 0.005
		r["ritual"] = ritual
		await RenderingServer.frame_post_draw
		var path := out.path_join("lake_%s.png" % nm)
		get_viewport().get_texture().get_image().save_png(path)
		r["shot"] = path
		report.shots[nm] = r
		print("[lake] %s: fps %.2f worst %.1f ms hitches %d gpu %.2f/%.2f ms (refl %.2f) cpu %.1f draw %d prims %dk vram %.0f MB face %.1f%% rule_ok %s %s" % [nm,
			r.fps, r.worst_frame_ms, r.hitches_over_50ms, r.gpu_ms_median, r.gpu_ms_p95, r.refl_gpu_ms_median, r.cpu_process_ms_median, r.draw_calls, int(r.primitives / 1000),
			r.vram_mb, r.largest_face_frac_of_frame * 100.0, r.rule_ok, ritual])
		if nm == "medium":
			# the rest of the medium measurement once the lantern is up
			var r2 := await _measure(measure_s)
			for k in ["fps", "worst_frame_ms", "hitches_over_50ms", "gpu_ms_median", "gpu_ms_p95", "refl_gpu_ms_median", "cpu_process_ms_median", "draw_calls", "primitives", "vram_mb"]:
				r[k] = r2[k]
			r["largest_face_frac_of_frame"] = snappedf(guard.worst_frac, 0.001)
			r["rule_ok"] = guard.worst_frac <= FramingRule.MAX_FACE_FRAC + 0.005
	report["grounding_end"] = _grounding()
	report["viewer_lanterns"] = counts.get("viewer_lanterns", 0)
	var f := FileAccess.open(out.path_join("lake_report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[lake] report written: ", out.path_join("lake_report.json"))
	get_tree().quit()


func _measure(seconds: float) -> Dictionary:
	var frames := 0
	var t := 0.0
	var worst := 0.0
	var hitches := 0
	var gpu := []
	var rg := []
	var cpu := []
	var draws := []
	var prims := []
	var vram := 0.0
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		frames += 1
		worst = maxf(worst, dt)
		if dt > 0.05:
			hitches += 1
		var m := monitors()
		gpu.append(m.gpu_ms)
		rg.append(m.refl_gpu_ms)
		cpu.append(m.cpu_ms)
		draws.append(m.draw_calls)
		prims.append(m.primitives)
		vram = maxf(vram, m.vram_mb)
	gpu.sort()
	rg.sort()
	cpu.sort()
	return {"fps": snappedf(frames / t, 0.01), "frames": frames, "worst_frame_ms": snappedf(worst * 1000.0, 0.1),
		"hitches_over_50ms": hitches, "gpu_ms_median": snappedf(gpu[gpu.size() / 2], 0.01),
		"gpu_ms_p95": snappedf(gpu[int(gpu.size() * 0.95)], 0.01), "refl_gpu_ms_median": snappedf(rg[rg.size() / 2], 0.01),
		"cpu_process_ms_median": snappedf(cpu[cpu.size() / 2], 0.01),
		"draw_calls": int(draws.max()), "primitives": int(prims.max()), "vram_mb": snappedf(vram, 0.1)}


## Kneeling on the planks, not floating or sunk: knees, shins and feet just above the deck (the final pose, as the
## scene's pose modifier leaves it).
func _grounding() -> Dictionary:
	var g := {}
	for who in characters:
		var c: WorldCharacter = characters[who]
		var d := {}
		if limbs.has(who) and not (limbs[who] as LimbPose).measured.is_empty():
			for k in (limbs[who] as LimbPose).measured:
				d[k + "_above_deck_m"] = snappedf(((limbs[who] as LimbPose).measured[k] as Vector3).y - DECK_Y, 0.001)
			g[who] = d
			continue
		for part in [["head", "Head"], ["hips", "Hips"], ["l_knee", "LeftLowerLeg"], ["r_knee", "RightLowerLeg"], ["l_foot", "LeftFoot"], ["r_foot", "RightFoot"], ["l_hand", "LeftHand"], ["r_hand", "RightHand"]]:
			var bp = _bone(c, [part[1]])
			if bp != null:
				d[part[0] + "_above_deck_m"] = snappedf((bp as Vector3).y - DECK_Y, 0.001)
		g[who] = d
	return g


## Development aid: one still per listed shot after the warm-up (--still=/abs/dir [--shots=wide,medium]
## [--release-at=s] starts their release that many seconds into the warm-up).
func _still() -> void:
	var out := String(RenderProfile.options.get("still"))
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	mode = "hold"
	_next_release = 1e9
	if RenderProfile.options.has("release-at"):
		get_tree().create_timer(float(RenderProfile.options.get("release-at"))).timeout.connect(start_release)
	await get_tree().create_timer(float(RenderProfile.options.get("warm", str(WARMUP)))).timeout
	print("[lake] grounding: ", _grounding())
	for nm in String(RenderProfile.options.get("shots", "wide")).split(","):
		shot = nm
		shot_t = 0.0
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("still_%s.png" % nm))
		print("[lake] still %s: %s | ritual %s | fps %.1f gpu %.1f refl %.1f draw %d" % [nm, out, ritual, Performance.get_monitor(Performance.TIME_FPS),
			monitors().gpu_ms, monitors().refl_gpu_ms, monitors().draw_calls])
	get_tree().quit()


## Development aid: the kneel clip sampled every 0.3 s, a still each, from the side (--pose-probe --out=dir).
func _pose_probe() -> void:
	var out := String(RenderProfile.options.get("out", ProjectSettings.globalize_path("user://lake_probe")))
	DirAccess.make_dir_recursive_absolute(out)
	mode = "probe"
	guard.process_mode = Node.PROCESS_MODE_DISABLED      # a pose check of the rig, never shown to viewers
	await get_tree().create_timer(2.0).timeout
	var c: WorldCharacter = characters["mika"]
	var lib := c.body_player.get_animation_library("mx")
	var clip := String(RenderProfile.options.get("probe-clip", "kneel_fix"))
	var src := lib.get_animation(clip)
	print("[lake] probe %s length %.2f" % [clip, src.length])
	cam.fov = 40.0
	var t := 0.0
	while t <= src.length:
		var fr := WorldCharacter._bake_variant(src, "freeze", t)
		fr.loop_mode = Animation.LOOP_LINEAR
		var key := "probe_%d" % int(t * 10)
		lib.add_animation(key, fr)
		for who in characters:
			_play_clip(characters[who], key, 0.0)
		await get_tree().create_timer(0.35).timeout
		var hp: Vector3 = characters["mika"].global_position
		cam.look_at_from_position(hp + Vector3(-2.3, 0.75, -0.9), hp + Vector3(0, 0.45, 0), Vector3.UP)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("probe_%s_%04.1f.png" % [clip, t]))
		t += 0.3
	get_tree().quit()
