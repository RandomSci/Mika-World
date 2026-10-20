extends Node3D
## MIKA L1 CLOSE-UP LAB (Selwyn 2026-10-20: "her L1 dress looks bad in close ups while her face and hair look clean
## anime"). Test only, own files, nothing shared changes: Mika in her L1 outfit (the game's own WorldCharacter set-up)
## under the avatar lab's Whispering Woods light, without loading the world. Every change applies at runtime to her
## outfit surfaces or this run's viewport, one option at a time, so each can be judged on its own.
##   godot --path . res://scenes/tests/mika_l1_closeup_lab.tscn -- --save-path=user://test_regress_l1lab.json
##     --live-link=ws://127.0.0.1:9/test-none --no-bridge --l1out=<abs dir> [options]
##   --l1probe         list every outfit surface's shader, textures and settings, and the face's
##   --l1mat=strip     outfit keeps only the base colour under her face's MToon setup (no normal, matcap, rim texture,
##                     emission or extra maps; the face's shading shift, toony, GI and rim values)
##   --l1tex=<dir>     outfit base colours from <dir>/<L1_Piece_BaseColor>.png (cleaned or upscaled textures); the
##                     hair too when the dir holds L1_Hair_BaseColor.png
##   --l1hq            those textures BPTC compressed (Godot's high quality VRAM compression), else uncompressed
##   --l1aa=msaa4|taa  anti-aliasing (baseline is the stream's MSAA 2x, no TAA)
##   --l1aniso         16x anisotropic filtering on the outfit (MToon's samplers otherwise never ask for it)
##   --l1outline       inverted hull outlines on every outfit surface, the face's width mode and width
##   --l1grade         a softer colour grade (lower contrast and saturation, a touch darker, the AgX tonemap kept)
##   --l1alphaaa       alpha to coverage (alpha antialiasing) on the hair and cloth cutouts, with MSAA 4x
##   --l1skin=s,t[,r,g,b]  body skin: MToon shade shift s and toony t (game: -0.55, 0.88), shade colour r,g,b (default
##                     the face's)
## Shots: chest_sleeves, side, folded_arm, front, back_neck (Selwyn's five close-ups) and medium.

const MTOON_INC := "res://addons/Godot-MToon-Shader/mtoon_common.gdshaderinc"
const OUTLINE := "res://addons/Godot-MToon-Shader/mtoon_outline.gdshader"
const STRIP_KEYS := ["_BumpMap", "_SphereAdd", "_RimTexture", "_EmissionMap", "_ShadingGradeTexture", "_ReceiveShadowTexture", "_UvAnimMaskTexture"]
const FACE_LOOK := ["_ShadeShift", "_ShadeToony", "_IndirectLightIntensity", "_RimLightingMix", "_RimFresnelPower", "_RimLift", "_LightColorAttenuation"]

var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var o: Dictionary
var out := ""


func _ready() -> void:
	o = RenderProfile.options
	out = String(o.get("l1out", ProjectSettings.globalize_path("res://screenshots/l1lab")))
	DirAccess.make_dir_recursive_absolute(out)
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := PanoramaSkyMaterial.new()
	psm.panorama = load("res://assets/polyhaven/hdris/nature_reserve_forest/nature_reserve_forest_2k.hdr")
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.88
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, 150, 0)
	sun.light_energy = 3.1
	sun.light_color = Color(1, 0.9, 0.74)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	floor_mi.material_override = RealKit.stone_mat("mossy_stone_wall", false)
	add_child(floor_mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	Progression.load_data()
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	var st: Dictionary = AppearanceRegistry.stage_by_id("mika", "celestial_l1outfit")
	var mika := WorldCharacter.new()
	mika.name = "Mika"
	mika.character_id = "mika"
	mika.display_name = "Mika"
	mika.avatar_path = String(st.avatar)
	add_child(mika)
	mika.global_position = Vector3.ZERO
	mika.apply_light_balance(sun.light_energy, env.ambient_light_energy)
	await _wait(2.0)
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	vp.msaa_3d = Viewport.MSAA_2X
	vp.use_taa = false
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X        # what the stream profile sets
	match String(o.get("l1aa", "")):
		"msaa4": vp.msaa_3d = Viewport.MSAA_4X
		"taa":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.use_taa = true
	var face := _face_material(mika)
	var surfaces := _outfit_surfaces(mika)
	if o.has("l1probe"):
		_probe(surfaces, face)
	if String(o.get("l1mat", "")) == "strip":
		for s in surfaces:
			_strip(s, face)
	if o.has("l1tex"):
		var dir := String(o.l1tex)
		_retexture(surfaces + (_outfit_surfaces(mika, true) if FileAccess.file_exists(dir + "/L1_Hair_BaseColor.png") else []), dir, o.has("l1hq"))
	if o.has("l1alphaaa"):
		vp.msaa_3d = Viewport.MSAA_4X
		_alpha_aa(_outfit_surfaces(mika) + _outfit_surfaces(mika, true))
	if o.has("l1skin"):
		_skin(mika, face, String(o.l1skin))
	if o.has("l1aniso"):
		vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
		_anisotropic(surfaces)
	if o.has("l1outline"):
		_outline(surfaces, face)
	if o.has("l1grade"):
		env.adjustment_enabled = true                              # the game's AgX stays; less contrast and saturation
		env.adjustment_contrast = 0.9
		env.adjustment_saturation = 0.92
		env.adjustment_brightness = 0.97
	print("[l1] viewport msaa=%d taa=%s aniso=%d outfit surfaces=%d" % [vp.msaa_3d, vp.use_taa, vp.anisotropic_filtering_level, surfaces.size()])
	await _shots(mika)
	print("[l1] DONE")
	get_tree().quit()


func _face_material(c: WorldCharacter) -> ShaderMaterial:
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in (m.mesh.get_surface_count() if m.mesh else 0):
			var mat := m.get_active_material(si)
			if mat is ShaderMaterial and String(mat.resource_name).contains("Face_00_SKIN"):
				return mat
	return null


## [mesh instance, surface index, material] for every L1 outfit surface except the hair (or only the hair).
func _outfit_surfaces(c: WorldCharacter, hair := false) -> Array:
	var res := []
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in (m.mesh.get_surface_count() if m.mesh else 0):
			var mat := m.get_active_material(si)
			var nm := String(mat.resource_name) if mat else ""
			if nm.begins_with("L1_") and nm.begins_with("L1_Hair_") == hair:
				res.append([m, si, mat])
	return res


func _set_mat(s: Array, mat: Material) -> void:
	(s[0] as MeshInstance3D).set_surface_override_material(s[1], mat)
	s[2] = mat


func _probe(surfaces: Array, face: ShaderMaterial) -> void:
	var all := surfaces.duplicate()
	if face:
		all.append([null, -1, face])
	for s in all:
		var mat: Material = s[2]
		var depth := 0
		while mat and depth < 3:
			var line := "[l1probe] %s pass%d %s" % [String(s[2].resource_name), depth, mat.get_class()]
			if mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				line += " shader=%s" % (String(sm.shader.resource_path).get_file() if sm.shader else "?")
				var tex := []
				var vals := []
				for u in (sm.shader.get_shader_uniform_list(true) if sm.shader else []):
					var v = sm.get_shader_parameter(u.name)
					if v is Texture2D:
						var img := (v as Texture2D).get_image()
						tex.append("%s=%dx%d fmt%s mips=%s" % [u.name, v.get_width(), v.get_height(), str(img.get_format()) if img else "?", str(img.has_mipmaps()) if img else "?"])
					elif v != null and String(u.name) in FACE_LOOK + ["_BumpScale", "_OutlineWidth", "_OutlineWidthMode", "_OutlineColor", "_ShadeColor", "_Color", "_MatcapColor", "_RimColor", "_EmissionColor", "_AlphaCutoutEnable"]:
						vals.append("%s=%s" % [u.name, str(v)])
				line += " tex[%s] vals[%s]" % [", ".join(tex), ", ".join(vals)]
			elif mat is BaseMaterial3D:
				var b := mat as BaseMaterial3D
				line += " metallic=%.2f rough=%.2f normal=%s" % [b.metallic, b.roughness, str(b.normal_enabled)]
			print(line)
			mat = mat.next_pass
			depth += 1


## Base colour only, under the face's MToon lighting setup.
func _strip(s: Array, face: ShaderMaterial) -> void:
	var sm := (s[2] as ShaderMaterial).duplicate() as ShaderMaterial
	for k in STRIP_KEYS:
		sm.set_shader_parameter(k, null)
	sm.set_shader_parameter("_BumpScale", 0.0)
	sm.set_shader_parameter("_EmissionColor", Color.BLACK)
	sm.set_shader_parameter("_MatcapColor", Color.BLACK)
	sm.set_shader_parameter("_RimColor", Color.BLACK)
	if face:
		for k in FACE_LOOK:
			var v = face.get_shader_parameter(k)
			if v != null:
				sm.set_shader_parameter(k, v)
	_set_mat(s, sm)


func _retexture(surfaces: Array, dir: String, hq: bool) -> void:
	var cache := {}
	for s in surfaces:
		var p := "%s/%s.png" % [dir, String(s[2].resource_name).replace("_MToon", "_BaseColor")]
		if not cache.has(p):
			var img := Image.load_from_file(p)
			if img == null:
				push_error("[l1] no texture " + p)
				continue
			img.generate_mipmaps()
			if hq:
				img.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_SRGB)
			cache[p] = ImageTexture.create_from_image(img)
			print("[l1] texture %s %dx%d format=%d" % [p.get_file(), img.get_width(), img.get_height(), img.get_format()])
		var sm := (s[2] as ShaderMaterial).duplicate() as ShaderMaterial
		sm.set_shader_parameter("_MainTex", cache[p])
		sm.set_shader_parameter("_ShadeTexture", cache[p])
		_set_mat(s, sm)


## A runtime copy of the MToon shader whose colour samplers ask for anisotropic filtering (the shipped include
## declares them without a filter hint, so the viewport's anisotropy never reached her clothes).
func _anisotropic(surfaces: Array) -> void:
	var shaders := {}
	for s in surfaces:
		var sm := (s[2] as ShaderMaterial).duplicate() as ShaderMaterial
		var src: Shader = sm.shader
		if not shaders.has(src):
			var inc := FileAccess.get_file_as_string(MTOON_INC)
			for u in ["_MainTex", "_ShadeTexture"]:
				inc = inc.replace("uniform sampler2D %s : source_color, hint_default_white;" % u, "uniform sampler2D %s : source_color, hint_default_white, filter_linear_mipmap_anisotropic;" % u)
			var lines := PackedStringArray()
			for ln in src.code.split("\n"):
				lines.append(inc if ln.begins_with("#include") and ln.contains("mtoon_common") else ln)
			var sh := Shader.new()
			sh.code = "\n".join(lines)
			shaders[src] = sh
		sm.shader = shaders[src]
		_set_mat(s, sm)


## Alpha to coverage on the cutout surfaces: a runtime copy of the cutout shader that hands alpha to the scissor and
## antialiasing edge instead of discarding (needs MSAA).
func _alpha_aa(surfaces: Array) -> void:
	var shaders := {}
	var n := 0
	for s in surfaces:
		var sm := (s[2] as ShaderMaterial).duplicate() as ShaderMaterial
		var src: Shader = sm.shader
		if not String(src.resource_path).contains("cutout"):
			continue
		if not shaders.has(src):
			var inc := FileAccess.get_file_as_string(MTOON_INC).replace("if (_AlphaCutoutEnable > 0.5 && alpha < _Cutoff) { discard; }",
				"ALPHA = alpha; ALPHA_SCISSOR_THRESHOLD = _Cutoff; ALPHA_ANTIALIASING_EDGE = _Cutoff; ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(_MainTex, 0));")
			var lines := PackedStringArray()
			for ln in src.code.split("\n"):
				if ln.begins_with("render_mode"):
					ln = ln.replace(";", ", depth_draw_always;")       # writing ALPHA must not drop the cloth from the depth pass
				lines.append(inc if ln.begins_with("#include") and ln.contains("mtoon_common") else ln)
			var sh := Shader.new()
			sh.code = "\n".join(lines)
			shaders[src] = sh
		sm.shader = shaders[src]
		_set_mat(s, sm)
		n += 1
	print("[l1] alpha to coverage on %d cutout surfaces" % n)


## Body skin: soft shading like her face (the face's shade colour, a later shade threshold, a softer edge).
func _skin(c: WorldCharacter, face: ShaderMaterial, spec: String) -> void:
	var v := spec.split(",")
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in (m.mesh.get_surface_count() if m.mesh else 0):
			var mat := m.get_active_material(si)
			if not (mat is ShaderMaterial and String(mat.resource_name).ends_with("_Body_00_SKIN")):
				continue
			var sm := (mat as ShaderMaterial).duplicate() as ShaderMaterial
			print("[l1] skin before shift=%s toony=%s shade=%s color=%s" % [str(sm.get_shader_parameter("_ShadeShift")), str(sm.get_shader_parameter("_ShadeToony")), str(sm.get_shader_parameter("_ShadeColor")), str(sm.get_shader_parameter("_Color"))])
			sm.set_shader_parameter("_ShadeShift", float(v[0]))
			sm.set_shader_parameter("_ShadeToony", float(v[1]))
			if v.size() >= 5:
				sm.set_shader_parameter("_ShadeColor", Color(float(v[2]), float(v[3]), float(v[4])))
			elif face:
				sm.set_shader_parameter("_ShadeColor", face.get_shader_parameter("_ShadeColor"))
			m.set_surface_override_material(si, sm)


## Inverted hull outlines on every outfit surface, the face's width mode and width, the outfit's own dark navy.
func _outline(surfaces: Array, face: ShaderMaterial) -> void:
	var fo: ShaderMaterial = (face.next_pass as ShaderMaterial) if face else null
	for s in surfaces:
		var sm := (s[2] as ShaderMaterial).duplicate() as ShaderMaterial
		var op: ShaderMaterial
		if sm.next_pass is ShaderMaterial:
			op = (sm.next_pass as ShaderMaterial).duplicate() as ShaderMaterial
		else:
			op = ShaderMaterial.new()
			op.shader = load(OUTLINE)
			for u in sm.shader.get_shader_uniform_list(true):
				var v = sm.get_shader_parameter(u.name)
				if v != null:
					op.set_shader_parameter(u.name, v)
		if fo:
			for k in ["_OutlineWidthMode", "_OutlineWidth", "_OutlineScaledMaxDistance", "_OutlineColorMode", "_OutlineLightingMix", "_OutlineWidthTexture"]:
				var v = fo.get_shader_parameter(k)
				op.set_shader_parameter(k, v if k != "_OutlineWidthTexture" else null)
		op.set_shader_parameter("_OutlineColor", Color(0.12, 0.11, 0.24))
		sm.next_pass = op
		_set_mat(s, sm)
	print("[l1] outlines: face mode=%s width=%s" % [str(fo.get_shader_parameter("_OutlineWidthMode")) if fo else "-", str(fo.get_shader_parameter("_OutlineWidth")) if fo else "-"])


## Arm poses by aiming each bone at a direction in her own frame (right, up, forward), every frame after the animation.
class ArmPose extends Node:
	var c: WorldCharacter
	var aims := {}
	const CHILD := {"UpperArm": "LowerArm", "LowerArm": "Hand", "Hand": "MiddleProximal"}

	func _init() -> void:
		process_priority = (1 << 30) - 1

	func _process(_d: float) -> void:
		var sk := c.skeleton
		var right := _right(sk)
		var fwd := Vector3.UP.cross(right)
		for b: String in ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]:
			if not aims.has(b):
				continue
			var a: Vector3 = aims[b]
			var want := (right * a.x + Vector3.UP * a.y + fwd * a.z).normalized()
			var side := "Left" if b.begins_with("Left") else "Right"
			var part := b.trim_prefix(side)
			var i := sk.find_bone(b)
			var ch := sk.find_bone(side + String(CHILD[part]))
			if i < 0 or ch < 0:
				continue
			var g := sk.global_transform * sk.get_bone_global_pose(i)
			var have := ((sk.global_transform * sk.get_bone_global_pose(ch)).origin - g.origin).normalized()
			var ng := Basis(Quaternion(have, want)) * g.basis
			var pg := (sk.global_transform * sk.get_bone_global_pose(sk.get_bone_parent(i))).basis
			sk.set_bone_pose_rotation(i, (pg.inverse() * ng).orthonormalized().get_rotation_quaternion())

	static func _right(sk: Skeleton3D) -> Vector3:
		var ls := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftUpperArm"))).origin
		var rs := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperArm"))).origin
		return Vector3(rs.x - ls.x, 0, rs.z - ls.z).normalized()


func _bone(sk: Skeleton3D, n: String) -> Vector3:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n))).origin


func _shots(mika: WorldCharacter) -> void:
	var arms := ArmPose.new()
	arms.c = mika
	add_child(arms)
	# hands up, palms out, in front of the chest (Selwyn's front / chest shots)
	var up := {"LeftUpperArm": Vector3(-0.35, -0.55, 0.6), "LeftLowerArm": Vector3(0.1, 0.85, 0.35), "LeftHand": Vector3(0.0, 1.0, 0.1),
		"RightUpperArm": Vector3(0.35, -0.55, 0.6), "RightLowerArm": Vector3(-0.1, 0.85, 0.35), "RightHand": Vector3(0.0, 1.0, 0.1)}
	# right forearm folded across the waist (the folded-arm shot)
	var fold := up.duplicate()
	fold["RightUpperArm"] = Vector3(0.15, -0.92, 0.3)
	fold["RightLowerArm"] = Vector3(-0.85, 0.05, 0.45)
	fold["RightHand"] = Vector3(-1.0, 0.0, 0.2)
	var sk := mika.skeleton
	# [name, pose, aim bone, camera offset (right, up, forward), look offset (right, up, forward), fov]
	var shots := [
		["chest_sleeves", up, "UpperChest", Vector3(-0.08, 0.32, 0.55), Vector3(0, -0.12, 0), 50.0],
		["side", up, "UpperChest", Vector3(-0.95, 0.12, 0.12), Vector3(0, 0.06, 0), 42.0],
		["folded_arm", fold, "RightLowerArm", Vector3(0.18, 0.05, 0.42), Vector3(-0.08, 0, 0), 50.0],
		["front", up, "Chest", Vector3(0, 0.05, 1.45), Vector3(0, 0.02, 0), 40.0],
		["back_neck", up, "Neck", Vector3(-0.04, 0.20, -0.30), Vector3(0, -0.06, 0), 50.0, true],   # hair hidden: his shot clipped through it
		["medium", up, "Hips", Vector3(0.9, 0.35, 2.6), Vector3(0, 0.15, 0), 40.0],
	]
	var hide := ShaderMaterial.new()
	hide.shader = Shader.new()
	hide.shader.code = "shader_type spatial;\nvoid fragment() { discard; }"
	var hair := _outfit_surfaces(mika, true)
	for sh in shots:
		var no_hair: bool = sh.size() > 6 and sh[6]
		for s in hair:
			(s[0] as MeshInstance3D).set_surface_override_material(s[1], hide if no_hair else s[2])
		arms.aims = sh[1]
		await _wait(1.2)
		var r := ArmPose._right(sk)
		var f := Vector3.UP.cross(r)
		var c := _bone(sk, sh[2])
		var co: Vector3 = sh[3]
		var lo: Vector3 = sh[4]
		cam.global_position = c + r * co.x + Vector3.UP * co.y + f * co.z
		cam.look_at(c + r * lo.x + Vector3.UP * lo.y + f * lo.z)
		cam.fov = sh[5]
		await _wait(0.5)
		for i in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, sh[0]])
		print("[l1] shot ", sh[0])
	arms.queue_free()
