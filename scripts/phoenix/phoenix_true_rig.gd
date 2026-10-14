class_name PhoenixTrueRig
extends CreatureBody
## Oriel's TRUE FORM body: the original rigged Phoenix (tools/models/build_phoenix.py) with her authored clips,
## plus what a clip cannot know: where she looks (PhoenixGaze), flight bob / bank / pitch on a pivot, the fire
## of her feathers (feather.gdshader: each feather burns from within, flame licks at the tips), the flame tongues
## trailing from her flight feathers, train and crest (flame_card.gdshader), the gold of her gorget, crown and
## coverts, a halo of firelight behind her, flame wisps from her wingtips and train, sparks drifting around her,
## the warm light of her chest, and the burn of the transformation (dissolve). v3 (visual pass 2) after the
## developer's references. The Phoenix script owns behaviour; this body only shows it.

const GLB := "res://assets/creatures/phoenix/phoenix_true.glb"
const ATLAS := "res://assets/creatures/phoenix/feather_atlas.png"
const IRIS := "res://assets/creatures/phoenix/iris.png"
## state -> [clip, speed, loop]
const CLIPS := {
	"idle": ["idle", 1.0, true], "breathe": ["breathe", 1.0, true], "look": ["look", 1.0, false],
	"wing_spread": ["wing_spread", 1.0, false], "wing_fold": ["wing_fold", 1.0, false],
	"move": ["walk", 1.0, true], "walk": ["walk", 1.0, true], "turn_left": ["turn_left", 1.0, true], "turn_right": ["turn_right", 1.0, true],
	"takeoff": ["takeoff", 1.0, false], "fly": ["fly", 1.0, true], "glide": ["glide", 1.0, true],
	"bank_left": ["bank_left", 1.0, true], "bank_right": ["bank_right", 1.0, true], "hover": ["hover", 1.0, true],
	"land": ["land", 1.0, false], "perch_settle": ["perch_settle", 1.0, false],
	"cast": ["cast_fire", 1.0, false], "cast_fire": ["cast_fire", 1.0, false], "windup": ["cast_fire", 0.6, false],
	"defend": ["defend", 1.0, false], "attack": ["attack", 1.0, false], "strike": ["attack", 1.0, false],
	"hit": ["react", 1.0, false], "react": ["react", 1.0, false], "recover": ["recover", 1.0, false],
	"preen": ["preen", 1.0, false], "call": ["call", 1.0, false], "bow": ["bow", 1.0, false], "stretch": ["stretch", 1.0, false],
	"defeat": ["recover", 0.5, false],
	"majestic": ["majestic", 1.0, true], "majestic_enter": ["majestic_enter", 1.0, false],
	"wing_wrap": ["wing_wrap", 1.0, false], "wing_burst": ["wing_burst", 1.0, false],
	"attack_charge": ["attack_charge", 1.0, false], "attack_hold": ["attack_hold", 1.0, true],
	"attack_release": ["attack_release", 1.0, false], "attack_recover": ["attack_recover", 1.0, false],
}
const DAY_GLOW := 1.0

var model: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var gaze: PhoenixGaze
var clearance: WingClearance          # keeps wingtips and train out of the ground and walls
var feather_mat: ShaderMaterial
var gold_mat: ShaderMaterial
var flame_mat: ShaderMaterial
var halo: MeshInstance3D
var halo_mat: ShaderMaterial
var chest_light: OmniLight3D
var pivot: Node3D
var hover := 0.0                     # extra height asked by the flight controller
var pitch := 0.0                     # radians, nose down > 0
var bank := 0.0                      # radians, set by the flight controller (left wing down < 0)
var _bank := 0.0
var _hurt := 0.0
var _t := 0.0
var _embers: Array[GPUParticles3D] = []
var _ember_rate := 0.0
var _heat := 0.0
var heat_target := 0.0
var clip_done := ""                  # the last non-looping clip that finished


func build() -> void:
	glow_color = Color(1.0, 0.6, 0.2)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	model = (load(GLB) as PackedScene).instantiate()
	model.name = "Model"
	pivot.add_child(model)
	player = model.find_child("AnimationPlayer", true, false)
	skeleton = model.find_child("Skeleton3D", true, false)
	var atlas: Texture2D = load(ATLAS)
	feather_mat = ShaderMaterial.new()
	feather_mat.shader = load("res://shaders/phoenix/feather.gdshader")
	feather_mat.set_shader_parameter("atlas", atlas)
	feather_mat.set_shader_parameter("noise_tex", FX.noise())
	feather_mat.set_shader_parameter("glow", DAY_GLOW)
	gold_mat = feather_mat.duplicate() as ShaderMaterial
	gold_mat.set_shader_parameter("metal", 1.0)
	gold_mat.set_shader_parameter("flicker", 0.0)
	flame_mat = ShaderMaterial.new()
	flame_mat.shader = load("res://shaders/phoenix/flame_card.gdshader")
	flame_mat.set_shader_parameter("atlas", atlas)
	flame_mat.set_shader_parameter("noise_tex", FX.noise())
	flame_mat.set_shader_parameter("strength", 0.22)
	var solid := _solid_mat(0.0, 0.72)
	var beak := _solid_mat(0.75, 0.24)
	var leg := _solid_mat(0.15, 0.45)
	var eye := StandardMaterial3D.new()
	eye.albedo_texture = load(IRIS)
	eye.emission_enabled = true
	eye.emission_texture = load(IRIS)
	eye.emission = Color(1.0, 0.85, 0.5)
	eye.emission_energy_multiplier = 0.12
	eye.albedo_color = Color(0.6, 0.55, 0.5)
	eye.roughness = 0.05
	eye.metallic = 0.1
	eye.clearcoat_enabled = true
	eye.clearcoat = 1.0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := String(m.name)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if n.begins_with("Feathers"):
			m.material_override = feather_mat
		elif n.begins_with("Gold"):
			m.material_override = gold_mat
		elif n.begins_with("Flames"):
			m.material_override = flame_mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("Beak"):
			m.material_override = beak
		elif n.begins_with("Legs"):
			m.material_override = leg
		elif n.begins_with("Eyes"):
			m.material_override = eye
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_eyes = m
		else:
			m.material_override = solid
	if skeleton:
		gaze = PhoenixGaze.new()
		gaze.name = "Gaze"
		skeleton.add_child(gaze)
		clearance = WingClearance.new()
		clearance.name = "Clearance"
		skeleton.add_child(clearance)
	var mls := float(RenderProfile.get_setting("magic_light_scale"))
	chest_light = FX.light(Color(1.0, 0.6, 0.24), 1.6 * mls, 9.0)
	chest_light.position = Vector3(0, 1.7, 0.5)
	pivot.add_child(chest_light)
	# the halo of firelight behind her
	halo = MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(1, 1)
	halo.mesh = hq
	halo_mat = ShaderMaterial.new()
	halo_mat.shader = load("res://shaders/phoenix/aura_halo.gdshader")
	halo_mat.set_shader_parameter("strength", 0.16)
	halo_mat.set_shader_parameter("color", Color(1.0, 0.36, 0.08))
	halo.material_override = halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.scale = Vector3.ONE * 7.5
	halo.position = Vector3(0, 2.0, 0)
	pivot.add_child(halo)
	# flame wisps from the wingtips, the outer primaries, the train and the crest (world space: they trail)
	var wisp_mat := ShaderMaterial.new()
	wisp_mat.shader = load("res://shaders/phoenix/fx_sprite.gdshader")
	wisp_mat.set_shader_parameter("atlas", atlas)
	wisp_mat.set_shader_parameter("noise_tex", FX.noise())
	wisp_mat.set_shader_parameter("cell", 0)
	wisp_mat.set_shader_parameter("strength", 1.1)
	var wq := QuadMesh.new()
	wq.size = Vector2(0.2, 0.42)
	wq.material = wisp_mat
	var wisp_pm := FX.process("phoenix_wisps_v3", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.22
		pm.direction = Vector3.UP
		pm.spread = 25.0
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 1.3
		pm.gravity = Vector3(0, 1.6, 0)
		pm.damping_min = 0.6
		pm.damping_max = 1.2
		pm.scale_min = 0.6
		pm.scale_max = 1.3
		pm.scale_curve = _curve_tex([0.3, 1.0, 0.0])
		pm.color_ramp = FX.ramp([Color(1, 0.6, 0.2, 0), Color(1, 0.42, 0.06, 0.7), Color(0.9, 0.12, 0.03, 0.4), Color(0.5, 0.02, 0.08, 0)], [0.0, 0.15, 0.55, 1.0]))
	var wisp_at := {"Prim9_L": 1.55, "Prim9_R": 1.55, "Prim5_L": 1.75, "Prim5_R": 1.75, "Stream3_L": 0.6, "Stream3_R": 0.6}
	for bn in wisp_at:
		var at := _attach(bn)
		if at == null:
			continue
		var p := FX.particles(9, 0.6, wisp_pm, wq)
		p.position = Vector3(0, float(wisp_at[bn]), 0)       # along the bone (+Y) to the feather's end
		p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 7, 6))
		p.emitting = false
		at.add_child(p)
		_wisps.append(p)
	# the old ember motes at the hands (dense when she casts) stay, now on the new sprite
	for bn in ["Hand_L", "Hand_R", "Stream3_L", "Stream3_R"]:
		var at := _attach(bn)
		if at == null:
			continue
		var p := FX.particles(18, 1.1, FX.process("phoenix_embers", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.12
			pm.direction = Vector3.UP
			pm.spread = 60.0
			pm.initial_velocity_min = 0.2
			pm.initial_velocity_max = 0.7
			pm.gravity = Vector3(0, 0.6, 0)
			pm.damping_min = 0.4
			pm.damping_max = 0.9
			pm.scale_min = 0.35
			pm.scale_max = 0.8
			pm.color_ramp = FX.ramp([Color(1, 0.75, 0.3, 0), Color(1, 0.55, 0.12, 1), Color(0.9, 0.25, 0.04, 0.8), Color(0.3, 0.05, 0.0, 0)], [0.0, 0.15, 0.6, 1.0])), FX.mote_mesh(0.045))
		p.position = Vector3(0, 0.85 if bn.begins_with("Hand") else 0.6, 0)   # along the bone (its +Y)
		p.emitting = false
		at.add_child(p)
		_embers.append(p)
	# sparks drifting around her (the glints of the references)
	var spark_mat := wisp_mat.duplicate() as ShaderMaterial
	spark_mat.set_shader_parameter("cell", 1)
	spark_mat.set_shader_parameter("strength", 3.0)
	var sq := QuadMesh.new()
	sq.size = Vector2(0.16, 0.16)
	sq.material = spark_mat
	_sparks = FX.particles(70, 2.6, FX.process("phoenix_sparks_v3", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(4.2, 1.8, 1.6)
		pm.direction = Vector3.UP
		pm.spread = 60.0
		pm.initial_velocity_min = 0.1
		pm.initial_velocity_max = 0.5
		pm.gravity = Vector3(0, 0.35, 0)
		pm.damping_min = 0.2
		pm.damping_max = 0.5
		pm.scale_min = 0.4
		pm.scale_max = 1.4
		pm.color_ramp = FX.ramp([Color(1, 0.85, 0.5, 0), Color(1, 0.75, 0.35, 1), Color(1, 0.5, 0.2, 0.0), Color(1, 0.6, 0.3, 0.9), Color(1, 0.4, 0.1, 0)], [0.0, 0.2, 0.45, 0.7, 1.0])), sq)
	_sparks.position = Vector3(0, 2.4, 0.2)
	_sparks.visibility_aabb = AABB(Vector3(-7, -4, -5), Vector3(14, 10, 10))
	_sparks.emitting = true
	pivot.add_child(_sparks)
	if player:
		player.playback_default_blend_time = 0.25
	_entered("idle")


var _wisps: Array[GPUParticles3D] = []
var _sparks: GPUParticles3D
var _glow := DAY_GLOW
var _aura := 0.0
var aura_target := 0.0


static func _curve_tex(pts: Array) -> CurveTexture:
	var c := Curve.new()
	for i in pts.size():
		c.add_point(Vector2(float(i) / maxf(pts.size() - 1, 1), float(pts[i])))
	var t := CurveTexture.new()
	t.curve = c
	return t


## Fire strength of her plumage (daylight 1.25; cinematic moments and dusk higher).
func set_glow(g: float) -> void:
	_glow = g


## 0 = her resting halo, 1 = the blazing halo (charging the nova, the transformation).
func set_aura(a: float) -> void:
	aura_target = clampf(a, 0.0, 1.0)


func chest_point() -> Vector3:
	return _bone_pos("Chest", Vector3(0, 1.7, 0.5))


var _solids: Array[ShaderMaterial] = []
var _eyes: MeshInstance3D


func _solid_mat(metal: float, rough: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/phoenix/phoenix_solid.gdshader")
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("roughness", rough)
	_solids.append(m)
	return m


func _attach(bone: String) -> BoneAttachment3D:
	if skeleton == null or skeleton.find_bone(bone) < 0:
		return null
	var b := BoneAttachment3D.new()
	b.name = "At_" + bone
	b.bone_name = bone
	skeleton.add_child(b)
	return b


func has_clip(c: String) -> bool:
	return player != null and player.has_animation(c)


func clip_length(st: String) -> float:
	var c: Array = CLIPS.get(st, [])
	if c.is_empty() or not has_clip(String(c[0])):
		return 0.0
	return player.get_animation(String(c[0])).length / maxf(float(c[1]), 0.05)


## Play a state (CreatureBody API) - the clip's loop mode follows the table.
func _entered(s: String) -> void:
	var c: Array = CLIPS.get(s, CLIPS.idle)
	play_clip(String(c[0]), 0.22, float(c[1]), bool(c[2]))


func play_clip(clip: String, blend := 0.22, speed := 1.0, loop := false) -> float:
	if player == null or not player.has_animation(clip):
		return 0.0
	var a := player.get_animation(clip)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	player.play(clip, blend, speed)
	return a.length / maxf(speed, 0.05)


func current_clip() -> String:
	return player.current_animation if player else ""


## Where a spell is aimed at her: the chest.
func aim_point() -> Vector3:
	return _bone_pos("Chest", Vector3(0, 1.65, 0.3))


func head_point() -> Vector3:
	return _bone_pos("Head", Vector3(0, 2.7, 1.3))


func beak_point() -> Vector3:
	return _bone_pos("Beak_Lower", Vector3(0, 2.6, 1.7))


func _bone_pos(bone: String, fallback: Vector3) -> Vector3:
	if skeleton and skeleton.find_bone(bone) >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	return pivot.global_transform * fallback


## Wingtip positions (world), for measurements and effects.
func wingtips() -> Array:
	return [_bone_pos("Prim9_L", Vector3(3, 1.8, 0.8)), _bone_pos("Prim9_R", Vector3(-3, 1.8, 0.8))]


func flash(strength := 1.0) -> void:
	_hurt = clampf(strength, 0.3, 1.0)


func look_at_point(p: Vector3, w := 1.0) -> void:
	if gaze:
		gaze.target = p
		gaze.weight = w


func set_mouth(amp: float) -> void:
	if gaze:
		gaze.mouth = clampf(amp, 0.0, 1.0)


## 0 = resting embers, 1 = blazing (casting / transformation).
func set_heat(h: float) -> void:
	heat_target = clampf(h, 0.0, 1.0)


func set_dissolve(p: float, origin: Vector3) -> void:
	for fm in [feather_mat, gold_mat, flame_mat]:
		(fm as ShaderMaterial).set_shader_parameter("dissolve", clampf(p, 0.0, 1.0))
		(fm as ShaderMaterial).set_shader_parameter("dissolve_origin", origin)
	for w in _wisps:
		w.emitting = p < 0.5 and visible
	if halo:
		halo.visible = p < 0.9
	for m in _solids:
		m.set_shader_parameter("dissolve", clampf(p, 0.0, 1.0))
		m.set_shader_parameter("dissolve_origin", origin)
	if _eyes:
		_eyes.visible = p < 0.55


func set_embers(rate: float) -> void:
	_ember_rate = clampf(rate, 0.0, 1.0)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	state_t += delta
	_heat = lerpf(_heat, heat_target, 1.0 - exp(-3.0 * delta))
	_bank = lerpf(_bank, bank, 1.0 - exp(-4.0 * delta))
	var bob := 0.0
	if state in ["fly", "glide", "hover", "bank_left", "bank_right"]:
		bob = 0.1 * sin(_t * 2.6)
	pivot.position.y = lerpf(pivot.position.y, hover + bob, 1.0 - exp(-5.0 * delta))
	pivot.rotation = Vector3(lerpf(pivot.rotation.x, pitch, 1.0 - exp(-6.0 * delta)), 0, _bank)
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	_aura = lerpf(_aura, aura_target, 1.0 - exp(-2.5 * delta))
	for fm in [feather_mat, gold_mat]:
		(fm as ShaderMaterial).set_shader_parameter("hurt", _hurt)
		(fm as ShaderMaterial).set_shader_parameter("heat", _heat)
		(fm as ShaderMaterial).set_shader_parameter("glow", _glow * (1.0 + 0.6 * _aura))
	flame_mat.set_shader_parameter("heat", _heat)
	flame_mat.set_shader_parameter("strength", 0.22 * (_glow / DAY_GLOW) * (1.0 + 1.6 * _aura))
	if halo_mat:
		halo_mat.set_shader_parameter("strength", 0.16 + 0.8 * _aura + 0.2 * _heat)
		halo_mat.set_shader_parameter("rays", _aura)
	for m in _solids:
		m.set_shader_parameter("heat", _heat)
		m.set_shader_parameter("hurt", _hurt)
	feather_mat.set_shader_parameter("flutter", 1.0 if state in ["fly", "glide", "hover", "bank_left", "bank_right", "takeoff", "land"] else 0.0)
	var want_emb := _ember_rate > 0.0 or _heat > 0.3 or state in ["fly", "takeoff", "cast_fire", "cast", "hover"]
	# flame wisps at the wingtips only while her fire is up (charging, transforming, flying)
	var want_wisp := _heat > 0.25 or _aura > 0.2 or state in ["fly", "takeoff", "hover", "glide", "bank_left", "bank_right"]
	for w in _wisps:
		w.emitting = want_wisp and visible
	for p in _embers:
		p.emitting = want_emb
	if chest_light:
		var e := (1.6 + 3.5 * _heat + 5.0 * _aura + 2.0 * _hurt) * float(RenderProfile.get_setting("magic_light_scale"))
		chest_light.light_energy = lerpf(chest_light.light_energy, e, 1.0 - exp(-8.0 * delta))
	if player and not player.is_playing() and state_t > 0.3:
		clip_done = state


func collapse() -> void:
	play("recover")
	await get_tree().create_timer(1.4).timeout
