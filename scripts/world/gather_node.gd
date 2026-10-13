class_name GatherNode
extends Node3D
## A gatherable plant (data/gatherables.json). It only exists visually and physically; a mage notices it
## through perception, walks up, picks it with her hands (PickupAction), and only then does the item go
## into HER inventory. It regrows after a while. Original procedural design.

static var data := {}

var gid := ""
var kind := ""
var def := {}
var picked := false
var _regrow := 0.0
var _plant: Node3D


static func load_data() -> Dictionary:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string("res://data/gatherables.json"))
	return data


## Place every plant of `area_id` into `world` (called after the area is built).
static func populate(world: Node3D, area_id: String) -> Array:
	load_data()
	var out := []
	var map := world.get_world_3d().navigation_map
	var i := 0
	for s in data.spots.get(area_id, []):
		i += 1
		var p := Vector3(float(s.pos[0]), 0, float(s.pos[1]))
		p.y = world.ground_at(p.x, p.z) if world.has_method("ground_at") else 0.0
		var nav := NavigationServer3D.map_get_closest_point(map, p)
		if nav != Vector3.ZERO and nav.distance_to(p) > 2.5:
			continue           # not next to walkable ground: skip rather than put it somewhere unreachable
		var n := GatherNode.new()
		n.name = "Animated_Gather_%s_%d" % [s.kind, i]
		n.gid = "%s_%d" % [s.kind, i]
		n.kind = String(s.kind)
		n.def = data.kinds.get(n.kind, {})
		world.add_child(n)
		n.global_position = p
		out.append(n)
	return out


func _ready() -> void:
	add_to_group("gatherable")
	_plant = Node3D.new()
	add_child(_plant)
	var col: Array = def.get("color", [1, 1, 1])
	var c := Color(col[0], col[1], col[2])
	var stem_m := StandardMaterial3D.new()
	stem_m.albedo_color = Color(0.25, 0.42, 0.2)
	var bloom := StandardMaterial3D.new()
	bloom.albedo_color = c
	bloom.emission_enabled = true
	bloom.emission = c
	bloom.emission_energy_multiplier = float(def.get("glow", 1.0))
	for k in 3:
		var stem := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006
		cm.bottom_radius = 0.01
		cm.height = 0.22 + 0.06 * k
		stem.mesh = cm
		stem.material_override = stem_m
		var a := k * TAU / 3.0
		stem.position = Vector3(cos(a) * 0.04, cm.height * 0.5, sin(a) * 0.04)
		stem.rotation = Vector3(sin(a) * 0.15, 0, cos(a) * 0.15)
		_plant.add_child(stem)
		var head := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.04 if kind == "moonpetal" else 0.05
		head.mesh = sm
		head.material_override = bloom
		head.position = stem.position + Vector3(0, cm.height * 0.5 + 0.015, 0)
		_plant.add_child(head)
	var l := FX.light(c, 0.25 * float(RenderProfile.get_setting("magic_light_scale")), 1.4)
	l.position.y = 0.3
	_plant.add_child(l)


func label() -> String:
	return String(def.get("name", kind))


func available() -> bool:
	return not picked and is_instance_valid(_plant)


func _process(delta: float) -> void:
	if picked:
		_regrow -= delta
		if _regrow <= 0.0:
			picked = false
			_plant.visible = true
			_plant.scale = Vector3.ONE


## The physical part is done by the caller (PickupAction moves `token()`); this records the result for `c`.
func harvest(c: WorldCharacter) -> Dictionary:
	if picked:
		return {"ok": false, "detail": "already picked"}
	picked = true
	_regrow = float(def.get("regrow_s", 600.0))
	_plant.visible = false
	var ch := WorldState.record_activity({"id": "gather:" + kind, "verb": "gather", "label": "Gathered %s" % label()},
		{"items": {String(def.get("item", kind)): 1}, "knowledge": {"material:" + String(def.get("item", kind)): 1}}, c.character_id)
	if AudioDirector.instance:
		AudioDirector.instance.play3d("loot_pickup", global_position, "SFX", -8.0, "gather")
	return {"ok": true, "detail": "gathered a %s" % label(), "changes": ch}


## A detached copy of the bloom for the hands to carry (the plant itself stays rooted until harvested).
func token() -> Node3D:
	var t := _plant.duplicate() as Node3D
	get_parent().add_child(t)
	t.global_position = global_position
	return t
