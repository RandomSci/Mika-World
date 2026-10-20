class_name Spawner
extends Node
## Keeps a small, bounded population of creatures at the Sanctuary's wild edges (data/monsters.json):
## at most `max_alive`, respawning after a delay, each anchor validated against the navmesh and kept
## outside the ritual circle's ward. The rare Hollow Sentinel only appears after a while and rarely.
## Creatures exist only while the Sanctuary is loaded (they belong to the area, like the travellers).
## Also routes creature attacks to the mages (vigor) and tells each mage's planner about the threat.

signal monster_spawned(m: Monster)
signal monster_defeated(m: Monster, by: String)
signal mage_hit(mage: WorldCharacter, monster: Monster, amount: float)

static var data := {}
static var habitats := {}            # data/habitats.json (Milestone K8)
var territories: Array[Territory] = []

var main: Node
var enabled := true
var alive: Array[Monster] = []
var _next_spawn := 6.0
var _session := 0.0
var _last_rare := -1e9
var _uid := 0
var _rng := RandomNumberGenerator.new()
var log: Array = []


static func load_data() -> Dictionary:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	if habitats.is_empty():
		habitats = JSON.parse_string(FileAccess.get_file_as_string("res://data/habitats.json"))
	return data


func setup(m: Node) -> void:
	main = m
	load_data()
	_rng.seed = int(Time.get_unix_time_from_system())
	enabled = not RenderProfile.options.has("no-monsters")
	main.streaming.transition_started.connect(func(_f, _t): alive.clear(); _clear_territories())
	main.streaming.area_activated.connect(func(a, _r): _build_territories(a))
	if main.get("magic") and main.magic.has_signal("cast_resolved"):
		main.magic.cast_resolved.connect(_on_cast_noise)


func _process(delta: float) -> void:
	_session += delta
	alive = alive.filter(func(x): return is_instance_valid(x) and x.alive())
	# Milestone K8: populations are owned by the area's territories (data/habitats.json); the Sanctuary's old
	# anchors live on as its "sanctuary_edges" habitat


func _pick_kind() -> String:
	var total := 0.0
	var pool := {}
	for k in data.monsters:
		var d: Dictionary = data.monsters[k]
		if d.has("min_session_s") and (_session < float(d.min_session_s) or _session - _last_rare < float(d.get("rare_cooldown_s", 0.0))):
			continue
		pool[k] = float(d.weight)
		total += float(d.weight)
	var r := _rng.randf() * total
	for k in pool:
		r -= pool[k]
		if r <= 0.0:
			return k
	return "gloomwisp"


## Spawn one creature (kind "" = weighted pick) at a valid anchor; `at` overrides (tests). Returns it or null.
func spawn(kind: String = "", at = null) -> Monster:
	if not StreamFlags.fights():
		return null                                   # (go live 20 October: fights off, no creature ever appears)
	alive = alive.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion() and x.alive())
	if kind == "":
		kind = _pick_kind()
	var d: Dictionary = data.monsters.get(kind, {})
	if d.is_empty() or main.world == null:
		return null
	var pos: Vector3
	if at is Vector3:
		pos = at
	else:
		var anchors: Array = data.spawn_anchors.duplicate()
		anchors.shuffle()
		var found := false
		var map: RID = main.world.get_world_3d().navigation_map
		for a in anchors:
			var want := Vector3(a[0], 0, a[1])
			want.y = main.world.ground_at(want.x, want.z) if main.world.has_method("ground_at") else 0.0
			var p := NavigationServer3D.map_get_closest_point(map, want)
			if Vector2(p.x - want.x, p.z - want.z).length() > 2.0 or Vector2(p.x, p.z).length() < float(data.ward_radius) + 3.0:
				continue
			if alive.any(func(x): return x.global_position.distance_to(p) < 6.0):
				continue
			if main.characters.values().any(func(c): return c.visible and c.global_position.distance_to(p) < 10.0):
				continue   # never pop into existence right next to a mage
			pos = p
			found = true
			break
		if not found:
			return null
	_uid += 1
	var m := Monster.new()
	m.name = "Animated_Monster_%s_%d" % [kind, _uid]
	main.world.add_child(m)
	m.setup_monster(main, kind, "%s_%d" % [kind, _uid], pos, d)
	m.attacked.connect(_on_attacked)
	m.defeated.connect(func(mm, by):
		monster_defeated.emit(mm, by)
		log.append({"t": snappedf(_session, 0.1), "event": "defeated", "monster": mm.id, "by": by})
		if mm.territory:
			mm.territory.note_defeat())
	alive.append(m)
	if d.has("min_session_s"):
		_last_rare = _session
	log.append({"t": snappedf(_session, 0.1), "event": "spawned", "monster": m.id, "at": [snappedf(pos.x, 0.1), snappedf(pos.z, 0.1)]})
	if log.size() > 120:
		log.pop_front()
	monster_spawned.emit(m)
	return m


func _on_attacked(m: Monster, mage: WorldCharacter, amount: float) -> void:
	hear(m.global_position, 14.0, "fight")
	var mind := WorldState.mind(mage.character_id)
	mind.vigor = clampf(mind.vigor - amount, 0.0, 1.0)
	mage.set_expression("surprised", 0.8)
	get_tree().create_timer(0.6).timeout.connect(func(): if is_instance_valid(mage): mage.set_expression("surprised", 0.0))
	var away := Vector3(mage.global_position.x - m.global_position.x, 0, mage.global_position.z - m.global_position.z).normalized()
	mage.velocity += away * 2.2
	FX.burst(main.world, mage.global_position + Vector3(0, 1.1, 0), 18, 0.6, FX.pm_motes("water" if m.kind == "gloomwisp" else "fire", "burst"), FX.mote_mesh(0.04))
	if AudioDirector.instance:
		AudioDirector.instance.play3d("mage_hit", mage.global_position + Vector3(0, 1.2, 0), "SFX", -6.0, "mage_hit")
	log.append({"t": snappedf(_session, 0.1), "event": "hit_mage", "monster": m.id, "mage": mage.character_id, "vigor": snappedf(mind.vigor, 0.01)})
	mage_hit.emit(mage, m, amount)


## Creatures a mage can actually perceive: within sight range with a clear line from her eyes, or close
## enough to hear (HEARING_M) even behind a standing stone.
const HEARING_M := 12.0

func perceived_by(c: WorldCharacter, sight := 28.0) -> Array:
	var out := []
	for m in alive:
		if not is_instance_valid(m) or not m.alive():
			continue
		var d := c.global_position.distance_to(m.global_position)
		if d > sight:
			continue
		var q := PhysicsRayQueryParameters3D.create(c.global_position + Vector3(0, 1.5, 0), m.aim_point())
		q.exclude = [c.get_rid()]
		q.collision_mask = 1
		var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or (hit.position as Vector3).distance_to(m.aim_point()) < m.aim_radius + 0.5 or d < HEARING_M:
			out.append(m)
	return out


func describe() -> Dictionary:
	return {"alive": alive.map(func(m): return {"id": m.id, "kind": m.kind, "state": m.mstate, "routine": m.routine, "hp": snappedf(m.hp, 0.1),
		"target": m.target_mage.character_id if m.target_mage and is_instance_valid(m.target_mage) else ""}), "recent": log.slice(maxi(0, log.size() - 8)),
		"territories": territories.map(func(t): return t.describe())}


# ------------------------------------------------------------------ territories (Milestone K8)
func _clear_territories() -> void:
	for t in territories:
		if is_instance_valid(t):
			t.queue_free()
	territories.clear()


func _build_territories(area_id: String) -> void:
	_clear_territories()
	var area_h: Dictionary = habitats.get("areas", {}).get(area_id, {})
	for hid in area_h.get("habitats", {}):
		var t := Territory.new()
		t.setup(self, main, area_id, hid, area_h.habitats[hid], habitats.get("spawn", {}), habitats.get("depletion", {}))
		add_child(t)
		territories.append(t)


func behaviour_of(kind: String) -> Dictionary:
	return habitats.get("species_behaviour", {}).get(kind, {})


func in_safe_zone(area_id: String, p: Vector3) -> bool:
	for z in habitats.get("areas", {}).get(area_id, {}).get("safe_zones", []):
		if Vector2(p.x - z.center[0], p.z - z.center[1]).length() < float(z.radius):
			return true
	return false


func territory_at(p: Vector3) -> Territory:
	for t in territories:
		if t.contains(p):
			return t
	return null


## A noise in the world (spell, running steps, a fight): creatures that can hear it come to look.
func hear(pos: Vector3, loudness: float, kind: String) -> void:
	for t in territories:
		t.hear(pos, loudness, kind)


func _on_cast_noise(res: Dictionary) -> void:
	var c = main.characters.get(String(res.get("caster", "")))
	if c:
		hear((c as Node3D).global_position, 20.0, "spell")
