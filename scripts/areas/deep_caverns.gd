extends CaveArea
## D3 Underground Lake + D4 Ancient Vault (Crystal Caverns, fully underground) - rebuilt as a real cave
## (world-quality gate). The tunnel from the crystal hall descends west -> east into a cavern 90 m across and 26 m
## high: a still black LAKE fills its heart under a roof of hanging cyan crystals (their light lies on the water),
## a shore path of wet stone circles its north side to the ANCIENT VAULT - a carved facade in the cavern wall,
## columns and a lintel round a monumental door, a seal glowing above it.

const LAKE := Vector2(10, -2)
const LAKE_R := Vector2(19, 16)
const CAVERN := Vector2(8, -6)
const CAVERN_R := Vector2(46, 40)
const VAULT := Vector2(4, -42)
const ENTRY := Vector2(-86, 6)

var seal_mat: ShaderMaterial
var stone: ShaderMaterial


func _init() -> void:
	trails = [
		[[ENTRY, Vector2(-66, 6), Vector2(-46, 4), Vector2(-30, 2), Vector2(-20, -8), Vector2(-14, -22), Vector2(-6, -32), VAULT + Vector2(0, 6)], 2.4],
		[[Vector2(-30, 2), Vector2(-22, 14), Vector2(-6, 18), LAKE + Vector2(-6, 18)], 1.6],
	]


func cave_sdf(p: Vector2) -> float:
	var e := Vector2((p.x - CAVERN.x) / CAVERN_R.x, (p.y - CAVERN.y) / CAVERN_R.y)
	var hall := (e.length() - 1.0) * minf(CAVERN_R.x, CAVERN_R.y)
	var a := atan2(e.y, e.x)
	hall += 3.0 * sin(a * 4.0 + 1.3) + 1.6 * sin(a * 9.0)
	var tunnel := WhisperingWoods._seg_dist(p, ENTRY + Vector2(-4, 0), Vector2(-34, 3)) - 5.0
	var vault_bay := WhisperingWoods._seg_dist(p, VAULT + Vector2(0, 10), VAULT + Vector2(0, -2)) - 9.0
	return minf(minf(hall, tunnel), vault_bay)


func floor_h(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var sd := cave_sdf(p)
	if sd >= 0.0:
		return 34.0
	var bumps := 0.3 * sin(x * 0.33) * cos(z * 0.29) + 0.18 * sin((x + z) * 0.7)
	var f := bumps + clampf((-34.0 - x) / 52.0, 0.0, 1.0) * 6.0                   # the tunnel comes down from the west
	var lk := Vector2((p.x - LAKE.x) / LAKE_R.x, (p.y - LAKE.y) / LAKE_R.y).length()
	f -= 3.0 * (1.0 - smoothstep(0.8, 1.08, lk))                                 # the lake basin
	return f


func ceil_h(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var sd := cave_sdf(p)
	if sd >= 0.0:
		return floor_h(x, z)
	var e := Vector2((p.x - CAVERN.x) / CAVERN_R.x, (p.y - CAVERN.y) / CAVERN_R.y).length()
	var room := lerpf(6.5, 26.0, 1.0 - smoothstep(0.4, 1.15, e))
	var profile := sqrt(clampf(-sd / 7.0, 0.0, 1.0))
	var drips := 1.2 * sin(x * 0.29) * cos(z * 0.33) + 0.6 * sin((x - z) * 0.8)
	return floor_h(x, z) + maxf(0.0, (room + drips) * profile)


func occlusion(_x: float, _z: float) -> float:
	return 0.45         # no sky down here - the cavern's cold ambient glow (crystal light everywhere) stays


func water_dist(p: Vector2) -> float:
	return (Vector2((p.x - LAKE.x) / LAKE_R.x, (p.y - LAKE.y) / LAKE_R.y).length() - 1.0) * minf(LAKE_R.x, LAKE_R.y)


func env_preset() -> Dictionary:
	# no sky down here: a cold fill (the crystals' light everywhere) bright enough to read the rock, thin haze that
	# catches the light pools - deep dark only in the far corners
	return {"bg": Color(0.004, 0.008, 0.012), "sun_shadows": false,
		"day": {"ambient_color": Color(0.27, 0.4, 0.48), "ambient": 2.2, "sun_energy": 0.0, "fog": 0.006, "fog_color": Color(0.05, 0.1, 0.13), "vol_fog": 0.012, "vol_albedo": Color(0.7, 0.9, 1.0), "exposure": 1.45, "contrast": 1.08},
		"night": {"ambient_color": Color(0.27, 0.4, 0.48), "ambient": 2.2, "sun_energy": 0.0, "fog": 0.006, "fog_color": Color(0.05, 0.1, 0.13), "vol_fog": 0.012, "vol_albedo": Color(0.7, 0.9, 1.0), "exposure": 1.45, "contrast": 1.08}}


func features() -> Array:
	return [_lake, _roof_crystals, _shore, _vault, _glow]


func _v(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, height(p.x, p.y) + lift, p.y)


func _lake_y() -> float:
	return height(LAKE.x + LAKE_R.x * 0.85, LAKE.y) - 0.35


func _lake() -> void:
	# still black water: a near-black mirror that holds the crystals' light (screen-space reflections), a faint slow
	# ripple in the normal so the reflections shiver a little
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.008, 0.016, 0.022)
	wm.roughness = 0.03
	wm.metallic = 0.0
	wm.metallic_specular = 0.9
	wm.normal_enabled = true
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 2.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	nt.noise = fn
	wm.normal_texture = nt
	wm.normal_scale = 0.15
	wm.uv1_scale = Vector3(3.0, 3.0, 1.0)
	var w := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	cm.radial_segments = 64
	w.mesh = cm
	w.scale = Vector3(LAKE_R.x * 1.0, 1.0, LAKE_R.y * 1.0)
	w.material_override = wm
	w.position = Vector3(LAKE.x, _lake_y(), LAKE.y)
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w)
	var ring := []
	for i in 24:
		var a := TAU * i / 24.0
		ring.append(LAKE + Vector2(cos(a) * LAKE_R.x * 0.94, sin(a) * LAKE_R.y * 0.94))
	_nav_hole_poly(ring, _lake_y() - 4.0)
	add_location("underground_lake", Vector3(LAKE.x, 0, LAKE.y), 24.0, _v(LAKE + Vector2(-6, 19)), "a still black lake under a roof of hanging crystals")


## Keep walkers out of the deep water (a navmesh hole: an obstacle the bake carves round).
func _nav_hole_poly(pts: Array, y: float) -> void:
	var ob := NavigationObstacle3D.new()
	var vs := PackedVector3Array()
	for p in pts:
		vs.append(Vector3((p as Vector2).x, 0, (p as Vector2).y))
	ob.vertices = vs
	ob.height = 6.0
	ob.position = Vector3(0, y, 0)
	ob.affect_navigation_mesh = true
	ob.carve_navigation_mesh = true
	add_child(ob)


func _roof_crystals() -> void:
	var placed := 0
	for i in 60:
		var p := LAKE + Vector2(rng.randf_range(-1, 1) * LAKE_R.x, rng.randf_range(-1, 1) * LAKE_R.y) * 1.2
		var r := roof(p.x, p.y)
		if r - height(p.x, p.y) < 10.0:
			continue
		crystals(Vector3(p.x, r + 0.4, p.y), Vector3.DOWN, rng.randf_range(0.8, 2.2), [0, 0, 2][i % 3], 1200 + i, placed % 2 == 0)
		if placed % 3 == 0:
			# its light falls in a pool on the water / the shore far below (a spot: the cavern's key light)
			var gap := r - height(p.x, p.y)
			var sp := SpotLight3D.new()
			sp.light_color = Color(0.5, 0.85, 1.0)
			sp.light_energy = 5.0
			sp.spot_range = gap + 6.0
			sp.spot_angle = 24.0
			sp.spot_attenuation = 0.6
			sp.light_volumetric_fog_energy = 1.6
			sp.position = Vector3(p.x, r - 1.0, p.y)
			sp.rotation_degrees = Vector3(-90, 0, 0)
			add_child(sp)
		placed += 1
		if placed >= 22:
			break


func _shore() -> void:
	for i in 12:
		var a := TAU * i / 12.0 + 0.3
		var p := LAKE + Vector2(cos(a) * LAKE_R.x * 1.08, sin(a) * LAKE_R.y * 1.08)
		if trail_at(p.x, p.y) > 0.1:
			continue
		crystals(_v(p, -0.15), Vector3.UP, rng.randf_range(0.6, 1.5), i % 3, 1300 + i, i % 4 == 0)
	var lamp := _v(LAKE + Vector2(-8, 19))
	Kit.mesh_node(self, Kit.prop("Lantern_01", "Lantern_01"), null, Kit.xf(lamp, 0.0, Vector3.ONE * 1.5))
	Kit.omni(self, lamp + Vector3(0, 0.5, 0), Color(1.0, 0.68, 0.38), 0.9, 6.0)


func _vault() -> void:
	stone = RealKit.stone_mat("mossy_stone_wall") if RealKit.enabled() else Kit.tri("castle_wall_slates", "1k", 0.45, 0.1)
	var y0 := height(VAULT.x, VAULT.y)
	var c := Vector3(VAULT.x, y0, VAULT.y)
	var sb := StoneBuilder.new(height, 151)
	sb.base_y = y0 - 1.0
	sb.top_y = y0 + 12.0
	# a forecourt of worn flags, a facade wall into the rock, two great columns, a lintel and a pediment
	sb.block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.1, 3.0)), Vector3(14.0, 0.4, 7.0), 0.1, 0.04)
	sb.collider(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.1, 3.0)), Vector3(14.0, 0.4, 7.0))
	sb.wall(c + Vector3(-8.0, 0.2, -1.2), c + Vector3(-2.2, 0.2, -1.2), 10.0, 2.0, 0.0)
	sb.wall(c + Vector3(2.2, 0.2, -1.2), c + Vector3(8.0, 0.2, -1.2), 10.0, 2.0, 0.0)
	sb.block(Transform3D(Basis.IDENTITY, c + Vector3(0, 8.7, -1.2)), Vector3(4.4, 3.0, 2.0), 0.0, 0.05)
	for sx: float in [-1.0, 1.0]:
		sb.column(c + Vector3(sx * 3.4, 0.3, 0.4), 0.72, 8.0, 16)
	sb.block(Transform3D(Basis.IDENTITY, c + Vector3(0, 8.7, 0.3)), Vector3(9.2, 1.0, 1.8), 0.0, 0.06)
	sb.block(Transform3D(Basis.IDENTITY, c + Vector3(0, 9.6, 0.1)), Vector3(7.6, 0.8, 1.5), 0.0, 0.06)
	sb.block(Transform3D(Basis.IDENTITY, c + Vector3(0, 10.4, -0.1)), Vector3(5.2, 0.8, 1.2), 0.0, 0.06)
	sb.finish(self, stone, "VaultFacade")
	for p in Kit.prop_parts("large_castle_door"):
		Kit.mesh_node(self, p[0], null, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.0), c + Vector3(0, 0.3, -0.25)) * p[1])
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
	seal.position = c + Vector3(0, 7.4, -0.15)
	add_child(seal)
	Kit.omni(self, c + Vector3(0, 6.5, 2.0), Color(0.35, 0.9, 1.0), 1.6, 11.0)
	add_location("ancient_vault", Vector3(c.x, 0, c.z), 12.0, c + Vector3(0, 0.3, 5.0), "an ancient vault carved into the cavern wall, a seal glowing above its door")


## Faint light on the cavern walls (seeping mineral glow) so the space reads as a space, and the vault's two fire
## braziers: warm against the cold crystal light, the place someone once kept.
func _glow() -> void:
	for i in 10:
		var a := TAU * i / 10.0 + 0.2
		var p := CAVERN + Vector2(cos(a) * CAVERN_R.x * 0.82, sin(a) * CAVERN_R.y * 0.82)
		var y := lerpf(height(p.x, p.y), roof(p.x, p.y), 0.35)
		var l := Kit.omni(self, Vector3(p.x, y, p.y), Color(0.35, 0.7, 0.8), 0.9, 22.0)
		l.light_specular = 0.2
	var c := _v(VAULT)
	for sx: float in [-1.0, 1.0]:
		var at := c + Vector3(sx * 5.6, 0.3, 4.2)
		var bowl := Kit.lathe([Vector2(0.0, 0.0), Vector2(0.18, 0.0), Vector2(0.14, 0.12), Vector2(0.12, 0.85), Vector2(0.2, 0.9), Vector2(0.42, 1.02), Vector2(0.5, 1.2), Vector2(0.44, 1.22), Vector2(0.0, 1.05)], 16, false)
		Kit.mesh_node(self, bowl, stone, Kit.xf(at))
		var f := Campfire.new()
		f.name = "VaultBrazier"
		add_child(f)
		f.position = at + Vector3(0, 1.08, 0)
		f.scale = Vector3.ONE * 0.75
		f.ignite(0.5, 1.0e9)


func links() -> void:
	add_gate("crystal_caverns", _v(ENTRY), _v(ENTRY + Vector2(8, 0), 0.05), -PI * 0.5, 2.4)
	var c := _v(VAULT)
	var it := Interactable.make("vault_seal_resonate", "Resonate the vault seal with a crystal shard", "attune", "ancient_vault",
		c + Vector3(0, 0.3, 2.5), {"knowledge": {"vault:seal_resonated": 1, "lore:ancient_vault": 1}}, "spell_casting", 4.2)
	it.requires = {"items": {"crystal_shard": 1}}
	it.repeatable = false
	it.radius = 2.6
	it.on_done = func():
		seal_mat.set_shader_parameter("intensity", 2.5)
		seal_mat.set_shader_parameter("spin", 0.4)
	add_interactable(it)
	add_interactable(Interactable.make("vault_inscription", "Read the inscription carved beside the vault door", "study", "ancient_vault",
		c + Vector3(-3.0, 0.3, 2.2), {"knowledge": {"lore:vault_inscription": 1}}, "look_around", 3.5)).radius = 2.4
	add_interactable(Interactable.make("lake_meditate", "Meditate at the still lake's edge", "meditate", "underground_lake",
		_v(LAKE + Vector2(-6, 19)), {"skills": {"arcane_orb": 0.12}, "knowledge": {"calm:underground_lake": 1}}, "", 4.0)).radius = 2.6


func showcase_shots(loc: String) -> Array:
	var c := _v(VAULT)
	if loc == "ancient_vault":
		return [[c + Vector3(8, 2.5, 14), c + Vector3(0, 4.5, 0), 55.0]]
	var l := _v(LAKE + Vector2(-10, 20))
	return [[l + Vector3(0, 2.4, 0), _v(LAKE) + Vector3(0, 3.0, 0), 60.0]]
