class_name WhisperingWoods
extends KitArea
## Whispering Woods (Milestone K) — the Arcane Sanctuary's wild hinterland, entered through the Sanctuary's north
## arch. An ORIGINAL environment art-directed from the developer's ten reference images (docs/WHISPERING_WOODS.md):
##   S  entry trail from the Sanctuary            -> the ENCHANTED FOREST: a winding trail through layered,
##                                                   dense vegetation, giant leafy plants, light shafts
##   C  the CROSSROADS                             -> west: a narrow path to the HIDDEN LOTUS POND (willows,
##                                                   lilies, a little spring fall, fireflies after dark)
##                                                 -> east: down to the river, the OLD BRIDGE (an arched stone
##                                                   bridge; a bank path goes down to the water and under it)
##                                                 -> north: the FORKED STAIRWAY up the escarpment: right flight to
##                                                   the FORGOTTEN RUINS plateau (gate arch, collapsed walls, an
##                                                   inscription about far-off crystals, a VIEWPOINT over the falls),
##                                                   left flight to a hidden ALCOVE, and an overgrown shortcut
##                                                   back down to the pond
##   E  across the bridge: MONSTER TERRITORY (darker, dead trees, tracks) and the MONSTER DEN (a cave behind an
##      overgrown stone facade) — creatures live HERE, not beside the Sanctuary
##   NW from the ruins: the FRONTIER ROAD climbs a rocky ridge (+24 m) toward the highlands
##   The WATERFALL: the upper river leaves the high terrace over the escarpment into a misty pool.
## Heights are precomputed into a grid once (fast queries for terrain, scatter, navigation and ground_at).

const SIZE := 280.0
const STEP := 1.0
const HALF := SIZE * 0.5

# --- landmarks (local metres; -Z is north) ---------------------------------------------------------------------
const ENTRY := Vector2(0, 128)
const CROSS := Vector2(2, 38)
const POND := Vector2(-74, 46)
const POND_R := 15.0
const STAIR_BASE := Vector2(0, 2)
const STAIR_LANDING := Vector2(0, -9)
const ALCOVE := Vector2(-20, -21)
const PLATEAU := Vector2(0, -50)
const PLATEAU_H := 9.0
const RUIN_GATE := Vector2(0, -33)
const INSCRIPTION := Vector2(-2, -50)
const VIEWPOINT := Vector2(40, -34)
const FALLS := Vector2(55.5, -41)          # the lip, where the river leaves the terrace
const BRIDGE := Vector2(60, -21)          # deck centre; the river (x≈59.8) flows south under it
const BRIDGE_W := 50.0                      # west abutment x
const BRIDGE_E := 70.0
const DEN := Vector2(116, -30)
const DEN_MOUTH := Vector2(115, -29.5)       # the cave mouth, at the foot of the den hill, facing the trail
const DEN_FACE := Vector2(-0.743, 0.669)
const DEN_HILL := Vector2(132, -44)
const FRONTIER_END := Vector2(-96, -126)

## Trails: [points, width, kind]. kind: main | narrow | hidden (barely a path: worn grass)
var trails := [
	[[Vector2(0, 139), Vector2(0, 128), Vector2(-7, 108), Vector2(3, 88), Vector2(-9, 66), Vector2(-2, 50), CROSS], 3.4, "main"],
	[[CROSS, Vector2(-16, 44), Vector2(-34, 52), Vector2(-48, 52), Vector2(-56, 51)], 1.6, "narrow"],
	[[CROSS, Vector2(20, 30), Vector2(32, 14), Vector2(40, -2), Vector2(44, -13), Vector2(BRIDGE_W - 7.0, BRIDGE.y)], 2.8, "main"],
	[[Vector2(BRIDGE_E + 6.0, BRIDGE.y), Vector2(84, -20), Vector2(98, -23), Vector2(110, -25), DEN_MOUTH + DEN_FACE * 1.5], 2.4, "main"],
	[[CROSS, Vector2(1, 22), STAIR_BASE + Vector2(0, 6)], 3.0, "main"],
	[[Vector2(47, -6), Vector2(51.4, -14), Vector2(51.6, BRIDGE.y), Vector2(51.0, -26.5)], 1.2, "narrow"],   # the bank path under the bridge
	[[Vector2(0, -28.5), RUIN_GATE, Vector2(2, -40), INSCRIPTION + Vector2(0, 4)], 2.6, "main"],
	[[Vector2(4, -40), Vector2(16, -42.5), Vector2(28, -40), VIEWPOINT + Vector2(-3, -1)], 1.8, "narrow"],
	[[Vector2(-6, -52), Vector2(-24, -62), Vector2(-42, -76), Vector2(-60, -92), Vector2(-78, -108), FRONTIER_END], 2.4, "main"],
	[[STAIR_LANDING + Vector2(-2.5, 0), ALCOVE + Vector2(3, 2), ALCOVE], 1.8, "narrow"],
	[[ALCOVE + Vector2(-3, 3), Vector2(-34, -6), Vector2(-48, 10), Vector2(-58, 24), Vector2(-64, 29.5)], 1.0, "hidden"],
	[[Vector2(-30, 4), Vector2(-60, -2), Vector2(-100, -4), Vector2(-139, -6)], 2.0, "narrow"],
]

var _hgrid := PackedFloat32Array()
var _n := 0
var _trail_mask := PackedFloat32Array()     # 0..1 trail strength per grid cell
var _hidden_mask := PackedFloat32Array()
var mats := {}
var dress: WoodsDressing
var marks: WoodsLandmarks


static func resources() -> Array:
	return textures(["forrest_ground_01", "rock_wall_10", "castle_wall_slates"]) + textures(["leafy_grass", "mossy_rock"], "2k")


func env_preset() -> Dictionary:
	return {
		"day": {"sun_rot": Vector3(-42, 155, 0), "sun_energy": 1.9, "sun_color": Color(1.0, 0.93, 0.8), "fog": 0.0055, "fog_color": Color(0.66, 0.80, 0.82),
			"fog_sky": 0.0, "vol_fog": 0.008, "vol_albedo": Color(0.92, 0.96, 0.9), "ambient": 0.75, "exposure": 1.0, "bg_energy": 1.0, "saturation": 1.1},
		"night": {"fog": 0.008, "fog_color": Color(0.04, 0.08, 0.12), "fog_sky": 0.0, "vol_fog": 0.014, "ambient": 1.3, "exposure": 1.35, "bg_energy": 1.0},
		"vista": {"mountains": false, "ridge_height": 300.0, "ridge_seed": 19, "green": Color(0.30, 0.46, 0.40), "haze": Color(0.70, 0.84, 0.92), "max_haze": 0.72, "snow_line": 330.0},
	}


# ------------------------------------------------------------------ geography
## River centreline x for a given z (flows from the north terrace, over the falls, south out of the map).
static func river_x(z: float) -> float:
	return 63.0 + 6.0 * sin(z * 0.024) + 3.0 * sin(z * 0.067 + 1.3)


func _raw_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	# gentle rolling ground
	var roll := 1.1 * sin(x * 0.043) * cos(z * 0.037) + 0.55 * sin(x * 0.11 + 1.3) * sin(z * 0.093 + 0.4) + 0.25 * sin((x - z) * 0.21)
	# the river runs level (no rolling ground near it), so its water surfaces sit right in the bed
	roll *= smoothstep(5.0, 16.0, absf(x - river_x(z)))
	var h := roll
	# the northern escarpment: everything north of ~z=-26 is the high ground (+9), cut in the west by the ridge
	var esc_z := -24.0 + 3.0 * sin(x * 0.05) - smoothstep(20.0, 60.0, x) * 16.0
	# at the falls the face steepens into a real drop (the water leaps it into the plunge pool)
	var fk := 1.0 - smoothstep(9.0, 18.0, p.distance_to(FALLS + Vector2(0, 2)))
	var high := smoothstep(esc_z + lerpf(3.0, 0.6, fk), esc_z - lerpf(4.5, 1.4, fk), z)
	h += high * PLATEAU_H
	# the forked stairway's ramp up the escarpment face (walkable under the steps)
	var sx := x - STAIR_BASE.x
	var ramp := (1.0 - smoothstep(3.2, 6.0, absf(sx))) * smoothstep(STAIR_BASE.y + 2.0, STAIR_BASE.y - 2.0, z) * (1.0 - high)
	h += ramp * clampf((STAIR_BASE.y - z) / (STAIR_BASE.y - (esc_z - 4.5)), 0.0, 1.0) * PLATEAU_H
	# alcove ledge (+6) west of the stairs, reached from the landing by a gently rising shelf. Absolute target
	# heights (blended, not added) so the shelf meets the stair ramp exactly where it leaves it.
	var la := STAIR_LANDING + Vector2(-2, 0)
	var lb := ALCOVE + Vector2(3, 2)
	var lt := clampf((p - la).dot(lb - la) / (lb - la).length_squared(), 0.0, 1.0)
	var land_h := (STAIR_BASE.y - la.y) / (STAIR_BASE.y - (-24.0 + 3.0 * sin(la.x * 0.05) - 4.5)) * PLATEAU_H
	var shelf := (1.0 - smoothstep(1.8, 3.4, _seg_dist(p, la, lb)))
	var disc := 1.0 - smoothstep(5.5, 8.5, p.distance_to(ALCOVE))
	var k := maxf(shelf, disc) * (1.0 - high)
	var tgt := lerpf(land_h, 6.0, smoothstep(0.0, 1.0, lt)) if disc < 0.99 else 6.0
	tgt = lerpf(tgt, 6.0, disc)
	h = lerpf(h, roll + tgt, k) if roll + tgt > h else h
	# frontier ridge: climbs from the plateau toward the north-west corner
	var ridge_t := clampf(((p - Vector2(-6, -52)).dot((FRONTIER_END - Vector2(-6, -52)).normalized())) / (FRONTIER_END - Vector2(-6, -52)).length(), 0.0, 1.0)
	var ridge_d := _seg_dist(p, Vector2(-6, -52), FRONTIER_END + Vector2(-10, -10))
	h += (1.0 - smoothstep(9.0, 22.0, ridge_d)) * ridge_t * 15.0
	# a ravine west of the ridge
	h -= (1.0 - smoothstep(4.0, 14.0, _seg_dist(p, Vector2(-70, -40), Vector2(-120, -100)))) * 7.0 * smoothstep(-20.0, -50.0, z)
	# the river channel and the falls
	var rx := river_x(z)
	var dr := absf(x - rx)
	var bed := 1.0 - smoothstep(4.0, 10.0, dr)
	h -= bed * 2.4
	var pool := 1.0 - smoothstep(7.0, 13.0, p.distance_to(pool_center()))
	h -= pool * 1.8 * (1.0 - high)
	# the hidden pond basin and the little ledge its spring falls from
	var dp := p.distance_to(POND)
	h -= (1.0 - smoothstep(POND_R - 2.0, POND_R + 6.0, dp)) * 2.6
	h += (1.0 - smoothstep(6.0, 11.0, p.distance_to(POND + Vector2(-2, -19)))) * 5.0
	# the monster den hill (its cave is hollowed out at the very end)
	h += (1.0 - smoothstep(10.0, 26.0, p.distance_to(DEN_HILL))) * 11.0
	# enclosure: hills toward the edges (except the routes)
	var edge := maxf(absf(x), absf(z))
	h += smoothstep(118.0, 138.0, edge) * 14.0 * (1.0 - _gap_near_routes(p))
	# the den cave is hollowed out LAST (nothing may raise its floor afterwards)
	var cave_c := DEN_MOUTH - DEN_FACE * 5.0
	var ck := maxf(1.0 - smoothstep(6.0, 7.2, p.distance_to(cave_c)), 1.0 - smoothstep(2.0, 3.2, _seg_dist(p, DEN_MOUTH + DEN_FACE * 2.0, cave_c)))
	if ck > 0.0:
		var floor_h := (1.0 - smoothstep(10.0, 26.0, DEN_MOUTH.distance_to(DEN_HILL))) * 11.0 + roll
		h = lerpf(h, minf(h, floor_h), ck)   # only ever cut down (outside the mouth the natural slope stays)
	return h


## Exits through the enclosing hills: south (Sanctuary), west (old forest track), north-west (frontier).
func _gap_near_routes(p: Vector2) -> float:
	# corridors through the enclosing hills along each exit trail (not just a hole at the very edge)
	var g := 1.0 - smoothstep(7.0, 15.0, _seg_dist(p, Vector2(0, 150), Vector2(0, 105)))
	g = maxf(g, 1.0 - smoothstep(6.0, 14.0, _seg_dist(p, Vector2(-150, -6), Vector2(-100, -4))))
	g = maxf(g, 1.0 - smoothstep(8.0, 18.0, _seg_dist(p, FRONTIER_END + Vector2(-20, -20), FRONTIER_END + Vector2(14, 14))))
	return g


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Height from the precomputed grid (bilinear).
func height(x: float, z: float) -> float:
	if _hgrid.is_empty():
		return _raw_height(x, z)
	var fx := clampf((x + HALF) / STEP, 0.0, _n - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, _n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := _hgrid[iz * _n + ix]
	var b := _hgrid[iz * _n + ix + 1]
	var c := _hgrid[(iz + 1) * _n + ix]
	var d := _hgrid[(iz + 1) * _n + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## Water levels: the terrace river (constant, so the lip is level) and the plunge pool.
func upper_water_y() -> float:
	return height(river_x(FALLS.y - 6.0), FALLS.y - 6.0) + 1.2


func pool_water_y() -> float:
	return height(river_x(FALLS.y + 22.0), FALLS.y + 22.0) + 1.25   # same level as the river it feeds


static func pool_center() -> Vector2:
	return Vector2(river_x(FALLS.y + 8.0), FALLS.y + 8.0)


func ground_at(x: float, z: float) -> float:
	return height(x, z)


func trail_at(x: float, z: float) -> float:
	var ix := clampi(int(round((x + HALF) / STEP)), 0, _n - 1)
	var iz := clampi(int(round((z + HALF) / STEP)), 0, _n - 1)
	return _trail_mask[iz * _n + ix] if not _trail_mask.is_empty() else 0.0


func _precompute() -> void:
	_n = int(SIZE / STEP) + 1
	_hgrid.resize(_n * _n)
	for iz in _n:
		for ix in _n:
			_hgrid[iz * _n + ix] = _raw_height(-HALF + ix * STEP, -HALF + iz * STEP)
	# trails: rasterise each segment into the cells it touches (min distance -> soft strength)
	_trail_mask.resize(_n * _n)
	_trail_mask.fill(0.0)
	_hidden_mask.resize(_n * _n)
	_hidden_mask.fill(0.0)
	for t in trails:
		var pts: Array = t[0]
		var w: float = t[1]
		var hidden: bool = t[2] == "hidden"
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (w + 2.0)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (w + 2.0)
			for iz in range(maxi(0, int((lo.y + HALF) / STEP)), mini(_n, int((hi.y + HALF) / STEP) + 1)):
				for ix in range(maxi(0, int((lo.x + HALF) / STEP)), mini(_n, int((hi.x + HALF) / STEP) + 1)):
					var p := Vector2(-HALF + ix * STEP, -HALF + iz * STEP)
					var d := _seg_dist(p, a, b)
					var s := 1.0 - smoothstep(w * 0.35, w * 0.5 + 0.9, d)
					var k := iz * _n + ix
					if hidden:
						_hidden_mask[k] = maxf(_hidden_mask[k], s)
					else:
						_trail_mask[k] = maxf(_trail_mask[k], s)
	# trails smooth the ground they cross a little (worn, level footing)
	var sm := _hgrid.duplicate()
	for iz in range(1, _n - 1):
		for ix in range(1, _n - 1):
			var k := iz * _n + ix
			var s := _trail_mask[k]
			if s > 0.01:
				var avg := (_hgrid[k - 1] + _hgrid[k + 1] + _hgrid[k - _n] + _hgrid[k + _n] + _hgrid[k] * 4.0) / 8.0
				sm[k] = lerpf(_hgrid[k], avg, s)
	_hgrid = sm


func build_steps() -> Array:
	dress = WoodsDressing.new(self)
	marks = WoodsLandmarks.new(self)
	return [_precompute, _painted_sky, _terrain, _water, dress.compute_trail_distance, dress.trees, dress.undergrowth,
		dress.grass, dress.rocks, dress.cliffs, dress.atmosphere, marks.build, _links]


## The photographic panoramas clash with the painted forest: a procedural stylized sky instead (day + night).
func _painted_sky() -> void:
	var shader: Shader = load("res://shaders/nature/stylized_sky.gdshader")
	for v in [false, true]:
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("night", 1.0 if v else 0.0)
		var s := Sky.new()
		s.sky_material = sm
		s.radiance_size = Sky.RADIANCE_SIZE_128
		s.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		if v:
			_sky_night = s
		else:
			_sky_day = s
	env.fog_aerial_perspective = 0.55   # distant forest takes the sky's colour: painterly depth


## Painterly shadows: part of the ambient comes from a warm green-grey (light bounced off the forest), not only
## the blue sky, so shade reads green-teal instead of cold blue.
func set_night(v: bool) -> void:
	super.set_night(v)
	if env == null:
		return
	env.ambient_light_sky_contribution = 0.5
	env.ambient_light_color = Color(0.13, 0.2, 0.3) if v else Color(0.6, 0.66, 0.52)
	NatureKit.set_night_glow(v)
	if marks:
		marks.set_night(v)


func _terrain() -> void:
	nav_aabb = AABB(Vector3(-HALF + 2, -8, -HALF + 2), Vector3(SIZE - 4, 50, SIZE - 4))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/nature/terrain_stylized.gdshader")
	m.set_shader_parameter("grass_detail", load(Kit.tex_set("leafy_grass", "2k")[0]))
	m.set_shader_parameter("dirt_detail", load(Kit.tex_set("forrest_ground_01", "1k")[0]))
	m.set_shader_parameter("rock_detail", load(Kit.tex_set("rock_wall_10", "1k")[0]))
	m.set_shader_parameter("noise_tex", Kit.noise())
	mats.terrain = m
	Kit.terrain(self, SIZE, STEP, height, _terrain_mask, m)


func _terrain_mask(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var ix := clampi(int(round((x + HALF) / STEP)), 0, _n - 1)
	var iz := clampi(int(round((z + HALF) / STEP)), 0, _n - 1)
	var tr := _trail_mask[iz * _n + ix]
	var hid := _hidden_mask[iz * _n + ix] * 0.45
	var forest := _forest_density(p)
	var bank := (1.0 - smoothstep(5.0, 9.0, absf(x - river_x(z)))) + (1.0 - smoothstep(POND_R - 1.0, POND_R + 3.0, p.distance_to(POND)))
	return Color(maxf(tr, hid), forest * 0.85, clampf(bank, 0.0, 1.0), 0.0)


## How wooded a spot is (0 open meadow .. 1 deep forest). Drives the forest floor colour and the scatter.
func _forest_density(p: Vector2) -> float:
	var f := 0.55 + 0.25 * sin(p.x * 0.031 + 0.7) * cos(p.y * 0.027)
	f += 0.35 * (1.0 - smoothstep(30.0, 60.0, absf(p.x - 0.0))) * smoothstep(110.0, 70.0, p.y) * smoothstep(30.0, 50.0, p.y)  # the enchanted forest band
	f -= 0.6 * (1.0 - smoothstep(10.0, 22.0, p.distance_to(ENTRY + Vector2(0, -6))))   # open glade at the entry
	f -= 0.5 * (1.0 - smoothstep(8.0, 16.0, p.distance_to(CROSS)))
	f -= 0.7 * (1.0 - smoothstep(22.0, 34.0, p.distance_to(PLATEAU)))                  # the ruins plateau is open
	f += 0.25 * smoothstep(80.0, 100.0, p.x)                                           # monster territory: dense
	return clampf(f, 0.0, 1.0)


func _water() -> void:
	var wm := Kit.shader_mat("res://shaders/nature/stylized_water.gdshader", {"noise_tex": Kit.noise(), "flow": Vector2(0.0, 0.06),
		"depth_scale": 1.4, "ripple": 0.16, "sky_tint": Color(0.55, 0.72, 0.74)})
	mats.water = wm
	# the river below the falls: segments following the bed, from the plunge pool south
	var z := FALLS.y + 12.0
	while z < HALF:
		var seg := 6.0
		var x0 := river_x(z + seg * 0.5)
		var w := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(15.0, seg + 0.6)
		w.mesh = pm
		w.material_override = wm
		w.position = Vector3(x0, height(x0, z + seg * 0.5) + 1.25, z + seg * 0.5)
		w.rotation.y = -atan((river_x(z + seg) - river_x(z)) / seg)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
		z += seg
	# the upper river on the terrace, up to the lip
	z = -HALF
	while z < FALLS.y - 0.5:
		var seg2 := minf(6.0, FALLS.y - 0.5 - z)
		var x1 := river_x(z + seg2 * 0.5)
		var w2 := MeshInstance3D.new()
		var pm2 := PlaneMesh.new()
		pm2.size = Vector2(15.0, seg2 + 0.6)
		w2.mesh = pm2
		w2.material_override = wm
		w2.position = Vector3(x1, upper_water_y(), z + seg2 * 0.5)
		w2.rotation.y = -atan((river_x(z + seg2) - river_x(z)) / maxf(seg2, 0.1))
		w2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w2)
		z += seg2
	# the plunge pool
	var pool := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 10.0
	pc.bottom_radius = 10.0
	pc.height = 0.02
	pc.radial_segments = 48
	pool.mesh = pc
	pool.material_override = wm
	pool.position = Vector3(pool_center().x, pool_water_y(), pool_center().y)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	_water_obstacles()
	# the pond
	var pond := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = POND_R + 2.5
	cm.bottom_radius = POND_R + 2.5
	cm.height = 0.02
	cm.radial_segments = 64
	pond.mesh = cm
	pond.material_override = Kit.shader_mat("res://shaders/nature/stylized_water.gdshader", {"noise_tex": Kit.noise(), "flow": Vector2(0.004, 0.002),
		"shallow": Color(0.42, 0.8, 0.74), "deep": Color(0.02, 0.16, 0.2), "depth_scale": 2.0, "ripple": 0.025, "spec": 0.25, "sky_tint": Color(0.24, 0.40, 0.32), "glow_color": Color(0.35, 0.75, 0.9)})
	mats.pond = pond.material_override
	pond.position = Vector3(POND.x, height(POND.x, POND.y) + 1.55, POND.y)
	pond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pond)


## Water is not walkable: carve the river, the plunge pool and the pond out of the navmesh (the bake discards
## source geometry inside these shapes, below the water surface only — the bridge deck above is unaffected).
func _water_obstacles() -> void:
	var half_w := 6.6
	var z := -HALF
	while z < HALF:
		var z1 := minf(z + 6.0, HALF)
		var lip := z < FALLS.y + 1.0 and z1 > FALLS.y - 1.0
		var y_top := upper_water_y() if z1 <= FALLS.y + 1.0 else pool_water_y()
		var x0 := river_x(z)
		var x1 := river_x(z1)
		_nav_hole([Vector2(x0 - half_w, z), Vector2(x0 + half_w, z), Vector2(x1 + half_w, z1), Vector2(x1 - half_w, z1)], y_top - 8.0, 8.3 if not lip else 18.0)
		z = z1
	var pc := pool_center()
	var ring: Array[Vector2] = []
	for i in 16:
		ring.append(pc + Vector2.from_angle(TAU * i / 16.0) * 9.5)
	_nav_hole(ring, pool_water_y() - 6.0, 6.3)
	var pr: Array[Vector2] = []
	for i in 20:
		pr.append(POND + Vector2.from_angle(TAU * i / 20.0) * (POND_R + 2.0))
	_nav_hole(pr, height(POND.x, POND.y) - 2.0, 3.4)


func _nav_hole(pts: Array, y: float, h: float) -> void:
	var ob := NavigationObstacle3D.new()
	ob.avoidance_enabled = false
	ob.affect_navigation_mesh = true
	ob.position = Vector3(0, y, 0)
	ob.height = h
	var v := PackedVector3Array()
	for p in pts:
		v.append(Vector3(p.x, 0, p.y))
	ob.vertices = v
	add_child(ob)


func _links() -> void:
	print("[woods] dressing ", dress.stats, " landmarks ", marks.stats)
	add_location("whispering_woods", Vector3(-4, 0, 80), 50.0, Vector3(-4, height(-4, 80), 80), "a winding trail through the Whispering Woods")
	add_gate("sanctuary", Vector3(0, height(0, 136), 136), Vector3(0, height(0, 128) + 0.05, 128), 0.0, 3.0)
	add_gate("ancient_grove", Vector3(-136, height(-136, -6), -6), Vector3(-126, height(-126, -6) + 0.05, -6), -PI * 0.5, 3.0)
	add_gate("highland_path", Vector3(FRONTIER_END.x - 4, height(FRONTIER_END.x - 4, FRONTIER_END.y - 4), FRONTIER_END.y - 4),
		Vector3(FRONTIER_END.x + 4, height(FRONTIER_END.x + 4, FRONTIER_END.y + 4) + 0.05, FRONTIER_END.y + 4), PI * 0.75, 3.0)
	boundary_box(Vector3(0, 0, 0), Vector3(SIZE - 6, 40, SIZE - 6))
