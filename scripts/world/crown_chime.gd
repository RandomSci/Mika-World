class_name CrownChime
extends Node3D
## The Crown (Level 100, docs/THE_CROWN.md): nine bronze bells hung round the turret on the Mentor's Tower crown,
## where no stair goes - only Rising Air reaches it. On a night of wind each bell answers only a mage who has heard
## its Warden's ring somewhere in the world (data/crown.json: a deed or a teaching she really has). The wind sets
## them all moving; the ones she has not heard swing without a sound. All nine together: crown:heard_all_nine.

const RING_R := 2.2               # bells hang just off the turret wall
const HANG_Y := 2.15              # above the crown walk

var data: Dictionary = {}
var bells: Array = []             # [{pivot: Node3D, n, pos}]
var log: Array = []
var _busy := false


static func load_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/crown.json"))


## `floor_c`: the crown walk's centre (the turret's axis at walk height), in the parent's space.
func build(floor_c: Vector3, stone: Material) -> void:
	data = load_data()
	position = floor_c
	var bronze := Kit.metal(Color(0.62, 0.42, 0.2), 0.32)
	bronze.cull_mode = BaseMaterial3D.CULL_DISABLED
	var iron := Kit.metal(Color(0.12, 0.11, 0.1), 0.6)
	# the founders' bell-ring: an iron hoop on nine brackets out of the turret wall
	var hoop := TorusMesh.new()
	hoop.inner_radius = RING_R - 0.03
	hoop.outer_radius = RING_R + 0.03
	hoop.rings = 64
	Kit.mesh_node(self, hoop, iron, Kit.xf(Vector3(0, HANG_Y + 0.12, 0)), false)
	var shell := Kit.lathe([Vector2(0.27, 0.0), Vector2(0.285, 0.03), Vector2(0.24, 0.09), Vector2(0.18, 0.22),
		Vector2(0.155, 0.34), Vector2(0.12, 0.42), Vector2(0.06, 0.46), Vector2(0.0, 0.47)], 28, true, false)
	var rings: Array = data.get("rings", [])
	for i in rings.size():
		var a := TAU * float(i) / float(rings.size()) + 0.2
		var at := Vector3(cos(a) * RING_R, HANG_Y, sin(a) * RING_R)
		# bracket from the wall
		var br := Basis(Vector3.UP, -a)
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.5, 0.07, 0.07), 0.005), iron, Transform3D(br, Vector3(cos(a) * (RING_R - 0.22), HANG_Y + 0.12, sin(a) * (RING_R - 0.22))), false)
		var pivot := Node3D.new()
		pivot.name = "Bell%d" % int(rings[i].n)
		pivot.position = at + Vector3(0, 0.1, 0)
		pivot.rotation.y = -a
		add_child(pivot)
		var size := 0.8 + 0.06 * float(i)                 # ring 1 the smallest, ring 9 the largest
		Kit.mesh_node(pivot, shell, bronze, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), Vector3(0, -0.47 * size, 0)), false)
		var clapper := SphereMesh.new()
		clapper.radius = 0.045 * size
		clapper.height = 0.09 * size
		Kit.mesh_node(pivot, clapper, iron, Kit.xf(Vector3(0, -0.4 * size, 0)), false)
		bells.append({"pivot": pivot, "n": int(rings[i].n), "size": size})


## Which rings this mage has heard (by her own knowledge), in order.
func heard_by(who: String) -> Array:
	var k: Dictionary = WorldState.mind(who).knowledge
	var out := []
	for r in data.get("rings", []):
		if (r.any as Array).any(func(key): return k.has(String(key))):
			out.append(int(r.n))
	return out


## She stands on the crown at night and listens. The wind comes over the tower, every bell swings; the ones whose
## ring she has heard sound, one after another, then together. Returns what happened (and records it).
func listen(c: WorldCharacter, main: Node) -> Dictionary:
	var who := c.character_id
	if _busy:
		return {"ok": false, "detail": "the bells are already sounding"}
	if bool(data.get("night_only", true)) and not (WorldState.night or WorldState.daylight() < 0.15):
		return {"ok": false, "detail": "by day the bells hang still: the wind that moves them comes over the tower at night"}
	_busy = true
	var heard := heard_by(who)
	var center := global_position
	c.look_at_point(center + Vector3(0, HANG_Y, 0))
	if c.get("face") and c.face:
		c.face.pulse("surprised", 0.4, 1.5)
	var wind: AudioStreamPlayer3D = null
	if main.get("audio"):
		wind = main.audio.play3d("bell_crown_wind", center + Vector3(0, 2, 0), "SFX", -6.0, "crown")
	# the wind arrives: every bell starts to swing (a silent one swings just the same)
	for b in bells:
		_swing(b.pivot, 0.12 + randf() * 0.06, 2.6 + randf() * 0.6)
	await get_tree().create_timer(2.2).timeout
	var sounded := []
	for b in bells:
		if not is_instance_valid(c):
			break
		if heard.has(int(b.n)):
			_strike(b, main, 0.0)
			sounded.append(int(b.n))
			c.look_at_point((b.pivot as Node3D).global_position)
			await get_tree().create_timer(1.15).timeout
		else:
			await get_tree().create_timer(0.55).timeout     # a bell swinging with no sound: she hears the gap
	var all_nine := sounded.size() == bells.size() and bells.size() == 9
	if all_nine:
		await get_tree().create_timer(0.8).timeout
		for b in bells:
			_strike(b, main, -4.0)
		_crown_of_light(center)
	await get_tree().create_timer(2.0).timeout
	var lines: Dictionary = data.get("lines", {}).get(who, data.get("lines", {}).get("mika", {}))
	var pool: Array = lines.get("all" if all_nine else "partial", [])
	if main.get("voice") and not pool.is_empty():
		main.voice.say(who, String(pool[randi() % pool.size()]), {"mood": "tender" if all_nine else "neutral", "max_wait": 3.0})
	if c.get("face") and c.face:
		c.face.pulse("happy" if all_nine else "relaxed", 0.7 if all_nine else 0.4, 3.0)
	var missing: Array = []
	for r in data.get("rings", []):
		if not sounded.has(int(r.n)):
			missing.append({"n": int(r.n), "warden": String(r.warden), "how": String(r.how)})
	var know := {"crown:listened": 1}
	for n in sounded:
		know["crown:heard_ring_%d" % n] = 1
	if all_nine:
		know["crown:heard_all_nine"] = 1
	for m in missing:
		know["crown:silent_%d" % int(m.n)] = 1                 # what she still has to hear (the planner can seek it)
	var changes := WorldState.record_activity({"id": "crown:listen", "verb": "listen", "label": "listened to the Crown's bells (%d of 9 sounded)" % sounded.size()}, {"knowledge": know}, who)
	if wind and is_instance_valid(wind):
		var tw := wind.create_tween()
		tw.tween_property(wind, "volume_db", -40.0, 3.0)
		tw.tween_callback(wind.stop)          # a pooled player (AudioDirector): stopped, never freed
	var ev := {"who": who, "sounded": sounded, "missing": missing.map(func(m): return m.n), "all_nine": all_nine, "clock": WorldState.clock_text()}
	log.append(ev)
	if log.size() > 50:
		log.pop_front()
	_busy = false
	return {"ok": true, "sounded": sounded, "missing": missing, "all_nine": all_nine, "changes": changes,
		"detail": ("all nine bells sounded: she has heard every ring - the Crown" if all_nine else
			"%d of the nine bells sounded; silent: %s" % [sounded.size(), ", ".join(missing.map(func(m): return String(m.warden)))])}


func _swing(pivot: Node3D, amp: float, period: float) -> void:
	var tw := pivot.create_tween().set_loops(4)
	tw.tween_property(pivot, "rotation:x", amp, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pivot, "rotation:x", -amp, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(func():
		if is_instance_valid(pivot):
			pivot.create_tween().tween_property(pivot, "rotation:x", 0.0, 1.5).set_trans(Tween.TRANS_SINE))


func _strike(b: Dictionary, main: Node, db: float) -> void:
	var pivot: Node3D = b.pivot
	if main.get("audio"):
		main.audio.play3d("bell_ring_%d" % int(b.n), pivot.global_position, "SFX", db, "crown_bell")
	# a glint off the bronze as it sounds, rising away as a mote of light
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.5)
	l.light_energy = 2.2
	l.omni_range = 2.5
	add_child(l)
	l.global_position = pivot.global_position + Vector3(0, -0.2, 0)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "light_energy", 0.0, 1.6)
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 1.2, 0), 1.6)
	tw.chain().tween_callback(l.queue_free)


## All nine: a ring of light lifts off the bell-ring and hangs over the tower like a crown, then fades.
func _crown_of_light(center: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RING_R - 0.06
	tm.outer_radius = RING_R + 0.06
	tm.rings = 64
	ring.mesh = tm
	var m := Kit.emissive(Color(1.0, 0.85, 0.5), 6.0, true)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = m
	add_child(ring)
	ring.global_position = center + Vector3(0, HANG_Y + 0.12, 0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.55)
	light.light_energy = 0.0
	light.omni_range = 14.0
	ring.add_child(light)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "global_position", center + Vector3(0, HANG_Y + 5.5, 0), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector3.ONE * 1.6, 6.0)
	tw.tween_property(light, "light_energy", 4.0, 1.5)
	tw.chain().tween_property(m, "albedo_color:a", 0.0, 3.0)
	tw.parallel().tween_property(light, "light_energy", 0.0, 3.0)
	tw.chain().tween_callback(ring.queue_free)
