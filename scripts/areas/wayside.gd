class_name Wayside
extends WhisperingWoods
## A stretch of an OVERLAND ROUTE (V3 continuation: "Travel between major regions should involve multiple in-world
## days ... forest roads ... campsites ... resting, eating, preparing supplies"). The party walks a real road
## through it at real pace; it is generated per route and km (seeded), in the route's biome, with the Whispering
## Woods' realistic forest toolkit (same species, ground, undergrowth, light), so every stop is a different place:
##   the ROAD crosses it east -> west (the way the journey goes), with a STREAM and a stony FORD on it;
##   a CAMPSITE clearing a little off the road (flat, near the water, sheltered by big trees) with a ring of
##   fire stones, a fallen trunk to sit on and dry wood lying around in the forest for firewood;
##   both ends are gates: east = where they came from, west = onward (the JourneyDirector decides what loads next).
## params (set by the JourneyDirector before the load): route, km, seed, from, to, title.

static var params := {"route": "whispering_woods|ancient_grove", "km": 21.0, "seed": 4721, "from": "whispering_woods", "to": "ancient_grove",
	"title": "the old forest track west", "biome": "deep_forest"}

const ROAD_E := Vector2(136, 8)
const ROAD_W := Vector2(-136, -10)
const CAMP := Vector2(14, 34)
const CAMP_R := 9.5
const FORD := Vector2(-46, 2)

var camp := {}                   # what the camp scene uses: fire, seats, beds, wood, water, lookout (world positions)
var waypoint := {}               # the overland waypoint this stretch passes (data/overland.json), or {}
var site := Vector2.INF          # where it stands (north of the road)
var site_road := Vector2.INF     # where its path leaves the road
const SITE_R := 15.0
var town_key := ""               # TownLife: "wayside:<waypoint id>" when people live here
var _seed := 0
var _stream_pts: Array[Vector2] = []


func _init() -> void:
	_seed = int(params.get("seed", 1))
	var r := RandomNumberGenerator.new()
	r.seed = _seed
	# the road: a gently winding line from the east gate to the west gate
	var pts: Array[Vector2] = [ROAD_E]
	for i in range(1, 8):
		var t := i / 8.0
		var p := ROAD_E.lerp(ROAD_W, t)
		p.y += r.randf_range(-14.0, 14.0) * sin(t * PI)
		if absf(p.x - FORD.x) < 20.0:
			p = Vector2(p.x, FORD.y + r.randf_range(-3.0, 3.0))
		pts.append(p)
	pts.append(ROAD_W)
	var side := [Vector2(pts[3].x, pts[3].y), CAMP + Vector2(6, -6), CAMP + Vector2(2, -2)]
	trails = [[pts, 3.0, "main"], [side, 1.6, "narrow"], [[CAMP + Vector2(-6, 2), Vector2(-20, 22), Vector2(FORD.x + 8, FORD.y + 18)], 1.0, "hidden"]]
	# a waypoint on this stretch (a hamlet, an inn, a shelter, a landmark): a real place at the roadside, north of
	# the road (the camp lies south), where the journey's km puts it
	waypoint = params.get("waypoint", {})
	if not waypoint.is_empty():
		var wt := clampf(float(params.get("waypoint_t", 0.3)), 0.12, 0.88)
		var at := ROAD_E.lerp(ROAD_W, wt)
		var best := pts[0]
		for q in pts:
			if absf(q.x - at.x) < absf(best.x - at.x):
				best = q
		site_road = Vector2(at.x, best.y)
		if absf(site_road.x - FORD.x) < 18.0:
			site_road.x += 22.0 * signf(site_road.x - FORD.x + 0.01)
		site = site_road + Vector2(0, -20)
		trails.append([[site_road, site_road + Vector2(1.5, -7), site], 2.4, "main"])
	# the stream: north to south across the road at the ford
	_stream_pts.clear()
	for k in 15:
		var z := -HALF + k * SIZE / 14.0
		_stream_pts.append(Vector2(FORD.x + 9.0 * sin(z * 0.021 + _seed * 0.37) + 4.0 * sin(z * 0.07), z))


## Each stretch is its own place: its seed drives the layout and the dressing; its place on the planet (for the
## distant vista) lies between the two areas the route joins, by how far along it the party is.
func setup(id: String) -> void:
	super.setup(id)
	rng.seed = hash(id) ^ _seed
	info = info.duplicate()
	var a: Array = WorldState.areas.get(String(params.get("from", "")), {}).get("global_pos", [0, 0, 0])
	var b: Array = WorldState.areas.get(String(params.get("to", "")), {}).get("global_pos", [0, 0, 0])
	var route: Dictionary = JourneyDirector.route_info(String(params.get("route", "")))
	var t := clampf(float(params.get("km", 0.0)) / maxf(float(route.get("km", 1.0)), 1.0), 0.0, 1.0)
	info["global_pos"] = [lerpf(a[0], b[0], t), lerpf(a[1], b[1], t), lerpf(a[2], b[2], t)]


# ------------------------------------------------------------------ geography
func stream_x(z: float) -> float:
	return FORD.x + 9.0 * sin(z * 0.021 + _seed * 0.37) + 4.0 * sin(z * 0.07)


func _raw_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var s := float(_seed % 997) * 0.13
	var roll := 1.4 * sin(x * 0.041 + s) * cos(z * 0.035 + s * 0.5) + 0.6 * sin(x * 0.12 + 1.3) * sin(z * 0.09 + s) + 0.25 * sin((x - z) * 0.23)
	var h := roll
	# the stream bed (shallow at the ford, where the road crosses on stones)
	var dr := absf(x - stream_x(z))
	var ford_k := 1.0 - smoothstep(3.0, 8.0, absf(z - FORD.y))
	h -= (1.0 - smoothstep(2.5, 7.0, dr)) * lerpf(1.6, 0.98, ford_k)   # 15 cm of water over the ford stones
	h *= 1.0
	# the campsite: a level clearing
	var flat := 1.0 - smoothstep(CAMP_R - 2.0, CAMP_R + 5.0, p.distance_to(CAMP))
	h = lerpf(h, 0.3 + roll * 0.15, flat)
	# hills along the north and south edges (the road keeps to the valley)
	h += smoothstep(70.0, 132.0, absf(z)) * 16.0 * (1.0 - _gap_near_routes(p))
	h += smoothstep(118.0, 138.0, absf(x)) * 10.0 * (1.0 - _gap_near_routes(p))
	return h


func _gap_near_routes(p: Vector2) -> float:
	var g := 1.0 - smoothstep(8.0, 18.0, p.distance_to(ROAD_E))
	g = maxf(g, 1.0 - smoothstep(8.0, 18.0, p.distance_to(ROAD_W)))
	return g


func _terrain_mask(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var ix := clampi(int(round((x + HALF) / STEP)), 0, _n - 1)
	var iz := clampi(int(round((z + HALF) / STEP)), 0, _n - 1)
	var tr := _trail_mask[iz * _n + ix]
	var hid := _hidden_mask[iz * _n + ix] * 0.45
	var bank := 1.0 - smoothstep(4.0, 8.5, absf(x - stream_x(z)))
	var camp_bare := (1.0 - smoothstep(2.0, 4.5, p.distance_to(CAMP))) * 0.7
	return Color(maxf(maxf(tr, hid), camp_bare), _forest_density(p) * 0.85, clampf(bank, 0.0, 1.0), 0.0)


func _forest_density(p: Vector2) -> float:
	var s := float(_seed % 113)
	var f := 0.62 + 0.25 * sin(p.x * 0.033 + s) * cos(p.y * 0.029 + s * 0.3)
	f -= 0.55 * (1.0 - smoothstep(CAMP_R, CAMP_R + 9.0, p.distance_to(CAMP)))
	if site != Vector2.INF:
		f -= 0.75 * (1.0 - smoothstep(SITE_R, SITE_R + 10.0, p.distance_to(site)))
	return clampf(f, 0.0, 1.0)


## The road is smoothed where it runs (worn footing) - but at the ford it must go down INTO the stream: there the
## raw ground (the shallow stony bed) is put back, so the crossing is wet, ankle-deep water over the stones.
func _precompute() -> void:
	super._precompute()
	for iz in _n:
		var z := -HALF + iz * STEP
		if absf(z - FORD.y) > 7.0:
			continue
		for ix in _n:
			var x := -HALF + ix * STEP
			if absf(x - stream_x(z)) < 6.0:
				_hgrid[iz * _n + ix] = minf(_hgrid[iz * _n + ix], _raw_height(x, z))


## Hooks the Woods dressing asks a generated stretch for (its own zones, water and open ground).
func site_zone(p: Vector2) -> String:
	if p.distance_to(CAMP) < CAMP_R + 8.0 or (site != Vector2.INF and p.distance_to(site) < SITE_R + 6.0):
		return "clearing"
	if absf(p.x - stream_x(p.y)) < 10.0:
		return "streamside"
	return "deep" if _forest_density(p) > 0.7 else "wood"


func site_water_dist(p: Vector2) -> float:
	return absf(p.x - stream_x(p.y)) - 3.2


func site_clearing(p: Vector2, margin := 0.0) -> bool:
	if p.distance_to(CAMP) < CAMP_R + margin:
		return true
	if site != Vector2.INF and p.distance_to(site) < SITE_R + margin:
		return true
	if p.distance_to(ROAD_E) < 10.0 + margin or p.distance_to(ROAD_W) < 10.0 + margin:
		return true
	return p.distance_to(FORD) < 7.0 + margin


func build_steps() -> Array:
	dress = WoodsDressing.new(self)
	dress.rng.seed = 7171 ^ _seed
	feats = WoodsFeatures.new(self)
	feats.rng.seed = 9191 ^ _seed
	marks = null
	return [_precompute, _painted_sky, _terrain, _stream, dress.compute_trail_distance, dress.trees, dress.understory,
		dress.undergrowth, dress.grass, dress.rocks, dress.atmosphere, feats.leaf_fall, _campsite, _waypoint_site, _links]


func _stream() -> void:
	var wm := RiverRibbon.forest_water()
	mats.water = wm
	# the water level along the stream: the bed's depth below the bank, everywhere the same depth of water - and
	# across the ford it keeps the level of the water either side (shallow over the raised stony bed)
	var zs: Array[float] = []
	var lv: Array[float] = []
	var z := -HALF
	while z <= HALF:
		zs.append(z)
		lv.append(height(stream_x(z), z) + 0.75)
		z += 2.0
	var lo := FORD.y - 9.0
	var hi := FORD.y + 9.0
	var ia := 0
	var ib := zs.size() - 1
	for i in zs.size():
		if zs[i] <= lo:
			ia = i
		if zs[i] >= hi and ib == zs.size() - 1:
			ib = i
	for i in range(ia + 1, ib):
		lv[i] = lerpf(lv[ia], lv[ib], (zs[i] - zs[ia]) / maxf(zs[ib] - zs[ia], 0.01))
	var centre: Array = []
	var widths: Array = []
	for i in zs.size():
		centre.append(Vector3(stream_x(zs[i]), lv[i], zs[i]))
		widths.append(6.2)
	add_child(RiverRibbon.build(centre, widths, wm))
	# the water is not walkable - except at the ford, where the road crosses on stones
	for i in zs.size() - 1:
		var za := zs[i]
		var zb := zs[i + 1]
		if absf((za + zb) * 0.5 - FORD.y) < 5.0:
			continue
		var xa := stream_x(za)
		var xb := stream_x(zb)
		_nav_hole([Vector2(xa - 2.4, za), Vector2(xa + 2.4, za), Vector2(xb + 2.4, zb), Vector2(xb - 2.4, zb)], lv[i] - 4.0, 4.6)
	# stepping stones across the ford
	var stone := RealKit.stone_mat("rock_pitted_mossy") if RealKit.enabled() else Kit.tri("mossy_rock", "2k", 0.4, 0.95)
	var fx := stream_x(FORD.y)
	for i in 7:
		var p := Vector3(fx - 3.0 + i * 1.0, 0, FORD.y + rng.randf_range(-0.8, 0.8))
		var mi := Kit.mesh_node(self, Kit.rock_mesh(0.42, 500 + i, 0.25, Vector3(1.3, 0.4, 1.0)), stone, Kit.xf(Vector3(p.x, height(p.x, p.z) + 0.12, p.z), i))
		Kit.convex_collide(mi)


## The campsite: a ring of fire stones, a fallen trunk and a stump to sit on, flat ground for two bedrolls, a
## lookout spot with a view down the road, and dry branches lying in the forest round about (for gathering).
func _campsite() -> void:
	var c := Vector3(CAMP.x, height(CAMP.x, CAMP.y), CAMP.y)
	var pit := Kit.place_prop(self, "stone_fire_pit", Kit.xf(c + Vector3(0, -0.02, 0), rng.randf() * TAU, Vector3.ONE * 1.0), "", false)
	pit.name = "FirePit"
	var log_at := c + Vector3(-2.4, 0, 0.6)
	log_at.y = height(log_at.x, log_at.z)
	Kit.place_prop(self, "dead_tree_trunk", Kit.xf(log_at + Vector3(0, -0.1, 0), PI * 0.5 + 0.2, Vector3.ONE * 0.55), "", true)
	var stump_at := c + Vector3(1.9, 0, -1.7)
	stump_at.y = height(stump_at.x, stump_at.z)
	Kit.place_prop(self, "tree_stump_01", Kit.xf(stump_at, 0.7, Vector3.ONE * 0.9), "", true)
	var to_road := (Vector2(0, -1)).normalized()
	camp = {
		"center": c,
		"fire": c + Vector3(0, 0.05, 0),
		"seats": [c + Vector3(-1.5, 0, 0.9), c + Vector3(1.3, 0, 1.0)],
		"cook": c + Vector3(0.0, 0, 1.25),
		"beds": [c + Vector3(-1.6, 0, 3.2), c + Vector3(1.4, 0, 3.4)],
		"packs": [c + Vector3(-2.6, 0, 2.2), c + Vector3(2.6, 0, 2.4)],
		"lookout": c + Vector3(to_road.x, 0, to_road.y) * 5.5,
		"water": Vector3(stream_x(CAMP.y + 6.0) + 3.6, height(stream_x(CAMP.y + 6.0) + 3.6, CAMP.y + 6.0), CAMP.y + 6.0),
		"wood": [],
	}
	for k in ["seats", "beds", "packs"]:
		var arr: Array = camp[k]
		for i in arr.size():
			var p: Vector3 = arr[i]
			arr[i] = Vector3(p.x, height(p.x, p.z), p.z)
	var lk: Vector3 = camp.lookout
	camp.lookout = Vector3(lk.x, height(lk.x, lk.z), lk.z)
	# dry wood in the forest: branches lying 8-22 m from the fire, off the paths
	var placed := 0
	var tries := 0
	while placed < 7 and tries < 200:
		tries += 1
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(8.0, 22.0)
		var q := CAMP + Vector2.from_angle(ang) * dist
		if trail_at(q.x, q.y) > 0.2 or site_water_dist(q) < 2.0:
			continue
		var at := Vector3(q.x, height(q.x, q.y), q.y)
		var br := Kit.place_prop(self, "dry_branches_medium_01", Kit.xf(at, rng.randf() * TAU, Vector3.ONE * 0.7), "", false)
		br.name = "Firewood_%d" % placed
		(camp.wood as Array).append({"pos": at, "node": br})
		placed += 1


## The waypoint, built: a hamlet or village (houses round a yard, a woodpile, its people at work), an inn (a big house
## with a hanging sign, a bench, the keeper), a shelter (a small stone hut), a landmark (the Old Ash; a carved
## standing stone and a cairn). People who live there are data/residents.json "wayside:<id>" (TownLife).
func _waypoint_site() -> void:
	if waypoint.is_empty() or site == Vector2.INF:
		return
	var kind := String(waypoint.get("kind", ""))
	var wid := String(waypoint.get("id", "place"))
	var c := Vector3(site.x, height(site.x, site.y), site.y)
	var to_road := (site_road - site).normalized()
	var vm := village_mats()
	match kind:
		"hamlet", "village":
			var hb := HouseBuilder.new(self, height)
			var n := 4 if kind == "hamlet" else 5
			for i in n:
				var a := atan2(to_road.y, to_road.x) + PI * 0.35 + TAU * 0.65 * i / maxf(n - 1, 1)
				var hp := site + Vector2.from_angle(a) * 10.5
				var face := (site - hp).normalized()
				var base := height(hp.x, hp.y)
				for dx in [-3.0, 3.0]:
					for dz in [-3.0, 3.0]:
						base = minf(base, height(hp.x + dx, hp.y + dz))
				hb.house(Vector3(hp.x, base, hp.y), atan2(face.x, face.y), 6.0 + (i % 2) * 0.8, 5.0, 900 + _seed % 97 + i * 13, 1 if i % 3 != 0 else 2)
			for i in hb.doors.size():
				add_anchor("home:%d" % i, hb.doors[i].pos, float(hb.doors[i].yaw), true)
			var wp := c + Vector3(to_road.x, 0, to_road.y) * -4.0 + Vector3(3.5, 0, 0)
			wp.y = height(wp.x, wp.z)
			Kit.place_prop(self, "tree_stump_01", Kit.xf(wp, 0.3, Vector3.ONE * 0.7), "", true)
			Kit.place_prop(self, "wooden_axe", Kit.xf(wp + Vector3(0, 0.55, 0), 0.4), "", false)
			add_anchor("woodpile", wp + Vector3(-0.8, 0, 0), PI * 0.5)
			for j in 2:
				var sp := c + Vector3(-1.0 + j * 1.6, 0, 1.2)
				sp.y = height(sp.x, sp.z)
				add_anchor("square:%d" % j, sp, -PI * 0.5 if j == 0 else PI * 0.5)
			var g := c + Vector3(to_road.x, 0, to_road.y) * 5.0 + Vector3(-4.0, 0, 0)
			g.y = height(g.x, g.z)
			Kit.place_prop_all(self, "planter_box_01", Kit.xf(g, 0.2, Vector3.ONE * 1.4))
			add_anchor("garden:0", g + Vector3(0, 0, 1.2), PI)
			lantern_post(c + Vector3(to_road.x, 0, to_road.y) * 7.0, vm, 1.0)
		"inn":
			var hb2 := HouseBuilder.new(self, height)
			var base2 := height(site.x, site.y)
			for dx in [-5.0, 5.0]:
				for dz in [-4.0, 4.0]:
					base2 = minf(base2, height(site.x + dx, site.y + dz))
			hb2.house(Vector3(site.x, base2, site.y), atan2(to_road.x, to_road.y), 10.0, 7.0, 4400 + _seed % 53, 2)
			add_anchor("home:0", hb2.doors[0].pos, float(hb2.doors[0].yaw), true)
			var front := c + Vector3(to_road.x, 0, to_road.y) * 6.5
			front.y = height(front.x, front.z)
			# the hanging sign on its post
			var post := front + Vector3(to_road.y, 0, -to_road.x) * 3.0
			post.y = height(post.x, post.z)
			Kit.block(self, Vector3(0.16, 3.0, 0.16), Kit.xf(post + Vector3(0, 1.5, 0)), vm.timber, true, 0.02)
			Kit.block(self, Vector3(1.0, 0.1, 0.1), Kit.xf(post + Vector3(0.45, 2.9, 0)), vm.timber, false, 0.01)
			Kit.block(self, Vector3(0.8, 0.55, 0.05), Kit.xf(post + Vector3(0.6, 2.5, 0)), Kit.tri("wood_table_001", "1k", 1.0, 0.0, Color(0.5, 0.36, 0.24)), false, 0.01)
			night_only(Kit.omni(self, post + Vector3(0.6, 2.2, 0.4), Color(1.0, 0.7, 0.4), 1.4, 8.0))
			seat_bench(front + Vector3(to_road.y, 0, -to_road.x) * -2.5, atan2(to_road.x, to_road.y), 2, "bench_seat", 0, Kit.tri("wood_table_001", "1k", 0.9, 0.0, Color(0.62, 0.5, 0.4)))
			add_anchor("square:0", front, atan2(to_road.x, to_road.y))
		"shelter":
			var hb3 := HouseBuilder.new(self, height)
			hb3.house(Vector3(site.x, height(site.x, site.y) - 0.1, site.y), atan2(to_road.x, to_road.y), 4.6, 4.0, 7100 + _seed % 31, 1)
		"landmark":
			if wid == "the_old_ash":
				var tr := Kit.place_prop(self, "dead_tree_trunk", Kit.xf(c + Vector3(0, -0.2, 0), 0.4, Vector3.ONE * 2.2), "", true)
				tr.name = "OldAsh"
			else:
				var sb := StoneBuilder.new(height, 3300 + _seed % 71)
				sb.pier(c, 1.1, 3.2, atan2(to_road.x, to_road.y), 0.8)
				for k in 5:
					sb.block(Transform3D(Basis(Vector3.UP, k * 1.3), c + Vector3(2.2, 0.18 + k * 0.3, 1.4)), Vector3(0.9 - k * 0.12, 0.32, 0.8 - k * 0.1), 0.4, 0.07)
				sb.finish(self, RealKit.stone_mat("mossy_stone_wall") if RealKit.enabled() else Kit.tri("castle_wall_slates", "1k", 0.45, 0.3), "Landmark")
	if not for_area_people(wid).is_empty():
		town_key = "wayside:" + wid
	add_poi("waypoint_" + wid, c + Vector3(to_road.x, 0, to_road.y) * 5.0, String(waypoint.get("describe", waypoint.get("name", wid))), "the_road", 4.0)
	print("[wayside] waypoint %s (%s) at %s" % [wid, kind, site])


static func for_area_people(wid: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	return d.get("wayside:" + wid, {}) if d is Dictionary else {}


func _links() -> void:
	var title := String(params.get("title", "the road"))
	add_location("the_road", Vector3(0, 0, 0), 150.0, Vector3(CAMP.x, height(CAMP.x, CAMP.y), CAMP.y), "a stretch of %s, about %d km along" % [title, int(float(params.get("km", 0.0)))])
	var from_id := String(params.get("from", "whispering_woods"))
	var to_id := String(params.get("to", "ancient_grove"))
	if WorldState.areas.has(from_id):
		add_gate(from_id, Vector3(ROAD_E.x, height(ROAD_E.x, ROAD_E.y), ROAD_E.y), Vector3(ROAD_E.x - 9, height(ROAD_E.x - 9, ROAD_E.y) + 0.05, ROAD_E.y), PI * 0.5, 3.0)
	if WorldState.areas.has(to_id) and to_id != from_id:
		add_gate(to_id, Vector3(ROAD_W.x, height(ROAD_W.x, ROAD_W.y), ROAD_W.y), Vector3(ROAD_W.x + 9, height(ROAD_W.x + 9, ROAD_W.y) + 0.05, ROAD_W.y), -PI * 0.5, 3.0)
	boundary_box(Vector3(0, 0, 0), Vector3(SIZE - 6, 40, SIZE - 6))
	print("[wayside] %s km %.1f seed %d dressing %s" % [title, float(params.get("km", 0.0)), _seed, dress.stats])


# ------------------------------------------------------------------ time of day
## The light follows the world clock hour by hour (not a day/night switch): the sun climbs and sets across the
## sky, dawn and dusk warm the haze, and after dusk the forest is dark - moonlight, the night sky, and whatever
## fire the travellers make. Keys: [hour, sun energy, sun colour, ambient, exposure, sky energy, fog colour, fog].
# [hour, moon/sun energy, its colour, ambient, exposure, sky energy, fog colour, fog density]. Night is moonlit and
# readable on a stream (QA 2026-10-15: the old night averaged < 12/255 - viewers saw only fireflies)
const LIGHT := [
	[0.0, 0.3, Color(0.5, 0.62, 1.0), 0.2, 1.25, 0.5, Color(0.02, 0.03, 0.055), 0.006],
	[4.6, 0.3, Color(0.5, 0.62, 1.0), 0.2, 1.25, 0.5, Color(0.02, 0.03, 0.055), 0.006],
	[5.6, 0.55, Color(1.0, 0.55, 0.36), 0.15, 1.0, 0.42, Color(0.3, 0.26, 0.28), 0.006],
	[7.0, 1.9, Color(1.0, 0.8, 0.6), 0.27, 0.92, 0.8, Color(0.42, 0.46, 0.44), 0.0045],
	[12.0, 3.1, Color(1.0, 0.92, 0.8), 0.34, 0.88, 0.95, Color(0.45, 0.53, 0.48), 0.0032],
	[16.5, 2.8, Color(1.0, 0.85, 0.64), 0.32, 0.88, 0.9, Color(0.46, 0.5, 0.44), 0.0036],
	[18.6, 1.15, Color(1.0, 0.55, 0.3), 0.2, 0.95, 0.55, Color(0.42, 0.3, 0.24), 0.0045],
	[19.7, 0.32, Color(0.85, 0.42, 0.36), 0.12, 1.0, 0.32, Color(0.12, 0.09, 0.1), 0.0055],
	[20.6, 0.3, Color(0.5, 0.62, 1.0), 0.2, 1.25, 0.5, Color(0.02, 0.03, 0.055), 0.006],
	[24.0, 0.3, Color(0.5, 0.62, 1.0), 0.2, 1.25, 0.5, Color(0.02, 0.03, 0.055), 0.006],
]
var hour_shown := -1.0
var _tod_t := 0.0


func set_night(v: bool) -> void:
	super.set_night(v)
	set_time_of_day(WorldState.hour_f())


func set_time_of_day(h: float) -> void:
	if env == null or sun == null:
		return
	hour_shown = h
	var i := 0
	while i < LIGHT.size() - 2 and h >= float(LIGHT[i + 1][0]):
		i += 1
	var a: Array = LIGHT[i]
	var b: Array = LIGHT[i + 1]
	var k := clampf((h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var night_now := h < 5.1 or h > 20.0
	night = night_now
	sun.light_energy = lerpf(a[1], b[1], k)
	sun.light_color = (a[2] as Color).lerp(b[2], k)
	env.ambient_light_energy = lerpf(a[3], b[3], k)
	env.tonemap_exposure = lerpf(a[4], b[4], k)
	env.background_energy_multiplier = lerpf(a[5], b[5], k)
	env.fog_light_color = (a[6] as Color).lerp(b[6], k)
	env.fog_density = lerpf(a[7], b[7], k)
	env.sky = _sky_night if night_now else _sky_day
	env.ambient_light_sky_contribution = 0.55 if night_now else 0.5
	env.ambient_light_color = Color(0.2, 0.26, 0.42) if night_now else Color(0.6, 0.66, 0.52)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_albedo = Color(0.35, 0.42, 0.6) if night_now else Color(0.9, 0.93, 0.86)
	# the sun's arc (east at dawn, high at noon, west at dusk); at night the "sun" is the moon, high and cold
	if night_now:
		sun.rotation_degrees = Vector3(-48, 120, 0)
	else:
		var t := clampf((h - 5.0) / 15.0, 0.0, 1.0)
		sun.rotation_degrees = Vector3(-lerpf(4.0, 4.0, t) - sin(t * PI) * 52.0, lerpf(70.0, 250.0, t), 0)
	for n in get_tree().get_nodes_in_group("night_lights_" + str(get_instance_id())):
		n.visible = night_now
	for n in get_tree().get_nodes_in_group("day_only_" + str(get_instance_id())):
		n.visible = h > 8.0 and h < 17.0          # light shafts and motes belong to the high sun
	if _shafts.is_empty():
		for n in find_children("*", "MeshInstance3D", true, false):
			var mo := (n as MeshInstance3D).material_override as ShaderMaterial
			if mo and mo.shader and mo.shader.resource_path.contains("light_shaft"):
				_shafts.append(n)
	for n in _shafts:
		if is_instance_valid(n):
			(n as Node3D).visible = h > 8.0 and h < 17.0


var _shafts: Array = []


func _process(delta: float) -> void:
	_tod_t -= delta
	if _tod_t <= 0.0:
		_tod_t = 0.25
		if absf(WorldState.hour_f() - hour_shown) > 0.02:
			set_time_of_day(WorldState.hour_f())


## Where a party arriving on the road from the east (or west) appears: on the road just inside the stretch.
func road_point(t: float) -> Vector3:
	var pts: Array = trails[0][0]
	var total := 0.0
	for i in pts.size() - 1:
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	var want := clampf(t, 0.0, 1.0) * total
	for i in pts.size() - 1:
		var seg := (pts[i] as Vector2).distance_to(pts[i + 1])
		if want <= seg:
			var q: Vector2 = (pts[i] as Vector2).lerp(pts[i + 1], want / seg)
			return Vector3(q.x, height(q.x, q.y), q.y)
		want -= seg
	return Vector3(ROAD_W.x, height(ROAD_W.x, ROAD_W.y), ROAD_W.y)
