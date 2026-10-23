extends CaveArea
## D1 Crystal Entrance + D2 Luminous Crystal Hall (Crystal Caverns) - rebuilt as a real cave (world-quality gate).
##   W  the QUARRY RAVINE: the road from the village runs between sheer rock walls (old quarry cuts, scree,
##      the miners' camp with crates and lanterns) to the CAVE MOUTH in the cliff
##   the mouth tunnel opens into the LUMINOUS CRYSTAL HALL: a domed chamber 30 m across and 18 m high, its floor
##      dipping to a still pool, crystal formations in cyan, violet and sea-green growing from the floor, the walls
##      and the roof - and the GIANT CRYSTAL, a violet spire taller than a house
##   E  a descending tunnel to the Deep Caverns

const MOUTH := Vector2(-22, 0)
const HALL := Vector2(26, -4)
const HALL_R := Vector2(30, 24)
const POOL := Vector2(32, -8)
const GIANT := Vector2(38, -20)
const TUNNEL_END := Vector2(86, 12)
const GATE_VILLAGE := Vector2(-86, 2)


func _init() -> void:
	trails = [
		[[GATE_VILLAGE, Vector2(-60, -2), Vector2(-40, 2), MOUTH, Vector2(0, 0), Vector2(14, -2), HALL + Vector2(-6, 6)], 2.6],
		[[HALL + Vector2(-6, 6), Vector2(40, 8), Vector2(56, 8), Vector2(72, 10), TUNNEL_END], 2.0],
	]


func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	return WhisperingWoods._seg_dist(p, a, b)


## Signed distance to the cave volume (negative inside): mouth tunnel, hall, east tunnel.
func cave_sdf(p: Vector2) -> float:
	var mouth := _seg_d(p, MOUTH + Vector2(-2, 0), Vector2(4, 0)) - 6.5
	var e := Vector2((p.x - HALL.x) / HALL_R.x, (p.y - HALL.y) / HALL_R.y)
	var hall := (e.length() - 1.0) * minf(HALL_R.x, HALL_R.y)
	hall += 2.0 * sin(atan2(e.y, e.x) * 5.0 + 0.7) + 1.2 * sin(atan2(e.y, e.x) * 11.0)
	var east := minf(_seg_d(p, Vector2(50, 6), Vector2(70, 10)), _seg_d(p, Vector2(70, 10), TUNNEL_END + Vector2(4, 0))) - 4.8
	return minf(minf(mouth, hall), east)


## The cliff face the cave is cut into: west of it is the open quarry ravine (sky overhead), east of it the rock.
## The mouth tunnel used to reach ~10 m out past it: its roof floated over the ravine as a thin sheet and curved
## down to the ground at the far end, sealing the cave from the ravine (the village road could not get in).
const FACE_X := MOUTH.x + 2.0


func ceiling_open(x: float, _z: float) -> bool:
	return x < FACE_X - 0.01


func _ravine_w(z: float, x: float) -> float:
	return 9.0 + 2.5 * sin(x * 0.07) + 1.5 * sin(x * 0.19 + z)


func floor_h(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var bumps := 0.35 * sin(x * 0.31) * cos(z * 0.27) + 0.2 * sin((x + z) * 0.61)
	var sd := cave_sdf(p)
	if sd < 0.0 and x >= FACE_X:
		var f := -0.05 * maxf(x - MOUTH.x, 0.0) + bumps
		var he := Vector2((p.x - HALL.x) / HALL_R.x, (p.y - HALL.y) / HALL_R.y).length()
		f -= 2.0 * (1.0 - smoothstep(0.0, 0.9, he))                             # the hall's floor dips to the middle
		f -= 1.6 * (1.0 - smoothstep(3.0, 8.0, p.distance_to(POOL)))            # the still pool
		f -= smoothstep(56.0, 86.0, x) * 4.0 * (1.0 - smoothstep(-1.0, 0.0, sd)) # the tunnel descends east
		return f
	if x < MOUTH.x + 2.0:
		# the quarry ravine: a level floor between sheer walls
		var w := _ravine_w(z, x)
		var wall := smoothstep(w, w + 5.0, absf(z)) * (26.0 + 3.0 * sin(x * 0.11 + z * 0.05))
		var cut := smoothstep(w + 8.0, w + 18.0, absf(z)) * 4.0                  # old quarry benches above
		return bumps * 0.6 + wall + cut
	# solid rock around the cave
	return 28.0 + 2.0 * sin(x * 0.07) * cos(z * 0.05)


func ceil_h(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var sd := cave_sdf(p)
	if sd >= 0.0 or x < FACE_X:
		return floor_h(x, z)
	var he := Vector2((p.x - HALL.x) / HALL_R.x, (p.y - HALL.y) / HALL_R.y).length()
	var room := lerpf(6.0, 18.0, 1.0 - smoothstep(0.6, 1.25, he))
	var profile := sqrt(clampf(-sd / 6.0, 0.0, 1.0))
	var drips := 0.8 * sin(x * 0.43) * cos(z * 0.37) + 0.5 * sin((x - z) * 0.9)
	var f := floor_h(x, z)
	return f + maxf(0.0, room * profile + drips * profile)


func occlusion(x: float, z: float) -> float:
	var sd := cave_sdf(Vector2(x, z))
	if sd >= 0.0:
		return 0.0
	# light from the mouth reaches a few metres in
	return clampf((x - MOUTH.x) / 14.0, 0.0, 1.0)


func water_dist(p: Vector2) -> float:
	return p.distance_to(POOL) - 5.0


func env_preset() -> Dictionary:
	return {"sky_day": "res://assets/polyhaven/hdris/kloppenheim_06_puresky/kloppenheim_06_puresky_2k.hdr",
		"day": {"sun_rot": Vector3(-40, 150, 0), "sun_energy": 2.6, "sun_color": Color(1.0, 0.93, 0.82), "ambient": 0.5, "fog": 0.004, "fog_color": Color(0.55, 0.62, 0.7),
			"vol_fog": 0.022, "vol_albedo": Color(0.75, 0.88, 1.0), "exposure": 0.95, "bg_energy": 0.9, "contrast": 1.12},
		"night": {"ambient": 0.6, "fog": 0.006, "fog_color": Color(0.03, 0.05, 0.08), "vol_fog": 0.024, "exposure": 1.3},
		"vista": {"mountains": false, "ridge": false, "no_impostors": true},
		"shadow_distance": 110.0, "shadow_fade_start": 0.55}


func features() -> Array:
	return [_mouth_face, _hall_crystals, _giant, _pool, _miners_camp, _scree]


## The rock above the mouth: from the roof's open edge up to the cliff top, across the opening (the roof is seen
## only from below, so without this the mouth would be a slot open to the sky).
func _mouth_face() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := FACE_X
	var prev := []
	var z := -9.0
	while z <= 9.0:
		var bottom := roof(x, z)
		var top := 28.0 + 2.0 * sin(x * 0.07) * cos(z * 0.05) + 0.5
		var cur := [Vector3(x, minf(bottom, top), z), Vector3(x, top, z)]
		if not prev.is_empty() and (top - bottom > 0.05 or (prev[1] as Vector3).y - (prev[0] as Vector3).y > 0.05):
			# both windings: the face is seen from the ravine (and its back from inside the rock never shows)
			for v in [prev[0], cur[0], prev[1], prev[1], cur[0], cur[1], prev[0], prev[1], cur[0], prev[1], cur[1], cur[0]]:
				st.set_normal(Vector3(-1, 0, 0))
				st.set_uv(Vector2((v as Vector3).z, (v as Vector3).y) * 0.25)
				st.set_color(Color(0, 0, 0, 0.1))
				st.add_vertex(v)
		prev = cur
		z += 0.5
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "MouthFace"
	mi.mesh = st.commit()
	mi.material_override = _rock()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(mi)


func _v(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, height(p.x, p.y) + lift, p.y)


func _hall_crystals() -> void:
	# floor formations round the hall's edges and along the tunnel walls; hanging ones from the roof
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 900:
		tries += 1
		var p := HALL + Vector2.from_angle(rng.randf() * TAU) * Vector2(HALL_R.x, HALL_R.y) * rng.randf_range(0.45, 0.95)
		if trail_at(p.x, p.y) > 0.1 or p.distance_to(POOL) < 6.5 or p.distance_to(GIANT) < 6.0:
			continue
		var edge := clampf(1.0 + cave_sdf(p) / 6.0, 0.0, 1.0)
		var inward := (HALL - p).normalized()
		var up := (Vector3(inward.x, 0, inward.y) * edge * 0.9 + Vector3.UP).normalized()
		crystals(_v(p, -0.15), up, rng.randf_range(0.9, 2.6), placed % 3, 500 + placed, placed % 2 == 0)
		placed += 1
	for i in 12:
		var p2 := HALL + Vector2.from_angle(rng.randf() * TAU) * Vector2(HALL_R.x, HALL_R.y) * rng.randf_range(0.1, 0.7)
		var r := roof(p2.x, p2.y)
		if r - height(p2.x, p2.y) < 6.0:
			continue
		crystals(Vector3(p2.x, r + 0.3, p2.y), Vector3.DOWN, rng.randf_range(0.8, 1.8), i % 3, 700 + i, i % 3 == 0)
	# a few in the mouth tunnel, catching the daylight
	for i in 4:
		var p3 := Vector2(rng.randf_range(-12, 4), (5.0 if i % 2 == 0 else -5.0) + rng.randf_range(-0.5, 0.5))
		crystals(_v(p3, -0.1), (Vector3(0, 0, -signf(p3.y)) * 0.8 + Vector3.UP).normalized(), rng.randf_range(0.5, 1.1), 0, 800 + i, false)
	add_location("luminous_crystal_hall", Vector3(HALL.x, 0, HALL.y), 26.0, _v(HALL + Vector2(-6, 8)), "a domed cavern lit by crystal formations, a still pool at its heart")


func _giant() -> void:
	crystals(_v(GIANT, -0.4), Vector3(0.12, 1, 0.05).normalized(), 7.5, 1, 911, true)
	Kit.omni(self, _v(GIANT, 6.0), Color(0.75, 0.6, 1.0), 2.4, 18.0)
	add_poi("giant_crystal", _v(GIANT + Vector2(-5, 5)), "Towering violet crystal formation", "luminous_crystal_hall", 4.5)


func _pool() -> void:
	var wm := RiverRibbon.forest_water()
	for kv in [["shallow", Color(0.2, 0.42, 0.5)], ["deep", Color(0.0, 0.03, 0.05)], ["sky_tint", Color(0.2, 0.45, 0.6)], ["spec", 0.9], ["flow", Vector2(0.0, 0.004)], ["ripple", 0.03]]:
		wm.set_shader_parameter(kv[0], kv[1])
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 6.4
	cm.bottom_radius = 6.4
	cm.height = 0.02
	cm.radial_segments = 40
	disc.mesh = cm
	disc.material_override = wm
	disc.position = Vector3(POOL.x, height(POOL.x, POOL.y) + 1.1, POOL.y)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)


func _miners_camp() -> void:
	var c := _v(MOUTH + Vector2(-10, 4))
	Kit.place_prop(self, "wooden_crate_01", Kit.xf(c + Vector3(0, 0, 0), 0.3), "", true)
	Kit.place_prop(self, "wooden_crate_01", Kit.xf(c + Vector3(1.0, 0, 0.4), 1.1), "", true)
	Kit.place_prop(self, "wooden_crate_01", Kit.xf(c + Vector3(0.5, 0.62, 0.2), 0.7), "", false)
	Kit.place_prop_all(self, "wooden_barrels_01", Kit.xf(c + Vector3(-1.6, 0, -0.6), 0.0, Vector3.ONE * 0.8), true)
	# timber props shoring up the mouth, a lantern on a post
	var wood := Kit.tri("dark_wooden_planks", "1k", 0.6, 0.0, Color(0.55, 0.4, 0.28))
	for sz: float in [-1.0, 1.0]:
		var post := _v(MOUTH + Vector2(1, sz * 5.4))
		Kit.block(self, Vector3(0.36, 5.6, 0.36), Kit.xf(post + Vector3(0, 2.8, 0)), wood, true, 0.02)
	Kit.block(self, Vector3(0.4, 0.4, 11.6), Kit.xf(_v(MOUTH + Vector2(1, 0)) + Vector3(0, 5.7, 0)), wood, false, 0.02)
	var lamp := _v(MOUTH + Vector2(-4, 5.5))
	Kit.block(self, Vector3(0.15, 2.2, 0.15), Kit.xf(lamp + Vector3(0, 1.1, 0)), wood, true, 0.01)
	Kit.mesh_node(self, Kit.prop("Lantern_01", "Lantern_01"), null, Kit.xf(lamp + Vector3(0, 2.3, 0), 0.0, Vector3.ONE * 1.6))
	Kit.omni(self, lamp + Vector3(0, 2.4, 0), Color(1.0, 0.7, 0.4), 1.0, 8.0)
	add_location("crystal_entrance", Vector3(MOUTH.x - 8, 0, MOUTH.y), 14.0, _v(MOUTH + Vector2(-8, -2)), "a quarry ravine ending at a cave mouth shored with timber")


func _scree() -> void:
	var by_id := {}
	for i in 90:
		var p := Vector2(rng.randf_range(-86, MOUTH.x), rng.randf_range(-16, 16))
		var w := _ravine_w(p.y, p.x)
		if absf(p.y) < w - 1.0 or trail_at(p.x, p.y) > 0.1:
			continue
		if p.distance_to(MOUTH + Vector2(-10, 4)) < 5.0 or p.distance_to(MOUTH + Vector2(-4, 5.5)) < 2.5:
			continue        # the miners' camp (its crates, the survey spot) and the lantern post stay clear of boulders
		var id: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
		(by_id.get_or_add(id, []) as Array).append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, 0)).scaled(Vector3.ONE * rng.randf_range(0.5, 2.0)), _v(p, -0.3)))
	for id in by_id:
		NatureKit.scatter(self, NatureKit.mesh(String(id)), by_id[id], {"vis_end": 160.0, "shadow": true, "name": "Scree"})


func links() -> void:
	var gv := GATE_VILLAGE
	add_gate("village", _v(gv), _v(gv + Vector2(8, 0), 0.05), -PI * 0.5, 2.8)
	add_gate("deep_caverns", _v(TUNNEL_END), _v(TUNNEL_END + Vector2(-7, -1), 0.05), PI * 0.5, 2.4)
	add_interactable(Interactable.make("collect_crystal_shard", "Chip a small shard from a crystal cluster", "collect", "luminous_crystal_hall",
		_v(HALL + Vector2(-14, 10)), {"items": {"crystal_shard": 1}}, "", 3.0)).radius = 3.0
	add_interactable(Interactable.make("crystal_resonance", "Listen to the crystals' resonance", "study", "luminous_crystal_hall",
		_v(GIANT + Vector2(-5, 6)), {"knowledge": {"lore:crystal_resonance": 1}, "skills": {"arcane_orb": 0.1}}, "spell_casting", 4.2)).radius = 4.5
	add_interactable(Interactable.make("entrance_survey", "Examine the miners' crates at the cave mouth", "inspect", "crystal_entrance",
		_v(MOUTH + Vector2(-9, 2.5)), {"knowledge": {"lore:crystal_miners": 1}}, "look_around", 3.0)).radius = 2.4
