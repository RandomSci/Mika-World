class_name StorageRing
extends Node3D
## A STORAGE RING (the developer: "make them wear a beautiful storage ring that can store objects and living things").
## A jewelled band on the right ring finger whose stone holds a pocket of folded space. Things are drawn out of it
## into the open palm - a thread of light runs from the stone and the thing grows out of it - and stored back the
## same way, shrinking into the stone. Living things can rest in it too (a softer, warmer light). What is inside is
## each mage's own, kept in her mind (persisted): {id: label}.
## (This is an artefact, not a skill: it moves objects, never people - teleportation is still unlearned.)

const STYLES := {
	"mika": {"band": Color(0.92, 0.66, 0.5), "stone": Color(0.25, 0.95, 0.55), "glow": Color(0.45, 1.0, 0.65)},     # rose gold, emerald
	"luna": {"band": Color(0.86, 0.88, 0.95), "stone": Color(0.62, 0.45, 1.0), "glow": Color(0.72, 0.6, 1.0)},      # silver, moonstone
}

var c: WorldCharacter
var style := {}
var stone: MeshInstance3D
var light: OmniLight3D
var log: Array = []


static func attach(ch: WorldCharacter) -> StorageRing:
	var old := ch.find_child("StorageRing", true, false)
	if old:
		return old as StorageRing
	var bone := "RightRingProximal" if ch.skeleton.find_bone("RightRingProximal") >= 0 else "RightHand"
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	ba.name = "RingFinger"
	ch.skeleton.add_child(ba)
	var r := StorageRing.new()
	r.name = "StorageRing"
	r.c = ch
	r.style = STYLES.get(ch.character_id, STYLES.mika)
	ba.add_child(r)
	r._build(bone)
	return r


func _build(bone: String) -> void:
	# along the finger bone, a little past its base; the band wraps the finger
	var sk := c.skeleton
	var bi := sk.find_bone(bone)
	var child_len := 0.025
	for k in sk.get_bone_count():
		if sk.get_bone_parent(k) == bi:
			child_len = sk.get_bone_rest(k).origin.length()
			break
	position = Vector3(0, child_len * 0.45, 0)
	var band := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.0085
	tm.outer_radius = 0.0112
	tm.rings = 24
	tm.ring_segments = 8
	band.mesh = tm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = style.band
	bm.metallic = 1.0
	bm.roughness = 0.18
	band.material_override = bm
	add_child(band)
	stone = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0068
	sm.height = 0.0095
	stone.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = style.stone
	gm.emission_enabled = true
	gm.emission = style.glow
	gm.emission_energy_multiplier = 2.6
	gm.roughness = 0.05
	gm.metallic_specular = 1.0
	stone.material_override = gm
	stone.position = Vector3(0, 0, 0.0118)         # set on the back of the finger
	add_child(stone)
	light = OmniLight3D.new()
	light.light_color = style.glow
	light.light_energy = 0.06
	light.omni_range = 0.35
	light.shadow_enabled = false
	stone.add_child(light)


func contents() -> Dictionary:
	return WorldState.mind(c.character_id).knowledge.get("ring_contents", {})


func _set_contents(d: Dictionary) -> void:
	WorldState.mind(c.character_id).knowledge["ring_contents"] = d
	WorldState._dirty = true


func has(id: String) -> bool:
	return contents().has(id)


## Put things in without ceremony (setting out on a journey: what she already carries in it).
func stock(items: Dictionary) -> void:
	var d := contents().duplicate()
	d.merge(items, true)
	_set_contents(d)


func _thread(to: Vector3, seconds: float, reverse := false) -> void:
	var from := stone.global_position
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.02
	pm.direction = (to - from).normalized() if not reverse else (from - to).normalized()
	pm.spread = 25.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3.ZERO
	pm.color_ramp = FX.ramp([Color(style.glow.r, style.glow.g, style.glow.b, 0.0), Color(style.glow.r, style.glow.g, style.glow.b, 1.0), Color(1, 1, 1, 0)], [0.0, 0.3, 1.0])
	var p := FX.particles(36, 0.55, pm, FX.mote_mesh(0.012, true))
	p.one_shot = true
	p.explosiveness = 0.6
	get_tree().current_scene.add_child(p) if get_tree().current_scene else c.get_parent().add_child(p)
	p.global_position = from if not reverse else to
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.9, seconds * 0.4)
	tw.tween_property(light, "light_energy", 0.06, seconds * 0.8)


## Draw `id` out of the ring as `node` (a HoldableObject the caller built): it grows out of the stone's light into
## her open palm and is held. Awaitable; returns false if the ring does not hold it.
func draw(id: String, node: HoldableObject) -> bool:
	if not has(id) or c.handler.held != null:
		return false
	var palm := c.handler.palm()
	var final_scale := node.scale
	node.scale = final_scale * 0.02
	node.global_position = palm - Vector3(0, node.grasp_height, 0)
	_thread(palm, 0.45)
	c.handler.held = node
	node.on_grasped(c)
	var tw := create_tween()
	tw.tween_property(node, "scale", final_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	var d := contents().duplicate()
	d.erase(id)
	_set_contents(d)
	log.append({"t": WorldState.clock_text(), "drew": id})
	return true


## Store what is in her hand (or `node` anywhere within reach): it shrinks into the stone with a thread of light.
func store(id: String, label: String, node: Node3D = null) -> bool:
	var obj: Node3D = node if node else c.handler.held
	if obj == null:
		return false
	if c.handler.held == obj:
		c.handler.held = null
	var to := stone.global_position
	_thread(obj.global_position, 0.45, true)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(obj, "scale", obj.scale * 0.02, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(obj, "global_position", to, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	obj.queue_free()
	var d := contents().duplicate()
	d[id] = label
	_set_contents(d)
	log.append({"t": WorldState.clock_text(), "stored": id})
	return true


## A living thing taken into the ring's pocket (a rescued animal, an injured traveller's pet): it rests there,
## unharmed, until released. The thing itself (a node in the world) is kept as a record of what it was.
func store_living(id: String, label: String, creature: Node3D) -> bool:
	if creature == null or not is_instance_valid(creature):
		return false
	_thread(creature.global_position + Vector3(0, 0.3, 0), 0.8, true)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(creature, "scale", Vector3.ONE * 0.02, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(creature, "global_position", stone.global_position, 0.7).set_trans(Tween.TRANS_SINE)
	await tw.finished
	creature.visible = false
	creature.process_mode = Node.PROCESS_MODE_DISABLED
	var d := contents().duplicate()
	d[id] = label + " (living, resting)"
	_set_contents(d)
	log.append({"t": WorldState.clock_text(), "stored_living": id})
	return true
