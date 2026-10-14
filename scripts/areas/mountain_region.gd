class_name MountainRegion
extends ForestRegion
## A CELESTIAL HIGHLANDS area on the realistic toolkit (world-quality gate): alpine ground from photoscans (sparse
## mountain grass, scree, cliff rock, snow by altitude), pines thinning to a treeline, meadows of flowers, boulders
## bedded in steep slopes, the photographic Alps sky - and the SEA OF CLOUDS below the cliffs (layered, sun-lit,
## drifting, soft against the rock). Subclasses shape the mountain (shape), say where the void is (cloud_y) and add
## their own structures (features / links), like any ForestRegion.

## a pure sky (no ground in it): above the clouds, nothing but sky meets the cloud sea at the horizon
const ALPS_SKY := "res://assets/polyhaven/hdris/kloppenheim_06_puresky/kloppenheim_06_puresky_2k.hdr"

var cloud_y := -70.0             # the cloud sea's height (world y)
var treeline := 45.0             # above this the pines stop
var snowline := 52.0             # snow lies above this (more on north-facing ground)
var _cloud_mats: Array = []


func env_preset() -> Dictionary:
	return {
		"sky_day": ALPS_SKY,
		"day": {"sun_rot": Vector3(-30, -140, 0), "sun_energy": 2.9, "sun_color": Color(1.0, 0.93, 0.82), "fog": 0.0014, "fog_color": Color(0.7, 0.77, 0.86),
			"fog_sky": 0.0, "vol_fog": 0.0, "ambient": 0.42, "exposure": 0.86, "bg_energy": 1.0, "saturation": 0.95, "contrast": 1.12},
		"night": {"fog": 0.0016, "fog_color": Color(0.05, 0.07, 0.12), "fog_sky": 0.0, "vol_fog": 0.0, "ambient": 1.2, "exposure": 1.4, "bg_energy": 1.0,
			"sun_energy": 0.45, "sun_color": Color(0.6, 0.7, 1.0), "sun_rot": Vector3(-50, 120, 0)},
		"vista": {"mountains": false, "ridge": false, "no_impostors": true},
	}


func _terrain() -> void:
	nav_aabb = AABB(Vector3(-HALF + 2, -40, -HALF + 2), Vector3(SIZE - 4, 160, SIZE - 4))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/real/real_terrain.gdshader")
	for pair in [["litter", "sparse_grass"], ["floor", "rocky_terrain_02"], ["path", "stony_dirt_path"], ["rock", "cliff_side"], ["bank", "snow_02"]]:
		m.set_shader_parameter(pair[0] + "_alb", RealKit.ph_tex(pair[1], "diff"))
		m.set_shader_parameter(pair[0] + "_nrm", RealKit.ph_tex(pair[1], "nor_gl"))
	m.set_shader_parameter("moss_alb", RealKit.ph_tex("leafy_grass", "diff"))
	m.set_shader_parameter("moss_nrm", RealKit.ph_tex("leafy_grass", "nor_gl"))
	m.set_shader_parameter("noise_tex", Kit.noise())
	m.set_shader_parameter("tile", 0.22)
	mats.terrain = m
	Kit.terrain(self, SIZE, STEP, height, _terrain_mask, m)


## Masks: R = trail, G = "forest" (here: lush meadow vs bare scree), B = snow.
func _terrain_mask(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var ix := clampi(int(round((x + HALF) / STEP)), 0, _n - 1)
	var iz := clampi(int(round((z + HALF) / STEP)), 0, _n - 1)
	var tr := _trail_mask[iz * _n + ix]
	var h := height(x, z)
	var north := clampf((height(x, z + 2.0) - height(x, z - 2.0)) * 0.25, -1.0, 1.0)   # ground facing north keeps snow
	var snow := smoothstep(snowline - 6.0, snowline + 8.0, h + north * 6.0)
	var lush := clampf(_forest_density(p) * (1.0 - smoothstep(treeline - 5.0, snowline, h)), 0.0, 1.0)
	return Color(tr, lush, snow * (1.0 - tr), 0.0)


func density(p: Vector2, f: float) -> float:
	var h := height(p.x, p.y)
	return f * (1.0 - smoothstep(treeline - 12.0, treeline, h)) * 0.75


func site_zone(p: Vector2) -> String:
	for c in clearings:
		if p.distance_to(c[0]) < float(c[1]) + 6.0:
			return String(c[2])
	return "frontier"            # mountain pines (and the odd weathered snag) wherever trees stand


func build_steps() -> Array:
	var steps: Array = super.build_steps()
	steps.insert(3, _cloud_sea)
	steps.erase(dress.understory)          # the forest's broadleaf saplings do not grow up here
	return steps


## The sea of clouds: three drifting layers far below, wider than the eye can see.
func _cloud_sea() -> void:
	var sd := Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(-140), 0)) * Vector3(0, 0, -1)
	for i in 3:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(6000, 6000)
		mi.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/nature/cloud_sea.gdshader")
		m.set_shader_parameter("noise_tex", Kit.noise())
		m.set_shader_parameter("layer", float(i) / 2.0)
		m.set_shader_parameter("scale", 0.0007 + i * 0.00025)
		m.set_shader_parameter("drift", 0.0035 + i * 0.0015)
		m.set_shader_parameter("sun_dir", -sd)
		m.set_shader_parameter("coverage", 0.36 + i * 0.07)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, cloud_y + i * 3.5, 0)
		mi.name = "CloudSea_%d" % i
		add_child(mi)
		_cloud_mats.append(m)


func set_time_of_day(h: float) -> void:
	super.set_time_of_day(h)
	if env:
		# the mountain air: cooler, bluer haze than the forest's
		env.fog_light_color = env.fog_light_color.lerp(Color(0.66, 0.74, 0.86), 0.6) if not night else env.fog_light_color
		env.ambient_light_color = Color(0.62, 0.68, 0.78) if not night else Color(0.2, 0.26, 0.42)
	var night_now := h < 5.1 or h > 20.0
	var dusk := clampf(1.0 - absf(h - 19.0) / 1.6, 0.0, 1.0) + clampf(1.0 - absf(h - 6.0) / 1.4, 0.0, 1.0)
	for m in _cloud_mats:
		var top := Color(1.0, 0.99, 0.97).lerp(Color(1.0, 0.7, 0.5), clampf(dusk, 0.0, 1.0))
		if night_now:
			top = Color(0.32, 0.38, 0.55)
		(m as ShaderMaterial).set_shader_parameter("top_color", top)
		(m as ShaderMaterial).set_shader_parameter("shade_color", Color(0.12, 0.15, 0.25) if night_now else Color(0.82, 0.86, 0.93).lerp(Color(0.72, 0.58, 0.62), clampf(dusk, 0.0, 1.0)))
		(m as ShaderMaterial).set_shader_parameter("haze_color", Color(0.1, 0.12, 0.2) if night_now else Color(0.78, 0.84, 0.92))


## Big rock outcrops (photoscanned rock faces) set into steep ground and along cliff edges.
func outcrops(spots: Array) -> void:
	var ids := ["rock_face_01", "rock_face_02"]
	for i in spots.size():
		var sp: Array = spots[i]
		var p: Vector2 = sp[0]
		var s := float(sp[1])
		Kit.place_prop(self, ids[i % 2], Kit.xf(Vector3(p.x, height(p.x, p.y) - 0.6 * s, p.y), float(sp[2]) if sp.size() > 2 else rng.randf() * TAU, Vector3.ONE * s), "", true)
