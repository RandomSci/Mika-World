## QA: every avatar surface's shader, transparency and outline settings (both girls).
static func run(t) -> void:
	await t._hold_all()
	await t._force_luna_l1()
	for id in ["luna", "mika"]:
		var c: WorldCharacter = t.main.characters[id]
		for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var mat := m.get_active_material(si)
				var line := "%s %s[%d]" % [id, m.name, si]
				var depth := 0
				while mat and depth < 3:
					if mat is ShaderMaterial:
						var sm := mat as ShaderMaterial
						var sh := String(sm.shader.resource_path).get_file() if sm.shader else "?"
						line += " | %s cut=%s ow=%s owm=%s" % [sh, str(sm.get_shader_parameter("_AlphaCutoutEnable")), str(sm.get_shader_parameter("_OutlineWidth")), str(sm.get_shader_parameter("_OutlineWidthMode"))]
					elif mat is BaseMaterial3D:
						line += " | Std transp=%d" % (mat as BaseMaterial3D).transparency
					mat = mat.next_pass
					depth += 1
				print("[mat] " + line)
