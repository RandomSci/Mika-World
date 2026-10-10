class_name AlchemyTable
extends Node3D
## The Sanctuary's alchemy table: three vessels (moonwater, sylph dew, ember salt) and a mixing bowl.
## An experiment is fully physical: inspect the ingredients (head turns to each), then for each chosen
## ingredient reach -> grasp -> carry over the bowl -> tilt and pour (stream + bowl level/colour change)
## -> return it to its slot; optionally stir with a thread of arcane light. The bowl's reaction decides:
##   moonwater + sylph dew + arcane stir  -> Luminous Draught (glows; 1 added to inventory)
##   ember salt with moonwater           -> fizz and smoke, murky bowl (nothing gained)
##   anything else                       -> a cloudy, inert mixture
## The bowl drains and the vessels are topped up from the stores ~40 s later (bounded, repeatable).

const RECIPES := {
	"luminous_draught": {"ingredients": ["moonwater", "sylph_dew"], "stir": true, "item": "luminous_draught"},
}
const LIQUID_COLORS := {"moonwater": Color(0.7, 0.85, 1.0), "sylph_dew": Color(0.7, 1.0, 0.75), "ember_salt": Color(1.0, 0.5, 0.15)}

var vessels := {}               # contents id -> HoldableObject
var bowl_liquid: MeshInstance3D
var bowl_mat: StandardMaterial3D
var bowl_light: OmniLight3D
var bowl_pos := Vector3.ZERO
var bowl := []                  # ingredients poured, in order
var bowl_state := "empty"
var busy := false
var _reset_at := -1.0


func build(area: Node3D, pos: Vector3, yaw: float) -> void:
	area.add_child(self)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	var wood := Kit.uvmat("dark_wooden_planks")
	var top := Kit.mesh_node(self, Kit.box_mesh(Vector3(0.7, 0.07, 1.45), 0.015), wood, Kit.xf(Vector3(0, 0.79, 0)))
	top.name = "TableTop"
	for c in [Vector2(-0.28, -0.62), Vector2(0.28, -0.62), Vector2(-0.28, 0.62), Vector2(0.28, 0.62)]:
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.07, 0.76, 0.07), 0.01), wood, Kit.xf(Vector3(c.x, 0.38, c.y)))
	Kit.static_box(self, Vector3(0.7, 0.82, 1.45), Kit.xf(Vector3(0, 0.41, 0)))
	Kit.place_prop(self, "chemistry_set", Kit.xf(Vector3(-0.2, 0.825, 0.45), PI * 0.5, Vector3.ONE * 0.9))
	# mixing bowl at the front edge (the reader side is local +X)
	bowl_pos = to_global(Vector3(0.12, 0.825, -0.05))
	var bm := Kit.mesh_node(self, Kit.lathe([Vector2(0.05, 0.0), Vector2(0.11, 0.02), Vector2(0.15, 0.07), Vector2(0.16, 0.1), Vector2(0.14, 0.1), Vector2(0.13, 0.07), Vector2(0.09, 0.025), Vector2(0.0, 0.02)], 24, true, false),
		Kit.uvmat("plastered_wall_02", "1k", Vector2.ONE, Color(0.75, 0.72, 0.68)), Kit.xf(Vector3(0.12, 0.825, -0.05)))
	bm.name = "MixingBowl"
	bowl_liquid = MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.125
	lm.bottom_radius = 0.09
	lm.height = 0.05
	bowl_liquid.mesh = lm
	bowl_mat = StandardMaterial3D.new()
	bowl_mat.albedo_color = Color(0.6, 0.7, 0.8, 0.85)
	bowl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bowl_mat.roughness = 0.1
	bowl_mat.emission_enabled = true
	bowl_mat.emission = Color(0, 0, 0)
	bowl_liquid.material_override = bowl_mat
	bowl_liquid.position = Vector3(0.12, 0.85, -0.05)
	bowl_liquid.visible = false
	add_child(bowl_liquid)
	bowl_light = FX.light(Color(0.7, 0.85, 1.0), 0.0, 2.5)
	bowl_light.position = Vector3(0.12, 1.0, -0.05)
	add_child(bowl_light)
	# vessels
	_vessel("moonwater", "flask of moonwater", "Silver-blue water drawn under a full moon.", Vector3(0.12, 0.825, -0.5), "flask")
	_vessel("sylph_dew", "vial of sylph dew", "Pale green dew gathered at dawn; smells of rain.", Vector3(0.14, 0.825, -0.3), "vial")
	_vessel("ember_salt", "jar of ember salt", "Orange crystals, faintly warm to the touch.", Vector3(0.12, 0.825, 0.32), "jar")


func _vessel(contents: String, label: String, desc: String, local: Vector3, shape: String) -> void:
	var h := HoldableObject.new()
	h.setup(contents, label, desc, contents, ["inspect", "pick_up", "pour", "place", "return"])
	add_child(h)
	h.position = local
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.92, 0.95, 0.28)
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	glass.rim_enabled = true
	glass.rim = 0.5
	var liq := StandardMaterial3D.new()
	liq.albedo_color = LIQUID_COLORS[contents]
	liq.emission_enabled = true
	liq.emission = LIQUID_COLORS[contents] * 0.25
	match shape:
		"flask":
			Kit.mesh_node(h, Kit.lathe([Vector2(0.0, 0.0), Vector2(0.065, 0.005), Vector2(0.07, 0.07), Vector2(0.03, 0.14), Vector2(0.022, 0.2), Vector2(0.026, 0.215)], 16, true, false), glass, Transform3D.IDENTITY, false)
			Kit.mesh_node(h, Kit.lathe([Vector2(0.0, 0.006), Vector2(0.06, 0.01), Vector2(0.063, 0.065), Vector2(0.0, 0.07)], 16, true, false), liq, Transform3D.IDENTITY, false)
			h.grasp_height = 0.15
		"vial":
			Kit.mesh_node(h, Kit.lathe([Vector2(0.0, 0.0), Vector2(0.03, 0.005), Vector2(0.03, 0.13), Vector2(0.018, 0.15), Vector2(0.02, 0.165)], 12, true, false), glass, Transform3D.IDENTITY, false)
			Kit.mesh_node(h, Kit.lathe([Vector2(0.0, 0.006), Vector2(0.026, 0.008), Vector2(0.026, 0.09), Vector2(0.0, 0.095)], 12, true, false), liq, Transform3D.IDENTITY, false)
			h.grasp_height = 0.1
		"jar":
			var ceramic := StandardMaterial3D.new()
			ceramic.albedo_color = Color(0.55, 0.42, 0.32)
			ceramic.roughness = 0.6
			Kit.mesh_node(h, Kit.lathe([Vector2(0.0, 0.0), Vector2(0.06, 0.005), Vector2(0.065, 0.09), Vector2(0.045, 0.11), Vector2(0.0, 0.11)], 16, true, false), ceramic, Transform3D.IDENTITY, false)
			var top := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.04
			tm.bottom_radius = 0.045
			tm.height = 0.01
			top.mesh = tm
			top.material_override = liq
			top.position.y = 0.112
			h.add_child(top)
			h.grasp_height = 0.07
	vessels[contents] = h


func remember_homes() -> void:
	for v in vessels.values():
		(v as HoldableObject).remember_home()


func describe() -> Dictionary:
	return {"bowl": bowl.duplicate(), "bowl_state": bowl_state, "vessels": vessels.values().map(func(v): return v.describe()),
		"known_recipes": RECIPES.keys().filter(func(k): return WorldState.knowledge.has("recipe:" + k))}


## A whole experiment by `c`. ingredients = [] lets the table choose: the known recipe if she knows one,
## otherwise a curious (and possibly wrong) pairing. Returns exactly what happened.
func experiment(c: WorldCharacter, ingredients: Array = [], stir = null) -> Dictionary:
	if busy:
		return {"ok": false, "detail": "the table is in use"}
	if bowl_state != "empty":
		return {"ok": false, "detail": "the bowl still holds the last mixture (%s); it drains soon" % bowl_state}
	busy = true
	var h: ObjectHandler = c.handler
	var steps := []
	var knows: bool = WorldState.knowledge.has("recipe:luminous_draught")
	if ingredients.is_empty():
		if knows:
			ingredients = RECIPES.luminous_draught.ingredients.duplicate()
		else:
			ingredients = ["moonwater", ["ember_salt", "sylph_dew"].pick_random()]
	if stir == null:
		stir = knows
	# look over the ingredients first
	for v in vessels.values():
		c.look_head_at((v as HoldableObject).grasp_point())
		await get_tree().create_timer(0.9).timeout
	steps.append("inspected %s" % ", ".join(vessels.values().map(func(v): return v.label)))
	for ing in ingredients:
		var v: HoldableObject = vessels.get(ing)
		if v == null:
			steps.append("no %s on the table" % ing)
			continue
		c.look_head_at(v.grasp_point())
		if not await h.grasp(v):
			steps.append("could not reach the %s" % v.label)
			continue
		steps.append("picked up the %s" % v.label)
		c.look_head_at(bowl_pos + Vector3(0, 0.1, 0))
		if await h.carry_to(bowl_pos + Vector3(0.04, 0.09, 0.0)):
			MagicEvents.emit_phase(c, "alchemy", "pour", ing, bowl_pos)
			await h.set_tilt(deg_to_rad(105.0), 0.7)
			_pour_fx(v, ing)
			await get_tree().create_timer(1.1).timeout
			v.amount = maxf(0.0, v.amount - 0.35)
			bowl.append(ing)
			_update_bowl()
			await h.set_tilt(0.0, 0.5)
			steps.append("poured %s into the bowl" % ing)
		await h.place(v.home)
		steps.append("returned the %s" % v.label)
	await h.relax(0.5)
	if stir:
		c.look_head_at(bowl_pos)
		await h.reach(bowl_pos + Vector3(0, 0.22, 0), 0.6)
		MagicEvents.emit_phase(c, "alchemy", "stir", "arcane", bowl_pos)
		FX.burst(self, bowl_pos + Vector3(0, 0.12, 0), 30, 1.0, FX.pm_motes("arcane", "gather"), FX.mote_mesh(0.03))
		await get_tree().create_timer(1.2).timeout
		await h.relax(0.5)
		steps.append("stirred once with a thread of arcane light")
	c.look_head_at(null)
	var res := _resolve(stir)
	res["steps"] = steps
	res["ingredients"] = ingredients
	busy = false
	_reset_at = Time.get_ticks_msec() / 1000.0 + 40.0
	return res


func _pour_fx(v: HoldableObject, ing: String) -> void:
	var col: Color = LIQUID_COLORS[ing]
	var pm := FX.process("pour_" + ing, func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.01
		pm.direction = Vector3.DOWN
		pm.spread = 6.0
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.4
		pm.gravity = Vector3(0, -6.0, 0)
		pm.scale_min = 0.6
		pm.scale_max = 1.0
		pm.color_ramp = FX.ramp([Color(col, 0.9), Color(col, 0.0)]))
	var p := FX.particles(70, 0.35, pm, FX.mote_mesh(0.02))
	add_child(p)
	p.global_position = bowl_pos + Vector3(0, 0.2, 0)
	p.emitting = true
	get_tree().create_timer(1.1).timeout.connect(func(): p.emitting = false)
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _update_bowl() -> void:
	bowl_liquid.visible = not bowl.is_empty()
	var col := Color(0, 0, 0)
	for ing in bowl:
		col += LIQUID_COLORS[ing]
	col /= maxf(bowl.size(), 1)
	bowl_mat.albedo_color = Color(col, 0.85)
	bowl_liquid.scale = Vector3(1.0, 0.6 + 0.4 * minf(bowl.size(), 3), 1.0)


func _resolve(stirred: bool) -> Dictionary:
	var set_ := bowl.duplicate()
	set_.sort()
	if set_.has("ember_salt") and set_.has("moonwater"):
		bowl_state = "fizzing"
		bowl_mat.albedo_color = Color(0.45, 0.32, 0.2, 0.9)
		FX.burst(self, bowl_pos + Vector3(0, 0.12, 0), 40, 1.6, FX.pm_motes("fire", "burst"), FX.mote_mesh(0.025))
		FX.burst(self, bowl_pos + Vector3(0, 0.15, 0), 24, 2.6, FX.pm_puff("smoke"), FX.puff_mesh(0.3))
		var ch := WorldState.record_activity({"id": "alchemy_fizz", "verb": "craft", "label": "Ember salt with moonwater"}, {"knowledge": {"alchemy:ember_salt_fizz": 1}})
		return {"ok": true, "outcome": "fizz", "detail": "the mixture fizzed, spat orange sparks and smoked; nothing usable", "changes": ch}
	var rec: Array = RECIPES.luminous_draught.ingredients.duplicate()
	rec.sort()
	if set_ == rec and stirred:
		bowl_state = "glowing"
		bowl_mat.emission = Color(0.6, 0.85, 1.0)
		bowl_mat.emission_energy_multiplier = 2.0
		var tw := create_tween()
		tw.tween_property(bowl_light, "light_energy", 1.6, 1.2)
		FX.burst(self, bowl_pos + Vector3(0, 0.15, 0), 40, 1.6, FX.pm_motes("water", "rise"), FX.mote_mesh(0.03))
		var ch2 := WorldState.record_activity({"id": "alchemy_luminous_draught", "verb": "craft", "label": "Brewed a Luminous Draught"},
			{"items": {"luminous_draught": 1}, "knowledge": {"alchemy:luminous_draught_brewed": 1}})
		return {"ok": true, "outcome": "luminous_draught", "detail": "the mixture began to glow softly and smelled of rain: one Luminous Draught", "changes": ch2}
	bowl_state = "cloudy"
	var why := "it was not stirred with arcane light" if set_ == rec else "this combination does not react"
	return {"ok": true, "outcome": "inert", "detail": "the mixture stayed cloudy and inert (%s)" % why, "changes": {}}


func _process(_delta: float) -> void:
	if _reset_at > 0.0 and Time.get_ticks_msec() / 1000.0 > _reset_at and not busy:
		_reset_at = -1.0
		bowl.clear()
		bowl_state = "empty"
		bowl_mat.emission = Color(0, 0, 0)
		bowl_light.light_energy = 0.0
		_update_bowl()
		for v in vessels.values():
			(v as HoldableObject).amount = 1.0   # topped up from the sanctuary stores
