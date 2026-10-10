class_name PhysicsTest
extends Node
## Collision / navigation regression (--physicstest[=area1,area2]). For every streamed area:
##  1. Audit: every visible, solid-looking mesh at body height must overlap a collider. Samples points on
##     the mesh surface between 0.15 m and 1.6 m above the ground and checks them against physics.
##     Flagged meshes are reported with their scene path (truthful list of "walk-through" props).
##  2. Wall push: from navmesh points near colliders, Mika is driven straight at the obstacle for
##     2.5 s with player-style input. Pass = she never ends up on the far side of the hit surface.
##  3. Path validity: navigation paths between random navmesh points are checked segment by segment
##     with a chest-height ray against static geometry (a path must not cross a wall).
##  4. Named checks (Sanctuary): chamber walls, gate, watchpoint stairs up/down, garden seat, library walls.
## Writes <shots_dir>/physics_test.json and quits.

var main: Node
var report := {"areas": {}, "named": {}}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 1234
	_run.call_deferred()


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	main.player.enabled = false
	await get_tree().create_timer(2.0).timeout
	if RenderProfile.options.has("pushcase"):
		# --pushcase=area,x,y,z,dx,dz : reproduce one wall push with a per-frame log
		var pc := String(RenderProfile.options.pushcase).split(",")
		await main.streaming.travel(pc[0], mika, false)
		await _wait_frames(10)
		var st := Vector3(float(pc[1]), float(pc[2]), float(pc[3]))
		var dr := Vector3(float(pc[4]), 0, float(pc[5])).normalized()
		mika.global_position = st + Vector3(0, 0.1, 0)
		await _wait_frames(2)
		for i in 75:
			mika.set_move_input(dr, true)
			await get_tree().physics_frame
			var cap := CapsuleShape3D.new(); cap.radius = 0.16; cap.height = 1.1
			var q := PhysicsShapeQueryParameters3D.new(); q.shape = cap; q.exclude = [mika.get_rid()]
			q.transform = Transform3D(Basis.IDENTITY, mika.global_position + Vector3(0, 0.85, 0))
			var hits := mika.get_world_3d().direct_space_state.intersect_shape(q, 4)
			print("[pushcase] %d pos=%s floor=%s wall=%s hits=%s" % [i, str(mika.global_position.snapped(Vector3.ONE * 0.01)), mika.is_on_floor(), mika.is_on_wall(), str(hits.map(func(h): return _name(h.collider)))])
		get_tree().quit()
		return
	var opt := String(RenderProfile.options.get("physicstest", "true"))
	var areas: Array = WorldState.areas.keys() if opt == "true" else Array(opt.split(","))
	for a in areas:
		if main.streaming.current_id != a:
			var r: Dictionary = await main.streaming.travel(a, mika, false)
			if not r.get("ok", false):
				report.areas[a] = {"error": "load failed"}
				continue
		await _wait_frames(6)
		var rec := {}
		rec["audit"] = _audit(main.world)
		rec["wall_push"] = await _wall_push(main.world, mika, 14)
		rec["paths"] = _paths(main.world, 25)
		if a == "sanctuary":
			report.named = await _named(main.world, mika)
		if a == "arcane_library":
			report.named_library = await _named_library(main.world, mika)
		report.areas[a] = rec
		print("[physicstest] %s audit_flagged=%d wall_push %d/%d paths_crossing %d/%d" % [a, rec.audit.flagged.size(),
			rec.wall_push.passed, rec.wall_push.tested, rec.paths.crossing, rec.paths.tested])
	var f := FileAccess.open(RenderProfile.shots_dir + "/physics_test.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[physicstest] done")
	get_tree().quit()


# ------------------------------------------------------------------ 1. audit
const SKIP_GROUPS := ["cat_trees", "cat_foliage", "cat_grass", "cat_vista"]


func _audit(world: Node3D) -> Dictionary:
	var space := world.get_world_3d().direct_space_state
	var flagged := []
	var checked := 0
	for n in world.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n
		if not gi.is_visible_in_tree() or gi is GPUParticles3D or gi is CPUParticles3D:
			continue
		if _skipped(gi, world):
			continue
		var mesh: Mesh = null
		var xforms: Array[Transform3D] = []
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
			xforms.append(gi.global_transform)
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
			var mm := (gi as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			for i in mini(mm.instance_count, 40):
				xforms.append(gi.global_transform * mm.get_instance_transform(i))
		if mesh == null or mesh is QuadMesh or mesh is PlaneMesh:
			continue
		var mat = gi.material_override
		if mat is ShaderMaterial and String((mat as ShaderMaterial).shader.resource_path).contains("magic"):
			continue
		for xf in xforms:
			var aabb: AABB = xf * mesh.get_aabb()
			if aabb.size.y < 0.5 or maxf(aabb.size.x, aabb.size.z) < 0.25:
				continue  # small clutter: walking "through" a pebble is acceptable
			var ground := _ground_y(space, aabb.get_center())
			if aabb.position.y > ground + 1.4 or aabb.end.y < ground + 0.35:
				continue  # entirely above head height or below the knees (canopies, rugs, floor decals)
			if aabb.size.x > 30.0 or aabb.size.z > 30.0:
				continue  # terrain / sky shells
			checked += 1
			var r := _surface_coverage(space, mesh, xf, ground)
			# only meshes standing on/next to walkable navmesh matter (she can only "walk through" what she can reach)
			var map := world.get_world_3d().navigation_map
			var c := aabb.get_center()
			var near_nav := NavigationServer3D.map_get_closest_point(map, Vector3(c.x, ground, c.z))
			var reach := Vector2(near_nav.x - c.x, near_nav.z - c.z).length() - maxf(aabb.size.x, aabb.size.z) * 0.5
			if r.samples >= 6 and r.covered < 0.35 and reach < 0.6 and not world._near_gate(c):
				var mname := String(mesh.resource_name) if mesh.resource_name != "" else mesh.resource_path.get_file()
				var matname := ""
				var mm2 = gi.material_override if gi.material_override else (mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else null)
				if mm2:
					matname = String(mm2.resource_name) if mm2.resource_name != "" else (String((mm2 as ShaderMaterial).shader.resource_path.get_file()) if mm2 is ShaderMaterial else mm2.get_class())
				flagged.append({"mesh": mname, "mesh_class": mesh.get_class(), "material": matname, "node": String(world.get_path_to(gi)), "pos": [snappedf(aabb.get_center().x, 0.1), snappedf(aabb.get_center().y, 0.1), snappedf(aabb.get_center().z, 0.1)],
					"size": [snappedf(aabb.size.x, 0.1), snappedf(aabb.size.y, 0.1), snappedf(aabb.size.z, 0.1)], "covered": snappedf(r.covered, 0.01)})
	return {"checked": checked, "flagged": flagged}


func _skipped(gi: Node, world: Node) -> bool:
	var n: Node = gi
	while n != null and n != world:
		for g in SKIP_GROUPS:
			if n.is_in_group(g):
				return true
		var nm := String(n.name)
		if nm.begins_with("Vista") or nm.begins_with("Animated") or nm.begins_with("Tree") or nm.contains("Water") or nm.contains("Sky"):
			return true
		var gim := gi as MeshInstance3D
		if gim and gim.mesh and (String(gim.mesh.resource_name).begins_with("broadleaf_tree") or gim.mesh is TorusMesh):
			return true  # trees: trunk collider; canopy is above head height. Torus: portal rings (walk-through by design)
			return true
		n = n.get_parent()
	return false


func _ground_y(space: PhysicsDirectSpaceState3D, p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 60.0, p.z), Vector3(p.x, p.y - 60.0, p.z))
	var hits := []
	# lowest walkable surface under the object: the terrain/floor, not the object's own top
	var from := Vector3(p.x, p.y - 0.0, p.z)
	var q2 := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.5, 0), from - Vector3(0, 80, 0))
	var h := space.intersect_ray(q2)
	return (h.position as Vector3).y if not h.is_empty() else p.y - 1.0


func _surface_coverage(space: PhysicsDirectSpaceState3D, mesh: Mesh, xf: Transform3D, ground: float) -> Dictionary:
	var samples := 0
	var covered := 0
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collide_with_areas = false
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var step := maxi(1, verts.size() / 60)
		for i in range(0, verts.size(), step):
			var w := xf * verts[i]
			if w.y < ground + 0.15 or w.y > ground + 1.6:
				continue
			samples += 1
			q.transform = Transform3D(Basis.IDENTITY, w)
			if not space.intersect_shape(q, 1).is_empty():
				covered += 1
	return {"samples": samples, "covered": float(covered) / maxf(samples, 1)}


# ------------------------------------------------------------------ 2. wall push
func _wall_push(world: Node3D, mika: WorldCharacter, count: int) -> Dictionary:
	var space := world.get_world_3d().direct_space_state
	var map := world.get_world_3d().navigation_map
	var tested := 0
	var passed := 0
	var failures := []
	var tries := 0
	var region_rid: RID = world.nav_region.get_rid() if world.nav_region else RID()
	while tested < count and tries < 400:
		tries += 1
		var start := NavigationServer3D.map_get_random_point(map, 1, false)
		if not _reachable(world, map, start):
			continue  # navmesh islands on top of walls etc. are not part of the walkable world
		var dir := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
		var from := start + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 4.0)
		q.exclude = [mika.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.normal as Vector3).y > 0.5:
			continue
		var d: float = from.distance_to(hit.position)
		if d < 0.8:
			continue
		# a wall must be a wall at knee height too (otherwise it is a step/ledge she may climb)
		var qk := PhysicsRayQueryParameters3D.create(start + Vector3(0, 0.45, 0), start + Vector3(0, 0.45, 0) + dir * 4.0)
		qk.exclude = [mika.get_rid()]
		var hk := space.intersect_ray(qk)
		if hk.is_empty():
			continue
		tested += 1
		var res := await _drive_and_watch(mika, start, dir, 2.5, true)
		if res.ok:
			passed += 1
		else:
			res["start"] = _v(start)
			res["dir"] = _v(dir)
			res["wall_at_m"] = snappedf(d, 0.01)
			failures.append(res)
	return {"tested": tested, "passed": passed, "failures": failures}


## Drive Mika and watch every physics frame for real clipping: (a) a shrunken copy of her capsule
## overlapping static geometry, (b) her movement between frames crossing a surface (tunnelling).
func _drive_and_watch(mika: WorldCharacter, start: Vector3, dir: Vector3, seconds: float, run: bool) -> Dictionary:
	var space := mika.get_world_3d().direct_space_state
	mika.velocity = Vector3.ZERO
	mika.global_position = start + Vector3(0, 0.1, 0)
	mika.rotation.y = atan2(-dir.x, -dir.z)
	await _wait_frames(3)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.16
	cap.height = 1.1
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.exclude = [mika.get_rid()]
	var prev := mika.global_position
	var overlaps := 0
	var tunnels := 0
	var first := ""
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		mika.set_move_input(dir, run)
		await get_tree().physics_frame
		var cur := mika.global_position
		q.transform = Transform3D(Basis.IDENTITY, cur + Vector3(0, 0.85, 0))
		var hits := space.intersect_shape(q, 4)
		for h in hits:
			if h.collider is StaticBody3D or h.collider is CSGShape3D:
				overlaps += 1
				if first == "":
					first = "overlap with %s at %s" % [_name(h.collider), str(cur.snapped(Vector3.ONE * 0.01))]
				break
		for hgt in [0.5, 1.2]:
			var r := PhysicsRayQueryParameters3D.create(prev + Vector3(0, hgt, 0), cur + Vector3(0, hgt, 0))
			r.exclude = [mika.get_rid()]
			if prev.distance_to(cur) > 0.001:
				var hr := space.intersect_ray(r)
				if not hr.is_empty() and (hr.normal as Vector3).y < 0.6:
					tunnels += 1
					if first == "":
						first = "crossed surface of %s at %s" % [_name(hr.collider), str((hr.position as Vector3).snapped(Vector3.ONE * 0.01))]
		prev = cur
	mika.set_move_input(Vector3.ZERO, false)
	return {"ok": overlaps == 0 and tunnels == 0, "overlap_frames": overlaps, "tunnel_frames": tunnels, "first": first, "end": _v(mika.global_position)}


func _name(o) -> String:
	if o is Node:
		var n: Node = o
		var w: Node = main.world
		return String(w.get_path_to(n)) if w.is_ancestor_of(n) else String(n.name)
	return str(o)


func _reachable(world: Node3D, map: RID, p: Vector3) -> bool:
	var sp: Vector3 = world.spawn_point("").origin
	var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, sp), p, true)
	return path.size() > 0 and path[path.size() - 1].distance_to(p) < 0.6


# ------------------------------------------------------------------ 3. path validity
func _paths(world: Node3D, count: int) -> Dictionary:
	var space := world.get_world_3d().direct_space_state
	var map := world.get_world_3d().navigation_map
	var crossing := 0
	var bad := []
	for i in count:
		var a := NavigationServer3D.map_get_random_point(map, 1, false)
		var b := NavigationServer3D.map_get_random_point(map, 1, false)
		var path := NavigationServer3D.map_get_path(map, a, b, true)
		for k in range(1, path.size()):
			var p0 := path[k - 1] + Vector3(0, 1.1, 0)
			var p1 := path[k] + Vector3(0, 1.1, 0)
			if p0.distance_to(p1) < 0.05:
				continue
			var q := PhysicsRayQueryParameters3D.create(p0, p1)
			var h := space.intersect_ray(q)
			if not h.is_empty() and (h.normal as Vector3).y < 0.5:
				# a segment that runs into a vertical surface at chest height: verify it isn't just a slope edge
				var q2 := PhysicsRayQueryParameters3D.create(p0 + Vector3(0, 0.4, 0), p1 + Vector3(0, 0.4, 0))
				if not space.intersect_ray(q2).is_empty():
					crossing += 1
					bad.append({"from": _v(path[k - 1]), "to": _v(path[k]), "collider": String(world.get_path_to(h.collider)) if h.collider is Node and world.is_ancestor_of(h.collider) else str(h.collider)})
					break
	return {"tested": count, "crossing": crossing, "examples": bad.slice(0, 6)}


# ------------------------------------------------------------------ 4. named checks
func _push_check(mika: WorldCharacter, start: Vector3, toward: Vector3, label: String, seconds := 2.5) -> Dictionary:
	var dir := toward - start
	dir.y = 0
	var dist := dir.length()
	dir = dir.normalized()
	var w := await _drive_and_watch(mika, start + Vector3(0, 0.05, 0), dir, seconds, false)
	await _wait_frames(2)
	var p := mika.global_position
	return {"label": label, "end": _v(p), "advanced_m": snappedf((p - start).dot(dir), 0.01), "target_m": snappedf(dist, 0.01),
		"clipping": not w.ok, "clip_detail": w.first}


func _named(world: Node3D, mika: WorldCharacter) -> Dictionary:
	var out := {}
	var g := func(x: float, z: float) -> float: return world.terrain.fast_height(x, z)
	# chamber: walk at the north wall from inside (must stop before z = -25)
	var r := await _push_check(mika, Vector3(-21.5, g.call(-21.5, -21.5) + 0.1, -22.0), Vector3(-21.5, 0, -28.0), "chamber north wall")
	r["ok"] = mika.global_position.z > -24.75
	out.chamber_wall = r
	r = await _push_check(mika, Vector3(-21.5, g.call(-21.5, -21.0), -21.0), Vector3(-28.0, 0, -21.0), "chamber west wall (behind altar)")
	r["ok"] = mika.global_position.x > -25.2
	out.chamber_west = r
	# watchpoint: up the stairs and back down
	r = await _push_check(mika, Vector3(-8.2, g.call(-8.2, 38.0), 38.0), Vector3(-17.0, 0, 38.0), "watchpoint stairs up", 6.0)
	r["ok"] = mika.global_position.y > g.call(-18.0, 38.0) + 1.7
	out.watch_up = r
	r = await _push_check(mika, mika.global_position, Vector3(-6.0, 0, 38.0), "watchpoint stairs down", 6.0)
	r["ok"] = mika.global_position.x > -10.0 and absf(mika.global_position.y - g.call(mika.global_position.x, 38.0)) < 0.5
	out.watch_down = r
	# watchpoint: platform edge without parapet must not be walked through sideways into the tower
	r = await _push_check(mika, Vector3(-17.0, g.call(-18.0, 38.0) + 2.0, 36.6), Vector3(-21.0, 0, 34.8), "watch tower stump")
	r["ok"] = Vector2(mika.global_position.x + 20.0, mika.global_position.z - 36.0).length() > 1.2
	out.watch_tower = r
	# gate inscription stone and statue
	r = await _push_check(mika, Vector3(3.7, g.call(3.7, -12.0), -12.0), Vector3(3.7, 0, -17.0), "gate inscription stone")
	r["ok"] = mika.global_position.z > -14.35
	out.gate_stone = r
	# garden: the pond guard keeps her out of the water
	r = await _push_check(mika, Vector3(16.5, g.call(16.5, 23.0), 23.0), Vector3(16.5, 0, 15.0), "pond edge")
	r["ok"] = Vector2(mika.global_position.x - 16.5, mika.global_position.z - 19.0).length() > 2.6
	out.pond = r
	# training target posts
	var tc := SanctuaryTerrain.TRAINING_CENTER
	var tp := tc + Vector2(cos(deg_to_rad(15.0)), sin(deg_to_rad(15.0))) * 5.0
	r = await _push_check(mika, Vector3(tc.x, g.call(tc.x, tc.y), tc.y), Vector3(tp.x + 2.0, 0, tp.y + 0.55), "rune target post")
	r["ok"] = Vector2(mika.global_position.x - tp.x, mika.global_position.z - tp.y).length() > 0.25
	out.target_post = r
	for k in out:
		out[k].ok = out[k].ok and not out[k].clipping
		print("[physicstest] named ", k, " ", out[k].ok, " ", JSON.stringify(out[k]))
	return out


func _named_library(world: Node3D, mika: WorldCharacter) -> Dictionary:
	# drive at the library's walls in the 4 cardinal directions from the spawn
	var out := {}
	var sp: Transform3D = world.spawn_point("sanctuary")
	var space := world.get_world_3d().direct_space_state
	for k in 4:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * PI * 0.5)
		var from := sp.origin + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 40.0)
		q.exclude = [mika.get_rid()]
		var h := space.intersect_ray(q)
		if h.is_empty():
			out["dir%d" % k] = {"ok": false, "detail": "no wall within 40 m (open?)"}
			continue
		var wall_d: float = from.distance_to(h.position)
		var r := await _push_check(mika, sp.origin, sp.origin + dir * (wall_d + 3.0), "library wall %d" % k, wall_d / 1.45 + 2.0)
		r["ok"] = r.advanced_m < wall_d + 0.05 and not r.clipping
		r["wall_m"] = snappedf(wall_d, 0.01)
		out["dir%d" % k] = r
	return out


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
