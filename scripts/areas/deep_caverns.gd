extends KitArea
## D3 Underground Lake + D4 Ancient Vault (Crystal Caverns, fully underground).
## A vast cavern with a still, faintly glowing lake beneath a ceiling of hanging cyan crystals;
## a shoreline path leads to an ancient vault façade with a monumental door and glowing seal.

const LAKE := Vector3(4, 0, -8)
const VAULT := Vector3(-14, 0, -30)

var cave_rock: ShaderMaterial
var stone: ShaderMaterial
var seal_mat: ShaderMaterial


static func resources() -> Array:
	return textures(["rock_wall_10", "rocky_terrain_02", "stony_dirt_path", "castle_wall_slates"]) + models(["large_castle_door", "moon_rock_01", "moon_rock_03", "Lantern_01"])


func env_preset() -> Dictionary:
	return {"bg": Color(0.004, 0.008, 0.012), "sun_shadows": false,
		"day": {"ambient_color": Color(0.3, 0.42, 0.52), "ambient": 0.9, "sun_energy": 0.0, "fog": 0.018, "fog_color": Color(0.02, 0.06, 0.08), "vol_fog": 0.025, "vol_albedo": Color(0.6, 0.85, 1.0), "exposure": 1.25},
		"night": {"ambient_color": Color(0.3, 0.42, 0.52), "ambient": 0.9, "sun_energy": 0.0, "fog": 0.018, "fog_color": Color(0.02, 0.06, 0.08), "vol_fog": 0.025, "exposure": 1.25}}


func height(x: float, z: float) -> float:
	var lake := Vector2((x - LAKE.x) / 13.0, (z - LAKE.z) / 15.0).length()
	var basin := -2.2 * (1.0 - smoothstep(0.75, 1.05, lake))
	return basin + sin(x * 0.35) * 0.2 + cos(z * 0.27) * 0.2


func build_steps() -> Array:
	return [_ground, _shell, _lake, _ceiling_crystals, _shore, _vault, _links]


func _ground() -> void:
	nav_aabb = AABB(Vector3(-30, -5, -44), Vector3(60, 16, 66))
	cave_rock = Kit.tri("rock_wall_10", "1k", 0.25, 0.0, Color(0.5, 0.56, 0.62), {"wetness": 0.6, "grime_height": 0.0, "two_sided": true})
	stone = Kit.tri("castle_wall_slates", "1k", 0.45, 0.1, Color(0.72, 0.76, 0.8))
	magic_receivers = [cave_rock, stone]
	var mat := Kit.terrain_mat("rocky_terrain_02", "rock_wall_10", "stony_dirt_path", Color(0.55, 0.6, 0.66), Color(0.4, 0.44, 0.5))
	Kit.terrain(self, 80.0, 1.0, height, func(x, z):
		var shore := absf(Vector2((x - LAKE.x) / 13.0, (z - LAKE.z) / 15.0).length() - 1.15)
		return Color(1.0 - smoothstep(0.05, 0.15, shore), 0.6, 0.0), mat)


func _shell() -> void:
	var mi := Kit.mesh_node(self, Kit.cave_shell(Vector3(26.0, 11.0, 30.0), 31, 0.22, Callable(), 48, 24), cave_rock, Kit.xf(Vector3(0, 2.5, -10)))
	Kit.trimesh_collide(mi)


func _lake() -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 34)
	w.mesh = pm
	w.material_override = Kit.shader_mat("res://shaders/water.gdshader", {"shallow": Color(0.04, 0.22, 0.3), "deep": Color(0.0, 0.03, 0.06), "clarity": 2.5,
		"flow": Vector2(0.004, 0.006), "wave_scale": 0.05, "glow_color": Color(0.2, 0.75, 1.0), "glow": 0.5})
	w.position = LAKE + Vector3(0, -0.9, 0)
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w)
	# invisible barrier so walkers stay on the shore (the lake is deep)
	for i in 28:
		var a := TAU * i / 28.0
		var p := LAKE + Vector3(cos(a) * 12.0, 0, sin(a) * 14.0)
		Kit.static_box(self, Vector3(3.4, 3.0, 0.4), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p + Vector3(0, 0.5, 0)))
	add_location("underground_lake", LAKE, 20.0, LAKE + Vector3(-14.5, height(LAKE.x - 14.5, LAKE.z + 6), 6.0))


func _ceiling_crystals() -> void:
	var cols := [Color(0.25, 0.85, 1.0), Color(0.35, 0.95, 0.9), Color(0.5, 0.6, 1.0)]
	var meshes := []
	for i in 4:
		meshes.append(Kit.crystal_mesh(rng.randf_range(0.8, 2.4), rng.randf_range(0.12, 0.28), 900 + i))
	for k in 3:
		var xs := []
		for i in 70:
			var p := Vector3(rng.randf_range(-20, 22), 0, rng.randf_range(-32, 14))
			var e := Vector2(p.x / 26.0, (p.z + 10.0) / 30.0).length()
			if e > 0.82:
				continue
			p.y = 2.5 + 11.0 * sqrt(maxf(0.0, 1.0 - e * e)) - 0.4
			xs.append(Transform3D(Basis(Vector3.RIGHT, PI) * Basis(Vector3(rng.randf(), 0, rng.randf()).normalized(), rng.randf_range(0, 0.4)).scaled(Vector3.ONE * rng.randf_range(0.6, 1.5)), p))
		Kit.multimesh(self, meshes[k], xs, 0.0, false, Kit.crystal(cols[k], 2.4))
	for p in [LAKE + Vector3(0, 8, 0), LAKE + Vector3(-8, 7, -10), LAKE + Vector3(8, 7, 8), LAKE + Vector3(-18, 4, 6), LAKE + Vector3(16, 4, -14)]:
		Kit.omni(self, p, Color(0.3, 0.8, 1.0), 2.4, 18.0)


func _shore() -> void:
	for i in 14:
		var a := TAU * i / 14.0
		var p := LAKE + Vector3(cos(a) * 14.5, 0, sin(a) * 16.5)
		if p.distance_to(VAULT) < 8.0:
			continue
		Kit.place_prop(self, ["moon_rock_01", "moon_rock_03"][i % 2], Kit.xf(Vector3(p.x, height(p.x, p.z) - 0.2, p.z), a, Vector3.ONE * rng.randf_range(2.5, 5.0)), "", true)
	for i in 8:  # shoreline crystal clusters reflected in the water
		var a := TAU * i / 8.0 + 0.3
		var p := LAKE + Vector3(cos(a) * 11.3, 0, sin(a) * 13.2)
		for j in 4:
			Kit.mesh_node(self, Kit.crystal_mesh(rng.randf_range(0.5, 1.6), 0.12, 950 + i * 4 + j), Kit.crystal(Color(0.3, 0.9, 1.0), 2.6),
				Transform3D(Basis(Vector3(rng.randf(), 0, rng.randf()).normalized(), rng.randf_range(0.1, 0.7)), Vector3(p.x + rng.randf_range(-0.6, 0.6), height(p.x, p.z) - 0.1, p.z + rng.randf_range(-0.6, 0.6))), false)
	Kit.mesh_node(self, Kit.prop("Lantern_01", "Lantern_01"), null, Kit.xf(LAKE + Vector3(-14.5, height(LAKE.x - 14.5, LAKE.z + 4) + 0.0, 4.0), 0.0, Vector3.ONE * 1.5))
	Kit.omni(self, LAKE + Vector3(-14.5, height(LAKE.x - 14.5, LAKE.z + 4) + 0.5, 4.0), Color(1.0, 0.68, 0.38), 0.8, 5.0)


func _vault() -> void:
	var y0 := height(VAULT.x, VAULT.z)
	var yaw := atan2(LAKE.x - VAULT.x, LAKE.z - VAULT.z)
	var root := Node3D.new()
	root.transform = Kit.xf(Vector3(VAULT.x, y0, VAULT.z), yaw)
	add_child(root)
	Kit.block(root, Vector3(12, 0.4, 6), Kit.xf(Vector3(0, 0.0, 1.0)), stone, true, 0.04)
	Kit.block(root, Vector3(14, 9, 1.8), Kit.xf(Vector3(0, 4.5, -1.6)), stone, true, 0.06)
	for sx: float in [-1.0, 1.0]:
		Kit.mesh_node(root, Kit.lathe([Vector2(0.7, 0), Vector2(0.75, 0.4), Vector2(0.55, 0.6), Vector2(0.5, 6.6), Vector2(0.75, 7.0), Vector2(0.75, 7.4)], 16), stone, Kit.xf(Vector3(sx * 3.2, 0.2, 0.2)))
		Kit.static_box(root, Vector3(1.4, 7.4, 1.4), Kit.xf(Vector3(sx * 3.2, 3.9, 0.2)))
	Kit.block(root, Vector3(8.6, 1.0, 1.6), Kit.xf(Vector3(0, 7.9, 0.1)), stone, false, 0.05)
	Kit.mesh_node(root, Kit.box_mesh(Vector3(5.0, 1.8, 0.3), 0.05), stone, Kit.xf(Vector3(0, 9.3, -0.6)))
	for p in Kit.prop_parts("large_castle_door"):
		Kit.mesh_node(root, p[0], null, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.0), Vector3(0, 0.2, -0.65)) * p[1])
	# glowing seal above the door
	var seal := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 2.4)
	seal.mesh = q
	seal_mat = ShaderMaterial.new()
	seal_mat.shader = load("res://shaders/magic/sigil.gdshader")
	seal_mat.set_shader_parameter("sides", 5)
	seal_mat.set_shader_parameter("color", Color(0.3, 0.9, 1.0))
	seal_mat.set_shader_parameter("intensity", 0.8)
	seal_mat.set_shader_parameter("spin", 0.08)
	seal.material_override = seal_mat
	seal.position = Vector3(0, 7.0, -0.55)
	root.add_child(seal)
	Kit.omni(root, Vector3(0, 6.5, 1.5), Color(0.35, 0.9, 1.0), 1.4, 9.0)
	add_location("ancient_vault", VAULT, 10.0, Vector3(VAULT.x, y0, VAULT.z) + Basis(Vector3.UP, yaw) * Vector3(0, 0.25, 4.5))
	var it := Interactable.make("vault_seal_resonate", "Resonate the vault seal with a crystal shard", "attune", "ancient_vault",
		Vector3(VAULT.x, y0, VAULT.z) + Basis(Vector3.UP, yaw) * Vector3(0, 0.2, 2.5), {"knowledge": {"vault:seal_resonated": 1, "lore:ancient_vault": 1}}, "spell_casting", 4.2)
	it.requires = {"items": {"crystal_shard": 1}}
	it.repeatable = false
	it.radius = 2.6
	it.on_done = func():
		seal_mat.set_shader_parameter("intensity", 2.5)
		seal_mat.set_shader_parameter("spin", 0.4)
	add_interactable(it)
	add_interactable(Interactable.make("vault_inscription", "Read the inscription carved beside the vault door", "study", "ancient_vault",
		Vector3(VAULT.x, y0, VAULT.z) + Basis(Vector3.UP, yaw) * Vector3(-3.0, 0.2, 2.2), {"knowledge": {"lore:vault_inscription": 1}}, "look_around", 3.5)).radius = 2.4


func _links() -> void:
	var p := Vector3(16.0, height(16, 14), 14.0)
	add_gate("crystal_caverns", p, Vector3(12.5, height(12.5, 10.5) + 0.05, 10.5), atan2(16.0 - 12.5, 14.0 - 10.5) + PI, 2.2)
	Kit.mesh_node(self, Kit.box_mesh(Vector3(3.5, 4.0, 0.5), 0.02), Kit.emissive(Color(0, 0, 0), 0.0), Transform3D(Basis(Vector3.UP, atan2(16.0, 14.0)), p + Vector3(1.2, 2.0, 1.0)), false)
	add_interactable(Interactable.make("lake_meditate", "Meditate at the still lake's edge", "meditate", "underground_lake",
		LAKE + Vector3(-13.5, height(LAKE.x - 13.5, LAKE.z + 6), 6.0), {"skills": {"arcane_orb": 0.12}, "knowledge": {"calm:underground_lake": 1}}, "", 4.0)).radius = 2.6


func showcase_shots(loc: String) -> Array:
	if loc == "ancient_vault":
		return [[VAULT + Vector3(8, 2.5, 12), VAULT + Vector3(0, 4.5, 0), 55.0]]
	return [[LAKE + Vector3(-14, 2.4, 10), LAKE + Vector3(4, 3.0, -6), 60.0]]
