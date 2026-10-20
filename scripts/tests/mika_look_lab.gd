extends "res://scripts/tests/mika_l1_closeup_lab.gd"
## MIKA LOOK LAB (Selwyn 2026-10-20: "as close as possible to Genshin and Wuthering Waves character rendering, technique
## only, never their assets"). Test only, own files, nothing shared changes, Mika only, no world loaded. The close-up
## lab's scene, poses and shots, under one of four lights, in the current look or the prototype:
##   godot --path . res://scenes/tests/mika_look_lab.tscn -- --save-path=user://test_regress_l1lab.json
##     --live-link=ws://127.0.0.1:9/test-none --no-bridge --l1out=<abs dir> --light=day|dusk|night|forest
##     [--look=proto] [--maps=<abs dir>] [--l1tex=<abs dir of the flat outfit textures>] [--avatar=<res:// vrm>]
##     [--texcheck] [--trimshots]
## --texcheck: every L1_v2 outfit texture as the GPU gets it (decompressed) against its source png in l1v2_tex,
## texels off by more than 24 and 48 of 255. --trimshots: four tight trim close-ups after the six shots.
## --avatar puts a test build in her place (Mika L1 outfit v2: res://assets/characters/mika/tests/MikaCelestial_L1v2.vrm
## with --maps and --l1tex from Mika-Transformation-Lab/l1_v2/look); without it she wears the current L1 stage.
## The prototype (shaders/tests/look/):
##   1 look_toon on body and outfit: ramp rows per material, a lightmap per outfit piece (shadow threshold, metal and
##     gem specular, material id) built from the cleaned flat textures;
##   2 look_face: the face's shadow from a drawn face shadow map that sweeps with the light;
##   3 look_hair: the toon ramp plus a controlled angel ring in head space;
##   4 look_outline on body, outfit and hair (smoothed normals baked into TANGENT), a thin rim on everything;
##   5 the character light rig (LookRig below): her key, ambient and rim come from presets per light, derived from the
##     world's sun or moon but with the height clamped and her own exposure, not from the world's lights.
## Plus the kept dress-test kit: MSAA 4x, no PBR maps.

const LOOK := "res://shaders/tests/look/"
const LAB := "/home/selwyn/Downloads/Mika-Transformation-Lab"

# world: sun or moon [elevation, azimuth, colour, energy], sky energy, ambient energy, fog
# rig: key colour, key energy (above 1: these materials are unshaded but still go through the AgX tonemap, which
# compresses them), ambient colour, rim colour, rim strength, night ramp rows
const LIGHTS := {
	"day": {"sun": [34.0, 150.0, Color(1, 0.9, 0.74), 3.1], "sky": 1.0, "amb": 0.34, "fog": 0.0,
		"key": Color(1.0, 0.96, 0.9), "energy": 1.3, "ambient": Color(0.34, 0.36, 0.44), "rim": Color(1.0, 0.96, 0.92), "rim_k": 0.22, "night": 0.0},
	"dusk": {"sun": [7.0, 115.0, Color(1.0, 0.56, 0.32), 2.2], "sky": 0.45, "amb": 0.22, "fog": 0.006,
		"key": Color(1.0, 0.76, 0.58), "energy": 1.2, "ambient": Color(0.30, 0.25, 0.38), "rim": Color(1.0, 0.62, 0.42), "rim_k": 0.45, "night": 0.0},
	"night": {"sun": [42.0, 200.0, Color(0.55, 0.66, 1.0), 0.45], "sky": 0.07, "amb": 0.12, "fog": 0.004,
		"key": Color(0.74, 0.82, 1.0), "energy": 0.95, "ambient": Color(0.18, 0.2, 0.33), "rim": Color(0.62, 0.78, 1.0), "rim_k": 0.55, "night": 1.0},
	"forest": {"sun": [55.0, 170.0, Color(0.8, 0.95, 0.68), 0.9], "sky": 0.3, "amb": 0.2, "fog": 0.02,
		"key": Color(0.94, 1.0, 0.88), "energy": 1.15, "ambient": Color(0.22, 0.3, 0.25), "rim": Color(0.86, 1.0, 0.8), "rim_k": 0.35, "night": 0.0},
}


func _run() -> void:
	var lt: Dictionary = LIGHTS[String(o.get("light", "day"))]
	_world_light(lt)
	var st: Dictionary = AppearanceRegistry.stage_by_id("mika", "celestial_l1outfit")
	var mika := WorldCharacter.new()
	mika.name = "Mika"
	mika.character_id = "mika"
	mika.display_name = "Mika"
	mika.avatar_path = String(o.get("avatar", st.avatar))
	add_child(mika)
	mika.global_position = Vector3.ZERO
	mika.apply_light_balance(sun.light_energy, env.ambient_light_energy)
	await _wait(2.0)
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	vp.msaa_3d = Viewport.MSAA_2X                                  # the stream's
	vp.use_taa = false
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
	if String(o.get("look", "")) == "proto":
		vp.msaa_3d = Viewport.MSAA_4X
		vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
		_proto(mika, lt)
	print("[look] light=%s look=%s" % [String(o.get("light", "day")), String(o.get("look", "current"))])
	if o.has("texcheck"):
		_texcheck(mika)
	if o.has("facesweep"):
		await _face_sweep(mika)
	else:
		await _shots(mika)
	print("[l1] DONE")
	get_tree().quit()


## --facesweep: face close-ups with her key light swung 0, 45 and 90 degrees to her right (the rig's yaw override; the
## world's sun turns too, so the current look sees the same light).
func _face_sweep(mika: WorldCharacter) -> void:
	var sk := mika.skeleton
	var right := LookRig._right(sk)
	var fwd := Vector3.UP.cross(right)
	var head := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin + Vector3.UP * 0.07
	cam.global_position = head + fwd * 0.75 - Vector3.UP * 0.04
	cam.look_at(head - Vector3.UP * 0.05)
	cam.fov = 30.0
	for deg in [0, 45, 90]:
		var a := deg_to_rad(float(deg))
		var to_light := (fwd * cos(a) + right * sin(a)) * cos(deg_to_rad(30.0)) + Vector3.UP * sin(deg_to_rad(30.0))
		sun.look_at(sun.global_position - to_light, Vector3.UP)
		var rh := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand"))).origin - head
		var cam_side := cam.global_transform.basis.x                         # the image's right
		print("[look] sweep %d: right=%s fwd=%s to_light=%s right hand along right=%.2f, light toward image right=%.2f, camera faces her=%.2f" % [deg, right, fwd, to_light, rh.dot(right), to_light.dot(cam_side), (-cam.global_transform.basis.z).dot(-fwd)])
		await _wait(0.6)
		for i in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/face_%03d.png" % [out, deg])
		print("[l1] shot face_%03d" % deg)


func _world_light(lt: Dictionary) -> void:
	var s: Array = lt.sun
	sun.rotation_degrees = Vector3(-float(s[0]), float(s[1]), 0)
	sun.light_color = s[2]
	sun.light_energy = float(s[3])
	(env.sky.sky_material as PanoramaSkyMaterial).energy_multiplier = float(lt.sky)
	env.ambient_light_energy = float(lt.amb)
	if float(lt.fog) > 0.0:
		env.fog_enabled = true
		env.fog_density = float(lt.fog)
		env.fog_light_color = Color(0.45, 0.5, 0.6) if lt.night > 0.5 else (Color(0.5, 0.62, 0.48) if lt.fog > 0.01 else Color(0.8, 0.6, 0.55))
		env.fog_light_energy = float(lt.sky)


func _tex(path: String, mips := true) -> ImageTexture:
	var img := Image.load_from_file(path)
	if img == null:
		push_error("[look] no image " + path)
		return null
	if mips:
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Smoothed normals (welded by position) into TANGENT, for an outline hull that doesn't split at hard edges.
func _smooth_normals(m: MeshInstance3D) -> void:
	var old := m.mesh as ArrayMesh
	if old == null:
		return
	var keep := []
	for si in old.get_surface_count():
		keep.append(m.get_surface_override_material(si))
	var nm := ArrayMesh.new()
	nm.blend_shape_mode = old.blend_shape_mode
	for b in old.get_blend_shape_count():
		nm.add_blend_shape(old.get_blend_shape_name(b))
	for si in old.get_surface_count():
		var arr := old.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var acc := {}
		for i in verts.size():
			var k := Vector3i(roundi(verts[i].x * 2e4), roundi(verts[i].y * 2e4), roundi(verts[i].z * 2e4))
			acc[k] = acc.get(k, Vector3.ZERO) + norms[i]
		var tan := PackedFloat32Array()
		tan.resize(verts.size() * 4)
		for i in verts.size():
			var k := Vector3i(roundi(verts[i].x * 2e4), roundi(verts[i].y * 2e4), roundi(verts[i].z * 2e4))
			var n: Vector3 = (acc[k] as Vector3).normalized()
			tan[i * 4] = n.x; tan[i * 4 + 1] = n.y; tan[i * 4 + 2] = n.z; tan[i * 4 + 3] = 1.0
		arr[Mesh.ARRAY_TANGENT] = tan
		var flags := old.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		nm.add_surface_from_arrays(old.surface_get_primitive_type(si), arr, old.surface_get_blend_shape_arrays(si), {}, flags)
		nm.surface_set_material(si, old.surface_get_material(si))
		nm.surface_set_name(si, old.surface_get_name(si))
	m.mesh = nm
	for si in keep.size():
		m.set_surface_override_material(si, keep[si])


func _proto(mika: WorldCharacter, lt: Dictionary) -> void:
	var maps := String(o.get("maps", LAB + "/look_proto/maps"))
	var flat := String(o.get("l1tex", LAB + "/l1_flat/flat"))
	var ramp := _tex(maps + "/ramp.png", false)
	var sdf := _tex(maps + "/face_sdf.png", false)
	var toon: Shader = load(LOOK + "look_toon.gdshader")
	var face_sh: Shader = load(LOOK + "look_face.gdshader")
	var hair_sh: Shader = load(LOOK + "look_hair.gdshader")
	var line_sh: Shader = load(LOOK + "look_outline.gdshader")
	var toon_one := Shader.new()                                   # one sided toon for the layered cloth (v2 outfit)
	toon_one.code = toon.code.replace("cull_disabled", "cull_back")
	const ONE_SIDED := ["L1_v2_PatternOut", "L1_v2_TrimOut", "L1_v2_Lining"]
	var rig := LookRig.new()
	rig.c = mika
	rig.lt = lt
	rig.sun = sun
	var n := {"outfit": 0, "body": 0, "hair": 0, "face": 0}
	for mi in mika.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var kinds := []
		for si in m.mesh.get_surface_count():
			kinds.append(_kind(m.get_active_material(si)))
		if kinds.has("outfit") or kinds.has("body") or kinds.has("hair"):
			_smooth_normals(m)
		for si in m.mesh.get_surface_count():
			var old := m.get_active_material(si) as ShaderMaterial
			var kind := String(kinds[si])
			if kind == "":
				continue
			var nmat := ShaderMaterial.new()
			nmat.resource_name = old.resource_name
			nmat.set_shader_parameter("ramp_tex", ramp)
			var base: Texture2D = old.get_shader_parameter("_MainTex")
			var tint: Color = old.get_shader_parameter("_Color") if old.get_shader_parameter("_Color") != null else Color.WHITE
			match kind:
				"outfit":
					var piece := String(old.resource_name).replace("_MToon", "")
					nmat.shader = toon_one if piece in ONE_SIDED else toon
					var fp := "%s/%s_BaseColor.png" % [flat, piece]
					var ft := _tex(fp) if FileAccess.file_exists(fp) else null   # else the build's own (v2: VRAM compressed)
					base = ft if ft else base
					var ilm := _tex("%s/%s_ILM.png" % [maps, piece])
					if ilm:
						nmat.set_shader_parameter("ilm_tex", ilm)
						nmat.set_shader_parameter("use_ilm", true)
				"body":
					nmat.shader = toon
					nmat.set_shader_parameter("ramp_row", 0.0)
					nmat.set_shader_parameter("tint", tint)
				"hair":
					nmat.shader = hair_sh
					nmat.set_shader_parameter("tint", tint)
				"face":
					nmat.shader = face_sh
					nmat.set_shader_parameter("sdf_tex", sdf)
					nmat.set_shader_parameter("tint", tint)
			nmat.set_shader_parameter("base_tex", base)
			if kind == "face":
				nmat.next_pass = old.next_pass                  # her own outline, as it is
			elif String(old.resource_name).begins_with("L1_v2_Lining"):
				pass                                            # no outline hull inside a sleeve or behind a panel
			else:
				var line := ShaderMaterial.new()
				line.shader = line_sh
				line.set_shader_parameter("base_tex", base)
				nmat.next_pass = line
			m.set_surface_override_material(si, nmat)
			rig.mats.append(nmat)
			n[kind] += 1
	add_child(rig)
	print("[look] prototype materials ", n)


func _kind(mat: Material) -> String:
	var nm := String(mat.resource_name) if mat else ""
	if not (mat is ShaderMaterial):
		return ""
	if nm.begins_with("L1_Hair_"):
		return "hair"
	if nm.begins_with("L1_"):
		return "outfit"
	if nm.ends_with("_Body_00_SKIN"):
		return "body"
	if nm.ends_with("_Face_00_SKIN"):
		return "face"
	return ""


## The character light rig: every frame her key, ambient and rim, from the preset and the world's sun or moon
## direction with its height clamped to 18-48 degrees (a low sun still lights her face, a high one doesn't flatten it).
class LookRig extends Node:
	var c: WorldCharacter
	var lt: Dictionary
	var sun: DirectionalLight3D
	var mats := []

	func _init() -> void:
		process_priority = (1 << 30) - 2

	func _process(_d: float) -> void:
		var to_light := sun.global_transform.basis.z.normalized()
		var flat := Vector3(to_light.x, 0, to_light.z).normalized()
		var el := clampf(asin(clampf(to_light.y, -1, 1)), deg_to_rad(18), deg_to_rad(48))
		var key := (flat * cos(el) + Vector3.UP * sin(el)).normalized()
		var sk := c.skeleton
		var right := _right(sk)
		var fwd := Vector3.UP.cross(right)
		var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))
		var hb := Basis(-right, Vector3.UP, fwd).orthonormalized()   # x = her left, y up, z forward
		var head_inv := Projection(Transform3D(hb, head.origin).affine_inverse())
		for m in mats:
			var sm := m as ShaderMaterial
			sm.set_shader_parameter("key_dir", key)
			sm.set_shader_parameter("key_color", lt.key)
			sm.set_shader_parameter("key_energy", lt.energy)
			sm.set_shader_parameter("ambient_color", lt.ambient)
			sm.set_shader_parameter("rim_color", lt.rim)
			sm.set_shader_parameter("rim_strength", lt.rim_k)
			sm.set_shader_parameter("night", lt.night)
			sm.set_shader_parameter("head_fwd", fwd)
			sm.set_shader_parameter("head_right", right)
			sm.set_shader_parameter("head_inv", head_inv)

	static func _right(sk: Skeleton3D) -> Vector3:
		var ls := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftUpperArm"))).origin
		var rs := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperArm"))).origin
		return Vector3(rs.x - ls.x, 0, rs.z - ls.z).normalized()


## The v2 test build's outfit textures as Godot holds them (VRAM compressed) against the source pngs.
func _texcheck(mika: WorldCharacter) -> void:
	var seen := {}
	for mi in mika.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in (m.mesh.get_surface_count() if m.mesh else 0):
			var mat := m.mesh.surface_get_material(si) as ShaderMaterial
			if mat == null or not String(mat.resource_name).begins_with("L1_v2_"):
				continue
			var nm := String(mat.resource_name).replace("_MToon", "")
			if seen.has(nm):
				continue
			seen[nm] = true
			var t: Texture2D = mat.get_shader_parameter("_MainTex")
			var img := t.get_image() if t else null
			var src := Image.load_from_file("res://assets/characters/mika/tests/l1v2_tex/%s_BaseColor.png" % nm)
			if img == null or src == null:
				print("[texcheck] %s missing" % nm)
				continue
			var fmt := img.get_format()
			var mips := img.has_mipmaps()
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			if img.has_mipmaps():
				img.clear_mipmaps()
			img.convert(Image.FORMAT_RGB8)
			src.convert(Image.FORMAT_RGB8)
			var a := img.get_data()
			var b := src.get_data()
			var n24 := 0
			var n48 := 0
			var worst := 0
			var step := 3 * 7                                          # every 7th texel, enough for a share
			var i := 0
			var tot := 0
			while i + 2 < mini(a.size(), b.size()):
				var d := maxi(maxi(absi(a[i] - b[i]), absi(a[i + 1] - b[i + 1])), absi(a[i + 2] - b[i + 2]))
				worst = maxi(worst, d)
				if d > 24: n24 += 1
				if d > 48: n48 += 1
				tot += 1
				i += step
			print("[texcheck] %s %dx%d format=%d mipmaps=%s off>24 %.3f%% off>48 %.3f%% worst %d" % [nm, t.get_width(), t.get_height(), fmt, str(mips), 100.0 * n24 / tot, 100.0 * n48 / tot, worst])
