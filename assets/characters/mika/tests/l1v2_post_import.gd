@tool
extends EditorScenePostImport
## Mika L1 outfit v2 test build only (Selwyn 2026-10-20: "compress all 7 textures, VRAM compressed, high quality,
## mipmaps on"). The VRM importer embeds every texture uncompressed and without mipmaps; this post import script, set
## on MikaCelestial_L1v2.vrm alone, points the v2 outfit materials at the same bakes imported from l1v2_tex/ as BPTC
## with mipmaps. Nothing else uses it.

const TEX := "res://assets/characters/mika/tests/l1v2_tex/"
## single sided layers (outside, lining) share the trim sheet and the pattern
const SAME := {"L1_v2_PatternOut": "L1_v2_Pattern", "L1_v2_TrimOut": "L1_v2_Trim", "L1_v2_Lining": "L1_v2_Trim"}


func _post_import(scene: Node) -> Object:
	var n := 0
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(si)
			while mat is ShaderMaterial:
				var nm := String(mat.resource_name)
				if nm.begins_with("L1_v2_"):
					var piece := nm.replace("_MToon", "").replace("_Outline", "")
					var p := TEX + String(SAME.get(piece, piece)) + "_BaseColor.png"
					if ResourceLoader.exists(p):
						var t: Texture2D = load(p)
						for k in ["_MainTex", "_ShadeTexture"]:
							if mat.get_shader_parameter(k) != null:
								mat.set_shader_parameter(k, t)
						n += 1
				mat = mat.next_pass
	print("[l1v2] post import: %d outfit materials on the compressed textures" % n)
	return scene
