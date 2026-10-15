extends MountainRegion
## E3 Celestial Observatory + E4 Cloud Temple (Celestial Highlands) - rebuilt on the realistic toolkit
## (world-quality gate). The SUMMIT: a high rock massif standing out of the sea of clouds, cliffs on every side.
##   S  the PILGRIM STAIRWAY climbs a narrow ridge from the mountain path to the summit (worn steps, cairns)
##   W  the CELESTIAL OBSERVATORY on the western shoulder: a brass armillary sphere turning over a rune disc, a stone
##      star dial; the widest view of the sky
##   NE the CLOUD TEMPLE at the cliff edge: a stepped masonry podium, timber columns, two flared slate roofs,
##      lanterns, an altar with candles in the sanctum - beyond it only the clouds
## Snow lies in the hollows; wind-bent spruces cling below the rim.

const OBS := Vector3(-34, 0, -6)
const TEMPLE := Vector3(26, 0, -40)
const TOP := Vector2(-2, -14)               # the plateau's centre
const GATE_PATH := Vector2(3.0 * sin(134.0 * 0.05), 134)   # on the ridge's crest

var stone: ShaderMaterial
var roof: Material
var wood: Material
var rings: Array[Node3D] = []


func _init() -> void:
	cloud_y = -80.0
	treeline = 14.0
	snowline = 34.0
	# the stairway keeps to the crest of the ridge (x = 3 sin(z * 0.05), shape() below): a few metres off it the
	# ground falls away to the clouds
	var crest: Array = [GATE_PATH]
	var zc := 124.0
	while zc > 38.0:
		crest.append(Vector2(3.0 * sin(zc * 0.05), zc))
		zc -= 8.0
	crest.append(Vector2(0, 38))
	crest.append(TOP + Vector2(0, 20))
	trails = [
		[crest, 2.6, "main"],
		[[TOP + Vector2(0, 20), Vector2(-14, 8), Vector2(OBS.x + 6, OBS.z + 6)], 2.0, "main"],
		[[TOP + Vector2(0, 20), Vector2(10, -6), Vector2(TEMPLE.x - 4, TEMPLE.z + 14)], 2.4, "main"],
	]
	clearings = [[Vector2(OBS.x, OBS.z), 10.0, "glade"], [Vector2(TEMPLE.x, TEMPLE.z), 13.0, "glade"], [TOP + Vector2(0, 18), 8.0, "glade"]]
	streams = []


func gate_spots() -> Array:
	return [GATE_PATH]


func _plateau(x: float, z: float) -> float:
	# 0 inside the summit plateau .. 1 at its rim (an irregular oval), more beyond
	var p := Vector2(x - TOP.x, (z - TOP.y) * 1.15)
	var r := 62.0 + 7.0 * sin(atan2(p.y, p.x) * 3.0 + 0.6) + 4.0 * sin(atan2(p.y, p.x) * 7.0)
	return p.length() / r


func shape(x: float, z: float, h: float) -> float:
	var top := 34.0 + h * 1.4 - 3.0 * smoothstep(0.3, 0.95, _plateau(x, z))
	# the ridge the stairway climbs: from the summit's south rim down to the mountain path
	var ridge_t := clampf((z - 40.0) / 94.0, 0.0, 1.0)
	var ridge_w := lerpf(18.0, 13.0, ridge_t)          # a crest wide enough to walk two abreast all the way down
	var on_ridge := 1.0 - smoothstep(ridge_w * 0.5, ridge_w, absf(x - 3.0 * sin(z * 0.05)))
	var ridge_h := lerpf(30.0, 2.0, ridge_t) + h * 0.3
	var fall := smoothstep(0.95, 1.25, _plateau(x, z))
	var cliff := -170.0
	var v := lerpf(top, cliff, fall)
	# the ridge runs on onto the plateau's rim (it used to stop at z = 30, just where the rim begins to fall
	# away, which left a 68-degree notch between stairway and summit)
	if z > 10.0:
		v = maxf(v, lerpf(cliff, ridge_h, on_ridge * smoothstep(10.0, 22.0, z)))
	return v


func features() -> Array:
	return [_observatory, _temple_base, _temple_hall, _temple_roofs, _stair_cairns, func(): outcrops([[Vector2(-58, -40), 3.2], [Vector2(50, 6), 2.8], [Vector2(-20, -62), 2.6], [Vector2(-50, 20), 2.4]])]


func _v(p: Vector2) -> Vector3:
	return Vector3(p.x, height(p.x, p.y), p.y)


func _stone() -> ShaderMaterial:
	if stone == null:
		stone = RealKit.stone_mat("mossy_stone_wall") if RealKit.enabled() else Kit.tri("castle_wall_slates", "1k", 0.45, 0.12)
	return stone


func _mats() -> void:
	if roof == null:
		roof = Kit.uvmat("roof_slates_02", "1k", Vector2(4, 3), Color(0.55, 0.6, 0.62))
		wood = Kit.tri("dark_wooden_planks", "1k", 0.7, 0.0, Color(0.5, 0.28, 0.2))


# ------------------------------------------------------------------ the observatory
func _observatory() -> void:
	_mats()
	var c := _v(Vector2(OBS.x, OBS.z))
	# a paved circle (worn flags) round the instrument
	var sb := StoneBuilder.new(height, 121)
	sb.base_y = c.y - 1.0
	sb.top_y = c.y + 2.0
	for i in 16:
		var a := TAU * i / 16.0
		sb.block(Transform3D(Basis(Vector3.UP, a), c + Vector3(cos(a) * 4.6, 0.05, sin(a) * 4.6)), Vector3(1.7, 0.3, 0.9), 0.15, 0.04)
	sb.finish(self, _stone(), "ObservatoryRing")
	rune_disc(c + Vector3(0, 0.08, 0), 4.0, Color(0.9, 0.75, 0.45), Color(0.7, 0.55, 1.0), 33.0)
	var brass := Kit.metal(Color(0.8, 0.6, 0.32), 0.25)
	Kit.mesh_node(self, Kit.lathe([Vector2(0.6, 0.1), Vector2(0.55, 0.3), Vector2(0.25, 0.45), Vector2(0.2, 1.4), Vector2(0.35, 1.5)], 12, false), _stone(), Kit.xf(c))
	Kit.static_box(self, Vector3(0.9, 1.5, 0.9), Kit.xf(c + Vector3(0, 0.75, 0)))
	var sphere_root := Node3D.new()
	sphere_root.position = c + Vector3(0, 2.6, 0)
	add_child(sphere_root)
	for i in 3:
		var t := TorusMesh.new()
		t.inner_radius = 0.95 - i * 0.15
		t.outer_radius = 1.02 - i * 0.15
		t.rings = 48
		t.ring_segments = 6
		var ring := Node3D.new()
		ring.rotation = Vector3(PI * 0.5 * (i % 2), i * 0.6, 0.41 * i)
		sphere_root.add_child(ring)
		Kit.mesh_node(ring, t, brass, Transform3D.IDENTITY)
		rings.append(ring)
	Kit.mesh_node(sphere_root, SphereMesh.new(), Kit.emissive(Color(0.7, 0.8, 1.0), 4.0, true), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.18), Vector3.ZERO), false)
	Kit.mesh_node(sphere_root, Kit.lathe([Vector2(0.03, -1.1), Vector2(0.03, 1.1)], 6), brass, Transform3D(Basis(Vector3.FORWARD, 0.41), Vector3.ZERO))
	Kit.omni(self, c + Vector3(0, 2.6, 0), Color(0.75, 0.82, 1.0), 1.2, 7.0)
	var dial := Vector3(c.x + 7.5, 0, c.z + 2.5)
	dial.y = height(dial.x, dial.z)
	Kit.mesh_node(self, Kit.lathe([Vector2(1.3, 0), Vector2(1.3, 0.7), Vector2(1.45, 0.78), Vector2(1.45, 0.86), Vector2(0, 0.86)], 32), _stone(), Kit.xf(dial))
	Kit.static_box(self, Vector3(2.4, 0.9, 2.4), Kit.xf(dial + Vector3(0, 0.45, 0)))
	Kit.mesh_node(self, Kit.box_mesh(Vector3(0.06, 0.7, 1.0), 0.01), brass, Transform3D(Basis(Vector3.RIGHT, 0.6), dial + Vector3(0, 1.1, 0)))
	add_location("celestial_observatory", Vector3(c.x, 0, c.z), 12.0, c + Vector3(0, 0.12, 5.2), "a brass armillary sphere on the summit's western shoulder")


func _process(delta: float) -> void:
	super._process(delta)
	for i in rings.size():
		rings[i].rotate_object_local(Vector3.UP, delta * (0.15 + i * 0.07))


# ------------------------------------------------------------------ the cloud temple
func _temple_y() -> float:
	return height(TEMPLE.x, TEMPLE.z)


func _temple_base() -> void:
	_mats()
	var y0 := _temple_y()
	var sb := StoneBuilder.new(height, 131)
	sb.base_y = y0 - 3.0
	sb.top_y = y0 + 3.0
	# a stepped masonry podium (three courses), its foot sunk into the slope
	for tier in 3:
		var w := 20.0 - tier * 2.4
		var d := 15.0 - tier * 2.0
		var yy := y0 - 0.6 + tier * 0.5
		var x := -w * 0.5
		while x < w * 0.5 - 0.01:
			var bw := minf(1.8, w * 0.5 - x)
			sb.block(Transform3D(Basis.IDENTITY, Vector3(TEMPLE.x + x + bw * 0.5, yy + 0.25, TEMPLE.z - tier * 0.4 + d * 0.5 - 0.45)), Vector3(bw, 0.5, 0.9), 0.2, 0.04)
			sb.block(Transform3D(Basis.IDENTITY, Vector3(TEMPLE.x + x + bw * 0.5, yy + 0.25, TEMPLE.z - tier * 0.4 - d * 0.5 + 0.45)), Vector3(bw, 0.5, 0.9), 0.2, 0.04)
			x += bw
		# the podium's fill and the temple floor: worn flagstones (the stone material grows moss on every top face)
		Kit.block(self, Vector3(w - 0.4, 0.5, d - 1.6), Kit.xf(Vector3(TEMPLE.x, yy + 0.25, TEMPLE.z - tier * 0.4)), Kit.tri("monastery_stone_floor", "2k", 0.35, 0.0, Color(0.86, 0.84, 0.8)), false, 0.03)
		for sx: float in [-1.0, 1.0]:
			sb.block(Transform3D(Basis.IDENTITY, Vector3(TEMPLE.x + sx * (w * 0.5 - 0.45), yy + 0.25, TEMPLE.z - tier * 0.4)), Vector3(0.9, 0.5, d), 0.2, 0.04)
	sb.steps(Vector3(TEMPLE.x, height(TEMPLE.x, TEMPLE.z + 12.0), TEMPLE.z + 12.0), Vector3(TEMPLE.x, y0 + 0.9, TEMPLE.z + 5.0), 5.0, 0.45, 0.16, 0.5)
	sb.finish(self, _stone(), "TemplePodium")
	Kit.static_box(self, Vector3(15.2, 1.5, 11.0), Kit.xf(Vector3(TEMPLE.x, y0 + 0.15, TEMPLE.z - 0.8)))


func _temple_hall() -> void:
	var y := _temple_y() + 0.9
	for ix in 4:
		for iz in 3:
			if iz == 1 and (ix == 1 or ix == 2):
				continue
			var p := TEMPLE + Vector3(-5.4 + ix * 3.6, 0, 3.0 - iz * 3.4)
			Kit.mesh_node(self, Kit.lathe([Vector2(0.38, 0), Vector2(0.32, 0.25), Vector2(0.3, 4.3), Vector2(0.42, 4.5)], 12), wood, Kit.xf(Vector3(p.x, y, p.z)))
			Kit.static_box(self, Vector3(0.7, 4.5, 0.7), Kit.xf(Vector3(p.x, y + 2.25, p.z)))
	var sb := StoneBuilder.new(height, 133)
	sb.base_y = y - 1.0
	sb.top_y = y + 5.0
	sb.wall(Vector3(TEMPLE.x - 5.9, y, TEMPLE.z - 4.0), Vector3(TEMPLE.x + 5.9, y, TEMPLE.z - 4.0), 4.5, 0.5, 0.0, 0.32)
	sb.finish(self, _stone(), "SanctumWall")
	Kit.block(self, Vector3(12.6, 0.5, 8.6), Kit.xf(Vector3(TEMPLE.x, y + 4.7, TEMPLE.z - 0.4)), wood, false, 0.04)
	Kit.block(self, Vector3(2.2, 1.0, 1.0), Kit.xf(Vector3(TEMPLE.x, y + 0.5, TEMPLE.z - 2.8)), _stone(), true, 0.04)
	Kit.place_prop(self, "brass_candleholders", Kit.xf(Vector3(TEMPLE.x - 0.6, y + 1.0, TEMPLE.z - 2.8)), "brass_candleholder_03")
	Kit.omni(self, Vector3(TEMPLE.x, y + 2.2, TEMPLE.z - 2.0), Color(1.0, 0.68, 0.4), 1.6, 8.0)
	for sx: float in [-1.0, 1.0]:
		Kit.mesh_node(self, Kit.prop("Lantern_01", "Lantern_01"), null, Kit.xf(Vector3(TEMPLE.x + sx * 6.2, y + 3.6, TEMPLE.z + 3.6), 0.0, Vector3.ONE * 2.0))
		night_only(Kit.omni(self, Vector3(TEMPLE.x + sx * 6.2, y + 3.9, TEMPLE.z + 3.6), Color(1.0, 0.62, 0.32), 1.4, 8.0))
	add_location("cloud_temple", Vector3(TEMPLE.x, 0, TEMPLE.z), 15.0, Vector3(TEMPLE.x, y + 0.05, TEMPLE.z + 1.5), "a temple with flared roofs at the summit's cliff edge, above the clouds")


func _temple_roofs() -> void:
	var y := _temple_y() + 0.9 + 4.95
	var base := Vector3(TEMPLE.x, y, TEMPLE.z - 0.4)
	Kit.mesh_node(self, Kit.lathe([Vector2(10.6, 0.0), Vector2(9.6, 0.5), Vector2(6.0, 2.4), Vector2(4.6, 2.9)], 4, false), roof, Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(1.0, 1.0, 0.72)), base))
	Kit.block(self, Vector3(6.0, 2.0, 4.6), Kit.xf(base + Vector3(0, 3.8, 0)), wood, false, 0.03)
	Kit.mesh_node(self, Kit.lathe([Vector2(6.4, 0.0), Vector2(5.8, 0.4), Vector2(2.4, 2.4), Vector2(0.3, 3.2)], 4, false), roof, Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(1.0, 1.0, 0.75)), base + Vector3(0, 4.7, 0)))
	Kit.mesh_node(self, Kit.lathe([Vector2(0.15, 0), Vector2(0.1, 1.6), Vector2(0.0, 1.9)], 6), Kit.metal(Color(0.8, 0.6, 0.3), 0.3), Kit.xf(base + Vector3(0, 7.8, 0)))
	night_only(Kit.mesh_node(self, Kit.box_mesh(Vector3(5.6, 1.0, 4.65), 0.02), Kit.emissive(Color(1.0, 0.65, 0.35), 2.0), Kit.xf(base + Vector3(0, 3.8, 0)), false))


func _stair_cairns() -> void:
	var sb := StoneBuilder.new(height, 141)
	for z in [116.0, 96.0, 76.0, 56.0]:
		var p := Vector2(3.0 * sin(z * 0.05) + 4.2, z)
		var y := height(p.x, p.y) - 0.1
		for k in 5:
			var s := lerpf(0.7, 0.3, k / 5.0)
			sb.block(Transform3D(Basis(Vector3.UP, k * 0.9 + z), Vector3(p.x, y + 0.14 + k * 0.26, p.y)), Vector3(s, 0.28, s * 0.85), 0.25, 0.08)
	sb.finish(self, _stone(), "StairCairns")
	add_poi("pilgrim_stair", _v(Vector2(0, 76)), "The pilgrims' stairway up the ridge", "cloud_temple", 2.4)


## The ninth gate: the frieze's two sisters who would not climb alone. Honest conditions, checked in the world.
func _ninth_gate(c: WorldCharacter, it: Interactable) -> Dictionary:
	it.effects = {}
	var partner: WorldCharacter = null
	for n in get_tree().get_nodes_in_group("avoid"):
		if n is WorldCharacter and n != c and (n as WorldCharacter).visible and (n as WorldCharacter).global_position.distance_to(c.global_position) < 4.0:
			partner = n
	var h := WorldState.hour_f()
	var why := []
	if partner == null:
		why.append("the gate does not answer one alone")
	if not (WorldState.night and (h >= 24.0 or h < 1.5)):
		why.append("the Twin Lights are not over the temple (they stand there just after midnight)")
	for who in [c] + ([partner] if partner else []):
		if WorldState.mind(who.character_id).level() < 89:
			why.append("%s is not ready to climb so high (level %d)" % [MagicSystem.display_name(who.character_id), WorldState.mind(who.character_id).level()])
	if not why.is_empty():
		return {"ok": false, "detail": "the ninth gate stays shut: " + "; ".join(why)}
	for who in [c, partner]:
		WorldState.record_activity({"id": "ninth_gate", "verb": "attune", "label": "Opened the ninth gate together"}, {"knowledge": {"ninth_gate:opened": 1}}, who.character_id)
	return {"ok": true, "detail": "the ninth gate opened for the two of them together"}


func links() -> void:
	edge_gate("highland_path", GATE_PATH)
	var y := _temple_y() + 0.9
	add_interactable(Interactable.make("temple_pray", "Offer a quiet prayer in the Cloud Temple", "pray", "cloud_temple",
		Vector3(TEMPLE.x, y, TEMPLE.z - 1.4), {"skills": {"arcane_orb": 0.15}, "knowledge": {"blessing:cloud_temple": 1}}, "spell_casting", 4.2)).radius = 2.6
	add_interactable(Interactable.make("temple_frieze_read", "Read the frieze carved round the temple wall", "read", "cloud_temple",
		Vector3(TEMPLE.x - 1.8, y, TEMPLE.z - 0.4), {"knowledge": {"lore:cloud_temple_frieze": 1}}, "", 4.0)).radius = 2.4
	interactables["temple_frieze_read"].book_id = "summit_frieze"
	add_interactable(Interactable.make("weaver_stone_read", "Read the stone set in the floor beneath the altar", "read", "cloud_temple",
		Vector3(TEMPLE.x + 1.2, y, TEMPLE.z - 0.8), {"knowledge": {"lore:weaver_stone": 1}}, "", 4.0)).radius = 2.2
	interactables["weaver_stone_read"].book_id = "weaver_words"
	# the ninth gate (docs/WORLD_BIBLE.md): the Level 90 Orbit Gate - it answers only two mages together, at night
	# when the Twin Lights stand over the temple (00:00-01:30), both ready to climb (level 89+)
	var gate := Interactable.make("ninth_gate_open", "Stand under the Twin Lights and ask the ninth gate to open", "attune", "cloud_temple",
		Vector3(TEMPLE.x, y, TEMPLE.z + 0.6), {}, "spell_casting", 5.0)
	gate.radius = 2.6
	gate.custom_activity = _ninth_gate.bind(gate)
	add_interactable(gate)
	add_interactable(Interactable.make("twin_lights_watch", "Watch the night sky over the temple for the Twin Lights", "observe", "cloud_temple",
		Vector3(TEMPLE.x, y, TEMPLE.z + 4.5), {"knowledge": {"sight:twin_lights": 1, "astronomy:twin_lights": 1}}, "look_around", 6.0)).radius = 2.6
	add_interactable(Interactable.make("armillary_align", "Align the armillary sphere to the stars", "study", "celestial_observatory",
		_v(Vector2(OBS.x, OBS.z + 1.3)), {"knowledge": {"astronomy:armillary": 1}}, "look_around", 4.0)).radius = 2.2
	add_interactable(Interactable.make("star_dial_read", "Read the time on the star dial", "read", "celestial_observatory",
		_v(Vector2(OBS.x + 7.5, OBS.z + 4.1)), {"knowledge": {"astronomy:star_dial": 1}}, "", 3.0)).radius = 2.0


func showcase_shots(loc: String) -> Array:
	var ty := _temple_y()
	if loc == "cloud_temple":
		return [[Vector3(TEMPLE.x - 14.0, ty + 4.0, TEMPLE.z + 18.0), Vector3(TEMPLE.x, ty + 5.0, TEMPLE.z), 55.0]]
	var oy := height(OBS.x, OBS.z)
	return [[Vector3(OBS.x + 6.0, oy + 2.2, OBS.z + 8.0), Vector3(OBS.x, oy + 2.4, OBS.z), 50.0], [Vector3(-20, oy + 3.0, -20), Vector3(400, cloud_y, -600), 55.0]]
