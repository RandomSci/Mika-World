class_name FaceStyle
extends RefCounted
## Day 3: a character's reworked face (Luna: big round eyes, gradient golden irises with sparkle and three
## catchlights, thicker darker lashes, fuller soft brows, a small soft glossy pink mouth, a soft blush). The textures
## were painted from the avatar's own (tools/face_style/make_luna_face.py) and are swapped into its face materials
## when the avatar loads. The VRM files are never modified; a missing texture keeps the original.

## material name suffix -> [texture file, {shader parameter: value}]
const PARTS := {
	"_EyeIris_00_EYE": ["Luna_EyeIris_00_EYE.png", {}],
	"_EyeHighlight_00_EYE": ["Luna_EyeHighlight_00_EYE.png", {}],
	"_FaceEyelash_00_FACE": ["Luna_FaceEyelash_00_FACE.png", {"_Color": Color(1, 1, 1, 1), "_ShadeColor": Color(0.85, 0.8, 0.8, 1)}],
	"_FaceEyeline_00_FACE": ["Luna_FaceEyeline_00_FACE.png", {"_Color": Color(1, 1, 1, 1), "_ShadeColor": Color(0.85, 0.8, 0.8, 1)}],
	"_FaceBrow_00_FACE": ["Luna_FaceBrow_00_FACE.png", {"_Color": Color(1, 1, 1, 1), "_ShadeColor": Color(0.82, 0.76, 0.74, 1)}],
	"_Face_00_SKIN": ["Luna_Face_00_SKIN.png", {}],
}


## Returns how many face materials took the style (0 when `dir` is empty or nothing matched).
static func apply(avatar: Node, dir: String) -> int:
	if dir.is_empty() or avatar == null:
		return 0
	var n := 0
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si) as ShaderMaterial
			if mat == null:
				continue
			var rn := String(mat.resource_name)
			for suffix in PARTS:
				if not rn.ends_with(suffix):
					continue
				var path := dir.path_join(String(PARTS[suffix][0]))
				if not ResourceLoader.exists(path):
					continue
				var old = mat.get_shader_parameter("_MainTex")
				var tex: Texture2D = load(path)
				if old is Texture2D and (old.get_width() != tex.get_width() or old.get_height() != tex.get_height()):
					push_warning("FaceStyle: %s is %dx%d, the model's is %dx%d; kept the original" % [path, tex.get_width(), tex.get_height(), old.get_width(), old.get_height()])
					continue
				mat.set_shader_parameter("_MainTex", tex)
				var params: Dictionary = PARTS[suffix][1]
				for p in params:
					mat.set_shader_parameter(p, params[p])
				n += 1
	return n
