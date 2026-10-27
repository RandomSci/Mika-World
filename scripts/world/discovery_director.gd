class_name DiscoveryDirector
extends Node
## Day 3: dynamic discoveries. Nothing is placed in advance: about once an hour on average (more off the paths, in an
## unexplored corner, in a newly reached area, at night, in rain, while she is lost; less on the home dais) the
## director decides that the mage the camera follows comes across something. It rolls a rarity (common 60 %,
## uncommon 28 %, rare 10 %, legendary 2 %), picks a find for the region she is in from data/discovery_pool.json
## (never the same kind twice in a row; a long memory keeps them fresh; one-off finds come once ever; the Phoenix
## path's clues only in order), and sets the real thing down a few metres from her, off the path, on walkable ground:
## a prop and an interactable. She notices it (a line, a look), walks over and examines it (her planner's top option),
## the reward is applied (WorldState.record_activity - "discover:" activities also start the mages' talk about it),
## both mages react, the overlay notes it, and it is saved: the place stays in the world and can be revisited.

signal found(entry: Dictionary)
signal moment(kind: String, who: String)       # an emotional beat for the camera (part 1's close-up trigger)

const LIVE_EXPIRE_S := 480.0        # a find nobody went to fades after 8 minutes
const SPAWN_MIN_M := 6.0
const SPAWN_MAX_M := 15.0

var main: Node
var pool := {}
var rng := RandomNumberGenerator.new()
var live := {}                      # the find waiting in the world right now
var forced := ""                    # tests: a template id to place at the next chance
var enabled := true
var _acc := 0.0
var _area_since := {}               # area -> ticks when she arrived (the "newly reached" boost)


func setup(m: Node) -> void:
	main = m
	name = "DiscoveryDirector"
	pool = DiscoveryRules.load_pool()
	rng.randomize()
	process_mode = Node.PROCESS_MODE_PAUSABLE


func state() -> Dictionary:
	var st: Dictionary = WorldState.finds
	for k in {"log": [], "seq": 0, "since_min": 0.0, "last_kind": ""}.keys():
		if not st.has(k):
			st[k] = {"log": [], "seq": 0, "since_min": 0.0, "last_kind": ""}[k]
	return st


# ------------------------------------------------------------------ live
func _process(delta: float) -> void:
	_acc += delta
	if _acc < 5.0:
		return
	var dt := _acc
	_acc = 0.0
	if main == null or main.world == null:
		return
	var area := String(main.streaming.current_id)
	if not _area_since.has(area):
		_area_since = {area: Time.get_ticks_msec()}
	var st := state()
	if not live.is_empty():
		_check_live()
		return
	if not enabled:
		return
	st.since_min = float(st.since_min) + dt / 60.0
	var who := lead()
	if who == "" or not eligible(who):
		return
	var ctx := context(who)
	var r := DiscoveryRules.rate_per_min(pool, ctx, float(st.since_min))
	if forced != "" or rng.randf() < 1.0 - exp(-r * dt / 60.0):
		spawn(who, ctx)


## The mage the camera follows (the find happens to her, where viewers are looking).
func lead() -> String:
	for w in main.mage_brains:
		var b: SanctuaryBrain = main.mage_brains[w]
		if b.enabled and b.is_foreground() and (main.characters[w] as WorldCharacter).visible:
			return w
	return ""


func eligible(who: String) -> bool:
	var b: SanctuaryBrain = main.mage_brains[who]
	if b.threat != null or b.hold:
		return false
	if main.get("performance") and main.performance.busy():
		return false
	if main.streaming.get("transitioning") == true:
		return false
	return true


func context(who: String) -> Dictionary:
	var c: WorldCharacter = main.characters[who]
	var b: SanctuaryBrain = main.mage_brains[who]
	var area := String(main.streaming.current_id)
	var visits := int(WorldState.visited_locations.get(area, 0))
	var arrived := float(_area_since.get(area, Time.get_ticks_msec()))
	var ctx := {
		"area": area, "region": String(WorldState.areas.get(area, {}).get("region", "")),
		"off_path": b.explore_map.off_path(c.global_position) if b.explore_map else false,
		"unexplored": b.explore_map.grid().size() < 40 if b.explore_map else false,
		"new_area": area != "sanctuary" and (visits <= 2 or Time.get_ticks_msec() - arrived < 600000.0),
		"night": main.day_night != null and main.day_night.k > 0.5,
		"rain": main.weather != null and main.weather.rain > 0.3,
		"home_core": area == "sanctuary" and Vector2(c.global_position.x, c.global_position.z).length() < 14.0,
		"lost": bool(b.get("lost")),
	}
	return ctx


## Put a find down near her. Returns the live record, or {} when nothing fit / no clear spot.
func spawn(who: String, ctx := {}) -> Dictionary:
	if ctx.is_empty():
		ctx = context(who)
	var st := state()
	var f := DiscoveryRules.pick(pool, String(ctx.region), DiscoveryRules.roll_tier(pool, rng), st, WorldState.mind(who).knowledge, rng, forced)
	if f.is_empty():
		return {}
	var c: WorldCharacter = main.characters[who]
	var spot = _spot(c)
	if spot == null:
		return {}
	forced = ""
	var kd: Dictionary = pool.kind_defaults.get(String(f.kind), {})
	var area := main.world as Node3D
	var local: Vector3 = area.to_local(spot)
	var seq := int(st.seq) + 1
	var holder := Node3D.new()
	holder.name = "Find_%d" % seq
	area.add_child(holder)
	var top := _build(holder, String(f.get("prop", kd.get("prop", "stele"))), local, rng.randf_range(0.0, TAU), f)
	var effects: Dictionary = f.get("reward", {}).duplicate(true)
	effects.get_or_add("knowledge", {})["find:" + String(f.id)] = 1
	var it := Interactable.make("discover:%d:%s" % [seq, f.id], String(f.label).capitalize(), String(kd.get("verb", "inspect")),
		"", local, effects, String(kd.get("gesture", "")),
		float(kd.get("duration", 6.0)))
	it.kind = "discovery"
	it.repeatable = false
	it.radius = 1.6
	it.face_point = top
	area.add_interactable(it)
	live = {"seq": seq, "find": f, "it": it, "holder": holder, "area": String(main.streaming.current_id), "who": who,
		"pos": spot, "local": local, "t0": Time.get_ticks_msec(), "ctx": ctx}
	# she notices it: a look, a beat of surprise, a word
	c.look_head_at(spot + Vector3(0, 0.6, 0))
	if c.face:
		c.face.pulse("surprised", 0.8, 1.0)
	_say(who, kd.get("notice", {}).get(who, []))
	(main.mage_brains[who] as SanctuaryBrain).interrupt("discovery")      # an errand walk breaks off; real work finishes first
	print("[discovery] %s noticed %s (%s, %s) %.1f m away in %s %s" % [who, f.id, f.tier, f.kind, c.global_position.distance_to(spot), live.area, str(ctx)])
	return live


func _check_live() -> void:
	var gone: bool = not is_instance_valid(live.get("it")) or String(main.streaming.current_id) != String(live.area)
	if gone or Time.get_ticks_msec() - int(live.t0) > LIVE_EXPIRE_S * 1000.0:
		if not gone and is_instance_valid(live.it) and (live.it as Interactable).busy:
			return
		print("[discovery] %s faded unseen" % live.find.id)
		if is_instance_valid(live.get("it")):
			main.world.interactables.erase((live.it as Interactable).id)
			(live.it as Node).queue_free()
		if is_instance_valid(live.get("holder")):
			(live.holder as Node).queue_free()
		live = {}


## Called by the planner after she examined it (the interactable's own result).
func on_found(who: String, res: Dictionary) -> Dictionary:
	if live.is_empty() or not res.get("ok", false):
		return {}
	var f: Dictionary = live.find
	var st := state()
	var l: Vector3 = live.local
	var entry := {"seq": int(live.seq), "id": String(f.id), "kind": String(f.kind), "tier": String(f.tier), "label": String(f.label),
		"area": String(live.area), "region": String(live.ctx.get("region", "")), "pos": [snappedf(l.x, 0.01), snappedf(l.y, 0.01), snappedf(l.z, 0.01)],
		"unix": int(Time.get_unix_time_from_system()), "world_min": WorldState.world_min, "who": who, "reward": f.get("reward", {}),
		"context": (live.ctx as Dictionary).keys().filter(func(k): return live.ctx[k] is bool and live.ctx[k])}
	st.seq = int(live.seq)
	(st.log as Array).append(entry)
	st.last_kind = String(f.kind)
	st.since_min = 0.0
	# the place stays: from now on it is somewhere to come back to
	var it: Interactable = live.it
	if is_instance_valid(it):
		_make_revisit(it, entry)
	live = {}
	_react(who, entry)
	WorldState.save_game("discovery")
	found.emit(entry)
	moment.emit("discovery", who)
	print("[discovery] FOUND %s" % JSON.stringify(entry))
	return entry


func _react(who: String, e: Dictionary) -> void:
	var kd: Dictionary = pool.kind_defaults.get(e.kind, {})
	var c: WorldCharacter = main.characters[who]
	if c.face:
		c.face.pulse("excited" if e.tier in ["rare", "legendary"] else "happy", 1.0, 2.5)
	_say(who, kd.get("react", {}).get(who, []))
	var name_who := MagicSystem.display_name(who)
	var tier_txt: String = {"common": "", "uncommon": " (uncommon)", "rare": " (rare!)", "legendary": " (LEGENDARY)"}.get(e.tier, "")
	if main.get("overlay_ui"):
		main.overlay_ui.note("%s found %s%s" % [name_who, e.label, tier_txt])
	for w in main.characters:
		if w == who:
			continue
		var o: WorldCharacter = main.characters[w]
		if not o.visible or o.global_position.distance_to(c.global_position) > 30.0:
			continue
		o.look_head_at(main.world.to_global(Vector3(e.pos[0], e.pos[1], e.pos[2])) + Vector3(0, 0.6, 0))
		if o.face:
			o.face.pulse("surprised", 0.7, 0.8)
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(o) and o.face:
				o.face.pulse("happy", 0.8, 2.0)
			_say(w, kd.get("react", {}).get(w, [])))


func _say(who: String, lines: Array) -> void:
	if lines.is_empty() or main.get("voice") == null:
		return
	var b: SanctuaryBrain = main.mage_brains.get(who)
	var voice: String = b.call("_voice") if b else who
	main.voice.say(voice, String(lines[rng.randi() % lines.size()]), {})


## Past finds in this area come back as places to revisit (called when an area opens, behind the travel card).
func restore(area: Node) -> int:
	if area == null or area.has_meta("finds_restored"):
		return 0
	area.set_meta("finds_restored", true)
	var id := String(area.get("area_id"))
	var n := 0
	for e in (state().log as Array).slice(-60):
		if String(e.get("area", "")) != id:
			continue
		var f := _template(String(e.id))
		var kd: Dictionary = pool.kind_defaults.get(String(e.kind), {})
		var p := Vector3(e.pos[0], e.pos[1], e.pos[2])
		var holder := Node3D.new()
		holder.name = "Find_%d" % int(e.seq)
		area.add_child(holder)
		var top := _build(holder, String(f.get("prop", kd.get("prop", "stele"))), p, float(int(e.seq) % 7), f)
		var it := Interactable.make("revisit:%d:%s" % [int(e.seq), e.id], "Revisit " + String(e.label), "revisit", "", p, {}, "", 6.0)
		_make_revisit(it, e)
		it.face_point = top
		area.add_interactable(it)
		n += 1
	if n > 0:
		print("[discovery] %s: %d past finds to revisit" % [id, n])
		area.set_meta("props_after_bake", true)
	return n


func _make_revisit(it: Interactable, e: Dictionary) -> void:
	it.kind = "revisit"
	it.repeatable = true
	it.verb = "revisit"
	it.label = "Revisit " + String(e.label)
	it.effects = {"knowledge": {"revisit:" + String(e.id): 1}}
	it.duration = 6.0
	it.gesture = "look_around"


func _template(id: String) -> Dictionary:
	for f in pool.get("finds", []):
		if String(f.id) == id:
			return f
	return {}


## Revisit candidates in the current area (for the planner).
func revisits() -> Array:
	var out := []
	if main.world == null:
		return out
	for id in main.world.interactables:
		var it = main.world.interactables[id]
		if is_instance_valid(it) and (it as Interactable).kind == "revisit":
			out.append(it)
	return out


## A walkable, clear spot 6-15 m from her, off the path where possible, ahead of her rather than behind.
func _spot(c: WorldCharacter):
	var map: RID = c.get_world_3d().navigation_map
	var space := c.get_world_3d().direct_space_state
	var fwd := -c.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var b: SanctuaryBrain = main.mage_brains[c.character_id]
	var best = null
	var best_s := -1e9
	for i in 24:
		var ang := rng.randf_range(-1.9, 1.9)
		var want := c.global_position + fwd.rotated(Vector3.UP, ang) * rng.randf_range(SPAWN_MIN_M, SPAWN_MAX_M)
		var p := NavigationServer3D.map_get_closest_point(map, want)
		if p.distance_to(Vector3(want.x, p.y, want.z)) > 1.5 or absf(p.y - c.global_position.y) > 3.0:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.4, 1.6, 1.4)
		q.shape = sh
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.0, 0))
		q.collision_mask = 1
		var hits := space.intersect_shape(q, 4).filter(func(h): return not (h.collider is CharacterBody3D))
		if not hits.is_empty():
			continue
		var crowded := false
		for id in main.world.interactables:
			var it = main.world.interactables[id]
			if is_instance_valid(it) and (it as Node3D).global_position.distance_to(p) < 3.5:
				crowded = true
		if crowded:
			continue
		var s := 0.0
		if b.explore_map and b.explore_map.off_path(p):
			s += 1.0
		s -= absf(ang) * 0.2
		s += rng.randf() * 0.3
		if s > best_s:
			best_s = s
			best = p
	return best


# ------------------------------------------------------------------ props (area-local, under `holder`)
func _build(holder: Node3D, kind: String, p: Vector3, yaw: float, f: Dictionary) -> Vector3:
	var area := holder.get_parent()
	var col: Array = f.get("color", [1.0, 0.85, 0.6])
	var glow := Color(float(col[0]), float(col[1]), float(col[2]))
	match kind:
		"stele", "cairn", "shrine", "crates", "lantern":
			var before := area.get_child_count()
			var top: Vector3 = Discoveries._prop(area, kind, p, yaw)
			_adopt(area, holder, before)
			return top
		"plant":
			for i in 5:
				var a := TAU * i / 5.0 + yaw
				var r := 0.18 + 0.12 * float(i % 2)
				var stem := p + Vector3(cos(a) * r, 0, sin(a) * r)
				var h := 0.28 + 0.08 * float(i % 3)
				_glow_box(holder, Vector3(0.025, h, 0.025), stem + Vector3(0, h * 0.5, 0), Color(0.25, 0.5, 0.25), 0.0)
				_glow_sphere(holder, 0.07, stem + Vector3(0, h + 0.04, 0), glow, 2.2)
			_light(holder, p + Vector3(0, 0.5, 0), glow, 0.7, 3.0)
			return p + Vector3(0, 0.3, 0)
		"wisp":
			var orb := _glow_sphere(holder, 0.16, p + Vector3(0, 1.3, 0), glow, 4.0)
			_light(holder, p + Vector3(0, 1.3, 0), glow, 1.2, 5.0)
			var tw := orb.create_tween().set_loops()
			tw.tween_property(orb, "position:y", orb.position.y + 0.25, 1.6).set_trans(Tween.TRANS_SINE)
			tw.tween_property(orb, "position:y", orb.position.y, 1.6).set_trans(Tween.TRANS_SINE)
			Kit.static_box(holder, Vector3(0.6, 0.2, 0.6), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.1, 0)))
			return p + Vector3(0, 1.3, 0)
		"glint":
			_glow_sphere(holder, 0.05, p + Vector3(0, 0.05, 0), Color(1.0, 0.92, 0.6), 6.0)
			_light(holder, p + Vector3(0, 0.3, 0), Color(1.0, 0.9, 0.6), 0.6, 2.0)
			_glow_box(holder, Vector3(0.5, 0.08, 0.4), p + Vector3(0, 0.04, 0), Color(0.4, 0.36, 0.3), 0.0)
			return p + Vector3(0, 0.1, 0)
		"lair":
			var stone: Material = Kit.tri("castle_wall_slates", "1k", 0.6, 0.1, Color(0.55, 0.5, 0.45))
			for i in 6:
				var a := TAU * i / 6.0 + yaw
				Kit.block(holder, Vector3(0.5, 0.35 + 0.1 * float(i % 2), 0.45), Transform3D(Basis(Vector3.UP, a), p + Vector3(cos(a), 0.18, sin(a)) * Vector3(0.9, 1, 0.9)), stone, i % 2 == 0, 0.06)
			_glow_box(holder, Vector3(1.0, 0.04, 1.0), p + Vector3(0, 0.02, 0), Color(0.3, 0.24, 0.16), 0.0)
			return p + Vector3(0, 0.3, 0)
		"vista":
			var stone2: Material = Kit.tri("castle_wall_slates", "1k", 0.6, 0.1, Color(0.7, 0.68, 0.64))
			Kit.block(holder, Vector3(1.3, 0.42, 0.6), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0.21, 0)), stone2, true, 0.08)
			return p + Vector3(0, 0.5, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, -2.0)
		"cleft":
			var stone3: Material = Kit.tri("castle_wall_slates", "1k", 0.6, 0.1, Color(0.5, 0.48, 0.45))
			var bb := Basis(Vector3.UP, yaw)
			Kit.block(holder, Vector3(0.5, 2.0, 0.6), Transform3D(bb, p + bb * Vector3(-0.75, 1.0, 0)), stone3, true, 0.08)
			Kit.block(holder, Vector3(0.5, 2.2, 0.6), Transform3D(bb, p + bb * Vector3(0.75, 1.1, 0)), stone3, true, 0.08)
			Kit.block(holder, Vector3(2.0, 0.45, 0.7), Transform3D(bb, p + bb * Vector3(0, 2.3, 0)), stone3, true, 0.08)
			_glow_box(holder, Vector3(1.0, 1.9, 0.05), p + bb * Vector3(0, 0.95, 0.3), Color(0.05, 0.05, 0.07), 0.0)
			_light(holder, p + bb * Vector3(0, 1.0, 0.6), glow, 0.5, 3.0)
			return p + Vector3(0, 1.0, 0)
	return Discoveries._prop(area, "stele", p, yaw)


func _adopt(area: Node, holder: Node3D, before: int) -> void:
	var kids := area.get_children().slice(before)
	for k in kids:
		if k == holder:
			continue
		k.reparent(holder, true)


func _glow_sphere(parent: Node3D, r: float, p: Vector3, col: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = energy > 0.0
	mat.emission = col
	mat.emission_energy_multiplier = energy
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = p
	parent.add_child(mi)
	return mi


func _glow_box(parent: Node3D, size: Vector3, p: Vector3, col: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = energy > 0.0
	mat.emission = col
	mat.emission_energy_multiplier = energy
	mi.material_override = mat
	mi.position = p
	parent.add_child(mi)
	return mi


func _light(parent: Node3D, p: Vector3, col: Color, energy: float, rng_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.shadow_enabled = false
	l.position = p
	parent.add_child(l)
	return l
