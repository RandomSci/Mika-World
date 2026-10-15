class_name WorldStreamingManager
extends Node
## Streams areas in and out. Only ONE area scene is instantiated at a time; the others exist
## only as registry data (and, for up to CACHE_MAX recently used/predicted areas, as loaded
## resources that can be dropped). Loading is two-phase and threaded:
##   1. ResourceLoader.load_threaded_request(scene)   → once LOADED, read script RESOURCES
##   2. load_threaded_request() for every texture/model the area declares
## Activation runs the area's build steps under a travel mask within a per-frame time budget,
## then bakes navigation asynchronously. Unloading frees the node tree (render/physics/nav
## objects go with it), drops the cache entry and releases now-unused Kit materials.

signal area_activated(area_id: String, report: Dictionary)
signal transition_started(from_area: String, to_area: String)
signal transition_failed(to_area: String, reason: String)
signal preload_progress(area_id: String, progress: float)

const CACHE_MAX := 3            # areas whose resources may stay resident (current + predicted + previous)
const BUILD_BUDGET_MS := 10.0   # per-frame build budget during activation

var characters_root: Node3D
var camera_rig: Node
var overlay: TravelOverlay
var current: AreaBase
var current_id := ""
var state := "idle"             # idle | preloading | transition_out | unloading | activating | baking | transition_in
var cache := {}                 # area_id -> {"scene": PackedScene, "resources": Array, "used": msec}
var loading := {}               # area_id -> {"phase": 1|2, "paths": PackedStringArray, "t0": msec, "error": ""}
var last_report := {}
var prewarm_once: Callable  # run once behind the first travel mask (shader pipeline compilation)
var history: Array[Dictionary] = []


func _process(_delta: float) -> void:
	for id in loading.keys():
		_poll(id)


# ------------------------------------------------------------------ preloading
func preload_area(id: String) -> void:
	if cache.has(id) or loading.has(id) or not WorldState.areas.has(id):
		return
	var scene_path: String = WorldState.areas[id].scene
	if not ResourceLoader.exists(scene_path):
		loading[id] = {"phase": 0, "paths": PackedStringArray(), "t0": Time.get_ticks_msec(), "error": "scene missing: " + scene_path}
		return
	var err := ResourceLoader.load_threaded_request(scene_path, "PackedScene", true)
	loading[id] = {"phase": 1, "paths": PackedStringArray([scene_path]), "t0": Time.get_ticks_msec(), "error": "" if err == OK else error_string(err)}


func _poll(id: String) -> void:
	var L: Dictionary = loading[id]
	if L.error != "" or L.phase == 0:
		return
	var progress := 0.0
	var all_done := true
	for p in L.paths:
		var prog := []
		var st := ResourceLoader.load_threaded_get_status(p, prog)
		match st:
			ResourceLoader.THREAD_LOAD_LOADED:
				progress += 1.0
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				progress += prog[0] if not prog.is_empty() else 0.0
				all_done = false
			_:
				L.error = "failed to load %s (status %d)" % [p, st]
				return
	preload_progress.emit(id, progress / maxf(L.paths.size(), 1))
	if not all_done:
		return
	if L.phase == 1:
		var scene: PackedScene = ResourceLoader.load_threaded_get(L.paths[0])
		var res_paths := _declared_resources(scene)
		L.scene = scene
		L.phase = 2
		L.paths = PackedStringArray()
		for p in res_paths:
			if ResourceLoader.exists(p):
				ResourceLoader.load_threaded_request(p, "", true)
				L.paths.append(p)
		return
	var resources := []
	for p in L.paths:
		resources.append(ResourceLoader.load_threaded_get(p))
	cache[id] = {"scene": L.scene, "resources": resources, "used": Time.get_ticks_msec(),
		"preload_ms": Time.get_ticks_msec() - L.t0, "resource_count": resources.size()}
	loading.erase(id)
	_trim_cache()


func _declared_resources(scene: PackedScene) -> Array:
	var st := scene.get_state()
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == "script":
			var script: Script = st.get_node_property_value(0, i)
			for m in script.get_script_method_list():
				if m.name == "resources":
					return script.call("resources")
			return script.get_script_constant_map().get("RESOURCES", [])
	return []


func is_ready(id: String) -> bool:
	return cache.has(id)


func load_error(id: String) -> String:
	return loading[id].error if loading.has(id) else ""


func _trim_cache() -> void:
	while cache.size() > CACHE_MAX:
		var oldest := ""
		var t := 1 << 62
		for id in cache:
			if id != current_id and cache[id].used < t:
				t = cache[id].used
				oldest = id
		if oldest == "":
			return
		cache.erase(oldest)


func status() -> Dictionary:
	var l := {}
	for id in loading:
		l[id] = {"phase": loading[id].phase, "error": loading[id].error}
	var c := {}
	for id in cache:
		c[id] = {"resources": cache[id].resource_count, "preload_ms": cache[id].preload_ms}
	return {"state": state, "current_area": current_id, "loading": l, "cached": c, "instantiated_areas": _instantiated_count(),
		"last_transition": last_report}


func _instantiated_count() -> int:
	return get_tree().get_nodes_in_group("streamed_area").size()


# ------------------------------------------------------------------ transitions
## Travel the character to `to_area`, arriving at the gate that faces `from_area`.
## Returns the transition report (or {"ok": false, "reason": ...}).
func travel(to_area: String, character: WorldCharacter, masked := true) -> Dictionary:
	if state != "idle":
		return {"ok": false, "reason": "transition already in progress (%s)" % state}
	if not WorldState.areas.has(to_area):
		return {"ok": false, "reason": "unknown area " + to_area}
	var t_start := Time.get_ticks_msec()
	var from_area := current_id
	var region_name: String = WorldState.regions[WorldState.areas[to_area].region].name
	var route_text: String = WorldState.adjacency.get(from_area, {}).get(to_area, "")
	state = "preloading"
	transition_started.emit(from_area, to_area)
	preload_area(to_area)
	if masked and overlay:
		await overlay.fade_out(region_name, _area_title(to_area), route_text)
	var t_masked := Time.get_ticks_msec()
	var wait_frames := 0
	while not cache.has(to_area):
		if load_error(to_area) != "":
			var reason := load_error(to_area)
			loading.erase(to_area)
			state = "idle"
			if masked and overlay:
				await overlay.fade_in()
			transition_failed.emit(to_area, reason)
			return {"ok": false, "reason": reason, "stayed_in": from_area}
		if overlay:
			overlay.set_progress(_progress(to_area))
		wait_frames += 1
		await get_tree().process_frame
	var t_loaded := Time.get_ticks_msec()
	# --- instantiate + validate the new area BEFORE touching the old one (failure keeps her where she is)
	var entry: Dictionary = cache[to_area]
	entry.used = Time.get_ticks_msec()
	var inst: Node = entry.scene.instantiate()
	if not (inst is AreaBase):
		inst.free()
		cache.erase(to_area)
		state = "idle"
		if masked and overlay:
			await overlay.fade_in()
		var why := "scene for %s did not produce an AreaBase (script error?)" % to_area
		transition_failed.emit(to_area, why)
		return {"ok": false, "reason": why, "stayed_in": from_area}
	var area: AreaBase = inst
	# --- unload the old area completely
	state = "unloading"
	var mem_before := _mem()
	character.set_physics_process(false)
	character.velocity = Vector3.ZERO
	if current:
		current.remove_from_group("streamed_area")
		current.queue_free()
		current = null
		await get_tree().process_frame
		await get_tree().process_frame
	var released := Kit.release_unused()
	var t_unloaded := Time.get_ticks_msec()
	# --- activate the new one in budgeted steps
	state = "activating"
	area.name = "Area_" + to_area
	area.setup(to_area)
	area.add_to_group("streamed_area")
	get_parent().add_child(area)
	current = area
	current_id = to_area
	var steps: Array = area.activate_steps()
	var worst_step := 0.0
	var step_ms := []
	var frames := 0
	var i := 0
	while i < steps.size():
		var f0 := Time.get_ticks_usec()
		while i < steps.size() and (Time.get_ticks_usec() - f0) < BUILD_BUDGET_MS * 1000.0:
			var s0 := Time.get_ticks_usec()
			steps[i].call()
			var dt := (Time.get_ticks_usec() - s0) / 1000.0
			worst_step = maxf(worst_step, dt)
			step_ms.append(snappedf(dt, 0.1))
			i += 1
		frames += 1
		await get_tree().process_frame
	var t_built := Time.get_ticks_msec()
	var layout_hash := _layout_hash(area)
	if RenderProfile.options.has("hashdump"):
		var f := FileAccess.open("user://layout_%s_%d.txt" % [to_area, history.size()], FileAccess.WRITE)
		for n in area.find_children("*", "GeometryInstance3D", true, false):
			f.store_line("%s\t%s" % [area.get_path_to(n), str((n as Node3D).global_transform.origin.snapped(Vector3.ONE * 0.001))])
		f.close()
	state = "baking"
	await area.bake_navigation()
	var t_nav := Time.get_ticks_msec()
	# --- place the character, keep its state, snap the camera
	var at: Transform3D = area.spawn_point(from_area)
	character.global_transform = at
	character.velocity = Vector3.ZERO
	character.world = area
	character.set_physics_process(true)
	if camera_rig and camera_rig.has_method("snap_behind"):
		camera_rig.snap_behind()
	WorldState.current_area = to_area
	WorldState.enter_location(area.location_at(at.origin))
	if prewarm_once.is_valid():
		var pw := prewarm_once
		prewarm_once = Callable()
		await pw.call()
	state = "transition_in"
	if masked and overlay:
		await overlay.fade_in()
	state = "idle"
	var mem_after := _mem()
	last_report = {"ok": true, "from": from_area, "to": to_area, "route": route_text,
		"total_ms": Time.get_ticks_msec() - t_start, "mask_ms": t_masked - t_start,
		"wait_for_preload_ms": t_loaded - t_masked, "preload_wait_frames": wait_frames, "preload_ms": entry.preload_ms,
		"unload_ms": t_unloaded - t_loaded, "build_ms": t_built - t_unloaded, "build_frames": frames,
		"worst_build_step_ms": snappedf(worst_step, 0.01), "step_ms": step_ms, "nav_bake_ms": t_nav - t_built,
		"kit_released": released, "resources_preloaded": entry.resource_count,
		"mem_static_mb_before": mem_before.static_mb, "mem_static_mb_after": mem_after.static_mb,
		"video_mb_after": mem_after.video_mb, "nodes_after": mem_after.nodes, "objects_after": mem_after.objects,
		"nav_regions_after": mem_after.nav_regions, "instantiated_areas": _instantiated_count(),
		"arrived_location": WorldState.current_location, "layout_hash": layout_hash}
	history.append(last_report)
	if history.size() > 200:
		history.pop_front()
	area_activated.emit(to_area, last_report)
	print("[stream] ", JSON.stringify(last_report))
	return last_report


func _progress(id: String) -> float:
	if cache.has(id):
		return 1.0
	if not loading.has(id):
		return 0.0
	return 0.5 if loading[id].phase == 2 else 0.15


func _area_title(id: String) -> String:
	var names := []
	for l in WorldState.locations_in_area(id):
		names.append(WorldState.locations[l].name)
	return " · ".join(names)


static func _mem() -> Dictionary:
	return {"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nav_regions": int(Performance.get_monitor(Performance.NAVIGATION_REGION_COUNT))}


## Deterministic fingerprint of everything placed in an area (mesh + multimesh instance transforms).
## Identical on every visit ⇒ no reseeding, no spontaneous world changes.
static func _layout_hash(area: Node) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var positions := []
	for n in area.find_children("*", "GeometryInstance3D", true, false):
		var rel := String(area.get_path_to(n))
		if rel.contains("AltarCrystal") or rel.contains("Animated"):
			continue  # deliberately animated (bobbing crystals, ambient creatures), not layout
		if n is MeshInstance3D:
			ctx.update(var_to_bytes((n as Node3D).global_transform.origin.snapped(Vector3.ONE * 0.001)))
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			var mm := (n as MultiMeshInstance3D).multimesh
			ctx.update(var_to_bytes(mm.instance_count))
			for i in mini(mm.instance_count, 64):
				ctx.update(var_to_bytes(mm.get_instance_transform(i).origin.snapped(Vector3.ONE * 0.001)))
	return ctx.finish().hex_encode().left(12)
