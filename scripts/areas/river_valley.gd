extends ForestRegion
## B2 Luminous River + B3 Waterfall Crossing (Enchanted Forest) - rebuilt on the Whispering Woods' realistic
## toolkit (the world-quality gate). A wooded valley below a 22 m escarpment:
##   N  the upper river runs across the high wood to the lip, where it splits round a boulder into TWIN FALLS that
##      plunge into a misty POOL at the foot of the cliff
##   the WATERFALL CROSSING: stepping stones across the pool's outlet, right in the falls' spray
##   the LUMINOUS RIVER meanders south through the valley meadows; its reeds carry glowing beads and the water
##      is full of drifting lights after dark
##   the BRIDGE ROAD: an old three-arched stone bridge carries the road from the grove (south-west) east toward
##      the village
##   a path climbs the escarpment beside the falls to a ledge with a view down the valley
## Gates: south-west -> Ancient Grove, east -> the village (the waterfall bridge road).

const POOL := Vector2(0, -38)
const LIP_Z := -50.0
const CLIFF_H := 22.0
const BRIDGE_Z := 34.0
const CROSSING := Vector2(2, -24)
const MEADOW := Vector2(-6, 74)
const LEDGE := Vector2(-30, -54)
const GATE_GROVE := Vector2(-134, 104)
const GATE_VILLAGE := Vector2(134, 20)

var stone: ShaderMaterial
var _bead_mat: StandardMaterial3D


func _init() -> void:
	trails = [
		[[GATE_GROVE, Vector2(-110, 92), Vector2(-80, 72), Vector2(-50, 52), Vector2(-28, 40), Vector2(-16, BRIDGE_Z)], 3.0, "main"],
		[[Vector2(18, BRIDGE_Z), Vector2(40, 32), Vector2(70, 26), Vector2(100, 22), GATE_VILLAGE], 3.0, "main"],
		[[Vector2(-20, 38), Vector2(-14, 20), Vector2(-10, 0), Vector2(-6, -18), CROSSING + Vector2(-4, 0)], 2.0, "narrow"],
		[[CROSSING + Vector2(5, 0), Vector2(14, -12), Vector2(16, 10), Vector2(14, 26)], 1.6, "narrow"],
		[[Vector2(-12, -26), Vector2(-24, -34), Vector2(-34, -40), Vector2(-36, -48), LEDGE], 1.4, "narrow"],
		[[Vector2(-18, 40), Vector2(-14, 58), MEADOW + Vector2(-4, 0)], 1.6, "narrow"],
	]
	water_tune = {"spec": 0.32, "sheen_fres": 0.2, "sheen_base": 0.03, "sky_tint": Color(0.2, 0.28, 0.26), "shallow": Color(0.36, 0.44, 0.36), "foam_amount": 0.25}
	clearings = [[MEADOW, 14.0, "pond"], [POOL + Vector2(0, 14), 7.0, "falls_approach"], [GATE_GROVE + Vector2(10, -8), 9.0, "glade"]]
	streams = [
		[[Vector2(6, -140), Vector2(-4, -110), Vector2(4, -80), Vector2(-2, -62), Vector2(0, LIP_Z - 2.0)], 3.2, 1.2],
		[[POOL + Vector2(0, 10.5), CROSSING, Vector2(-2, -6), Vector2(4, 12), Vector2(2, BRIDGE_Z), Vector2(8, 52), Vector2(-2, 74) + Vector2(14, 0), Vector2(4, 100), Vector2(-6, 124), Vector2(0, 140)], 4.2, 1.5],
	]


func gate_spots() -> Array:
	return [GATE_GROVE, GATE_VILLAGE]


func _cliff_z(x: float) -> float:
	return LIP_Z + 3.0 * sin(x * 0.045) + 2.0 * sin(x * 0.11 + 0.7) - smoothstep(20.0, 90.0, absf(x)) * 6.0


func shape(x: float, z: float, h: float) -> float:
	var p := Vector2(x, z)
	# the escarpment: the high wood north of the cliff line (a steep face, sharpest beside the falls)
	var cz := _cliff_z(x)
	var near_falls := 1.0 - smoothstep(10.0, 26.0, absf(x))
	var hi := smoothstep(cz + lerpf(5.0, 1.2, near_falls), cz - lerpf(6.0, 1.6, near_falls), z)
	h += hi * CLIFF_H
	# the ledge path climbs the face west of the falls on a ramp
	var ramp := 1.0 - smoothstep(2.0, 5.0, _seg_dist(p, Vector2(-34, -36), LEDGE))
	var ramp_h := clampf(inverse_lerp(-36.0, -54.0, z), 0.0, 1.0) * CLIFF_H
	h = lerpf(h, maxf(ramp_h, h) if hi > 0.98 else ramp_h + h - hi * CLIFF_H, ramp)
	# the plunge pool, a deep bowl at the foot of the falls
	h -= 2.4 * (1.0 - smoothstep(6.0, 13.0, p.distance_to(POOL)))
	# valley sides: wooded slopes rising east and west, opened where the road passes
	# (the road's notch: east it leaves at z≈20-26, west it climbs out toward the grove at z≈70-100)
	var notch_z := 24.0 if x > 0 else 80.0
	var side := smoothstep(40.0, 120.0, absf(x)) * 14.0 * (1.0 - (1.0 - smoothstep(12.0, 34.0, absf(z - notch_z))) * 0.75)
	h += side * (1.0 - hi)
	return h


func density(p: Vector2, f: float) -> float:
	# the valley floor along the river is meadow-like and open; the slopes are dense wood
	var valley := 1.0 - smoothstep(14.0, 40.0, absf(p.x))
	f -= 0.35 * valley * smoothstep(LIP_Z + 10.0, LIP_Z + 30.0, p.y)
	return f


func _ford_at(p: Vector2) -> bool:
	return p.distance_to(CROSSING) < 4.5 or absf(p.y - BRIDGE_Z) < 4.0


func features() -> Array:
	return [_pool_water, _falls, _crossing_stones, _bridge, _river_lights, _cliff_rocks, _ledge,
		func(): dress_clearing(MEADOW, 14.0, true), func(): dress_clearing(POOL + Vector2(0, 14), 6.0, true, [[CROSSING, 4.0]])]


func _v(p: Vector2) -> Vector3:
	return Vector3(p.x, height(p.x, p.y), p.y)


func _stone() -> ShaderMaterial:
	if stone == null:
		stone = RealKit.stone_mat("mossy_stone_wall") if RealKit.enabled() else Kit.tri("mossy_rock", "2k", 0.4, 0.95)
	return stone


func upper_y() -> float:
	return height(0, LIP_Z - 2.5) + 1.2 * 0.38


func pool_y() -> float:
	return height(CROSSING.x, CROSSING.y) + 1.5 * 0.38


# ------------------------------------------------------------------ water
func _pool_water() -> void:
	var wm: Material = mats.get("water")
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 11.0
	cm.bottom_radius = 11.0
	cm.height = 0.02
	cm.radial_segments = 48
	disc.mesh = cm
	disc.material_override = wm
	disc.position = Vector3(POOL.x, pool_y(), POOL.y)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	var ring := []
	for i in 12:
		ring.append(POOL + Vector2.from_angle(i * TAU / 12.0) * 9.0)
	_nav_hole(ring, pool_y() - 4.0, 4.6)


func _falls() -> void:
	# twin falls: the river parts round a boulder at the lip
	var top := upper_y()
	var lip := Vector3(0, top, LIP_Z - 1.0)
	waterfall(lip, pool_y(), [[-3.6, 3.4, 0.0, 2.6, 0.95], [3.8, 3.0, 0.1, 2.4, 1.05], [0.2, 0.9, 0.5, 1.6, 1.2]], Vector3(0, 0, 1))
	var split := Transform3D(Basis.from_euler(Vector3(0.1, 0.6, -0.1)).scaled(Vector3.ONE * 1.6), Vector3(0.2, top - 0.6, LIP_Z - 1.6))
	NatureKit.scatter(self, NatureKit.mesh("Rock_Medium_2"), [split], {"shadow": true, "vis_end": 260.0, "name": "LipBoulder"})
	add_location("waterfall_crossing", Vector3(CROSSING.x, 0, CROSSING.y), 18.0, _v(CROSSING + Vector2(-10, 3)), "stepping stones across the pool's outlet, in the spray of the twin falls")


func _crossing_stones() -> void:
	for i in 8:
		var p := CROSSING + Vector2(-4.2 + i * 1.15, sin(i * 1.7) * 0.5)
		var mi := Kit.mesh_node(self, Kit.rock_mesh(0.5, 800 + i, 0.25, Vector3(1.3, 0.45, 1.05)), _stone(),
			Kit.xf(Vector3(p.x, pool_y() + 0.12, p.y), i * 0.7))
		Kit.convex_collide(mi)
		await _build_slice()          # (a hull per stone: all eight held a 212 ms frame, 22 Oct)


func _bridge() -> void:
	stone_bridge(BRIDGE_Z, -13.0, 15.0, _stone(), 77)
	add_poi("old_bridge", _v(Vector2(1, BRIDGE_Z)) + Vector3(0, 3.2, 0), "The old stone bridge over the luminous river", "luminous_river")


## The luminous river: reeds along the banks carry glowing beads, and drifting lights hang over the water after dark.
func _river_lights() -> void:
	var reeds := []
	var beads := []
	for i in 520:
		var z := rng.randf_range(-20.0, 138.0)
		# walk to the bank: find the river centre at this z by sampling
		var best := 0.0
		var bd := INF
		for xx in range(-30, 31, 2):
			var d := float(stream_info(Vector2(xx, z))[0])
			if d < bd:
				bd = d
				best = float(xx)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p := Vector2(best + side * rng.randf_range(4.6, 7.2), z)
		if trail_at(p.x, p.y) > 0.3 or absf(z - BRIDGE_Z) < 4.0:
			continue
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), Vector3(p.x, height(p.x, p.y) - 0.05, p.y))
		reeds.append(t)
		if rng.randf() < 0.45:
			beads.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.6, 1.2)), t.origin + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.7, 1.3), rng.randf_range(-0.2, 0.2))))
	NatureKit.scatter(self, NatureKit.mesh("Grass_Wispy_Tall"), reeds, {"vis_end": 70.0, "name": "Reeds"})
	var bead := SphereMesh.new()
	bead.radius = 0.035
	bead.height = 0.07
	bead.radial_segments = 6
	bead.rings = 3
	_bead_mat = Kit.emissive(Color(0.45, 1.0, 0.85), 0.25)
	Kit.multimesh(self, bead, beads, 50.0, false, _bead_mat)
	# drifting lights over the water (night): slow motes hovering just above the surface
	for zz in [-10.0, 20.0, 52.0, 80.0, 110.0]:
		var c := Vector2(0, zz)
		var bd2 := INF
		for xx in range(-30, 31, 2):
			var d2 := float(stream_info(Vector2(xx, zz))[0])
			if d2 < bd2:
				bd2 = d2
				c.x = float(xx)
		var em := FX.particles(26, 6.0, FX.pm_motes("wind", "trail"), FX.mote_mesh(0.05, true))
		em.position = Vector3(c.x, height(c.x, c.y) + 1.1, c.y)
		em.emitting = true
		add_child(em)
		night_only(em)
		night_only(Kit.omni(self, Vector3(c.x, height(c.x, c.y) + 1.4, c.y), Color(0.35, 0.95, 0.8), 0.7, 9.0))
	add_location("luminous_river", Vector3(MEADOW.x, 0, MEADOW.y), 30.0, _v(MEADOW + Vector2(6, 0)), "a meadow on the luminous river, glowing reeds along its banks")


func set_time_of_day(h: float) -> void:
	super.set_time_of_day(h)
	if _bead_mat:
		_bead_mat.emission_energy_multiplier = 2.6 if (h < 5.5 or h > 19.5) else 0.25


## Mossy boulders heaped along the foot of the escarpment and framing the pool.
func _cliff_rocks() -> void:
	var by_id := {}
	for i in 46:
		var x := rng.randf_range(-110.0, 110.0)
		if absf(x) < 7.0:
			continue
		var cz := _cliff_z(x) + rng.randf_range(2.0, 6.0)
		var p := Vector2(x, cz)
		if trail_at(p.x, p.y) > 0.3:
			continue
		var id: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
		var s := rng.randf_range(1.2, 2.6)
		(by_id.get_or_add(id, []) as Array).append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))).scaled(Vector3.ONE * s), _v(p) - Vector3(0, 0.5 * s, 0)))
	for i in 12:
		var p2 := POOL + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 13.5)
		if p2.distance_to(CROSSING) < 5.0 or p2.y < POOL.y - 8.0:
			continue
		var id2: String = ["Rock_Medium_1", "Rock_Medium_3"][rng.randi() % 2]
		(by_id.get_or_add(id2, []) as Array).append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * rng.randf_range(0.9, 1.6)), _v(p2) - Vector3(0, 0.4, 0)))
	for id3 in by_id:
		NatureKit.scatter(self, NatureKit.mesh(String(id3)), by_id[id3], {"shadow": true, "vis_end": 300.0, "name": "CliffRocks"})


func _ledge() -> void:
	var sb := StoneBuilder.new(height, 83)
	var c := _v(LEDGE)
	sb.base_y = c.y - 1.0
	sb.top_y = c.y + 2.0
	# a low parapet of old stones at the ledge's edge
	sb.wall(c + Vector3(-3.0, 0, 3.0), c + Vector3(4.0, 0, 2.6), 0.9, 0.6, 0.3)
	sb.finish(self, _stone(), "LedgeWall")
	add_poi("falls_ledge", c, "A ledge beside the falls with a view down the valley", "waterfall_crossing")


# ------------------------------------------------------------------ links
func links() -> void:
	edge_gate("ancient_grove", GATE_GROVE)
	edge_gate("village", GATE_VILLAGE)
	add_interactable(Interactable.make("collect_river_water", "Fill a flask with luminous river water", "collect", "luminous_river",
		_v(MEADOW + Vector2(12, 0)), {"items": {"luminous_water": 1}}, "", 2.5)).radius = 2.6
	add_interactable(Interactable.make("reeds_study", "Study the glowing reeds", "study", "luminous_river",
		_v(MEADOW + Vector2(10, 8)), {"knowledge": {"lore:luminous_reeds": 1}}, "look_around", 3.5)).radius = 2.6
	add_interactable(Interactable.make("falls_meditate", "Meditate before the falls", "meditate", "waterfall_crossing",
		_v(CROSSING + Vector2(-6, 3)), {"skills": {"arcane_orb": 0.1}, "knowledge": {"calm:waterfall": 1}}, "", 4.0)).radius = 2.6
	add_poi("stepping_stones", _v(CROSSING), "Stepping stones across the pool's outlet", "waterfall_crossing")
