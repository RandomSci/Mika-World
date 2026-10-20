class_name DanceStage
extends Node3D
## The moonlit Lantern Lake for the lake dance (2026-10-19, Selwyn's targets T1-T3): a deep navy starry sky with a
## full moon of normal size, warm golden lanterns floating on the water and hanging in the air round her, her real
## skin and outfit colours (a neutral moon key on her, no blue wash), strong bloom, no blur. lift() raises every
## lantern and brightens it for the finale. Only for the dance scene: it dresses the area it is given and nothing else.

const CHAR_LAYER := 1 << 12            # her own key light reaches only her
const MOON_LAYER := 1 << 13            # the moon stays out of the lake mirror (a solid disc there read as a sticker)
const GOLD_TINT := Color(1.0, 0.56, 0.17)
const GOLD_HOT := Color(1.0, 0.9, 0.64)

var lake: Node3D
var center := Vector3.ZERO             # where she dances (on the water)
var water_y := 0.0
var lantern_mats: Array = []
var _water_mm: MultiMesh
var _water_base: Array = []            # [index, Transform3D, delay, height]
var _hover: Array = []                 # {node, base, seed, rise}
var _lift_t := -1.0
var _moon_dir := Vector3.ZERO
var moon_node: MeshInstance3D
static var moon_up := 0.27              # the moon's place and size (the MV: higher and bigger, an anime moon)
static var moon_side := 0.5
static var moon_size := 150.0
static var lantern_keep := 1.0          # share of the festival lanterns kept (a quiet night out in the boat: few)
static var hover_lanterns := true
static var clear_radius := 2.6           # no floating lanterns this close to the centre
var _shimmer: MeshInstance3D
var _t := 0.0


static func build(lake_node: Node3D, at: Vector3, water: float, cams: Array, who: WorldCharacter) -> DanceStage:
	var s := DanceStage.new()
	s.name = "DanceStage"
	s.lake = lake_node
	s.center = at
	s.water_y = water
	lake_node.add_child(s)
	s.add_to_group("env_owner")               # (the day/night cycle leaves the look alone while the stage stands)
	s._look()
	s._moon(cams)
	s._light_her(who, cams)
	s._lanterns(cams)
	return s


func _envs() -> Array:
	var out := []
	for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		if (we as WorldEnvironment).environment and not ((we as WorldEnvironment).environment in out):
			out.append((we as WorldEnvironment).environment)
	var cam := get_viewport().get_camera_3d()
	if cam and cam.environment and not (cam.environment in out):
		out.append(cam.environment)
	var rc = lake.get("refl_cam")
	if rc and (rc as Camera3D).environment and not ((rc as Camera3D).environment in out):
		out.append((rc as Camera3D).environment)
	return out


## The night: navy sky and haze, bright stars, neutral ambient, strong bloom (the mirror keeps its glow off).
func _look() -> void:
	for env in _envs():
		var e := env as Environment
		if e.sky and e.sky.sky_material is ShaderMaterial:
			var sm := e.sky.sky_material as ShaderMaterial
			for kv in [["zenith", Color(0.025, 0.06, 0.17)], ["upper", Color(0.04, 0.09, 0.24)], ["low", Color(0.09, 0.17, 0.36)],
					["glow_col", Color(0.16, 0.26, 0.5)], ["haze", Color(0.1, 0.16, 0.3)], ["mtn_near", Color(0.03, 0.05, 0.11)],
					["mtn_mid", Color(0.05, 0.08, 0.17)], ["mtn_far", Color(0.09, 0.13, 0.25)], ["star_energy", 2.6]]:
				sm.set_shader_parameter(kv[0], kv[1])
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.3, 0.33, 0.42)
		e.ambient_light_energy = 0.35
		e.fog_light_color = Color(0.08, 0.13, 0.26)
		e.fog_density = 0.0032
		e.adjustment_enabled = false
		if e.glow_enabled:
			e.glow_intensity = 1.0
			e.glow_strength = 1.0
			e.glow_bloom = 0.0
			e.glow_hdr_threshold = 1.0
			e.glow_hdr_scale = 1.4
			e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
			for lv in [[0, 0.0], [1, 0.5], [2, 0.85], [3, 0.9], [4, 0.6], [5, 0.3], [6, 0.0]]:
				e.set_glow_level(lv[0], lv[1])
	# the lake's own lights: neutral silver moonlight instead of the violet dusk
	for nm in ["DuskSky", "FillOnThem"]:
		for l in lake.find_children(nm, "DirectionalLight3D", true, false):
			(l as DirectionalLight3D).light_color = Color(0.8, 0.85, 1.0) if nm == "DuskSky" else Color(0.95, 0.96, 1.0)
			(l as DirectionalLight3D).light_energy = 0.3 if nm == "DuskSky" else 0.35


## A full moon high over the far lake, up and to one side of where the camera looks (about 4 degrees across).
func _moon(cams: Array) -> void:
	var cam: Vector3 = cams[0]
	var look := (center - cam)
	look.y = 0.0
	look = look.normalized()
	var side := look.cross(Vector3.UP).normalized()
	var dir := (look - side * moon_side + Vector3.UP * moon_up).normalized()
	var mi := MeshInstance3D.new()
	mi.name = "Moon"
	var q := QuadMesh.new()
	q.size = Vector2(moon_size, moon_size)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/dance/moon.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0
	mi.layers = MOON_LAYER
	var rc = lake.get("refl_cam")
	if rc:
		(rc as Camera3D).cull_mask &= ~MOON_LAYER
	add_child(mi)
	mi.global_position = center + dir * 600.0
	_moon_dir = dir
	moon_node = mi
	# its reflection: a soft broken column of light on the water under it (the mirror never sees the disc itself)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in 48:
		var z := 8.0 * pow(450.0 / 8.0, i / 47.0)
		var w := 0.6 + 0.07 * z
		st.set_uv(Vector2(0.0, i / 47.0))
		st.add_vertex(Vector3(-w, 0.0, z))
		st.set_uv(Vector2(1.0, i / 47.0))
		st.add_vertex(Vector3(w, 0.0, z))
	_shimmer = MeshInstance3D.new()
	_shimmer.name = "MoonShimmer"
	_shimmer.mesh = st.commit()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/anime/dance/moon_shimmer.gdshader")
	_shimmer.material_override = sm
	_shimmer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shimmer.layers = MOON_LAYER
	_shimmer.extra_cull_margin = 500.0
	add_child(_shimmer)


## Her light: a neutral moon key from the front-left and a warm lantern bounce from below the lens, on her alone, so
## her skin and dress keep their own colours.
func _light_her(who: WorldCharacter, cams: Array) -> void:
	for n in who.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers |= CHAR_LAYER
	var cam: Vector3 = cams[0]
	var to_cam := (cam - center)
	to_cam.y = 0.0
	to_cam = to_cam.normalized()
	var side := to_cam.cross(Vector3.UP).normalized()
	var key := DirectionalLight3D.new()
	key.name = "MoonKey"
	key.light_color = Color(1.0, 0.98, 0.96)
	key.light_energy = 0.5
	key.light_specular = 0.2
	key.shadow_enabled = false
	key.light_cull_mask = CHAR_LAYER
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(key)
	var from := center + (to_cam * 1.0 + side * 0.7 + Vector3.UP * 0.9).normalized() * 10.0
	key.look_at_from_position(from, center + Vector3.UP, Vector3.UP)
	var warm := OmniLight3D.new()
	warm.name = "LanternBounce"
	warm.light_color = Color(1.0, 0.72, 0.42)
	warm.light_energy = 0.45
	warm.omni_range = 3.2
	warm.omni_attenuation = 1.2
	warm.shadow_enabled = false
	warm.light_cull_mask = CHAR_LAYER
	add_child(warm)
	warm.global_position = center + to_cam * 1.1 - side * 0.6 + Vector3.UP * 0.35


## A second dancer in her own key light too.
func light_also(who: WorldCharacter) -> void:
	for n in who.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers |= CHAR_LAYER


func _lanterns(cams: Array) -> void:
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		var mt = g.material_override
		if mt is ShaderMaterial and (mt as ShaderMaterial).shader and String((mt as ShaderMaterial).shader.resource_path).ends_with("lantern.gdshader"):
			if not (mt in lantern_mats):
				lantern_mats.append(mt)
	for m in lantern_mats:
		(m as ShaderMaterial).set_shader_parameter("tint", GOLD_TINT)
		(m as ShaderMaterial).set_shader_parameter("hot", GOLD_HOT)
	# the floating lanterns: none in her circle or between the lens and her
	for mmi in lake.find_children("WaterLanterns*", "MultiMeshInstance3D", true, false):
		_water_mm = (mmi as MultiMeshInstance3D).multimesh
		var gx := (mmi as MultiMeshInstance3D).global_transform
		for i in _water_mm.instance_count:
			var t := _water_mm.get_instance_transform(i)
			var p := gx * t.origin
			var hide := Vector2(p.x - center.x, p.z - center.z).length() < clear_radius or randf() < 1.0 - 0.55 * lantern_keep
			for c in cams:
				var cp: Vector3 = c
				if _seg_dist(Vector2(p.x, p.z), Vector2(cp.x, cp.z), Vector2(center.x, center.z)) < 1.7 or Vector2(p.x - cp.x, p.z - cp.z).length() < 3.0:
					hide = true
			if hide:
				_water_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), t.origin + Vector3(0, -50, 0)))
			else:
				_water_base.append([i, t, randf_range(0.0, 1.4), randf_range(1.5, 5.0)])
		break
	for mmi in lake.find_children("SkyLanterns*", "MultiMeshInstance3D", true, false):
		var mm := (mmi as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			if randf() < 1.0 - 0.28 * lantern_keep:
				var t := mm.get_instance_transform(i)
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), t.origin + Vector3(0, -50, 0)))
	# lanterns hanging in the air round her: a few big ones at the sides, more further out behind her
	var lm = lake.get("lantern_mesh")
	if lm == null or not hover_lanterns:
		return
	var cam: Vector3 = cams[0]
	var back := center - cam
	back.y = 0.0
	back = back.normalized()
	var side := back.cross(Vector3.UP).normalized()
	var spots := [[-3.4, 3.5, 2.4, 0.62], [3.6, 4.5, 3.1, 0.66], [-4.2, 6.0, 3.9, 0.62], [4.6, 5.0, 1.6, 0.6], [-1.6, 7.5, 3.0, 0.55],
		[1.8, 8.5, 4.4, 0.55], [-6.5, 9.0, 2.2, 0.6], [6.8, 10.0, 3.4, 0.6], [0.4, 12.0, 5.6, 0.55], [-3.5, 14.0, 6.2, 0.6],
		[3.6, 15.0, 2.6, 0.6], [-8.5, 16.0, 4.8, 0.65], [9.0, 18.0, 5.4, 0.65], [-1.0, 20.0, 3.4, 0.6], [5.5, 22.0, 7.0, 0.7],
		[-6.0, 24.0, 8.0, 0.7]]
	for s in spots:
		var mi := MeshInstance3D.new()
		mi.mesh = lm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := lake.call("_lantern_material", 0) as ShaderMaterial
		sm.set_shader_parameter("tint", GOLD_TINT)
		sm.set_shader_parameter("hot", GOLD_HOT)
		sm.set_shader_parameter("energy", 1.45)
		lantern_mats.append(sm)
		mi.material_override = sm
		add_child(mi)
		var p := center + side * float(s[0]) + back * (float(s[1]) - 1.0) + Vector3(0, water_y + float(s[2]), 0)
		p.y = water_y + float(s[2])
		mi.global_position = p
		mi.scale = Vector3.ONE * float(s[3])
		mi.rotation.y = randf() * TAU
		_hover.append({"node": mi, "base": p, "seed": randf() * 10.0, "rise": randf_range(2.5, 5.0)})


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## The finale: every lantern lifts off and burns brighter.
func lift() -> void:
	if _lift_t >= 0.0:
		return                          # (both dancers call it: once)
	_lift_t = 0.0
	for m in lantern_mats:
		var sm := m as ShaderMaterial
		var e0 = sm.get_shader_parameter("energy")
		var base := 1.3 if e0 == null else float(e0)
		var tw := create_tween()
		tw.tween_method(func(v): sm.set_shader_parameter("energy", v), base, base * 2.1, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v): sm.set_shader_parameter("energy", v), base * 2.1, base * 1.55, 2.5)


## A short brightening of every lantern on a big move.
func flare(strength := 1.0) -> void:
	if _lift_t >= 0.0:
		return
	for m in lantern_mats:
		var sm := m as ShaderMaterial
		var base := float(sm.get_meta("base_energy", 1.3 if sm.get_shader_parameter("energy") == null else sm.get_shader_parameter("energy")))
		sm.set_meta("base_energy", base)
		var tw := create_tween()
		tw.tween_method(func(v): sm.set_shader_parameter("energy", v), base * (1.0 + 0.9 * strength), base, 1.5).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d()
	if _shimmer and cam:
		var flat := Vector3(_moon_dir.x, 0.0, _moon_dir.z).normalized()
		_shimmer.global_transform = Transform3D(Basis.looking_at(-flat, Vector3.UP), Vector3(cam.global_position.x, water_y + 0.006, cam.global_position.z))
	for h in _hover:
		var n: Node3D = h.node
		var up := 0.0
		if _lift_t >= 0.0:
			up = float(h.rise) * ease(clampf(_lift_t / 5.0, 0.0, 1.0), 0.6)
		n.global_position = (h.base as Vector3) + Vector3(0, 0.07 * sin(_t * 0.8 + float(h.seed)) + up, 0)
		n.rotation.y += delta * 0.08
	if _lift_t >= 0.0:
		_lift_t += delta
		if _water_mm:
			for w in _water_base:
				var k := clampf((_lift_t - float(w[2])) / 4.0, 0.0, 1.0)
				if k <= 0.0:
					continue
				var t: Transform3D = w[1]
				_water_mm.set_instance_transform(int(w[0]), Transform3D(t.basis, t.origin + Vector3(0, float(w[3]) * ease(k, 0.55), 0)))
