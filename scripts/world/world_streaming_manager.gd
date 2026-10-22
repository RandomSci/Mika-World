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
## Behind the opaque travel card a build may use far more of each frame: with 8 ms slices a 1 s job spread over 4 s of
## card (one 33 ms frame per slice, 22 Oct world trip: builds of 3.9, 7.5 and 8.6 s). Nobody sees those frames, and
## 28 ms keeps every one well under 100 ms. In view (an unmasked build) the small slices stay.
const MASKED_SLICE_US := 28000
const OPEN_SLICE_US := 8000
static var masked_build := false


## How long a sliced build step may run before it hands the frame back.
static func slice_us() -> int:
	return MASKED_SLICE_US if masked_build else OPEN_SLICE_US

var characters_root: Node3D
var camera_rig: Node
var overlay: TravelOverlay
var current: AreaBase
var current_id := ""
var state := "idle"             # idle | preloading | transition_out | unloading | activating | baking | transition_in
var cache := {}                 # area_id -> {"scene": PackedScene, "resources": Array, "used": msec}
var loading := {}               # area_id -> {"phase": 1|2, "paths": PackedStringArray, "t0": msec, "error": ""}
var last_report := {}
var build_step := -1                    # the area step running now (QA traces)
var prewarm_once: Callable  # run once behind the first travel mask (shader pipeline compilation)
var before_reveal: Array = []   # Callables awaited on EVERY travel behind the mask, after the area is built (AdaptiveQuality)
var history: Array[Dictionary] = []
var _slow_frames := []


func _process(delta: float) -> void:
	for id in loading.keys():
		_poll(id)
	if state != "idle" and delta > 0.05:
		_slow_frames.append([state, snappedf(delta * 1000.0, 1.0)])       # (in the travel report: frames over 50 ms)


# ------------------------------------------------------------------ preloading
## Areas whose heavy build runs on a thread ahead of arrival: id -> [start, ready] (static Callables).
const LAKE_BUILD := preload("res://scripts/areas/lantern_lake.gd")
var prebuilders := {"lantern_lake": [Callable(LAKE_BUILD, "prebuild_start"), Callable(LAKE_BUILD, "prebuild_ready")]}


## Called as soon as a trip there is decided (the brain's walk, a journey): the scene loads and the area's heavy
## build starts in the background, so the arrival behind the travel card is short.
func prebuild(id: String) -> void:
	preload_area(id)
	if prebuilders.has(id) and id != current_id:
		(prebuilders[id][0] as Callable).call()


func _prebuilt(id: String) -> bool:
	return not prebuilders.has(id) or bool((prebuilders[id][1] as Callable).call())


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
		var res_paths: Array = _declared_resources(scene).duplicate()     # (an area's RESOURCES constant is read-only)
		for rp in _recorded_resources(id):
			if not res_paths.has(rp):
				res_paths.append(rp)
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


# ------------------------------------------------------------------ recorded resources
## The textures and shaders an area really used on its last build (user://area_preload.json): preloaded on a thread
## with its scene during the walk, so the build never loads them itself (the Mentor's Tower's ground material and
## textures took 0.67 s in one frame of its build, 2026-10-22).
const AREA_PRELOAD := "user://area_preload.json"
var _recorded_layout := {}


func _recorded_resources(id: String) -> Array:
	if not FileAccess.file_exists(AREA_PRELOAD):
		return []
	var j = JSON.parse_string(FileAccess.get_file_as_string(AREA_PRELOAD))
	return (j.get(id, []) as Array) if j is Dictionary else []


## After a build, in the background (a few nodes per frame): every material's shader and texture file.
func _record_resources(area: Node, id: String, layout: String) -> void:
	var paths := {}
	var seen := {}
	var t0 := Time.get_ticks_usec()
	var add_res := func(r):
		if r is Resource and String((r as Resource).resource_path).begins_with("res://") and not String((r as Resource).resource_path).contains("::"):
			paths[(r as Resource).resource_path] = true
	var scan_mat := func(m):
		if m == null or seen.has(m.get_instance_id()):
			return
		seen[m.get_instance_id()] = true
		if m is ShaderMaterial and (m as ShaderMaterial).shader:
			add_res.call((m as ShaderMaterial).shader)
			for u in (m as ShaderMaterial).shader.get_shader_uniform_list():
				add_res.call((m as ShaderMaterial).get_shader_parameter(u.name))
		elif m is BaseMaterial3D:
			for pr in (m as Object).get_property_list():
				if String(pr.name).ends_with("_texture"):
					add_res.call((m as Object).get(pr.name))
	if _recorded_layout.get(id, "") == layout and not _recorded_resources(id).is_empty():
		return                                     # (this layout's list is already on disk)
	# walked a little per frame (find_children over the tower's 10,800 nodes held a frame 0.2 s)
	var stack: Array = [area]
	while not stack.is_empty():
		var nd = stack.pop_back()
		if not is_instance_valid(nd):
			continue
		for c in (nd as Node).get_children():
			stack.append(c)
		if not (nd is GeometryInstance3D):
			continue
		var g = nd
		scan_mat.call((g as GeometryInstance3D).material_override)
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
		if mesh:
			for si in mesh.get_surface_count():
				scan_mat.call(mesh.surface_get_material(si))
		if Time.get_ticks_usec() - t0 > 4000:
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
			if not is_instance_valid(area):
				return
	var all := {}
	if FileAccess.file_exists(AREA_PRELOAD):
		var j = JSON.parse_string(FileAccess.get_file_as_string(AREA_PRELOAD))
		if j is Dictionary:
			all = j
	all[id] = paths.keys()
	_recorded_layout[id] = layout
	var f := FileAccess.open(AREA_PRELOAD, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))
	if RenderProfile.options.has("stream-trace"):
		print("[streamtrace] %s: %d resource files recorded for preloading" % [id, paths.size()])


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
	if not StreamFlags.area_allowed(to_area):
		print("[stream] %s is closed tonight (StreamFlags regions): not loaded" % to_area)
		return {"ok": false, "reason": "%s is closed tonight" % to_area}
	var t_start := Time.get_ticks_msec()
	var from_area := current_id
	var region_name: String = WorldState.regions[WorldState.areas[to_area].region].name
	var route_text: String = WorldState.adjacency.get(from_area, {}).get(to_area, "")
	state = "preloading"
	_slow_frames = []
	transition_started.emit(from_area, to_area)
	prebuild(to_area)
	if masked and overlay:
		await overlay.fade_out(region_name, _area_title(to_area), route_text)
	var t_masked := Time.get_ticks_msec()
	var wait_frames := 0
	while not cache.has(to_area) or not _prebuilt(to_area):
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
	masked_build = masked and overlay != null
	var worst_step := 0.0
	var step_ms := []
	var frames := 0
	var i := 0
	while i < steps.size():
		var f0 := Time.get_ticks_usec()
		while i < steps.size() and (Time.get_ticks_usec() - f0) < (MASKED_SLICE_US if masked_build else BUILD_BUDGET_MS * 1000.0):
			if steps[i] is String:          # "frame": the area asks for a frame boundary here
				i += 1
				break
			var s0 := Time.get_ticks_usec()
			build_step = i
			if RenderProfile.options.has("stream-trace"):
				print("[streamtrace] %s step %d starts (frame %d, %.0f ms into the frame budget)" % [to_area, i, Engine.get_process_frames(), (Time.get_ticks_usec() - f0) / 1000.0])
			var fr0 := Engine.get_process_frames()
			await steps[i].call()            # (a long step may hand frames back as it goes: it is awaited to the end)
			var dt := (Time.get_ticks_usec() - s0) / 1000.0
			if RenderProfile.options.has("stream-trace") and dt > 60.0:
				print("[streamtrace] %s step %d took %.0f ms over %d frames" % [to_area, i, dt, Engine.get_process_frames() - fr0])
			if Engine.get_process_frames() != fr0:
				f0 = Time.get_ticks_usec()       # it ran over several frames: a fresh budget for this one
			worst_step = maxf(worst_step, dt)
			step_ms.append(snappedf(dt, 0.1))
			i += 1
		frames += 1
		var fw0 := Time.get_ticks_usec()
		await get_tree().process_frame
		if RenderProfile.options.has("stream-trace"):
			print("[streamtrace] %s frame %d: steps to %d, step work %.0f ms, frame wait %.0f ms" % [to_area, frames, i, (fw0 - f0) / 1000.0, (Time.get_ticks_usec() - fw0) / 1000.0])
	var t_built := Time.get_ticks_msec()
	masked_build = false
	NatureKit.save_warm_list()
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
	at.origin = area.free_spot(at.origin, [character.get_rid()] as Array[RID])      # never inside something solid
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
	for cb in before_reveal:
		if (cb as Callable).is_valid():
			await (cb as Callable).call()
	if area.has_method("warm_up") and camera_rig and camera_rig.get("camera"):
		await area.warm_up(camera_rig.camera)
	state = "transition_in"
	if masked and overlay:
		await overlay.fade_in()
	state = "idle"
	if not RenderProfile.options.has("no-record"):
		_record_resources(area, to_area, layout_hash)
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
		"arrived_location": WorldState.current_location, "layout_hash": layout_hash, "slow_frames": _slow_frames.duplicate()}
	history.append(last_report)
	if history.size() > 200:
		history.pop_front()
	var ae0 := Time.get_ticks_usec()
	area_activated.emit(to_area, last_report)
	if RenderProfile.options.has("stream-trace"):
		print("[streamtrace] %s arrival handlers %.0f ms" % [to_area, (Time.get_ticks_usec() - ae0) / 1000.0])
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
