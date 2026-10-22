class_name RegionMagic
extends RefCounted
## Every region has its own magic to practise (Selwyn, 22 Oct: "each region gets its own signature activities ...
## its own magic to practise, so it never feels empty"). Until now spell practice targets stood only on the
## sanctuary's training grounds, so far away the girls had nothing to cast at. Each far area gets a few targets of
## the two proven sanctuary kinds (a rune disc on a post, a crystal on a stand), coloured and named for the place,
## placed on flat ground a few metres from one of its locations. They are ordinary ReactiveElements: the brain's
## practice option, the spell system, the reactions and the knowledge they teach all work as at home.

const SPOTS := {
	"ancient_grove": [
		{"type": "rune", "loc": "ancient_grove", "id": "grove_glyph", "label": "the glyph stone among the giant roots", "color": Color(0.5, 0.95, 0.55), "sides": 5},
		{"type": "crystal", "loc": "forgotten_forest_shrine", "id": "shrine_seed_crystal", "label": "the green seed crystal at the shrine", "color": Color(0.45, 1.0, 0.6)}],
	"river_valley": [
		{"type": "crystal", "loc": "luminous_river", "id": "river_dew_crystal", "label": "the dew crystal on the riverbank", "color": Color(0.5, 0.9, 1.0)},
		{"type": "rune", "loc": "waterfall_crossing", "id": "falls_rune", "label": "the spray rune by the falls", "color": Color(0.6, 0.85, 1.0), "sides": 6}],
	"village": [
		{"type": "crystal", "loc": "village_square", "id": "square_lantern_crystal", "label": "the lantern crystal in the square", "color": Color(1.0, 0.75, 0.4)},
		{"type": "rune", "loc": "craft_workshop", "id": "workshop_rune", "label": "the workshop's mending rune", "color": Color(1.0, 0.65, 0.35), "sides": 4}],
	"observatory_hill": [
		{"type": "rune", "loc": "village_observatory", "id": "observatory_star_rune", "label": "the star rune by the observatory", "color": Color(0.85, 0.85, 1.0), "sides": 7}],
	"crystal_caverns": [
		{"type": "crystal", "loc": "crystal_entrance", "id": "singing_crystal", "label": "a singing cave crystal", "color": Color(0.75, 0.55, 1.0)},
		{"type": "crystal", "loc": "luminous_crystal_hall", "id": "hall_resonance_crystal", "label": "the resonance crystal in the hall", "color": Color(0.5, 0.95, 1.0)}],
	"deep_caverns": [
		{"type": "rune", "loc": "ancient_vault", "id": "vault_seal_rune", "label": "a seal rune at the old vault", "color": Color(0.95, 0.8, 0.45), "sides": 8}],
	"highland_path": [
		{"type": "rune", "loc": "mountain_path", "id": "cairn_rune", "label": "the rune on the old cairn", "color": Color(0.95, 0.9, 0.65), "sides": 5},
		{"type": "crystal", "loc": "cliff_overlook", "id": "wind_crystal", "label": "the wind crystal at the overlook", "color": Color(0.8, 0.95, 1.0)}],
	"celestial_summit": [
		{"type": "rune", "loc": "celestial_observatory", "id": "summit_star_rune", "label": "the star rune on the summit", "color": Color(1.0, 0.92, 0.6), "sides": 7},
		{"type": "crystal", "loc": "cloud_temple", "id": "temple_sky_crystal", "label": "the sky crystal at the cloud temple", "color": Color(0.7, 0.85, 1.0)}],
	"academy": [
		{"type": "crystal", "loc": "advanced_magic_arena", "id": "arena_practice_crystal", "label": "the arena's practice crystal", "color": Color(0.55, 0.8, 1.0)},
		{"type": "rune", "loc": "academy_courtyard", "id": "courtyard_rune", "label": "the courtyard's exam rune", "color": Color(0.6, 0.75, 1.0), "sides": 6},
		{"type": "rune", "loc": "academy_gardens", "id": "garden_rune", "label": "the garden's bloom rune", "color": Color(0.55, 1.0, 0.7), "sides": 5}],
}


static func has_magic(area_id: String) -> bool:
	return SPOTS.has(area_id)


## A build step (AreaBase.activate_steps): the targets of this area, if it has any.
static func build(area: AreaBase) -> void:
	var specs: Array = SPOTS.get(area.area_id, [])
	var i := 0
	for spec in specs:
		i += 1
		var poi: Dictionary = area.points_of_interest.get(String(spec.loc), {})
		if poi.is_empty():
			continue
		var at: Vector3 = _flat_spot(area, poi.position, i)
		if at == Vector3.INF:
			print("[regionmagic] %s: no flat ground near %s for %s" % [area.area_id, spec.loc, spec.id])
			continue
		var face := Vector3(poi.position.x - at.x, 0, poi.position.z - at.z)
		var yaw := atan2(face.x, face.z) if face.length() > 0.1 else 0.0
		if String(spec.type) == "rune":
			_rune(area, spec, at, yaw)
		else:
			_crystal(area, spec, at)
	if not specs.is_empty():
		print("[regionmagic] %s: %d practice targets" % [area.area_id, ReactiveElement.registry_of(area).size()])


## Flat, open ground 4 to 6 m from a location's spot (8 directions, the gentlest wins): no slope over 0.35 m across
## the post's footprint and nothing solid already standing there.
static func _flat_spot(area: AreaBase, c: Vector3, salt: int) -> Vector3:
	var best := Vector3.INF
	var best_s := 0.35
	var space := area.get_world_3d().direct_space_state if area.is_inside_tree() else null
	for k in 8:
		for d in [4.5, 6.0]:
			var a := (k + salt * 0.37) * TAU / 8.0
			var x: float = c.x + cos(a) * d
			var z: float = c.z + sin(a) * d
			var y: float = area.ground_at(x, z)
			var spread := 0.0
			for o in [Vector2(0.8, 0), Vector2(-0.8, 0), Vector2(0, 0.8), Vector2(0, -0.8)]:
				spread = maxf(spread, absf(area.ground_at(x + o.x, z + o.y) - y))
			if spread >= best_s:
				continue
			if space:
				var q := PhysicsShapeQueryParameters3D.new()
				var sh := BoxShape3D.new()
				sh.size = Vector3(1.2, 1.6, 1.2)
				q.shape = sh
				q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + 1.0, z))
				if not space.intersect_shape(q, 1).is_empty():
					continue
			best_s = spread
			best = Vector3(x, y, z)
	return best


## The area's own stone where it has one (forest, village, highlands, academy), else a plain weathered grey.
static func _stone_of(area: AreaBase) -> Material:
	if area.has_method("_stone"):
		return area.call("_stone")
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.46, 0.44, 0.4)
	m.roughness = 0.92
	return m


static func _rune(area: AreaBase, spec: Dictionary, base: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var stone := _stone_of(area)
	var post := Kit.mesh_node(area, Kit.box_mesh(Vector3(0.22, 1.5, 0.22), 0.03), stone, Transform3D(b, base + Vector3(0, 0.75, 0)))
	var disc := Kit.mesh_node(area, Kit.lathe([Vector2(0.48, 0), Vector2(0.5, 0.06), Vector2(0.48, 0.12)], 24, true, true), stone,
		Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), base + Vector3(0, 1.35, 0) + b * Vector3(0, 0, 0.1)))
	var body := Kit.static_box(area, Vector3(1.0, 1.6, 0.3), Transform3D(b, base + Vector3(0, 0.8, 0)))
	var sig := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.92, 0.92)
	sig.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/magic/sigil.gdshader")
	m.set_shader_parameter("sides", int(spec.get("sides", 5)))
	m.set_shader_parameter("color", spec.color)
	m.set_shader_parameter("intensity", 0.3)
	m.set_shader_parameter("spin", 0.2)
	m.set_shader_parameter("seed", float(hash(String(spec.id)) % 97))
	sig.material_override = m
	sig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sig.transform = Transform3D(b, base + Vector3(0, 1.35, 0) + b * Vector3(0, 0, 0.24))
	area.add_child(sig)
	var rr := RuneReactive.new()
	rr.name = "Reactive_" + String(spec.id)
	area.add_child(rr)
	rr.global_transform = Transform3D(b, base + Vector3(0, 1.35, 0) + b * Vector3(0, 0, 0.2))
	rr._base_color = spec.color
	rr.setup(String(spec.id), String(spec.label), m, disc, [disc, sig])
	rr.bodies.append(body)
	area.add_poi("magic:" + String(spec.id), base + Vector3(0, 1.35, 0), String(spec.label).capitalize(), String(spec.loc), 2.4)
	post.name = "RunePost_" + String(spec.id)


static func _crystal(area: AreaBase, spec: Dictionary, at: Vector3) -> void:
	var stone := _stone_of(area)
	Kit.mesh_node(area, Kit.lathe([Vector2(0.32, 0), Vector2(0.28, 0.1), Vector2(0.14, 0.18), Vector2(0.12, 0.9), Vector2(0.24, 0.98), Vector2(0.24, 1.05)], 12, false, true), stone, Kit.xf(at))
	var body := Kit.static_box(area, Vector3(0.5, 1.05, 0.5), Kit.xf(at + Vector3(0, 0.52, 0)))
	var pc := PracticeCrystal.new()
	pc.name = "Reactive_" + String(spec.id)
	area.add_child(pc)
	pc.position = at
	var cm := MeshInstance3D.new()
	cm.mesh = Kit.crystal_mesh(0.5, 0.13, hash(String(spec.id)) % 50)
	cm.material_override = Kit.crystal(spec.color, 1.6)
	cm.position.y = 1.45
	pc.add_child(cm)
	var cl := FX.light(spec.color, 0.8, 3.0)
	cl.position.y = 1.5
	pc.add_child(cl)
	pc.setup(String(spec.id), String(spec.label), cm, cl)
	pc.bodies.append(body)
	area.add_poi("magic:" + String(spec.id), at + Vector3(0, 1.45, 0), String(spec.label).capitalize(), String(spec.loc), 2.4)
