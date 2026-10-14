class_name PhoenixHuman
extends WorldCharacter
## Oriel's HUMANOID FORM (visual pass 2). Her body is the developer's own Zahra (a desert dancer from the
## Character Lab, author: the developer), COPIED into the project at assets/characters/phoenix/
## Zahra_DesertDancer.vrm - the file is only read; its look is restyled at runtime to the Phoenix's colours
## (tools/textures/oriel_zahra_recolor.py): a deep crimson hood with gold edges, a flame veil, ivory-gold top,
## a gold collar, crimson pleats burning to ember at the hem, auburn-crimson hair, molten-gold eyes, ruby and
## fire-opal gems, an ember sash. Expressions, blinking, lip sync and the shared clip library are WorldCharacter's.
##
## Her TRANSFORMATION (a magical-girl sequence, original to her: after the classic structure - a body of light,
## then each part of her made in turn by ribbons, a spin, the crown last, a final pose):
##   * reveal materials: every surface gets a reveal variant of its own MToon shader (mtoon_reveal.gdshaderinc):
##     hair, crown (hood, veil, circlet), top, arms, skirt and legs materialise along their own sweeps with a
##     burning seam; a glow pass (reveal_glow.gdshader) makes her a silhouette of white-gold light that cools;
##   * flame ribbons (FlameRibbon) wind around each part as it is made; spark bursts when a part completes;
##   * phantom wings of flame open from her back for the final pose (the bird she was);
##   * authored choreography (PoseAuthor, solved on her skeleton): arms crossed over the heart, opening, hands
##     through the hair, a raised knee, a full spin, each arm, a hand to the brow, the final pose.
## The previous Luna-based body (tools/textures/oriel_recolor.py) and the procedural body stay in the repo.

const BASE_VRM := "res://assets/characters/phoenix/Zahra_DesertDancer.vrm"
const TEX_DIR := "res://assets/characters/phoenix/oriel_zahra_tex/"
## VRM material name (substring) -> [restyled texture or "", colour factor or null]
const RESTYLE := {
	"NC_Zahra_Hood": ["NC_Zahra_Hood", null], "NC_Zahra_Veil": ["NC_Zahra_Veil", null],
	"NC_Zahra_Top": ["NC_Zahra_Top", null], "NC_Zahra_Collar": ["NC_Zahra_Collar", null],
	"NC_Zahra_Skirt": ["NC_Zahra_Skirt", null], "NC_Zahra_Hair": ["NC_Zahra_Hair", null],
	"EyeIris": ["F00_000_00_EyeIris_00_EYE", null], "Body_00_SKIN": ["F00_002_02_Body_00_SKIN", null],
	"NC_Zahra_Tie": ["", Color(0.95, 0.4, 0.1)], "NC_BlueGem": ["", Color(0.8, 0.03, 0.05)],
	"NC_TealGem": ["", Color(1.0, 0.48, 0.05)], "NC_Gold": ["", Color(0.95, 0.66, 0.2)],
	"NC_Zahra_Sandal": ["", Color(0.4, 0.09, 0.05)],
}
## reveal group per material (substring); the rest of the outfit (gold, gems) is classified by body part
const GROUPS := {"NC_Zahra_Hair": 0, "NC_Zahra_Hood": 1, "NC_Zahra_Veil": 1, "NC_Zahra_Top": 2, "NC_Zahra_Tie": 2,
	"NC_Zahra_Collar": 2, "NC_Zahra_Skirt": 4, "NC_Zahra_Sandal": 5}
const SCALE := 1.09

var feather_mat: ShaderMaterial
var aura: GPUParticles3D
var aura_light: OmniLight3D
var _heat := 0.0
var heat_target := 0.0
var _ornaments: Array[Node3D] = []
var _iris_mats: Array[ShaderMaterial] = []
var _styled := {}                 # MeshInstance3D -> {surface: restyled material}
var _reveal := {}                 # MeshInstance3D -> {surface: reveal chain}
var _reveal_all: Array[ShaderMaterial] = []
var _glow_all: Array[ShaderMaterial] = []
var revealing := false
var wings: Node3D
var wing_mat: ShaderMaterial
var ribbons: Array[FlameRibbon] = []
var spin := 0.0                   # extra yaw of the avatar (her pirouette), radians
var lift := 0.0                   # the avatar floats this much (metres)
var pose_override := false        # true while a transformation drives lift / spin (never while she sits)
var _spark_mesh: QuadMesh
var _spark_pm: ParticleProcessMaterial


func _init() -> void:
	character_id = "phoenix"
	display_name = "Oriel"
	avatar_path = BASE_VRM
	walk_speed = 1.3
	run_speed = 3.6


func _ready() -> void:
	super()
	_dress()
	nav_agent.height = 1.8
	aura_light = FX.light(Color(1.0, 0.62, 0.28), 0.1 * float(RenderProfile.get_setting("magic_light_scale")), 2.4)
	aura_light.position = Vector3(0, 0.9, 0.0)
	add_child(aura_light)
	aura = FX.particles(14, 2.4, FX.process("phoenix_aura", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.35, 0.7, 0.3)
		pm.direction = Vector3.UP
		pm.spread = 25.0
		pm.initial_velocity_min = 0.12
		pm.initial_velocity_max = 0.3
		pm.gravity = Vector3(0, 0.25, 0)
		pm.damping_min = 0.2
		pm.damping_max = 0.5
		pm.scale_min = 0.3
		pm.scale_max = 0.6
		pm.color_ramp = FX.ramp([Color(1, 0.7, 0.3, 0), Color(1, 0.55, 0.15, 0.9), Color(0.9, 0.3, 0.05, 0.6), Color(0.4, 0.08, 0, 0)], [0.0, 0.2, 0.7, 1.0])), FX.mote_mesh(0.03))
	aura.position = Vector3(0, 0.9, 0)
	aura.emitting = true
	add_child(aura)
	for i in 4:
		var r := FlameRibbon.new()
		r.name = "Ribbon%d" % i
		add_child(r)
		ribbons.append(r)
	var atlas: Texture2D = load(PhoenixTrueRig.ATLAS)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/phoenix/fx_sprite.gdshader")
	sm.set_shader_parameter("atlas", atlas)
	sm.set_shader_parameter("noise_tex", FX.noise())
	sm.set_shader_parameter("cell", 1)
	sm.set_shader_parameter("strength", 3.5)
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.14, 0.14)
	_spark_mesh.material = sm
	_spark_pm = FX.process("oriel_tf_sparks", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.12
		pm.spread = 180.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 2.0
		pm.gravity = Vector3(0, 0.4, 0)
		pm.damping_min = 1.5
		pm.damping_max = 3.0
		pm.scale_min = 0.5
		pm.scale_max = 1.6
		pm.color_ramp = FX.ramp([Color(1, 0.95, 0.75, 1), Color(1, 0.7, 0.3, 0.9), Color(1, 0.4, 0.1, 0)], [0.0, 0.4, 1.0]))


var _dressed_once := false


## Runs again after an avatar swap (WorldCharacter rebuilds the rig); the first build is dressed by _ready.
func _build_rig(scene: PackedScene = null, instance: Node3D = null) -> void:
	super(scene, instance)
	if _dressed_once and is_inside_tree():
		_dress()


func _dress() -> void:
	_dressed_once = true
	avatar.scale = Vector3.ONE * SCALE
	feather_mat = ShaderMaterial.new()
	feather_mat.shader = load("res://shaders/phoenix/feather.gdshader")
	feather_mat.set_shader_parameter("atlas", load(PhoenixTrueRig.ATLAS))
	feather_mat.set_shader_parameter("noise_tex", FX.noise())
	feather_mat.set_shader_parameter("glow", 0.5)
	feather_mat.set_shader_parameter("flicker", 0.4)
	_iris_mats.clear()
	_styled.clear()
	_reveal.clear()
	_reveal_all.clear()
	_glow_all.clear()
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.has_meta("oriel_fx") or (wings and is_instance_valid(wings) and wings.is_ancestor_of(m)):
			continue
		var per := {}
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			if mat == null or not (mat is ShaderMaterial):
				continue
			var sm := mat as ShaderMaterial
			var key := _restyle_key(String(sm.resource_name))
			if key != "":
				sm = _restyled(sm, key)
				m.set_surface_override_material(si, sm)
			per[si] = sm
		_styled[m] = per
	_build_ornaments()
	_build_wings()
	_build_choreo()
	_light_balance = Vector2(-1, -1)      # the new materials need the light balance again


func _restyle_key(nm: String) -> String:
	for k in RESTYLE:
		if nm.contains(k):
			return k
	return ""


func _restyled(mat: ShaderMaterial, key: String) -> ShaderMaterial:
	var dup := mat.duplicate() as ShaderMaterial
	var spec: Array = RESTYLE[key]
	if String(spec[0]) != "":
		var path: String = TEX_DIR + String(spec[0]) + ".png"
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			dup.set_shader_parameter("_MainTex", tex)
			if dup.get_shader_parameter("_ShadeTexture") != null:
				dup.set_shader_parameter("_ShadeTexture", tex)
			if key == "EyeIris":
				dup.set_shader_parameter("_EmissionColor", Color(0.5, 0.3, 0.06))
				dup.set_shader_parameter("_EmissionMap", tex)
				_iris_mats.append(dup)
	if spec[1] != null:
		var c: Color = spec[1]
		dup.set_shader_parameter("_Color", c)
		dup.set_shader_parameter("_ShadeColor", c.darkened(0.4))
		if key.ends_with("Gem"):
			dup.set_shader_parameter("_EmissionColor", c * 0.35)
	return dup


## Small feather ornaments that tie her to the bird: a pair of crimson-and-gold plumes at the temples, sweeping
## back from under the hood (shared feather shader with her true form).
func _build_ornaments() -> void:
	for o in _ornaments:
		if is_instance_valid(o):
			o.queue_free()
	_ornaments.clear()
	# (v2's temple plumes read as antennae under Zahra's hood: her gold circlet and ruby carry the Phoenix now)


func _ornament(bone: String, mesh: ArrayMesh, offset: Vector3) -> void:
	if skeleton.find_bone(bone) < 0:
		return
	var at := BoneAttachment3D.new()
	at.bone_name = bone
	skeleton.add_child(at)
	var mi := MeshInstance3D.new()
	mi.set_meta("oriel_fx", true)
	mi.mesh = mesh
	mi.material_override = feather_mat
	mi.position = offset
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	at.add_child(mi)
	_ornaments.append(at)


## A feather card strip (atlas cell (cx, cy) of the 4 x 2 atlas), with the UV2 the feather shader reads.
static func _card(st: SurfaceTool, root: Vector3, dir: Vector3, side: Vector3, length: float, width: float, cell: Vector2i, cols: Array, droop := 0.12, segs := 4, glow := 0.6, seed := 0.0) -> void:
	var d := dir.normalized()
	var sd := side.normalized()
	var n := d.cross(sd).normalized()
	var prev := []
	for k in segs + 1:
		var s := float(k) / segs
		var p := root + d * (length * s) - n * (droop * length * s * s)
		var c: Color = (cols[0] as Color).lerp(cols[1], s)
		var row := []
		for u in [-1.0, 1.0]:
			var v: Vector3 = p + sd * (width * 0.5 * float(u) * (1.0 - 0.3 * s))
			# Godot UV of the atlas: x = (cx + u01) / 4, y = 1 - (cy + s) / 2
			row.append([v, Vector2((cell.x + (float(u) * 0.5 + 0.5)) * 0.25, 1.0 - (cell.y + s) * 0.5), c, Vector2(minf(s, 0.999) + seed, glow)])
		if k > 0:
			for tri in [[prev[0], prev[1], row[1]], [prev[0], row[1], row[0]]]:
				for vtx in tri:
					st.set_color(vtx[2])
					st.set_uv(vtx[1])
					st.set_uv2(vtx[3])
					st.set_normal(n)
					st.add_vertex(vtx[0])
		prev = row
	return


func _plume_mesh(sx: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var dir := Vector3(0.45 * sx, 0.8 - 0.16 * i, -0.5 - 0.1 * i)
		_card(st, Vector3(0, 0, -0.01 * i), dir, Vector3(0.0, 0.25, 1.0), 0.24 - 0.04 * i, 0.05, Vector2i(0, 1),
			[Color(0.55, 0.03, 0.04), Color(1.0, 0.72, 0.28)], -0.25, 5, 0.6, float(3 * i + (1 if sx > 0 else 7)))
	return st.commit()


# ------------------------------------------------------------------ phantom wings of flame
func _build_wings() -> void:
	if wings and is_instance_valid(wings):
		wings.queue_free()
	wings = Node3D.new()
	wings.name = "PhantomWings"
	avatar.add_child(wings)           # avatar space: she faces +Z, her left is +X
	wings.position = Vector3(0, 1.28, -0.12)
	wings.scale = Vector3.ONE * 0.001
	wings.visible = false
	wing_mat = ShaderMaterial.new()
	wing_mat.shader = load("res://shaders/phoenix/flame_card.gdshader")
	wing_mat.set_shader_parameter("atlas", load(PhoenixTrueRig.ATLAS))
	wing_mat.set_shader_parameter("noise_tex", FX.noise())
	wing_mat.set_shader_parameter("strength", 1.2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx in [1.0, -1.0]:
		for i in 9:
			var ang := deg_to_rad(10.0 + 11.0 * i)
			var dir := Vector3(sx * cos(ang), sin(ang), -0.35).normalized()
			var L := 1.0 + 0.7 * sin(PI * float(i) / 8.0)
			_card(st, Vector3(sx * 0.06, 0, 0), dir, Vector3(0, 0, 1).cross(dir), L, 0.42, Vector2i(3, 0),
				[Color(1.0, 0.7, 0.3), Color(0.95, 0.2, 0.05)], -0.1, 5, 1.0, float((i * 5 + (0 if sx > 0 else 3)) % 16))
	var mi := MeshInstance3D.new()
	mi.set_meta("oriel_fx", true)
	mi.mesh = st.commit()
	mi.material_override = wing_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wings.add_child(mi)


func set_wings(open: float, strength := 1.2) -> void:
	if wings == null:
		return
	wings.visible = open > 0.01
	wings.scale = Vector3.ONE * maxf(open, 0.001)
	wing_mat.set_shader_parameter("strength", strength)


# ------------------------------------------------------------------ the reveal (materials)
func _group_of(nm: String, m: MeshInstance3D) -> int:
	for k in GROUPS:
		if nm.contains(k):
			return int(GROUPS[k])
	var mn := String(m.name)
	if mn.contains("Body") or mn.contains("Face") or nm.contains("_SKIN") or nm.contains("_EYE") or nm.contains("_FACE"):
		return 6
	return -1


static var _reveal_shaders := {}


func _reveal_shader(orig: Shader) -> Shader:
	if orig == null:
		return null
	var key := orig.resource_path if orig.resource_path != "" else str(orig.get_instance_id())
	if _reveal_shaders.has(key):
		return _reveal_shaders[key]
	var code := orig.code
	if not code.contains("mtoon_common.gdshaderinc"):
		_reveal_shaders[key] = null
		return null
	var rx := RegEx.new()
	rx.compile("#include\\s+\"[^\"]*mtoon_common\\.gdshaderinc\"")
	code = rx.sub(code, "#include \"res://shaders/phoenix/mtoon_reveal.gdshaderinc\"")
	var sh := Shader.new()
	sh.code = code
	_reveal_shaders[key] = sh
	return sh


func _reveal_variant(base: ShaderMaterial, g: int) -> ShaderMaterial:
	var sh := _reveal_shader(base.shader)
	if sh == null:
		return null
	var r := base.duplicate() as ShaderMaterial
	r.shader = sh
	for u in base.shader.get_shader_uniform_list():
		r.set_shader_parameter(u.name, base.get_shader_parameter(u.name))
	r.set_shader_parameter("rv_on", 1.0)
	r.set_shader_parameter("rv_group", g)
	_reveal_all.append(r)
	return r


func _reveal_chain(base: ShaderMaterial, g: int) -> ShaderMaterial:
	var head: ShaderMaterial = null
	var tail: ShaderMaterial = null
	var cur: Material = base
	while cur is ShaderMaterial:
		var v := _reveal_variant(cur as ShaderMaterial, g)
		if v == null:
			break
		if head == null:
			head = v
		else:
			tail.next_pass = v
		tail = v
		cur = (cur as ShaderMaterial).next_pass
	if head == null:
		return null
	tail.next_pass = null
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/phoenix/reveal_glow.gdshader")
	gm.set_shader_parameter("rv_on", 1.0)
	gm.set_shader_parameter("rv_group", g)
	gm.set_shader_parameter("glow", 0.0)
	gm.set_shader_parameter("noise_tex", FX.noise())
	tail.next_pass = gm
	_glow_all.append(gm)
	_reveal_all.append(gm)
	return head


func _ensure_reveal() -> void:
	if not _reveal.is_empty():
		return
	for m in _styled:
		var per: Dictionary = _styled[m]
		var rv := {}
		for si in per:
			var base: ShaderMaterial = per[si]
			var chain := _reveal_chain(base, _group_of(String(base.resource_name), m))
			if chain:
				rv[si] = chain
		_reveal[m] = rv


## Switch every surface to its reveal chain (start of a transformation): nothing made yet but her body of light.
func begin_reveal(start := {}, glow := 1.0) -> void:
	_ensure_reveal()
	for m in _reveal:
		var mm := m as MeshInstance3D
		if not is_instance_valid(mm):
			continue
		for si in _reveal[m]:
			mm.set_surface_override_material(si, _reveal[m][si])
	revealing = true
	_light_balance = Vector2(-1, -1)
	_update_joints()
	set_reveal(start, glow)


## Progress per group (0 = unmade .. 1 = made): hair, crown, top, arms, skirt, legs, body; `glow` 1 = all light.
func set_reveal(p: Dictionary, glow: float) -> void:
	var p0 := Vector4(float(p.get("hair", 0.0)), float(p.get("crown", 0.0)), float(p.get("top", 0.0)), float(p.get("arms", 0.0)))
	var p1 := Vector4(float(p.get("skirt", 0.0)), float(p.get("legs", 0.0)), float(p.get("body", 1.0)), 0.0)
	for r in _reveal_all:
		r.set_shader_parameter("rv_p0", p0)
		r.set_shader_parameter("rv_p1", p1)
	for g in _glow_all:
		g.set_shader_parameter("glow", glow)


## Back to her finished, restyled materials (end of a transformation; no reveal cost in normal play).
func end_reveal() -> void:
	for m in _styled:
		var mm := m as MeshInstance3D
		if not is_instance_valid(mm):
			continue
		for si in _styled[m]:
			mm.set_surface_override_material(si, _styled[m][si])
	revealing = false
	_light_balance = Vector2(-1, -1)


func _bpos(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	if i < 0:
		return global_position + Vector3(0, 1.0, 0)
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin


func joints() -> Dictionary:
	var head := _bpos("Head")
	return {"head": head + Vector3(0, 0.08, 0), "chest": _bpos("UpperChest") if skeleton.find_bone("UpperChest") >= 0 else _bpos("Chest"),
		"hips": _bpos("Hips"), "lsh": _bpos("LeftUpperArm"), "lhand": _bpos("LeftHand"), "rsh": _bpos("RightUpperArm"), "rhand": _bpos("RightHand"),
		"lknee": _bpos("LeftLowerLeg"), "lfoot": _bpos("LeftFoot"), "rknee": _bpos("RightLowerLeg"), "rfoot": _bpos("RightFoot"),
		"lhip": _bpos("LeftUpperLeg"), "rhip": _bpos("RightUpperLeg"), "neck": _bpos("Neck")}


func _update_joints() -> void:
	var j := joints()
	for r in _reveal_all:
		r.set_shader_parameter("rv_head", j.head)
		r.set_shader_parameter("rv_chest", j.chest)
		r.set_shader_parameter("rv_hips", j.hips)
		r.set_shader_parameter("rv_lsh", j.lsh)
		r.set_shader_parameter("rv_lhand", j.lhand)
		r.set_shader_parameter("rv_rsh", j.rsh)
		r.set_shader_parameter("rv_rhand", j.rhand)
		r.set_shader_parameter("rv_lknee", j.lknee)
		r.set_shader_parameter("rv_lfoot", j.lfoot)
		r.set_shader_parameter("rv_rknee", j.rknee)
		r.set_shader_parameter("rv_rfoot", j.rfoot)


func spark_burst(at: Vector3, amount := 26) -> void:
	if get_parent() == null:
		return
	var p := FX.burst(get_parent(), at, amount, 0.9, _spark_pm, _spark_mesh)
	if p:
		p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))


# ------------------------------------------------------------------ choreography (PoseAuthor)
func _build_choreo() -> void:
	if skeleton == null or body_player == null:
		return
	var lib := AnimationLibrary.new()
	var path := String(avatar.get_path_to(skeleton))
	lib.add_animation("tf_cinematic", PoseAuthor.build(skeleton, path, _keys_cinematic(), 6.8))
	lib.add_animation("tf_short", PoseAuthor.build(skeleton, path, _keys_short(), 2.6))
	lib.add_animation("tf_reform", PoseAuthor.build(skeleton, path, _keys_reform(), 4.4))
	if body_player.has_animation_library("oriel"):
		body_player.remove_animation_library("oriel")
	body_player.add_animation_library("oriel", lib)


func play_choreo(clip: String, fade_in := 0.3, fade_out := 0.6) -> void:
	if not body_player.has_animation("oriel/" + clip):
		return
	var bt := anim_tree.tree_root as AnimationNodeBlendTree
	var shot := bt.get_node("cast") as AnimationNodeOneShot
	shot.fadein_time = fade_in
	shot.fadeout_time = fade_out
	bt.get_node("cast_anim").animation = "oriel/" + clip
	anim_tree.set("parameters/gesture_speed/scale", 1.0)
	anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func choreo_length(clip: String) -> float:
	return body_player.get_animation("oriel/" + clip).length if body_player.has_animation("oriel/" + clip) else 0.0


# Pose vocabulary (VRM skeleton space: +Y up, +Z the way she faces, +X her left).
static func _arms_down() -> Dictionary:
	return PoseAuthor.sym({"aim": {"LeftUpperArm": Vector3(0.22, -0.97, 0.04), "LeftLowerArm": Vector3(0.18, -0.95, 0.2), "LeftHand": Vector3(0.12, -0.96, 0.2)}})


static func _legs_stand() -> Dictionary:
	return PoseAuthor.sym({"aim": {"LeftUpperLeg": Vector3(0.04, -1.0, 0.02), "LeftLowerLeg": Vector3(0.02, -1.0, -0.05), "LeftFoot": Vector3(0.02, -0.5, 0.86)}})


static func _p(aims: Dictionary, turns := {}, mirror := true) -> Dictionary:
	var base := PoseAuthor.merge(_legs_stand(), {"aim": aims, "turn": turns})
	return PoseAuthor.sym(base) if mirror else base


func _keys_cinematic() -> Array:
	# arms crossed over the heart, head bowed (the light-body forms)
	var cross := PoseAuthor.merge(_legs_stand(), {"aim": {"LeftUpperArm": Vector3(0.3, -0.5, 0.81), "LeftLowerArm": Vector3(-0.86, 0.42, 0.28), "LeftHand": Vector3(-0.7, 0.6, 0.3),
		"RightUpperArm": Vector3(-0.3, -0.56, 0.77), "RightLowerArm": Vector3(0.86, 0.36, 0.36), "RightHand": Vector3(0.7, 0.55, 0.4)},
		"turn": {"Head": Vector3(14, 0, 0), "Neck": Vector3(6, 0, 0), "Spine": Vector3(4, 0, 0)}})
	# opening: arms flung wide and up, the chest lifted, face to the sky
	var open := _p({"LeftUpperArm": Vector3(0.78, 0.58, 0.18), "LeftLowerArm": Vector3(0.62, 0.77, 0.12), "LeftHand": Vector3(0.5, 0.85, 0.1)},
		{"Head": Vector3(-16, 0, 0), "Chest": Vector3(-7, 0, 0), "UpperChest": Vector3(-5, 0, 0)})
	# hands through her hair, head thrown back (the hair is made)
	var hair := _p({"LeftUpperArm": Vector3(0.62, 0.72, -0.3), "LeftLowerArm": Vector3(-0.5, 0.62, -0.6), "LeftHand": Vector3(-0.6, 0.3, -0.74)},
		{"Head": Vector3(-24, 12, 0), "Neck": Vector3(-6, 0, 0), "Spine": Vector3(-6, 0, 0)})
	# a raised knee, arms out to the sides, wrists lifted (the sandals are made, ribbons up her legs)
	var knee := PoseAuthor.merge(_p({"LeftUpperArm": Vector3(0.97, 0.2, 0.08), "LeftLowerArm": Vector3(0.95, 0.3, 0.08), "LeftHand": Vector3(0.9, 0.42, 0.1)},
		{"Head": Vector3(6, -10, 0), "Hips": Vector3(0, 0, -4)}), {"aim": {"LeftUpperLeg": Vector3(0.1, -0.25, 0.96), "LeftLowerLeg": Vector3(0.04, -0.96, 0.25), "LeftFoot": Vector3(0.02, -0.82, 0.55)}})
	# the pirouette: one arm curved over her head, the other curved before her waist
	var twirl := PoseAuthor.merge(_legs_stand(), {"aim": {"LeftUpperArm": Vector3(0.45, 0.88, 0.12), "LeftLowerArm": Vector3(-0.4, 0.88, 0.22), "LeftHand": Vector3(-0.7, 0.6, 0.3),
		"RightUpperArm": Vector3(-0.35, -0.62, 0.7), "RightLowerArm": Vector3(0.62, -0.12, 0.78), "RightHand": Vector3(0.8, 0.05, 0.6)},
		"turn": {"Head": Vector3(-4, 14, 6)}})
	# each arm offered in turn (the sleeves / bracelets are made)
	var arm_l := PoseAuthor.merge(_legs_stand(), {"aim": {"LeftUpperArm": Vector3(0.38, 0.42, 0.82), "LeftLowerArm": Vector3(0.32, 0.5, 0.8), "LeftHand": Vector3(0.3, 0.55, 0.78),
		"RightUpperArm": Vector3(-0.95, 0.12, 0.25), "RightLowerArm": Vector3(-0.94, 0.22, 0.22), "RightHand": Vector3(-0.9, 0.3, 0.2)}, "turn": {"Head": Vector3(-4, 22, 0), "Spine": Vector3(0, 8, 0)}})
	var arm_r := PoseAuthor.merge(_legs_stand(), {"aim": {"RightUpperArm": Vector3(-0.38, 0.42, 0.82), "RightLowerArm": Vector3(-0.32, 0.5, 0.8), "RightHand": Vector3(-0.3, 0.55, 0.78),
		"LeftUpperArm": Vector3(0.95, 0.12, 0.25), "LeftLowerArm": Vector3(0.94, 0.22, 0.22), "LeftHand": Vector3(0.9, 0.3, 0.2)}, "turn": {"Head": Vector3(-4, -22, 0), "Spine": Vector3(0, -8, 0)}})
	# a hand to the brow (the circlet and the hood are made)
	var crown := PoseAuthor.merge(_legs_stand(), {"aim": {"RightUpperArm": Vector3(-0.55, 0.12, 0.83), "RightLowerArm": Vector3(0.62, 0.72, 0.3), "RightHand": Vector3(0.5, 0.85, 0.15),
		"LeftUpperArm": Vector3(0.42, -0.88, 0.2), "LeftLowerArm": Vector3(0.45, -0.82, 0.35), "LeftHand": Vector3(0.45, -0.8, 0.4)}, "turn": {"Head": Vector3(6, -10, 0)}})
	# the final pose: a hand on her hip, the other raised high, weight on one leg, head tilted - a smile
	var final := {"aim": {"LeftUpperArm": Vector3(0.62, -0.62, -0.48), "LeftLowerArm": Vector3(-0.5, -0.4, 0.77), "LeftHand": Vector3(-0.6, -0.3, 0.74),
		"RightUpperArm": Vector3(-0.42, 0.88, 0.2), "RightLowerArm": Vector3(-0.28, 0.94, 0.2), "RightHand": Vector3(-0.2, 0.96, 0.18),
		"LeftUpperLeg": Vector3(0.1, -0.99, 0.05), "LeftLowerLeg": Vector3(0.06, -1.0, -0.04), "LeftFoot": Vector3(0.1, -0.5, 0.86),
		"RightUpperLeg": Vector3(-0.02, -0.96, 0.27), "RightLowerLeg": Vector3(-0.04, -0.97, -0.2), "RightFoot": Vector3(-0.06, -0.62, 0.78)},
		"turn": {"Hips": Vector3(0, 8, 6), "Spine": Vector3(0, -4, -5), "Chest": Vector3(-4, 0, -2), "Head": Vector3(2, -8, 10)}}
	return [[0.0, cross], [0.7, cross], [1.25, open], [1.9, hair], [2.5, knee], [2.9, twirl], [3.7, twirl], [4.05, arm_l], [4.45, arm_r],
		[5.0, crown], [5.5, crown], [6.0, final], [6.8, final]]


func _keys_short() -> Array:
	var open := _p({"LeftUpperArm": Vector3(0.78, 0.58, 0.18), "LeftLowerArm": Vector3(0.62, 0.77, 0.12), "LeftHand": Vector3(0.5, 0.85, 0.1)},
		{"Head": Vector3(-14, 0, 0), "Chest": Vector3(-6, 0, 0)})
	var settle := _p({"LeftUpperArm": Vector3(0.45, -0.88, 0.12), "LeftLowerArm": Vector3(0.4, -0.85, 0.35), "LeftHand": Vector3(0.35, -0.85, 0.4)}, {"Head": Vector3(4, 0, 0)})
	return [[0.0, open], [1.0, open], [1.9, settle], [2.6, settle]]


func _keys_reform() -> Array:
	var gather := PoseAuthor.merge(_legs_stand(), {"aim": {"LeftUpperArm": Vector3(0.3, -0.5, 0.81), "LeftLowerArm": Vector3(-0.86, 0.42, 0.28), "LeftHand": Vector3(-0.7, 0.6, 0.3),
		"RightUpperArm": Vector3(-0.3, -0.56, 0.77), "RightLowerArm": Vector3(0.86, 0.36, 0.36), "RightHand": Vector3(0.7, 0.55, 0.4)},
		"turn": {"Head": Vector3(16, 0, 0), "Spine": Vector3(6, 0, 0)}})
	var rise := _p({"LeftUpperArm": Vector3(0.3, 0.95, 0.05), "LeftLowerArm": Vector3(0.18, 0.98, 0.05), "LeftHand": Vector3(0.1, 0.99, 0.05)}, {"Head": Vector3(-20, 0, 0), "Chest": Vector3(-8, 0, 0)})
	var wings_open := _p({"LeftUpperArm": Vector3(0.9, 0.42, -0.12), "LeftLowerArm": Vector3(0.82, 0.55, -0.15), "LeftHand": Vector3(0.75, 0.62, -0.15)}, {"Head": Vector3(-26, 0, 0), "Chest": Vector3(-10, 0, 0)})
	return [[0.0, gather], [1.2, gather], [2.2, rise], [3.2, wings_open], [4.4, wings_open]]


# ------------------------------------------------------------------ light, heat, life
## Her skin and hair are light-balanced like the mages' (a slightly lower key: she should read warm, not white).
func apply_light_balance(sun_energy: float, ambient_energy: float) -> void:
	super(sun_energy * 1.45, ambient_energy * 1.3)


func set_heat(h: float) -> void:
	heat_target = clampf(h, 0.0, 1.0)


var _lb := 0.0


func _process(delta: float) -> void:
	super(delta)
	_lb -= delta
	if _lb <= 0.0 and world and world.get("sun") and world.get("world_env"):
		_lb = 1.0
		var sun: DirectionalLight3D = world.get("sun")
		apply_light_balance(sun.light_energy if sun.visible else 0.0, (world.get("world_env") as WorldEnvironment).environment.ambient_light_energy)
	_heat = lerpf(_heat, heat_target, 1.0 - exp(-3.0 * delta))
	if feather_mat:
		feather_mat.set_shader_parameter("heat", _heat)
	for m in _iris_mats:
		m.set_shader_parameter("_EmissionMultiplier", 1.0 + 3.0 * _heat)
	if aura_light:
		aura_light.light_energy = (0.1 + 2.5 * _heat) * float(RenderProfile.get_setting("magic_light_scale"))
	if avatar and pose_override:
		avatar.position.y = lift
		avatar.rotation.y = PI + spin
	if revealing:
		_update_joints()
	for r in ribbons:
		r.rebuild()


## Kept for the callers of the previous body: 0 = whole, 1 = gone (her feather ornaments burn; the avatar hides
## when nothing of her is made). The transformation itself uses begin_reveal / set_reveal.
func set_dissolve(p: float, origin: Vector3) -> void:
	if feather_mat:
		feather_mat.set_shader_parameter("dissolve", clampf(p, 0.0, 1.0))
		feather_mat.set_shader_parameter("dissolve_origin", origin)
	if avatar:
		avatar.visible = p < 0.6 or revealing


func head_point() -> Vector3:
	if skeleton and skeleton.find_bone("Head") >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin + Vector3(0, 0.08, 0)
	return global_position + Vector3(0, 1.6, 0)


func chest_point() -> Vector3:
	return global_position + Vector3(0, 1.25, 0)


# ------------------------------------------------------------------ the transformation timelines (her side)
## Phoenix -> woman, cinematic (seconds after the swap): the light-body, then each part made in turn.
const TL_CINE := {"hair": [0.15, 1.0], "legs": [1.5, 2.3], "skirt": [2.35, 3.4], "arms": [3.75, 4.6], "top": [4.25, 5.0], "crown": [5.0, 5.6]}
const TL_SHORT := {"hair": [0.1, 0.8], "legs": [0.3, 1.0], "skirt": [0.4, 1.2], "arms": [0.5, 1.3], "top": [0.6, 1.3], "crown": [0.9, 1.4]}
## woman -> Phoenix (before the swap): unmade in reverse, the crown first, the hair last
const TL_REFORM := {"crown": [0.6, 1.2], "arms": [1.1, 1.8], "top": [1.4, 2.1], "skirt": [1.8, 2.6], "legs": [2.3, 3.0], "hair": [2.7, 3.4]}
const TF_LEN := {"cinematic": 6.8, "short": 2.6, "reform": 4.2}

var tf_mode := ""
var _tf_fired := {}


## Before the swap: draw her with every reveal shader but nothing made (fully invisible), so the reveal shader
## variants compile while the bird is still on screen - no hitch when the light-body appears.
func tf_prepare() -> void:
	if aura:
		aura.emitting = false
	visible = true
	if avatar:
		avatar.visible = true
	begin_reveal({"body": 0.0}, 0.0)
	set_reveal({"body": 0.0}, 0.0)


func tf_begin(mode: String) -> void:
	if aura:
		aura.emitting = true
	tf_mode = mode
	_tf_fired.clear()
	pose_override = true
	lift = 0.0
	spin = 0.0
	visible = true
	if avatar:
		avatar.visible = true
	if mode == "reform":
		begin_reveal({"hair": 1.0, "crown": 1.0, "top": 1.0, "arms": 1.0, "skirt": 1.0, "legs": 1.0, "body": 1.0}, 0.0)
		play_choreo("tf_reform", 0.3, 0.3)
	else:
		begin_reveal({"body": 1.0}, 1.0)
		play_choreo("tf_cinematic" if mode == "cinematic" else "tf_short", 0.12, 0.7)
	set_heat(1.0)


func tf_step(u: float) -> void:
	match tf_mode:
		"cinematic":
			_tf_make(u, TL_CINE, 1.0 - smoothstep(0.9, 6.0, u))
			lift = 0.38 * smoothstep(0.0, 0.7, u) * (1.0 - smoothstep(5.3, 6.2, u))
			spin = TAU * _ease((u - 2.35) / 1.25)
			set_wings(smoothstep(5.4, 5.95, u) * (1.0 + 0.04 * sin(u * 9.0)), 1.5 * (1.0 - smoothstep(6.15, 6.8, u)))
			if u > 5.9 and not _tf_fired.has("smile"):
				_tf_fired["smile"] = true
				set_expression("happy", 0.55)
		"short":
			_tf_make(u, TL_SHORT, 1.0 - smoothstep(0.3, 1.9, u))
			set_wings(0.75 * smoothstep(1.0, 1.4, u), 1.3 * (1.0 - smoothstep(1.7, 2.4, u)))
		"reform":
			var prog := {"body": 1.0}
			for g in TL_REFORM:
				var r: Array = TL_REFORM[g]
				prog[g] = 1.0 - smoothstep(float(r[0]), float(r[1]), u)
			set_reveal(prog, smoothstep(0.4, 2.8, u))
			lift = 0.45 * smoothstep(1.0, 2.6, u)
			spin = TAU * _ease((u - 1.6) / 1.6)
			set_wings(1.5 * smoothstep(2.4, 3.6, u), 1.0 + 1.6 * smoothstep(3.0, 4.0, u))
			var j := joints()
			var feet: Vector3 = (j.lfoot + j.rfoot) * 0.5
			_ribbon(0, feet - Vector3(0, 0.05, 0), j.head + Vector3(0, 0.35, 0), smoothstep(0.8, 3.6, u), 0.5, 4.0, 0.12, u)
			_ribbon(1, feet - Vector3(0, 0.05, 0), j.head + Vector3(0, 0.35, 0), smoothstep(1.4, 3.9, u), 0.62, 3.0, 0.1, u + 1.7)
			for i in [2, 3]:
				ribbons[i].fade = 0.0


func tf_end() -> void:
	end_reveal()
	set_reveal({"hair": 1.0, "crown": 1.0, "top": 1.0, "arms": 1.0, "skirt": 1.0, "legs": 1.0, "body": 1.0}, 0.0)
	pose_override = false
	lift = 0.0
	spin = 0.0
	if avatar:
		avatar.position.y = 0.0
		avatar.rotation.y = PI
	set_wings(0.0)
	for r in ribbons:
		r.fade = 0.0
		r.head = 0.0
	tf_mode = ""


static func _ease(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)         # smootherstep: a pirouette that eases in and out


## The making: progress per group from its window, glow, ribbons on the part being made, a burst when done.
func _tf_make(u: float, tl: Dictionary, glow: float) -> void:
	var prog := {"body": 1.0}
	for g in tl:
		var r: Array = tl[g]
		prog[g] = smoothstep(float(r[0]), float(r[1]), u)
	set_reveal(prog, glow)
	var j := joints()
	var up := Vector3.UP
	var w: Dictionary = {}
	for g in tl:
		var r: Array = tl[g]
		w[g] = clampf((u - float(r[0])) / maxf(float(r[1]) - float(r[0]), 0.01), 0.0, 1.0)
	# slot 0: the hair, then the bodice; slots 1/2: the legs, then the arms; slot 3: the skirt, then the crown
	if u < (tl.top[0] as float):
		_ribbon(0, j.head + up * 0.24, j.neck - up * 0.08, w.hair, 0.19, 2.0, 0.09, u)
	else:
		_ribbon(0, j.hips, j.neck, w.top, 0.23, 2.5, 0.1, u)
	if u < (tl.arms[0] as float):
		_ribbon(1, j.lfoot, j.lhip, w.legs, 0.12, 3.0, 0.08, u)
		_ribbon(2, j.rfoot, j.rhip, w.legs, 0.12, 3.0, 0.08, u + 1.3)
	else:
		_ribbon(1, j.lsh, j.lhand, w.arms, 0.1, 3.0, 0.07, u)
		_ribbon(2, j.rsh, j.rhand, w.arms, 0.1, 3.0, 0.07, u + 1.3)
	if u < (tl.crown[0] as float):
		_ribbon(3, j.hips + up * 0.05, (j.lknee + j.rknee) * 0.5 - up * 0.12, w.skirt, 0.36, 2.5, 0.14, u)
	else:
		_ribbon(3, j.head + up * 0.18, j.head - up * 0.06, w.crown, 0.19, 1.5, 0.08, u)
	var spots := {"hair": j.head + up * 0.1, "legs": (j.lfoot + j.rfoot) * 0.5, "skirt": j.hips - up * 0.25, "arms": j.lhand, "top": j.chest, "crown": j.head + Vector3(0, 0.02, 0)}
	for g in tl:
		if float(prog[g]) >= 0.98 and not _tf_fired.has(g):
			_tf_fired[g] = true
			spark_burst(spots[g], 30)
			if g == "arms":
				spark_burst(j.rhand, 22)
			if g == "crown":
				spark_burst(spots[g] + Vector3(0, 0.05, 0), 40)


func _ribbon(i: int, a: Vector3, b: Vector3, prog: float, radius: float, turns: float, width: float, ph: float) -> void:
	if i >= ribbons.size():
		return
	var r := ribbons[i]
	r.a = a
	r.b = b
	r.head = prog
	r.radius = radius
	r.turns = turns
	r.width = width
	r.phase = ph * 2.2
	r.fade = smoothstep(0.0, 0.06, prog) * (1.0 - smoothstep(0.93, 1.0, prog))
