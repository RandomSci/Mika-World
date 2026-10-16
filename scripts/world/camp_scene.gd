class_name CampScene
extends Node
## A night in the wild on a journey (V3 continuation - "Choosing a suitable campsite. Setting up camp, blankets and
## equipment. Gathering supplies and firewood. Preparing food ... Cooking and eating with real props and
## animations. Sharing stories ... Watching stars ... Sleeping with natural transitions ... Taking turns keeping
## watch when the area is dangerous. Packing belongings and continuing the journey at dawn. Do not fake these
## activities with objects teleporting into hands or characters instantly switching poses.")
##
## Every object is a real thing in the world that a hand reaches, grasps, carries and puts down (ObjectHandler IK +
## the Mixamo / UAL pick-up, put-down, kneel and sit clips); what they travel with comes out of their STORAGE RINGS
## into the palm (and goes back in the morning); Mika walks into the
## trees for dry branches and carries them back one by one; Luna unrolls the bedrolls on the ground; the fire is
## struck from sparks and grows; water is fetched from the stream in the pot; supper cooks on the stones and is
## eaten spoonful by spoonful. The night passes on the world clock; whether they keep watch depends on how dangerous
## this stretch of road is; what comes out of the dark is a real creature of the route's habitats.
## Returns a record of the night (beats, lines, the watch, any encounter) for the journey log.

var main: Node
var jd: JourneyDirector
var w: Wayside
var mika: WorldCharacter
var luna: WorldCharacter
var fire: Campfire
var rec := {"beats": [], "said": [], "watch": [], "encounter": {}, "meal": {}, "where": ""}
var lines := {}
var talk := []
var props := {}                     # name -> Node3D (bedrolls, pot, bowls, spoon...)
var _rng := RandomNumberGenerator.new()
var _t0 := 0.0


func _beat(what: String, who := "", detail := "") -> void:
	var e := {"clock": WorldState.clock_text(), "beat": what, "who": who, "detail": detail}
	(rec.beats as Array).append(e)
	print("[camp] %s  %s%s%s" % [e.clock, what, (" (" + who + ")") if who != "" else "", (": " + detail) if detail != "" else ""])
	if jd:
		jd.stage = "camp: " + what


func _line(who: String, key: String, fill := {}) -> String:
	var arr: Array = lines.get(who, {}).get(key, [])
	if arr.is_empty():
		return ""
	var s := String(arr[_rng.randi() % arr.size()])
	for k in fill:
		s = s.replace("{%s}" % k, String(fill[k]))
	return s


func _say(who: String, key: String, wait := true, fill := {}) -> void:
	var text := _line(who, key, fill)
	await _speak(who, text, wait)


func _speak(who: String, text: String, wait := true) -> void:
	if text == "":
		return
	(rec.said as Array).append({"who": who, "text": text, "clock": WorldState.clock_text()})
	var c: WorldCharacter = main.characters.get(who)
	var other: WorldCharacter = luna if c == mika else mika
	if other and c and other.reaction and not other.reaction.active:
		other.look_head_at(c.global_position + Vector3(0, 1.3 if c.ground_pose == "" else 0.8, 0))
	if main.voice == null:
		if wait:
			await _wait(clampf(text.length() * 0.06, 1.2, 5.0))
		return
	if wait:
		await main.voice.say(String(Progression.mages.get(who, {}).get("voice", who)), text)
	else:
		main.voice.say(String(Progression.mages.get(who, {}).get("voice", who)), text)


func _wait(s: float) -> void:
	var t := 0.0
	while t < s and is_inside_tree():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


# ------------------------------------------------------------------ body helpers
func _walk(c: WorldCharacter, p: Vector3, run := false, max_s := 40.0) -> bool:
	var map := c.get_world_3d().navigation_map
	var goal := NavigationServer3D.map_get_closest_point(map, p)
	if Vector2(c.global_position.x - goal.x, c.global_position.z - goal.z).length() < 0.6:
		return true
	c.navigate_to(goal, run)
	var t := 0.0
	while c.current_action == "navigate_to" and t < max_s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return Vector2(c.global_position.x - goal.x, c.global_position.z - goal.z).length() < 1.4


func _face(c: WorldCharacter, p: Vector3) -> void:
	c.look_at_point(p)
	var t := 0.0
	while c.current_action == "look_at" and t < 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _kneel(c: WorldCharacter) -> void:
	c.play_gesture("crouch_loop", 0.45, 0.5)
	await _wait(0.5)


func _rise(c: WorldCharacter) -> void:
	c.end_gesture()
	await _wait(0.55)


func _sit(c: WorldCharacter, talk_loop := false) -> void:
	if c.ground_pose == "sit":
		return
	c.play_gesture("sit_ground_enter", 0.3, 0.3)
	c.set_ground_pose("sit", c.animation_length("sit_ground_enter") * 0.9)
	await _wait(c.animation_length("sit_ground_enter") * 0.85)
	c.play_gesture("sit_ground_talk" if talk_loop else "sit_ground_loop", 0.3, 0.6)


func _unsit(c: WorldCharacter) -> void:
	if c.ground_pose != "sit":
		return
	c.end_gesture()
	c.play_gesture("sit_ground_exit", 0.2, 0.4)
	c.set_ground_pose("", c.animation_length("sit_ground_exit") * 0.9)
	await _wait(c.animation_length("sit_ground_exit") + 0.2)


## Pick a thing up off the ground (or a pack) and KEEP it in the hand: face it, bend with the pick-up clip, the arm
## reaches it when it comes within reach, grasps it, and the arm returns to the clip with the thing in the palm.
## The last steps in: a walk stops within its tolerance (up to ~1.4 m short); to take something from the ground she
## steps in close (real steps, steering round anything in the way) until it is within arm's reach.
func _close_in(c: WorldCharacter, p: Vector3, within := 0.55, max_s := 2.5) -> void:
	var t := 0.0
	while t < max_s:
		var d := Vector3(p.x - c.global_position.x, 0, p.z - c.global_position.z)
		if d.length() <= within:
			break
		c.set_move_input(c._steer_around(d.normalized()), false)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	c.set_move_input(Vector3.ZERO, false)


func _pick(c: WorldCharacter, obj: HoldableObject) -> bool:
	if obj == null or c.handler.held != null:
		return false
	await _close_in(c, obj.global_position)
	await _face(c, obj.global_position)
	var gp := obj.grasp_point()
	var low := gp.y - c.global_position.y < 0.7
	var clip := "pick_floor" if low else "pick_chest"
	c.play_gesture(clip, 0.25, 0.45)
	var length := c.animation_length(clip)
	var t := 0.0
	var got := false
	while t < length * 0.75:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not got and t > length * 0.2 and c.handler.can_reach(obj.grasp_point()):
			got = await c.handler.grasp(obj)
	if got:
		await c.handler.relax(0.45)
	return got


## Put the held thing down at `at` (on the ground or the stones): bend with the put-down clip; the hand carries it
## to the spot when it comes within reach and lets go there.
func _put(c: WorldCharacter, at: Vector3, yaw := 0.0) -> bool:
	if c.handler.held == null:
		return false
	await _close_in(c, at, 0.75)
	await _face(c, at)
	var low := at.y - c.global_position.y < 0.7
	if low:
		c.play_gesture("put_down", 0.25, 0.45)
	var length := c.animation_length("put_down") if low else 0.6
	var t := 0.0
	var done := false
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	while t < length * 0.85 and not done:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > length * 0.2 and c.handler.can_reach(at + Vector3(0, c.handler.held.grasp_height, 0)):
			done = await c.handler.place(xf, 0.45)
	await c.handler.relax(0.4)
	return done


## Hand something to the other: the giver holds it out between them, the receiver reaches the same point, it
## changes hands there.
func _hand_over(giver: WorldCharacter, taker: WorldCharacter, obj: HoldableObject) -> bool:
	if giver.handler.held != obj:
		return false
	var mid := (giver.global_position + taker.global_position) * 0.5 + Vector3(0, 0.95 if giver.ground_pose == "" else 0.55, 0)
	if not giver.handler.can_reach(mid) or not taker.handler.can_reach(mid):
		return false
	await giver.handler.carry_to(mid - Vector3(0, obj.grasp_height, 0), 0.7)
	await taker.handler.reach(mid, 0.6)
	giver.handler.held = null
	obj.holder = taker
	taker.handler.held = obj
	await giver.handler.relax(0.4)
	await taker.handler.relax(0.5)
	return true


func _holdable(id: String, label: String, mesh_node: Node3D, at: Vector3, grasp_h := 0.06) -> HoldableObject:
	var h := HoldableObject.new()
	h.setup(id, label, label)
	h.grasp_height = grasp_h
	w.add_child(h)
	h.global_position = at
	if mesh_node:
		h.add_child(mesh_node)
	h.remember_home()
	props[id] = h
	return h


func _model(id: String, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	var mi := Kit.place_prop_all(root, id, Kit.xf(Vector3.ZERO, 0.0, Vector3.ONE * scale))
	return root if mi else root


static func _fabric(tex: String, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var base := "res://assets/polyhaven/textures/%s/%s_" % [tex, tex]
	for suf in ["diff_1k.jpg", "albedo_1k.jpg"]:
		if ResourceLoader.exists(base + suf):
			m.albedo_texture = load(base + suf)
	if ResourceLoader.exists(base + "nor_gl_1k.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(base + "nor_gl_1k.jpg")
	m.albedo_color = tint
	m.roughness = 0.9
	m.uv1_scale = Vector3(2, 2, 2)
	return m


## A bedroll laid out: a wool blanket over a leather ground sheet (unrolls from its roll by scaling along its length).
static func make_bedroll(tint: Color) -> Node3D:
	var root := Node3D.new()
	var sheet := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.75, 0.035, 1.85)
	sheet.mesh = bm
	sheet.material_override = _fabric("poly_wool_herringbone", tint)
	sheet.position = Vector3(0, 0.02, -0.92)
	root.add_child(sheet)
	return root


# ------------------------------------------------------------------ the night
func run(p_main: Node, p_jd: JourneyDirector, p_w: Wayside, party: Array) -> Dictionary:
	main = p_main
	jd = p_jd
	w = p_w
	mika = party[0]
	luna = party[1] if party.size() > 1 else null
	_rng.seed = int(WorldState.world_min)
	var f := FileAccess.open("res://data/camp.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text()) if f else {}
	lines = data.get("lines", {})
	talk = data.get("talk", [])
	var cp: Dictionary = w.camp
	rec.where = "%s, km %.0f" % [String(jd.leg().get("name", "the road")), float(WorldState.journey.get("km", 0.0))]
	# --- 1. the place
	_beat("arrive", "", rec.where)
	jd._start_follow()
	if jd._follow:
		await main.companionship.walk_together(mika, jd._follow, cp.center + Vector3(0.5, 0, -2.2), 60.0)
	jd._stop_follow()
	await _face(mika, cp.center)
	var why := []
	if float(w.site_water_dist(Vector2(cp.center.x, cp.center.z))) < 14.0:
		why.append("water close")
	why.append("level ground")
	why.append("big trees around")
	_beat("choose_site", "mika", ", ".join(why))
	await _say("mika", "choose_site")
	if luna:
		await _say("luna", "agree_site", false)
	# --- 2. their things are in their storage rings (no packs): nothing to unload
	# --- 3. firewood (Mika) while Luna lays out the bedrolls
	props["done_wood"] = false
	props["done_beds"] = luna == null
	_firewood(cp)
	if luna:
		_bedrolls(cp)
	var tw := 0.0
	while not (props.done_wood and props.done_beds) and tw < 240.0:
		await get_tree().physics_frame
		tw += get_physics_process_delta_time()
	# --- 4. the fire
	await _light_fire(cp)
	# --- 5. supper
	await _supper(cp)
	# --- 6. by the fire: talk, stars
	await _fireside(cp)
	# --- 7. the night: sleep, the watch, whatever comes out of the dark
	await _night(cp)
	# --- 8. morning
	await _morning(cp)
	return rec


# ------------------------------------------------------------------ the storage rings
## What each carries on a journey, in her ring (the developer: "a beautiful storage ring that can store objects and
## living things"). Called when a journey starts.
static func stock_rings(m: WorldCharacter, l: WorldCharacter) -> void:
	var rm := StorageRing.attach(m)
	rm.stock({"spoon": "a wooden spoon", "bowl_mika": "a wooden bowl", "bowl_luna": "a wooden bowl", "spud_0": "a sweet potato",
		"spud_1": "a sweet potato", "apple_mika": "an apple", "apple_luna": "an apple", "flint": "flint and steel"})
	if l:
		var rl := StorageRing.attach(l)
		rl.stock({"roll_0": "Mika's bedroll", "roll_1": "Luna's bedroll", "pot": "the cooking pot", "waterskin": "a waterskin"})


## Out of her ring into her open palm: a real object she then holds (HoldableObject), grown from the stone's light.
func _draw(c: WorldCharacter, id: String, label: String, model: Node3D, grasp_h := 0.05) -> HoldableObject:
	var ring := StorageRing.attach(c)
	var h := HoldableObject.new()
	h.setup(id, label, label)
	h.grasp_height = grasp_h
	w.add_child(h)
	if model:
		h.add_child(model)
	props[id] = h
	if not await ring.draw(id, h):
		h.queue_free()
		props.erase(id)
		return null
	_beat("from the ring", c.character_id, label)
	return h


## Into her ring: the thing in her hand (or one within reach) shrinks into the stone.
func _store(c: WorldCharacter, id: String, label: String, node: Node3D = null) -> void:
	if node and node != c.handler.held:
		await _walk(c, node.global_position + (c.global_position - node.global_position).normalized() * 0.6)
		await _kneel(c)
		if c.handler.can_reach(node.global_position + Vector3(0, 0.1, 0)):
			await c.handler.reach(node.global_position + Vector3(0, 0.1, 0), 0.4)
		await StorageRing.attach(c).store(id, label, node)
		await c.handler.relax(0.3)
		await _rise(c)
	else:
		await StorageRing.attach(c).store(id, label)
		await c.handler.relax(0.3)
	props.erase(id)
	_beat("into the ring", c.character_id, label)


static func _roll_mesh(tint: Color) -> Node3D:
	var root := Node3D.new()
	var roll := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.1
	cm.height = 0.72
	roll.mesh = cm
	roll.material_override = _fabric("poly_wool_herringbone", tint)
	roll.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(roll)
	return root


# ------------------------------------------------------------------ firewood
func _firewood(cp: Dictionary) -> void:
	await _say("mika", "firewood", false)
	var wood: Array = (cp.wood as Array).duplicate()
	wood.sort_custom(func(a, b): return (a.pos as Vector3).distance_to(cp.fire) < (b.pos as Vector3).distance_to(cp.fire))
	var got := 0
	for i in mini(3, wood.size()):
		var it: Dictionary = wood[i]
		var node: Node3D = it.node
		if not is_instance_valid(node):
			continue
		_beat("firewood: walks into the trees", "mika", "%.0f m from the fire" % (it.pos as Vector3).distance_to(cp.fire))
		if not await _walk(mika, it.pos + ((cp.fire as Vector3) - (it.pos as Vector3)).normalized() * 0.8, false, 40.0):
			continue
		var h := HoldableObject.new()
		h.setup("wood_%d" % i, "dry branches", "an armful of dry branches")
		h.grasp_height = 0.1
		w.add_child(h)
		h.global_position = node.global_position
		node.reparent(h, true)
		if await _pick(mika, h):
			await _walk(mika, (cp.fire as Vector3) + Vector3(0.9, 0, -0.6), false, 40.0)
			var stack := (cp.fire as Vector3) + Vector3(0.75 + got * 0.12, 0, -0.45 - got * 0.1)
			stack.y = w.height(stack.x, stack.z)
			if await _put(mika, stack, _rng.randf() * TAU):
				got += 1
				WorldState.journey.supplies.firewood = int(WorldState.journey.supplies.get("firewood", 0)) + 1
	rec.meal["firewood_carried"] = got
	_beat("firewood stacked", "mika", "%d armfuls carried back" % got)
	props.done_wood = true


# ------------------------------------------------------------------ bedrolls
func _bedrolls(cp: Dictionary) -> void:
	await _say("luna", "bedrolls", false)
	var beds: Array = cp.beds
	for i in beds.size():
		var spot: Vector3 = beds[i]
		var tint := Color(0.55, 0.42, 0.3) if i == 0 else Color(0.3, 0.33, 0.45)
		await _walk(luna, spot + Vector3(0.7, 0, -0.2))
		await _face(luna, spot)
		await _kneel(luna)
		var h := await _draw(luna, "roll_%d" % i, "a rolled wool bedroll", _roll_mesh(tint), 0.1)
		if h == null:
			await _rise(luna)
			continue
		var yaw := atan2((cp.fire as Vector3).x - spot.x, (cp.fire as Vector3).z - spot.z)
		if luna.handler.held == h and luna.handler.can_reach(spot + Vector3(0, 0.12, 0)):
			await luna.handler.place(Transform3D(Basis(Vector3.UP, yaw), spot + Vector3(0, 0.1, 0)), 0.5)
		elif luna.handler.held == h:
			luna.handler.held = null
			h.on_placed(Transform3D(Basis(Vector3.UP, yaw), spot + Vector3(0, 0.1, 0)))
		# unroll: the blanket spreads from the roll along its length while her hand pushes it out
		var bed := make_bedroll(tint)
		bed.name = "Bed_%d" % i
		w.add_child(bed)
		bed.global_transform = Transform3D(Basis(Vector3.UP, yaw + PI), spot)
		bed.scale = Vector3(1, 1, 0.08)
		props["bed_%d" % i] = bed
		var far := spot + Basis(Vector3.UP, yaw + PI) * Vector3(0, 0.05, -1.7)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(bed, "scale", Vector3.ONE, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(h, "global_position", far, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if luna.handler.can_reach(spot + Vector3(0, 0.1, 0)):
			luna.handler.target.global_position = luna.handler.palm()
			var tw2 := create_tween()
			tw2.tween_property(luna.handler.ik, "influence", 0.8, 0.4)
			tw2.parallel().tween_method(func(v: Vector3): luna.handler.target.global_position = v, spot + Vector3(0, 0.1, 0), far + Vector3(0, 0.1, 0), 1.6)
			tw2.tween_property(luna.handler.ik, "influence", 0.0, 0.4)
		await _wait(1.8)
		h.queue_free()
		await _rise(luna)
		_beat("bedroll laid out", "luna", "bed %d" % (i + 1))
	props.done_beds = true


# ------------------------------------------------------------------ fire
func _light_fire(cp: Dictionary) -> void:
	fire = Campfire.new()
	fire.name = "Campfire"
	w.add_child(fire)
	fire.global_position = cp.fire
	await _walk(mika, (cp.fire as Vector3) + Vector3(0, 0, 0.9))
	await _face(mika, cp.fire)
	await _kneel(mika)
	_beat("striking sparks", "mika", "flint and steel over the tinder")
	var over: Vector3 = (cp.fire as Vector3) + Vector3(0, 0.3, 0)
	var hit := 0
	for i in 5:
		if mika.handler.can_reach(over):
			await mika.handler.reach(over + Vector3(0, 0.12, 0), 0.25)
			await mika.handler.reach(over, 0.12)
		fire.strike_spark()
		hit += 1
		if i >= 2 and _rng.randf() < 0.6:
			break
		await _wait(0.35)
	await mika.handler.relax(0.4)
	fire.ignite(5.0, 120.0)
	_beat("the fire catches", "mika", "after %d strikes" % hit)
	await _wait(1.5)
	await _say("mika", "fire_lit")
	if int(WorldState.journey.supplies.get("firewood", 0)) > 0:
		fire.feed(60.0)
		WorldState.journey.supplies.firewood = int(WorldState.journey.supplies.firewood) - 1
	await _wait(2.0)
	await _rise(mika)


# ------------------------------------------------------------------ supper
func _supper(cp: Dictionary) -> void:
	var fire_p: Vector3 = cp.fire
	if luna:
		await _say("luna", "water", false)
		var pot := await _draw(luna, "pot", "the cooking pot", _model("pot_enamel_01", 0.9), 0.16)
		if pot == null:
			pot = _holdable("pot", "the cooking pot", _model("pot_enamel_01", 0.9), (cp.fire as Vector3) + Vector3(0.6, 0.0, 0.6), 0.16)
		_beat("fetching water", "luna", "to the stream with the pot")
		await _walk(luna, cp.water, false, 50.0)
		await _face(luna, (cp.water as Vector3) + Vector3(-1.5, 0, 0))
		await _kneel(luna)
		var dip := luna.global_position - luna.global_transform.basis.z * 0.55 + Vector3(0, 0.1, 0)
		if luna.handler.held == pot and luna.handler.can_reach(dip + Vector3(0, pot.grasp_height, 0)):
			await luna.handler.carry_to(dip, 0.6)
			await luna.handler.set_tilt(0.5, 0.5)
			await _wait(0.6)
			await luna.handler.set_tilt(0.0, 0.5)
		pot.contents = "water"
		await luna.handler.relax(0.4)
		await _rise(luna)
		await _walk(luna, fire_p + Vector3(0.9, 0, 0.5), false, 50.0)
		await _kneel(luna)
		var on_stones := fire_p + Vector3(0.0, 0.18, 0.0)
		if luna.handler.held == pot and luna.handler.can_reach(on_stones + Vector3(0, pot.grasp_height, 0)):
			await luna.handler.place(Transform3D(Basis.IDENTITY, on_stones), 0.6)
		elif luna.handler.held == pot:
			luna.handler.held = null
			pot.on_placed(Transform3D(Basis.IDENTITY, on_stones))
		await luna.handler.relax(0.4)
		_beat("the pot on the fire", "luna", "filled with stream water")
		await _rise(luna)
	await _say("mika", "cook", false)
	var cook: Vector3 = cp.cook
	await _walk(mika, cook)
	await _face(mika, fire_p)
	await _kneel(mika)
	var pot2: HoldableObject = props.get("pot")
	var added := 0
	for i in 2:
		var spud := await _draw(mika, "spud_%d" % i, "a sweet potato", _model("sweet_potato", 1.0), 0.03)
		if spud:
			if pot2 and mika.handler.can_reach(pot2.global_position + Vector3(0, 0.35, 0)):
				await mika.handler.carry_to(pot2.global_position + Vector3(0, 0.3, 0), 0.5)
				mika.handler.held = null
				var tw := create_tween()
				tw.tween_property(spud, "global_position", pot2.global_position + Vector3(0, 0.08, 0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_callback(spud.hide)
				added += 1
			else:
				mika.handler.held = null
		await mika.handler.relax(0.3)
	var spoon := await _draw(mika, "spoon", "a wooden spoon", _model("wooden_spoon", 1.0), 0.02)
	var stirred := 0
	if spoon and pot2:
		var c0 := pot2.global_position + Vector3(0, 0.32, 0)
		if mika.handler.can_reach(c0):
			for k in 10:
				var a := k * TAU / 5.0
				await mika.handler.reach(c0 + Vector3(cos(a) * 0.07, 0, sin(a) * 0.07), 0.22)
				stirred += 1
	_beat("cooking", "mika", "%d sweet potatoes in, stirred" % added)
	WorldState.journey.supplies.food = maxi(0, int(WorldState.journey.supplies.get("food", 0)) - 1)
	await _wait(2.0)
	# two bowls out of the ring, set down by the pot, filled spoon by spoon
	var held_spoon := mika.handler.held
	if held_spoon:
		mika.handler.held = null
		held_spoon.global_position = mika.global_position - mika.global_transform.basis.z * 0.35 + mika.global_transform.basis.x * 0.25 + Vector3(0, 0.02, 0)
	var bowl_m := await _draw(mika, "bowl_mika", "a wooden bowl", _model("wooden_bowl_01", 0.8), 0.04)
	if bowl_m:
		await _put(mika, mika.global_position - mika.global_transform.basis.z * 0.42 - mika.global_transform.basis.x * 0.3 + Vector3(0, 0.0, 0), 0.0)
	var bowl_l := await _draw(mika, "bowl_luna", "a wooden bowl", _model("wooden_bowl_01", 0.8), 0.04)
	if bowl_l:
		await _put(mika, mika.global_position - mika.global_transform.basis.z * 0.42 - mika.global_transform.basis.x * 0.55 + Vector3(0, 0.0, 0), 0.0)
	if held_spoon and mika.handler.can_reach(held_spoon.grasp_point()):
		await mika.handler.grasp(held_spoon)
	if mika.handler.held == spoon and pot2 and bowl_m and bowl_l:
		for b in [bowl_m, bowl_l]:
			for k in 2:
				if mika.handler.can_reach(pot2.global_position + Vector3(0, 0.25, 0)) and mika.handler.can_reach((b as Node3D).global_position + Vector3(0, 0.1, 0)):
					await mika.handler.reach(pot2.global_position + Vector3(0, 0.22, 0), 0.35)
					await mika.handler.reach((b as Node3D).global_position + Vector3(0, 0.12, 0), 0.4)
	if mika.handler.held == spoon:
		mika.handler.held = null
		spoon.global_position = mika.global_position - mika.global_transform.basis.z * 0.4 + Vector3(0.15, 0.02, 0)
	await mika.handler.relax(0.3)
	await _rise(mika)
	rec.meal["cooked"] = added
	rec.meal["stirred"] = stirred
	if luna:
		var seat_l: Vector3 = (cp.seats as Array)[1]
		await _walk(luna, seat_l)
		await _face(luna, fire_p)
		await _sit(luna)
		await _walk(mika, bowl_l.global_position + (mika.global_position - bowl_l.global_position).normalized() * 0.55)
		await _kneel(mika)
		if mika.handler.can_reach(bowl_l.grasp_point()):
			await mika.handler.grasp(bowl_l)
			await mika.handler.relax(0.3)
		await _rise(mika)
		await _walk(mika, seat_l + (fire_p - seat_l).normalized() * 0.75)
		await _face(mika, luna.global_position)
		await _say("mika", "serve", false)
		var given := await _hand_over(mika, luna, bowl_l)
		rec.meal["handed_bowl"] = given
		_beat("supper served", "mika", "the bowl changed hands" if given else "set down beside her")
		if not given and mika.handler.held == bowl_l:
			mika.handler.held = null
			bowl_l.global_position = seat_l + (fire_p - seat_l).normalized() * 0.4
		await _say("luna", "thanks_food", false)
	var seat_m: Vector3 = (cp.seats as Array)[0]
	await _walk(mika, bowl_m.global_position + (mika.global_position - bowl_m.global_position).normalized() * 0.55)
	await _kneel(mika)
	if mika.handler.can_reach(bowl_m.grasp_point()):
		await mika.handler.grasp(bowl_m)
		await mika.handler.relax(0.3)
	await _rise(mika)
	await _walk(mika, seat_m)
	await _face(mika, fire_p)
	await _sit(mika)
	var bites := 0
	for k in 4:
		for c in [mika, luna]:
			if c == null or (c as WorldCharacter).handler.held == null:
				continue
			var wc := c as WorldCharacter
			var head := wc.skeleton.global_transform * wc.skeleton.get_bone_global_pose(wc.skeleton.find_bone("Head")).origin
			var mouth := head - wc.global_transform.basis.z * 0.12 + Vector3(0, -0.06, 0)
			var lap := wc.global_position - wc.global_transform.basis.z * 0.3 + Vector3(0, 0.45, 0)
			if wc.handler.can_reach(mouth) and wc.handler.can_reach(lap):
				await wc.handler.reach(lap, 0.35)
				wc.set_expression("aa", 0.6)
				await wc.handler.reach(mouth, 0.45)
				await _wait(0.25)
				wc.set_expression("aa", 0.0)
				bites += 1
		await _wait(0.4)
	rec.meal["bites"] = bites
	_beat("supper eaten", "", "%d spoonfuls between them" % bites)
	for c in [mika, luna]:
		if c and (c as WorldCharacter).handler.held:
			var wc := c as WorldCharacter
			var held := wc.handler.held
			wc.handler.held = null
			held.global_position = wc.global_position - wc.global_transform.basis.z * 0.35 + Vector3(0, 0.02, 0)
			await wc.handler.relax(0.3)
	for who in WorldState.journey.condition:
		WorldState.journey.condition[who].hunger = 0.05
	await _say("mika", "eat")


# ------------------------------------------------------------------ fireside
func _fireside(_cp: Dictionary) -> void:
	var j: Dictionary = WorldState.journey
	var fill := {"dest": String(j.dest).replace("_", " "), "purpose_short": String(j.purpose).split(":")[0], "km": str(int(float(j.km))), "day": str(WorldState.day())}
	var have := {"purpose": true, "km": true, "stars": WorldState.hour_f() > 19.5 or WorldState.hour_f() < 4.0}
	for e in j.log:
		if String(e.get("kind", "")) == "waypoint":
			var what := String(e.what)
			if what.contains("Ford") or what.contains("crossing"):
				have["ford"] = true
				fill["ford"] = what.get_slice(" (", 0).replace("passed ", "")
			if what.contains("bought"):
				have["village"] = true
				fill["village"] = what.get_slice(" (", 0).replace("passed ", "")
	for k in ["mika", "luna"]:
		var last: Dictionary = WorldState.mind(k).knowledge.get("struck_last", {})
		if not last.is_empty() and Time.get_unix_time_from_system() - float(last.get("unix", 0)) < 86400:
			have["fight"] = true
	for c in [mika, luna]:
		if c and (c as WorldCharacter).ground_pose == "sit":
			(c as WorldCharacter).play_gesture("sit_ground_talk", 0.4, 0.6)
	var spoken := 0
	for t in talk:
		if not have.get(String(t.need), false):
			continue
		_beat("fireside talk", "", String(t.need))
		for ln in t.lines:
			var text := String(ln[1])
			var missing := false
			for k in ["dest", "purpose_short", "km", "day", "ford", "village"]:
				if text.contains("{%s}" % k):
					if not fill.has(k):
						missing = true
					text = text.replace("{%s}" % k, String(fill.get(k, "")))
			if missing:
				break
			await _speak(String(ln[0]), text, true)
			spoken += 1
			await _wait(0.5)
		if spoken >= 8:
			break
	rec["talk_lines"] = spoken
	_beat("quiet by the fire", "", "listening to the night")
	for c in [mika, luna]:
		if c and (c as WorldCharacter).ground_pose == "sit":
			(c as WorldCharacter).play_gesture("sit_ground_loop", 0.6, 0.6)
			(c as WorldCharacter).look_head_at((c as WorldCharacter).global_position + Vector3(0, 6, 0) - (c as WorldCharacter).global_transform.basis.z * 4.0)
	await _pass_time_to(21.5, 25.0)
	for c in [mika, luna]:
		if c:
			(c as WorldCharacter).look_head_at(null)


## Let the world clock run on to hour `h` over `real_s` seconds (evenings pass, nights pass).
func _pass_time_to(h: float, real_s: float) -> void:
	var now := WorldState.hour_f()
	var dh := h - now
	if dh < 0.0 and dh > -6.0:
		return          # already past it (a long fireside talk ran over): never wrap round into tomorrow
	if dh < 0.0:
		dh += 24.0
	var minutes := dh * 60.0
	WorldState.clock_boost = clampf(minutes / maxf(real_s * WorldState.clock_rate, 0.01), 1.0, 2000.0)
	var target := WorldState.world_min + minutes
	var t := 0.0
	while WorldState.world_min < target and t < real_s * 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	WorldState.clock_boost = 1.0


# ------------------------------------------------------------------ night
func _danger() -> float:
	var lg: Dictionary = jd.leg()
	var d := float(lg.get("danger", 0.2))
	if not (lg.get("habitats", []) as Array).is_empty():
		d += 0.15
	return d


func _lie(c: WorldCharacter, bed: Vector3) -> void:
	await _unsit(c)
	var fire_p: Vector3 = w.camp.fire
	var away := Vector3(bed.x - fire_p.x, 0, bed.z - fire_p.z).normalized()
	await _walk(c, bed + away * 0.2)
	await _face(c, bed + away * 2.0)
	await c.lie_down(0.6)


func _night(cp: Dictionary) -> void:
	var dz := _danger()
	var watch := dz >= 0.4 and luna != null
	(rec.watch as Array).append({"decided": "keep watch in turns" if watch else "both sleep", "danger": snappedf(dz, 0.01)})
	_beat("bedtime", "", "danger %.2f -> %s" % [dz, "watch in turns" if watch else "both sleep"])
	if watch:
		await _say("luna", "first_watch")
		await _say("mika", "sleep_first")
		await _lie(mika, (cp.beds as Array)[0])
		_beat("first watch", "luna", "Mika asleep")
		(rec.watch as Array).append({"who": "luna", "from": WorldState.clock_text()})
	else:
		if luna:
			_lie(luna, (cp.beds as Array)[1])
		await _lie(mika, (cp.beds as Array)[0])
		await _wait(2.0)
	await _pass_time_to(0.0, 18.0)
	if watch and fire:
		fire.feed(90.0)
		_beat("a branch on the fire", "luna", "it flares up")
	var habitats: Array = jd.leg().get("habitats", [])
	if watch and habitats.has("mossback") and not WorldState.journey.get("met_mossback", false):
		await _pass_time_to(1.5, 10.0)
		await _encounter(cp, "mossback")
	else:
		await _pass_time_to(5.8, 25.0)


func _encounter(cp: Dictionary, kind: String) -> void:
	var fire_p: Vector3 = cp.fire
	var map := mika.get_world_3d().navigation_map
	var dir := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf_range(-1.2, 1.2))
	var at := NavigationServer3D.map_get_closest_point(map, fire_p + dir * 26.0)
	var mon: Monster = main.spawner.spawn(kind, at)
	rec.encounter = {"kind": kind, "at": WorldState.clock_text()}
	if mon == null:
		return
	WorldState.journey["met_mossback"] = true
	var uid := String(mon.id)
	mon.home = fire_p
	_beat("something in the dark", "", "%s, %.0f m from the fire" % [mon.def.get("name", kind), at.distance_to(fire_p)])
	await _wait(2.5)
	luna.look_head_at(mon.global_position + Vector3(0, 2.0, 0))
	await _say("luna", "notice")
	await _unsit(luna)
	await _face(luna, mon.global_position)
	await _walk(luna, mika.global_position + (luna.global_position - mika.global_position).normalized() * 0.9, false)
	luna.reaction.pose("rx_crouch_help", 0.5)
	await _say("luna", "wake_mika")
	luna.reaction.release(0.5)
	await mika.get_up()
	await _say("mika", "woken", false)
	if is_instance_valid(mon):
		mika.look_head_at(mon.global_position + Vector3(0, 2.0, 0))
	_beat("both awake, facing it", "", "the fire between them and it")
	var res := {}
	if is_instance_valid(mon) and mon.alive():
		mon.target_mage = mika
		mon.mstate = "chase"
		var go := func(b, who: String) -> void:
			if b == null:
				res[who] = {}
				return
			b.current = {"kind": "hunt", "label": "drive it off", "stage": "starting"}
			res[who] = await b.run_activity({"kind": "hunt", "key": "hunt:" + mon.id, "monster": mon.id, "monster_kind": kind, "tier": mon.tier(), "label": "drive it off"})
			b.current = {}
		go.call(main.mage_brains.get("luna"), "luna")
		go.call(main.mage_brains.get("mika"), "mika")
		var t := 0.0
		while res.size() < 2 and t < 150.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
	var fled := String(Monster.last_fled.get("uid", "")) == uid
	var gone := not is_instance_valid(mon) or not mon.alive()
	rec.encounter["outcome"] = "it fled from the fire" if fled else ("they drove it off" if gone else "it went back into the dark")
	rec.encounter["mika"] = str(res.get("mika", {}).get("detail", ""))
	rec.encounter["luna"] = str(res.get("luna", {}).get("detail", ""))
	_beat("the creature is gone", "", rec.encounter.outcome)
	jd.note("a %s came to the camp in the night; %s" % [kind, rec.encounter.outcome], "encounter")
	if fled:
		(WorldState.journey.unresolved as Array).append("the %s of %s is still out there" % [kind, String(jd.leg().get("name", "the road"))])
	await _wait(1.0)
	await _walk(mika, fire_p + Vector3(-0.8, 0, 1.2))
	await _walk(luna, fire_p + Vector3(0.9, 0, 1.0))
	await _face(mika, luna.global_position)
	await _say("mika", "after_encounter")
	await _say("luna", "after_encounter")
	await _say("mika", "take_watch")
	await _say("luna", "sleep_now", false)
	await _lie(luna, (cp.beds as Array)[1])
	await _walk(mika, (cp.seats as Array)[0])
	await _face(mika, fire_p)
	await _sit(mika)
	(rec.watch as Array).append({"who": "mika", "from": WorldState.clock_text()})
	_beat("second watch", "mika", "Luna asleep")
	if fire:
		fire.feed(120.0)
	await _pass_time_to(5.9, 25.0)


# ------------------------------------------------------------------ morning
func _morning(cp: Dictionary) -> void:
	_beat("dawn", "", "the light comes up through the trees")
	await _pass_time_to(6.4, 8.0)
	var sleeper: WorldCharacter = null
	if luna and luna.ground_pose == "lie":
		sleeper = luna
	elif mika.ground_pose == "lie":
		sleeper = mika
	var waker: WorldCharacter = mika if sleeper == luna else luna
	if sleeper and waker:
		await _unsit(waker)
		await _walk(waker, sleeper.global_position + (waker.global_position - sleeper.global_position).normalized() * 0.9)
		waker.reaction.pose("rx_crouch_help", 0.5)
		await _say(waker.character_id, "wake_mate")
		waker.reaction.release(0.5)
		await sleeper.get_up()
		await _say(sleeper.character_id, "morning", false)
		sleeper.play_gesture("stretch_arms", 0.3, 0.5)
		await _wait(sleeper.animation_length("stretch_arms") * 0.8)
	for c in [mika, luna]:
		if c and (c as WorldCharacter).ground_pose == "lie":
			await (c as WorldCharacter).get_up()
		elif c and (c as WorldCharacter).ground_pose == "sit":
			await _unsit(c)
	_beat("awake", "", "both up")
	for c in [mika, luna]:
		if c == null:
			continue
		var wc := c as WorldCharacter
		# Mika keeps the food: she draws an apple for herself, and one she hands to Luna
		var apple: HoldableObject = null
		if wc == mika:
			apple = await _draw(mika, "apple_mika", "an apple", _model("food_apple_01", 1.0), 0.04)
		elif luna:
			await _walk(mika, luna.global_position + (mika.global_position - luna.global_position).normalized() * 0.85)
			var mine: HoldableObject = mika.handler.held
			if mine:
				mika.handler.held = null
				mine.visible = false
			var gift := await _draw(mika, "apple_luna", "an apple", _model("food_apple_01", 1.0), 0.04)
			if gift and await _hand_over(mika, luna, gift):
				apple = gift
			if mine:
				mine.visible = true
				mika.handler.held = mine
			if apple == null:
				continue
		if apple:
			for k in 2:
				var head := wc.skeleton.global_transform * wc.skeleton.get_bone_global_pose(wc.skeleton.find_bone("Head")).origin
				var mouth := head - wc.global_transform.basis.z * 0.12 + Vector3(0, -0.06, 0)
				if wc.handler.can_reach(mouth):
					await wc.handler.reach(mouth, 0.5)
					wc.set_expression("aa", 0.5)
					await _wait(0.4)
					wc.set_expression("aa", 0.0)
					await wc.handler.relax(0.4)
			wc.handler.held = null
			apple.queue_free()
	_beat("breakfast", "", "an apple each")
	var pot: HoldableObject = props.get("pot")
	if fire:
		if pot:
			await _walk(mika, (cp.fire as Vector3) + Vector3(0.7, 0, 0.4))
			await _kneel(mika)
			if mika.handler.can_reach(pot.grasp_point()) and await mika.handler.grasp(pot):
				await mika.handler.relax(0.3)
				await _rise(mika)
				if mika.handler.can_reach((cp.fire as Vector3) + Vector3(0, 0.7, 0)):
					await mika.handler.carry_to((cp.fire as Vector3) + Vector3(0, 0.55, 0), 0.5)
					await mika.handler.set_tilt(1.2, 0.6)
				fire.douse()
				_beat("fire doused", "mika", "water over the embers")
				await _wait(1.2)
				await mika.handler.set_tilt(0.0, 0.4)
				await _put(mika, (cp.fire as Vector3) + Vector3(0.8, 0, 0.8), 0.0)
			else:
				await _rise(mika)
		if fire.lit:
			fire.douse()
	await _say("mika", "pack", false)
	for i in 2:
		var bed: Node3D = props.get("bed_%d" % i)
		var c2: WorldCharacter = mika if i == 0 else luna
		if bed == null or c2 == null:
			continue
		await _walk(c2, bed.global_position + Vector3(0.6, 0, 0))
		await _kneel(c2)
		var tw := create_tween()
		tw.tween_property(bed, "scale", Vector3(1, 1, 0.08), 1.4).set_trans(Tween.TRANS_SINE)
		await _wait(1.5)
		bed.queue_free()
		await _rise(c2)
	# everything back into the rings: the rolled bedrolls (Luna), the pot, the bowls and the spoon
	for i in 2:
		if luna:
			var roll := _holdable("roll_%d" % i, "a rolled wool bedroll", _roll_mesh(Color(0.55, 0.42, 0.3) if i == 0 else Color(0.3, 0.33, 0.45)), ((cp.beds as Array)[i] as Vector3) + Vector3(0, 0.1, 0), 0.1)
			await _store(luna, "roll_%d" % i, "a rolled wool bedroll", roll)
	for spec in [["pot", luna if luna else mika, "the cooking pot"], ["spoon", mika, "a wooden spoon"], ["bowl_mika", mika, "a wooden bowl"], ["bowl_luna", mika, "a wooden bowl"]]:
		var node: Node3D = props.get(String(spec[0]))
		if node and is_instance_valid(node):
			await _store(spec[1], String(spec[0]), String(spec[2]), node)
	_beat("packed", "", "ready to walk on")
	if luna:
		await _say("luna", "ready", false)
	await _wait(1.0)
