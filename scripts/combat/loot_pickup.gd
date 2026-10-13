class_name LootPickup
extends Node3D
## A physical drop from a defeated creature: a small glowing shard that hovers where it fell. Only a mage
## who walks up to it (within reach) can collect it; the item then goes into HER inventory as a recorded
## activity. Unclaimed drops fade after a few minutes (bounded world state).

const REACH := 1.6
const LIFETIME_S := 240.0

var item := ""
var count := 1
var source := ""
var claimed := false
var _t := 0.0
var _gem: MeshInstance3D


static func drop(parent: Node, at: Vector3, p_item: String, p_count: int, p_source: String) -> LootPickup:
	var l := LootPickup.new()
	l.name = "Animated_Loot_%s" % p_item
	l.item = p_item
	l.count = p_count
	l.source = p_source
	parent.add_child(l)
	l.global_position = at
	return l


static func all_in(world: Node) -> Array:
	return world.find_children("Animated_Loot_*", "LootPickup", true, false) if world else []


func _ready() -> void:
	add_to_group("loot")
	var c: Array = Spawner.load_data().items.get(item, {}).get("color", [1, 1, 1])
	var col := Color(c[0], c[1], c[2])
	_gem = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.14, 0.24, 0.14)
	_gem.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.5
	m.metallic = 0.4
	m.roughness = 0.2
	_gem.material_override = m
	_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_gem)
	var l := FX.light(col, 0.5 * float(RenderProfile.get_setting("magic_light_scale")), 2.0)
	l.position.y = 0.4
	add_child(l)


func label() -> String:
	return "%d %s" % [count, String(Spawner.load_data().items.get(item, {}).get("name", item))]


func _process(delta: float) -> void:
	_t += delta
	if _gem:
		_gem.position.y = 0.35 + 0.06 * sin(_t * 2.5)
		_gem.rotation.y += delta * 1.5
	if _t > LIFETIME_S and not claimed:
		queue_free()


## Collect into mage `c`'s inventory. Refused (and reported) when she is not close enough or it is taken.
func collect(c: WorldCharacter) -> Dictionary:
	if claimed:
		return {"ok": false, "detail": "already collected"}
	var d := Vector2(c.global_position.x - global_position.x, c.global_position.z - global_position.z).length()
	if d > REACH:
		return {"ok": false, "detail": "too far to pick up (%.1f m)" % d}
	claimed = true
	var ch := WorldState.record_activity({"id": "collect:" + item, "verb": "collect", "label": "Collected %s" % label(), "source": source},
		{"items": {item: count}, "knowledge": {"material:" + item: 1}}, c.character_id)
	FX.burst(get_parent(), global_position + Vector3(0, 0.35, 0), 20, 0.6, FX.pm_motes("self", "burst"), FX.mote_mesh(0.035))
	if AudioDirector.instance:
		AudioDirector.instance.play3d("loot_pickup", global_position, "SFX", -6.0, "loot")
	queue_free()
	return {"ok": true, "detail": "collected %s" % label(), "item": item, "count": count, "changes": ch}
