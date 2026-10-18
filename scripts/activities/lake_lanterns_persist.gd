class_name LakeLanternsPersist
extends Node
## Persistence for Lantern Lake's free lanterns (2026-10-19): the ones released from the pier and from the boat, and
## the viewers' lanterns with their names, plus viewer lanterns still waiting in the queue. Made by ScenePersist as a
## child of the lake node (scripts/areas/lantern_lake.gd, which it only reads and refills - never edits); in group
## "persistent_activity" like every other resumable activity.

var lake: Node3D
var area_id := ""


func _ready() -> void:
	add_to_group("persistent_activity")


func persist_key() -> String:
	return "lake_lanterns:" + area_id


## A viewer's lantern (released or queued) is a step: saved at once.
func persist_step() -> String:
	if lake == null or not is_instance_valid(lake):
		return ""
	return "viewers %d queued %d" % [int((lake.get("counts") as Dictionary).get("viewer_lanterns", 0)), (lake.get("_viewer_queue") as Array).size()]


func snapshot() -> Dictionary:
	if lake == null or not is_instance_valid(lake):
		return {}
	var out := []
	var names := []
	for d in (lake.get("free_lanterns") as Array):
		var n: Node3D = d.get("node")
		if n == null or not is_instance_valid(n):
			continue
		var lt = d.get("light")
		var e := {"p": [snappedf(n.position.x, 0.001), snappedf(n.position.y, 0.001), snappedf(n.position.z, 0.001)],
			"ry": snappedf(n.rotation.y, 0.001), "s": snappedf(n.scale.x, 0.001),
			"v": [snappedf((d.vel as Vector3).x, 0.0001), snappedf((d.vel as Vector3).y, 0.0001), snappedf((d.vel as Vector3).z, 0.0001)],
			"age": snappedf(float(d.get("age", 0.0)), 0.01), "kind": String(d.get("kind", "chat")), "name": String(d.get("name", "")),
			"seed": float(d.get("seed", 0.0)), "spin": float(d.get("spin", 0.0)), "light": -1.0}
		if lt != null and is_instance_valid(lt):
			e.light = snappedf((lt as OmniLight3D).light_energy, 0.001)
			e["e0"] = float((lt as OmniLight3D).get_meta("e0", (lt as OmniLight3D).light_energy))
		if e.name != "":
			names.append(e.name)
		out.append(e)
	var q := []
	for it in (lake.get("_viewer_queue") as Array):
		q.append([String(it[0]), String(it[1])])
	return {"kind": "lake_lanterns", "step": persist_step(), "lanterns": out, "names": names, "queue": q,
		"viewer_count": int((lake.get("counts") as Dictionary).get("viewer_lanterns", 0)), "t": float(lake.get("_t"))}


## The lanterns exactly as they were (the freshly built lake's random seed sky is replaced by the saved one).
func restore(d: Dictionary) -> void:
	if lake == null or not is_instance_valid(lake) or not d.has("lanterns"):
		return
	var fl: Array = lake.get("free_lanterns")
	for x in fl:
		if x.get("node") != null and is_instance_valid(x.node):
			(x.node as Node).queue_free()
	fl.clear()
	for e in (d.lanterns as Array):
		var L: Dictionary = lake.call("_make_lantern", String(e.get("kind", "chat")), String(e.get("name", "")), float(e.get("s", 0.95)))
		var n: Node3D = L.node
		var p: Array = e.get("p", [0, 0, 0])
		n.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		n.rotation.y = float(e.get("ry", 0.0))
		var v: Array = e.get("v", [0, 0, 0])
		L.vel = Vector3(float(v[0]), float(v[1]), float(v[2]))
		L.age = float(e.get("age", 0.0))
		L.seed = float(e.get("seed", 0.0))
		L.spin = float(e.get("spin", 0.0))
		if float(e.get("light", -1.0)) >= 0.0:
			lake.call("_lantern_light", L, float(e.light), false)
			(L.light as OmniLight3D).set_meta("e0", float(e.get("e0", e.light)))
		fl.append(L)
	var q: Array = lake.get("_viewer_queue")
	q.clear()
	for it in (d.get("queue", []) as Array):
		q.append([String(it[0]), String(it[1])])
	(lake.get("counts") as Dictionary)["viewer_lanterns"] = int(d.get("viewer_count", 0))
	print("[resume] lake lanterns: %d back in the sky (%d named: %s), %d viewer lanterns queued" % [fl.size(), (d.get("names", []) as Array).size(),
		", ".join(d.get("names", [])), q.size()])
