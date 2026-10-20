extends AreaBase
## LANTERN LAKE in the living world (Day 2): the env-test scene (scripts/areas/lantern_lake.gd, embedded) as a place
## of the home region - a calm mountain lake at dusk-light, hundreds of paper lanterns rising over it and floating on
## the water, an old wooden pier, reeds, pines, mist and fireflies. A path runs down to it past Starfall Hill.
## Their second night spot (Levels 1-9 nights: Starfall Hill or here): they walk down together, sit at the end of the
## pier, watch the lanterns and now and then let one go (SanctuaryBrain._lakewatch).
## Walkable: the near bank and the pier (a ramp onto the deck); the lake itself is never on the navmesh.

const LAKE := preload("res://scripts/areas/lantern_lake.gd")
const PIER_X := 4.0
const DECK_Y := 0.62
const SIT_Z := -2.2                      # where they sit at the end of the pier, facing the lake (-Z)
const SIT_GAP := 0.9

var lake: Node3D


static func resources() -> Array:
	return []


func env_preset() -> Dictionary:
	return {"sun_shadows": false}


const SLICES := 10
var _pending: Array = []                 # the prebuilt lake's parts still to join the scene (a slice per frame)
var _pending_n := 0


## "frame" asks WorldStreamingManager for a frame boundary: the prebuilt lake joins the scene a slice per frame (all of
## it in one frame was a 500 ms frame behind the travel card, the renderer taking every mesh and instance at once).
func build_steps() -> Array:
	var st: Array = [_lake]
	for i in SLICES:
		st.append("frame")
		st.append(_attach_slice.bind(i))
	st.append_array(["frame", _ground, _links])
	return st


func _lake() -> void:
	nav_aabb = AABB(Vector3(-22.0, -1.5, -4.5), Vector3(54.0, 12.0, 58.0))
	sun.visible = false
	sun.light_energy = 0.0
	lake = LAKE.take_prebuilt()             # built on a thread while they walked down (WorldStreamingManager.prebuild)
	if lake == null:
		lake = LAKE.new()
	else:
		# colliders stay (the navmesh bake needs the pier); everything else joins a slice per frame
		for ch in lake.get_children():
			if ch is StaticBody3D or not ch.find_children("*", "StaticBody3D", true, false).is_empty():
				continue
			lake.remove_child(ch)
			_pending.append(ch)
		_pending_n = _pending.size()
	lake.name = "Lake"
	lake.set("embedded", true)
	lake.set("host_env", env)
	add_child(lake)                          # (its _ready builds the place into this area's environment)
	if not _pending.is_empty():
		lake.set_process(false)              # (its lanterns are not all in the scene yet)
		lake.set_physics_process(false)


var _hidden: Array = []                  # slices attached hidden: shown one per frame in warm_up (the camera is at the lake then)


func _attach_slice(i: int) -> void:
	var n := _pending.size() if i == SLICES - 1 else ceili(_pending_n / float(SLICES))
	var sl := []
	for k in mini(n, _pending.size()):
		var ch: Node = _pending.pop_front()
		if ch is Node3D and (ch as Node3D).visible:
			(ch as Node3D).visible = false
			sl.append(ch)
		lake.add_child(ch)
	if not sl.is_empty():
		_hidden.append(sl)
	if _pending.is_empty() and lake:
		lake.set_process(true)
		lake.set_physics_process(true)


## Behind the travel card, after the build (WorldStreamingManager.travel): every material of the lake, its boat and
## the dance glows drawn once, so none compiles on screen.
func warm_up(camera: Camera3D) -> void:
	# the lake's parts appear one slice per frame in front of the arrival camera: their materials compile a few at a time
	# (all of them in one frame was a 265 ms frame behind the travel card)
	for sl in _hidden:
		for ch in sl:
			if is_instance_valid(ch):
				(ch as Node3D).visible = true
		await get_tree().process_frame
	_hidden.clear()
	# the boat moored at the pier is built now too (1.2 s after the reveal it was a 140 ms frame on screen)
	if LakeRitual.instance and (not RenderProfile.options.has("mktest") or RenderProfile.options.has("lake-ritual") or String(RenderProfile.options.get("mktest", "")) == "golive_soak"):
		LakeRitual.instance._ensure_boat()
	await ShaderPrewarm.area(camera, self, ["res://shaders/lantern_lake", "res://shaders/real", "res://shaders/moonbloom",
		"res://shaders/anime/boat", "res://shaders/anime/dance"])


func h(x: float, z: float) -> float:
	return float(lake.call("h", x, z)) if lake else 0.0


func ground_at(x: float, z: float) -> float:
	if absf(x - PIER_X) < 1.1 and z < 9.2 and z > -3.6:
		return DECK_Y
	return h(x, z)


## The bank as a collider (a height field, 1 m cells) - only on land: under the water there is nothing to walk on, so
## the navmesh stops at the shore; plus a ramp from the bank up onto the deck.
func _ground() -> void:
	var x0 := -22
	var x1 := 32
	var z0 := 8
	var z1 := 54
	var wdt := x1 - x0 + 1
	var dpt := z1 - z0 + 1
	var hm := HeightMapShape3D.new()
	hm.map_width = wdt
	hm.map_depth = dpt
	var data := PackedFloat32Array()
	data.resize(wdt * dpt)
	for j in dpt:
		for i in wdt:
			data[j * wdt + i] = h(float(x0 + i), float(z0 + j))
	hm.map_data = data
	var body := StaticBody3D.new()
	body.name = "Bank"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = hm
	body.add_child(cs)
	body.position = Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
	add_child(body)
	# the ramp: from the bank 2.6 m behind the pier's land end up to the deck
	var zb := 11.6
	var zt := 8.9
	var yb := h(PIER_X, zb)
	var run := zb - zt
	var rise := DECK_Y - yb
	var ang := atan2(rise, run)
	var rb := StaticBody3D.new()
	rb.name = "PierRamp"
	var rcs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 0.1, sqrt(run * run + rise * rise) + 0.3)
	rcs.shape = box
	rb.add_child(rcs)
	rb.transform = Transform3D(Basis(Vector3.RIGHT, ang), Vector3(PIER_X, (yb + DECK_Y) * 0.5 - 0.05, (zb + zt) * 0.5))
	add_child(rb)


func _links() -> void:
	add_location("lantern_lake", Vector3(PIER_X, 0, 14.0), 32.0, Vector3(PIER_X, h(PIER_X, 13.0), 13.0),
		"Lantern Lake: a calm lake below Starfall Hill where paper lanterns rise over the water at night")
	add_gate("sanctuary", Vector3(PIER_X, h(PIER_X, 47.0), 47.0), Vector3(PIER_X, h(PIER_X, 41.0) + 0.05, 41.0), 0.0, 2.4)


## Their two places at the end of the pier (world), facing the lake.
func sit_spots() -> Array:
	return [to_global(Vector3(PIER_X - SIT_GAP * 0.5, DECK_Y, SIT_Z)), to_global(Vector3(PIER_X + SIT_GAP * 0.5, DECK_Y, SIT_Z))]


func lake_facing() -> Vector3:
	return to_global(Vector3(PIER_X, DECK_Y, -30.0))


## The lens while they sit on the pier: the lake scene's own shots, alternating - wide from the near shore among the
## reeds (the pier, the two of them small at its end, the lake full of lanterns, the mountains), then a medium from
## behind on the pier, three-quarter (both whole, the lake beyond). Never a face close-up.
func watch_shot(t: float) -> Dictionary:
	var cyc := fmod(t, 36.0)
	if cyc < 14.0:
		var e := smoothstep(0.0, 14.0, cyc)                  # wide: from the near shore among the reeds
		return {"pos": to_global(Vector3(lerpf(-1.9, -1.4, e), 1.38, lerpf(6.4, 5.8, e))), "look": to_global(Vector3(PIER_X + 2.0, 2.4, -12.0)),
			"fov": 55.0, "rate": 1.5, "cut": cyc < 0.06}
	if cyc < 26.0:
		var e2 := smoothstep(14.0, 26.0, cyc)                # low over the water off the end of the pier: the two from the front-left, small
		return {"pos": to_global(Vector3(lerpf(-2.2, -1.6, e2), 0.55, SIT_Z - lerpf(7.6, 7.1, e2))),
			"look": to_global(Vector3(PIER_X + 0.4, DECK_Y + 0.8, SIT_Z + 0.4)), "fov": 52.0, "rate": 1.5, "cut": absf(cyc - 14.0) < 0.06}
	var e3 := smoothstep(26.0, 36.0, cyc)                    # high over the bank: the whole lake, the pier, the lanterns
	return {"pos": to_global(Vector3(lerpf(-7.0, -5.5, e3), 8.5, lerpf(18.0, 16.5, e3))), "look": to_global(Vector3(PIER_X + 2.0, 1.0, -28.0)),
		"fov": 55.0, "rate": 1.5, "cut": absf(cyc - 26.0) < 0.06}


func release_lantern() -> void:
	if lake and lake.has_method("release_from_pier"):
		lake.release_from_pier()


## The lake keeps its own look: it is a night place. By day only the light comes up a little (they are rarely here).
func set_night(v: bool) -> void:
	night = v
	env.ambient_light_energy = 0.55 if v else 0.9
	env.tonemap_exposure = 1.0 if v else 1.12
	env.fog_density = 0.0042 if v else 0.0028
	# the stream's adaptive quality turns volumetric fog on in every area; the lake's look has none (Godot's default
	# density turned the whole scene into a flat violet wash)
	env.volumetric_fog_density = 0.0
	env.fog_sky_affect = 0.0
	sun.visible = false
	sun.light_energy = 0.0
	for n in get_tree().get_nodes_in_group("night_lights_" + str(get_instance_id())):
		n.visible = v
