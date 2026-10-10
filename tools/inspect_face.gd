extends SceneTree
func _init():
	var root: Node = load("res://assets/characters/mika/Mika.vrm").instantiate()
	for mn in ["Face", "Body"]:
		var mi: MeshInstance3D = root.find_child(mn, true, false)
		for s in mi.mesh.get_surface_count():
			var m = mi.get_active_material(s)
			if not (m is ShaderMaterial): continue
			var name := String(m.resource_name)
			if not name.contains("SKIN"): continue
			print("== ", mn, "[", s, "] ", name, " shader=", m.shader.resource_path.get_file(), " next_pass=", m.next_pass, " prio=", m.render_priority)
			for mat in [m, m.next_pass]:
				if mat == null: continue
				print("   -- ", mat.resource_name, " shader=", mat.shader.resource_path.get_file(), " prio=", mat.render_priority)
				for p in mat.shader.get_shader_uniform_list():
					if not (p.name in ["_ShadeColor", "_ShadeShift", "_ShadeToony", "_IndirectLightIntensity", "_LightColorAttenuation", "_OutlineWidthMode", "_OutlineWidth", "_OutlineScaledMaxDistance", "_OutlineColorMode", "_OutlineColor", "_OutlineLightingMix", "_OutlineWidthTexture", "_ReceiveShadowRate", "_ShadingGradeRate", "_RimColor", "_RimLift", "_MatcapColor"]): continue
					var v = mat.get_shader_parameter(p.name)
					if v is Texture2D: v = "tex:" + str(v.get_size())
					print("        ", p.name, " = ", v)
	root.free()
	quit()
