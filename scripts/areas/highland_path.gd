extends MountainRegion
## E1 Mountain Path + E2 Cliff Overlook (Celestial Highlands) - rebuilt on the realistic toolkit (world-quality gate).
## A mountainside 280 m across: the trail leaves the village road at the foot (south) and climbs in long
## switchbacks through the last pines, past cairns and an old stone WAYSTATION, onto bare scree and snow toward the
## SUMMIT STAIRWAY (north). The frontier road from the Whispering Woods comes over the western shoulder and joins it.
## The whole east side falls away 150 m to the SEA OF CLOUDS; a stone OVERLOOK juts out over the drop.

const GATE_VILLAGE := Vector2(-10, 134)
const GATE_WOODS := Vector2(-134, 22)
const GATE_SUMMIT := Vector2(10, -134)
const OVERLOOK2 := Vector2(66, -4)
const WAYSTATION := Vector2(-30, 52)
const JUNCTION := Vector2(-6, 24)
const TRAIL_PTS := [GATE_VILLAGE, Vector2(18, 112), Vector2(-22, 88), Vector2(16, 64), Vector2(-16, 42), JUNCTION, Vector2(26, 6),
	Vector2(-14, -20), Vector2(20, -46), Vector2(-12, -72), Vector2(14, -98), Vector2(6, -118), GATE_SUMMIT]

var stone: ShaderMaterial
var slate: Material
var _overlook_y := 0.0


func _init() -> void:
	cloud_y = -95.0
	treeline = 38.0
	snowline = 66.0
	trails = [
		[TRAIL_PTS, 2.6, "main"],
		[[GATE_WOODS, Vector2(-110, 26), Vector2(-80, 34), Vector2(-50, 30), Vector2(-26, 26), JUNCTION], 2.2, "main"],
		[[Vector2(26, 6), Vector2(40, 2), Vector2(54, -2), OVERLOOK2 + Vector2(-4, 0)], 1.8, "narrow"],
		[[Vector2(-16, 42), WAYSTATION + Vector2(4, -3)], 1.4, "narrow"],
	]
	clearings = [[OVERLOOK2 + Vector2(-6, 0), 6.0, "glade"], [WAYSTATION, 7.0, "glade"], [JUNCTION, 6.0, "glade"]]
	streams = []


func gate_spots() -> Array:
	return [GATE_VILLAGE, GATE_WOODS, GATE_SUMMIT]


func _edge_x(z: float) -> float:
	return 74.0 + 9.0 * sin(z * 0.04) + 4.0 * sin(z * 0.13 + 1.0)


func shape(x: float, z: float, h: float) -> float:
	var p := Vector2(x, z)
	# the mountainside climbs north: ~0 m at the village road, ~85 m at the summit stairway
	h = h * 2.2 + (140.0 - z) * 0.3
	# ribs and gullies across the slope
	h += 3.0 * sin(x * 0.045 + z * 0.012) + 2.0 * cos(z * 0.06 + x * 0.02)
	# the western shoulder the frontier road crosses
	h += 9.0 * exp(-pow((x + 92.0) / 34.0, 2.0)) * (1.0 - smoothstep(0.0, 70.0, absf(z - 20.0)))
	# the east: everything past the edge falls away to the clouds; the overlook rock stands out over it
	var d := x - _edge_x(z)
	var spur := 1.0 - smoothstep(4.0, 11.0, p.distance_to(OVERLOOK2 + Vector2(3, 0)))
	h -= smoothstep(-6.0, 30.0, d - spur * 12.0) * 175.0
	return h


func features() -> Array:
	return [_overlook, _waystation, _cairns, _summit_stair, _boulders, func(): outcrops([[Vector2(48, 40), 2.6], [Vector2(-60, -30), 3.0], [Vector2(40, -80), 2.4],
		[Vector2(-50, 90), 2.2], [Vector2(56, 70), 2.8], [Vector2(-90, -70), 3.2], [Vector2(30, -120), 2.4]])]


func _v(p: Vector2) -> Vector3:
	return Vector3(p.x, height(p.x, p.y), p.y)


func _stone() -> ShaderMaterial:
	if stone == null:
		stone = RealKit.stone_mat("mossy_stone_wall") if RealKit.enabled() else Kit.tri("rock_wall_10", "1k", 0.4, 0.9)
	return stone


func _slate() -> Material:
	if slate == null:
		slate = Kit.tri("roof_slates_02", "1k", 0.5, 0.15)
	return slate


## The overlook: a paved stone platform with a low parapet, jutting out over the cloud sea.
func _overlook() -> void:
	var c := _v(OVERLOOK2)
	_overlook_y = c.y + 0.4
	var sb := StoneBuilder.new(height, 91)
	sb.base_y = c.y - 4.0
	sb.top_y = c.y + 2.0
	sb.block(Transform3D(Basis.IDENTITY, Vector3(c.x, _overlook_y - 0.3, c.z)), Vector3(8.0, 0.6, 7.0), 0.3, 0.06)
	sb.collider(Transform3D(Basis.IDENTITY, Vector3(c.x, _overlook_y - 0.3, c.z)), Vector3(8.0, 0.6, 7.0))
	# a buttress under the lip
	sb.block(Transform3D(Basis.IDENTITY, Vector3(c.x + 2.6, _overlook_y - 2.4, c.z)), Vector3(2.6, 3.6, 6.0), 0.4, 0.1)
	sb.wall(Vector3(c.x + 4.0, _overlook_y, c.z - 3.4), Vector3(c.x + 4.0, _overlook_y, c.z + 3.4), 0.95, 0.5, 0.1)
	sb.wall(Vector3(c.x - 1.0, _overlook_y, c.z - 3.5), Vector3(c.x + 4.0, _overlook_y, c.z - 3.5), 0.95, 0.5, 0.2)
	sb.wall(Vector3(c.x - 1.0, _overlook_y, c.z + 3.5), Vector3(c.x + 4.0, _overlook_y, c.z + 3.5), 0.95, 0.5, 0.25)
	sb.finish(self, _stone(), "Overlook")
	add_location("cliff_overlook", Vector3(c.x, 0, c.z), 10.0, Vector3(c.x + 1.0, _overlook_y, c.z), "a stone overlook above the sea of clouds")


## An old stone shelter for travellers: thick walls, a slate roof, a doorway facing the trail, a bench outside.
func _waystation() -> void:
	var c := _v(WAYSTATION)
	var sb := StoneBuilder.new(height, 93)
	sb.base_y = c.y - 1.0
	sb.top_y = c.y + 4.0
	var w := 6.0
	var d := 4.6
	var y0 := c.y - 0.2
	sb.wall(Vector3(c.x - w * 0.5, y0, c.z - d * 0.5), Vector3(c.x + w * 0.5, y0, c.z - d * 0.5), 2.8, 0.6, 0.0)
	sb.wall(Vector3(c.x - w * 0.5, y0, c.z - d * 0.5), Vector3(c.x - w * 0.5, y0, c.z + d * 0.5), 2.8, 0.6, 0.0)
	sb.wall(Vector3(c.x + w * 0.5, y0, c.z - d * 0.5), Vector3(c.x + w * 0.5, y0, c.z + d * 0.5), 2.8, 0.6, 0.0)
	sb.wall(Vector3(c.x - w * 0.5, y0, c.z + d * 0.5), Vector3(c.x - 0.8, y0, c.z + d * 0.5), 2.8, 0.6, 0.0)
	sb.wall(Vector3(c.x + 0.8, y0, c.z + d * 0.5), Vector3(c.x + w * 0.5, y0, c.z + d * 0.5), 2.8, 0.6, 0.0)
	# the door's lintel, bedded on the jambs' top courses (the walls follow the ground, so not at a fixed height)
	sb.block_on(Vector3(c.x, y0 + 2.6, c.z + d * 0.5), Vector3(2.0, 0.4, 0.62), 0.2, 0.05, 2.0)
	# the bench outside, on a plinth where the ground falls away in front of the door
	var bench := Vector3(c.x + 2.0, y0 + 0.25, c.z + d * 0.5 + 0.9)
	sb.block(Transform3D(Basis.IDENTITY, bench), Vector3(1.8, 0.45, 0.55), 0.3, 0.05)
	sb.footing(bench, Vector3(1.6, 0, 0.5), bench.y - 0.225)
	sb.finish(self, _stone(), "Waystation")
	# the roof: two pitched slate planes
	for sgn: float in [-1.0, 1.0]:
		var rb := Basis(Vector3.RIGHT, sgn * 0.52)
		Kit.block(self, Vector3(w + 1.0, 0.16, d * 0.62), Transform3D(rb, Vector3(c.x, y0 + 3.45, c.z + sgn * d * 0.27)), _slate(), true, 0.02)
	# a lantern hook by the door, lit after dark
	night_only(Kit.omni(self, Vector3(c.x - 1.3, y0 + 2.3, c.z + d * 0.5 + 0.5), Color(1.0, 0.72, 0.42), 1.2, 7.0))
	add_poi("waystation", Vector3(c.x, y0, c.z + d * 0.5 + 1.6), "An old stone waystation for travellers", "mountain_path", 2.4)


## Cairns at the switchback corners (one is the old one travellers add stones to).
func _cairns() -> void:
	var sb := StoneBuilder.new(height, 95)
	var corners := [TRAIL_PTS[2], TRAIL_PTS[3], TRAIL_PTS[4], TRAIL_PTS[7], TRAIL_PTS[8], TRAIL_PTS[9]]
	var i := 0
	for q in corners:
		var off := Vector2(3.2, 1.2) if (q as Vector2).x > 0 else Vector2(-3.2, 1.2)
		var p: Vector2 = (q as Vector2) + off
		var y := height(p.x, p.y) - 0.1
		var layers := 5 + (i % 3)
		for k in layers:
			var s := lerpf(0.75, 0.32, float(k) / layers)
			sb.block(Transform3D(Basis(Vector3.UP, k * 0.9 + i), Vector3(p.x, y + 0.14 + k * 0.26, p.y)), Vector3(s, 0.28, s * 0.85), 0.25, 0.08)
		sb.collider(Transform3D(Basis.IDENTITY, Vector3(p.x, y + layers * 0.13, p.y)), Vector3(0.8, layers * 0.26, 0.8))
		if i == 2:
			add_poi("trail_cairn", Vector3(p.x, y, p.y) + Vector3(0, 0, 1.4), "Stone cairn marking the switchbacks", "mountain_path", 2.0)
		i += 1
	sb.finish(self, _stone(), "Cairns")
	add_location("mountain_path", Vector3(0, 0, 40), 60.0, _v(TRAIL_PTS[4]), "a switchback trail up a mountainside above the clouds")


## Where the trail reaches the summit stairway: two worn pillars and a lintel (the old gate of the pilgrims' way).
func _summit_stair() -> void:
	var c := _v(GATE_SUMMIT + Vector2(0, 12))
	var sb := StoneBuilder.new(height, 97)
	sb.base_y = c.y - 1.0
	sb.top_y = c.y + 5.0
	sb.arch(c, 0.0, 3.6, 3.2, 0.9, 0.9, false, 0.0)
	sb.finish(self, _stone(), "PilgrimGate")


func _boulders() -> void:
	var by_id := {}
	for i in 70:
		var p := Vector2(rng.randf_range(-130, 70), rng.randf_range(-130, 130))
		if trail_at(p.x, p.y) > 0.2 or site_clearing(p, 2.0) or p.x > _edge_x(p.y) - 6.0:
			continue
		var id: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
		(by_id.get_or_add(id, []) as Array).append(dress.xf_at(p, rng.randf_range(0.6, 2.2), 0.3, 0.3))
	for id in by_id:
		NatureKit.scatter(self, NatureKit.mesh(String(id)), by_id[id], {"vis_end": 220.0, "shadow": true, "name": "Boulders"})


func links() -> void:
	edge_gate("village", GATE_VILLAGE)
	edge_gate("whispering_woods", GATE_WOODS)
	edge_gate("celestial_summit", GATE_SUMMIT)
	add_interactable(Interactable.make("cairn_add_stone", "Add a stone to the trail cairn", "offer", "mountain_path",
		points_of_interest["trail_cairn"].position, {"knowledge": {"custom:cairn_stone": 1}}, "", 2.5)).radius = 2.4
	add_interactable(Interactable.make("overlook_observe", "Take in the view over the sea of clouds", "observe", "cliff_overlook",
		Vector3(OVERLOOK2.x + 1.0, _overlook_y, OVERLOOK2.y), {"knowledge": {"geography:cloud_sea": 1}, "discover": ["cloud_temple", "celestial_observatory"]}, "look_around", 4.0)).radius = 2.6


func showcase_shots(loc: String) -> Array:
	if loc == "cliff_overlook":
		return [[Vector3(OVERLOOK2.x - 7.0, _overlook_y + 2.2, OVERLOOK2.y + 3.0), Vector3(OVERLOOK2.x + 400.0, cloud_y + 20.0, OVERLOOK2.y - 150.0), 62.0]]
	return []
