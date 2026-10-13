class_name Territory
extends Node
## One habitat's living population (Milestone K8, data/habitats.json). A territory decides WHEN and WHERE a
## creature exists: its own population limit and daily rhythm (more out at night for night creatures), respawn
## delays that lengthen after defeats (depletion, persisted per save, recovering over game time), spawn points
## inside the habitat only, never inside a safe zone, never near a mage and never where the camera can see them
## appear (in the frustum with a clear line of sight). It also hands each creature its lair, patrol route, rest
## spots and guard post, which drive the territory behaviour in Monster (patrol / rest / guard / investigate /
## retreat). Noises in the world (spells, running, impacts) reach creatures through `hear()`.

var spawner: Spawner
var main: Node
var area_id := ""
var id := ""
var def := {}
var alive: Array[Monster] = []
var rng := RandomNumberGenerator.new()
var log: Array = []
var _next_spawn := 8.0
var _session := 0.0
var _last_rare := -1e9
var _spawn_cfg := {}
var _depletion := {}


func setup(p_spawner: Spawner, p_main: Node, p_area: String, p_id: String, p_def: Dictionary, spawn_cfg: Dictionary, depletion: Dictionary) -> void:
	spawner = p_spawner
	main = p_main
	area_id = p_area
	id = p_id
	def = p_def
	_spawn_cfg = spawn_cfg
	_depletion = depletion
	name = "Territory_" + id
	rng.seed = hash(area_id + ":" + id) + int(Time.get_unix_time_from_system()) % 100000
	_next_spawn = rng.randf_range(4.0, 10.0)


# ------------------------------------------------------------------ geometry
func center() -> Vector3:
	return Vector3(def.center[0], 0, def.center[1])


func contains(p: Vector3) -> bool:
	return Vector2(p.x - def.center[0], p.z - def.center[1]).length() <= float(def.radius)


func lair_center() -> Vector3:
	if def.get("lair") == null:
		return Vector3.INF
	return Vector3(def.lair.center[0], 0, def.lair.center[1])


func patrol_points() -> Array:
	var out := []
	for p in def.get("patrol", []):
		out.append(Vector3(p[0], 0, p[1]))
	return out


func rest_points() -> Array:
	var out := []
	for p in def.get("rest_spots", []):
		out.append(Vector3(p[0], 0, p[1]))
	if out.is_empty() and def.get("lair") != null:
		out.append(lair_center())
	return out


func guard_post() -> Vector3:
	var g = def.get("guard_post")
	return Vector3(g[0], 0, g[1]) if g != null else Vector3.INF


func perches() -> Array:
	var out := []
	for p in def.get("perches", []):
		out.append(Vector3(p[0], 0, p[1]))
	return out


## Ground height under a flat point (the area's terrain).
func ground(p: Vector3) -> Vector3:
	var w = main.world
	if w and w.has_method("ground_at"):
		return Vector3(p.x, w.ground_at(p.x, p.z), p.z)
	return p


# ------------------------------------------------------------------ population
func active_fraction() -> float:
	var act: Dictionary = def.get("activity", {"day": 1.0, "night": 1.0})
	return float(act.get("night" if WorldState.night else "day", 1.0))


func target_population() -> int:
	var base := int(def.max_alive) + (int(def.get("night_bonus", 0)) if WorldState.night else 0)
	return int(round(base * active_fraction()))


## Persisted depletion: each defeat lengthens the respawn for a while; the territory recovers over game time.
func state() -> Dictionary:
	var all: Dictionary = WorldState.habitats
	if not all.has(area_id):
		all[area_id] = {}
	if not all[area_id].has(id):
		all[area_id][id] = {"defeats": 0, "depleted_until": 0.0, "last_defeat": 0.0}
	return all[area_id][id]


func depletion_factor() -> float:
	var st := state()
	var left: float = float(st.depleted_until) - WorldState.game_time()
	if left <= 0.0:
		return 1.0
	var max_f := 1.0 / maxf(float(_depletion.get("max_factor", 0.2)), 0.05)
	return clampf(1.0 + left / float(_depletion.get("recover_s", 1800.0)) * (max_f - 1.0), 1.0, max_f)


func note_defeat() -> void:
	var st := state()
	st.defeats = int(st.defeats) + 1
	st.last_defeat = WorldState.game_time()
	st.depleted_until = maxf(float(st.depleted_until), WorldState.game_time()) + float(_depletion.get("per_defeat_s", 420.0))
	_note("defeat", {"defeats": st.defeats, "depleted_for_s": snappedf(float(st.depleted_until) - WorldState.game_time(), 1.0)})


func respawn_delay() -> float:
	var r: Array = def.respawn_s
	return rng.randf_range(float(r[0]), float(r[1])) * depletion_factor()


func _process(delta: float) -> void:
	_session += delta
	alive = alive.filter(func(x): return is_instance_valid(x) and x.alive())
	if spawner == null or not spawner.enabled or main.world == null or main.streaming.state != "idle" or main.streaming.current_id != area_id:
		return
	_next_spawn -= delta
	if _next_spawn <= 0.0:
		_next_spawn = respawn_delay() if alive.size() + 1 >= target_population() else rng.randf_range(6.0, 14.0)
		if alive.size() < target_population() and spawner.alive.size() < int(spawner.data.get("max_alive_world", 6)):
			try_spawn()


func pick_kind() -> String:
	var total := 0.0
	var pool := {}
	for k in def.species:
		var md: Dictionary = spawner.data.monsters.get(k, {})
		if md.is_empty():
			continue
		if md.has("min_session_s") and (_session < float(md.min_session_s) or _session - _last_rare < float(md.get("rare_cooldown_s", 0.0))):
			continue
		pool[k] = float(def.species[k])
		total += float(def.species[k])
	if pool.is_empty():
		return ""
	var r := rng.randf() * total
	for k in pool:
		r -= pool[k]
		if r <= 0.0:
			return k
	return pool.keys()[0]


## A valid, unseen spawn point inside the habitat (or null).
func find_spawn_point(kind: String) -> Variant:
	var map: RID = main.world.get_world_3d().navigation_map
	var cam: Camera3D = get_viewport().get_camera_3d()
	var beh: Dictionary = spawner.behaviour_of(kind)
	var flyer := String(beh.get("style", "ground")) == "flyer"
	var lair := lair_center()
	for attempt in 24:
		var p: Vector3
		# a resting-rhythm creature appears at (or near) its lair; others anywhere in the territory
		if lair != Vector3.INF and (not active_now(kind) or rng.randf() < 0.4):
			p = lair + Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-2.0, 2.0))
		else:
			var ang := rng.randf() * TAU
			var rr := sqrt(rng.randf()) * float(def.radius) * 0.9
			p = center() + Vector3(cos(ang) * rr, 0, sin(ang) * rr)
		p = ground(p)
		if not flyer:
			var np := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(np.x - p.x, np.z - p.z).length() > 2.0:
				continue
			p = np
		if spawner.in_safe_zone(area_id, p):
			continue
		var too_close := false
		for c in main.characters.values():
			var wc := c as WorldCharacter
			if wc and wc.visible and wc.global_position.distance_to(p) < float(_spawn_cfg.get("min_mage_distance", 14.0)):
				too_close = true
		if too_close:
			continue
		if alive.any(func(x): return x.global_position.distance_to(p) < 4.0):
			continue
		if cam and _camera_sees(cam, p + Vector3(0, 0.8, 0)):
			continue
		return p
	return null


## Would the camera watch it appear? In the frustum (with a margin), nearer than the spawn distance, and with a
## clear line of sight (trees and rocks may hide a spawn that is technically in frame).
func _camera_sees(cam: Camera3D, p: Vector3) -> bool:
	var d := cam.global_position.distance_to(p)
	if d < 10.0:
		return true
	if d > float(_spawn_cfg.get("min_camera_distance", 28.0)) * 2.2:
		return false
	if not cam.is_position_in_frustum(p):
		# a margin: just outside the frame still counts as seen when the camera is turning
		var to := (p - cam.global_position).normalized()
		var fwd := -cam.global_transform.basis.z
		var ang := rad_to_deg(acos(clampf(to.dot(fwd), -1.0, 1.0)))
		var half := cam.fov * 0.5 * 1.35 + float(_spawn_cfg.get("frustum_margin_deg", 8.0))
		if ang > half:
			return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, p)
	q.collision_mask = 1 | 4
	var hit: Dictionary = main.world.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(p) < 1.0


func active_now(kind: String) -> bool:
	var beh: Dictionary = spawner.behaviour_of(kind)
	match String(beh.get("rhythm", "any")):
		"night": return WorldState.night
		"day": return not WorldState.night
	return true


func try_spawn() -> Monster:
	var kind := pick_kind()
	if kind == "":
		return null
	var p = find_spawn_point(kind)
	if p == null:
		_note("no_spot", {"kind": kind})
		return null
	var m: Monster = spawner.spawn(kind, p)
	if m == null:
		return null
	m.territory = self
	m.home = p
	m.begin_territory_life(active_now(kind))
	alive.append(m)
	if spawner.data.monsters[kind].has("min_session_s"):
		_last_rare = _session
	_note("spawned", {"kind": kind, "at": [snappedf(p.x, 0.1), snappedf(p.z, 0.1)], "active": active_now(kind), "pop": alive.size(), "target": target_population()})
	return m


## A noise reaches the creatures that can hear it (loudness in metres, scaled by the habitat's hearing).
func hear(pos: Vector3, loudness: float, kind: String) -> void:
	for m in alive:
		if not is_instance_valid(m) or not m.alive():
			continue
		var beh: Dictionary = spawner.behaviour_of(m.kind)
		var reach := loudness * float(beh.get("investigate_radius", 1.0)) * (float(def.get("hearing", 18.0)) / 18.0)
		if kind == "spell" and bool(beh.get("drawn_to_magic", false)):
			reach *= 1.5
		if m.global_position.distance_to(pos) <= reach:
			m.on_noise(pos, kind)


func _note(event: String, detail := {}) -> void:
	var e := {"t": snappedf(_session, 0.1), "event": event, "habitat": id}
	e.merge(detail)
	log.append(e)
	if log.size() > 80:
		log.pop_front()


func describe() -> Dictionary:
	return {"habitat": id, "label": def.get("label", id), "alive": alive.size(), "target": target_population(),
		"active_fraction": active_fraction(), "depletion": snappedf(depletion_factor(), 0.01), "defeats": state().defeats,
		"creatures": alive.map(func(m): return {"kind": m.kind, "state": m.mstate, "at": [snappedf(m.global_position.x, 0.1), snappedf(m.global_position.z, 0.1)]})}
