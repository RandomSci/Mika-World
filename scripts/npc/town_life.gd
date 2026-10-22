class_name TownLife
extends Node
## The people who live in the towns (data/residents.json; docs/TOWN_LIFE.md). When an area with residents
## becomes active (the Village, the Academy) each resident is placed where their own day puts them at this hour -
## at work, at the market, on the square, inside their house at night - and lives on from there (Resident). Nothing
## is simulated while an area is not loaded: a person's place follows from their schedule and the clock alone, so
## there is no off-screen cost and no drift. Several people at one place stand round it (spot_for), not in one
## another. The mages are noticed: a nod as she passes, now and then a word in the resident's own voice (once a day
## each; one voice at a time across the town), remembered in WorldState.npc_state.

const SPEAK_GAP_S := 20.0

var main: Node
var residents := {}                 # id -> Resident (the loaded area's)
var area_id := ""
var data := {}
var enabled := true
var _speak_t := -999.0
var _scan := 0.0
var sparks := 0


func setup(m: Node) -> void:
	main = m
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	if RenderProfile.options.has("no-residents"):
		enabled = false


func for_area(id: String) -> Dictionary:
	return data.get(id, {}) if data.get(id, {}) is Dictionary else {}


## Behind the travel card (WorldStreamingManager.before_reveal): the new area's people are made one a frame and
## placed before the card lifts. Made after the reveal, all at once, the village's five cost two 130 ms frames in
## view (22 Oct world trip).
var _prepared := ""


func prepare(id: String) -> void:
	# their models load on the loader's thread first (loaded in the frame they appear, the village's five held a
	# 0.9 s frame in view, 22 Oct)
	var key := id
	if main.world and "town_key" in main.world and String(main.world.town_key) != "":
		key = String(main.world.town_key)
	var paths := []
	for rid in for_area(key):
		var mp := String((for_area(key)[rid] as Dictionary).get("model", ""))
		if mp != "" and not paths.has(mp) and ResourceLoader.load_threaded_request(mp) == OK:
			paths.append(mp)
	var t0 := Time.get_ticks_msec()
	while paths.any(func(p): return ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS) and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	var held := paths.map(func(p): return ResourceLoader.load_threaded_get(p))     # (cached now: load() finds them)
	await area_activated(id, true)
	held.clear()
	_prepared = id


## The area changed: the old town's people stay behind (freed with it), the new one's step into their day.
func area_activated(id: String, staggered := false) -> void:
	if _prepared == id and not staggered:
		_prepared = ""
		return                        # (already there: prepared behind the travel card)
	_prepared = ""
	clear()
	area_id = id
	if not enabled:
		return
	# a stretch of road can hold a hamlet or an inn: its people are "wayside:<waypoint id>"
	var key := id
	if main.world and "town_key" in main.world and String(main.world.town_key) != "":
		key = String(main.world.town_key)
	var people := for_area(key)
	if people.is_empty() or main.world == null or not ("anchors" in main.world) or (main.world.anchors as Dictionary).is_empty():
		return
	for rid in people:
		var r := Resident.new()
		main.world.add_child(r)
		r.setup(String(rid), people[rid], self, main.world)
		residents[rid] = r
		if staggered:
			await get_tree().process_frame
	# place them once the navmesh is there (their walks need it)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for rid in residents:
		if is_instance_valid(residents[rid]):
			(residents[rid] as Resident).place_now()
	print("[town] %s: %d residents (%s)" % [id, residents.size(), ", ".join(residents.keys().map(func(k): return "%s %s" % [k, (residents[k] as Resident).activity]))])


## The resident teaching a lesson right now in the loaded area (at his place, mid-lesson), or null.
func teaching() -> Resident:
	for rid in residents:
		var r = residents[rid]
		if is_instance_valid(r) and (r as Resident).activity == "teach" and (r as Resident).state == "at:teach":
			return r
	return null


func clear() -> void:
	for rid in residents:
		if is_instance_valid(residents[rid]):
			(residents[rid] as Node).queue_free()
	residents.clear()


## Where this resident stands at an anchor: the anchor itself, or - when others share it - a place round it.
func spot_for(r: Resident, key: String, a: Dictionary) -> Vector3:
	var p: Vector3 = a.pos
	var sharers: Array = residents.keys().filter(func(k): return is_instance_valid(residents[k]) and (residents[k] as Resident).anchor_key == key)
	var i := sharers.find(r.id)
	if sharers.size() <= 1 or i <= 0:
		return p
	var fwd := Vector3(sin(float(a.yaw)), 0, cos(float(a.yaw)))
	var side := Vector3(fwd.z, 0, -fwd.x)
	# round the place in a loose ring (a conversation circle), each a little apart
	var ang := PI * 0.5 * i * (1.0 if i % 2 == 1 else -1.0)
	return p + (side * cos(ang) + fwd * sin(ang)) * 1.3


func someone_near(r: Node3D, radius: float) -> Node3D:
	var best: Node3D = null
	var bd := radius
	for rid in residents:
		var o = residents[rid]
		if not is_instance_valid(o) or o == r or not (o as Node3D).visible:
			continue
		var d := (o as Node3D).global_position.distance_to(r.global_position)
		if d < bd:
			bd = d
			best = o
	for who in main.characters:
		var c: Node3D = main.characters[who]
		if c and c.visible and c.global_position.distance_to(r.global_position) < bd:
			bd = c.global_position.distance_to(r.global_position)
			best = c
	return best


## A small spell of light at the caster's hands (students practising, the teacher demonstrating).
func spell_spark(r: Resident) -> void:
	sparks += 1
	var fwd := Vector3(sin(r.rotation.y), 0, cos(r.rotation.y))
	var at := r.global_position + fwd * 0.6 + Vector3(0, 1.3, 0)
	var col: Color = [Color(0.5, 0.8, 1.0), Color(0.6, 1.0, 0.7), Color(1.0, 0.8, 0.45)][sparks % 3]
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 1.6
	l.omni_range = 3.5
	main.world.add_child(l)
	l.global_position = at
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	orb.mesh = sm
	orb.material_override = Kit.emissive(col, 5.0, true)
	main.world.add_child(orb)
	orb.global_position = at
	var tw := orb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "global_position", at + fwd * 3.5 + Vector3(0, 0.6, 0), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(orb, "scale", Vector3.ONE * 0.2, 0.7)
	tw.tween_property(l, "light_energy", 0.0, 0.8)
	tw.chain().tween_callback(func():
		orb.queue_free()
		l.queue_free())


func _process(delta: float) -> void:
	if residents.is_empty():
		return
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.5
	var now := Time.get_ticks_msec() / 1000.0
	var day := WorldState.day()
	for who in main.characters:
		var c: Node3D = main.characters[who]
		if c == null or not c.visible:
			continue
		for rid in residents:
			var r = residents[rid]
			if not is_instance_valid(r) or not (r as Resident).visible:
				continue
			var d := (r as Node3D).global_position.distance_to(c.global_position)
			if d > 4.5:
				continue
			var st: Dictionary = WorldState.npc_state.get_or_add("res:" + String(rid), {})
			var seen_key := "noticed_%s" % who
			if int(st.get(seen_key, -1)) == day:
				continue
			st[seen_key] = day
			st["met_" + String(who)] = int(st.get("met_" + String(who), 0)) + 1
			var speak: bool = now - _speak_t > SPEAK_GAP_S and not (main.get("voice") != null and main.voice.busy())
			if speak:
				_speak_t = now
			(r as Resident).notice(c, speak)
			# she glances back
			if c.has_method("look_head_at"):
				c.look_head_at((r as Node3D).global_position + Vector3(0, 1.55, 0))
				get_tree().create_timer(2.2).timeout.connect(func(): if is_instance_valid(c): c.look_head_at(null))


func describe(from: Vector3) -> Array:
	var out := []
	for rid in residents:
		if is_instance_valid(residents[rid]):
			out.append((residents[rid] as Resident).describe(from))
	return out


## Someone (other than `me`) already waiting out the rain at this doorstep.
static func shelter_taken(area: Node, key: String, me: Node) -> bool:
	for n in area.get_children():
		if n != me and n is Resident and (n as Resident).activity == "shelter" and (n as Resident).anchor_key == key:
			return true
	return false

