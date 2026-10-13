class_name ExplorationMap
extends RefCounted
## Spatial curiosity for one mage (her own map, saved in her mind as mind.explored). Instead of walking
## between the known activity spots, she can pick a place she has NOT been to that she can actually see:
##   1. candidates are sampled on the REAL navigation mesh (always walkable: no walls, no water, no void);
##   2. only candidates she can perceive now: a clear line from her eyes, or very close;
##   3. each is scored: novelty (her coverage grid) + what is perceivably there (a cluster of rocks/props,
##      a change of elevation, water she can see) + her personal taste - distance - recently walked routes;
##   4. she walks there through normal navigation, looks around at what is there, and remembers the spot.
## Off-path = more than OFF_PATH_M from every known activity spot / point of interest / sub-area centre.
## Only feature-rich spots count as a "place" worth remembering (small first-visit XP), so wandering over
## empty grass cannot be farmed.

const CELL := 8.0                # coverage grid (metres)
const SAMPLES := 28
const SIGHT := 34.0
const OFF_PATH_M := 6.0

var main: Node
var mage: WorldCharacter
var mind: MageMind
var prefs := {}                  # feature -> weight (her taste), from data/mages.json "explore_taste"


func _init(p_main: Node, p_mage: WorldCharacter, p_mind: MageMind, p_prefs: Dictionary) -> void:
	main = p_main
	mage = p_mage
	mind = p_mind
	prefs = p_prefs


func area() -> String:
	return String(main.streaming.current_id)


static func cell_key(p: Vector3) -> String:
	return "%d,%d" % [int(floor(p.x / CELL)), int(floor(p.z / CELL))]


func grid() -> Dictionary:
	return mind.explored.get_or_add(area(), {})


## Mark the cell she is standing in (called about once a second while she is in view).
func mark(p: Vector3) -> void:
	var g := grid()
	g[cell_key(p)] = int(Time.get_unix_time_from_system())


func coverage() -> float:
	return float(grid().size())


## Up to `n` candidate destinations, best first: {pos, score, novelty, features:{...}, off_path, describe}.
func candidates(n := 3) -> Array:
	if main.world == null:
		return []
	var map := mage.get_world_3d().navigation_map
	var eyes := mage.global_position + Vector3(0, 1.55, 0)
	var space := mage.get_world_3d().direct_space_state
	var out := []
	var g := grid()
	var now := Time.get_unix_time_from_system()
	for i in SAMPLES:
		var p := NavigationServer3D.map_get_random_point(map, 1, true)
		var d := p.distance_to(mage.global_position)
		if d < 7.0 or d > SIGHT:
			continue
		# perceivable: a clear line from her eyes to the spot (or it is close)
		var q := PhysicsRayQueryParameters3D.create(eyes, p + Vector3(0, 0.8, 0))
		q.exclude = [mage.get_rid()]
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.position as Vector3).distance_to(p) > 2.0 and d > 12.0:
			continue
		var last := float(g.get(cell_key(p), 0))
		var novelty := 1.0 if last == 0.0 else clampf((now - last) / 3600.0, 0.0, 0.5)
		if novelty <= 0.05:
			continue
		var f := features(p)
		var interest: float = f.props * 0.12 + f.relief * 0.5 + (0.6 if f.water else 0.0)
		var taste := 0.0
		for k in prefs:
			if k == "relief":
				taste += float(prefs[k]) * f.relief
			elif k == "water" and f.water:
				taste += float(prefs[k])
			elif k == "props":
				taste += float(prefs[k]) * minf(f.props, 6.0) / 6.0
		var off := off_path(p)
		var score := novelty * 1.0 + minf(interest, 1.2) * 0.6 + taste * 0.4 - d * 0.012 + (0.2 if off else 0.0)
		out.append({"pos": p, "score": snappedf(score, 0.01), "novelty": snappedf(novelty, 0.01), "features": f, "off_path": off,
			"distance": snappedf(d, 0.1), "describe": describe(p, f)})
	out.sort_custom(func(a, b): return a.score > b.score)
	return out.slice(0, n)


## What is perceivably at a spot: solid things around it, how uneven the ground is, visible water.
func features(p: Vector3) -> Dictionary:
	var space := mage.get_world_3d().direct_space_state
	var sq := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 3.5
	sq.shape = sph
	sq.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.0, 0))
	sq.collision_mask = 1
	var props := 0
	var names := {}
	for h in space.intersect_shape(sq, 16):
		var col = h.collider
		if col is StaticBody3D and not (col as Node).is_in_group("cat_terrain"):
			props += 1
			names[String((col as Node).name).get_slice("_", 0).to_lower()] = true
	var relief := 0.0
	if main.world.has_method("ground_at"):
		var hs := []
		for a in 6:
			var o := Vector3(cos(a * TAU / 6.0), 0, sin(a * TAU / 6.0)) * 3.0
			hs.append(float(main.world.ground_at(p.x + o.x, p.z + o.z)))
		relief = clampf((hs.max() - hs.min()) / 2.0, 0.0, 1.0)
	var water := false
	for r in main.magic.reactives().values():
		if (r as ReactiveElement).kind == "water" and (r as ReactiveElement).global_position.distance_to(p) < 9.0:
			water = true
	return {"props": props, "relief": snappedf(relief, 0.01), "water": water, "things": names.keys().slice(0, 4)}


func off_path(p: Vector3) -> bool:
	for id in main.world.points_of_interest:
		if (main.world.points_of_interest[id].position as Vector3).distance_to(p) < OFF_PATH_M:
			return false
	for id in main.world.interactables:
		if (main.world.interactables[id] as Node3D).global_position.distance_to(p) < OFF_PATH_M:
			return false
	for sid in WorldState.sanctuary.get("sub_areas", {}):
		var c: Array = WorldState.sanctuary.sub_areas[sid].center
		if area() == "sanctuary" and Vector2(p.x - float(c[0]), p.z - float(c[2])).length() < OFF_PATH_M:
			return false
	return true


func describe(p: Vector3, f: Dictionary) -> String:
	var where := ""
	var best := 1e9
	for sid in WorldState.sanctuary.get("sub_areas", {}):
		var c: Array = WorldState.sanctuary.sub_areas[sid].center
		var d := Vector2(p.x - float(c[0]), p.z - float(c[2])).length()
		if d < best:
			best = d
			where = String(WorldState.sanctuary.sub_areas[sid].name)
	var what := "an unfamiliar patch of ground"
	if f.water:
		what = "the water's edge"
	elif f.relief > 0.5:
		what = "a rise in the ground"
	elif f.props >= 3:
		what = "a cluster of rocks and old stones"
	elif f.props >= 1:
		what = "something half-hidden in the grass"
	return "%s beyond the %s" % [what, where] if area() == "sanctuary" and where != "" else what


## Worth remembering as a place (first visit pays a little): something is actually there.
static func notable(f: Dictionary) -> bool:
	return f.props >= 2 or f.relief > 0.45 or f.water
